;;; pearl-gtd.el --- Complete Getting Things Done (GTD) workflow for org-mode  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 OverbearingPearl
;; Author: OverbearingPearl <OverbearingPearl@outlook.com>
;; Assisted-by: Kimi:kimi-k2.5, DeepSeek:deepseek-v3.2, Claude:claude-sonnet-4.6
;; URL: https://github.com/OverbearingPearl/pearl-gtd
;; Version: 0.1.0
;; Package-Requires: ((emacs "27.1") (org "9.3"))
;; Keywords: outlines, tools, convenience, org, todo, gtd, calendar
;; License: MIT
;; SPDX-License-Identifier: MIT

;;; Commentary:

;; Pearl-GTD implements David Allen's complete "Getting Things Done" methodology
;; for Emacs org-mode, covering all five workflow steps: Capture, Clarify,
;; Organize, Reflect, and Engage.
;;
;; Key features:
;; - Full GTD workflow with inbox processing and staging buffer
;; - Natural Planning Model for project planning with forced completion
;; - Six Horizons of Focus (L3-L6) with hierarchy constraints
;; - Daily and weekly review cycles with horizon columns
;; - Context-based filtering and delegation tracking
;; - Standard GTD lists: Projects, Next Actions, Waiting For, Someday/Maybe, Reference
;;
;; This package aims to implement the complete framework from the original
;; book, including both horizontal (workflow) and vertical (horizons) focus
;; management, which existing packages do not fully cover.

;;; Code:

(require 'cl-lib)
(declare-function ert-delete-all-tests "ert")
(declare-function ert-run-tests-batch-and-exit "ert")

(defvar pearl-gtd-directory nil
  "Root directory of Pearl-GTD.")

(eval-and-compile
  (when load-file-name
    (setq pearl-gtd-directory (file-name-directory load-file-name)))
  (when pearl-gtd-directory
    (add-to-list 'load-path (expand-file-name "lisp" pearl-gtd-directory))))

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
  "Initialize the Pearl-GTD system.
Create the base directory and necessary files."
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
    ;; First load the test infrastructure
    (let ((test-file (expand-file-name "pearl-gtd-test.el" test-dir)))
      (when (file-exists-p test-file)
        (load-file test-file)))
    (dolist (file (directory-files test-dir nil "pearl-gtd-test-.*\\.el$"))
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
            (condition-case nil
                (unload-feature feature)
              (error nil))))))
    ;; Unload pearl-gtd.el if loaded
    (when (featurep 'pearl-gtd)
      (condition-case nil
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
