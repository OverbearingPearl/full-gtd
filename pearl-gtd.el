;;; pearl-gtd.el --- Complete Getting Things Done (GTD) workflow for org-mode  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 OverbearingPearl

;; Author: OverbearingPearl <OverbearingPearl@outlook.com>
;; Version: 0.1.0
;; Package-Requires: ((emacs "27.1"))
;; Keywords: outlines, tools, convenience, productivity, gtd, org, task, management, workflow, todo, getting-things-done, david-allen, inbox, review, projects, actions, contexts, horizons, focus, productivity, organization, time-management
;; URL: https://github.com/OverbearingPearl/pearl-gtd

;;; Commentary:

;; This package provides a complete GTD implementation for org-mode,
;; including six horizon levels: Purpose, Vision, Goals, Areas,
;; Projects, and Actions.

;; Pearl-GTD is a comprehensive implementation of David Allen's "Getting Things Done"
;; methodology within Emacs org-mode. It covers all five core GTD workflow steps:
;;
;; 1. Capture - Collect what has your attention
;; 2. Clarify - Process what it means
;; 3. Organize - Put it where it belongs
;; 4. Reflect - Review frequently
;; 5. Engage - Simply do
;;
;; Features:
;; • Complete GTD workflow with inbox processing
;; • Six Horizon of Focus (Purpose, Vision, Goals, Areas, Projects, Actions)
;; • Natural Planning Model for project planning
;; • Weekly and daily review cycles
;; • Context-based task filtering (@office, @home, @errands, etc.)
;; • Two-Minute Rule implementation
;; • Delegation tracking and reminders
;; • All standard GTD lists (Projects, Next Actions, Waiting For, Someday/Maybe, Reference)
;; • Brainstorming tools and organizing principles
;; • Comprehensive vertical and horizontal focus management

;;; Code:

(defvar pearl-gtd-directory (file-name-directory load-file-name))

(add-to-list 'load-path (expand-file-name "lisp" pearl-gtd-directory))

(require 'pearl-gtd-init)
(require 'pearl-gtd-inbox)
(require 'pearl-gtd-core)
(require 'pearl-gtd-review)
(require 'pearl-gtd-do)
(require 'pearl-gtd-horizons)
(require 'pearl-gtd-planning)

(defun pearl-gtd-capture ()
  "Capture a new item to the inbox."
  (interactive)
  (pearl-gtd-inbox--capture))

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
  "Run weekly review."
  (interactive)
  (pearl-gtd-review--weekly))

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

(defun pearl-gtd-horizons-view ()
  "Display horizon hierarchy view."
  (interactive)
  (pearl-gtd-horizons--view))

(defun pearl-gtd-planning-start ()
  "Start Natural Planning Model workflow."
  (interactive)
  (pearl-gtd-planning--start))

(defun pearl-gtd-run-tests ()
  "Run all Pearl-GTD unit tests."
  (interactive)
  (require 'ert)
  (ert-delete-all-tests)
  ;; Reload all modules first to ensure latest code is used
  (pearl-gtd-reload-modules)
  ;; Load test files automatically from the lisp directory
  (let ((test-dir (expand-file-name "lisp" pearl-gtd-directory)))
    (dolist (file (directory-files test-dir nil "test-.*\\.el$"))
      (let ((full-path (expand-file-name file test-dir)))
        (when (file-exists-p full-path)
          (load-file full-path)))))
  ;; Use batch-compatible function to ensure output is visible in terminal
  (if noninteractive
      (ert-run-tests-batch-and-exit)
    (ert t)))

(defun pearl-gtd-reload-modules ()
  "Reload Pearl-GTD modules for updated code."
  (interactive)
  (let* ((root-dir pearl-gtd-directory)
         (lisp-dir (expand-file-name "lisp" pearl-gtd-directory))
         (el-files (directory-files lisp-dir nil "\\.el$")))
    ;; Unload all features first
    (dolist (file el-files)
      (when (string-match "^[^.]+\\.el$" file)
        (let ((feature (intern (file-name-base file))))
          (when (featurep feature)
            (condition-case err
                (unload-feature feature)
              (error nil))))))
    ;; Unload pearl-gtd.el if loaded
    (when (featurep 'pearl-gtd)
      (condition-case err
          (unload-feature 'pearl-gtd)
        (error nil)))
    ;; Load pearl-gtd.el from root directory
    (let ((pearl-gtd-el (expand-file-name "pearl-gtd.el" root-dir)))
      (when (file-exists-p pearl-gtd-el)
        (load-file pearl-gtd-el)))
    ;; Load .el source files from lisp directory, ignoring .elc
    (dolist (file el-files)
      (when (and (string-match "^[^.]+\\.el$" file)
                 (not (string-match "^test-" file)))
        (let ((el-path (expand-file-name file lisp-dir)))
          (load-file el-path))))
    (message "Modules reloaded.")))

(provide 'pearl-gtd)

;;; pearl-gtd.el ends here
