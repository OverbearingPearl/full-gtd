;;; pearl-gtd-do.el --- Do/Work phase for pearl-gtd  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 OverbearingPearl

;; Author: OverbearingPearl <OverbearingPearl@outlook.com>
;; Version: 0.1.0
;; Package-Requires: ((emacs "27.1") (org "9.4"))
;; Keywords: outlines, tools, convenience, productivity, gtd, org
;; URL: https://github.com/OverbearingPearl/pearl-gtd

;;; Commentary:

;; This file handles the "Do" phase of GTD, focusing on executing tasks and viewing contexts.
;; Delegation tracking and reminders are handled in the Review phase.

;;; Code:

(require 'org)
(require 'cl-lib)
(require 'pearl-gtd-init)

(defvar pearl-gtd-do-view-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "n") (lambda () (interactive) (pearl-gtd-do--next-row)))
    (define-key map (kbd "p") (lambda () (interactive) (pearl-gtd-do--previous-row)))
    (define-key map (kbd "j") (lambda () (interactive) (pearl-gtd-do--next-row)))
    (define-key map (kbd "k") (lambda () (interactive) (pearl-gtd-do--previous-row)))
    (define-key map (kbd "c") (lambda () (interactive) (pearl-gtd-do--complete-task-at-point)))
    (define-key map (kbd "q") 'quit-window)
    map))

(define-minor-mode pearl-gtd-do-view-mode
  "Minor mode for viewing GTD actions in table format."
  :init-value nil
  :lighter " Pearl-Do"
  :keymap pearl-gtd-do-view-mode-map)

(defun pearl-gtd-do--next-row ()
  "Move to next row in the actions table."
  (forward-line 1)
  (when (eobp)
    (forward-line -1)
    (beep))
  (beginning-of-line)
  (when (looking-at "|[-+]")  ; Skip separator lines
    (forward-line 1)
    (when (eobp)
      (forward-line -1)))
  (org-table-goto-column 1))

(defun pearl-gtd-do--previous-row ()
  "Move to previous row in the actions table."
  (forward-line -1)
  (when (bobp)
    (forward-line 1)
    (beep))
  (beginning-of-line)
  (when (looking-at "|[-+]")  ; Skip separator lines
    (forward-line -1)
    (when (bobp)
      (forward-line 1)))
  (org-table-goto-column 1))

(defun pearl-gtd-do--complete-task-at-point ()
  "Mark the task at point as complete."
  (let ((headline (string-trim (org-table-get-field 1))))
    (when (and headline (not (string= headline "")))
      (let ((actions-file (expand-file-name "actions.org" pearl-gtd-init-base-directory)))
        (when (file-exists-p actions-file)
          (with-current-buffer (find-file-noselect actions-file)
            (goto-char (point-min))
            (when (re-search-forward (concat "^\\*+ " (regexp-quote headline) "\\($\\| \\)") nil t)
              (let ((org-log-done 'time))
                (org-todo "DONE"))
              (save-buffer)))))
      (let ((inhibit-read-only t))
        (org-table-goto-column 3)  ; Status column
        (org-table-blank-field)
        (insert "DONE")
        (org-table-align)
        (message "Task marked as complete")))))

(defun pearl-gtd-do--create-actions-table-buffer (contexts buffer-name)
  "Create a read-only table buffer showing actions filtered by CONTEXTS.
CONTEXTS is a list of normalized context strings (without @ prefix), or nil for all.
BUFFER-NAME is the name for the new buffer."
  (let ((buffer (get-buffer-create buffer-name))
        (actions '()))
    (message "DEBUG: Starting table creation for contexts: %S" contexts)
    (dolist (file '("actions.org"))
      (let ((file-path (expand-file-name file pearl-gtd-init-base-directory)))
        (message "DEBUG: Checking file: %s" file-path)
        (message "DEBUG: File exists? %s" (file-exists-p file-path))
        (when (file-exists-p file-path)
          (with-temp-buffer
            (insert-file-contents file-path)
            (message "DEBUG: File contents: %s" (replace-regexp-in-string "\n" "\\\\n" (buffer-string)))
            (org-mode)
            (message "DEBUG: org-mode activated, starting map-entries")
            (org-map-entries
             (lambda ()
               (message "DEBUG: Processing entry at point")
               (let* ((head (org-get-heading t t))
                      (tags (org-get-tags-at))
                      (todo-state (org-get-todo-state))
                      (scheduled (org-entry-get nil "SCHEDULED"))
                      (delegated (org-entry-get nil "DELEGATED"))
                      (matching-contexts (when contexts
                                          (cl-intersection tags contexts :test #'string=))))
                 (message "DEBUG: head=%S, tags=%S, todo-state=%S" head tags todo-state)
                 (message "DEBUG: matching-contexts=%S" matching-contexts)
                 (when (and (string= todo-state "TODO")
                            (or (null contexts) matching-contexts))
                   (message "DEBUG: Adding action to list")
                   (push (list head
                              (if matching-contexts
                                  (mapconcat (lambda (c) (concat "@" c)) matching-contexts ",")
                                "")
                              (or todo-state "")
                              (or scheduled "")
                              (or delegated ""))
                         actions))))
             nil nil)  ; Changed from nil 'file to nil nil
            (message "DEBUG: Finished map-entries, actions count: %d" (length actions))))))
    (message "DEBUG: Final actions list: %S" actions)
    ;; Create buffer with table
    (with-current-buffer buffer
      (setq buffer-read-only nil)  ; Ensure we can modify the buffer
      (erase-buffer)
      (org-mode)
      (if (null actions)
          (insert "(No actions found)\n")
        (insert "| Headline | Context | Status | Scheduled | Delegated |\n")
        (insert "|----------+---------+--------+-----------+-----------|\n")
        (dolist (action (nreverse actions))
          (insert (format "| %s | %s | %s | %s | %s |\n"
                         (replace-regexp-in-string "|" "\\\\vert{}" (nth 0 action))
                         (nth 1 action)
                         (nth 2 action)
                         (nth 3 action)
                         (nth 4 action))))
        (org-table-align))
      (setq buffer-read-only t)
      (goto-char (point-min))
      (forward-line 1)  ; Move to first data row
      (current-buffer))))

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
  (let ((context (completing-read "Select context: " '("@office" "@home" "@errands" "@computer"))))
    (pearl-gtd-do--view-context context)))

(defun pearl-gtd-do--view-by-contexts ()
  "View next actions filtered by multiple contexts."
  (let ((contexts (completing-read "Select contexts (comma separated): " '("@office" "@home" "@errands" "@computer"))))
    (pearl-gtd-do--view-context contexts)))

(defun pearl-gtd-do--view-all-actions ()
  "View all next actions regardless of context."
  (pearl-gtd-do--view-context nil))

(defun pearl-gtd-do--view-delegated ()
  "View all delegated tasks in table format."
  (let ((buffer-name "*Pearl-GTD: Delegated*")
        (actions '()))
    (dolist (file '("actions.org"))
      (let ((file-path (expand-file-name file pearl-gtd-init-base-directory)))
        (when (file-exists-p file-path)
          (with-temp-buffer
            (insert-file-contents file-path)
            (org-mode)
            (org-map-entries
             (lambda ()
               (let* ((head (org-get-heading t t))
                      (tags (org-get-tags-at))
                      (todo-state (org-get-todo-state))
                      (scheduled (org-entry-get nil "SCHEDULED"))
                      (delegated (org-entry-get nil "DELEGATED")))
                 (when delegated
                   (push (list head
                              (mapconcat (lambda (c) (concat "@" c)) tags ",")
                              (or todo-state "")
                              (or scheduled "")
                              delegated)
                         actions))))
             nil nil)))))
    (get-buffer-create buffer-name)
    (with-current-buffer buffer-name
      (setq buffer-read-only nil)  ; Ensure we can modify
      (erase-buffer)
      (org-mode)
      (if (null actions)
          (insert "(No delegated tasks)\n")
        (insert "| Headline | Context | Status | Scheduled | Delegated |\n")
        (insert "|----------+---------+--------+-----------+-----------|\n")
        (dolist (action (nreverse actions))
          (insert (format "| %s | %s | %s | %s | %s |\n"
                         (replace-regexp-in-string "|" "\\\\vert{}" (nth 0 action))
                         (nth 1 action)
                         (nth 2 action)
                         (nth 3 action)
                         (nth 4 action))))
        (org-table-align))
      (setq buffer-read-only t)
      (goto-char (point-min)))
    (pop-to-buffer buffer-name)
    (pearl-gtd-do-view-mode 1)))

(defun pearl-gtd-do--view-today ()
  "View actions scheduled for today in table format."
  (let ((buffer-name "*Pearl-GTD: Today*")
        (actions '())
        (today-string (format-time-string "%Y-%m-%d")))
    (dolist (file '("actions.org"))
      (let ((file-path (expand-file-name file pearl-gtd-init-base-directory)))
        (when (file-exists-p file-path)
          (with-temp-buffer
            (insert-file-contents file-path)
            (org-mode)
            (org-map-entries
             (lambda ()
               (let* ((head (org-get-heading t t))
                      (tags (org-get-tags-at))
                      (todo-state (org-get-todo-state))
                      (scheduled (org-entry-get nil "SCHEDULED"))
                      (delegated (org-entry-get nil "DELEGATED")))
                 (when (and scheduled (string-match-p today-string scheduled))
                   (push (list head
                              (mapconcat (lambda (c) (concat "@" c)) tags ",")
                              (or todo-state "")
                              (or scheduled "")
                              (or delegated ""))
                         actions))))
             nil nil)))))
    (get-buffer-create buffer-name)
    (with-current-buffer buffer-name
      (setq buffer-read-only nil)  ; Ensure we can modify
      (erase-buffer)
      (org-mode)
      (if (null actions)
          (insert "(No actions scheduled for today)\n")
        (insert "| Headline | Context | Status | Scheduled | Delegated |\n")
        (insert "|----------+---------+--------+-----------+-----------|\n")
        (dolist (action (nreverse actions))
          (insert (format "| %s | %s | %s | %s | %s |\n"
                         (replace-regexp-in-string "|" "\\\\vert{}" (nth 0 action))
                         (nth 1 action)
                         (nth 2 action)
                         (nth 3 action)
                         (nth 4 action))))
        (org-table-align))
      (setq buffer-read-only t)
      (goto-char (point-min)))
    (pop-to-buffer buffer-name)
    (pearl-gtd-do-view-mode 1)))

(defun pearl-gtd-do--complete-task ()
  "Mark the current task as complete."
  ;; Enable org-log-done to automatically set CLOSED property
  (let ((org-log-done 'time))
    (org-todo "DONE"))
  ;; Save the buffer to ensure changes are written to file
  (save-buffer))

(provide 'pearl-gtd-do)

;;; pearl-gtd-do.el ends here
