;;; full-gtd-utils-test.el --- Test infrastructure and utilities  -*- lexical-binding: t; -*-

;;; Commentary:

;; This file provides shared infrastructure for Full-GTD user story tests.
;; It contains assertion helpers and test utilities.

;;; Code:

(require 'ert)
(require 'cl-lib)

(defvar full-gtd-test-caught-error nil
  "Variable to store caught errors during tests.")

(defun full-gtd-test-file-contains-p (file pattern)
  "Check FILE for PATTERN and return (FOUND CONTENT).
FOUND is non-nil if PATTERN found; CONTENT is the file content as string.
FILE is the file path; PATTERN is the regex pattern to search for."
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

(defun full-gtd-test-file-contains-p-bool (file pattern)
  "Check FILE for PATTERN and return t if present, nil otherwise.
FILE is the file path to check.
PATTERN is the regex pattern to search for."
  (car (full-gtd-test-file-contains-p file pattern)))

(defun full-gtd-test-file-lacks-p (file pattern)
  "Assert that FILE does not contain PATTERN.
FILE is the file path to check.
PATTERN is the string to search for."
  (with-temp-buffer
    (insert-file-contents file)
    (goto-char (point-min))
    (let ((case-fold-search nil))
      (not (search-forward pattern nil t)))))

(defun full-gtd-test-inbox-empty-p (base-dir)
  "Check if inbox is visually empty (missing or zero size).
BASE-DIR is the base directory to check."
  (let ((inbox (expand-file-name "inbox.org" base-dir)))
    (or (not (file-exists-p inbox))
        (= 0 (file-attribute-size (file-attributes inbox))))))

(defun full-gtd-test-cleanup-buffers (buffer-names)
  "Safely kill all buffers in BUFFER-NAMES, ignoring errors."
  (dolist (name buffer-names)
    (when-let ((buf (get-buffer name)))
      (with-current-buffer buf
        (setq buffer-read-only nil))
      (condition-case nil
          (kill-buffer buf)
        (error nil)))))

(defun full-gtd-test-task-exists-p (file title)
  "Check if task TITLE exists in FILE.
FILE is the file path to check.
TITLE is the task title to search for."
  (full-gtd-test-file-contains-p file (format "* %s" title)))

(defun full-gtd-test--create-files (temp-dir file-specs)
  "Create files in TEMP-DIR from FILE-SPECS.
Each spec is (FILENAME CONTENT).  CONTENT is a list of lines or a string."
  (dolist (spec file-specs)
    (let ((path (expand-file-name (car spec) temp-dir))
          (content (cdr spec)))
      (with-temp-file path
        (insert (if (stringp content)
                    content
                  (mapconcat #'identity content "\n")))))))

(defun full-gtd-test--cleanup (temp-dir)
  "Kill buffers visiting files under TEMP-DIR, then delete TEMP-DIR."
  (dolist (buf (buffer-list))
    (when (and (buffer-file-name buf)
               (string-prefix-p temp-dir (buffer-file-name buf)))
      (with-current-buffer buf
        (set-buffer-modified-p nil))
      (kill-buffer buf)))
  (when (file-directory-p temp-dir)
    (delete-directory temp-dir t)))

(defun full-gtd-test--debug-files (temp-dir file-names)
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

(defmacro full-gtd-test-define-story (name docstring &rest args)
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
       (let* ((temp-dir (make-temp-file "full-gtd-test-" t))
              (full-gtd-init-base-directory temp-dir)
              (full-gtd-test-caught-error nil))
         (unwind-protect
             (progn
               ,setup
               (full-gtd-test--create-files
                temp-dir
                (list ,@(mapcar (lambda (spec)
                                  `(cons ,(car spec) ,(cadr spec)))
                                files)))
               (cl-letf ,mock
                 ,body)
               (ert-info ((full-gtd-test--debug-files
                           temp-dir
                           ',(mapcar #'car files)))
                 ,asserts))
           (condition-case nil
               ,teardown
             (error nil))
           (full-gtd-test--cleanup temp-dir))))))

(provide 'full-gtd-utils-test)

;;; full-gtd-utils-test.el ends here
