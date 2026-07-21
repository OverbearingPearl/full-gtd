;;; pearl-gtd-init.el --- Initialization functions for pearl-gtd  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 OverbearingPearl
;; License: MIT
;; URL: https://github.com/OverbearingPearl/pearl-gtd
;; Package-Requires: ((emacs "27.1") (cl-lib "0.5") (org "9.3"))

;;; Commentary:

;; This file provides initialization functions for pearl-gtd.

;;; Code:

(defvar pearl-gtd-init-base-directory (expand-file-name "~/.pearl-gtd/")
  "Base directory for Pearl-GTD.")

(defun pearl-gtd-init--initialize ()
  "Initialize the Pearl-GTD system by creating the base directory
and necessary files."
  (let ((dir pearl-gtd-init-base-directory))
    (unless (file-directory-p dir)
      (make-directory dir))
    (dolist (file '("inbox.org" "reference.org" "someday.org" "actions.org"))
      (let ((file-path (expand-file-name file dir)))
        (unless (file-exists-p file-path)
          (write-region "" nil file-path))))
    (message "Pearl-GTD initialized in %s" dir)))

(provide 'pearl-gtd-init)

;;; pearl-gtd-init.el ends here
