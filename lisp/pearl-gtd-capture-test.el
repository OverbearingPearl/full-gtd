;;; pearl-gtd-test-capture.el --- User stories: Capture phase  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 OverbearingPearl
;; Author: OverbearingPearl <OverbearingPearl@outlook.com>
;; Assisted-by: Kimi:kimi-k2.5, DeepSeek:deepseek-v3.2, Claude:claude-sonnet-4.6
;; URL: https://github.com/OverbearingPearl/pearl-gtd
;; License: MIT
;; SPDX-License-Identifier: MIT

;;; Commentary:

;; User stories for capturing items into inbox.

;;; Code:

(require 'ert)
(require 'pearl-gtd)
(require 'pearl-gtd-test)

(pearl-gtd-test-define-story pearl-gtd-test-capture-user-captures-simple-idea-to-inbox
  "User runs M-x pearl-gtd-capture and inputs 'Buy milk'."
  :setup (pearl-gtd-init-initialize)
  :files nil
  :mock (((symbol-function 'read-string) (lambda (prompt &rest _)
                                           (cond
                                            ((string-match "Capture to inbox" prompt) "Buy milk")
                                            (t "")))))
  :body (pearl-gtd-capture)
  :asserts (progn
             (let ((inbox-file (expand-file-name "inbox.org" pearl-gtd-init-base-directory)))
               (should (pearl-gtd-test-file-contains-p-bool inbox-file "* Buy milk"))
               (should (pearl-gtd-test-file-contains-p-bool inbox-file ":ID:"))))
  :teardown nil)

(pearl-gtd-test-define-story pearl-gtd-test-capture-user-captures-idea-with-timestamp
  "Captured items automatically get CREATED timestamp."
  :setup (pearl-gtd-init-initialize)
  :files nil
  :mock (((symbol-function 'read-string) (lambda (prompt &rest _)
                                           (cond
                                            ((string-match "Capture to inbox" prompt) "Task with time")
                                            (t "")))))
  :body (pearl-gtd-capture)
  :asserts (progn
             (let ((inbox-file (expand-file-name "inbox.org" pearl-gtd-init-base-directory)))
               (should (pearl-gtd-test-file-contains-p-bool inbox-file ":CREATED:"))
               (should (pearl-gtd-test-file-contains-p-bool inbox-file ":ID:"))))
  :teardown nil)

(pearl-gtd-test-define-story pearl-gtd-test-capture-user-captures-empty-string-creates-nothing
  "User attempts to capture an empty string."
  :setup (pearl-gtd-init-initialize)
  :files nil
  :mock (((symbol-function 'read-string) (lambda (prompt &rest _)
                                           (cond
                                            ((string-match "Capture to inbox" prompt) "")
                                            (t "")))))
  :body (pearl-gtd-capture)
  :asserts (let ((inbox-file (expand-file-name "inbox.org" pearl-gtd-init-base-directory)))
             (let ((result (pearl-gtd-test-file-contains-p inbox-file "* ")))
               (should-not (car result))))
  :teardown nil)

(pearl-gtd-test-define-story pearl-gtd-test-capture-user-captures-special-chars
  "User captures task with special characters."
  :setup (pearl-gtd-init-initialize)
  :files nil
  :mock (((symbol-function 'read-string) (lambda (prompt &rest _)
                                           (cond
                                            ((string-match "Capture to inbox" prompt) "Fix [urgent] bug")
                                            (t "")))))
  :body (pearl-gtd-capture)
  :asserts (let ((inbox-file (expand-file-name "inbox.org" pearl-gtd-init-base-directory)))
             (should (pearl-gtd-test-file-contains-p-bool inbox-file "* Fix \\[urgent\\] bug")))
  :teardown nil)

(pearl-gtd-test-define-story pearl-gtd-test-capture-user-captures-very-long-title
  "User captures a very long title."
  :setup (pearl-gtd-init-initialize)
  :files nil
  :mock (((symbol-function 'read-string) (lambda (prompt &rest _)
                                           (cond
                                            ((string-match "Capture to inbox" prompt) "This is a very long title that exceeds normal length for testing purposes")
                                            (t "")))))
  :body (pearl-gtd-capture)
  :asserts (let ((inbox-file (expand-file-name "inbox.org" pearl-gtd-init-base-directory)))
             (should (pearl-gtd-test-file-contains-p-bool inbox-file "* This is a very long title that exceeds normal length for testing purposes")))
  :teardown nil)

(pearl-gtd-test-define-story pearl-gtd-test-capture-user-cancels-capture-when-inbox-has-content
  "User cancels capture when inbox already has content, inbox unchanged."
  :setup (pearl-gtd-init-initialize)
  :files (("inbox.org" "* Existing task\n"))
  :mock (((symbol-function 'read-string) (lambda (prompt &rest _)
                                           (cond
                                            ((string-match "Capture to inbox" prompt) "")
                                            (t "")))))
  :body (pearl-gtd-capture)
  :asserts (let ((inbox-file (expand-file-name "inbox.org" pearl-gtd-init-base-directory)))
             (let ((result1 (pearl-gtd-test-file-contains-p inbox-file "* Existing task")))
               (should (car result1)))
             (let ((result2 (pearl-gtd-test-file-contains-p inbox-file "* Existing task\n* ")))
               (should-not (car result2))))
  :teardown nil)

(pearl-gtd-test-define-story pearl-gtd-test-capture-user-captures-two-items-sequentially
  "User captures two items in sequence, both appear in inbox."
  :setup (pearl-gtd-init-initialize)
  :files nil
  :mock (((symbol-function 'read-string)
          (let ((count 0))
            (lambda (prompt &rest _)
              (setq count (1+ count))
              (cond
               ((and (= count 1) (string-match "Capture to inbox" prompt)) "First task")
               ((and (= count 2) (string-match "Capture to inbox" prompt)) "Second task")
               (t ""))))))
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

(pearl-gtd-test-define-story pearl-gtd-test-capture-user-captures-duplicate-titles
  "User captures two items with same title, both get unique IDs."
  :setup (pearl-gtd-init-initialize)
  :files nil
  :mock (((symbol-function 'read-string)
          (let ((count 0))
            (lambda (prompt &rest _)
              (setq count (1+ count))
              (cond
               ((and (= count 1) (string-match "Capture to inbox" prompt)) "Buy milk")
               ((and (= count 2) (string-match "Capture to inbox" prompt)) "Buy milk")
               (t ""))))))
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

(pearl-gtd-test-define-story pearl-gtd-test-capture-user-appends-to-existing-inbox
  "User captures to non-empty inbox, new task appended after existing."
  :setup (pearl-gtd-init-initialize)
  :files (("inbox.org" "* First existing task\n"))
  :mock (((symbol-function 'read-string) (lambda (prompt &rest _)
                                           (cond
                                            ((string-match "Capture to inbox" prompt) "New captured task")
                                            (t "")))))
  :body (pearl-gtd-capture)
  :asserts (let ((inbox-file (expand-file-name "inbox.org" pearl-gtd-init-base-directory)))
             (should (pearl-gtd-test-file-contains-p-bool inbox-file "* First existing task"))
             (should (pearl-gtd-test-file-contains-p-bool inbox-file "* New captured task")))
  :teardown nil)

(pearl-gtd-test-define-story pearl-gtd-test-capture-user-preserves-two-existing-tasks
  "Capture preserves two existing tasks in inbox."
  :setup (pearl-gtd-init-initialize)
  :files (("inbox.org" "* Task one\n* Task two\n"))
  :mock (((symbol-function 'read-string) (lambda (prompt &rest _)
                                           (cond
                                            ((string-match "Capture to inbox" prompt) "Third task")
                                            (t "")))))
  :body (pearl-gtd-capture)
  :asserts (let ((inbox-file (expand-file-name "inbox.org" pearl-gtd-init-base-directory)))
             (should (pearl-gtd-test-file-contains-p-bool inbox-file "* Task one"))
             (should (pearl-gtd-test-file-contains-p-bool inbox-file "* Task two"))
             (should (pearl-gtd-test-file-contains-p-bool inbox-file "* Third task")))
  :teardown nil)

(pearl-gtd-test-define-story pearl-gtd-test-capture-user-captures-mixed-special-chars-in-batch
  "User captures two items with special characters."
  :setup (pearl-gtd-init-initialize)
  :files nil
  :mock (((symbol-function 'read-string)
          (let ((count 0))
            (lambda (prompt &rest _)
              (setq count (1+ count))
              (cond
               ((and (= count 1) (string-match "Capture to inbox" prompt)) "Task [urgent] with brackets")
               ((and (= count 2) (string-match "Capture to inbox" prompt)) "Task * with asterisk")
               (t ""))))))
  :body (progn
          (pearl-gtd-capture)
          (pearl-gtd-capture))
  :asserts (let ((inbox-file (expand-file-name "inbox.org" pearl-gtd-init-base-directory)))
             (should (pearl-gtd-test-file-contains-p-bool inbox-file "* Task \\[urgent\\] with brackets"))
             (should (pearl-gtd-test-file-contains-p-bool inbox-file "* Task \\* with asterisk")))
  :teardown nil)

(pearl-gtd-test-define-story pearl-gtd-test-capture-user-quits-during-input
  "User presses C-g during capture input, nothing is saved."
  :setup (pearl-gtd-init-initialize)
  :files nil
  :mock (((symbol-function 'read-string) (lambda (prompt &rest _)
                                           (cond
                                            ((string-match "Capture to inbox" prompt) (signal 'quit nil))
                                            (t "")))))
  :body (progn
         (condition-case err
             (pearl-gtd-capture)
           (quit (setq pearl-gtd-test-caught-error err))))
:asserts (progn
           (should (pearl-gtd-test-inbox-empty-p pearl-gtd-init-base-directory))
           (should (eq (car pearl-gtd-test-caught-error) 'quit)))
  :teardown nil)

(pearl-gtd-test-define-story pearl-gtd-test-capture-sanitizes-newline-in-input
  "Newline in capture input must be sanitized to prevent entry injection."
  :setup (pearl-gtd-init-initialize)
  :files nil
  :mock (((symbol-function 'read-string) (lambda (prompt &rest _)
                                           (cond
                                            ((string-match "Capture to inbox" prompt) "Line1\n* Line2")
                                            (t "")))))
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

(pearl-gtd-test-define-story pearl-gtd-test-capture-strips-control-characters
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

(pearl-gtd-test-define-story pearl-gtd-test-capture-user-captures-very-long-headline
  "Headlines with 1000+ characters must be handled."
  :setup (pearl-gtd-init-initialize)
  :files nil
  :mock (((symbol-function 'read-string)
          (lambda (prompt &rest _)
            (cond
             ((string-match "Capture to inbox" prompt)
              (concat "Very long task: " (make-string 1000 ?X)))
             (t "")))))
  :body (pearl-gtd-capture)
  :asserts (let ((inbox-file (expand-file-name "inbox.org" pearl-gtd-init-base-directory)))
             (should (file-exists-p inbox-file))
             (let ((size (file-attribute-size (file-attributes inbox-file))))
               (should (> size 1000))))
  :teardown nil)

(provide 'pearl-gtd-test-capture)

;;; pearl-gtd-test-capture.el ends here
