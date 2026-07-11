;;; pearl-gtd-review.el --- Review phase for pearl-gtd  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 OverbearingPearl

;; Author: OverbearingPearl <OverbearingPearl@outlook.com>
;; Version: 0.1.0
;; Package-Requires: ((emacs "27.1") (org "9.0"))
;; Keywords: outlines, tools, convenience, productivity, gtd, org
;; URL: https://github.com/OverbearingPearl/pearl-gtd

;;; Commentary:

;; This file handles the "Review" phase of GTD.
;; Provides unified daily and weekly views with multiple sections.

;;; Code:

(require 'org)
(require 'cl-lib)
(require 'pearl-gtd-init)
(require 'pearl-gtd-core)

(defvar-local pearl-gtd-review--current-view-type nil
  "Type of current review view: daily or weekly.")

(defvar-local pearl-gtd-review--entry-map nil
  "Vector mapping row numbers to (ID . FILE) cons cells.")

(defvar pearl-gtd-review-view-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "q") #'pearl-gtd-review--quit-or-return)
    (define-key map (kbd "n") #'pearl-gtd-review--next-row)
    (define-key map (kbd "p") #'pearl-gtd-review--previous-row)
    (define-key map (kbd "j") #'pearl-gtd-review--next-row)
    (define-key map (kbd "k") #'pearl-gtd-review--previous-row)
    (define-key map (kbd "RET") #'pearl-gtd-review--goto-task-at-point)
    (define-key map (kbd "g") #'pearl-gtd-review--refresh-view)
    ;; Property editing with defaults
    (define-key map (kbd "c") #'pearl-gtd-review--edit-context-at-point)
    (define-key map (kbd "d") #'pearl-gtd-review--edit-delegated-at-point)
    (define-key map (kbd "t") #'pearl-gtd-review--edit-scheduled-at-point)
    (define-key map (kbd "s") #'pearl-gtd-review--set-deadline-at-point)
    (define-key map (kbd "r") #'pearl-gtd-review--rename-task-at-point)
    (define-key map (kbd "C") #'pearl-gtd-review--complete-task-at-point)
    (define-key map (kbd "P") #'pearl-gtd-review--edit-project-at-point)
    ;; Horizon editing
    (define-key map (kbd "3") #'pearl-gtd-horizons--edit-l3-at-point)
    (define-key map (kbd "4") #'pearl-gtd-horizons--edit-l4-at-point)
    (define-key map (kbd "5") #'pearl-gtd-horizons--edit-l5-at-point)
    (define-key map (kbd "6") #'pearl-gtd-horizons--edit-l6-at-point)
    map))

(define-minor-mode pearl-gtd-review-view-mode
  "Minor mode for reviewing GTD items in table format."
  :init-value nil
  :lighter " Pearl-Review"
  :keymap pearl-gtd-review-view-mode-map
  :interactive nil)

(defun pearl-gtd-review--data-row-boundaries ()
  "Return cons cell (FIRST-DATA-ROW . LAST-DATA-ROW) positions."
  (save-excursion
    (goto-char (point-min))
    (while (and (not (eobp))
                (or (looking-at "|[-+]")
                    (looking-at "| Headline[ \t]*|")
                    (not (looking-at "|"))))
      (forward-line 1))
    (let ((first-data (line-beginning-position)))
      (goto-char (point-max))
      (forward-line -1)
      (while (and (not (bobp))
                  (or (looking-at "|[-+]")
                      (looking-at "| Headline[ \t]*|")
                      (not (looking-at "|"))
                      (looking-at "^$")))
        (forward-line -1))
      (cons first-data (line-beginning-position)))))

(defun pearl-gtd-review--next-row ()
  "Move to next row in the table."
  (interactive)
  (let* ((boundaries (pearl-gtd-review--data-row-boundaries))
         (last-data-row (cdr boundaries)))
    (if (>= (line-beginning-position) last-data-row)
        (beep)
      (forward-line 1)
      (while (and (not (eobp))
                  (or (looking-at "|[-+]")
                      (looking-at "| Headline[ \t]*|")
                      (not (looking-at "|"))))
        (forward-line 1))
      (org-table-goto-column 1))))

(defun pearl-gtd-review--previous-row ()
  "Move to previous row in the table."
  (interactive)
  (let* ((boundaries (pearl-gtd-review--data-row-boundaries))
         (first-data-row (car boundaries)))
    (if (<= (line-beginning-position) first-data-row)
        (beep)
      (forward-line -1)
      (while (and (not (bobp))
                  (or (looking-at "|[-+]")
                      (looking-at "| Headline[ \t]*|")
                      (not (looking-at "|"))))
        (forward-line -1))
      (org-table-goto-column 1))))

(defun pearl-gtd-review--get-entry-at-point ()
  "Get (ID . FILE) from current row in table using text properties."
  (save-excursion
    (beginning-of-line)
    (let ((end (line-end-position))
          (id nil)
          (file nil))
      (while (and (not id) (< (point) end))
        (setq id (get-text-property (point) 'pearl-gtd-id))
        (setq file (get-text-property (point) 'pearl-gtd-file))
        (forward-char 1))
      (when (and id file)
        (cons id file)))))

(defun pearl-gtd-review--with-entry-buffer (id file callback)
  "Execute CALLBACK in buffer of FILE with entry ID."
  (let ((file-path (expand-file-name file pearl-gtd-init-base-directory))
        (result nil))
    (with-current-buffer (find-file-noselect file-path)
      (org-mode)
      (goto-char (point-min))
      (when (re-search-forward (concat ":ID:[ \t]+" (regexp-quote id)) nil t)
        (org-back-to-heading)
        (funcall callback)
        (setq result t))
      (save-buffer))
    result))

(defun pearl-gtd-review--get-property-by-id (id file property)
  "Get PROPERTY value of entry with ID in FILE."
  (let ((value nil))
    (pearl-gtd-review--with-entry-buffer id file
      (lambda () (setq value (org-entry-get nil property))))
    value))

(defun pearl-gtd-review--set-property-by-id (id file property value)
  "Set PROPERTY to VALUE for entry with ID in FILE."
  (pearl-gtd-review--with-entry-buffer id file
    (lambda () (org-entry-put nil property value))))

(defun pearl-gtd-review--remove-property-by-id (id file property)
  "Remove PROPERTY from entry with ID in FILE."
  (pearl-gtd-review--with-entry-buffer id file
    (lambda () (org-delete-property property))))

(defun pearl-gtd-review--get-scheduled-by-id (id file)
  "Get scheduled date string for entry with ID in FILE."
  (let ((date nil))
    (pearl-gtd-review--with-entry-buffer id file
      (lambda ()
        (let ((s (org-entry-get nil "SCHEDULED")))
          (when s
            (string-match "<\\([0-9]\\{4\\}-[0-9]\\{2\\}-[0-9]\\{2\\}\\)" s)
            (setq date (match-string 1 s))))))
    date))

(defun pearl-gtd-review--get-headline-by-id (id file)
  "Get headline of entry with ID in FILE."
  (let ((headline nil))
    (pearl-gtd-review--with-entry-buffer id file
      (lambda () (setq headline (org-get-heading t t))))
    headline))

(defun pearl-gtd-review--edit-context-at-point ()
  "Edit context with current value as default.  Empty input removes it."
  (interactive)
  (let ((entry (pearl-gtd-review--get-entry-at-point)))
    (when entry
      (let* ((id (car entry))
             (file (cdr entry))
             (current-value (pearl-gtd-review--get-property-by-id id file "CONTEXT"))
             (new-value (read-string "Context (empty to remove): " (or current-value ""))))
        (if (string= new-value "")
            (pearl-gtd-review--remove-property-by-id id file "CONTEXT")
          (pearl-gtd-review--set-property-by-id id file "CONTEXT" new-value))
        (pearl-gtd-review--refresh-view)))))

(defun pearl-gtd-review--edit-delegated-at-point ()
  "Edit delegated with current value as default.  Empty input removes it."
  (interactive)
  (let ((entry (pearl-gtd-review--get-entry-at-point)))
    (when entry
      (let* ((id (car entry))
             (file (cdr entry))
             (current-value (pearl-gtd-review--get-property-by-id id file "DELEGATED"))
             (new-value (read-string "Delegated to (empty to remove): " (or current-value ""))))
        (if (string= new-value "")
            (progn
              (pearl-gtd-review--remove-property-by-id id file "DELEGATED")
              (pearl-gtd-review--remove-property-by-id id file "DELEGATED_DATE"))
          (pearl-gtd-review--set-property-by-id id file "DELEGATED" new-value)
          (pearl-gtd-review--set-property-by-id id file "DELEGATED_DATE"
                                               (format-time-string "[%Y-%m-%d]")))
        (pearl-gtd-review--refresh-view)))))

(defun pearl-gtd-review--edit-scheduled-at-point ()
  "Edit scheduled date with current value as default.  Empty input removes it."
  (interactive)
  (let ((entry (pearl-gtd-review--get-entry-at-point)))
    (when entry
      (let* ((id (car entry))
             (file (cdr entry))
             (current-scheduled (pearl-gtd-review--get-scheduled-by-id id file))
             (default-value (or current-scheduled ""))
             (new-value (read-string "Schedule date YYYY-MM-DD (empty to remove): " default-value)))
        (pearl-gtd-review--with-entry-buffer id file
          (lambda ()
            (if (string= new-value "")
                (org-schedule '(4))
              (org-schedule nil new-value))
            (save-buffer)))
        (pearl-gtd-review--refresh-view)))))

(defun pearl-gtd-review--set-deadline-at-point ()
  "Set deadline for task at point with reminder."
  (interactive)
  (let ((entry (pearl-gtd-review--get-entry-at-point)))
    (when entry
      (let* ((id (car entry))
             (file (cdr entry))
             (deadline (read-string "Deadline (YYYY-MM-DD): "))
             (reminder (read-string "Reminder days before: " "0")))
        (pearl-gtd-review--with-entry-buffer id file
          (lambda ()
            (org-deadline nil deadline)
            (org-set-property "REMINDER_DAYS" reminder)
            (save-buffer)))
        (pearl-gtd-review--refresh-view)))))

(defun pearl-gtd-review--rename-task-at-point ()
  "Rename task at point."
  (interactive)
  (let ((entry (pearl-gtd-review--get-entry-at-point)))
    (when entry
      (let* ((id (car entry))
             (file (cdr entry))
             (current-headline (pearl-gtd-review--get-headline-by-id id file))
             (new-name (read-string "New task name: " current-headline)))
        (when (and new-name (not (string= new-name "")) (not (string= new-name current-headline)))
          (pearl-gtd-review--with-entry-buffer id file
            (lambda ()
              (org-edit-headline new-name)
              (save-buffer)))
          (pearl-gtd-review--refresh-view))))))

(defun pearl-gtd-review--edit-project-at-point ()
  "Edit project with current value as default.  Empty input removes it."
  (interactive)
  (let ((entry (pearl-gtd-review--get-entry-at-point)))
    (when entry
      (let* ((id (car entry))
             (file (cdr entry))
             (current-value (pearl-gtd-review--get-property-by-id id file "PROJECT"))
             (new-value (read-string "Project (empty to remove): " (or current-value ""))))
        (if (string= new-value "")
            (progn
              (pearl-gtd-review--remove-property-by-id id file "PROJECT")
              ;; Also remove horizon properties when leaving project
              (pearl-gtd-review--remove-property-by-id id file "HORIZON_L3")
              (pearl-gtd-review--remove-property-by-id id file "HORIZON_L4")
              (pearl-gtd-review--remove-property-by-id id file "HORIZON_L5")
              (pearl-gtd-review--remove-property-by-id id file "HORIZON_L6"))
          (pearl-gtd-review--set-property-by-id id file "PROJECT" new-value))
        (pearl-gtd-review--refresh-view)))))

(defun pearl-gtd-review--complete-task-at-point ()
  "Mark task at point as done."
  (interactive)
  (let ((entry (pearl-gtd-review--get-entry-at-point)))
    (when entry
      (let ((id (car entry))
            (file (cdr entry)))
        (pearl-gtd-review--with-entry-buffer id file
          (lambda ()
            (let ((org-log-done 'time))
              (org-todo "DONE"))
            (save-buffer)))
        (pearl-gtd-review--refresh-view)))))

(defun pearl-gtd-review--goto-task-at-point ()
  "Jump to task in source file."
  (interactive)
  (let ((entry (pearl-gtd-review--get-entry-at-point)))
    (when entry
      (let ((id (car entry))
            (file (cdr entry)))
        (find-file (expand-file-name file pearl-gtd-init-base-directory))
        (goto-char (point-min))
        (when (re-search-forward (concat ":ID:[ \t]+" (regexp-quote id)) nil t)
          (org-back-to-heading))))))

(defun pearl-gtd-review--refresh-view ()
  "Refresh current review view."
  (interactive)
  (pcase pearl-gtd-review--current-view-type
    ('daily (pearl-gtd-review--daily))
    ('weekly (pearl-gtd-review--weekly))
    (_ (message "Cannot refresh this view"))))

(defun pearl-gtd-review--insert-table-row (head id file &rest fields)
  "Insert a table row into the review buffer.
HEAD is the entry headline string.
ID is the unique identifier string, or nil for project rows.
FILE is the source file path string.
FIELDS is a list of field values in order.

For project rows (ID is nil), attach `pearl-gtd-project' property to HEAD.
For task rows, attach `pearl-gtd-id' and `pearl-gtd-file' properties to HEAD.

The number of fields determines the table format:
- 1 field: Created (Inbox - Headline + Created)
- 7 fields: Status, Scheduled, Deadline, Context, Delegated, Project (standard)
- 6 fields: Status, Scheduled, Deadline, Context, Delegated, L3 (No Project)
- 8 fields: Total, Todo, Done, Next Deadline, L3, L4, L5, L6 (Project rows)"
  (let* ((headline-escaped (replace-regexp-in-string "|" "\\\\vert{}" head))
         (field-count (length fields)))
    ;; Insert headline with properties
    (insert "| ")
    (let ((start (point)))
      (insert headline-escaped)
      (if (and (null id) head)
          (put-text-property start (point) 'pearl-gtd-project head)
        (progn
          (put-text-property start (point) 'pearl-gtd-id id)
          (put-text-property start (point) 'pearl-gtd-file file))))
    ;; Insert fields
    (dolist (field fields)
      (insert " | " (or field "")))
    (insert " |\n")))

(defun pearl-gtd-review--create-table-buffer (buffer-name sections)
  "Create review buffer named BUFFER-NAME with multiple sections.
SECTIONS is a list of (TITLE . ENTRIES) or (TITLE ENTRIES . TYPE)
where TYPE can be \\='project for project sections."
  (with-current-buffer (get-buffer-create buffer-name)
    (setq buffer-read-only nil)
    (erase-buffer)
    (org-mode)
    (setq pearl-gtd-review--entry-map (make-vector 100 nil))
    (let ((entry-index 0))
      (if (null sections)
          (insert "(No entries to review)\n")
        (dolist (section sections)
          (let* ((title (car section))
                 (is-project (eq (cddr section) 'project))
                 (entries (if is-project (cadr section) (cdr section)))
                 (is-no-project (string-match-p "no project" (downcase title)))
                 (is-inbox (string-match-p "inbox" (downcase title))))
            (insert (format "** %s\n" title))
            (cond
             (is-project
              (insert "| Project | Total | Todo | Done | Next Deadline | L3 | L4 | L5 | L6 |\n")
              (insert "|---------+-------+------+------+---------------+----+----+----+----|\n"))
             (is-no-project
              (insert "| Headline | Status | Scheduled | Deadline | Context | Delegated | L3 |\n")
              (insert "|----------+--------+-----------+----------+---------+-----------+----|\n"))
             (is-inbox
              (insert "| Headline | Created |\n")
              (insert "|----------+---------|\n"))
             (t
              (insert "| Headline | Status | Scheduled | Deadline | Context | Delegated | Project |\n")
              (insert "|----------+--------+-----------+----------+---------+-----------+---------|\n")))
            (if (null entries)
                (cond
                 (is-no-project
                  (insert "| (No entries) | | | | | | |\n"))  ; 7 columns for No Project (including L3)
                 (is-project
                  (insert "| (No entries) | | | | | | | | |\n"))    ; 9 columns for Project (including L3-L6)
                 (is-inbox
                  (insert "| (No entries) | |\n"))  ; 2 columns for Inbox)
                 (t
                  (insert "| (No entries) | | | | | | |\n")))  ; 7 columns for standard (no Created)
              (dolist (entry entries)
                (apply #'pearl-gtd-review--insert-table-row entry)
                (unless (or is-project is-no-project is-inbox)
                  (aset pearl-gtd-review--entry-map entry-index (cons (nth 1 entry) (nth 2 entry))))
                (setq entry-index (1+ entry-index))))
            (forward-line -1)
            (org-table-align)
            (goto-char (point-max))
            (insert "\n")))))
    (setq buffer-read-only t)
    (goto-char (point-min))
    (current-buffer)))

(defun pearl-gtd-review--collect-entries-from-file (file &optional predicates include-created)
  "Collect entries from FILE matching PREDICATES.
INCLUDE-CREATED non-nil means include Created field.
Returns list of entry lists suitable for table display."
  (let ((file-path (expand-file-name file pearl-gtd-init-base-directory))
        (entries '()))
    (when (file-exists-p file-path)
      (with-temp-buffer
        (insert-file-contents file-path)
        (org-mode)
        (org-map-entries
         (lambda ()
           (let ((id (org-entry-get nil "ID")))
             (when id
               (let ((head (org-get-heading t t))
                     (todo-state (org-get-todo-state))
                     (scheduled (org-entry-get nil "SCHEDULED"))
                     (deadline (org-entry-get nil "DEADLINE"))
                     (context (org-entry-get nil "CONTEXT"))
                     (delegated (org-entry-get nil "DELEGATED"))
                     (project (org-entry-get nil "PROJECT"))
                     (created (org-entry-get nil "CREATED")))
                 (when (or (null predicates)
                           (cl-every (lambda (pred) (funcall pred)) predicates))
                   ;; Convert nil values to empty strings
                   (if include-created
                       ;; For inbox, only return Headline and Created (1 field)
                       (push (list head id file
                                   (or created ""))
                             entries)
                     (push (list head id file
                                 (or todo-state "")
                                 (or scheduled "")
                                 (or deadline "")
                                 (or context "")
                                 (or delegated "")
                                 (or project ""))
                           entries)))))))
         nil nil)))
    (nreverse entries)))

(defun pearl-gtd-review--entry-upcoming-deadline-p ()
  "Return non-nil if entry has deadline within next 7 days."
  (let ((deadline (org-entry-get nil "DEADLINE")))
    (when deadline
      (let* ((deadline-time (org-time-string-to-time deadline))
             (now-days (floor (/ (float-time (current-time)) 86400)))
             (deadline-days (floor (/ (float-time deadline-time) 86400)))
             (seven-days-later (+ now-days 7)))
        (and (>= deadline-days now-days)
             (<= deadline-days seven-days-later))))))

(defun pearl-gtd-review--collect-upcoming-deadlines ()
  "Collect entries with deadlines in next 7 days from actions.org."
  (pearl-gtd-review--collect-entries-from-file
   "actions.org"
   (list #'pearl-gtd-core-entry-todo-p
         #'pearl-gtd-review--entry-upcoming-deadline-p)
   nil))  ; no Created field

(defun pearl-gtd-review--collect-all-projects ()
  "Collect all unique project names from actions.org."
  (let ((actions-file (expand-file-name "actions.org" pearl-gtd-init-base-directory))
        (projects '()))
    (when (file-exists-p actions-file)
      (with-temp-buffer
        (insert-file-contents actions-file)
        (org-mode)
        (org-map-entries
         (lambda ()
           (let ((proj (org-entry-get nil "PROJECT")))
             (when proj
               ;; PROJECT can contain multiple projects separated by comma or space
               (dolist (p (split-string proj "[, ]" t))
                 (cl-pushnew p projects :test #'string=)))))
         nil nil)))
    (nreverse projects)))

(defun pearl-gtd-review--get-project-stats (proj-name)
  "Get statistics for PROJ-NAME from actions.org.
PROJ-NAME is a string naming the project to analyze.
Returns list (TOTAL TODO DONE NEXT-DEADLINE L3 L4 L5 L6) where:
TOTAL is the total number of entries,
TODO is the count of unfinished entries,
DONE is the count of completed entries,
NEXT-DEADLINE is the earliest deadline string or empty string,
L3-L6 are horizon values from project entries."
  (let ((file-path (expand-file-name "actions.org" pearl-gtd-init-base-directory))
        (total 0)
        (done 0)
        (todo 0)
        (next-deadline nil)
        (horizon-l3 nil)
        (horizon-l4 nil)
        (horizon-l5 nil)
        (horizon-l6 nil))
    (when (file-exists-p file-path)
      (with-temp-buffer
        (insert-file-contents file-path)
        (org-mode)
        (org-map-entries
         (lambda ()
           (let ((proj (org-entry-get nil "PROJECT")))
             (when proj
               (let ((projects (split-string proj "[, ]" t)))
                 (when (member proj-name projects)
                   (cl-incf total)
                   (let ((todo-state (org-get-todo-state)))
                     (cond
                      ((member todo-state org-done-keywords) (cl-incf done))
                      ((string= todo-state "TODO") (cl-incf todo)))
                     ;; Collect horizon values from first TODO entry
                     (when (and (null horizon-l3) (pearl-gtd-core-entry-todo-p))
                       (setq horizon-l3 (org-entry-get nil "HORIZON_L3"))
                       (setq horizon-l4 (org-entry-get nil "HORIZON_L4"))
                       (setq horizon-l5 (org-entry-get nil "HORIZON_L5"))
                       (setq horizon-l6 (org-entry-get nil "HORIZON_L6")))
                     (let ((deadline (org-entry-get nil "DEADLINE")))
                       (when deadline
                         (let ((d-time (org-time-string-to-time deadline)))
                           (when (or (null next-deadline)
                                     (time-less-p d-time (org-time-string-to-time next-deadline)))
                             (setq next-deadline deadline)))))))))))
         nil nil)))
    (list (number-to-string total)
          (number-to-string todo)
          (number-to-string done)
          (or next-deadline "")
          (or horizon-l3 "")
          (or horizon-l4 "")
          (or horizon-l5 "")
          (or horizon-l6 ""))))

(defun pearl-gtd-review--collect-stuck-projects ()
  "Collect projects with no associated TODO actions.
Returns list of entries formatted for project table display."
  (let ((all-projects (pearl-gtd-review--collect-all-projects))
        (projects-with-todos '())
        (stuck-projects '()))
    (let ((file-path (expand-file-name "actions.org" pearl-gtd-init-base-directory)))
      (when (file-exists-p file-path)
        (with-temp-buffer
          (insert-file-contents file-path)
          (org-mode)
          (org-map-entries
           (lambda ()
             (when (pearl-gtd-core-entry-todo-p)
               (let ((proj (org-entry-get nil "PROJECT")))
                 (when proj
                   (dolist (p (split-string proj "[, ]" t))
                     (cl-pushnew p projects-with-todos :test #'string=))))))
           nil nil))))
    (dolist (proj all-projects)
      (unless (member proj projects-with-todos)
        (let ((stats (pearl-gtd-review--get-project-stats proj)))
          (push (list proj nil "actions.org"
                      (nth 0 stats)  ; Total
                      (nth 1 stats)  ; Todo
                      (nth 2 stats)  ; Done
                      (nth 3 stats)  ; Next Deadline
                      (nth 4 stats)  ; L3
                      (nth 5 stats)  ; L4
                      (nth 6 stats)  ; L5
                      (nth 7 stats)  ; L6
                      )
                stuck-projects))))
    (nreverse stuck-projects)))

(defun pearl-gtd-review--collect-active-projects ()
  "Collect projects that have associated TODO actions.
Returns list of entries formatted for project table display."
  (let ((projects-with-todos '())
        (active-projects '()))
    (let ((file-path (expand-file-name "actions.org" pearl-gtd-init-base-directory)))
      (when (file-exists-p file-path)
        (with-temp-buffer
          (insert-file-contents file-path)
          (org-mode)
          (org-map-entries
           (lambda ()
             (when (pearl-gtd-core-entry-todo-p)
               (let ((proj (org-entry-get nil "PROJECT")))
                 (when proj
                   (dolist (p (split-string proj "[, ]" t))
                     (cl-pushnew p projects-with-todos :test #'string=))))))
           nil nil))))
    (dolist (proj projects-with-todos)
      (let ((stats (pearl-gtd-review--get-project-stats proj)))
        (push (list proj nil "actions.org"
                    (nth 0 stats)  ; Total
                    (nth 1 stats)  ; Todo
                    (nth 2 stats)  ; Done
                    (nth 3 stats)  ; Next Deadline
                    (nth 4 stats)  ; L3
                    (nth 5 stats)  ; L4
                    (nth 6 stats)  ; L5
                    (nth 7 stats)  ; L6
                    )
              active-projects)))
    (nreverse active-projects)))

(defun pearl-gtd-review--collect-no-project-actions ()
  "Collect TODO actions that don't belong to any project.
Returns list of entry lists suitable for table display."
  (let ((file-path (expand-file-name "actions.org" pearl-gtd-init-base-directory))
        (entries '()))
    (when (file-exists-p file-path)
      (with-temp-buffer
        (insert-file-contents file-path)
        (org-mode)
        (org-map-entries
         (lambda ()
           (when (pearl-gtd-core-entry-todo-p)
             (let ((id (org-entry-get nil "ID"))
                   (proj (org-entry-get nil "PROJECT")))
               (when (and id (or (null proj) (string= proj "")))
                 (let ((head (org-get-heading t t))
                       (todo-state (org-get-todo-state))
                       (scheduled (org-entry-get nil "SCHEDULED"))
                       (deadline (org-entry-get nil "DEADLINE"))
                       (context (org-entry-get nil "CONTEXT"))
                       (delegated (org-entry-get nil "DELEGATED"))
                       (horizon-l3 (org-entry-get nil "HORIZON_L3")))
                   ;; Return 7 fields: head, id, file, todo-state, scheduled, deadline, context, delegated, horizon-l3
                   ;; But for table display, we need 6 fields after head/id/file
                   (push (list head id "actions.org"
                               (or todo-state "")
                               (or scheduled "")
                               (or deadline "")
                               (or context "")
                               (or delegated "")
                               (or horizon-l3 ""))
                         entries))))))
         nil nil)))
    (nreverse entries)))

(defun pearl-gtd-review--daily ()
  "Run daily review with sections: Today, Next Actions, and Inbox."
  (let* ((buffer-name "*Pearl-GTD Daily Review*")
         (today-entries (pearl-gtd-review--collect-entries-from-file
                         "actions.org"
                         (list #'pearl-gtd-core-entry-todo-p
                               #'pearl-gtd-core-entry-scheduled-today-p)
                         nil))  ; no Created field
         (next-entries (pearl-gtd-review--collect-entries-from-file
                        "actions.org"
                        (list (lambda ()
                                (and (pearl-gtd-core-entry-todo-p)
                                     (not (pearl-gtd-core-entry-scheduled-today-p)))))
                        nil))  ; no Created field
         (inbox-entries (pearl-gtd-review--collect-entries-from-file "inbox.org" nil t))  ; include Created
         (completed-today-entries (pearl-gtd-review--collect-entries-from-file
                                   "actions.org"
                                   (list #'pearl-gtd-core-entry-done-p
                                         #'pearl-gtd-core-entry-completed-today-p)
                                   nil))  ; no Created field
         (sections (list (cons "actions.org - Today" today-entries)
                         (cons "actions.org - Completed Today" completed-today-entries)
                         (cons "actions.org - Next Actions" next-entries)
                         (cons "inbox.org - Inbox" inbox-entries))))
    (pearl-gtd-review--create-table-buffer buffer-name sections)
    (with-current-buffer buffer-name
      (setq pearl-gtd-review--current-view-type 'daily))
    (pop-to-buffer buffer-name)
    (pearl-gtd-review-view-mode 1)))

(defun pearl-gtd-review--weekly ()
  "Run weekly review with comprehensive sections."
  (let* ((buffer-name "*Pearl-GTD Weekly Review*")
         ;; 1. Inbox - clear first (include Created)
         (inbox-entries (pearl-gtd-review--collect-entries-from-file "inbox.org" nil t))
         ;; 2. Overdue - urgent items (no Created)
         (overdue-entries (pearl-gtd-review--collect-entries-from-file
                           "actions.org"
                           (list #'pearl-gtd-core-entry-todo-p
                                 #'pearl-gtd-core-entry-overdue-p)
                           nil))
         ;; 3. Upcoming Deadlines (no Created)
         (upcoming-entries (pearl-gtd-review--collect-upcoming-deadlines))
         ;; 4. Completed - review accomplishments (no Created)
         (completed-entries (pearl-gtd-review--collect-entries-from-file
                             "actions.org"
                             (list #'pearl-gtd-core-entry-done-p)
                             nil))
         ;; 6. Delegated - check waiting for (no Created)
         (delegated-entries (pearl-gtd-review--collect-entries-from-file
                             "actions.org"
                             (list #'pearl-gtd-core-entry-todo-p
                                   #'pearl-gtd-core-entry-delegated-p)
                             nil))
         ;; 7. Next Actions (no Created)
         (next-entries (pearl-gtd-review--collect-entries-from-file
                        "actions.org"
                        (list (lambda ()
                                (and (pearl-gtd-core-entry-todo-p)
                                     (not (pearl-gtd-core-entry-overdue-p))
                                     (not (pearl-gtd-core-entry-delegated-p))
                                     (not (pearl-gtd-review--entry-upcoming-deadline-p)))))
                        nil))
         ;; 8. Stuck Projects
         (stuck-entries (pearl-gtd-review--collect-stuck-projects))
         ;; 9. Active Projects
         (active-entries (pearl-gtd-review--collect-active-projects))
         ;; 10. Actions without projects (include Created for No Project)
         (no-project-entries (pearl-gtd-review--collect-no-project-actions))
         ;; 11. Someday/Maybe (no Created)
         (someday-entries (pearl-gtd-review--collect-entries-from-file "someday.org" nil nil))
         ;; Build sections in GTD review order
         (sections (list (cons "inbox.org - Inbox" inbox-entries)
                         (cons "actions.org - Overdue" overdue-entries)
                         (cons "actions.org - Upcoming Deadlines" upcoming-entries)
                         (cons "actions.org - Completed" completed-entries)
                         (cons "actions.org - Delegated" delegated-entries)
                         (cons "actions.org - Next Actions" next-entries)
                         (cons "Projects - Stuck" (cons stuck-entries 'project))
                         (cons "Projects - Active" (cons active-entries 'project))
                         (cons "actions.org - No Project" no-project-entries)
                         (cons "someday.org - Someday" someday-entries))))
    (pearl-gtd-review--create-table-buffer buffer-name sections)
    (with-current-buffer buffer-name
      (setq pearl-gtd-review--current-view-type 'weekly))
    (pop-to-buffer buffer-name)
    (pearl-gtd-review-view-mode 1)))

(defun pearl-gtd-review--collect-project-entries (proj-name)
  "Collect all entries from actions.org belonging to PROJ-NAME.
PROJ-NAME is a string naming the project to search for.
Returns list of entry lists suitable for `pearl-gtd-review--insert-table-row'."
  (let ((file-path (expand-file-name "actions.org" pearl-gtd-init-base-directory))
        (entries '()))
    (when (file-exists-p file-path)
      (with-temp-buffer
        (insert-file-contents file-path)
        (org-mode)
        (org-map-entries
         (lambda ()
           (let ((id (org-entry-get nil "ID"))
                 (proj (org-entry-get nil "PROJECT")))
             (when (and id proj (member proj-name (split-string proj "[, ]" t)))
               (let ((head (org-get-heading t t))
                     (todo-state (org-get-todo-state))
                     (scheduled (org-entry-get nil "SCHEDULED"))
                     (deadline (org-entry-get nil "DEADLINE"))
                     (context (org-entry-get nil "CONTEXT"))
                     (delegated (org-entry-get nil "DELEGATED"))
                     (created (org-entry-get nil "CREATED")))
                 ;; Convert nil values to empty strings
                 ;; For project task view, include Created field
                 (push (list head id "actions.org"
                             (or todo-state "")
                             (or scheduled "")
                             (or deadline "")
                             (or context "")
                             (or delegated "")
                             proj-name
                             (or created ""))
                       entries)))))
         nil nil)))
    (nreverse entries)))

(defun pearl-gtd-review--show-project-tasks (proj-name)
  "Display all tasks for PROJ-NAME in a dedicated buffer.
PROJ-NAME is a string naming the project to display.
Creates and pops to buffer *Pearl-GTD Project: PROJ-NAME*."
  (let* ((buffer-name (format "*Pearl-GTD Project: %s*" proj-name))
         (entries (pearl-gtd-review--collect-project-entries proj-name))
         (sections (list (cons (format "actions.org - %s" proj-name) entries))))
    (pearl-gtd-review--create-table-buffer buffer-name sections)
    (with-current-buffer buffer-name
      (setq pearl-gtd-review--current-view-type nil))
    (pop-to-buffer buffer-name)
    (pearl-gtd-review-view-mode 1)))

(defun pearl-gtd-review--quit-or-return ()
  "Quit window, or return to weekly review if in project sub-view."
  (interactive)
  (if (and (boundp 'pearl-gtd-review--current-view-type)
           (null pearl-gtd-review--current-view-type))
      (progn
        (kill-buffer)
        (when (get-buffer "*Pearl-GTD Weekly Review*")
          (pop-to-buffer "*Pearl-GTD Weekly Review*")))
    (quit-window)))

(defun pearl-gtd-review--goto-task-at-point ()
  "Jump to task in source file, or show project tasks if on project row."
  (interactive)
  (save-excursion
    (beginning-of-line)
    (let ((end (line-end-position))
          (project nil))
      (while (and (< (point) end) (not project))
        (setq project (get-text-property (point) 'pearl-gtd-project))
        (forward-char 1))
      (if project
          (pearl-gtd-review--show-project-tasks project)
        (let ((entry (pearl-gtd-review--get-entry-at-point)))
          (when entry
            (let ((id (car entry))
                  (file (cdr entry)))
              (find-file (expand-file-name file pearl-gtd-init-base-directory))
              (goto-char (point-min))
              (when (re-search-forward (concat ":ID:[ \t]+" (regexp-quote id)) nil t)
                (org-back-to-heading)))))))))

(provide 'pearl-gtd-review)

;;; pearl-gtd-review.el ends here
