;;; pearl-gtd-test-capture.el --- User stories: Capture phase  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 OverbearingPearl
;; Author: OverbearingPearl <OverbearingPearl@outlook.com>
;; Assisted-by: Kimi:kimi-k2.5, DeepSeek:deepseek-v3.2, Claude:claude-sonnet-4.6
;; URL: https://github.com/OverbearingPearl/pearl-gtd
;; SPDX-License-Identifier: MIT

;;; Commentary:

;; User stories for capturing items into inbox.

;;; Code:

(require 'ert)
(require 'pearl-gtd)
(require 'pearl-gtd-test)

(pearl-gtd-test-define-story pearl-gtd-capture-user-captures-simple-idea-to-inbox-test
  "User runs M-x pearl-gtd-capture and inputs 'Buy milk'."
  :setup (pearl-gtd-init-initialize)
  :files nil
  :mock (((symbol-function 'read-string) (lambda (&rest _) "Buy milk")))
  :body (pearl-gtd-capture)
  :asserts (progn
             (let ((inbox-file (expand-file-name "inbox.org" pearl-gtd-init-base-directory)))
               (should (pearl-gtd-test-file-contains-p-bool inbox-file "* Buy milk"))
               (should (pearl-gtd-test-file-contains-p-bool inbox-file ":ID:"))))
  :teardown nil)

(pearl-gtd-test-define-story pearl-gtd-capture-user-captures-idea-with-timestamp-test
  "Captured items automatically get CREATED timestamp."
  :setup (pearl-gtd-init-initialize)
  :files nil
  :mock (((symbol-function 'read-string) (lambda (&rest _) "Task with time")))
  :body (pearl-gtd-capture)
  :asserts (progn
             (let ((inbox-file (expand-file-name "inbox.org" pearl-gtd-init-base-directory)))
               (should (pearl-gtd-test-file-contains-p-bool inbox-file ":CREATED:"))
               (should (pearl-gtd-test-file-contains-p-bool inbox-file ":ID:"))))
  :teardown nil)

(pearl-gtd-test-define-story pearl-gtd-capture-user-captures-empty-string-creates-nothing-test
  "User attempts to capture an empty string."
  :setup (pearl-gtd-init-initialize)
  :files nil
  :mock (((symbol-function 'read-string) (lambda (&rest _) "")))
  :body (pearl-gtd-capture)
  :asserts (let ((inbox-file (expand-file-name "inbox.org" pearl-gtd-init-base-directory)))
             (let ((result (pearl-gtd-test-file-contains-p inbox-file "* ")))
               (should-not (car result))))
  :teardown nil)

(pearl-gtd-test-define-story pearl-gtd-capture-user-captures-special-chars-test
  "User captures task with special characters."
  :setup (pearl-gtd-init-initialize)
  :files nil
  :mock (((symbol-function 'read-string) (lambda (&rest _) "Fix [urgent] bug")))
  :body (pearl-gtd-capture)
  :asserts (let ((inbox-file (expand-file-name "inbox.org" pearl-gtd-init-base-directory)))
             (should (pearl-gtd-test-file-contains-p-bool inbox-file "* Fix \\[urgent\\] bug")))
  :teardown nil)

(pearl-gtd-test-define-story pearl-gtd-capture-user-captures-very-long-title-test
  "User captures a very long title."
  :setup (pearl-gtd-init-initialize)
  :files nil
  :mock (((symbol-function 'read-string) (lambda (&rest _) "This is a very long title that exceeds normal length for testing purposes")))
  :body (pearl-gtd-capture)
  :asserts (let ((inbox-file (expand-file-name "inbox.org" pearl-gtd-init-base-directory)))
             (should (pearl-gtd-test-file-contains-p-bool inbox-file "* This is a very long title that exceeds normal length for testing purposes")))
  :teardown nil)

(pearl-gtd-test-define-story pearl-gtd-capture-user-cancels-capture-when-inbox-has-content-test
  "User cancels capture when inbox already has content, inbox unchanged."
  :setup (pearl-gtd-init-initialize)
  :files (("inbox.org" "* Existing task\n"))
  :mock (((symbol-function 'read-string) (lambda (&rest _) "")))
  :body (pearl-gtd-capture)
  :asserts (let ((inbox-file (expand-file-name "inbox.org" pearl-gtd-init-base-directory)))
             (let ((result1 (pearl-gtd-test-file-contains-p inbox-file "* Existing task")))
               (should (car result1)))
             (let ((result2 (pearl-gtd-test-file-contains-p inbox-file "* Existing task\n* ")))
               (should-not (car result2))))
  :teardown nil)

(pearl-gtd-test-define-story pearl-gtd-capture-user-captures-two-items-sequentially-test
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
             (should (pearl-gtd-test-file-contains-p-bool inbox-file "* First task"))
             (should (pearl-gtd-test-file-contains-p-bool inbox-file "* Second task"))
             (with-temp-buffer
               (insert-file-contents inbox-file)
               (goto-char (point-min))
               (should (search-forward ":ID:" nil t))
               (should (search-forward ":ID:" nil t))))
  :teardown nil)

(pearl-gtd-test-define-story pearl-gtd-capture-user-captures-duplicate-titles-test
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
             (should (pearl-gtd-test-file-contains-p-bool inbox-file "* Buy milk"))
             (with-temp-buffer
               (insert-file-contents inbox-file)
               (goto-char (point-min))
               (should (search-forward ":ID:" nil t))
               (should (search-forward ":ID:" nil t))))
  :teardown nil)

(pearl-gtd-test-define-story pearl-gtd-capture-user-appends-to-existing-inbox-test
  "User captures to non-empty inbox, new task appended after existing."
  :setup (pearl-gtd-init-initialize)
  :files (("inbox.org" "* First existing task\n"))
  :mock (((symbol-function 'read-string) (lambda (&rest _) "New captured task")))
  :body (pearl-gtd-capture)
  :asserts (let ((inbox-file (expand-file-name "inbox.org" pearl-gtd-init-base-directory)))
             (should (pearl-gtd-test-file-contains-p-bool inbox-file "* First existing task"))
             (should (pearl-gtd-test-file-contains-p-bool inbox-file "* New captured task")))
  :teardown nil)

(pearl-gtd-test-define-story pearl-gtd-capture-user-preserves-two-existing-tasks-test
  "Capture preserves two existing tasks in inbox."
  :setup (pearl-gtd-init-initialize)
  :files (("inbox.org" "* Task one\n* Task two\n"))
  :mock (((symbol-function 'read-string) (lambda (&rest _) "Third task")))
  :body (pearl-gtd-capture)
  :asserts (let ((inbox-file (expand-file-name "inbox.org" pearl-gtd-init-base-directory)))
             (should (pearl-gtd-test-file-contains-p-bool inbox-file "* Task one"))
             (should (pearl-gtd-test-file-contains-p-bool inbox-file "* Task two"))
             (should (pearl-gtd-test-file-contains-p-bool inbox-file "* Third task")))
  :teardown nil)

(pearl-gtd-test-define-story pearl-gtd-capture-user-captures-mixed-special-chars-in-batch-test
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
             (should (pearl-gtd-test-file-contains-p-bool inbox-file "* Task \\[urgent\\] with brackets"))
             (should (pearl-gtd-test-file-contains-p-bool inbox-file "* Task \\* with asterisk")))
  :teardown nil)

(pearl-gtd-test-define-story pearl-gtd-capture-user-quits-during-input-test
  "User presses C-g during capture input, nothing is saved."
  :setup (pearl-gtd-init-initialize)
  :files nil
  :mock (((symbol-function 'read-string) (lambda (&rest _) (signal 'quit nil))))
  :body (progn
         (condition-case err
             (pearl-gtd-capture)
           (quit (setq pearl-gtd-test-caught-error err))))
:asserts (progn
           (should (pearl-gtd-test-inbox-empty-p pearl-gtd-init-base-directory))
           (should (eq (car pearl-gtd-test-caught-error) 'quit)))
  :teardown nil)

(pearl-gtd-test-define-story pearl-gtd-capture-sanitizes-newline-in-input-test
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

(pearl-gtd-test-define-story pearl-gtd-capture-strips-control-characters-test
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

(pearl-gtd-test-define-story pearl-gtd-capture-user-captures-very-long-headline-test
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

(provide 'pearl-gtd-test-capture)

;;; pearl-gtd-test-capture.el ends here
