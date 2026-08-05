;;; pearl-gtd-review.el --- Review phase for pearl-gtd  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 OverbearingPearl
;; Author: OverbearingPearl <OverbearingPearl@outlook.com>
;; Assisted-by: Kimi:kimi-k2.5, DeepSeek:deepseek-v3.2, Claude:claude-sonnet-4.6
;; URL: https://github.com/OverbearingPearl/pearl-gtd
;; SPDX-License-Identifier: MIT

;;; Commentary:

;; This file handles the "Review" phase of GTD.
;; Provides unified daily and weekly views with multiple sections.
;; In table views, press `a' to archive a project (see
;; `pearl-gtd-review--archive-project').

;;; Code:

(require 'org)
(require 'cl-lib)
(require 'pearl-gtd-init)
(require 'pearl-gtd-core)
(require 'pearl-gtd-ui)

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
    (define-key map (kbd "3") #'pearl-gtd-horizons--edit-area-at-point)
    (define-key map (kbd "4") #'pearl-gtd-horizons--edit-goal-at-point)
    (define-key map (kbd "5") #'pearl-gtd-horizons--edit-vision-at-point)
    (define-key map (kbd "6") #'pearl-gtd-horizons--edit-purpose-at-point)
    ;; Archive project
    (define-key map (kbd "a") #'pearl-gtd-review--archive-project-at-point)
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

(defun pearl-gtd-review--get-project-at-point ()
  "Return project name at point, if any."
  (save-excursion
    (beginning-of-line)
    (let ((end (line-end-position))
          (project nil))
      (while (and (not project) (< (point) end))
        (setq project (get-text-property (point) 'pearl-gtd-project))
        (forward-char 1))
      project)))

(defun pearl-gtd-review--get-property-by-id (id file property)
  "Get PROPERTY value of entry with ID in FILE."
  (pearl-gtd-core-with-entry-at-id id file
    (org-entry-get nil property)))

(defun pearl-gtd-review--set-property-by-id (id file property value)
  "Set PROPERTY to VALUE for entry with ID in FILE."
  (pearl-gtd-core-with-entry-at-id id file
    (org-entry-put nil property value)))

(defun pearl-gtd-review--remove-property-by-id (id file property)
  "Remove PROPERTY from entry with ID in FILE."
  (pearl-gtd-core-with-entry-at-id id file
    (org-delete-property property)))

(defun pearl-gtd-review--get-scheduled-by-id (id file)
  "Get scheduled date string for entry with ID in FILE."
  (pearl-gtd-core-with-entry-at-id id file
    (let ((s (org-entry-get nil "SCHEDULED")))
      (when s
        (string-match "<\\([0-9]\\{4\\}-[0-9]\\{2\\}-[0-9]\\{2\\}\\)" s)
        (match-string 1 s)))))

(defun pearl-gtd-review--get-headline-by-id (id file)
  "Get headline of entry with ID in FILE."
  (pearl-gtd-core-with-entry-at-id id file
    (org-get-heading t t)))

(defun pearl-gtd-review--delete-entry-by-id (id file)
  "Delete entry with ID from FILE."
  (pearl-gtd-core-with-entry-at-id id file
    (org-cut-subtree)
    (save-buffer)))

(defun pearl-gtd-review--should-delete-on-completion-p (id file)
  "Return non-nil if entry with ID in FILE should be deleted when completed.
Entries without PROJECT property should be deleted."
  (let ((project (pearl-gtd-review--get-property-by-id id file "PROJECT")))
    (or (null project) (string= project ""))))

(defun pearl-gtd-review--archive-project (project)
  "Archive PROJECT from action.org to archive.org.
Archiving is allowed only when all actions of PROJECT are DONE and no
action belongs to any other project alongside PROJECT."
  (let ((action-file (expand-file-name "action.org" pearl-gtd-init-base-directory))
        (archive-file (expand-file-name "archive.org" pearl-gtd-init-base-directory)))
    (unless (file-exists-p action-file)
      (error "action.org not found"))
    (let ((archive-buffer (find-file-noselect archive-file)))
      ;; Ensure archive.org has an Org-mode project heading for PROJECT.
      (with-current-buffer archive-buffer
        (org-mode)
        (goto-char (point-min))
        (if (re-search-forward (format "^\\* %s[ \t]*$" (regexp-quote project)) nil t)
            ;; Project heading exists: move to the end of its subtree.
            (progn
              (let ((end (save-excursion (org-end-of-subtree))))
                (goto-char end)
                (when (and (not (bolp)) (not (looking-back "\n")))
                  (insert "\n"))))
          ;; Project heading does not exist: create it at the end.
          (goto-char (point-max))
          (unless (bolp) (insert "\n"))
          (insert (format "* %s\n" project))))
      ;; Process action.org.
      (pearl-gtd-state--with-file-buffer action-file
        (let ((positions '())
              (blocked nil))
          ;; First pass: validate and collect all matching entries.
          (org-map-entries
           (lambda ()
             (let ((proj (org-entry-get nil "PROJECT"))
                   (todo-state (org-get-todo-state)))
               (when (and proj (not (string= proj "")))
                 (let ((projects (pearl-gtd-core--split-values proj)))
                   (when (member project projects)
                     ;; Must be exclusive to this project.
                     (unless (and (= (length projects) 1)
                                  (string= (car projects) project))
                       (setq blocked t))
                     ;; If it is a TODO item, it must already be DONE.
                     (when todo-state
                       (unless (member todo-state org-done-keywords)
                         (setq blocked t)))
                     (push (point) positions))))))
           nil nil)
          (when blocked
            (error "Project %s cannot be archived: it has uncompleted actions or actions shared with other projects" project))
          (unless positions
            (error "No actions found for project %s" project))
          ;; Second pass: cut subtrees from bottom to top and paste them
          ;; under the project heading in archive.org.
          (dolist (pos positions)
            (goto-char pos)
            (org-cut-subtree)
            (with-current-buffer archive-buffer
              ;; Move to correct paste location.
              (goto-char (point-min))
              (re-search-forward (format "^\\* %s[ \t]*$" (regexp-quote project)) nil t)
              (org-end-of-subtree)
              (when (and (not (bolp)) (not (looking-back "\n")))
                (insert "\n"))
              (org-paste-subtree 2)
              (set-buffer-modified-p t)))
          (save-buffer)))
      ;; Save archive.org.
      (with-current-buffer archive-buffer
        (save-buffer)
        (set-buffer-modified-p nil)))
    (message "Project %s archived to archive.org" project)))

(defun pearl-gtd-review--archive-project-at-point ()
  "Archive project at point from review view."
  (interactive)
  (let ((project (pearl-gtd-review--get-project-at-point)))
    (unless project
      (error "No project at point"))
    (pearl-gtd-review--archive-project project)
    (pearl-gtd-review--refresh-view)))

(defmacro pearl-gtd-review-define-property-editor (name property prompt property-type &optional extra-cleanup)
  "Define property editor function with NAME for PROPERTY.
PROMPT is the user prompt string.
PROPERTY-TYPE is a symbol for completion (context, project, delegate,
l3, l4, l5, l6, principle).
EXTRA-CLEANUP is a form to execute when removing the property
\(e.g., also remove DELEGATED_DATE)."
  (let ((fn-name (intern (concat "pearl-gtd-review--edit-" name "-at-point")))
        (getter (intern (concat "pearl-gtd-review--get-property-by-id")))
        (setter (intern (concat "pearl-gtd-review--set-property-by-id")))
        (remover (intern (concat "pearl-gtd-review--remove-property-by-id"))))
    `(defun ,fn-name ()
       ,(format "Edit %s with current value as default. Empty input removes it." property)
       (interactive)
       (let ((entry (pearl-gtd-review--get-entry-at-point)))
         (when entry
           (let* ((id (car entry))
                  (file (cdr entry))
                  (current-value (,getter id file ,property))
                  (new-value (if ',property-type
                                (pearl-gtd-core-read-property-with-completion
                                 ,prompt ',property-type (or current-value ""))
                              (string-trim (read-string ,prompt (or current-value ""))))))
             (if (string= new-value "")
                 (progn
                   (,remover id file ,property)
                   ,extra-cleanup)
               (,setter id file ,property new-value))
             (pearl-gtd-review--refresh-view)))))))

(pearl-gtd-review-define-property-editor "context" "CONTEXT" "Context (empty to remove, supports spaces, e.g., @office, @home office): " context)

(pearl-gtd-review-define-property-editor "delegated" "DELEGATED" "Delegated to (empty to remove, supports full name, e.g., John Smith): " delegate
  (pearl-gtd-review--remove-property-by-id id file "DELEGATED_DATE"))

(defun pearl-gtd-review--edit-scheduled-at-point ()
  "Edit scheduled date with current value as default.  Empty input removes it."
  (interactive)
  (let ((entry (pearl-gtd-review--get-entry-at-point)))
    (when entry
      (let* ((id (car entry))
             (file (cdr entry))
             (current-scheduled (pearl-gtd-review--get-scheduled-by-id id file))
             (default-value (or current-scheduled ""))
             (new-value (string-trim (read-string "Schedule date (empty to remove, e.g., 2026-12-25, 2026-12-25 14:30): " default-value))))
        (pearl-gtd-core-with-entry-at-id id file
          (if (string= new-value "")
              (org-schedule '(4))
            (org-schedule nil new-value))
          (save-buffer))
        (pearl-gtd-review--refresh-view)))))

(defun pearl-gtd-review--set-deadline-at-point ()
  "Set deadline for task at point with reminder."
  (interactive)
  (let ((entry (pearl-gtd-review--get-entry-at-point)))
    (when entry
      (let* ((id (car entry))
             (file (cdr entry))
             (deadline (string-trim (read-string "Deadline (e.g., 2026-12-25, 2026-12-25 14:30): ")))
             (reminder (string-trim (read-string "Reminder days before (e.g., 3, 0 for none): " "0"))))
        (pearl-gtd-core-with-entry-at-id id file
          (org-deadline nil deadline)
          (org-set-property "REMINDER_DAYS" reminder)
          (save-buffer))
        (pearl-gtd-review--refresh-view)))))

(defun pearl-gtd-review--rename-task-at-point ()
  "Rename task at point."
  (interactive)
  (let ((entry (pearl-gtd-review--get-entry-at-point)))
    (when entry
      (let* ((id (car entry))
             (file (cdr entry))
             (current-headline (pearl-gtd-review--get-headline-by-id id file))
             (new-name (string-trim (read-string "New task name (supports spaces, e.g., Prepare quarterly report): " current-headline))))
        (when (and new-name (not (string= new-name "")) (not (string= new-name current-headline)))
          (pearl-gtd-core-with-entry-at-id id file
            (org-edit-headline new-name)
            (save-buffer))
          (pearl-gtd-review--refresh-view))))))

(pearl-gtd-review-define-property-editor "project" "PROJECT" "Project (empty to remove, supports spaces, use ; for multiple, e.g., Website Redesign; Q1 Goals): " project
  (progn
    (pearl-gtd-review--remove-property-by-id id file "L3_AREA")
    (pearl-gtd-review--remove-property-by-id id file "L4_GOAL")
    (pearl-gtd-review--remove-property-by-id id file "L5_VISION")
    (pearl-gtd-review--remove-property-by-id id file "L6_PURPOSE")))

(defun pearl-gtd-review--complete-task-at-point ()
  "Mark task at point as done. Delete task if it has no PROJECT property."
  (interactive)
  (let ((entry (pearl-gtd-review--get-entry-at-point)))
    (when entry
      (let ((id (car entry))
            (file (cdr entry)))
        (if (pearl-gtd-review--should-delete-on-completion-p id file)
            (progn
              (pearl-gtd-review--delete-entry-by-id id file)
              (message "Task deleted (no project)"))
          (pearl-gtd-core-with-entry-at-id id file
            (let ((org-log-done 'time))
              (org-todo 'done))
            (save-buffer)))
        (pearl-gtd-review--refresh-view)))))

(defun pearl-gtd-review--refresh-view ()
  "Refresh current review view."
  (interactive)
  (pcase pearl-gtd-review--current-view-type
    ('daily (pearl-gtd-review--daily))
    ('weekly (pearl-gtd-review--weekly))
    (_ (message "Cannot refresh this view"))))

(defun pearl-gtd-review--insert-table-row (head id file fields)
  "Insert a table row into the review buffer.
HEAD is the entry headline string.
ID is the unique identifier string, or nil for project rows.
FILE is the source file path string.
FIELDS is a list of field values in order.

For project rows (ID is nil), attach `pearl-gtd-project' property to HEAD.
For task rows, attach `pearl-gtd-id' and `pearl-gtd-file' properties to HEAD."
  (pearl-gtd-ui--insert-table-row head id file fields (null id)))

(defun pearl-gtd-review--build-table-data (sections)
  "Build table data from SECTIONS.
Returns SECTIONS-DATA and META.
SECTIONS-DATA is a list of \=(TITLE TYPE ENTRIES).
META is an alist with keys :entry-map and :entry-index."
  (let ((entry-map (make-vector 100 nil))
        (entry-index 0)
        (sections-data '()))
    (dolist (section sections)
      (let* ((title (car section))
             (is-project (eq (cddr section) 'project))
             (is-project-tasks (eq (cddr section) 'project-tasks))
             (entries (cond
                       (is-project (cadr section))
                       (is-project-tasks (cadr section))
                       (t (cdr section))))
             (is-no-project (string-match-p "no project" (downcase title)))
             (is-inbox (string-match-p "inbox" (downcase title)))
             (type (cond
                    (is-project 'project)
                    (is-no-project 'no-project)
                    (is-inbox 'inbox)
                    (is-project-tasks 'project-tasks)
                    (t 'standard))))
        (push (list title type entries) sections-data)
        (unless (or is-project is-no-project is-inbox)
          (dolist (entry entries)
            (aset entry-map entry-index (cons (nth 1 entry) (nth 2 entry)))
            (setq entry-index (1+ entry-index))))))
    (cons (nreverse sections-data)
          (list (cons :entry-map entry-map)
                (cons :entry-index entry-index)))))

(defun pearl-gtd-review--render-table (buffer sections-data meta)
  "Render SECTIONS-DATA into BUFFER using META."
  (let ((entry-map (cdr (assq :entry-map meta))))
    (with-current-buffer buffer
      (setq buffer-read-only nil)
      (erase-buffer)
      (org-mode)
      (setq-local header-line-format
                  (pcase pearl-gtd-review--current-view-type
                    ('daily "Daily Review | n/p/j/k: move | RET: jump | c/d/t/s/r/P: property | C: complete | a: archive | g: refresh | q: quit")
                    ('weekly "Weekly Review | n/p/j/k: move | RET: jump | c/d/t/s/r/P/3-6: property | C: complete | a: archive | g: refresh | q: quit")
                    (_ "Review | n/p/j/k: move | RET: jump | c/d/t/s/r/P/3-6: property | C: complete | a: archive | g: refresh | q: quit")))
      (setq pearl-gtd-review--entry-map entry-map)
      (if (null sections-data)
          (insert "(No entries to review)\n")
        (dolist (section sections-data)
          (let ((title (nth 0 section))
                (type (nth 1 section))
                (entries (nth 2 section)))
            (insert (format "** %s\n" title))
            (pcase type
              ('project
               (insert "| Project | Total | Todo | Done | Next Deadline | L3_AREA | L4_GOAL | L5_VISION | L6_PURPOSE |\n")
               (insert "|---------+-------+------+------+---------------+---------+---------+-----------+------------|\n"))
              ('no-project
               (insert "| Headline | Status | Scheduled | Deadline | Context | Delegated | L3_AREA |\n")
               (insert "|----------+--------+-----------+----------+---------+-----------+---------|\n"))
              ('inbox
               (insert "| Headline | Created |\n")
               (insert "|----------+---------|\n"))
              ('project-tasks
               (insert "| Headline | Status | Scheduled | Deadline | Context | Delegated | Project | Created |\n")
               (insert "|----------+--------+-----------+----------+---------+-----------+---------+---------|\n"))
              (_
               (insert "| Headline | Status | Scheduled | Deadline | Context | Delegated | Project |\n")
               (insert "|----------+--------+-----------+----------+---------+-----------+---------|\n")))
            (if (null entries)
                (progn
                  (pcase type
                    ('no-project
                     ;; 7 columns: Headline, Status, Scheduled, Deadline, Context, Delegated, L3_AREA
                     (insert "| (No entries) | | | | | | |\n"))
                    ('project
                     ;; 8 columns: Project, Total, Todo, Done, L6_PURPOSE, L5_VISION, L4_GOAL, L3_AREA
                     (insert "| (No entries) | | | | | | | |\n"))
                    ('inbox
                     ;; 2 columns: Headline, Created
                     (insert "| (No entries) | |\n"))
                    ('project-tasks
                     ;; 8 columns: Headline, Status, Scheduled, Deadline, Context, Delegated, Project, Created
                     (insert "| (No entries) | | | | | | | |\n"))
                    (_
                     ;; 7 columns: Headline, Status, Scheduled, Deadline, Context, Delegated, Project
                     (insert "| (No entries) | | | | | | |\n")))
                  (org-table-align))
              (dolist (entry entries)
                (let ((head (nth 0 entry))
                      (id (nth 1 entry))
                      (file (or (nth 2 entry) "action.org"))
                      (fields (nthcdr 3 entry)))
                  (pearl-gtd-review--insert-table-row head id file fields)))
              (org-table-align))
            (goto-char (point-max))
            (insert "\n"))))
      (setq buffer-read-only t)
      (goto-char (point-min))
      (current-buffer))))

(defun pearl-gtd-review--create-table-buffer (buffer-name sections)
  "Create review buffer named BUFFER-NAME with multiple sections.
SECTIONS is a list of (TITLE . ENTRIES) or (TITLE ENTRIES . TYPE)
where TYPE can be \\='project for project sections."
  (let* ((table-data (pearl-gtd-review--build-table-data sections))
         (sections-data (car table-data))
         (meta (cdr table-data))
         (buffer (get-buffer-create buffer-name)))
    (pearl-gtd-review--render-table buffer sections-data meta)
    buffer))

(defun pearl-gtd-review--collect-entries-from-file (file &optional predicates include-created)
  "Collect entries from FILE matching PREDICATES.
INCLUDE-CREATED non-nil means include Created field.
Returns list of entry lists suitable for table display."
  (let* ((file-path (expand-file-name file pearl-gtd-init-base-directory))
         (entries (pearl-gtd-core-filter-entries file-path predicates)))
    (if include-created
        (mapcar (lambda (e)
                  (list (nth 0 e) (nth 7 e) (nth 8 e) (or (nth 6 e) "")))
                entries)
      (mapcar (lambda (e)
                (list (nth 0 e) (nth 7 e) (nth 8 e)
                      (or (nth 2 e) "") (or (nth 3 e) "") (or (nth 9 e) "")
                      (or (nth 10 e) "") (or (nth 4 e) "") (or (nth 5 e) "")))
              entries))))

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
  "Collect entries with deadlines in next 7 days from action.org."
  (pearl-gtd-review--collect-entries-from-file
   "action.org"
   (list #'pearl-gtd-core-entry-todo-p
         #'pearl-gtd-review--entry-upcoming-deadline-p)
   nil))  ; no Created field

(defun pearl-gtd-review--collect-all-projects ()
  "Collect all unique project names from action.org.
Supports semicolon separators (both English and Chinese)."
  (let ((actions-file (expand-file-name "action.org" pearl-gtd-init-base-directory))
        (projects '()))
    (when (file-exists-p actions-file)
      (with-temp-buffer
        (insert-file-contents actions-file)
        (org-mode)
        (org-map-entries
         (lambda ()
           (let ((proj (org-entry-get nil "PROJECT")))
             (when proj
               (dolist (p (pearl-gtd-core--split-values proj))
                 (cl-pushnew p projects :test #'string=)))))
         nil nil)))
    (nreverse projects)))

(defun pearl-gtd-review--get-project-stats (proj-name)
  "Get statistics for PROJ-NAME from action.org.
PROJ-NAME is a string naming the project to analyze.
Returns list (TOTAL TODO DONE NEXT-DEADLINE L3 L4 L5 L6)."
  (let ((file-path (expand-file-name "action.org" pearl-gtd-init-base-directory))
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
               (let ((projects (pearl-gtd-core--split-values proj)))
                 (when (member proj-name projects)
                   (cl-incf total)
                   (let ((todo-state (org-get-todo-state)))
                     (cond
                      ((member todo-state org-done-keywords) (cl-incf done))
                      ((member todo-state org-not-done-keywords) (cl-incf todo)))
                     ;; Collect horizon values from first TODO entry
                     (when (and (null horizon-l3) (pearl-gtd-core-entry-todo-p))
                       (setq horizon-l3 (org-entry-get nil "L3_AREA"))
                       (setq horizon-l4 (org-entry-get nil "L4_GOAL"))
                       (setq horizon-l5 (org-entry-get nil "L5_VISION"))
                       (setq horizon-l6 (org-entry-get nil "L6_PURPOSE")))
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
    (let ((file-path (expand-file-name "action.org" pearl-gtd-init-base-directory)))
      (when (file-exists-p file-path)
        (with-temp-buffer
          (insert-file-contents file-path)
          (org-mode)
          (org-map-entries
           (lambda ()
             (when (pearl-gtd-core-entry-todo-p)
               (let ((proj (org-entry-get nil "PROJECT")))
                 (when proj
                   (dolist (p (pearl-gtd-core--split-values proj))
                     (cl-pushnew p projects-with-todos :test #'string=))))))
           nil nil))))
    (dolist (proj all-projects)
      (unless (member proj projects-with-todos)
        (let ((stats (pearl-gtd-review--get-project-stats proj)))
          (push (list proj nil "action.org"
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
    (let ((file-path (expand-file-name "action.org" pearl-gtd-init-base-directory)))
      (when (file-exists-p file-path)
        (with-temp-buffer
          (insert-file-contents file-path)
          (org-mode)
          (org-map-entries
           (lambda ()
             (when (pearl-gtd-core-entry-todo-p)
               (let ((proj (org-entry-get nil "PROJECT")))
                 (when proj
                   (dolist (p (pearl-gtd-core--split-values proj))
                     (cl-pushnew p projects-with-todos :test #'string=))))))
           nil nil))))
    (dolist (proj projects-with-todos)
      (let ((stats (pearl-gtd-review--get-project-stats proj)))
        (push (list proj nil "action.org"
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
  (let* ((file-path (expand-file-name "action.org" pearl-gtd-init-base-directory))
         (entries (pearl-gtd-core-filter-entries file-path (list #'pearl-gtd-core-entry-todo-p))))
    (mapcar (lambda (e)
              (list (nth 0 e) (nth 7 e) (nth 8 e)
                    (or (nth 2 e) "") (or (nth 3 e) "") (or (nth 9 e) "")
                    (or (nth 10 e) "") (or (nth 4 e) "") (or (nth 11 e) "")))
            (cl-remove-if-not
             (lambda (e)
               (let ((proj (nth 5 e)))
                 (or (null proj) (string= proj ""))))
             entries))))

(defun pearl-gtd-review--daily ()
  "Run daily review with sections: Today, Next Actions, and Inbox."
  (let* ((buffer-name "*Pearl-GTD Daily Review*")
         (today-entries (pearl-gtd-review--collect-entries-from-file
                         "action.org"
                         (list #'pearl-gtd-core-entry-todo-p
                               #'pearl-gtd-core-entry-scheduled-today-p)
                         nil))  ; no Created field
         (next-entries (pearl-gtd-review--collect-entries-from-file
                        "action.org"
                        (list (lambda ()
                                (and (pearl-gtd-core-entry-todo-p)
                                     (not (pearl-gtd-core-entry-scheduled-today-p)))))
                        nil))  ; no Created field
         (inbox-entries (pearl-gtd-review--collect-entries-from-file "inbox.org" nil t))  ; include Created
         (completed-today-entries (pearl-gtd-review--collect-entries-from-file
                                   "action.org"
                                   (list #'pearl-gtd-core-entry-done-p
                                         #'pearl-gtd-core-entry-completed-today-p)
                                   nil))  ; no Created field
         (sections (list (cons "action.org - Today" today-entries)
                         (cons "action.org - Completed Today" completed-today-entries)
                         (cons "action.org - Next Actions" next-entries)
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
                           "action.org"
                           (list #'pearl-gtd-core-entry-todo-p
                                 #'pearl-gtd-core-entry-overdue-p)
                           nil))
         ;; 3. Upcoming Deadlines (no Created)
         (upcoming-entries (pearl-gtd-review--collect-upcoming-deadlines))
         ;; 4. Completed - review accomplishments (no Created)
         (completed-entries (pearl-gtd-review--collect-entries-from-file
                             "action.org"
                             (list #'pearl-gtd-core-entry-done-p)
                             nil))
         ;; 6. Delegated - check waiting for (no Created)
         (delegated-entries (pearl-gtd-review--collect-entries-from-file
                             "action.org"
                             (list #'pearl-gtd-core-entry-todo-p
                                   #'pearl-gtd-core-entry-delegated-p)
                             nil))
         ;; 7. Next Actions (no Created)
         (next-entries (pearl-gtd-review--collect-entries-from-file
                        "action.org"
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
                         (cons "action.org - Overdue" overdue-entries)
                         (cons "action.org - Upcoming Deadlines" upcoming-entries)
                         (cons "action.org - Completed" completed-entries)
                         (cons "action.org - Delegated" delegated-entries)
                         (cons "action.org - Next Actions" next-entries)
                         (cons "Projects - Stuck" (cons stuck-entries 'project))
                         (cons "Projects - Active" (cons active-entries 'project))
                         (cons "action.org - No Project" no-project-entries)
                         (cons "someday.org - Someday" someday-entries))))
    (pearl-gtd-review--create-table-buffer buffer-name sections)
    (with-current-buffer buffer-name
      (setq pearl-gtd-review--current-view-type 'weekly))
    (pop-to-buffer buffer-name)
    (pearl-gtd-review-view-mode 1)))

(defun pearl-gtd-review--collect-project-entries (proj-name)
  "Collect all entries from action.org belonging to PROJ-NAME.
PROJ-NAME is a string naming the project to search for.
Returns list of entry lists suitable for `pearl-gtd-review--insert-table-row'."
  (let* ((file-path (expand-file-name "action.org" pearl-gtd-init-base-directory))
         (entries (pearl-gtd-core-filter-entries file-path nil)))
    (mapcar (lambda (e)
              (list (nth 0 e) (nth 7 e) (nth 8 e)
                    (or (nth 2 e) "") (or (nth 3 e) "") (or (nth 9 e) "")
                    (or (nth 10 e) "") (or (nth 4 e) "") proj-name
                    (or (nth 6 e) "")))
            (cl-remove-if-not
             (lambda (e)
               (let ((proj (nth 5 e)))
                 (and proj (member proj-name (pearl-gtd-core--split-values proj)))))
             entries))))

(defun pearl-gtd-review--show-project-tasks (proj-name)
  "Display all tasks for PROJ-NAME in a dedicated buffer.
PROJ-NAME is a string naming the project to display.
Creates and pops to buffer *Pearl-GTD Project: PROJ-NAME*."
  (let* ((buffer-name (format "*Pearl-GTD Project: %s*" proj-name))
         (entries (pearl-gtd-review--collect-project-entries proj-name))
         (sections (list (cons (format "action.org - %s" proj-name) (cons entries 'project-tasks)))))
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

(pearl-gtd-core-define-table-navigators
  "pearl-gtd-review"
  #'pearl-gtd-review--data-row-boundaries
  "| Headline[ \t]*|")

(provide 'pearl-gtd-review)

;;; pearl-gtd-review.el ends here
