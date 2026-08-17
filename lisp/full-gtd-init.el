;;; full-gtd-init.el --- Initialization functions for full-gtd  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 OverbearingPearl
;; Author: OverbearingPearl <OverbearingPearl@outlook.com>
;; Assisted-by: Kimi:kimi-k2.5, DeepSeek:deepseek-v3.2, Claude:claude-sonnet-4.6
;; URL: https://github.com/OverbearingPearl/full-gtd
;; SPDX-License-Identifier: MIT

;;; Commentary:

;; This file provides initialization functions for full-gtd.

;;; Code:

(defgroup full-gtd nil
  "Full-GTD user data settings."
  :group 'files)

(defcustom full-gtd-init-base-directory (expand-file-name "~/.full-gtd/")
  "Base directory for Full-GTD user org files."
  :type 'directory
  :group 'full-gtd)

(defun full-gtd-init--initialize ()
  "Initialize the Full-GTD system.
Create the base directory and necessary files."
  (let ((dir full-gtd-init-base-directory))
    (unless (file-directory-p dir)
      (make-directory dir))
    (dolist (file '("inbox.org" "reference.org" "someday.org" "action.org"))
      (let ((file-path (expand-file-name file dir)))
        (unless (file-exists-p file-path)
          (write-region "" nil file-path))))
    (message "Full-GTD initialized in %s" dir)))

(provide 'full-gtd-init)

;;; full-gtd-init.el ends here
