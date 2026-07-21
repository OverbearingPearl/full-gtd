;;; pearl-gtd-test.el --- Test infrastructure and entry point  -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: MIT
;; URL: https://github.com/OverbearingPearl/pearl-gtd

;;; Commentary:

;; This file provides shared infrastructure for Pearl-GTD user story tests.
;; It contains assertion helpers and test runners.

;;; Code:

(require 'ert)
(require 'cl-lib)

(defvar pearl-gtd-test-caught-error nil
  "Variable to store caught errors during tests.")

(defun pearl-gtd-test-file-contains-p (file pattern)
  "Assert that FILE contains PATTERN.
FILE is the file path to check.
PATTERN is the regex pattern to search for.
Returns a list (found-p file-content) where found-p is t/nil,
and file-content is the entire file content as a string."
  (if (not (file-exists-p file))
      (list nil (format "File does not exist: %s" file))
    (with-temp-buffer
      (insert-file-contents file)
      (let ((content (buffer-string))
            (found (progn
                     (goto-char (point-min))
                     (let ((case-fold-search nil))
                       (re-search-forward pattern nil t)))))
        (list found content)))))

(defun pearl-gtd-test-file-contains-p-bool (file pattern)
  "Return t if FILE contains PATTERN, nil otherwise.
FILE is the file path to check.
PATTERN is the regex pattern to search for."
  (car (pearl-gtd-test-file-contains-p file pattern)))

(defun pearl-gtd-test-file-lacks-p (file pattern)
  "Assert that FILE does not contain PATTERN.
FILE is the file path to check.
PATTERN is the string to search for."
  (with-temp-buffer
    (insert-file-contents file)
    (goto-char (point-min))
    (let ((case-fold-search nil))
      (not (search-forward pattern nil t)))))

(defun pearl-gtd-test-inbox-empty-p (base-dir)
  "Check if inbox is visually empty (missing or zero size).
BASE-DIR is the base directory to check."
  (let ((inbox (expand-file-name "inbox.org" base-dir)))
    (or (not (file-exists-p inbox))
        (= 0 (file-attribute-size (file-attributes inbox))))))

(defun pearl-gtd-test-cleanup-buffers (buffer-names)
  "Safely kill all buffers in BUFFER-NAMES, ignoring errors."
  (dolist (name buffer-names)
    (when-let ((buf (get-buffer name)))
      (with-current-buffer buf
        (setq buffer-read-only nil))
      (ignore-errors (kill-buffer buf)))))

(defun pearl-gtd-test-task-exists-p (file title)
  "Check if task TITLE exists in FILE.
FILE is the file path to check.
TITLE is the task title to search for."
  (pearl-gtd-test-file-contains-p file (format "* %s" title)))

(defun pearl-gtd-test--create-files (temp-dir file-specs)
  "Create files in TEMP-DIR from FILE-SPECS.
Each spec is (FILENAME CONTENT).  CONTENT is a list of lines or a string."
  (dolist (spec file-specs)
    (let ((path (expand-file-name (car spec) temp-dir))
          (content (cdr spec)))
      (with-temp-file path
        (insert (if (stringp content)
                    content
                  (mapconcat #'identity content "\n")))))))

(defun pearl-gtd-test--cleanup (temp-dir)
  "Kill buffers visiting files under TEMP-DIR, then delete TEMP-DIR."
  (dolist (buf (buffer-list))
    (when (and (buffer-file-name buf)
               (string-prefix-p temp-dir (buffer-file-name buf)))
      (with-current-buffer buf
        (set-buffer-modified-p nil))
      (kill-buffer buf)))
  (when (file-directory-p temp-dir)
    (delete-directory temp-dir t)))

(defun pearl-gtd-test--debug-files (temp-dir file-names)
  "Return multi-line debug string showing contents of files under TEMP-DIR.
FILE-NAMES is a list of filenames (strings)."
  (mapconcat
   (lambda (fname)
     (let ((path (expand-file-name fname temp-dir)))
       (concat "-- " fname " --\n"
               (if (file-exists-p path)
                   (with-temp-buffer
                     (insert-file-contents path)
                     (buffer-string))
                 "File does not exist"))))
   file-names "\n\n"))

(defmacro pearl-gtd-test-define-story (name docstring &rest args)
  "Define a user story test named NAME with DOCSTRING.
ARGS is a plist with:
:setup    - Form to run before test.
:files    - List of (FILENAME (LINE1 LINE2 ...)).  Each line is a string.
:mock     - List of `cl-letf' bindings for input simulation.
:body     - Test body form.
:asserts  - Assertion forms.
:teardown - Cleanup form run before automatic cleanup."
  (declare (indent defun))
  (let ((setup    (plist-get args :setup))
        (files    (plist-get args :files))
        (mock     (plist-get args :mock))
        (body     (plist-get args :body))
        (asserts  (plist-get args :asserts))
        (teardown (plist-get args :teardown)))
    `(ert-deftest ,name ()
       ,docstring
       (let* ((temp-dir (make-temp-file "pearl-gtd-test-" t))
              (pearl-gtd-init-base-directory temp-dir)
              (pearl-gtd-test-caught-error nil))
         (unwind-protect
             (progn
               ,setup
               (pearl-gtd-test--create-files
                temp-dir
                (list ,@(mapcar (lambda (spec)
                                  `(cons ,(car spec) ,(cadr spec)))
                                files)))
               (cl-letf ,mock
                 ,body)
               (ert-info ((pearl-gtd-test--debug-files
                           temp-dir
                           ',(mapcar #'car files)))
                 ,asserts))
           (ignore-errors ,teardown)
           (pearl-gtd-test--cleanup temp-dir))))))

(provide 'pearl-gtd-test)

;;; pearl-gtd-test.el ends here
