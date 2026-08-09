;;; pearl-gtd-init.el --- Initialization functions for pearl-gtd  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 OverbearingPearl
;; Author: OverbearingPearl <OverbearingPearl@outlook.com>
;; Assisted-by: Kimi:kimi-k2.5, DeepSeek:deepseek-v3.2, Claude:claude-sonnet-4.6
;; URL: https://github.com/OverbearingPearl/pearl-gtd
;; SPDX-License-Identifier: MIT

;;; Commentary:

;; This file provides initialization functions for pearl-gtd.

;;; Code:

(defgroup pearl-gtd nil
  "Pearl-GTD user data settings."
  :group 'files)

(defcustom pearl-gtd-init-base-directory (expand-file-name "~/.pearl-gtd/")
  "Base directory for Pearl-GTD user org files."
  :type 'directory
  :group 'pearl-gtd)

(defun pearl-gtd-init--initialize ()
  "Initialize the Pearl-GTD system.
Create the base directory and necessary files."
  (let ((dir pearl-gtd-init-base-directory))
    (unless (file-directory-p dir)
      (make-directory dir))
    (dolist (file '("inbox.org" "reference.org" "someday.org" "action.org"))
      (let ((file-path (expand-file-name file dir)))
        (unless (file-exists-p file-path)
          (write-region "" nil file-path))))
    (message "Pearl-GTD initialized in %s" dir)))

(provide 'pearl-gtd-init)

;;; pearl-gtd-init.el ends here
