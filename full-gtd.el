;;; full-gtd.el --- Complete Getting Things Done (GTD) workflow for org-mode  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 OverbearingPearl
;; Author: OverbearingPearl <OverbearingPearl@outlook.com>
;; Assisted-by: Kimi:kimi-k2.5, DeepSeek:deepseek-v3.2, Claude:claude-sonnet-4.6
;; URL: https://github.com/OverbearingPearl/full-gtd
;; Version: 0.1.16
;; Package-Requires: ((emacs "27.1") (org "9.3"))
;; Keywords: outlines, tools, convenience, org, todo, gtd, calendar
;; SPDX-License-Identifier: MIT

;;; Commentary:

;; Complete Getting Things Done for Emacs org-mode.

;; The only Emacs implementation that covers the entire GTD framework:
;; capture, clarify, organize, reflect, engage, plus the Natural
;; Planning Model and the Six Horizons of Focus.

;; Key features:
;; - One-key inbox processing with clarify, staging table, and hybrid
;;   date input (t/T/w/h or free-form).
;; - Reference and Someday/Maybe archives with project association.
;; - Daily & weekly reviews with table editing and jump-to-source.
;; - Single-card Do sessions with smart prioritization (urgency,
;;   horizons, context).
;; - Horizon matrix view that spot orphaned projects immediately.
;; - Planning workflow enforces Purpose → Vision → Goal → Project →
;;   Next Action.

;; Commands: full-gtd-capture, full-gtd-process-inbox,
;; full-gtd-review-daily, full-gtd-review-weekly, full-gtd-do,
;; full-gtd-horizons-view, full-gtd-planning-start.

;; Data lives in plain Org files (default ~/.full-gtd/).

;;; Code:

(require 'cl-lib)

(eval-and-compile
  (defvar full-gtd--package-root
    (or (and load-file-name (file-name-directory load-file-name))
        default-directory)
    "Root directory of Full-GTD package source.")
  (when full-gtd--package-root
    (add-to-list 'load-path (expand-file-name "lisp" full-gtd--package-root))))

(require 'full-gtd-init)
(require 'full-gtd-state)
(require 'full-gtd-inbox)
(require 'full-gtd-core)
(require 'full-gtd-ui)
(require 'full-gtd-review)
(require 'full-gtd-do)
(require 'full-gtd-horizons)
(require 'full-gtd-planning)

(defun full-gtd-capture ()
  "Capture a new item to the inbox."
  (interactive)
  (full-gtd-inbox--capture))

(defun full-gtd-process-inbox ()
  "Process the inbox."
  (interactive)
  (full-gtd-inbox--process))

(defun full-gtd-init-initialize ()
  "Initialize the Full-GTD system.
Create the base directory and necessary files."
  (interactive)
  (full-gtd-init--initialize))

(defun full-gtd-review-daily ()
  "Run daily review."
  (interactive)
  (full-gtd-review--daily))

(defun full-gtd-review-weekly ()
  "Run weekly review."
  (interactive)
  (full-gtd-review--weekly))

(defun full-gtd-do ()
  "Start a Do session for engaging with next actions.
Prompts for context, time budget, and energy level, then enters
a single-card execution loop.  The session continues until you
choose to quit or modify conditions when no actions remain.

With \\[universal-argument] as prefix, prompts for view type
\(next/delegated/today) before asking for filters."
  (interactive)
  (let ((view-type (if current-prefix-arg
                       (intern (completing-read "View type: "
                                                '("next" "delegated" "today")
                                                nil t))
                     'next)))
    (let ((conditions (full-gtd-do--prompt-conditions)))
      (apply #'full-gtd-do--start-session (cons view-type conditions)))))

(defun full-gtd-horizons-view ()
  "Display horizon hierarchy view."
  (interactive)
  (full-gtd-horizons--view))

(defun full-gtd-planning-start ()
  "Start Natural Planning Model workflow."
  (interactive)
  (full-gtd-planning--start))

(provide 'full-gtd)

;;; full-gtd.el ends here
