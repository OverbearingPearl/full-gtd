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
  (let ((buffer-name "*Pearl-GTD: All Actions*"))
    (get-buffer-create buffer-name)
    (with-current-buffer buffer-name
      (erase-buffer)
      (org-mode)
      (insert "* All Next Actions\n")
      (dolist (file '("actions.org"))
        (let ((file-path (expand-file-name file pearl-gtd-init-base-directory)))
          (when (file-exists-p file-path)
            (insert-file-contents file-path)
            (org-map-entries
             (lambda ()
               (let ((head (org-get-heading t t)))
                 (when (string-match-p "TODO" head)
                   (insert (format "- %s\n" head)))))
             "TODO" 'file))))
      (goto-char (point-min))
      (org-mode))
    (pop-to-buffer buffer-name)))

(defun pearl-gtd-do--view-delegated ()
  "View all delegated tasks."
  (let ((buffer-name "*Pearl-GTD: Delegated*"))
    (get-buffer-create buffer-name)
    (with-current-buffer buffer-name
      (erase-buffer)
      (org-mode)
      (insert "* Delegated Tasks\n")
      (dolist (file '("actions.org"))
        (let ((file-path (expand-file-name file pearl-gtd-init-base-directory)))
          (when (file-exists-p file-path)
            (insert-file-contents file-path)
            (org-map-entries
             (lambda ()
               (let ((head (org-get-heading t t))
                     (props (org-entry-properties)))
                 (when (assoc "DELEGATED" props)
                   (insert (format "- %s (to %s)\n" head (cdr (assoc "DELEGATED" props)))))))
             "TODO" 'file))))
      (goto-char (point-min))
      (org-mode))
    (pop-to-buffer buffer-name)))

(defun pearl-gtd-do--view-today ()
  "View actions scheduled for today."
  (let ((buffer-name "*Pearl-GTD: Today*"))
    (get-buffer-create buffer-name)
    (with-current-buffer buffer-name
      (erase-buffer)
      (org-mode)
      (insert "* Today's Actions\n")
      (dolist (file '("actions.org"))
        (let ((file-path (expand-file-name file pearl-gtd-init-base-directory)))
          (when (file-exists-p file-path)
            (insert-file-contents file-path)
            (org-map-entries
             (lambda ()
               (let ((head (org-get-heading t t))
                     (scheduled (org-entry-get nil "SCHEDULED")))
                 (when (and scheduled (string-match-p (format-time-string "%Y-%m-%d") scheduled))
                   (insert (format "- %s\n" head)))))
             "TODO" 'file))))
      (goto-char (point-min))
      (org-mode))
    (pop-to-buffer buffer-name)))

(defun pearl-gtd-do--complete-task ()
  "Mark the current task as complete."
  ;; Enable org-log-done to automatically set CLOSED property
  (let ((org-log-done 'time))
    (org-todo "DONE"))
  ;; Save the buffer to ensure changes are written to file
  (save-buffer))

(defun pearl-gtd-do--view-context (context-input)
  "Internal function to view tasks by CONTEXT-INPUT.
CONTEXT-INPUT can be a single context string or a list of context strings.
When a string contains commas, it is split into multiple contexts.
Context tags are normalized by removing the @ prefix if present."
  (let* ((contexts (cond
                    ((listp context-input) context-input)
                    ((string-match-p "," context-input)
                     (mapcar #'string-trim (split-string context-input "," t)))
                    (t (list context-input))))
         (normalized-contexts (mapcar (lambda (c)
                                       (if (string-prefix-p "@" c)
                                           (substring c 1)
                                         c))
                                     contexts))
         (display-name (if (listp context-input)
                          (mapconcat #'identity context-input ", ")
                        context-input))
         (buffer-name (format "*Pearl-GTD: %s*" display-name)))
    (get-buffer-create buffer-name)
    (with-current-buffer buffer-name
      (erase-buffer)
      (org-mode)
      (insert (format "* Actions for %s\n" display-name))
      (dolist (file '("actions.org"))
        (let ((file-path (expand-file-name file pearl-gtd-init-base-directory)))
          (when (file-exists-p file-path)
            (insert-file-contents file-path)
            (org-map-entries
             (lambda ()
               (let ((head (org-get-heading t t))
                     (tags (org-get-tags-at)))
                 (when (cl-some (lambda (ctx) (member ctx tags)) normalized-contexts)
                   (insert (format "- %s\n" head)))))
             "TODO" 'file))))
      (goto-char (point-min))
      (org-mode))
    (pop-to-buffer buffer-name)))

(provide 'pearl-gtd-do)

;;; pearl-gtd-do.el ends here
