;;; pearl-gtd-inbox.el --- Inbox handling for pearl-gtd  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 OverbearingPearl
;; Author: OverbearingPearl <OverbearingPearl@outlook.com>
;; Assisted-by: Kimi:kimi-k2.5, DeepSeek:deepseek-v3.2, Claude:claude-sonnet-4.6
;; URL: https://github.com/OverbearingPearl/pearl-gtd
;; License: MIT
;; SPDX-License-Identifier: MIT

;;; Commentary:

;; This file handles inbox-related functions for pearl-gtd,
;; including capture and processing with user interaction via staging,
;; fully aligned with GTD workflow.

;;; Code:

(require 'cl-lib)
(require 'org)
(require 'org-id)
(require 'pearl-gtd-core)
(require 'pearl-gtd-review)

(defface pearl-gtd-inbox--highlight
  '((t :inherit highlight))
  "Face for highlighting the current entry."
  :group 'pearl-gtd)

(defface pearl-gtd-inbox--deleted
  '((t :inherit shadow :strike-through t))
  "Face for deleted (trash) entries."
  :group 'pearl-gtd)

(defface pearl-gtd-inbox--executed
  '((t :inherit success :strike-through t))
  "Face for executed (2-minute rule) entries."
  :group 'pearl-gtd)

(defvar pearl-gtd-inbox--current-test-name nil
  "Current running test name for debugging.")

(defvar pearl-gtd-inbox--staging-original-file nil
  "The original Org file path for the staging buffer.")

(defvar pearl-gtd-inbox--staging-changes nil
  "A list to store staged changes, e.g., ((row col new-value) ...).")

(defvar pearl-gtd-inbox--current-prompt-type nil
  "Current prompt type.
Possible values include \\='rename, \\='remarks, \\='context,
\\='schedule, \\='deadline, \\='delegate, and \\='project.")

(defvar pearl-gtd-inbox--last-context nil
  "Last context used during current inbox processing session.")

(defun pearl-gtd-inbox--read-destination-key (headline)
  "Read single key for destination choice for HEADLINE.
Returns one of: ?a (Next Action), ?r (Reference), ?s (Someday), ?t (Trash),
?x (Execute <2min), ?c (Clarify).
Signals \\='quit if user presses \\`C-g\\'."
  (message "Process '%s': [a] Next Action | [r] Reference | [s] Someday | [t] Trash | [x] Execute (<2min) | [c] Clarify: "
           (substring headline 0 (min 30 (length headline))))
  (let ((key (read-key)))
    (while (not (or (memq key '(?a ?A ?r ?R ?s ?S ?t ?T ?x ?X ?c ?C))
                    (eq key 7)))  ; C-g is character 7
      (message "Invalid key. Process '%s': [a] Next Action | [r] Reference | [s] Someday | [t] Trash | [x] Execute (<2min) | [c] Clarify: "
               (substring headline 0 (min 30 (length headline))))
      (setq key (read-key)))
    ;; If C-g pressed, signal quit
    (if (eq key 7)
        (signal 'quit nil)
      (downcase key))))

(defun pearl-gtd-inbox--clarify-entry (headline)
  "Clarify HEADLINE and remarks.
Returns (NEW-HEADLINE . REMARKS).  Either can be nil."
  (let* ((new (read-string (format "Clarify '%s' [RET keep]: <Clear next action> (e.g., Buy organic milk from Whole Foods): "
                                   headline)))
         (new-headline (let ((trimmed (string-trim new)))
                        (unless (string= trimmed "") trimmed)))
         (remarks-text (read-string (format "Notes for '%s' [RET skip]: <Details or constraints> (e.g., Check brand: Organic Valley): "
                                            (or new-headline headline)))))
    (cons new-headline (unless (string= remarks-text "") remarks-text))))

(defun pearl-gtd-inbox--collect-action-attrs (&optional staging-buffer default-context default-project)
  "Collect action attributes with context inheritance.
If STAGING-BUFFER is provided, ensure focus returns to it after each input.
If DEFAULT-CONTEXT is a non-empty string, use it directly.
If DEFAULT-PROJECT is a non-empty string, use it directly.
Returns alist: ((context . VAL) (schedule . VAL) (deadline . VAL)
               (delegate . VAL) (project . VAL))"
  (let* ((ctx (if (and default-context (not (string= default-context "")))
                  default-context
                (progn
                  (when staging-buffer (pop-to-buffer staging-buffer))
                  (pearl-gtd-inbox--read-context))))
         (sched (progn
                  (when staging-buffer (pop-to-buffer staging-buffer))
                  (pearl-gtd-core-read-date 'schedule)))
         (dead (progn
                 (when staging-buffer (pop-to-buffer staging-buffer))
                 (pearl-gtd-core-read-date 'deadline)))
         (deleg (progn
                  (when staging-buffer (pop-to-buffer staging-buffer))
                  (pearl-gtd-inbox--read-delegate)))
         (proj (if (and default-project (not (string= default-project "")))
                   default-project
                 (progn
                   (when staging-buffer (pop-to-buffer staging-buffer))
                   (pearl-gtd-inbox--read-project)))))
    `((context . ,ctx) (schedule . ,sched) (deadline . ,dead)
      (delegate . ,deleg) (project . ,proj))))

(defun pearl-gtd-inbox--read-context ()
  "Read context with completion from existing actions, allowing free input."
  (let* ((existing (pearl-gtd-core-collect-contexts
                    (expand-file-name "actions.org" pearl-gtd-init-base-directory)))
         (default (or pearl-gtd-inbox--last-context ""))
         (prompt (if (string= default "")
                     "Context [RET none, TAB complete]: <@location/tool> (e.g., @office, @home, @phone): "
                   (format "Context [RET '%s', TAB complete]: <@location/tool> (e.g., @office, @home): " default)))
         (input (completing-read prompt existing nil nil nil nil default)))
    (unless (string= input "")
      (setq pearl-gtd-inbox--last-context input))
    input))

(defun pearl-gtd-inbox--read-project ()
  "Read project with completion from existing projects."
  (let* ((existing (pearl-gtd-review--collect-all-projects))
         (input (completing-read "Project [RET none, TAB complete]: <Project name> (e.g., Website-Redesign, Q1-Goals): " existing nil nil)))
    input))

(defun pearl-gtd-inbox--read-delegate ()
  "Read delegate with completion from existing delegates."
  (let* ((existing '())
         (input (completing-read "Delegated to [RET none, TAB complete]: <Person name> (e.g., John Smith, Alice): " existing nil nil)))
    input))

(defvar-local pearl-gtd-inbox--current-highlight nil
  "Current highlight overlay in the staging buffer.")

(defvar-local pearl-gtd-inbox--marked-deleted-rows '()
  "Buffer-local list of row numbers marked as deleted.")

(defvar-local pearl-gtd-inbox--marked-executed-rows '()
  "Buffer-local list of row numbers marked as executed.")

(defun pearl-gtd-inbox--create-staging-buffer (file-path &optional buffer-name filter-pred)
  "Create a staging buffer from FILE-PATH.
Optional BUFFER-NAME specifies the buffer name.  Return the created buffer.
Optional FILTER-PRED is a predicate called with no arguments in the
context of each entry; only entries matching the predicate are included."
  (setq pearl-gtd-inbox--staging-original-file file-path
        pearl-gtd-inbox--staging-changes nil
        pearl-gtd-inbox--marked-deleted-rows '()
        pearl-gtd-inbox--marked-executed-rows '())
  (let ((actual-buffer-name (or buffer-name (generate-new-buffer-name " *pearl-gtd-inbox-staging*")))
        (headlines '()))
    (with-current-buffer (get-buffer-create actual-buffer-name)
      (setq buffer-read-only nil)
      (erase-buffer)
      (insert-file-contents file-path)
      (org-mode)
      (org-map-entries
       (lambda ()
         (when (or (null filter-pred) (funcall filter-pred))
           (push (list (org-get-heading t t)
                       (org-get-tags)
                       (org-get-todo-state)
                       (org-entry-get nil "CREATED"))
                 headlines))))
      (erase-buffer)
      (insert "| Headline | Remarks | Age | Tags |\n")
      (insert "|----------+---------+-----+------|\n")
      (dolist (entry (nreverse headlines))
        (let* ((created-str (nth 3 entry))
               (age-str (if created-str
                            (let* ((created-time (date-to-time created-str))
                                   (diff (time-subtract (current-time) created-time))
                                   (total-seconds (floor (float-time diff)))
                                   (days (/ total-seconds 86400))
                                   (hours (/ (% total-seconds 86400) 3600))
                                   (minutes (/ (% total-seconds 3600) 60)))
                              (format "%dd %dh %dm" days hours minutes))
                          "N/A"))
               (headline (nth 0 entry))
               (escaped-headline (replace-regexp-in-string "|" "\\\\vert{}" headline)))
          (insert (format "| %s | | %s | %s |\n"
                          escaped-headline
                          age-str
                          (mapconcat #'identity (nth 1 entry) ",")))))
      (org-table-align)
      (setq buffer-read-only t)
      (current-buffer))))

(defun pearl-gtd-inbox--map-entries (buffer func)
  "Map over all entries in BUFFER.
Calls FUNC with headline, entry-ref, and original-tags for each entry."
  (with-current-buffer buffer
    (save-excursion
      (goto-char (point-min))
      (forward-line 2)
      (let ((entries '()))
        (while (not (eobp))
          (let ((current-row (line-number-at-pos)))
            (when (looking-at "|")
              (let ((headline (string-trim (org-table-get-field 1)))
                    (tags-field (string-trim (org-table-get-field 4))))
                ;; Unescape pipe characters that were escaped for table display
                (setq headline (replace-regexp-in-string "\\\\vert{}" "|" headline))
                (when (and headline (not (string= headline "")))
                  (push (list headline (cons buffer current-row) tags-field) entries)))))
          (forward-line 1))
        (dolist (entry (nreverse entries))
          (funcall func (nth 0 entry) (nth 1 entry) (nth 2 entry)))))))

(defun pearl-gtd-inbox--highlight-entry (entry-ref)
  "Highlight ENTRY-REF in staging buffer.
ENTRY-REF is a cons cell (BUFFER . ROW)."
  (let ((buffer (car entry-ref)) (row (cdr entry-ref)))
    (with-current-buffer buffer
      (save-excursion
        (when pearl-gtd-inbox--current-highlight
          (delete-overlay pearl-gtd-inbox--current-highlight))
        (goto-char (point-min))
        (forward-line (1- row))
        (let ((ov (make-overlay (line-beginning-position) (line-end-position))))
          (overlay-put ov 'face 'pearl-gtd-inbox--highlight)
          (overlay-put ov 'evaporate t)
          (setq pearl-gtd-inbox--current-highlight ov))))))

(defun pearl-gtd-inbox--mark-deleted-impl (row)
  "Mark ROW as deleted.  Internal implementation for state layer."
  (let ((inhibit-read-only t))
    (save-excursion
      (goto-char (point-min))
      (forward-line (1- row))
      (org-table-goto-column 1)
      (let* ((start (point))
             (end (progn (skip-chars-forward "^|") (point)))
             (ov (make-overlay start end)))
        (overlay-put ov 'face 'pearl-gtd-inbox--deleted)
        (overlay-put ov 'evaporate t)))
    (cl-pushnew row pearl-gtd-inbox--marked-deleted-rows)))

(defun pearl-gtd-inbox--mark-deleted (entry-ref)
  "Mark ENTRY-REF as deleted.
ENTRY-REF is a cons cell (BUFFER . ROW)."
  (let ((buffer (car entry-ref)) (row (cdr entry-ref)))
    (with-current-buffer buffer
      (pearl-gtd-inbox--mark-deleted-impl row))))

(defun pearl-gtd-inbox--mark-executed-impl (row)
  "Mark ROW as executed.  Internal implementation for state layer."
  (let ((inhibit-read-only t))
    (save-excursion
      (goto-char (point-min))
      (forward-line (1- row))
      (org-table-goto-column 1)
      (let* ((start (point))
             (end (progn (skip-chars-forward "^|") (point)))
             (ov (make-overlay start end)))
        (overlay-put ov 'face 'pearl-gtd-inbox--executed)
        (overlay-put ov 'evaporate t)))
    (cl-pushnew row pearl-gtd-inbox--marked-executed-rows)))

(defun pearl-gtd-inbox--mark-executed (entry-ref)
  "Mark ENTRY-REF as executed.
ENTRY-REF is a cons cell (BUFFER . ROW)."
  (let ((buffer (car entry-ref)) (row (cdr entry-ref)))
    (with-current-buffer buffer
      (pearl-gtd-inbox--mark-executed-impl row))))

(defun pearl-gtd-inbox--stage-change-impl (row col new-value)
  "Stage change for ROW at COL with NEW-VALUE.
Internal implementation for state layer."
  (push (list row col new-value) pearl-gtd-inbox--staging-changes)
  (let ((inhibit-read-only t))
    (save-excursion
      (goto-char (point-min))
      (forward-line (1- row))
      (org-table-goto-column col)
      (org-table-blank-field)
      (insert new-value)
      (org-table-align)
      (pearl-gtd-inbox--reapply-marks (current-buffer)))))

(defun pearl-gtd-inbox--stage-change (entry-ref col new-value)
  "Stage change for ENTRY-REF at COL with NEW-VALUE.
ENTRY-REF is a cons cell (BUFFER . ROW).
COL is the column number to modify.
NEW-VALUE is the string to insert."
  (let ((buffer (car entry-ref)) (row (cdr entry-ref)))
    (with-current-buffer buffer
      (pearl-gtd-inbox--stage-change-impl row col new-value))))

(defun pearl-gtd-inbox--clear-changes (buffer)
  "Clear changes in BUFFER.
BUFFER is the staging buffer to clear."
  (with-current-buffer buffer
    (setq pearl-gtd-inbox--staging-changes nil)))

(defun pearl-gtd-inbox--reapply-marks (buffer)
  "Reapply marks to BUFFER after table alignment.
BUFFER is the staging buffer to update."
  (with-current-buffer buffer
    (dolist (row pearl-gtd-inbox--marked-deleted-rows)
      (condition-case nil
          (progn
            (goto-char (point-min))
            (forward-line (1- row))
            (org-table-goto-column 1)
            (let* ((start (point))
                   (end (progn (skip-chars-forward "^|") (point)))
                   (ov (make-overlay start end)))
              (overlay-put ov 'face 'pearl-gtd-inbox--deleted)
              (overlay-put ov 'evaporate t)))
        (error nil)))
    (dolist (row pearl-gtd-inbox--marked-executed-rows)
      (condition-case nil
          (progn
            (goto-char (point-min))
            (forward-line (1- row))
            (org-table-goto-column 1)
            (let* ((start (point))
                   (end (progn (skip-chars-forward "^|") (point)))
                   (ov (make-overlay start end)))
              (overlay-put ov 'face 'pearl-gtd-inbox--executed)
              (overlay-put ov 'evaporate t)))
        (error nil)))))

(defvar pearl-gtd-inbox--pending-moves nil
  "List of pending moves after staging.

Each element is a list:
ORIGINAL-HEADLINE, TARGET-FILE, PROPERTIES-STRING,
NEW-HEADLINE, REMARKS, and DEADLINE.

If TARGET-FILE is nil, the entry is deleted (trash).
PROPERTIES-STRING contains tags and properties.
NEW-HEADLINE is the clarified headline, or nil if unchanged.
REMARKS is the clarified remarks text, or nil if none.
DEADLINE is the deadline date string, or nil if not set.")

(defvar pearl-gtd-inbox-stage-buffer-name nil
  "The name of the current inbox staging buffer.")

(defun pearl-gtd-inbox--capture ()
  "Capture a new item to the inbox with a timestamp."
  (let ((item (string-trim (read-string "Capture to inbox: <Raw idea or task> (e.g., Buy milk, Call mom about dinner): "))))
    (unless (string-empty-p item)
      ;; Sanitize: remove control chars and normalize newlines
      (setq item (replace-regexp-in-string "[\x00-\x08\x0b-\x0c\x0e-\x1f\x7f]" "" item))
      (setq item (replace-regexp-in-string "\n" " " item))
      (with-current-buffer (find-file-noselect (expand-file-name "inbox.org" pearl-gtd-init-base-directory))
        (goto-char (point-max))
        (insert (format "* %s\n:PROPERTIES:\n:CREATED: %s\n:END:\n" item (format-time-string "%F %T")))
        (forward-line -2)
        (org-id-get-create)
        (save-buffer)))))

;;;; State Machine Layer

(defun pearl-gtd-inbox--fields-to-props (fields)
  "Convert FIELDS alist to properties string for org entry."
  (let ((parts '()))
    (dolist (f fields)
      (pcase f
        (`(context . ,ctx)
         (when ctx (push ctx parts)))
        (`(schedule . ,sched)
         (when sched (push (format ":SCHEDULED:%s:" sched) parts)))
        (`(deadline . ,dead)
         (when dead (push (format ":DEADLINE:%s:" dead) parts)))
        (`(delegate . ,deleg)
         (when deleg (push (format ":DELEGATED:%s:" deleg) parts)))
        (`(project . ,proj)
         (when proj (push (format ":PROJECT:%s:" proj) parts)))))
    (mapconcat #'identity (nreverse parts) " ")))

;;;; Entry Point

(defun pearl-gtd-inbox--process-entry (headline buffer entry-ref original-tags &optional default-context default-project)
  "Process HEADLINE entry with new streamlined flow.
Optional DEFAULT-CONTEXT and DEFAULT-PROJECT are passed to action
attribute collection.  ORIGINAL-TAGS is the original tags string from
the staging buffer."
  (let ((current-headline headline)
        (current-remarks nil)
        (dest nil))
    (while (not dest)
      (pearl-gtd-inbox--highlight-entry entry-ref)
      (let ((key (pearl-gtd-inbox--read-destination-key current-headline)))
        (pcase key
          (?c (let ((clarified (pearl-gtd-inbox--clarify-entry current-headline)))
                (when (car clarified)
                  (setq current-headline (car clarified))
                  (pearl-gtd-inbox--stage-change entry-ref 1 current-headline))
                (when (cdr clarified)
                  (setq current-remarks (cdr clarified))
                  (pearl-gtd-inbox--stage-change entry-ref 2 current-remarks))))
          (?a (setq dest 'action))
          (?r (setq dest 'ref))
          (?s (setq dest 'someday))
          (?t (setq dest 'trash))
          (?x (setq dest 'execute))
          (_ (message "Invalid key") (sit-for 0.5)))))
    (pcase dest
      ('execute
       (pearl-gtd-inbox--mark-executed entry-ref)
       (pearl-gtd-inbox--stage-change entry-ref 4 "Executed")
       (push (list headline nil nil current-headline current-remarks nil)
             pearl-gtd-inbox--pending-moves))
      ('trash
       (pearl-gtd-inbox--mark-deleted entry-ref)
       (pearl-gtd-inbox--stage-change entry-ref 4 "Trashed")
       (push (list headline nil nil current-headline current-remarks nil)
             pearl-gtd-inbox--pending-moves))
      ('ref
       (pearl-gtd-inbox--stage-change entry-ref 4 "Reference")
       (push (list headline "reference.org" nil current-headline current-remarks nil)
             pearl-gtd-inbox--pending-moves))
      ('someday
       (pearl-gtd-inbox--stage-change entry-ref 4 "Someday")
       (push (list headline "someday.org" nil current-headline current-remarks nil)
             pearl-gtd-inbox--pending-moves))
      ('action
       (let* ((attrs (pearl-gtd-inbox--collect-action-attrs buffer default-context default-project))
              (deadline (cdr (assoc 'deadline attrs)))
              (context (cdr (assoc 'context attrs)))
              (project (cdr (assoc 'project attrs)))
              (tags-summary original-tags))
         ;; Build tags summary from original tags + new attributes
         (when (and context (not (string= context "")))
           (setq tags-summary (if (string= tags-summary "")
                                 context
                               (concat tags-summary "," context))))
         (when (and project (not (string= project "")))
           (setq tags-summary (if (string= tags-summary "")
                                 (concat "Project:" project)
                               (concat tags-summary ",Project:" project))))
         (when (and deadline (not (string= deadline "")))
           (setq tags-summary (if (string= tags-summary "")
                                 (concat "Deadline:" deadline)
                               (concat tags-summary ",Deadline:" deadline))))
         (when buffer (pop-to-buffer buffer))
         (pearl-gtd-inbox--stage-change entry-ref 4 tags-summary)
         (push (list headline "actions.org"
                     (pearl-gtd-inbox--fields-to-props attrs)
                     current-headline current-remarks deadline)
               pearl-gtd-inbox--pending-moves))))
    (pearl-gtd-inbox--apply-staged-changes buffer (cdr entry-ref) nil)))

(defun pearl-gtd-inbox--process (&optional brainstorm default-context default-project)
  "Process the inbox according to GTD clarify and organize steps.
If BRAINSTORM is non-nil, only process entries with BRAINSTORM property
set to \"t\".  DEFAULT-CONTEXT and DEFAULT-PROJECT are used when
BRAINSTORM is non-nil."
  (setq pearl-gtd-inbox--last-context nil)
  (let ((inbox-file (expand-file-name "inbox.org" pearl-gtd-init-base-directory)))
    (setq pearl-gtd-inbox--pending-moves '())
    (when (and pearl-gtd-inbox-stage-buffer-name (get-buffer pearl-gtd-inbox-stage-buffer-name))
      (kill-buffer pearl-gtd-inbox-stage-buffer-name))
    (if (file-exists-p inbox-file)
        (let* ((attrs (file-attributes inbox-file))
               (file-size (file-attribute-size attrs)))
          (if (> file-size 0)
              (let* ((buffer-name (if brainstorm
                                      (format " *brainstorm-organize: %s*" (or default-project "unknown"))
                                    " *inbox-processing*"))
                     (staging-buffer (pearl-gtd-inbox--create-staging-buffer
                                      inbox-file
                                      buffer-name
                                      (when brainstorm
                                        (lambda ()
                                          (and (string= (org-entry-get nil "BRAINSTORM") "t")
                                               (or (null default-project)
                                                   (string= (org-entry-get nil "PROJECT") default-project))))))))
                (setq pearl-gtd-inbox-stage-buffer-name (buffer-name staging-buffer))
                (pop-to-buffer staging-buffer)
                (condition-case _err
                    (with-current-buffer staging-buffer
                      (org-mode)
                      (pearl-gtd-inbox--map-entries
                       staging-buffer
                       (lambda (headline entry-ref original-tags)
                         (pearl-gtd-inbox--highlight-entry entry-ref)
                         (pearl-gtd-inbox--process-entry headline staging-buffer entry-ref original-tags default-context default-project)))
                      (when pearl-gtd-inbox--current-highlight
                        (delete-overlay pearl-gtd-inbox--current-highlight)
                        (setq pearl-gtd-inbox--current-highlight nil))
                      (pearl-gtd-inbox--clear-changes staging-buffer)
                      (setq pearl-gtd-inbox--pending-moves (nreverse pearl-gtd-inbox--pending-moves))
                      (dolist (move pearl-gtd-inbox--pending-moves)
                        (pearl-gtd-inbox--do-move (nth 0 move) (nth 1 move) (nth 2 move)
                                                  (nth 3 move) (nth 4 move) (nth 5 move)
                                                  brainstorm))
                      (when (and (file-exists-p inbox-file)
                                 (= 0 (file-attribute-size (file-attributes inbox-file))))
                        (delete-file inbox-file))
                      (message "Inbox processing complete and changes applied per GTD workflow."))
                  (quit
                   (message "Inbox processing cancelled.")
                   (kill-buffer staging-buffer)
                   (signal 'quit nil))))
            (let ((buffer-name "*Pearl-GTD: Inbox*"))
              (get-buffer-create buffer-name)
              (with-current-buffer buffer-name
                (setq buffer-read-only nil)
                (erase-buffer)
                (org-mode)
                (insert "(Inbox is empty - nothing to process)\n")
                (setq buffer-read-only t)
                (goto-char (point-min)))
              (pop-to-buffer buffer-name)
              (message "Inbox is empty, nothing to process."))))
      (let ((buffer-name "*Pearl-GTD: Inbox*"))
        (get-buffer-create buffer-name)
        (with-current-buffer buffer-name
          (setq buffer-read-only nil)
          (erase-buffer)
          (org-mode)
          (insert "(Inbox is empty - nothing to process)\n")
          (setq buffer-read-only t)
          (goto-char (point-min)))
        (pop-to-buffer buffer-name)
        (message "Inbox is empty, nothing to process.")))))

(defun pearl-gtd-inbox--do-move (headline target-file properties-string new-headline remarks deadline &optional brainstorm)
  "Move HEADLINE to TARGET-FILE and delete from inbox.
If TARGET-FILE is nil, just delete from inbox (trash).
If BRAINSTORM is non-nil, remove BRAINSTORM property before moving.
PROPERTIES-STRING contains tags and properties.
NEW-HEADLINE is the clarified headline (nil if unchanged).
REMARKS is the clarified remarks text (nil if none).
DEADLINE is the deadline date string (nil if not set)."
  (let ((inbox-path (expand-file-name "inbox.org" pearl-gtd-init-base-directory))
        subtree-content)
    (when (and properties-string (not (string= properties-string "")))
      (with-current-buffer (find-file-noselect inbox-path)
        (org-mode)
        (goto-char (point-min))
        (when (re-search-forward (concat "^\\*+ " (regexp-quote headline) "\\($\\| \\)") nil t)
          (beginning-of-line)
          (let ((components (split-string properties-string " " t)))
            (dolist (comp components)
              (cond
               ((string-match "^:SCHEDULED:\\(.+\\):$" comp)
                (let ((date-str (match-string 1 comp)))
                  (org-schedule nil date-str)))
               ((string-match "^:PROJECT:\\(.+\\):$" comp)
                (let ((projects (match-string 1 comp)))
                  (dolist (proj (split-string projects "," t))
                    (org-entry-add-to-multivalued-property
                     nil "PROJECT" (string-trim proj)))))
               ((string-match "^:\\([^:]+\\):\\(.+\\):$" comp)
                (let ((prop-name (match-string 1 comp))
                      (prop-value (match-string 2 comp)))
                  (org-set-property prop-name prop-value)))
               ((string-match "^@\\(.+\\)$" comp)
                (let ((tag (match-string 1 comp)))
                  (org-set-tags (list tag))))
               ((not (string-match "^:" comp))
                (org-set-tags (list comp))))))
          (save-buffer))))
    (when (and deadline (not (string= deadline "")))
      (with-current-buffer (find-file-noselect inbox-path)
        (org-mode)
        (goto-char (point-min))
        (if (re-search-forward (concat "^\\*+ " (regexp-quote (or new-headline headline)) "\\($\\| \\)") nil t)
            (progn
              (org-deadline nil deadline)
              (save-buffer))
          nil)))
    (with-current-buffer (find-file-noselect inbox-path)
      (org-mode)
      (goto-char (point-min))
      (when (re-search-forward (concat "^\\*+ " (regexp-quote headline) "\\($\\| \\)") nil t)
        (beginning-of-line)
        (when new-headline
          (org-edit-headline new-headline))
        (when (and target-file (string= target-file "actions.org"))
          (org-todo "TODO"))
        (when remarks
          (org-end-of-meta-data t)
          (unless (bolp)
            (insert "\n"))
          (insert remarks "\n"))
        (goto-char (point-min))
        (re-search-forward (concat "^\\*+[ \t]+\\(?:[A-Z]+[ \t]+\\)?"
                                   (regexp-quote (or new-headline headline))
                                   "\\($\\| \\)"))
        (beginning-of-line)
        (when (and brainstorm target-file)
          (org-delete-property "BRAINSTORM"))
        (org-mark-subtree)
        (setq subtree-content (buffer-substring (region-beginning) (region-end)))
        (kill-region (region-beginning) (region-end))
        (save-buffer))
      (when (and target-file subtree-content)
        (let ((target-path (expand-file-name target-file pearl-gtd-init-base-directory)))
          (with-current-buffer (find-file-noselect target-path)
            (org-mode)
            (goto-char (point-max))
            (unless (bolp) (insert "\n"))
            (insert subtree-content)
            (unless (bolp) (insert "\n"))
            (save-buffer)))))))

(defun pearl-gtd-inbox--apply-staged-changes (_buffer _row _context)
  "Apply staged changes for entry.  No-op in current implementation."
  nil)

(provide 'pearl-gtd-inbox)

;;; pearl-gtd-inbox.el ends here
