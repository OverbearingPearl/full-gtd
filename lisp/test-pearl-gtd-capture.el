;;; test-pearl-gtd-capture.el --- User stories: Capture phase  -*- lexical-binding: t; -*-

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
             (should (test-pearl-gtd-file-contains-p
                      (expand-file-name "inbox.org" pearl-gtd-init-base-directory)
                      "* Buy milk"))
             (should (test-pearl-gtd-file-contains-p
                      (expand-file-name "inbox.org" pearl-gtd-init-base-directory)
                      ":ID:")))
  :teardown nil)

(test-pearl-gtd-define-story test-pearl-gtd-capture-user-captures-idea-with-timestamp
  "Captured items automatically get CREATED timestamp."
  :setup (pearl-gtd-init-initialize)
  :files nil
  :mock (((symbol-function 'read-string) (lambda (&rest _) "Task with time")))
  :body (pearl-gtd-capture)
  :asserts (progn
             (should (test-pearl-gtd-file-contains-p
                      (expand-file-name "inbox.org" pearl-gtd-init-base-directory)
                      ":CREATED:"))
             (should (test-pearl-gtd-file-contains-p
                      (expand-file-name "inbox.org" pearl-gtd-init-base-directory)
                      ":ID:")))
  :teardown nil)

(test-pearl-gtd-define-story test-pearl-gtd-capture-user-captures-empty-string-creates-nothing
  "User attempts to capture an empty string."
  :setup (pearl-gtd-init-initialize)
  :files nil
  :mock (((symbol-function 'read-string) (lambda (&rest _) "")))
  :body (pearl-gtd-capture)
  :asserts (should-not (test-pearl-gtd-file-contains-p
                        (expand-file-name "inbox.org" pearl-gtd-init-base-directory)
                        "* "))
  :teardown nil)

(test-pearl-gtd-define-story test-pearl-gtd-capture-user-captures-special-chars
  "User captures task with special characters."
  :setup (pearl-gtd-init-initialize)
  :files nil
  :mock (((symbol-function 'read-string) (lambda (&rest _) "Fix [urgent] bug")))
  :body (pearl-gtd-capture)
  :asserts (should (test-pearl-gtd-file-contains-p
                    (expand-file-name "inbox.org" pearl-gtd-init-base-directory)
                    "* Fix \\[urgent\\] bug"))
  :teardown nil)

(test-pearl-gtd-define-story test-pearl-gtd-capture-user-captures-very-long-title
  "User captures a very long title."
  :setup (pearl-gtd-init-initialize)
  :files nil
  :mock (((symbol-function 'read-string) (lambda (&rest _) "This is a very long title that exceeds normal length for testing purposes")))
  :body (pearl-gtd-capture)
  :asserts (should (test-pearl-gtd-file-contains-p
                    (expand-file-name "inbox.org" pearl-gtd-init-base-directory)
                    "* This is a very long title that exceeds normal length for testing purposes"))
  :teardown nil)

(test-pearl-gtd-define-story test-pearl-gtd-capture-user-skips-capture-when-inbox-has-content
  "User cancels capture when inbox already has content, inbox unchanged."
  :setup (pearl-gtd-init-initialize)
  :files (("inbox.org" "* Existing task\n"))
  :mock (((symbol-function 'read-string) (lambda (&rest _) "")))
  :body (pearl-gtd-capture)
  :asserts (progn
             (should (test-pearl-gtd-file-contains-p
                      (expand-file-name "inbox.org" pearl-gtd-init-base-directory)
                      "* Existing task"))
             (should-not (test-pearl-gtd-file-contains-p
                          (expand-file-name "inbox.org" pearl-gtd-init-base-directory)
                          "* Existing task\n* ")))
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
  :asserts (progn
             (should (test-pearl-gtd-file-contains-p
                      (expand-file-name "inbox.org" pearl-gtd-init-base-directory)
                      "* First task"))
             (should (test-pearl-gtd-file-contains-p
                      (expand-file-name "inbox.org" pearl-gtd-init-base-directory)
                      "* Second task"))
             ;; Verify both have IDs
             (with-temp-buffer
               (insert-file-contents (expand-file-name "inbox.org" pearl-gtd-init-base-directory))
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
  :asserts (progn
             ;; Both entries exist
             (should (test-pearl-gtd-file-contains-p
                      (expand-file-name "inbox.org" pearl-gtd-init-base-directory)
                      "* Buy milk"))
             ;; Both have IDs (should find two :ID: occurrences)
             (with-temp-buffer
               (insert-file-contents (expand-file-name "inbox.org" pearl-gtd-init-base-directory))
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
  :asserts (progn
             (should (test-pearl-gtd-file-contains-p
                      (expand-file-name "inbox.org" pearl-gtd-init-base-directory)
                      "* First existing task"))
             (should (test-pearl-gtd-file-contains-p
                      (expand-file-name "inbox.org" pearl-gtd-init-base-directory)
                      "* New captured task")))
  :teardown nil)

(test-pearl-gtd-define-story test-pearl-gtd-capture-preserves-two-existing-tasks
  "Capture preserves two existing tasks in inbox."
  :setup (pearl-gtd-init-initialize)
  :files (("inbox.org" "* Task one\n* Task two\n"))
  :mock (((symbol-function 'read-string) (lambda (&rest _) "Third task")))
  :body (pearl-gtd-capture)
  :asserts (progn
             (should (test-pearl-gtd-file-contains-p
                      (expand-file-name "inbox.org" pearl-gtd-init-base-directory)
                      "* Task one"))
             (should (test-pearl-gtd-file-contains-p
                      (expand-file-name "inbox.org" pearl-gtd-init-base-directory)
                      "* Task two"))
             (should (test-pearl-gtd-file-contains-p
                      (expand-file-name "inbox.org" pearl-gtd-init-base-directory)
                      "* Third task")))
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
  :asserts (progn
             (should (test-pearl-gtd-file-contains-p
                      (expand-file-name "inbox.org" pearl-gtd-init-base-directory)
                      "* Task \\[urgent\\] with brackets"))
             (should (test-pearl-gtd-file-contains-p
                      (expand-file-name "inbox.org" pearl-gtd-init-base-directory)
                      "* Task \\* with asterisk")))
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
:asserts (progn
           (should (test-pearl-gtd-inbox-empty-p pearl-gtd-init-base-directory))
           (should (eq (car test-pearl-gtd-caught-error) 'quit)))
  :teardown nil)

(provide 'test-pearl-gtd-capture)

;;; test-pearl-gtd-capture.el ends here
