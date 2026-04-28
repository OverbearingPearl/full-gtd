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

(defun pearl-gtd-capture ()
  "Capture a new item to the inbox."
  (interactive)
  (pearl-gtd-inbox-capture))

(defun pearl-gtd-process-inbox ()
  "Process the inbox."
  (interactive)
  (pearl-gtd-inbox-process))

(defun pearl-gtd-run-tests ()
  "Run all Pearl-GTD unit tests."
  (interactive)
  (require 'ert)
  (ert-delete-all-tests)
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
    (dolist (file el-files)
      (when (string-match "^[^.]+\\.el$" file)
        (load-file (expand-file-name file lisp-dir))
        (message "Reloaded %s" file)))
    (message "Modules reloaded.")))

(provide 'pearl-gtd)

;;; pearl-gtd.el ends here
