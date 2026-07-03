;;; pearl-gtd-review.el --- Review phase for pearl-gtd  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 OverbearingPearl

;; Author: OverbearingPearl <OverbearingPearl@outlook.com>
;; Version: 0.1.0
;; Package-Requires: ((emacs "27.1") (org "9.4"))
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

(defun pearl-gtd-review--insert-table-row (head id file status scheduled deadline context delegated project created)
  "Insert a table row into the review buffer.
HEAD is the entry headline string.
ID is the unique identifier string, or nil for project rows.
FILE is the source file path string.
STATUS is the todo state string.
SCHEDULED is the scheduled date string or nil.
DEADLINE is the deadline date string or nil.
CONTEXT is the context tag string or nil.
DELEGATED is the delegation info string or nil.
PROJECT is the project name string or nil.
CREATED is the creation timestamp string or nil.

For project rows (ID is nil), attach `pearl-gtd-project' property to HEAD.
For task rows, attach `pearl-gtd-id' and `pearl-gtd-file' properties to HEAD."
  (let* ((headline-escaped (replace-regexp-in-string "|" "\\\\vert{}" head))
         (headline-with-props (copy-sequence headline-escaped)))
    (if (and (null id) head)
        (put-text-property 0 (length headline-with-props) 'pearl-gtd-project head headline-with-props)
      (progn
        (put-text-property 0 (length headline-with-props) 'pearl-gtd-id id headline-with-props)
        (put-text-property 0 (length headline-with-props) 'pearl-gtd-file file headline-with-props)))
    (insert (format "| %s | %s | %s | %s | %s | %s | %s | %s |\n"
                    headline-with-props
                    (or status "")
                    (or scheduled "")
                    (or deadline "")
                    (or context "")
                    (or delegated "")
                    (or project "")
                    (or created "")))))

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
                 (entries (if is-project (cadr section) (cdr section))))
            (insert (format "** %s\n" title))
            (if is-project
                (progn
                  (insert "| Project | Total | Todo | Done | Next Deadline | | | |\n")
                  (insert "|---------+-------+------+------+---------------+-+-+-+-|\n"))
              (progn
                (insert "| Headline | Status | Scheduled | Deadline | Context | Delegated | Project | Created |\n")
                (insert "|----------+--------+-----------+----------+---------+-----------+---------+---------|\n")))
            (if (null entries)
                (insert "| (No entries) | | | | | | | |\n")
              (dolist (entry entries)
                (apply #'pearl-gtd-review--insert-table-row entry)
                (unless is-project
                  (aset pearl-gtd-review--entry-map entry-index (cons (nth 1 entry) (nth 2 entry))))
                (setq entry-index (1+ entry-index))))
            (forward-line -1)
            (org-table-align)
            (goto-char (point-max))
            (insert "\n")))))
    (setq buffer-read-only t)
    (goto-char (point-min))
    (current-buffer)))

(defun pearl-gtd-review--collect-entries-from-file (file &optional predicates)
  "Collect entries from FILE matching PREDICATES.
Returns list of (HEAD ID FILE STATUS SCHEDULED DEADLINE CONTEXT DELEGATED PROJECT CREATED)."
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
                   (push (list head id file todo-state scheduled deadline context delegated project created)
                         entries))))))
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
         #'pearl-gtd-review--entry-upcoming-deadline-p)))

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
Returns list (TOTAL TODO DONE NEXT-DEADLINE) where:
TOTAL is the total number of entries,
TODO is the count of unfinished entries,
DONE is the count of completed entries,
NEXT-DEADLINE is the earliest deadline string or empty string."
  (let ((file-path (expand-file-name "actions.org" pearl-gtd-init-base-directory))
        (total 0)
        (done 0)
        (todo 0)
        (next-deadline nil))
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
                     (let ((deadline (org-entry-get nil "DEADLINE")))
                       (when deadline
                         (let ((d-time (org-time-string-to-time deadline)))
                           (when (or (null next-deadline)
                                     (time-less-p d-time (org-time-string-to-time next-deadline)))
                             (setq next-deadline deadline)))))))))))
         nil nil)))
    (list total todo done (or next-deadline ""))))

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
                      (number-to-string (nth 0 stats))
                      (number-to-string (nth 1 stats))
                      (number-to-string (nth 2 stats))
                      (nth 3 stats)
                      "" "" "")
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
                    (number-to-string (nth 0 stats))
                    (number-to-string (nth 1 stats))
                    (number-to-string (nth 2 stats))
                    (nth 3 stats)
                    "" "" "")
              active-projects)))
    (nreverse active-projects)))

(defun pearl-gtd-review--daily ()
  "Run daily review with sections: Today, Next Actions, and Inbox."
  (let* ((buffer-name "*Pearl-GTD Daily Review*")
         (today-entries (pearl-gtd-review--collect-entries-from-file
                         "actions.org"
                         (list #'pearl-gtd-core-entry-todo-p
                               #'pearl-gtd-core-entry-scheduled-today-p)))
         (next-entries (pearl-gtd-review--collect-entries-from-file
                        "actions.org"
                        (list (lambda ()
                                (and (pearl-gtd-core-entry-todo-p)
                                     (not (pearl-gtd-core-entry-scheduled-today-p)))))))
         (inbox-entries (pearl-gtd-review--collect-entries-from-file "inbox.org"))
         (completed-today-entries (pearl-gtd-review--collect-entries-from-file
                                   "actions.org"
                                   (list #'pearl-gtd-core-entry-done-p
                                         #'pearl-gtd-core-entry-completed-today-p)))
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
         ;; 1. Inbox - clear first
         (inbox-entries (pearl-gtd-review--collect-entries-from-file "inbox.org"))
         ;; 2. Overdue - urgent items
         (overdue-entries (pearl-gtd-review--collect-entries-from-file
                           "actions.org"
                           (list #'pearl-gtd-core-entry-todo-p
                                 #'pearl-gtd-core-entry-overdue-p)))
         ;; 3. Upcoming Deadlines
         (upcoming-entries (pearl-gtd-review--collect-upcoming-deadlines))
         ;; 4. Completed - review accomplishments
         (completed-entries (pearl-gtd-review--collect-entries-from-file
                             "actions.org"
                             (list #'pearl-gtd-core-entry-done-p)))
         ;; 6. Delegated - check waiting for
         (delegated-entries (pearl-gtd-review--collect-entries-from-file
                             "actions.org"
                             (list #'pearl-gtd-core-entry-todo-p
                                   #'pearl-gtd-core-entry-delegated-p)))
         ;; 7. Next Actions
         (next-entries (pearl-gtd-review--collect-entries-from-file
                        "actions.org"
                        (list (lambda ()
                                (and (pearl-gtd-core-entry-todo-p)
                                     (not (pearl-gtd-core-entry-overdue-p))
                                     (not (pearl-gtd-core-entry-delegated-p))
                                     (not (pearl-gtd-review--entry-upcoming-deadline-p)))))))
         ;; 8. Stuck Projects
         (stuck-entries (pearl-gtd-review--collect-stuck-projects))
         ;; 9. Active Projects
         (active-entries (pearl-gtd-review--collect-active-projects))
         ;; 10. Someday/Maybe
         (someday-entries (pearl-gtd-review--collect-entries-from-file "someday.org"))
         ;; Build sections in GTD review order
         (sections (list (cons "inbox.org - Inbox" inbox-entries)
                         (cons "actions.org - Overdue" overdue-entries)
                         (cons "actions.org - Upcoming Deadlines" upcoming-entries)
                         (cons "actions.org - Completed" completed-entries)
                         (cons "actions.org - Delegated" delegated-entries)
                         (cons "actions.org - Next Actions" next-entries)
                         (cons "Projects - Stuck" (cons stuck-entries 'project))
                         (cons "Projects - Active" (cons active-entries 'project))
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
                 (push (list head id "actions.org" todo-state scheduled deadline context delegated proj-name created)
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
