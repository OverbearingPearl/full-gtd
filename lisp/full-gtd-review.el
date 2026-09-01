;;; full-gtd-review.el --- Review phase for full-gtd  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 OverbearingPearl
;; Author: OverbearingPearl <OverbearingPearl@outlook.com>
;; Assisted-by: Kimi:kimi-k2.5, DeepSeek:deepseek-v3.2, Claude:claude-sonnet-4.6
;; URL: https://github.com/OverbearingPearl/full-gtd
;; SPDX-License-Identifier: MIT

;;; Commentary:

;; This file handles the "Review" phase of GTD.
;; Provides unified daily and weekly views with multiple sections.

;;; Code:

(require 'org)
(require 'cl-lib)
(require 'full-gtd-init)
(require 'full-gtd-core)
(require 'full-gtd-state)
(require 'full-gtd-ui)
(require 'full-gtd-horizons)
(require 'full-gtd-project-utils)

(defvar-local full-gtd-review--current-view-type nil
  "Type of current review view: daily, weekly, or project.")
(defvar-local full-gtd-review--current-project nil
  "Project name of the current project sub-view, if any.")

(defvar-local full-gtd-review--entry-map nil
  "Vector mapping row numbers to (ID . FILE) cons cells.")

(defvar full-gtd-review-view-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "q") #'full-gtd-review--quit-or-return)
    (define-key map (kbd "n") #'full-gtd-review--next-row)
    (define-key map (kbd "p") #'full-gtd-review--previous-row)
    (define-key map (kbd "j") #'full-gtd-review--next-row)
    (define-key map (kbd "k") #'full-gtd-review--previous-row)
    (define-key map (kbd "RET") #'full-gtd-review--goto-task-at-point)
    (define-key map (kbd "g") #'full-gtd-review--refresh-view)
    ;; Property editing with defaults
    (define-key map (kbd "c") #'full-gtd-review--edit-context-at-point)
    (define-key map (kbd "s") #'full-gtd-review--edit-scheduled-at-point)
    (define-key map (kbd "d") #'full-gtd-review--set-deadline-at-point)
    (define-key map (kbd "D") #'full-gtd-review--edit-delegated-at-point)
    (define-key map (kbd "r") #'full-gtd-review--rename-task-at-point)
    (define-key map (kbd "C") #'full-gtd-review--complete-task-at-point)
    (define-key map (kbd "P") #'full-gtd-review--edit-project-at-point)
    ;; Horizon editing
    (define-key map (kbd "3") #'full-gtd-horizons--edit-area-at-point)
    (define-key map (kbd "4") #'full-gtd-horizons--edit-goal-at-point)
    (define-key map (kbd "5") #'full-gtd-horizons--edit-vision-at-point)
    (define-key map (kbd "6") #'full-gtd-horizons--edit-purpose-at-point)
    ;; Activate someday
    (define-key map (kbd "a") #'full-gtd-review--activate-someday-at-point)
    ;; Archive project
    (define-key map (kbd "A") #'full-gtd-review--archive-project-at-point)
    (define-key map (kbd "e") #'full-gtd-review--edit-notes-at-point)
    map))

(define-minor-mode full-gtd-review-view-mode
  "Minor mode for reviewing GTD items in table format."
  :init-value nil
  :lighter " Full-Review"
  :keymap full-gtd-review-view-mode-map
  :interactive nil)

(defun full-gtd-review--data-row-boundaries ()
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

(defun full-gtd-review--get-entry-at-point ()
  "Get (ID . FILE) from current row in table using text properties."
  (save-excursion
    (beginning-of-line)
    (let ((end (line-end-position))
          (id nil)
          (file nil))
      (while (and (< (point) end)
                  (or (null id) (null file)))
        (unless id
          (setq id (get-text-property (point) 'full-gtd-id)))
        (unless file
          (setq file (get-text-property (point) 'full-gtd-file)))
        (forward-char 1))
      (when (and id file)
        (cons id file)))))

(defun full-gtd-review--put-row-metadata (marker id file project)
  "Attach row metadata after Org table alignment.
MARKER identifies an aligned data row.  ID and FILE identify task rows; PROJECT
identifies project rows."
  (when (marker-position marker)
    (goto-char marker)
    (beginning-of-line)
    (when (looking-at "|[ \t]*")
      (goto-char (match-end 0))
      (let ((start (point)))
        (when (search-forward "|" (line-end-position) t)
          (let ((end (progn
                       (skip-chars-backward " \t")
                       (point))))
            (when (< start end)
              (if id
                  (progn
                    (put-text-property start end 'full-gtd-id id)
                    (put-text-property start end 'full-gtd-file file))
                (put-text-property start end 'full-gtd-project project))))))))
  (set-marker marker nil))

(defun full-gtd-review--get-project-at-point ()
  "Return project name at point, if any."
  (save-excursion
    (beginning-of-line)
    (let ((end (line-end-position))
          (project nil))
      (while (and (not project) (< (point) end))
        (setq project (get-text-property (point) 'full-gtd-project))
        (forward-char 1))
      project)))

(defun full-gtd-review--get-property-by-id (id file property)
  "Get PROPERTY value of entry with ID in FILE."
  (full-gtd-core-with-entry-at-id id file
    (org-entry-get nil property)))

(defun full-gtd-review--set-property-by-id (id file property value)
  "Set PROPERTY to VALUE for entry with ID in FILE."
  (full-gtd-core-with-entry-at-id id file
    (org-entry-put nil property value)
    (when (and (string= property "PROJECT")
               (string= file "action.org"))
      (full-gtd-horizons--sync-entry-horizons))))

(defun full-gtd-review--remove-property-by-id (id file property)
  "Remove PROPERTY from entry with ID in FILE."
  (full-gtd-core-with-entry-at-id id file
    (org-delete-property property)
    (when (and (string= property "PROJECT")
               (string= file "action.org"))
      (full-gtd-horizons--sync-entry-horizons))))

(defun full-gtd-review--get-context-by-id (id file)
  "Return context tag (without @) for entry with ID in FILE, or nil."
  (full-gtd-core-with-entry-at-id id file
    (car (org-get-tags))))

(defun full-gtd-review--get-scheduled-by-id (id file)
  "Get scheduled date string for entry with ID in FILE."
  (full-gtd-core-with-entry-at-id id file
    (let ((s (org-entry-get nil "SCHEDULED")))
      (when s
        (string-match "<\\([0-9]\\{4\\}-[0-9]\\{2\\}-[0-9]\\{2\\}\\)" s)
        (match-string 1 s)))))

(defun full-gtd-review--get-deadline-by-id (id file)
  "Get deadline date string for entry with ID in FILE."
  (full-gtd-core-with-entry-at-id id file
    (let ((deadline (org-entry-get nil "DEADLINE")))
      (when (and deadline
                 (string-match "<\\([0-9]\\{4\\}-[0-9]\\{2\\}-[0-9]\\{2\\}\\)" deadline))
        (match-string 1 deadline)))))

(defun full-gtd-review--collect-activation-attributes (attributes)
  "Read confirmed activation attributes using ATTRIBUTES as defaults."
  (let* ((context (string-trim
                   (full-gtd-core-read-property-with-completion
                    "Context (empty to remove): " 'context
                    (or (alist-get 'context attributes) ""))))
         (schedule (let ((val (full-gtd-core-read-date 'schedule)))
                     (if val val "")))
         (deadline (let ((val (full-gtd-core-read-date 'deadline)))
                     (if val val "")))
         (delegate (string-trim
                    (full-gtd-core-read-property-with-completion
                     "Delegated to (empty to remove): " 'delegate
                     (or (alist-get 'delegate attributes) ""))))
         (project-input (string-trim
                         (full-gtd-core-read-property-with-completion
                          "Project (empty to remove): " 'project
                          (or (alist-get 'project attributes) ""))))
         (project (and (not (string-empty-p project-input))
                       (full-gtd-core--normalize-project-input project-input))))
    `((context . ,context)
      (schedule . ,schedule)
      (deadline . ,deadline)
      (delegate . ,delegate)
      (project . ,(or project "")))))

(defun full-gtd-review--apply-activation-attributes (attributes)
  "Apply confirmed activation ATTRIBUTES to the current Org entry."
  (let ((context (alist-get 'context attributes))
        (schedule (alist-get 'schedule attributes))
        (deadline (alist-get 'deadline attributes))
        (delegate (alist-get 'delegate attributes))
        (project (alist-get 'project attributes)))
    (if (string-empty-p context)
        (org-set-tags '())
      (org-set-tags (list context)))
    (if (string-empty-p delegate)
        (org-delete-property "DELEGATED")
      (org-entry-put nil "DELEGATED" delegate))
    (if (string-empty-p project)
        (org-delete-property "PROJECT")
      (org-entry-put nil "PROJECT" project))
    (if (string-empty-p schedule)
        (org-schedule '(4) nil)
      (org-schedule nil schedule))
    (if (string-empty-p deadline)
        (org-deadline '(4) nil)
      (org-deadline nil deadline))
    (org-todo (car org-not-done-keywords))))

(defun full-gtd-review--activate-someday-at-point ()
  "Activate the Someday entry at point as a TODO action."
  (interactive)
  (let ((entry (full-gtd-review--get-entry-at-point)))
    (unless entry
      (error "No entry at point"))
    (let ((someday-file (expand-file-name "someday.org"
                                          full-gtd-init-base-directory))
          (entry-file (expand-file-name (cdr entry)
                                        full-gtd-init-base-directory)))
      (let ((same-file-p (file-equal-p someday-file entry-file)))
        (unless same-file-p
          (error "Only someday entries can be activated")))
      (let* ((id (car entry))
             (context (full-gtd-review--get-context-by-id id entry-file))
             (schedule (progn
                         (let ((value (full-gtd-review--get-scheduled-by-id
                                       id entry-file)))
                           value)))
             (deadline (progn
                         (let ((value (full-gtd-review--get-deadline-by-id
                                       id entry-file)))
                           value)))
             (delegate (progn
                         (let ((value (full-gtd-review--get-property-by-id
                                       id entry-file "DELEGATED")))
                           value)))
             (project (progn
                        (let ((value (full-gtd-review--get-property-by-id
                                      id entry-file "PROJECT")))
                          value)))
             (attributes `((context . ,context)
                           (schedule . ,schedule)
                           (deadline . ,deadline)
                           (delegate . ,delegate)
                           (project . ,project)))
             (confirmed
              (progn
                (let ((value
                       (full-gtd-review--collect-activation-attributes
                        attributes)))
                  value))))
        (full-gtd-state--with-transaction '("someday.org" "action.org")
          (full-gtd-core-with-entry-at-id id entry-file
            (full-gtd-review--apply-activation-attributes confirmed)
            (full-gtd-horizons--sync-entry-horizons)
            (org-mark-subtree)
            (let ((subtree (buffer-substring-no-properties
                            (region-beginning) (region-end))))
              (delete-region (region-beginning) (region-end))
              (save-buffer)
              (full-gtd-state--with-file-buffer "action.org"
                (goto-char (point-max))
                (unless (bolp)
                  (insert "\n"))
                (insert subtree)
                (unless (bolp)
                  (insert "\n"))
                (save-buffer)))))
        (message "Activated someday entry in action.org")
        (full-gtd-review--refresh-view)))))

(defun full-gtd-review--get-headline-by-id (id file)
  "Get headline of entry with ID in FILE."
  (full-gtd-core-with-entry-at-id id file
    (org-get-heading t t)))

(defun full-gtd-review--delete-entry-by-id (id file)
  "Delete entry with ID from FILE."
  (full-gtd-core-with-entry-at-id id file
    (org-cut-subtree)
    (save-buffer)))

(defun full-gtd-review--should-delete-on-completion-p (id file)
  "Return non-nil if entry with ID in FILE should be deleted when completed.
Entries without PROJECT property should be deleted."
  (let ((project (full-gtd-review--get-property-by-id id file "PROJECT")))
    (or (null project) (string= project ""))))

(defun full-gtd-review--archive-project-at-point ()
  "Archive project at point from review view."
  (interactive)
  (let ((project (full-gtd-review--get-project-at-point)))
    (unless project
      (error "No project at point"))
    (full-gtd-project-utils--archive-project project)
    (full-gtd-review--refresh-view)))

(defmacro full-gtd-review-define-property-editor (name property prompt property-type &optional extra-cleanup)
  "Define property editor function with NAME for PROPERTY.
PROMPT is the user prompt string.
PROPERTY-TYPE is a symbol for completion (context, project, delegate,
l3, l4, l5, l6, principle).
EXTRA-CLEANUP is a form to execute when removing the property
\(e.g., also remove DELEGATED_DATE)."
  (let ((fn-name (intern (concat "full-gtd-review--edit-" name "-at-point")))
        (getter (intern (concat "full-gtd-review--get-property-by-id")))
        (setter (intern (concat "full-gtd-review--set-property-by-id")))
        (remover (intern (concat "full-gtd-review--remove-property-by-id"))))
    `(defun ,fn-name ()
       ,(format "Edit %s with current value as default.
If input is empty, remove the property."
                property)
       (interactive)
       (let ((entry (full-gtd-review--get-entry-at-point)))
         (when entry
           (let* ((id (car entry))
                  (file (cdr entry))
                  (current-value (,getter id file ,property))
                  (new-value (if ',property-type
                                (full-gtd-core-read-property-with-completion
                                 ,prompt ',property-type (or current-value ""))
                              (string-trim (read-string ,prompt (or current-value ""))))))
             (if (string= new-value "")
                 (progn
                   (,remover id file ,property)
                   ,extra-cleanup)
               (,setter id file ,property new-value))
             (full-gtd-review--refresh-view)))))))

(defun full-gtd-review--edit-context-at-point ()
  "Edit context tag with current value as default.
If input is empty, remove the property."
  (interactive)
  (let ((entry (full-gtd-review--get-entry-at-point)))
    (when entry
      (let* ((id (car entry))
             (file (cdr entry))
             (current-context (full-gtd-review--get-context-by-id id file))
             (new-context (full-gtd-core-read-property-with-completion
                           "Context (empty to remove, supports spaces, e.g., @office, @home office): "
                           'context (or current-context ""))))
        (full-gtd-core-with-entry-at-id id file
          (if (string= new-context "")
              (org-set-tags '())
            (org-set-tags (list new-context)))
          (save-buffer))
        (full-gtd-review--refresh-view)))))

(full-gtd-review-define-property-editor
   "delegated" "DELEGATED"
   (concat "Delegated to (empty to remove, supports full name, "
           "e.g., John Smith): ")
   delegate
   (full-gtd-review--remove-property-by-id id file "DELEGATED_DATE"))

(defun full-gtd-review--edit-scheduled-at-point ()
  "Edit scheduled date at point (bound to `s' in review mode).
Uses `full-gtd-core-read-date' quick keys.
If user presses RET, remove the scheduled date."
  (interactive)
  (let ((entry (full-gtd-review--get-entry-at-point)))
    (when entry
      (let* ((id (car entry))
             (file (cdr entry))
             (current-scheduled (full-gtd-review--get-scheduled-by-id id file)))
        (when current-scheduled
          (message "Current scheduled: %s" current-scheduled))
        (let ((new-date (full-gtd-core-read-date 'schedule)))
          (if new-date
              (full-gtd-core-with-entry-at-id id file
                (org-schedule nil new-date)
                (save-buffer))
            (full-gtd-core-with-entry-at-id id file
              (org-schedule '(4) nil)
              (save-buffer)))
          (full-gtd-review--refresh-view))))))

(defun full-gtd-review--set-deadline-at-point ()
  "Set deadline for task at point (bound to `d' in review mode).
Uses `full-gtd-core-read-date' quick keys.
If user presses RET, remove the deadline."
  (interactive)
  (let ((entry (full-gtd-review--get-entry-at-point)))
    (when entry
      (let* ((id (car entry))
             (file (cdr entry))
             (deadline (full-gtd-core-read-date 'deadline)))
        (if deadline
            (full-gtd-core-with-entry-at-id id file
              (org-deadline nil deadline)
              (save-buffer))
          (full-gtd-core-with-entry-at-id id file
            (org-deadline '(4) nil)
            (save-buffer)))
        (full-gtd-review--refresh-view)))))

(defun full-gtd-review--edit-notes-at-point ()
  "Edit notes (body) for task at point."
  (interactive)
  (let ((entry (full-gtd-review--get-entry-at-point)))
    (when entry
      (let ((id (car entry))
            (file (cdr entry)))
        (full-gtd-core-with-entry-at-id id file
          (full-gtd-core--edit-entry-notes)))
      (full-gtd-review--refresh-view))))

(defun full-gtd-review--rename-task-at-point ()
  "Rename task at point."
  (interactive)
  (let ((entry (full-gtd-review--get-entry-at-point)))
    (when entry
      (let* ((id (car entry))
             (file (cdr entry))
             (current-headline (full-gtd-review--get-headline-by-id id file))
             (new-name (string-trim (read-string "New task name (supports spaces, e.g., Prepare quarterly report): " current-headline))))
        (when (and new-name (not (string= new-name "")) (not (string= new-name current-headline)))
          (full-gtd-core-with-entry-at-id id file
            (org-edit-headline new-name)
            (save-buffer))
          (full-gtd-review--refresh-view))))))

(full-gtd-review-define-property-editor
   "project" "PROJECT"
   (concat "Project (empty to remove, supports spaces, use ; "
           "for multiple, e.g., Website Redesign; Q1 Goals): ")
   project
   (progn
    (full-gtd-review--remove-property-by-id id file "L3_AREA")
    (full-gtd-review--remove-property-by-id id file "L4_GOAL")
    (full-gtd-review--remove-property-by-id id file "L5_VISION")
    (full-gtd-review--remove-property-by-id id file "L6_PURPOSE")))

(defun full-gtd-review--complete-task-at-point ()
  "Mark task at point as done.
Delete task if it has no PROJECT property."
  (interactive)
  (let ((entry (full-gtd-review--get-entry-at-point)))
    (when entry
      (let ((id (car entry))
            (file (cdr entry)))
        (unless (string= file "action.org")
          (error "Only action entries can be completed"))
        (if (full-gtd-review--should-delete-on-completion-p id file)
            (progn
              (full-gtd-review--delete-entry-by-id id file)
              (message "Task deleted (no project)"))
          (full-gtd-core-with-entry-at-id id file
            (let ((org-log-done 'time))
              (org-todo 'done))
            (save-buffer)))
        (full-gtd-review--refresh-view)))))

(defun full-gtd-review--refresh-view ()
  "Refresh current review view."
  (interactive)
  (pcase full-gtd-review--current-view-type
    ('daily (full-gtd-review--daily))
    ('weekly (full-gtd-review--weekly))
    ('project (full-gtd-project-utils--show-project-tasks full-gtd-review--current-project))
    (_ (message "Cannot refresh this view"))))

(defun full-gtd-review--insert-table-row (head id file fields)
  "Insert a table row into the review buffer.
HEAD is the entry headline string.
ID is the unique identifier string, or nil for project rows.
FILE is the source file path string.
FIELDS is a list of field values in order.

For project rows (ID is nil), attach `full-gtd-project' property to HEAD.
For task rows, attach `full-gtd-id' and `full-gtd-file' properties to HEAD."
  (full-gtd-ui--insert-table-row head id file fields (null id)))

(defun full-gtd-review--build-table-data (sections)
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

(defun full-gtd-review--render-table (buffer sections-data meta)
  "Render SECTIONS-DATA into BUFFER using META."
  (let* ((entry-map (cdr (assq :entry-map meta)))
         (anchor (when (buffer-live-p buffer)
                   (with-current-buffer buffer
                     (full-gtd-ui--anchor-at-point))))
         (empty-heading-markers '()))
    (with-current-buffer buffer
      (setq buffer-read-only nil)
      (erase-buffer)
      (org-mode)
      (setq-local header-line-format
                  (pcase full-gtd-review--current-view-type
                    ('daily "Daily Review | n/p/j/k: move | RET: jump | c/s/d/D/r/e/P: property | C: complete | A: archive | g: refresh | q: quit")
                    ('weekly "Weekly Review | n/p/j/k: move | RET: jump | c/s/d/D/r/e/P/3-6: property | C: complete | a: activate someday | A: archive | g: refresh | q: quit")
                    (_ "Review | n/p/j/k: move | RET: jump | c/s/d/D/r/e/P/3-6: property | C: complete | A: archive | g: refresh | q: quit")))
      (setq full-gtd-review--entry-map entry-map)
      (if (null sections-data)
          (insert "(No entries to review)\n")
        (dolist (section sections-data)
          (let ((title (nth 0 section))
                (type (nth 1 section))
                (entries (nth 2 section))
                (heading-marker (copy-marker (point)))
                (table-marker (copy-marker (point)))
                (row-metadata '()))
            (insert (format "** %s\n" title))
            (unless entries
              (push heading-marker empty-heading-markers))
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
                  (full-gtd-review--insert-table-row head id file fields)
                  (push (list id file (and (null id) head))
                        row-metadata)))
              (org-table-align)
              (save-excursion
                (goto-char table-marker)
                (forward-line 2)
                (dolist (metadata (nreverse row-metadata))
                  (let ((row-marker (copy-marker (point))))
                    (forward-line 1)
                    (apply #'full-gtd-review--put-row-metadata
                           row-marker metadata))))
              (set-marker table-marker nil))
            (goto-char (point-max))
            (insert "\n"))))
      ;; Fold empty sections so their headings collapse automatically.
      (dolist (marker empty-heading-markers)
        (when (marker-position marker)
          (goto-char marker)
          (outline-hide-subtree)
          (set-marker marker nil)))
      (setq buffer-read-only t)
      (goto-char (point-min))
      (full-gtd-ui--restore-point-anchor anchor)
      (current-buffer))))

(defun full-gtd-review--create-table-buffer (buffer-name sections)
  "Create review buffer named BUFFER-NAME with multiple sections.
SECTIONS is a list of (TITLE . ENTRIES) or (TITLE ENTRIES . TYPE)
where TYPE can be \\='project for project sections."
  (let* ((table-data (full-gtd-review--build-table-data sections))
         (sections-data (car table-data))
         (meta (cdr table-data))
         (buffer (get-buffer-create buffer-name)))
    (full-gtd-review--render-table buffer sections-data meta)
    buffer))

(defun full-gtd-review--collect-entries-from-file (file &optional predicates include-created)
  "Collect entries from FILE matching PREDICATES.
INCLUDE-CREATED non-nil means include Created field.
Returns list of entry lists suitable for table display."
  (let* ((file-path (expand-file-name file full-gtd-init-base-directory))
         (entries (full-gtd-core-filter-entries file-path predicates)))
    (if include-created
        (mapcar (lambda (e)
                  (list (nth 0 e) (nth 7 e) (nth 8 e) (or (nth 6 e) "")))
                entries)
      (mapcar (lambda (e)
                (list (nth 0 e) (nth 7 e) (nth 8 e)
                      (or (nth 2 e) "") (or (nth 3 e) "") (or (nth 9 e) "")
                      (or (nth 10 e) "") (or (nth 4 e) "") (or (nth 5 e) "")))
              entries))))

(defun full-gtd-review--entry-upcoming-deadline-p ()
  "Return non-nil if entry has deadline within next 7 days."
  (let ((deadline (org-entry-get nil "DEADLINE")))
    (when deadline
      (let* ((deadline-time (org-time-string-to-time deadline))
             (now-days (floor (/ (float-time (current-time)) 86400)))
             (deadline-days (floor (/ (float-time deadline-time) 86400)))
             (seven-days-later (+ now-days 7)))
        (and (>= deadline-days now-days)
             (<= deadline-days seven-days-later))))))

(defun full-gtd-review--collect-upcoming-deadlines ()
  "Collect entries with deadlines in next 7 days from action.org."
  (full-gtd-review--collect-entries-from-file
   "action.org"
   (list #'full-gtd-core-entry-todo-p
         #'full-gtd-review--entry-upcoming-deadline-p)
   nil))  ; no Created field

(defun full-gtd-review--collect-all-projects ()
  "Collect all unique project names from action.org.
Supports semicolon separators (both English and Chinese)."
  (let ((actions-file (expand-file-name "action.org" full-gtd-init-base-directory))
        (projects '()))
    (when (file-exists-p actions-file)
      (with-temp-buffer
        (insert-file-contents actions-file)
        (org-mode)
        (org-map-entries
         (lambda ()
           (let ((proj (org-entry-get nil "PROJECT")))
             (when proj
               (dolist (p (full-gtd-core--split-values proj))
                 (cl-pushnew p projects :test #'string=)))))
         nil nil)))
    (nreverse projects)))

(defun full-gtd-review--get-project-stats (proj-name)
  "Get statistics for PROJ-NAME from action.org.
PROJ-NAME is a string naming the project to analyze.
Returns list (TOTAL TODO DONE NEXT-DEADLINE L3 L4 L5 L6)."
  (let ((file-path (expand-file-name "action.org" full-gtd-init-base-directory))
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
               (let ((projects (full-gtd-core--split-values proj)))
                 (when (member proj-name projects)
                   (cl-incf total)
                   (let ((todo-state (org-get-todo-state)))
                     (cond
                      ((member todo-state org-done-keywords) (cl-incf done))
                      ((member todo-state org-not-done-keywords) (cl-incf todo)))
                     ;; Collect horizon values from first TODO entry
                     (when (and (null horizon-l3) (full-gtd-core-entry-todo-p))
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

(defun full-gtd-review--collect-stuck-projects ()
  "Collect projects with no associated TODO actions.
Returns list of entries formatted for project table display."
  (let ((all-projects (full-gtd-review--collect-all-projects))
        (projects-with-todos '())
        (stuck-projects '()))
    (let ((file-path (expand-file-name "action.org" full-gtd-init-base-directory)))
      (when (file-exists-p file-path)
        (with-temp-buffer
          (insert-file-contents file-path)
          (org-mode)
          (org-map-entries
           (lambda ()
             (when (full-gtd-core-entry-todo-p)
               (let ((proj (org-entry-get nil "PROJECT")))
                 (when proj
                   (dolist (p (full-gtd-core--split-values proj))
                     (cl-pushnew p projects-with-todos :test #'string=))))))
           nil nil))))
    (dolist (proj all-projects)
      (unless (member proj projects-with-todos)
        (let ((stats (full-gtd-review--get-project-stats proj)))
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

(defun full-gtd-review--collect-active-projects ()
  "Collect projects that have associated TODO actions.
Returns list of entries formatted for project table display."
  (let ((projects-with-todos '())
        (active-projects '()))
    (let ((file-path (expand-file-name "action.org" full-gtd-init-base-directory)))
      (when (file-exists-p file-path)
        (with-temp-buffer
          (insert-file-contents file-path)
          (org-mode)
          (org-map-entries
           (lambda ()
             (when (full-gtd-core-entry-todo-p)
               (let ((proj (org-entry-get nil "PROJECT")))
                 (when proj
                   (dolist (p (full-gtd-core--split-values proj))
                     (cl-pushnew p projects-with-todos :test #'string=))))))
           nil nil))))
    (dolist (proj projects-with-todos)
      (let ((stats (full-gtd-review--get-project-stats proj)))
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

(defun full-gtd-review--collect-no-project-actions ()
  "Collect TODO actions that don't belong to any project.
Returns list of entry lists suitable for table display."
  (let* ((file-path (expand-file-name "action.org" full-gtd-init-base-directory))
         (entries (full-gtd-core-filter-entries file-path (list #'full-gtd-core-entry-todo-p))))
    (mapcar (lambda (e)
              (list (nth 0 e) (nth 7 e) (nth 8 e)
                    (or (nth 2 e) "") (or (nth 3 e) "") (or (nth 9 e) "")
                    (or (nth 10 e) "") (or (nth 4 e) "") (or (nth 11 e) "")))
            (cl-remove-if-not
             (lambda (e)
               (let ((proj (nth 5 e)))
                 (or (null proj) (string= proj ""))))
             entries))))

(defun full-gtd-review--daily ()
  "Run daily review with sections: Today, Next Actions, and Inbox."
  (let* ((buffer-name "*Full-GTD Daily Review*")
         (today-entries (full-gtd-review--collect-entries-from-file
                         "action.org"
                         (list #'full-gtd-core-entry-todo-p
                               #'full-gtd-core-entry-scheduled-today-p)
                         nil))  ; no Created field
         (next-entries (full-gtd-review--collect-entries-from-file
                        "action.org"
                        (list (lambda ()
                                (and (full-gtd-core-entry-todo-p)
                                     (not (full-gtd-core-entry-scheduled-today-p)))))
                        nil))  ; no Created field
         (inbox-entries (full-gtd-review--collect-entries-from-file "inbox.org" nil t))  ; include Created
         (completed-today-entries (full-gtd-review--collect-entries-from-file
                                   "action.org"
                                   (list #'full-gtd-core-entry-done-p
                                         #'full-gtd-core-entry-completed-today-p)
                                   nil))  ; no Created field
         (sections (list (cons "action.org - Today" today-entries)
                         (cons "action.org - Completed Today" completed-today-entries)
                         (cons "action.org - Next Actions" next-entries)
                         (cons "inbox.org - Inbox" inbox-entries))))
    (full-gtd-review--create-table-buffer buffer-name sections)
    (with-current-buffer buffer-name
      (setq full-gtd-review--current-view-type 'daily))
    (pop-to-buffer buffer-name)
    (full-gtd-review-view-mode 1)))

(defun full-gtd-review--weekly ()
  "Run weekly review with comprehensive sections."
  (let* ((buffer-name "*Full-GTD Weekly Review*")
         ;; 1. Inbox - clear first (include Created)
         (inbox-entries (full-gtd-review--collect-entries-from-file "inbox.org" nil t))
         ;; 2. Overdue - urgent items (no Created)
         (overdue-entries (full-gtd-review--collect-entries-from-file
                           "action.org"
                           (list #'full-gtd-core-entry-todo-p
                                 #'full-gtd-core-entry-overdue-p)
                           nil))
         ;; 3. Upcoming Deadlines (no Created)
         (upcoming-entries (full-gtd-review--collect-upcoming-deadlines))
         ;; 4. Completed - review accomplishments (no Created)
         (completed-entries (full-gtd-review--collect-entries-from-file
                             "action.org"
                             (list #'full-gtd-core-entry-done-p)
                             nil))
         ;; 6. Delegated - check waiting for (no Created)
         (delegated-entries (full-gtd-review--collect-entries-from-file
                             "action.org"
                             (list #'full-gtd-core-entry-todo-p
                                   #'full-gtd-core-entry-delegated-p)
                             nil))
         ;; 7. Next Actions (no Created)
         (next-entries (full-gtd-review--collect-entries-from-file
                        "action.org"
                        (list (lambda ()
                                (and (full-gtd-core-entry-todo-p)
                                     (not (full-gtd-core-entry-overdue-p))
                                     (not (full-gtd-core-entry-delegated-p))
                                     (not (full-gtd-review--entry-upcoming-deadline-p)))))
                        nil))
         ;; 8. Stuck Projects
         (stuck-entries (full-gtd-review--collect-stuck-projects))
         ;; 9. Active Projects
         (active-entries (full-gtd-review--collect-active-projects))
         ;; 10. Actions without projects (include Created for No Project)
         (no-project-entries (full-gtd-review--collect-no-project-actions))
         ;; 11. Someday/Maybe (no Created)
         (someday-entries (full-gtd-review--collect-entries-from-file "someday.org" nil nil))
         ;; 12. Reference (no Created)
         (reference-entries (full-gtd-review--collect-entries-from-file "reference.org" nil nil))
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
                         (cons "someday.org - Someday" someday-entries)
                         (cons "reference.org - Reference" reference-entries))))
    (full-gtd-review--create-table-buffer buffer-name sections)
    (with-current-buffer buffer-name
      (setq full-gtd-review--current-view-type 'weekly))
    (pop-to-buffer buffer-name)
    (full-gtd-review-view-mode 1)))

(defun full-gtd-review--quit-or-return ()
  "Quit window, or return to weekly review if in project sub-view."
  (interactive)
  (if (and (boundp 'full-gtd-review--current-view-type)
           (memq full-gtd-review--current-view-type '(nil project)))
      (progn
        (kill-buffer)
        (when (get-buffer "*Full-GTD Weekly Review*")
          (pop-to-buffer "*Full-GTD Weekly Review*")))
    (quit-window)))

(defun full-gtd-review--goto-task-at-point ()
  "Jump to task in source file, or show project tasks if on project row."
  (interactive)
  (save-excursion
    (beginning-of-line)
    (let ((end (line-end-position))
          (project nil))
      (while (and (< (point) end) (not project))
        (setq project (get-text-property (point) 'full-gtd-project))
        (forward-char 1))
      (if project
          (full-gtd-project-utils--show-project-tasks project)
        (let ((entry (full-gtd-review--get-entry-at-point)))
          (when entry
            (let ((id (car entry))
                  (file (cdr entry)))
              (find-file (expand-file-name file full-gtd-init-base-directory))
              (goto-char (point-min))
              (when (re-search-forward (concat ":ID:[ \t]+" (regexp-quote id)) nil t)
                (org-back-to-heading)))))))))

(full-gtd-core-define-table-navigators
  "full-gtd-review"
  #'full-gtd-review--data-row-boundaries
  "| Headline[ \t]*|")

(provide 'full-gtd-review)

;;; full-gtd-review.el ends here
