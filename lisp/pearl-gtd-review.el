;;; pearl-gtd-review.el --- Review phase for pearl-gtd  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 OverbearingPearl

;; Author: OverbearingPearl <OverbearingPearl@outlook.com>
;; Version: 0.1.0
;; Package-Requires: ((emacs "27.1") (org "9.4"))
;; Keywords: outlines, tools, convenience, productivity, gtd, org
;; URL: https://github.com/OverbearingPearl/pearl-gtd

;;; Commentary:

;; This file handles the "Review" phase of GTD, including delegation tracking and reminders.
;; Provides table-based review views with inline editing capabilities.

;;; Code:

(require 'org)
(require 'cl-lib)
(require 'pearl-gtd-init)
(require 'pearl-gtd-core)

(defvar-local pearl-gtd-review--current-view-type nil
  "Type of current review view: daily, weekly, undelegated, etc.")

(defvar-local pearl-gtd-review--current-view-params nil
  "Parameters for refreshing current view.")

(defvar-local pearl-gtd-review--row-to-entry-map nil
  "Hash table mapping row numbers to (ID . FILE) cons cells.")

(defvar pearl-gtd-review-view-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "q") #'quit-window)
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
    (define-key map (kbd "s") #'pearl-gtd-review--edit-deadline-at-point)
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
                    (looking-at "| Headline")
                    (not (looking-at "|"))))
      (forward-line 1))
    (let ((first-data (line-beginning-position)))
      (goto-char (point-max))
      (forward-line -1)
      (while (and (not (bobp))
                  (or (looking-at "|[-+]")
                      (looking-at "| Headline")
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
                      (looking-at "| Headline")
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
                      (looking-at "| Headline")
                      (not (looking-at "|"))))
        (forward-line -1))
      (org-table-goto-column 1))))

(defun pearl-gtd-review--get-entry-at-point ()
  "Get (ID . FILE) from row number at point using the row-to-entry map."
  (when pearl-gtd-review--row-to-entry-map
    ;; Find the current data row (skip header and separator)
    (let ((row (line-number-at-pos)))
      ;; Row 1 = header, Row 2 = separator, Row 3+ = data
      (when (>= row 3)
        (gethash row pearl-gtd-review--row-to-entry-map)))))

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
    (lambda ()
      ;; Use org-entry-put instead of org-set-property to avoid extra spaces
      (org-entry-put nil property value))))

(defun pearl-gtd-review--remove-property-by-id (id file property)
  "Remove PROPERTY from entry with ID in FILE."
  (pearl-gtd-review--with-entry-buffer id file
    (lambda () (org-delete-property property))))

(defun pearl-gtd-review--get-scheduled-by-id (id file)
  "Get scheduled date string for entry with ID."
  (let ((date nil))
    (pearl-gtd-review--with-entry-buffer id file
      (lambda ()
        (let ((s (org-entry-get nil "SCHEDULED")))
          (when s
            (string-match "<\\([0-9]\\{4\\}-[0-9]\\{2\\}-[0-9]\\{2\\}\\)" s)
            (setq date (match-string 1 s))))))
    date))

(defun pearl-gtd-review--get-deadline-by-id (id file)
  "Get deadline date string for entry with ID."
  (let ((date nil))
    (pearl-gtd-review--with-entry-buffer id file
      (lambda ()
        (let ((d (org-entry-get nil "DEADLINE")))
          (when d
            (string-match "<\\([0-9]\\{4\\}-[0-9]\\{2\\}-[0-9]\\{2\\}\\)" d)
            (setq date (match-string 1 d))))))
    date))

(defun pearl-gtd-review--get-headline-by-id (id file)
  "Get headline of entry with ID."
  (let ((headline nil))
    (pearl-gtd-review--with-entry-buffer id file
      (lambda () (setq headline (org-get-heading t t))))
    headline))

(defun pearl-gtd-review--edit-context-at-point ()
  "Edit context with current value as default. Empty input removes it."
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
  "Edit delegated with current value as default. Empty input removes it."
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
  "Edit scheduled date with current value as default. Empty input removes it."
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

(defun pearl-gtd-review--edit-deadline-at-point ()
  "Edit deadline with current value as default."
  (interactive)
  (let ((entry (pearl-gtd-review--get-entry-at-point)))
    (when entry
      (let* ((id (car entry))
             (file (cdr entry))
             (current-deadline (pearl-gtd-review--get-deadline-by-id id file))
             (default-value (or current-deadline ""))
             (new-value (read-string "Deadline YYYY-MM-DD (empty to remove): " default-value)))
        (pearl-gtd-review--with-entry-buffer id file
          (lambda ()
            (if (string= new-value "")
                (org-deadline '(4))
              (let ((reminder (read-string "Reminder days before: " "0")))
                (org-deadline nil new-value)
                (org-set-property "REMINDER_DAYS" reminder)))
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
  (when pearl-gtd-review--current-view-type
    (pcase pearl-gtd-review--current-view-type
      ('daily (pearl-gtd-review--daily))
      ('weekly (pearl-gtd-review--weekly))
      ('undelegated (pearl-gtd-review--undelegated))
      ('overdue (pearl-gtd-review--overdue))
      ('stuck-projects (pearl-gtd-review--stuck-projects))
      ('upcoming-deadlines (pearl-gtd-review--view-upcoming-deadlines))
      ('reminders (pearl-gtd-review--check-reminders))
      ('delegated-status (pearl-gtd-review--track-delegation-status))
      (_ (message "Cannot refresh this view")))))

(defun pearl-gtd-review--insert-table-row (head id file status scheduled deadline context delegated)
  "Insert a table row.
Note: Row-to-entry mapping is handled by the caller."
  (insert (format "| %s | %s | %s | %s | %s | %s | %s |\n"
                  (replace-regexp-in-string "|" "\\\\vert{}" head)
                  (or file "")
                  (or status "")
                  (or scheduled "")
                  (or deadline "")
                  (or context "")
                  (or delegated ""))))

(defun pearl-gtd-review--create-table-buffer (buffer-name entries)
  "Create a review table buffer with ENTRIES."
  (with-current-buffer (get-buffer-create buffer-name)
    (setq buffer-read-only nil)
    (erase-buffer)
    (org-mode)
    ;; Initialize row to entry map
    (setq pearl-gtd-review--row-to-entry-map (make-hash-table :test 'equal))
    (insert "| Headline | File | Status | Scheduled | Deadline | Context | Delegated |\n")
    (insert "|----------+------+--------+-----------+----------+---------+-----------|\n")
    (let ((row-num 3))  ; Start from row 3 (after header and separator)
      (dolist (entry entries)
        (let ((head (nth 0 entry))
              (id (nth 1 entry))
              (file (nth 2 entry))
              (status (nth 3 entry))
              (scheduled (nth 4 entry))
              (deadline (nth 5 entry))
              (context (nth 6 entry))
              (delegated (nth 7 entry)))
          (pearl-gtd-review--insert-table-row head id file status scheduled deadline context delegated)
          ;; Store mapping from row number to entry info
          (puthash row-num (cons id file) pearl-gtd-review--row-to-entry-map)
          (setq row-num (1+ row-num)))))
    (org-table-align)
    (setq buffer-read-only t)
    (goto-char (point-min))
    (current-buffer)))

(defun pearl-gtd-review--collect-entries-from-file (file &optional predicates)
  "Collect entries from FILE matching PREDICATES."
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
                     (delegated (org-entry-get nil "DELEGATED")))
                 ;; Check predicates if provided
                 (when (or (null predicates)
                           (cl-every (lambda (pred) (funcall pred)) predicates))
                   (push (list head id (file-name-nondirectory file-path)
                              todo-state scheduled deadline context delegated)
                         entries))))))
         nil nil))
      (nreverse entries))))

(defun pearl-gtd-review--daily ()
  "Run daily review in table format."
  (let ((buffer-name "*Pearl-GTD Daily Review*")
        (entries '()))
    ;; Collect today's scheduled tasks first (so they appear first in the table)
    (let ((today-entries (pearl-gtd-review--collect-entries-from-file
                          "actions.org"
                          (list #'pearl-gtd-core-entry-todo-p
                                #'pearl-gtd-core-entry-scheduled-today-p))))
      (setq entries (append entries today-entries)))
    ;; Collect inbox items
    (setq entries (append entries (pearl-gtd-review--collect-entries-from-file "inbox.org")))
    (pearl-gtd-review--create-table-buffer buffer-name entries)
    (with-current-buffer buffer-name
      (setq pearl-gtd-review--current-view-type 'daily
            pearl-gtd-review--current-view-params nil))
    (pop-to-buffer buffer-name)
    (pearl-gtd-review-view-mode 1)))

(defun pearl-gtd-review--weekly ()
  "Run weekly review across all lists in table format."
  (let ((buffer-name "*Pearl-GTD Weekly Review*")
        (entries '())
        (files '("inbox.org" "actions.org" "projects.org" "someday.org")))
    (dolist (file files)
      (setq entries (append entries (pearl-gtd-review--collect-entries-from-file file))))
    (pearl-gtd-review--create-table-buffer buffer-name entries)
    (with-current-buffer buffer-name
      (setq pearl-gtd-review--current-view-type 'weekly
            pearl-gtd-review--current-view-params nil))
    (pop-to-buffer buffer-name)
    (pearl-gtd-review-view-mode 1)))

(defun pearl-gtd-review--undelegated ()
  "Review tasks that are not delegated in table format."
  (let ((buffer-name "*Pearl-GTD: Undelegated*")
        (entries '()))
    (let ((file-path (expand-file-name "actions.org" pearl-gtd-init-base-directory)))
      (when (file-exists-p file-path)
        (with-temp-buffer
          (insert-file-contents file-path)
          (org-mode)
          (org-map-entries
           (lambda ()
             (when (and (string= (org-get-todo-state) "TODO")
                        (null (org-entry-get nil "DELEGATED")))
               (let ((head (org-get-heading t t))
                     (id (org-entry-get nil "ID")))
                 (when id
                   (push (list head id "actions.org" "TODO"
                              (org-entry-get nil "SCHEDULED")
                              (org-entry-get nil "DEADLINE")
                              (org-entry-get nil "CONTEXT")
                              nil)
                         entries)))))
           nil nil))))
    (pearl-gtd-review--create-table-buffer buffer-name entries)
    (with-current-buffer buffer-name
      (setq pearl-gtd-review--current-view-type 'undelegated
            pearl-gtd-review--current-view-params nil))
    (pop-to-buffer buffer-name)
    (pearl-gtd-review-view-mode 1)))

(defun pearl-gtd-review--overdue ()
  "Review overdue scheduled tasks in table format."
  (let ((buffer-name "*Pearl-GTD: Overdue*")
        (entries '()))
    (let ((file-path (expand-file-name "actions.org" pearl-gtd-init-base-directory)))
      (when (file-exists-p file-path)
        (with-temp-buffer
          (insert-file-contents file-path)
          (org-mode)
          (org-map-entries
           (lambda ()
             (when (and (string= (org-get-todo-state) "TODO")
                        (pearl-gtd-core-entry-overdue-p))
               (let ((head (org-get-heading t t))
                     (id (org-entry-get nil "ID")))
                 (when id
                   (push (list head id "actions.org" "TODO"
                              (org-entry-get nil "SCHEDULED")
                              (org-entry-get nil "DEADLINE")
                              (org-entry-get nil "CONTEXT")
                              (org-entry-get nil "DELEGATED"))
                         entries)))))
           nil nil))))
    (pearl-gtd-review--create-table-buffer buffer-name entries)
    (with-current-buffer buffer-name
      (setq pearl-gtd-review--current-view-type 'overdue
            pearl-gtd-review--current-view-params nil))
    (pop-to-buffer buffer-name)
    (pearl-gtd-review-view-mode 1)))

(defun pearl-gtd-review--stuck-projects ()
  "Review projects with no next actions in table format."
  (let ((buffer-name "*Pearl-GTD: Stuck Projects*")
        (entries '()))
    (let ((projects-file (expand-file-name "projects.org" pearl-gtd-init-base-directory))
          (actions-file (expand-file-name "actions.org" pearl-gtd-init-base-directory))
          (project-names '()))
      (when (and (file-exists-p projects-file) (file-exists-p actions-file))
        ;; Collect all project names from actions
        (with-temp-buffer
          (insert-file-contents actions-file)
          (org-mode)
          (org-map-entries
           (lambda ()
             (let ((proj (org-entry-get nil "PROJECT")))
               (when proj
                 (push proj project-names))))
           nil nil))
        ;; Find projects without actions
        (with-temp-buffer
          (insert-file-contents projects-file)
          (org-mode)
          (org-map-entries
           (lambda ()
             (let ((head (org-get-heading t t))
                   (id (org-entry-get nil "ID")))
               (when (and id (not (member head project-names)))
                 (push (list head id "projects.org"
                            (org-get-todo-state)
                            (org-entry-get nil "SCHEDULED")
                            (org-entry-get nil "DEADLINE")
                            (org-entry-get nil "CONTEXT")
                            (org-entry-get nil "DELEGATED"))
                       entries))))
           nil nil))))
    (pearl-gtd-review--create-table-buffer buffer-name entries)
    (with-current-buffer buffer-name
      (setq pearl-gtd-review--current-view-type 'stuck-projects
            pearl-gtd-review--current-view-params nil))
    (pop-to-buffer buffer-name)
    (pearl-gtd-review-view-mode 1)))

(defun pearl-gtd-review--set-deadline ()
  "Set deadline for current task with reminder."
  (let ((deadline (read-string "Deadline (YYYY-MM-DD): "))
        (reminder (read-string "Reminder days before: ")))
    (unless (org-at-heading-p)
      (org-back-to-heading))
    (org-deadline nil deadline)
    (org-set-property "REMINDER_DAYS" reminder)
    (save-buffer)))

(defun pearl-gtd-review--view-upcoming-deadlines ()
  "View tasks with deadlines in next 7 days in table format."
  (let* ((buffer-name "*Pearl-GTD: Upcoming Deadlines*")
         (entries '())
         (now-days (floor (/ (float-time (current-time)) 86400)))
         (seven-days-later (+ now-days 7)))
    (let ((file-path (expand-file-name "actions.org" pearl-gtd-init-base-directory)))
      (when (file-exists-p file-path)
        (with-temp-buffer
          (insert-file-contents file-path)
          (org-mode)
          (org-map-entries
           (lambda ()
             (let ((deadline (org-entry-get nil "DEADLINE")))
               (when deadline
                 (let* ((deadline-time (org-time-string-to-time deadline))
                        (deadline-days (floor (/ (float-time deadline-time) 86400))))
                   (when (and (>= deadline-days now-days)
                              (<= deadline-days seven-days-later))
                     (let ((head (org-get-heading t t))
                           (id (org-entry-get nil "ID")))
                       (when id
                         (push (list head id "actions.org"
                                    (org-get-todo-state)
                                    (org-entry-get nil "SCHEDULED")
                                    deadline
                                    (org-entry-get nil "CONTEXT")
                                    (org-entry-get nil "DELEGATED"))
                               entries))))))))
           nil nil))))
    (pearl-gtd-review--create-table-buffer buffer-name entries)
    (with-current-buffer buffer-name
      (setq pearl-gtd-review--current-view-type 'upcoming-deadlines
            pearl-gtd-review--current-view-params nil))
    (pop-to-buffer buffer-name)
    (pearl-gtd-review-view-mode 1)))

(defun pearl-gtd-review--check-reminders ()
  "Check and display reminders for due tasks in table format."
  (let ((buffer-name "*Pearl-GTD: Reminders*")
        (entries '()))
    (let ((file-path (expand-file-name "actions.org" pearl-gtd-init-base-directory)))
      (when (file-exists-p file-path)
        (with-temp-buffer
          (insert-file-contents file-path)
          (org-mode)
          (org-map-entries
           (lambda ()
             (let ((deadline (org-entry-get nil "DEADLINE"))
                   (reminder-days (org-entry-get nil "REMINDER_DAYS")))
               (when (and deadline reminder-days)
                 (let* ((deadline-time (org-time-string-to-time deadline))
                        (now (current-time))
                        (reminder-time (time-subtract deadline-time
                                                      (days-to-time (string-to-number reminder-days)))))
                   (when (time-less-p reminder-time now)
                     (let ((head (org-get-heading t t))
                           (id (org-entry-get nil "ID")))
                       (when id
                         (push (list head id "actions.org"
                                    (org-get-todo-state)
                                    (org-entry-get nil "SCHEDULED")
                                    deadline
                                    (org-entry-get nil "CONTEXT")
                                    (org-entry-get nil "DELEGATED"))
                               entries))))))))
           nil nil))))
    (pearl-gtd-review--create-table-buffer buffer-name entries)
    (with-current-buffer buffer-name
      (setq pearl-gtd-review--current-view-type 'reminders
            pearl-gtd-review--current-view-params nil))
    (pop-to-buffer buffer-name)
    (pearl-gtd-review-view-mode 1)))

(defun pearl-gtd-review--track-delegation-status ()
  "Track status of delegated tasks in table format."
  (let ((buffer-name "*Pearl-GTD: Delegated Status*")
        (entries '()))
    (let ((file-path (expand-file-name "actions.org" pearl-gtd-init-base-directory)))
      (when (file-exists-p file-path)
        (with-temp-buffer
          (insert-file-contents file-path)
          (org-mode)
          (org-map-entries
           (lambda ()
             (when (string= (org-get-todo-state) "TODO")
               (let ((delegated (org-entry-get nil "DELEGATED"))
                     (delegated-date (org-entry-get nil "DELEGATED_DATE")))
                 (when delegated
                   (let ((head (org-get-heading t t))
                         (id (org-entry-get nil "ID"))
                         (waiting-text (if delegated-date
                                           (let* ((clean-date (string-trim delegated-date "<" ">"))
                                                  (del-time (date-to-time clean-date))
                                                  (diff (time-subtract (current-time) del-time))
                                                  (days-waiting (floor (/ (float-time diff) 86400))))
                                             (format "%s (waiting %d days)" delegated days-waiting))
                                         delegated)))
                     (when id
                       (push (list head id "actions.org"
                                  "TODO"
                                  (org-entry-get nil "SCHEDULED")
                                  (org-entry-get nil "DEADLINE")
                                  (org-entry-get nil "CONTEXT")
                                  waiting-text)
                             entries)))))))
           nil nil))))
    (pearl-gtd-review--create-table-buffer buffer-name entries)
    (with-current-buffer buffer-name
      (setq pearl-gtd-review--current-view-type 'delegated-status
            pearl-gtd-review--current-view-params nil))
    (pop-to-buffer buffer-name)
    (pearl-gtd-review-view-mode 1)))

(defun pearl-gtd-review--send-delegation-reminder ()
  "Send reminder for overdue delegated task."
  (unless (org-at-heading-p)
    (org-back-to-heading))
  (let ((task (org-get-heading t t))
        (delegatee (org-entry-get nil "DELEGATED"))
        (deadline (org-entry-get nil "DEADLINE")))
    (when (and delegatee deadline task)
      (let ((deadline-time (org-time-string-to-time deadline)))
        (when (time-less-p deadline-time (current-time))
          (when (y-or-n-p (format "Send reminder to %s for task '%s'? " delegatee task))
            (org-set-property "REMINDER_SENT" (format-time-string "[%Y-%m-%d %a %H:%M]"))
            (save-buffer)))))))

(provide 'pearl-gtd-review)

;;; pearl-gtd-review.el ends here
