;;; pearl-gtd.el --- Complete GTD implementation for org-mode  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 OverbearingPearl

;; Author: OverbearingPearl <OverbearingPearl@outlook.com>
;; Version: 0.1.0
;; Package-Requires: ((emacs "27.1") (org "9.4"))
;; Keywords: outlines, tools, convenience, productivity, gtd, org
;; URL: https://github.com/OverbearingPearl/pearl-gtd

;;; Commentary:

;; This package provides a complete GTD implementation for org-mode,
;; including six horizon levels: Purpose, Vision, Goals, Areas,
;; Projects, and Actions.

;;; Code:

(defvar pearl-gtd-directory (file-name-directory load-file-name))

(add-to-list 'load-path (expand-file-name "lisp" pearl-gtd-directory))

(require 'pearl-gtd-init)
(require 'pearl-gtd-inbox)
(require 'pearl-gtd-core)
(require 'pearl-gtd-review)
(require 'pearl-gtd-do)

(defun pearl-gtd-capture ()
  "Capture a new item to the inbox."
  (interactive)
  (let ((item (string-trim (read-string "Enter item to capture: "))))
    (unless (string-empty-p item)
      (with-current-buffer (find-file-noselect (expand-file-name "inbox.org" pearl-gtd-init-base-directory))
        (goto-char (point-max))
        (insert (format "* %s\n:PROPERTIES:\n:CREATED: %s\n:END:\n" item (format-time-string "%Y-%m-%d %H:%M:%S")))
        ;; Add ID to the newly created headline
        (forward-line -2)  ; Go back to the headline line
        (org-id-get-create)
        (save-buffer)))))

(defun pearl-gtd-process-inbox ()
  "Process the inbox."
  (interactive)
  (pearl-gtd-inbox--process))

(defun pearl-gtd-init-initialize ()
  "Initialize the Pearl-GTD system by creating the base directory and necessary files."
  (interactive)
  (pearl-gtd-init--initialize))

(defun pearl-gtd-review-daily ()
  "Run daily review."
  (interactive)
  (pearl-gtd-review--daily))

(defun pearl-gtd-review-weekly ()
  "Run weekly review across all lists."
  (interactive)
  (pearl-gtd-review--weekly))

(defun pearl-gtd-review-undelegated ()
  "Review tasks that are not delegated."
  (interactive)
  (pearl-gtd-review--undelegated))

(defun pearl-gtd-review-edit-task ()
  "Edit the task at point in the review buffer."
  (interactive)
  (pearl-gtd-review--edit-task))

(defun pearl-gtd-review-overdue ()
  "Review overdue scheduled tasks."
  (interactive)
  (pearl-gtd-review--overdue))

(defun pearl-gtd-review-stuck-projects ()
  "Review projects with no next actions."
  (interactive)
  (pearl-gtd-review--stuck-projects))

(defun pearl-gtd-review-set-deadline ()
  "Set deadline for current task with reminder."
  (interactive)
  (pearl-gtd-review--set-deadline))

(defun pearl-gtd-review-view-upcoming-deadlines ()
  "View tasks with deadlines in next 7 days."
  (interactive)
  (pearl-gtd-review--view-upcoming-deadlines))

(defun pearl-gtd-review-check-reminders ()
  "Check and display reminders for due tasks."
  (interactive)
  (pearl-gtd-review--check-reminders))

(defun pearl-gtd-review-track-delegation-status ()
  "Track status of delegated tasks and display waiting time."
  (interactive)
  (pearl-gtd-review--track-delegation-status))

(defun pearl-gtd-review-send-delegation-reminder ()
  "Send reminder for overdue delegated task."
  (interactive)
  (pearl-gtd-review--send-delegation-reminder))

(defun pearl-gtd-do-view-by-context ()
  "View next actions filtered by a specific context."
  (interactive)
  (pearl-gtd-do--view-by-context))

(defun pearl-gtd-do-view-all-actions ()
  "View all next actions regardless of context."
  (interactive)
  (pearl-gtd-do--view-all-actions))

(defun pearl-gtd-do-view-delegated ()
  "View all delegated tasks."
  (interactive)
  (pearl-gtd-do--view-delegated))

(defun pearl-gtd-do-view-today ()
  "View actions scheduled for today."
  (interactive)
  (pearl-gtd-do--view-today))

(defun pearl-gtd-do-complete-task ()
  "Mark the current task as complete."
  (interactive)
  (pearl-gtd-do--complete-task))

(defun pearl-gtd-run-tests ()
  "Run all Pearl-GTD unit tests."
  (interactive)
  (require 'ert)
  (ert-delete-all-tests)
  ;; Reload all modules first to ensure latest code is used
  (pearl-gtd-reload-modules)
  ;; Load test files automatically from the lisp directory
  ;; This ensures all test files are loaded regardless of hardcoding
  (let ((test-dir (expand-file-name "lisp" pearl-gtd-directory)))
    (dolist (file (directory-files test-dir nil "test-.*\\.el$"))
      (let ((full-path (expand-file-name file test-dir)))
        (when (file-exists-p full-path)
          (load-file full-path)))))
  (ert t))

(defun pearl-gtd-reload-modules ()
  "Reload Pearl-GTD modules for updated code."
  (interactive)
  (let* ((lisp-dir (expand-file-name "lisp" pearl-gtd-directory))
         (el-files (directory-files lisp-dir nil "\\.el$")))
    ;; Unload all features first
    (dolist (file el-files)
      (when (string-match "^[^.]+\\.el$" file)
        (let ((feature (intern (file-name-base file))))
          (when (featurep feature)
            (condition-case nil
                (unload-feature feature)
              (error nil))))))
    ;; Load .el source files directly, ignoring .elc
    ;; Skip test files (only load core modules)
    (dolist (file el-files)
      (when (and (string-match "^[^.]+\\.el$" file)
                 (not (string-match "^test-" file)))
        (load-file (expand-file-name file lisp-dir))
        (message "Reloaded %s" file)))
    (message "Modules reloaded.")))

(provide 'pearl-gtd)

;;; pearl-gtd.el ends here
