;;; test-pearl-gtd-capture.el --- User stories: Capture phase  -*- lexical-binding: t; -*-

;; License: MIT
;; URL: https://github.com/OverbearingPearl/pearl-gtd
;; Package-Requires: ((emacs "27.1") (ert "1.0") (cl-lib "0.5"))

;;; Commentary:

;; User stories for capturing items into inbox.

;;; Code:

(require 'ert)
(require 'pearl-gtd)
(require 'test-pearl-gtd)

(test-pearl-gtd-define-story test-pearl-gtd-capture-user-captures-simple-idea-to-inbox
  "User runs M-x pearl-gtd-capture and inputs 'Buy milk'."
  :setup (pearl-gtd-init-initialize)
  :files nil
  :mock (((symbol-function 'read-string) (lambda (&rest _) "Buy milk")))
  :body (pearl-gtd-capture)
  :asserts (progn
             (let ((inbox-file (expand-file-name "inbox.org" pearl-gtd-init-base-directory)))
               (should (test-pearl-gtd-file-contains-p-bool inbox-file "* Buy milk"))
               (should (test-pearl-gtd-file-contains-p-bool inbox-file ":ID:"))))
  :teardown nil)

(test-pearl-gtd-define-story test-pearl-gtd-capture-user-captures-idea-with-timestamp
  "Captured items automatically get CREATED timestamp."
  :setup (pearl-gtd-init-initialize)
  :files nil
  :mock (((symbol-function 'read-string) (lambda (&rest _) "Task with time")))
  :body (pearl-gtd-capture)
  :asserts (progn
             (let ((inbox-file (expand-file-name "inbox.org" pearl-gtd-init-base-directory)))
               (should (test-pearl-gtd-file-contains-p-bool inbox-file ":CREATED:"))
               (should (test-pearl-gtd-file-contains-p-bool inbox-file ":ID:"))))
  :teardown nil)

(test-pearl-gtd-define-story test-pearl-gtd-capture-user-captures-empty-string-creates-nothing
  "User attempts to capture an empty string."
  :setup (pearl-gtd-init-initialize)
  :files nil
  :mock (((symbol-function 'read-string) (lambda (&rest _) "")))
  :body (pearl-gtd-capture)
  :asserts (let ((inbox-file (expand-file-name "inbox.org" pearl-gtd-init-base-directory)))
             (let ((result (test-pearl-gtd-file-contains-p inbox-file "* ")))
               (should-not (car result))))
  :teardown nil)

(test-pearl-gtd-define-story test-pearl-gtd-capture-user-captures-special-chars
  "User captures task with special characters."
  :setup (pearl-gtd-init-initialize)
  :files nil
  :mock (((symbol-function 'read-string) (lambda (&rest _) "Fix [urgent] bug")))
  :body (pearl-gtd-capture)
  :asserts (let ((inbox-file (expand-file-name "inbox.org" pearl-gtd-init-base-directory)))
             (should (test-pearl-gtd-file-contains-p-bool inbox-file "* Fix \\[urgent\\] bug")))
  :teardown nil)

(test-pearl-gtd-define-story test-pearl-gtd-capture-user-captures-very-long-title
  "User captures a very long title."
  :setup (pearl-gtd-init-initialize)
  :files nil
  :mock (((symbol-function 'read-string) (lambda (&rest _) "This is a very long title that exceeds normal length for testing purposes")))
  :body (pearl-gtd-capture)
  :asserts (let ((inbox-file (expand-file-name "inbox.org" pearl-gtd-init-base-directory)))
             (should (test-pearl-gtd-file-contains-p-bool inbox-file "* This is a very long title that exceeds normal length for testing purposes")))
  :teardown nil)

(test-pearl-gtd-define-story test-pearl-gtd-capture-user-cancels-capture-when-inbox-has-content
  "User cancels capture when inbox already has content, inbox unchanged."
  :setup (pearl-gtd-init-initialize)
  :files (("inbox.org" "* Existing task\n"))
  :mock (((symbol-function 'read-string) (lambda (&rest _) "")))
  :body (pearl-gtd-capture)
  :asserts (let ((inbox-file (expand-file-name "inbox.org" pearl-gtd-init-base-directory)))
             (let ((result1 (test-pearl-gtd-file-contains-p inbox-file "* Existing task")))
               (should (car result1)))
             (let ((result2 (test-pearl-gtd-file-contains-p inbox-file "* Existing task\n* ")))
               (should-not (car result2))))
  :teardown nil)

(test-pearl-gtd-define-story test-pearl-gtd-capture-user-captures-two-items-sequentially
  "User captures two items in sequence, both appear in inbox."
  :setup (pearl-gtd-init-initialize)
  :files nil
  :mock (((symbol-function 'read-string)
          (let ((count 0))
            (lambda (&rest _)
              (setq count (1+ count))
              (if (= count 1) "First task" "Second task")))))
  :body (progn
          (pearl-gtd-capture)
          (pearl-gtd-capture))
  :asserts (let ((inbox-file (expand-file-name "inbox.org" pearl-gtd-init-base-directory)))
             (should (test-pearl-gtd-file-contains-p-bool inbox-file "* First task"))
             (should (test-pearl-gtd-file-contains-p-bool inbox-file "* Second task"))
             (with-temp-buffer
               (insert-file-contents inbox-file)
               (goto-char (point-min))
               (should (search-forward ":ID:" nil t))
               (should (search-forward ":ID:" nil t))))
  :teardown nil)

(test-pearl-gtd-define-story test-pearl-gtd-capture-user-captures-duplicate-titles
  "User captures two items with same title, both get unique IDs."
  :setup (pearl-gtd-init-initialize)
  :files nil
  :mock (((symbol-function 'read-string)
          (let ((count 0))
            (lambda (&rest _)
              (setq count (1+ count))
              (if (= count 1) "Buy milk" "Buy milk")))))
  :body (progn
          (pearl-gtd-capture)
          (pearl-gtd-capture))
  :asserts (let ((inbox-file (expand-file-name "inbox.org" pearl-gtd-init-base-directory)))
             (should (test-pearl-gtd-file-contains-p-bool inbox-file "* Buy milk"))
             (with-temp-buffer
               (insert-file-contents inbox-file)
               (goto-char (point-min))
               (should (search-forward ":ID:" nil t))
               (should (search-forward ":ID:" nil t))))
  :teardown nil)

(test-pearl-gtd-define-story test-pearl-gtd-capture-user-appends-to-existing-inbox
  "User captures to non-empty inbox, new task appended after existing."
  :setup (pearl-gtd-init-initialize)
  :files (("inbox.org" "* First existing task\n"))
  :mock (((symbol-function 'read-string) (lambda (&rest _) "New captured task")))
  :body (pearl-gtd-capture)
  :asserts (let ((inbox-file (expand-file-name "inbox.org" pearl-gtd-init-base-directory)))
             (should (test-pearl-gtd-file-contains-p-bool inbox-file "* First existing task"))
             (should (test-pearl-gtd-file-contains-p-bool inbox-file "* New captured task")))
  :teardown nil)

(test-pearl-gtd-define-story test-pearl-gtd-capture-user-preserves-two-existing-tasks
  "Capture preserves two existing tasks in inbox."
  :setup (pearl-gtd-init-initialize)
  :files (("inbox.org" "* Task one\n* Task two\n"))
  :mock (((symbol-function 'read-string) (lambda (&rest _) "Third task")))
  :body (pearl-gtd-capture)
  :asserts (let ((inbox-file (expand-file-name "inbox.org" pearl-gtd-init-base-directory)))
             (should (test-pearl-gtd-file-contains-p-bool inbox-file "* Task one"))
             (should (test-pearl-gtd-file-contains-p-bool inbox-file "* Task two"))
             (should (test-pearl-gtd-file-contains-p-bool inbox-file "* Third task")))
  :teardown nil)

(test-pearl-gtd-define-story test-pearl-gtd-capture-user-captures-mixed-special-chars-in-batch
  "User captures two items with special characters."
  :setup (pearl-gtd-init-initialize)
  :files nil
  :mock (((symbol-function 'read-string)
          (let ((count 0))
            (lambda (&rest _)
              (setq count (1+ count))
              (cond
               ((= count 1) "Task [urgent] with brackets")
               ((= count 2) "Task * with asterisk")
               (t ""))))))
  :body (progn
          (pearl-gtd-capture)
          (pearl-gtd-capture))
  :asserts (let ((inbox-file (expand-file-name "inbox.org" pearl-gtd-init-base-directory)))
             (should (test-pearl-gtd-file-contains-p-bool inbox-file "* Task \\[urgent\\] with brackets"))
             (should (test-pearl-gtd-file-contains-p-bool inbox-file "* Task \\* with asterisk")))
  :teardown nil)

(test-pearl-gtd-define-story test-pearl-gtd-capture-user-quits-during-input
  "User presses C-g during capture input, nothing is saved."
  :setup (pearl-gtd-init-initialize)
  :files nil
  :mock (((symbol-function 'read-string) (lambda (&rest _) (signal 'quit nil))))
  :body (progn
         (condition-case err
             (pearl-gtd-capture)
           (quit (setq test-pearl-gtd-caught-error err))))
:asserts (let ((inbox-file (expand-file-name "inbox.org" pearl-gtd-init-base-directory)))
           (should (test-pearl-gtd-inbox-empty-p pearl-gtd-init-base-directory))
           (should (eq (car test-pearl-gtd-caught-error) 'quit)))
  :teardown nil)

(test-pearl-gtd-define-story test-pearl-gtd-capture-sanitizes-newline-in-input
  "Newline in capture input must be sanitized to prevent entry injection."
  :setup (pearl-gtd-init-initialize)
  :files nil
  :mock (((symbol-function 'read-string) (lambda (&rest _) "Line1\n* Line2")))
  :body (pearl-gtd-capture)
  :asserts (let ((inbox-file (expand-file-name "inbox.org" pearl-gtd-init-base-directory)))
             (with-temp-buffer
               (insert-file-contents inbox-file)
               (goto-char (point-min))
               (let ((count 0))
                 (while (re-search-forward "^\\* " nil t)
                   (setq count (1+ count)))
                 (should (= count 1)))
               (should (search-forward "Line1" nil t))))
  :teardown nil)

(test-pearl-gtd-define-story test-pearl-gtd-capture-strips-control-characters
  "Control characters in input must be stripped or escaped."
  :setup (pearl-gtd-init-initialize)
  :files nil
  :mock (((symbol-function 'read-string) (lambda (&rest _) "Task\x00with\x01null")))
  :body (pearl-gtd-capture)
  :asserts (let ((inbox-file (expand-file-name "inbox.org" pearl-gtd-init-base-directory)))
             (with-temp-buffer
               (insert-file-contents inbox-file)
               (should-not (search-forward "\x00" nil t))
               (should-not (search-forward "\x01" nil t))))
  :teardown nil)

(test-pearl-gtd-define-story test-pearl-gtd-capture-user-captures-very-long-headline
  "Headlines with 1000+ characters must be handled."
  :setup (pearl-gtd-init-initialize)
  :files nil
  :mock (((symbol-function 'read-string)
          (lambda (&rest _)
            (concat "Very long task: " (make-string 1000 ?X)))))
  :body (pearl-gtd-capture)
  :asserts (let ((inbox-file (expand-file-name "inbox.org" pearl-gtd-init-base-directory)))
             (should (file-exists-p inbox-file))
             (let ((size (file-attribute-size (file-attributes inbox-file))))
               (should (> size 1000))))
  :teardown nil)

(provide 'test-pearl-gtd-capture)

;;; test-pearl-gtd-capture.el ends here
