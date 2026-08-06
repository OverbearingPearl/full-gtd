;;; pearl-gtd-core.el --- Core infrastructure for pearl-gtd  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 OverbearingPearl
;; Author: OverbearingPearl <OverbearingPearl@outlook.com>
;; Assisted-by: Kimi:kimi-k2.5, DeepSeek:deepseek-v3.2, Claude:claude-sonnet-4.6
;; URL: https://github.com/OverbearingPearl/pearl-gtd
;; SPDX-License-Identifier: MIT

;;; Commentary:

;; Core infrastructure and thin delegation layer.
;; Predicates, filters, and data collection utilities.
;; File operation macros delegate to pearl-gtd-state.
;; Data normalization functions delegate to pearl-gtd-domain.

;;; Code:

(require 'org)
(require 'crm)  ;; completing-read-multiple
(require 'pearl-gtd-init)
(require 'pearl-gtd-domain)
(require 'pearl-gtd-state)

;;;; Predicates

(defun pearl-gtd-core-entry-todo-p ()
  "Return non-nil if current entry is a TODO item."
  (let ((state (org-get-todo-state)))
    (member state org-not-done-keywords)))

(defun pearl-gtd-core-entry-done-p ()
  "Return non-nil if current entry is a DONE item."
  (member (org-get-todo-state) org-done-keywords))

(defun pearl-gtd-core-entry-context-p (contexts)
  "Return non-nil if current entry has any of CONTEXTS.
CONTEXTS is a list of normalized context strings (without @ prefix)."
  (when contexts
    (let ((tags (org-get-tags)))
      (cl-intersection tags contexts :test #'string=))))

(defun pearl-gtd-core-entry-scheduled-today-p ()
  "Return non-nil if current entry is scheduled for today."
  (let* ((scheduled (org-entry-get nil "SCHEDULED"))
         (ct (current-time))
         (today-pattern (format-time-string "<%F" ct)))
    (and scheduled
         (string-match-p today-pattern scheduled))))

(defun pearl-gtd-core-entry-completed-today-p ()
  "Return non-nil if current entry was closed today."
  (let* ((closed (org-entry-get nil "CLOSED")))
    (and closed
         (string-match-p (format-time-string "\\[%F" (current-time)) closed))))

(defun pearl-gtd-core-entry-delegated-p ()
  "Return non-nil if current entry is delegated."
  (org-entry-get nil "DELEGATED"))

(defun pearl-gtd-core-entry-overdue-p ()
  "Return non-nil if current entry is overdue."
  (let ((scheduled (org-entry-get nil "SCHEDULED")))
    (and scheduled (time-less-p (org-time-string-to-time scheduled) (current-time)))))

;;;; Filters

(defun pearl-gtd-core-filter-entries (file-path predicates)
  "Filter entries in FILE-PATH using PREDICATES.
PREDICATES is a list of predicate functions to apply.
Each predicate is called with no arguments in the context of the entry.
Return list of entries that pass all predicates.
Entries are lists:
\(HEADLINE TAGS-STRING TODO-STATE SCHEDULED DELEGATED PROJECT CREATED
  ID FILE DEADLINE CONTEXT L3_AREA L4_GOAL L5_VISION L6_PURPOSE).
Nil values indicate unset properties."
  (let ((entries '())
        (file-name (file-name-nondirectory file-path)))
    (when (file-exists-p file-path)
      (with-temp-buffer
        (insert-file-contents file-path)
        (org-mode)
        (org-map-entries
         (lambda ()
           (when (cl-every (lambda (pred) (funcall pred)) predicates)
             (let* ((head (org-get-heading t t))
                    (id (org-entry-get nil "ID"))
                    (tags (org-get-tags))
                    (todo-state (org-get-todo-state))
                    (scheduled (org-entry-get nil "SCHEDULED"))
                    (deadline (org-entry-get nil "DEADLINE"))
                    (delegated (org-entry-get nil "DELEGATED"))
                    (project (org-entry-get nil "PROJECT"))
                    (created (org-entry-get nil "CREATED"))
                    (context (mapconcat (lambda (c) (concat "@" c)) tags ","))
                    (l3 (org-entry-get nil "L3_AREA"))
                    (l4 (org-entry-get nil "L4_GOAL"))
                    (l5 (org-entry-get nil "L5_VISION"))
                    (l6 (org-entry-get nil "L6_PURPOSE")))
               (when id
                 (put-text-property 0 (length head) 'pearl-gtd-id id head))
               (push (list head
                           (mapconcat (lambda (c) (concat "@" c)) tags ",")
                           todo-state
                           scheduled
                           delegated
                           project
                           created
                           id
                           file-name
                           deadline
                           context
                           l3
                           l4
                           l5
                           l6)
                     entries))))
         nil nil)))
    (nreverse entries)))

;;;; Data Collection

(defun pearl-gtd-core-collect-contexts (file-path)
  "Collect all unique context tags from FILE-PATH."
  (let ((contexts '()))
    (when (file-exists-p file-path)
      (with-temp-buffer
        (insert-file-contents file-path)
        (org-mode)
        (org-map-entries
         (lambda ()
           (when (string= (org-get-todo-state) "TODO")
             (dolist (tag (org-get-tags))
               (cl-pushnew tag contexts :test #'string=))))
         nil nil)))
    (mapcar (lambda (c) (concat "@" c)) contexts)))

;;;; Table rendering core

;;;; Macro for table navigation

(defmacro pearl-gtd-core-define-table-navigators (prefix boundaries-func &optional header-regexp)
  "Define table navigation functions for PREFIX using BOUNDARIES-FUNC.
Creates PREFIX--next-row and PREFIX--previous-row interactive functions.
BOUNDARIES-FUNC should return (first-row-pos . last-row-pos).
HEADER-REGEXP matches header lines to skip (default: \"| Headline\")."
  (let ((next-fn (intern (concat prefix "--next-row")))
        (prev-fn (intern (concat prefix "--previous-row")))
        (skip-fn (intern (concat prefix "--skip-line-p")))
        (header-re (or header-regexp "| Headline")))
    `(progn
       (defun ,skip-fn ()
         "Return non-nil if current line should be skipped during navigation."
         (or (looking-at "|[-+]")
             (looking-at ,header-re)
             (not (looking-at "|"))))

       (defun ,next-fn ()
         "Move to next data row in the table."
         (interactive)
         (let* ((boundaries (funcall ,boundaries-func))
                (last-data-row (cdr boundaries)))
           (if (>= (line-beginning-position) last-data-row)
               (beep)
             (forward-line 1)
             (while (and (not (eobp)) (,skip-fn))
               (forward-line 1))
             (org-table-goto-column 1))))

       (defun ,prev-fn ()
         "Move to previous data row in the table."
         (interactive)
         (let* ((boundaries (funcall ,boundaries-func))
                (first-data-row (car boundaries)))
           (if (<= (line-beginning-position) first-data-row)
               (beep)
             (forward-line -1)
             (while (and (not (bobp)) (,skip-fn))
               (forward-line -1))
             (org-table-goto-column 1)))))))

;;;; Macros for file operations

(defmacro pearl-gtd-core-with-file-buffer (file-path &rest body)
  "Execute BODY in buffer of FILE-PATH.
Delegate to state layer for transactional file operations."
  (declare (indent 1))
  `(pearl-gtd-state--with-file-buffer ,file-path ,@body))

(defmacro pearl-gtd-core-with-entry-at-id (id file &rest body)
  "Execute BODY with point at entry ID in FILE.
Delegate to state layer for transactional file operations."
  (declare (indent 2))
  `(pearl-gtd-state--with-entry-at-id ,id ,file ,@body))

(defun pearl-gtd-core-read-date (prompt-type)
  "Hybrid date input for PROMPT-TYPE: letter=quick, number=free-form, RET=skip.
PROMPT-TYPE is \\='schedule or \\='deadline for display.
Quick keys: t (today), T (tomorrow), w (week), h (hour, schedule only).
Returns date string or nil if skipped.
Signals \\='quit if user presses \\`C-g\\'."
  (catch 'done
    (let (result)
      (while (not result)
        (if (eq prompt-type 'schedule)
            (message "[Schedule] Quick: [t]oday, [T]omorrow, [w]eek, [h]our | Custom: <YYYY-MM-DD> or <YYYY-MM-DD HH:MM> | [RET] Skip: ")
          (message "[Deadline] Quick: [t]oday, [T]omorrow, [w]eek | Custom: <YYYY-MM-DD> | [RET] Skip: "))
        (let ((key (read-key)))
          (cond
           ((eq key ?t) (setq result (format-time-string "%F")))
           ((eq key ?T) (setq result (format-time-string "%F" (time-add (current-time) (* 24 3600)))))
           ((eq key ?w) (setq result (format-time-string "%F" (time-add (current-time) (* 7 24 3600)))))
           ((and (eq prompt-type 'schedule) (eq key ?h))
            (setq result (format-time-string "%F %R" (time-add (current-time) 3600))))
           ((eq key ?\r) (throw 'done nil))
           ((and (>= key ?0) (<= key ?9))
            (condition-case nil
                (let ((full (minibuffer-with-setup-hook
                                (lambda () (select-window (minibuffer-window)))
                              (read-string (format "%s (e.g., 2023-12-25 or 2023-12-25 14:30): " prompt-type)
                                           (string key) nil nil))))
                  (if (string-match-p "^[0-9]\\{4\\}-[0-9]\\{2\\}-[0-9]\\{2\\}\\(?: [0-2][0-9]:[0-5][0-9]\\)?$" full)
                      (setq result full)
                    (message "Invalid date, retry") (sit-for 0.5)))
              (quit (signal 'quit nil))))
           ((eq key 7)
            (signal 'quit nil))
           (t (message "Invalid key") (sit-for 0.5)))))
      result)))

(defun pearl-gtd-core--split-values (value-string)
  "Split VALUE-STRING using semicolon separator.
Supports both English (;) and Chinese (；) semicolons.
Trim whitespace from each value. Filter empty values.
Example: \"Project A; Project B；Project C\"
  -> (\"Project A\" \"Project B\" \"Project C\")
Delegate to domain layer for pure computation."
  (pearl-gtd-domain--split-values value-string))

(defun pearl-gtd-core--join-values (values)
  "Join VALUES list using English semicolon separator.
Always uses English semicolon for storage consistency.
Example: (\"Project A\" \"Project B\") -> \"Project A; Project B\"
Delegate to domain layer for pure computation."
  (pearl-gtd-domain--join-values values))

(defun pearl-gtd-core--normalize-project-input (input)
  "Normalize project input: convert Chinese semicolons to English.
Trim whitespace from each value. Returns nil if empty.
INPUT is the input string to normalize.
Example: \"Project A；Project B；Project C\"
  -> \"Project A; Project B; Project C\"
Delegate to domain layer for pure computation."
  (pearl-gtd-domain--normalize-project-input input))

(defun pearl-gtd-core--escape-table-field (field)
  "Escape pipe characters in FIELD for org-table display."
  (replace-regexp-in-string "|" "\\\\vert{}" field))

;;;; Unified property reading with completion

(defun pearl-gtd-core-read-property-with-completion (prompt property-type &optional initial)
  "Read property value with completion.
PROMPT is the prompt string displayed to the user.
PROPERTY-TYPE: context/project/delegate/l3/l4/l5/l6/principle.
INITIAL is the optional initial value string.
Project and horizons (L3-L6) support multiple values separated by semicolon."
  (let* ((candidates (pcase property-type
                       ('context (pearl-gtd-domain--collect-context-candidates))
                       ('project (pearl-gtd-domain--collect-project-candidates))
                       ('delegate (pearl-gtd-domain--collect-delegate-candidates))
                       ('l3 (pearl-gtd-domain--collect-horizon-candidates "L3_AREA"))
                       ('l4 (pearl-gtd-domain--collect-horizon-candidates "L4_GOAL"))
                       ('l5 (pearl-gtd-domain--collect-horizon-candidates "L5_VISION"))
                       ('l6 (pearl-gtd-domain--collect-horizon-candidates "L6_PURPOSE"))
                       ('principle (pearl-gtd-domain--collect-horizon-candidates "L6_PRINCIPLE"))
                       (_ (error "Unknown property type: %s" property-type))))
         (is-multi-value (member property-type '(project l3 l4 l5 l6 principle))))

    (if is-multi-value
        (let* ((crm-separator "[;；]\\s-*")
               (initial-input
                (when initial
                  (pearl-gtd-domain--join-values
                   (pearl-gtd-domain--split-values initial))))
               (values (completing-read-multiple prompt candidates nil nil initial-input)))
          (if values
              (pearl-gtd-domain--join-values values)
            ""))
      (string-trim (completing-read prompt candidates nil nil initial)))))

(provide 'pearl-gtd-core)

;;; pearl-gtd-core.el ends here
