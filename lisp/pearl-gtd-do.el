;;; pearl-gtd-do.el --- Do/Work phase for pearl-gtd  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 OverbearingPearl

;; Author: OverbearingPearl <OverbearingPearl@outlook.com>
;; Version: 0.1.0
;; Package-Requires: ((emacs "27.1") (org "9.0"))
;; Keywords: outlines, tools, convenience, productivity, gtd, org
;; URL: https://github.com/OverbearingPearl/pearl-gtd

;;; Commentary:

;; This file handles the "Do" phase of GTD, focusing on executing tasks and viewing contexts.
;; Delegation tracking and reminders are handled in the Review phase.

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
    (define-key map (kbd "n") #'pearl-gtd-do--next-row)
    (define-key map (kbd "p") #'pearl-gtd-do--previous-row)
    (define-key map (kbd "j") #'pearl-gtd-do--next-row)
    (define-key map (kbd "k") #'pearl-gtd-do--previous-row)
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

(defun pearl-gtd-do--next-row ()
  "Move to next row in the actions table."
  (interactive)
  (let* ((boundaries (pearl-gtd-do--data-row-boundaries))
         (last-data-row (cdr boundaries)))
    (if (>= (line-beginning-position) last-data-row)
        (beep)
      (forward-line 1)
      (while (and (not (eobp))
                  (or (looking-at "|[-+]")      ; Skip separator
                      (looking-at "| Headline") ; Skip header
                      (not (looking-at "|"))))  ; Skip non-table
        (forward-line 1))
      (org-table-goto-column 1))))

(defun pearl-gtd-do--previous-row ()
  "Move to previous row in the actions table."
  (interactive)
  (let* ((boundaries (pearl-gtd-do--data-row-boundaries))
         (first-data-row (car boundaries)))
    (if (<= (line-beginning-position) first-data-row)
        (beep)
      (forward-line -1)
      (while (and (not (bobp))
                  (or (looking-at "|[-+]")      ; Skip separator
                      (looking-at "| Headline") ; Skip header
                      (not (looking-at "|"))))  ; Skip non-table
        (forward-line -1))
      (org-table-goto-column 1))))

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

(defun pearl-gtd-do--create-actions-table-buffer (contexts buffer-name)
  "Create a read-only table buffer showing actions filtered by CONTEXTS.
CONTEXTS is a list of normalized context strings (without @ prefix), or nil for all.
BUFFER-NAME is the name for the new buffer."
  (let* ((buffer (get-buffer-create buffer-name))
         (file-path (expand-file-name "actions.org" pearl-gtd-init-base-directory))
         (predicates (list #'pearl-gtd-core-entry-todo-p))
         (actions nil))
    ;; Add context predicate if contexts specified
    (when contexts
      (setq predicates
            (append predicates
                    (list (lambda () (pearl-gtd-core-entry-context-p contexts))))))
    ;; Get filtered entries
    (setq actions (pearl-gtd-core-filter-entries file-path predicates))
    ;; Create buffer with results
    (with-current-buffer buffer
      (setq buffer-read-only nil)
      (erase-buffer)
      (org-mode)
      (if (null actions)
          (insert "(No actions found)\n")
        (insert "| Headline | Context | Status | Scheduled | Delegated | Project | Created |\n")
        (insert "|----------+---------+--------+-----------+-----------+---------+---------|\n")
        (dolist (action actions)
          (let* ((raw-headline (nth 0 action))
                 (id (get-text-property 0 'pearl-gtd-id raw-headline))
                 (file "actions.org")
                 (escaped-headline (replace-regexp-in-string "|" "\\\\vert{}" raw-headline)))
            (when id
              (put-text-property 0 (length escaped-headline) 'pearl-gtd-id id escaped-headline)
              (put-text-property 0 (length escaped-headline) 'pearl-gtd-file file escaped-headline))
            (insert (format "| %s | %s | %s | %s | %s | %s | %s |\n"
                           escaped-headline
                           (nth 1 action) (nth 2 action) (nth 3 action)
                           (nth 4 action) (nth 5 action) (nth 6 action)))))
        (org-table-align))
      (setq buffer-read-only t)
      (goto-char (point-min))
      (forward-line 2)
      (setq pearl-gtd-do--current-view-type 'context
            pearl-gtd-do--current-view-contexts contexts)
      (current-buffer))))

(defun pearl-gtd-do--collect-contexts ()
  "Collect all unique context tags from actions.org."
  (pearl-gtd-core-collect-contexts
   (expand-file-name "actions.org" pearl-gtd-init-base-directory)))

(defun pearl-gtd-do--view-context (context-input)
  "Internal function to view tasks by CONTEXT-INPUT in table format.
CONTEXT-INPUT can be a single context string, comma-separated string, or nil for all.
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
  (let* ((buffer-name "*Pearl-GTD: Delegated*")
         (file-path (expand-file-name "actions.org" pearl-gtd-init-base-directory))
         (actions (pearl-gtd-core-filter-entries
                   file-path
                   (list #'pearl-gtd-core-entry-todo-p
                         #'pearl-gtd-core-entry-delegated-p))))
    (get-buffer-create buffer-name)
    (with-current-buffer buffer-name
      (setq buffer-read-only nil)
      (erase-buffer)
      (org-mode)
      (if (null actions)
          (insert "(No delegated tasks)\n")
        (insert "| Headline | Context | Status | Scheduled | Delegated | Project | Created |\n")
        (insert "|----------+---------+--------+-----------+-----------+---------+---------|\n")
        (dolist (action actions)
          (let* ((raw-headline (nth 0 action))
                 (id (get-text-property 0 'pearl-gtd-id raw-headline))
                 (file "actions.org")
                 (escaped-headline (replace-regexp-in-string "|" "\\\\vert{}" raw-headline)))
            (when id
              (put-text-property 0 (length escaped-headline) 'pearl-gtd-id id escaped-headline)
              (put-text-property 0 (length escaped-headline) 'pearl-gtd-file file escaped-headline))
            (insert (format "| %s | %s | %s | %s | %s | %s | %s |\n"
                           escaped-headline
                           (nth 1 action) (nth 2 action) (nth 3 action)
                           (nth 4 action) (nth 5 action) (nth 6 action)))))
        (org-table-align))
      (setq buffer-read-only t)
      (goto-char (point-min))
      (forward-line 2))
    (with-current-buffer buffer-name
      (setq pearl-gtd-do--current-view-type 'delegated))
    (pop-to-buffer buffer-name)
    (pearl-gtd-do-view-mode 1)))

(defun pearl-gtd-do--view-today ()
  "View actions scheduled for today in table format."
  (let* ((buffer-name "*Pearl-GTD: Today*")
         (file-path (expand-file-name "actions.org" pearl-gtd-init-base-directory))
         (actions (pearl-gtd-core-filter-entries
                   file-path
                   (list #'pearl-gtd-core-entry-todo-p
                         #'pearl-gtd-core-entry-scheduled-today-p))))
    (get-buffer-create buffer-name)
    (with-current-buffer buffer-name
      (setq buffer-read-only nil)
      (erase-buffer)
      (org-mode)
      (if (null actions)
          (insert "(No actions scheduled for today)\n")
        (insert "| Headline | Context | Status | Scheduled | Delegated | Project | Created |\n")
        (insert "|----------+---------+--------+-----------+-----------+---------+---------|\n")
        (dolist (action actions)
          (let* ((raw-headline (nth 0 action))
                 (id (get-text-property 0 'pearl-gtd-id raw-headline))
                 (file "actions.org")
                 (escaped-headline (replace-regexp-in-string "|" "\\\\vert{}" raw-headline)))
            (when id
              (put-text-property 0 (length escaped-headline) 'pearl-gtd-id id escaped-headline)
              (put-text-property 0 (length escaped-headline) 'pearl-gtd-file file escaped-headline))
            (insert (format "| %s | %s | %s | %s | %s | %s | %s |\n"
                           escaped-headline
                           (nth 1 action) (nth 2 action) (nth 3 action)
                           (nth 4 action) (nth 5 action) (nth 6 action)))))
        (org-table-align))
      (setq buffer-read-only t)
      (goto-char (point-min))
      (forward-line 2))
    (with-current-buffer buffer-name
      (setq pearl-gtd-do--current-view-type 'today))
    (pop-to-buffer buffer-name)
    (pearl-gtd-do-view-mode 1)))

(defun pearl-gtd-do--goto-task ()
  "Jump from table view to the corresponding task in actions.org."
  (interactive)
  (let ((entry (pearl-gtd-do--get-entry-at-point)))
    (when entry
      (let* ((id (car entry))
             (file (cdr entry))
             (actions-file (expand-file-name file pearl-gtd-init-base-directory)))
        (let ((buffer (find-file-noselect actions-file)))
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
      (let* ((id (car entry))
             (file (cdr entry))
             (actions-file (expand-file-name file pearl-gtd-init-base-directory)))
        (with-current-buffer (find-file-noselect actions-file)
          (goto-char (point-min))
          (when (re-search-forward (concat ":ID:[ \t]+" (regexp-quote id)) nil t)
            (org-back-to-heading)
            (let ((org-log-done 'time)) (org-todo "DONE"))
            (save-buffer)))
        (let ((inhibit-read-only t))
          (org-table-goto-column 3)
          (org-table-blank-field)
          (insert "DONE")
          (org-table-align)
          (message "Task marked as complete"))))))

(defun pearl-gtd-do--rename-task-at-point ()
  "Rename the task at point in the view buffer."
  (interactive)
  (let ((entry (pearl-gtd-do--get-entry-at-point)))
    (when entry
      (let* ((id (car entry))
             (file (cdr entry))
             (actions-file (expand-file-name file pearl-gtd-init-base-directory))
             (new-name (read-string "New task name: ")))
        (when (and new-name (not (string= new-name "")))
          (with-current-buffer (find-file-noselect actions-file)
            (goto-char (point-min))
            (when (re-search-forward (concat ":ID:[ \t]+" (regexp-quote id)) nil t)
              (org-back-to-heading)
              (org-edit-headline new-name)
              (save-buffer)
              (message "Task renamed to '%s'" new-name)))
          (pearl-gtd-do--refresh-view))))))

(provide 'pearl-gtd-do)

;;; pearl-gtd-do.el ends here
