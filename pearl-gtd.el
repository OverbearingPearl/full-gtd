;;; pearl-gtd.el --- Complete Getting Things Done (GTD) workflow for org-mode  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 OverbearingPearl
;; Author: OverbearingPearl <OverbearingPearl@outlook.com>
;; Assisted-by: Kimi:kimi-k2.5, DeepSeek:deepseek-v3.2, Claude:claude-sonnet-4.6
;; URL: https://github.com/OverbearingPearl/pearl-gtd
;; Version: 0.1.8
;; Package-Requires: ((emacs "27.1") (org "9.3"))
;; Keywords: outlines, tools, convenience, org, todo, gtd, calendar
;; SPDX-License-Identifier: MIT

;;; Commentary:

;; Pearl-GTD implements David Allen's complete "Getting Things Done" methodology
;; for Emacs org-mode, covering all five workflow steps: Capture, Clarify,
;; Organize, Reflect, and Engage.
;;
;; Key features:
;; - Full GTD workflow with single-key inbox processing, optional clarify,
;;   and hybrid date input (t/T/w/h shortcuts or free-form)
;; - Natural Planning Model for project planning with forced completion
;; - Six Horizons of Focus (L3-L6) with hierarchy
;;   constraints
;; - Daily and weekly review cycles with horizon columns
;; - Context-based filtering and delegation tracking
;; - Standard GTD lists: Projects, Next Actions, Waiting For,
;;   Someday/Maybe, Reference
;; - Single-card execution: algorithmic prioritization by
;;   urgency/horizons/context instead of list browsing
;;
;; This package aims to implement the complete framework from the
;; original book, including both horizontal (workflow) and vertical
;; (horizons) focus management, which existing packages do not fully
;; cover.

;;; Code:

(require 'cl-lib)
(declare-function ert-delete-all-tests "ert")
(declare-function ert-run-tests-batch-and-exit "ert")

(eval-and-compile
  (defvar pearl-gtd--package-root
    (or (and load-file-name (file-name-directory load-file-name))
        default-directory)
    "Root directory of Pearl-GTD package source.")
  (when pearl-gtd--package-root
    (add-to-list 'load-path (expand-file-name "lisp" pearl-gtd--package-root))))

(require 'pearl-gtd-init)
(require 'pearl-gtd-state)
(require 'pearl-gtd-inbox)
(require 'pearl-gtd-core)
(require 'pearl-gtd-ui)
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

(defun pearl-gtd-do ()
  "Start a Do session for engaging with next actions.
Prompts for context, time budget, and energy level, then enters
a single-card execution loop. The session continues until you
choose to quit or modify conditions when no actions remain.

With \\[universal-argument] as prefix, prompts for view type
\(next/delegated/today) before asking for filters."
  (interactive)
  (let ((view-type (if current-prefix-arg
                       (intern (completing-read "View type: "
                                                '("next" "delegated" "today")
                                                nil t))
                     'next)))
    (let ((conditions (pearl-gtd-do--prompt-conditions)))
      (apply #'pearl-gtd-do--start-session (cons view-type conditions)))))

(defun pearl-gtd-horizons-view ()
  "Display horizon hierarchy view."
  (interactive)
  (pearl-gtd-horizons--view))

(defun pearl-gtd-planning-start ()
  "Start Natural Planning Model workflow."
  (interactive)
  (pearl-gtd-planning--start))

(defun pearl-gtd-run-tests ()
  "Run all Pearl-GTD tests (unit tests and user story tests)."
  (interactive)
  (require 'ert)
  (ert-delete-all-tests)
  ;; Reload all modules first to ensure latest code is used
  (pearl-gtd-reload-modules)
  ;; Load test files automatically from the lisp directory
  (let ((test-dir (expand-file-name "lisp" pearl-gtd--package-root)))
    ;; First load the test infrastructure
    (let ((test-file (expand-file-name "pearl-gtd-test.el" test-dir)))
      (when (file-exists-p test-file)
        (load-file test-file)))
    ;; Then load all other test files (horizontal layer + vertical layer)
    (dolist (file (directory-files test-dir nil "pearl-gtd-.*-test\\.el$"))
      (unless (string= file "pearl-gtd-test.el")  ; Infrastructure already loaded above
        (let ((full-path (expand-file-name file test-dir)))
          (when (file-exists-p full-path)
            (load-file full-path))))))
  ;; Use batch-compatible function to ensure output is visible in terminal
  (if noninteractive
      (ert-run-tests-batch-and-exit)
    (ert t)))

(defun pearl-gtd-reload-modules ()
  "Reload Pearl-GTD modules for updated code."
  (interactive)
  (let* ((root-dir pearl-gtd--package-root)
         (lisp-dir (expand-file-name "lisp" pearl-gtd--package-root))
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
    
    ;; Auto-clear all pearl-gtd keymap variables
    (mapatoms (lambda (sym)
                (when (and (string-match-p "^pearl-gtd-.*-mode-map$" (symbol-name sym))
                           (boundp sym))
                  (makunbound sym))))
    
    ;; Load pearl-gtd.el from root directory
    (let ((pearl-gtd-el (expand-file-name "pearl-gtd.el" root-dir)))
      (when (file-exists-p pearl-gtd-el)
        (load-file pearl-gtd-el)))
    ;; Load .el source files from lisp directory, ignoring .elc and test files
    (dolist (file el-files)
      (when (and (string-match "^[^.]+\\.el$" file)
                 (not (string-match "-test\\.el$" file)))
        (let ((el-path (expand-file-name file lisp-dir)))
          (load-file el-path))))
    (message "Modules reloaded.")))

(provide 'pearl-gtd)

;;; pearl-gtd.el ends here
