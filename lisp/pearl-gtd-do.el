;;; pearl-gtd-do.el --- Do/Work phase for pearl-gtd  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 OverbearingPearl
;; Author: OverbearingPearl <OverbearingPearl@outlook.com>
;; Assisted-by: Kimi:kimi-k2.5, DeepSeek:deepseek-v3.2, Claude:claude-sonnet-4.6
;; URL: https://github.com/OverbearingPearl/pearl-gtd
;; SPDX-License-Identifier: MIT

;;; Commentary:

;; This file handles the "Do" phase of GTD, focusing on executing
;; tasks and viewing contexts.  Delegation tracking and reminders are
;; handled in the Review phase.

;;; Code:

(require 'org)
(require 'cl-lib)
(require 'pearl-gtd-init)
(require 'pearl-gtd-core)

(defvar-local pearl-gtd-do--current-view-type nil
  "Type of the current view: `context, `delegated, `today, etc.")

(defvar-local pearl-gtd-do--current-view-contexts nil
  "Contexts used for the current view buffer when type is `context.")

(defvar pearl-gtd-do-view-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "q") #'quit-window)
    (define-key map (kbd "n") #'pearl-gtd-do-next-row)
    (define-key map (kbd "p") #'pearl-gtd-do-previous-row)
    (define-key map (kbd "j") #'pearl-gtd-do-next-row)
    (define-key map (kbd "k") #'pearl-gtd-do-previous-row)
    (define-key map (kbd "C") #'pearl-gtd-do--complete-task-at-point)
    (define-key map (kbd "RET") #'pearl-gtd-do--goto-task)
    (define-key map (kbd "g") #'pearl-gtd-do--refresh-view)
    (define-key map (kbd "r") #'pearl-gtd-do--rename-task-at-point)
    map))

(define-minor-mode pearl-gtd-do-view-mode
  "Minor mode for viewing GTD actions in table format."
  :init-value nil
  :lighter " Pearl-Do"
  :keymap pearl-gtd-do-view-mode-map
  :interactive nil)

(defun pearl-gtd-do--data-row-boundaries ()
  "Return cons cell (FIRST-DATA-ROW . LAST-DATA-ROW) positions.
FIRST-DATA-ROW is the position of the first data row in the table.
LAST-DATA-ROW is the position of the last data row in the table."
  (save-excursion
    (goto-char (point-min))
    ;; Skip header and separator to find first data row
    (while (and (not (eobp))
                (or (looking-at "|[-+]")      ; Separator
                    (looking-at "| Headline") ; Header
                    (not (looking-at "|"))))  ; Non-table
      (forward-line 1))
    (let ((first-data (line-beginning-position)))
      ;; Find last data row from end of buffer
      (goto-char (point-max))
      (forward-line -1)
      (while (and (not (bobp))
                  (or (looking-at "|[-+]")      ; Separator
                      (looking-at "| Headline") ; Header
                      (not (looking-at "|"))    ; Non-table
                      (looking-at "^$")))       ; Empty line
        (forward-line -1))
      (cons first-data (line-beginning-position)))))

(defun pearl-gtd-do--get-entry-at-point ()
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

(defun pearl-gtd-do--build-table-data (predicates)
  "Build table data from actions.org filtered by PREDICATES.
Returns (HEADER . ROWS) where ROWS is list of
\(HEADLINE CONTEXT STATUS SCHEDULED DELEGATED PROJECT CREATED ID FILE)."
  (let* ((file-path (expand-file-name "actions.org" pearl-gtd-init-base-directory))
         (entries (pearl-gtd-core-filter-entries file-path predicates))
         (header "| Headline | Context | Status | Scheduled | Delegated | Project | Created |")
         (rows '()))
    (dolist (entry entries)
      (let* ((raw-headline (nth 0 entry))
             (id (nth 7 entry))
             (file (nth 8 entry))
             (escaped-headline (replace-regexp-in-string "|" "\\\\vert{}" raw-headline)))
        (push (list escaped-headline (nth 1 entry) (nth 2 entry) (nth 3 entry)
                   (nth 4 entry) (nth 5 entry) (nth 6 entry) id file)
              rows)))
    (cons header (nreverse rows))))

(defun pearl-gtd-do--render-table (buffer table-data)
  "Render TABLE-DATA into BUFFER.  TABLE-DATA is (HEADER . ROWS)."
  (let ((header (car table-data))
        (rows (cdr table-data)))
    (with-current-buffer buffer
      (setq buffer-read-only nil)
      (erase-buffer)
      (org-mode)
      (insert header "\n")
      (insert "|----------+---------+--------+-----------+-----------+---------+---------|\n")
      (dolist (row rows)
        (let ((escaped-headline (nth 0 row))
              (id (nth 7 row))
              (file (nth 8 row)))
          (when id
            (put-text-property 0 (length escaped-headline) 'pearl-gtd-id id escaped-headline)
            (put-text-property 0 (length escaped-headline) 'pearl-gtd-file file escaped-headline))
          (insert (format "| %s | %s | %s | %s | %s | %s | %s |\n"
                          escaped-headline
                          (nth 1 row) (nth 2 row) (nth 3 row)
                          (nth 4 row) (nth 5 row) (nth 6 row)))))
      (org-table-align)
      (setq buffer-read-only t)
      (goto-char (point-min))
      (forward-line 2))))

(defun pearl-gtd-do--create-view-buffer (buffer-name predicates view-type
                                                  &optional empty-msg contexts)
  "Create a read-only table buffer showing actions filtered by PREDICATES.
BUFFER-NAME is the name of the buffer to create.
PREDICATES is a list of predicate functions to filter entries.
VIEW-TYPE is a symbol indicating the type of view.
Optional EMPTY-MSG is the message to display when no actions
are found.  Optional CONTEXTS is a list of contexts for the
view."
  (let* ((buffer (get-buffer-create buffer-name))
         (table-data (pearl-gtd-do--build-table-data predicates)))
    (if (null (cdr table-data))
        (with-current-buffer buffer
          (setq buffer-read-only nil)
          (erase-buffer)
          (insert (format "%s\n" (or empty-msg "(No actions found)")))
          (setq buffer-read-only t))
      (pearl-gtd-do--render-table buffer table-data))
    (with-current-buffer buffer
      (setq-local header-line-format
                  (pcase view-type
                    ('context "Context View | n/p/j/k: navigate | RET: jump | C: complete | r: rename | g: refresh | q: quit")
                    ('delegated "Delegated View | n/p/j/k: navigate | RET: jump | C: complete | r: rename | g: refresh | q: quit")
                    ('today "Today View | n/p/j/k: navigate | RET: jump | C: complete | r: rename | g: refresh | q: quit")
                    (_ "Actions View | n/p/j/k: navigate | RET: jump | C: complete | r: rename | g: refresh | q: quit")))
      (setq pearl-gtd-do--current-view-type view-type
            pearl-gtd-do--current-view-contexts contexts))
    buffer))

(defun pearl-gtd-do--create-actions-table-buffer (contexts buffer-name)
  "Create a read-only table buffer showing actions filtered by CONTEXTS.
CONTEXTS is a list of normalized context strings (without @ prefix),
or nil for all.
BUFFER-NAME is the name for the new buffer."
  (let ((predicates (list #'pearl-gtd-core-entry-todo-p)))
    (when contexts
      (setq predicates
            (append predicates
                    (list (lambda () (pearl-gtd-core-entry-context-p contexts))))))
    (pearl-gtd-do--create-view-buffer buffer-name predicates 'context "(No actions found)" contexts)))

(defun pearl-gtd-do--collect-contexts ()
  "Collect all unique context tags from actions.org."
  (pearl-gtd-core-collect-contexts
   (expand-file-name "actions.org" pearl-gtd-init-base-directory)))

(defun pearl-gtd-do--view-context (context-input)
  "Internal function to view tasks by CONTEXT-INPUT in table format.
CONTEXT-INPUT can be a single context string, comma-separated string,
or nil for all.
Context tags are normalized by removing the @ prefix for matching."
  (let* ((raw-input context-input)
         (contexts (cond
                    ((null context-input) nil)
                    ((listp context-input) context-input)
                    ((string-match-p "," context-input)
                     (mapcar #'string-trim (split-string context-input "," t)))
                    (t (list context-input))))
         (normalized-contexts (when contexts
                               (mapcar (lambda (c)
                                        (if (string-prefix-p "@" c)
                                            (substring c 1)
                                          c))
                                      contexts)))
         (display-name (cond
                       ((null raw-input) "All Actions")
                       ((listp raw-input) (mapconcat #'identity raw-input ", "))
                       (t raw-input)))
         (buffer-name (format "*Pearl-GTD: %s*" display-name)))
    (pop-to-buffer (pearl-gtd-do--create-actions-table-buffer normalized-contexts buffer-name))
    (pearl-gtd-do-view-mode 1)))

(defun pearl-gtd-do--view-by-context ()
  "View next actions filtered by a specific context."
  (let ((contexts (pearl-gtd-do--collect-contexts)))
    (when contexts
      (let ((context (completing-read "Select context: " contexts)))
        (pearl-gtd-do--view-context context)))))

(defun pearl-gtd-do--view-all-actions ()
  "View all next actions regardless of context."
  (pearl-gtd-do--view-context nil))

(defun pearl-gtd-do--view-delegated ()
  "View all delegated tasks in table format."
  (let ((buffer-name "*Pearl-GTD: Delegated*")
        (predicates (list #'pearl-gtd-core-entry-todo-p
                          #'pearl-gtd-core-entry-delegated-p)))
    (pop-to-buffer (pearl-gtd-do--create-view-buffer buffer-name predicates 'delegated "(No delegated tasks)"))
    (pearl-gtd-do-view-mode 1)))

(defun pearl-gtd-do--view-today ()
  "View actions scheduled for today in table format."
  (let ((buffer-name "*Pearl-GTD: Today*")
        (predicates (list #'pearl-gtd-core-entry-todo-p
                          #'pearl-gtd-core-entry-scheduled-today-p)))
    (pop-to-buffer (pearl-gtd-do--create-view-buffer buffer-name predicates 'today "(No actions scheduled for today)"))
    (pearl-gtd-do-view-mode 1)))

(defun pearl-gtd-do--goto-task ()
  "Jump from table view to the corresponding task in actions.org."
  (interactive)
  (let ((entry (pearl-gtd-do--get-entry-at-point)))
    (when entry
      (let* ((id (car entry))
             (file (cdr entry)))
        (let ((buffer (find-file-noselect (expand-file-name file pearl-gtd-init-base-directory))))
          (pop-to-buffer buffer)
          (goto-char (point-min))
          (if (re-search-forward (concat ":ID:[ \t]+" (regexp-quote id)) nil t)
              (progn (org-back-to-heading) (message "Jumped to task"))
            (message "Task not found in actions.org")))))))

(defun pearl-gtd-do--complete-task-at-point ()
  "Mark the task at point as complete in the view buffer."
  (interactive)
  (let ((entry (pearl-gtd-do--get-entry-at-point)))
    (when entry
      (let ((id (car entry))
            (file (cdr entry)))
        (pearl-gtd-core-with-entry-at-id id file
          (let ((org-log-done 'time)) (org-todo 'done)))
        (let ((inhibit-read-only t))
          (org-table-goto-column 3)
          (org-table-blank-field)
          (insert "DONE")
          (org-table-align)
          (message "Task marked as complete"))))))

(defun pearl-gtd-do--refresh-view ()
  "Refresh the current view buffer based on its type."
  (interactive)
  (pcase pearl-gtd-do--current-view-type
    ('context
     (pearl-gtd-do--view-context pearl-gtd-do--current-view-contexts))
    ('delegated
     (pearl-gtd-do--view-delegated))
    ('today
     (pearl-gtd-do--view-today))
    (_
     (pearl-gtd-do--view-all-actions))))

(defun pearl-gtd-do--rename-task-at-point ()
  "Rename the task at point in the view buffer."
  (interactive)
  (let ((entry (pearl-gtd-do--get-entry-at-point)))
    (when entry
      (let* ((id (car entry))
             (file (cdr entry))
             (new-name (read-string "New task name (supports spaces, e.g., Buy organic milk from Whole Foods): ")))
        (when (and new-name (not (string= new-name "")))
          (pearl-gtd-core-with-entry-at-id id file
            (org-edit-headline new-name))
          (pearl-gtd-do--refresh-view))))))

(pearl-gtd-core-define-table-navigators
  "pearl-gtd-do"
  #'pearl-gtd-do--data-row-boundaries
  "| Headline")

(provide 'pearl-gtd-do)

;;; pearl-gtd-do.el ends here
