;;; full-gtd-test.el --- ERT entry point for Full-GTD tests  -*- lexical-binding: t; -*-

;;; Commentary:

;; This is the test entry point for Full-GTD.  Loading this file adds the
;; package root and the Lisp directory to `load-path', loads the main
;; package, the test infrastructure, and provides commands to run all
;; ERT tests.

;;; Code:

(require 'cl-lib)
(require 'ert)

(defvar full-gtd-test--package-root
  (or (and load-file-name (file-name-directory load-file-name))
      default-directory)
  "Root directory of Full-GTD package source.")

(add-to-list 'load-path full-gtd-test--package-root)
(add-to-list 'load-path (expand-file-name "lisp" full-gtd-test--package-root))

(require 'full-gtd)
(require 'full-gtd-test-utils)

(defun full-gtd-test-reload-modules ()
  "Reload Full-GTD modules for updated code."
  (interactive)
  (let* ((root-dir full-gtd-test--package-root)
         (lisp-dir (expand-file-name "lisp" root-dir))
         (el-files (directory-files lisp-dir nil "\\.el$")))
    ;; Unload all features first
    (dolist (file el-files)
      (when (string-match "^[^.]+\\.el$" file)
        (let ((feature (intern (file-name-base file))))
          (when (featurep feature)
            (condition-case nil
                (unload-feature feature)
              (error nil))))))
    ;; Unload full-gtd.el if loaded
    (when (featurep 'full-gtd)
      (condition-case nil
          (unload-feature 'full-gtd)
        (error nil)))

    ;; Auto-clear all full-gtd keymap variables
    (mapatoms (lambda (sym)
                (when (and (string-match-p "^full-gtd-.*-mode-map$" (symbol-name sym))
                           (boundp sym))
                  (makunbound sym))))

    ;; Load full-gtd.el from root directory
    (let ((full-gtd-el (expand-file-name "full-gtd.el" root-dir)))
      (when (file-exists-p full-gtd-el)
        (load-file full-gtd-el)))
    ;; Load .el source files from lisp directory, ignoring .elc and test files
    (dolist (file el-files)
      (when (and (string-match "^[^.]+\\.el$" file)
                 (not (string-match "-test\\.el$" file)))
        (let ((el-path (expand-file-name file lisp-dir)))
          (load-file el-path))))
    (message "Modules reloaded.")))

(defun full-gtd-test-run ()
  "Run all Full-GTD test suites (unit and user story).
Loads the root test entry point, reloads all modules, then runs
every ERT test defined in the Lisp directory."
  (interactive)
  (require 'ert)
  (ert-delete-all-tests)
  ;; Reload all modules first to ensure latest code is used
  (full-gtd-test-reload-modules)
  ;; Ensure test infrastructure is loaded
  (require 'full-gtd-test-utils)
  ;; Load test files automatically from the lisp directory
  (let ((test-dir (expand-file-name "lisp" full-gtd-test--package-root)))
    (dolist (file (directory-files test-dir nil "full-gtd-.*-test\\.el$"))
      (let ((full-path (expand-file-name file test-dir)))
        (when (file-exists-p full-path)
          (load-file full-path)))))
  ;; Use batch-compatible function to ensure output is visible in terminal
  (if noninteractive
      (ert-run-tests-batch-and-exit)
    (ert t)))

(provide 'full-gtd-test)

;;; full-gtd-test.el ends here
