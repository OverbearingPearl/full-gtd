;;; full-gtd-test-capture.el --- User stories: Capture phase  -*- lexical-binding: t; -*-

;;; Commentary:

;; User stories for capturing items into inbox.

;;; Code:

(require 'ert)
(require 'full-gtd)
(require 'full-gtd-test)

(full-gtd-test-define-story full-gtd-capture-test-user-captures-simple-idea-to-inbox
  "User runs M-x full-gtd-capture and inputs 'Buy milk'."
  :setup (full-gtd-init-initialize)
  :files nil
  :mock (((symbol-function 'read-string) (lambda (prompt &rest _)
                                           (cond
                                            ((string-match "Capture to inbox" prompt) "Buy milk")
                                            (t "")))))
  :body (full-gtd-capture)
  :asserts (progn
             (let ((inbox-file (expand-file-name "inbox.org" full-gtd-init-base-directory)))
               (should (full-gtd-test-file-contains-p-bool inbox-file "* Buy milk"))
               (should (full-gtd-test-file-contains-p-bool inbox-file ":ID:"))))
  :teardown nil)

(full-gtd-test-define-story full-gtd-capture-test-user-captures-idea-with-timestamp
  "Captured items automatically get CREATED timestamp."
  :setup (full-gtd-init-initialize)
  :files nil
  :mock (((symbol-function 'read-string) (lambda (prompt &rest _)
                                           (cond
                                            ((string-match "Capture to inbox" prompt) "Task with time")
                                            (t "")))))
  :body (full-gtd-capture)
  :asserts (progn
             (let ((inbox-file (expand-file-name "inbox.org" full-gtd-init-base-directory)))
               (should (full-gtd-test-file-contains-p-bool inbox-file ":CREATED:"))
               (should (full-gtd-test-file-contains-p-bool inbox-file ":ID:"))))
  :teardown nil)

(full-gtd-test-define-story full-gtd-capture-test-user-captures-empty-string-creates-nothing
  "User attempts to capture an empty string."
  :setup (full-gtd-init-initialize)
  :files nil
  :mock (((symbol-function 'read-string) (lambda (prompt &rest _)
                                           (cond
                                            ((string-match "Capture to inbox" prompt) "")
                                            (t "")))))
  :body (full-gtd-capture)
  :asserts (let ((inbox-file (expand-file-name "inbox.org" full-gtd-init-base-directory)))
             (let ((result (full-gtd-test-file-contains-p inbox-file "* ")))
               (should-not (car result))))
  :teardown nil)

(full-gtd-test-define-story full-gtd-capture-test-user-captures-special-chars
  "User captures task with special characters."
  :setup (full-gtd-init-initialize)
  :files nil
  :mock (((symbol-function 'read-string) (lambda (prompt &rest _)
                                           (cond
                                            ((string-match "Capture to inbox" prompt) "Fix [urgent] bug")
                                            (t "")))))
  :body (full-gtd-capture)
  :asserts (let ((inbox-file (expand-file-name "inbox.org" full-gtd-init-base-directory)))
             (should (full-gtd-test-file-contains-p-bool inbox-file "* Fix \\[urgent\\] bug")))
  :teardown nil)

(full-gtd-test-define-story full-gtd-capture-test-user-captures-very-long-title
  "User captures a very long title."
  :setup (full-gtd-init-initialize)
  :files nil
  :mock (((symbol-function 'read-string) (lambda (prompt &rest _)
                                           (cond
                                            ((string-match "Capture to inbox" prompt) "This is a very long title that exceeds normal length for testing purposes")
                                            (t "")))))
  :body (full-gtd-capture)
  :asserts (let ((inbox-file (expand-file-name "inbox.org" full-gtd-init-base-directory)))
             (should (full-gtd-test-file-contains-p-bool inbox-file "* This is a very long title that exceeds normal length for testing purposes")))
  :teardown nil)

(full-gtd-test-define-story full-gtd-capture-test-user-cancels-capture-when-inbox-has-content
  "User cancels capture when inbox already has content, inbox unchanged."
  :setup (full-gtd-init-initialize)
  :files (("inbox.org" "* Existing task\n"))
  :mock (((symbol-function 'read-string) (lambda (prompt &rest _)
                                           (cond
                                            ((string-match "Capture to inbox" prompt) "")
                                            (t "")))))
  :body (full-gtd-capture)
  :asserts (let ((inbox-file (expand-file-name "inbox.org" full-gtd-init-base-directory)))
             (let ((result1 (full-gtd-test-file-contains-p inbox-file "* Existing task")))
               (should (car result1)))
             (let ((result2 (full-gtd-test-file-contains-p inbox-file "* Existing task\n* ")))
               (should-not (car result2))))
  :teardown nil)

(full-gtd-test-define-story full-gtd-capture-test-user-captures-two-items-sequentially
  "User captures two items in sequence, both appear in inbox."
  :setup (full-gtd-init-initialize)
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
          (full-gtd-capture)
          (full-gtd-capture))
  :asserts (let ((inbox-file (expand-file-name "inbox.org" full-gtd-init-base-directory)))
             (should (full-gtd-test-file-contains-p-bool inbox-file "* First task"))
             (should (full-gtd-test-file-contains-p-bool inbox-file "* Second task"))
             (with-temp-buffer
               (insert-file-contents inbox-file)
               (goto-char (point-min))
               (should (search-forward ":ID:" nil t))
               (should (search-forward ":ID:" nil t))))
  :teardown nil)

(full-gtd-test-define-story full-gtd-capture-test-user-captures-duplicate-titles
  "User captures two items with same title, both get unique IDs."
  :setup (full-gtd-init-initialize)
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
          (full-gtd-capture)
          (full-gtd-capture))
  :asserts (let ((inbox-file (expand-file-name "inbox.org" full-gtd-init-base-directory)))
             (should (full-gtd-test-file-contains-p-bool inbox-file "* Buy milk"))
             (with-temp-buffer
               (insert-file-contents inbox-file)
               (goto-char (point-min))
               (should (search-forward ":ID:" nil t))
               (should (search-forward ":ID:" nil t))))
  :teardown nil)

(full-gtd-test-define-story full-gtd-capture-test-user-appends-to-existing-inbox
  "User captures to non-empty inbox, new task appended after existing."
  :setup (full-gtd-init-initialize)
  :files (("inbox.org" "* First existing task\n"))
  :mock (((symbol-function 'read-string) (lambda (prompt &rest _)
                                           (cond
                                            ((string-match "Capture to inbox" prompt) "New captured task")
                                            (t "")))))
  :body (full-gtd-capture)
  :asserts (let ((inbox-file (expand-file-name "inbox.org" full-gtd-init-base-directory)))
             (should (full-gtd-test-file-contains-p-bool inbox-file "* First existing task"))
             (should (full-gtd-test-file-contains-p-bool inbox-file "* New captured task")))
  :teardown nil)

(full-gtd-test-define-story full-gtd-capture-test-user-preserves-two-existing-tasks
  "Capture preserves two existing tasks in inbox."
  :setup (full-gtd-init-initialize)
  :files (("inbox.org" "* Task one\n* Task two\n"))
  :mock (((symbol-function 'read-string) (lambda (prompt &rest _)
                                           (cond
                                            ((string-match "Capture to inbox" prompt) "Third task")
                                            (t "")))))
  :body (full-gtd-capture)
  :asserts (let ((inbox-file (expand-file-name "inbox.org" full-gtd-init-base-directory)))
             (should (full-gtd-test-file-contains-p-bool inbox-file "* Task one"))
             (should (full-gtd-test-file-contains-p-bool inbox-file "* Task two"))
             (should (full-gtd-test-file-contains-p-bool inbox-file "* Third task")))
  :teardown nil)

(full-gtd-test-define-story full-gtd-capture-test-user-captures-mixed-special-chars-in-batch
  "User captures two items with special characters."
  :setup (full-gtd-init-initialize)
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
          (full-gtd-capture)
          (full-gtd-capture))
  :asserts (let ((inbox-file (expand-file-name "inbox.org" full-gtd-init-base-directory)))
             (should (full-gtd-test-file-contains-p-bool inbox-file "* Task \\[urgent\\] with brackets"))
             (should (full-gtd-test-file-contains-p-bool inbox-file "* Task \\* with asterisk")))
  :teardown nil)

(full-gtd-test-define-story full-gtd-capture-test-user-quits-during-input
  "User presses C-g during capture input, nothing is saved."
  :setup (full-gtd-init-initialize)
  :files nil
  :mock (((symbol-function 'read-string) (lambda (prompt &rest _)
                                           (cond
                                            ((string-match "Capture to inbox" prompt) (signal 'quit nil))
                                            (t "")))))
  :body (progn
         (condition-case err
             (full-gtd-capture)
           (quit (setq full-gtd-test-caught-error err))))
:asserts (progn
           (should (full-gtd-test-inbox-empty-p full-gtd-init-base-directory))
           (should (eq (car full-gtd-test-caught-error) 'quit)))
  :teardown nil)

(full-gtd-test-define-story full-gtd-capture-test-sanitizes-newline-in-input
  "Newline in capture input must be sanitized to prevent entry injection."
  :setup (full-gtd-init-initialize)
  :files nil
  :mock (((symbol-function 'read-string) (lambda (prompt &rest _)
                                           (cond
                                            ((string-match "Capture to inbox" prompt) "Line1\n* Line2")
                                            (t "")))))
  :body (full-gtd-capture)
  :asserts (let ((inbox-file (expand-file-name "inbox.org" full-gtd-init-base-directory)))
             (with-temp-buffer
               (insert-file-contents inbox-file)
               (goto-char (point-min))
               (let ((count 0))
                 (while (re-search-forward "^\\* " nil t)
                   (setq count (1+ count)))
                 (should (= count 1)))
               (should (search-forward "Line1" nil t))))
  :teardown nil)

(full-gtd-test-define-story full-gtd-capture-test-strips-control-characters
  "Control characters in input must be stripped or escaped."
  :setup (full-gtd-init-initialize)
  :files nil
  :mock (((symbol-function 'read-string) (lambda (&rest _) "Task\x00with\x01null")))
  :body (full-gtd-capture)
  :asserts (let ((inbox-file (expand-file-name "inbox.org" full-gtd-init-base-directory)))
             (with-temp-buffer
               (insert-file-contents inbox-file)
               (should-not (search-forward "\x00" nil t))
               (should-not (search-forward "\x01" nil t))))
  :teardown nil)

(full-gtd-test-define-story full-gtd-capture-test-user-captures-very-long-headline
  "Headlines with 1000+ characters must be handled."
  :setup (full-gtd-init-initialize)
  :files nil
  :mock (((symbol-function 'read-string)
          (lambda (prompt &rest _)
            (cond
             ((string-match "Capture to inbox" prompt)
              (concat "Very long task: " (make-string 1000 ?X)))
             (t "")))))
  :body (full-gtd-capture)
  :asserts (let ((inbox-file (expand-file-name "inbox.org" full-gtd-init-base-directory)))
             (should (file-exists-p inbox-file))
             (let ((size (file-attribute-size (file-attributes inbox-file))))
               (should (> size 1000))))
  :teardown nil)

(full-gtd-test-define-story full-gtd-capture-test-user-captures-with-leading-trailing-spaces
  "Leading and trailing spaces should be trimmed in capture."
  :setup (full-gtd-init-initialize)
  :files nil
  :mock (((symbol-function 'read-string) (lambda (&rest _) "  Task with spaces  ")))
  :body (full-gtd-capture)
  :asserts (let ((inbox-file (expand-file-name "inbox.org" full-gtd-init-base-directory)))
             (should (full-gtd-test-file-contains-p-bool inbox-file "* Task with spaces"))
             (should-not (full-gtd-test-file-contains-p-bool inbox-file "*  Task with spaces  ")))
  :teardown nil)

(full-gtd-test-define-story full-gtd-capture-test-user-captures-with-tabs
  "Tabs in input should be handled."
  :setup (full-gtd-init-initialize)
  :files nil
  :mock (((symbol-function 'read-string) (lambda (&rest _) "Task\twith\ttabs")))
  :body (full-gtd-capture)
  :asserts (let ((inbox-file (expand-file-name "inbox.org" full-gtd-init-base-directory)))
             (should (full-gtd-test-file-contains-p-bool inbox-file "* Task")))
  :teardown nil)

(full-gtd-test-define-story full-gtd-capture-test-user-captures-multiple-consecutive-spaces
  "Multiple consecutive spaces should be preserved or handled gracefully."
  :setup (full-gtd-init-initialize)
  :files nil
  :mock (((symbol-function 'read-string) (lambda (&rest _) "Task    with    spaces")))
  :body (full-gtd-capture)
  :asserts (let ((inbox-file (expand-file-name "inbox.org" full-gtd-init-base-directory)))
             (should (full-gtd-test-file-contains-p-bool inbox-file "* Task    with    spaces")))
  :teardown nil)

(full-gtd-test-define-story full-gtd-capture-test-user-captures-chinese-punctuation
  "Chinese punctuation should be handled correctly."
  :setup (full-gtd-init-initialize)
  :files nil
  :mock (((symbol-function 'read-string) (lambda (&rest _) "任务：测试【紧急】")))
  :body (full-gtd-capture)
  :asserts (let ((inbox-file (expand-file-name "inbox.org" full-gtd-init-base-directory)))
             (should (full-gtd-test-file-contains-p-bool inbox-file "任务：测试【紧急】")))
  :teardown nil)

(full-gtd-test-define-story full-gtd-capture-test-user-captures-org-special-chars
  "Org-mode special characters should be escaped or handled."
  :setup (full-gtd-init-initialize)
  :files nil
  :mock (((symbol-function 'read-string) (lambda (&rest _) "Task with *asterisk* and #hash")))
  :body (full-gtd-capture)
  :asserts (let ((inbox-file (expand-file-name "inbox.org" full-gtd-init-base-directory)))
             (should (full-gtd-test-file-contains-p-bool inbox-file "* Task with"))
             (should (full-gtd-test-file-contains-p-bool inbox-file ":ID:")))
  :teardown nil)

(full-gtd-test-define-story full-gtd-capture-test-user-captures-multiple-items-with-semicolons
  "User captures multiple items separated by semicolons, each becomes its own inbox entry."
  :setup (full-gtd-init-initialize)
  :files nil
  :mock (((symbol-function 'read-string) (lambda (prompt &rest _)
                                           (cond
                                            ((string-match "Capture to inbox" prompt) "Buy milk; Call mom; 写周报")
                                            (t "")))))
  :body (full-gtd-capture)
  :asserts (let ((inbox-file (expand-file-name "inbox.org" full-gtd-init-base-directory)))
             (should (full-gtd-test-file-contains-p-bool inbox-file "* Buy milk"))
             (should (full-gtd-test-file-contains-p-bool inbox-file "* Call mom"))
             (should (full-gtd-test-file-contains-p-bool inbox-file "* 写周报"))
             (with-temp-buffer
               (insert-file-contents inbox-file)
               (goto-char (point-min))
               (let ((id-count 0))
                 (while (re-search-forward "^:ID:" nil t)
                   (setq id-count (1+ id-count)))
                 (should (= id-count 3)))))
  :teardown nil)

(provide 'full-gtd-capture-test)

;;; full-gtd-capture-test.el ends here
