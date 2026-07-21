;;; pearl-gtd-core.el --- Core infrastructure for pearl-gtd  -*- lexical-binding: t; -*-

;;; Commentary:

;; This file provides core infrastructure for Pearl-GTD, including
;; predicates, filters, and data collection utilities used by other modules.

;;; Code:

(require 'org)
(require 'pearl-gtd-init)

;;;; Predicates

(defun pearl-gtd-core-entry-todo-p ()
  "Return non-nil if current entry is a TODO item."
  (string= (org-get-todo-state) "TODO"))

(defun pearl-gtd-core-entry-done-p ()
  "Return non-nil if current entry is a DONE item."
  (string= (org-get-todo-state) "DONE"))

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
         (today-pattern (format-time-string "<%Y-%m-%d" ct)))
    (and scheduled
         (string-match-p today-pattern scheduled))))

(defun pearl-gtd-core-entry-completed-today-p ()
  "Return non-nil if current entry was closed today."
  (let* ((closed (org-entry-get nil "CLOSED")))
    (and closed
         (string-match-p (format-time-string "\\[%Y-%m-%d" (current-time) t) closed))))

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
Entries are lists: (HEADLINE TAGS-STRING TODO-STATE SCHEDULED DELEGATED PROJECT CREATED).
Nil values indicate unset properties."
  (let ((entries '()))
    (when (file-exists-p file-path)
      (with-temp-buffer
        (insert-file-contents file-path)
        (org-mode)
        (org-map-entries
         (lambda ()
           (when (cl-every (lambda (pred) (funcall pred)) predicates)
             (let* ((head (org-get-heading t t))
                    (id (org-entry-get nil "ID"))
                    (tags (org-get-tags-at))
                    (todo-state (org-get-todo-state))
                    (scheduled (org-entry-get nil "SCHEDULED"))
                    (delegated (org-entry-get nil "DELEGATED"))
                    (project (org-entry-get nil "PROJECT"))
                    (created (org-entry-get nil "CREATED")))
               ;; Attach ID as text property to headline for precise navigation
               (when id
                 (put-text-property 0 (length head) 'pearl-gtd-id id head))
               (push (list head
                          (mapconcat (lambda (c) (concat "@" c)) tags ",")
                          todo-state
                          scheduled
                          delegated
                          project
                          created)
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

;;;; Macro for table navigation

(defmacro pearl-gtd-core-define-table-navigators (prefix boundaries-func &optional header-regexp)
  "Define table navigation functions for PREFIX using BOUNDARIES-FUNC.
Creates PREFIX-next-row and PREFIX-previous-row interactive functions.
BOUNDARIES-FUNC should return (first-row-pos . last-row-pos).
HEADER-REGEXP matches header lines to skip (default: \"| Headline\")."
  (let ((next-fn (intern (concat prefix "-next-row")))
        (prev-fn (intern (concat prefix "-previous-row")))
        (skip-fn (intern (concat prefix "--skip-line-p")))
        (header-re (or header-regexp "| Headline")))
    `(progn
       (defun ,skip-fn ()
         "Return non-nil if current line should be skipped during navigation."
         (or (looking-at "|[-+]")                    ; separator line
             (looking-at ,header-re)                  ; header line
             (not (looking-at "|"))))                 ; non-table line

       (defun ,next-fn ()
         "Move to next data row in the table."
         (interactive)
         (let* ((boundaries (,boundaries-func))
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
         (let* ((boundaries (,boundaries-func))
                (first-data-row (car boundaries)))
           (if (<= (line-beginning-position) first-data-row)
               (beep)
             (forward-line -1)
             (while (and (not (bobp)) (,skip-fn))
               (forward-line -1))
             (org-table-goto-column 1)))))))

;;;; Macros for file operations

(defmacro with-file-buffer (file-path &rest body)
  "Execute BODY in buffer of FILE-PATH (expanded relative to base dir).
Buffer is saved if modified after BODY.  Internal errors crash (no catch-all)."
  (declare (indent 1))
  `(let* ((file-path-expanded (expand-file-name ,file-path pearl-gtd-init-base-directory))
          (buf (find-file-noselect file-path-expanded)))
     (with-current-buffer buf
       (org-mode)
       (widen)
       (prog1
           (progn ,@body)
         (when (buffer-modified-p)
           (save-buffer))))))

(defmacro with-entry-at-id (id file &rest body)
  "Execute BODY with point at entry ID in FILE.
Signals error if entry not found (internal state violation)."
  (declare (indent 2))
  `(with-file-buffer ,file
     (goto-char (point-min))
     (let ((id-val ,id))
       (cl-assert (re-search-forward (concat ":ID:[ \t]+" (regexp-quote id-val)) nil t)
                  t "Internal: entry %s not found in %s" id-val ,file)
       (org-back-to-heading)
       ,@body)))

(provide 'pearl-gtd-core)

;;; pearl-gtd-core.el ends here
