;;; test-pearl-gtd.el --- Test infrastructure and entry point  -*- lexical-binding: t; -*-

;;; Commentary:

;; This file provides shared infrastructure for Pearl-GTD user story tests.
;; It contains assertion helpers and test runners.

;;; Code:

(require 'ert)
(require 'cl-lib)

(defvar test-pearl-gtd-caught-error nil
  "Variable to store caught errors during tests.")

(defun test-pearl-gtd-file-contains-p (file pattern)
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

(defun test-pearl-gtd-file-contains-p-bool (file pattern)
  "Return t if FILE contains PATTERN, nil otherwise.
FILE is the file path to check.
PATTERN is the regex pattern to search for."
  (car (test-pearl-gtd-file-contains-p file pattern)))

(defun test-pearl-gtd-file-lacks-p (file pattern)
  "Assert that FILE does not contain PATTERN.
FILE is the file path to check.
PATTERN is the string to search for."
  (with-temp-buffer
    (insert-file-contents file)
    (goto-char (point-min))
    (let ((case-fold-search nil))
      (not (search-forward pattern nil t)))))

(defun test-pearl-gtd-inbox-empty-p (base-dir)
  "Check if inbox is visually empty (missing or zero size).
BASE-DIR is the base directory to check."
  (let ((inbox (expand-file-name "inbox.org" base-dir)))
    (or (not (file-exists-p inbox))
        (= 0 (file-attribute-size (file-attributes inbox))))))

(defun test-pearl-gtd-task-exists-p (file title)
  "Check if task TITLE exists in FILE.
FILE is the file path to check.
TITLE is the task title to search for."
  (test-pearl-gtd-file-contains-p file (format "* %s" title)))

(defmacro test-pearl-gtd-define-story (name docstring &rest args)
  "Define a user story test named NAME with DOCSTRING.
ARGS is a plist with keys:
:setup - Form to run before test
:files - List of (filename content) to create, content can be expression
:mock - List of `cl-letf` bindings for user input simulation
:body - The test body form
:asserts - Assertion forms
:teardown - Cleanup form"
  (declare (indent defun))
  (let ((setup (plist-get args :setup))
        (files (plist-get args :files))
        (mock (plist-get args :mock))
        (body (plist-get args :body))
        (asserts (plist-get args :asserts))
        (teardown (plist-get args :teardown)))
    `(ert-deftest ,name ()
       ,docstring
       (let* ((temp-dir (make-temp-file "test-pearl-gtd-" t))
              (pearl-gtd-init-base-directory temp-dir)
              (test-pearl-gtd-caught-error nil)
              (test-pearl-gtd--files ',files))
         (unwind-protect
             (progn
               (setq pearl-gtd-inbox--current-test-name ',name)
               ,setup
               ;; Create test files - evaluate content expressions at runtime
               ,@(mapcar (lambda (file-spec)
                          `(let ((file ,(car file-spec))
                                 (content ,(cadr file-spec)))
                             (with-temp-file (expand-file-name file temp-dir)
                               (insert content))))
                        files)
               ;; Run test with mocks
               (cl-letf ,mock
                 ,body
                 (condition-case err
                     ,asserts
                   (ert-test-failed
                    (let ((debug-info
                           (concat
                            "=== TEST FAILED: " (symbol-name ',name) " ===\n\n"
                            "=== FILE CONTENTS ===\n\n"
                            (mapconcat (lambda (f)
                                         (let* ((fname (car f))
                                                (path (expand-file-name fname temp-dir))
                                                (content (if (file-exists-p path)
                                                             (with-temp-buffer
                                                               (insert-file-contents path)
                                                               (buffer-string))
                                                           "File does not exist")))
                                           (format "-- %s --\n%s" fname content)))
                                       test-pearl-gtd--files "\n\n")
                            "\n\n=== END FILE CONTENTS ===\n\n"
                            "Original error: " (error-message-string err))))
                      (ert-fail debug-info))))))
           (ignore-errors ,teardown)
           ;; First save and kill buffers
           (dolist (buf (buffer-list))
             (when (and (buffer-file-name buf)
                        (string-prefix-p temp-dir (buffer-file-name buf)))
               (when (buffer-modified-p buf)
                 (with-current-buffer buf
                   (save-buffer)))
               (kill-buffer buf)))
           ;; Then delete files
           (dolist (file (directory-files temp-dir t "\\.org$"))
             (when (file-exists-p file)
               (delete-file file)))
           ;; Finally delete directory
           (delete-directory temp-dir))))))

(provide 'test-pearl-gtd)

;;; test-pearl-gtd.el ends here
