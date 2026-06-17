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
    (define-key map (kbd "n") #'pearl-gtd-do-next-row)
    (define-key map (kbd "p") #'pearl-gtd-do-previous-row)
    (define-key map (kbd "j") #'pearl-gtd-do-next-row)
    (define-key map (kbd "k") #'pearl-gtd-do-previous-row)
    (define-key map (kbd "c") #'pearl-gtd-do-complete-task-at-point)
    (define-key map (kbd "q") #'quit-window)
    map))

(define-minor-mode pearl-gtd-do-view-mode
  "Minor mode for viewing GTD actions in table format."
  :init-value nil
  :lighter " Pearl-Do"
  :keymap pearl-gtd-do-view-mode-map
  :interactive nil)

(defun pearl-gtd-do-next-row ()
  "Move to next row in the actions table."
  (interactive)
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

(defun pearl-gtd-do-previous-row ()
  "Move to previous row in the actions table."
  (interactive)
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

(defun pearl-gtd-do-complete-task-at-point ()
  "Mark the task at point as complete."
  (interactive)
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
                      (delegated (org-entry-get nil "DELEGATED"))
                      (matching-contexts (when contexts
                                          (cl-intersection tags contexts :test #'string=))))
                 (when (and (string= todo-state "TODO")
                            (or (null contexts) matching-contexts))
                   (let ((display-tags (if contexts matching-contexts tags)))
                     (push (list head
                                (if display-tags
                                    (mapconcat (lambda (c) (concat "@" c)) display-tags ",")
                                  "")
                                (or todo-state "")
                                (or scheduled "")
                                (or delegated ""))
                           actions)))))
             nil nil)))))
    (with-current-buffer buffer
      (setq buffer-read-only nil)
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
      (forward-line 1)
      (current-buffer))))

(defun pearl-gtd-do--collect-contexts ()
  "Collect all unique context tags from actions.org."
  (let ((contexts '()))
    (let ((actions-file (expand-file-name "actions.org" pearl-gtd-init-base-directory)))
      (when (file-exists-p actions-file)
        (with-temp-buffer
          (insert-file-contents actions-file)
          (org-mode)
          (org-map-entries
           (lambda ()
             (dolist (tag (org-get-tags-at))
               (cl-pushnew tag contexts :test #'string=)))
           nil nil))))
    (mapcar (lambda (c) (concat "@" c)) contexts)))

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
                 (when (and delegated (string= todo-state "TODO"))
                   (push (list head
                              (mapconcat (lambda (c) (concat "@" c)) tags ",")
                              (or todo-state "")
                              (or scheduled "")
                              delegated)
                         actions))))
             nil nil)))))
    (get-buffer-create buffer-name)
    (with-current-buffer buffer-name
      (setq buffer-read-only nil)
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
      (setq buffer-read-only nil)
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
