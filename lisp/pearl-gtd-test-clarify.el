;;; pearl-gtd-test-clarify.el --- User stories: Clarify phase  -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: MIT
;; URL: https://github.com/OverbearingPearl/pearl-gtd

;;; Commentary:

;; User stories for clarifying inbox items.

;;; Code:

(when load-file-name
  (add-to-list 'load-path (file-name-directory load-file-name)))
(require 'ert)
(require 'pearl-gtd)
(require 'pearl-gtd-test)

(pearl-gtd-test-define-story pearl-gtd-test-clarify-user-renames-unclear-task
  "User renames 'Stuff' to 'Buy birthday gift for mom' during processing."
  :setup (pearl-gtd-init-initialize)
  :files (("inbox.org" "* Stuff\n:PROPERTIES:\n:ID: test-id-1\n:END:\n"))
  :mock (((symbol-function 'y-or-n-p) (lambda (&rest _) nil))
         ((symbol-function 'read-string)
          (lambda (prompt &rest _)
            (cond
             ((string-match "Rename" prompt) "Buy birthday gift for mom")
             ((string-match "Add remarks" prompt) "")
             ((string-match "Assign" prompt) "reference")
             (t ""))))
         ((symbol-function 'completing-read)
          (lambda (prompt _collection &rest _)
            (cond
             ((string-match "Assign" prompt) "reference")
             (t "")))))
  :body (pearl-gtd-process-inbox)
  :asserts (progn
             (should (pearl-gtd-test-file-contains-p
                      (expand-file-name "reference.org" pearl-gtd-init-base-directory)
                      "* Buy birthday gift for mom"))
             (should (pearl-gtd-test-file-lacks-p
                      (expand-file-name "reference.org" pearl-gtd-init-base-directory)
                      "* Stuff"))
             ;; Verify ID is preserved after rename
             (should (pearl-gtd-test-file-contains-p
                      (expand-file-name "reference.org" pearl-gtd-init-base-directory)
                      ":ID:")))
  :teardown nil)

(pearl-gtd-test-define-story pearl-gtd-test-clarify-user-adds-notes-to-task
  "User adds 'Check Amazon first' as notes to a task."
  :setup (pearl-gtd-init-initialize)
  :files (("inbox.org" "* Research laptop\n"))
  :mock (((symbol-function 'y-or-n-p) (lambda (&rest _) nil))
         ((symbol-function 'read-string)
          (lambda (prompt &rest _)
            (cond
             ((string-match "Rename" prompt) "")
             ((string-match "Add remarks" prompt) "Check Amazon first")
             ((string-match "Assign" prompt) "reference")
             (t ""))))
         ((symbol-function 'completing-read)
          (lambda (prompt _collection &rest _)
            (cond
             ((string-match "Assign" prompt) "reference")
             (t "")))))
  :body (pearl-gtd-process-inbox)
  :asserts (pearl-gtd-test-file-contains-p
            (expand-file-name "reference.org" pearl-gtd-init-base-directory)
            "Check Amazon first")
  :teardown nil)

(pearl-gtd-test-define-story pearl-gtd-test-clarify-user-skips-all-clarifications
  "User skips all clarifications during processing."
  :setup (pearl-gtd-init-initialize)
  :files (("inbox.org" "* Simple task\n"))
  :mock (((symbol-function 'y-or-n-p) (lambda (&rest _) nil))
         ((symbol-function 'read-string)
          (lambda (prompt &rest _)
            (cond
             ((string-match "Rename" prompt) "")
             ((string-match "Add remarks" prompt) "")
             ((string-match "Assign" prompt) "reference")
             (t ""))))
         ((symbol-function 'completing-read)
          (lambda (prompt _collection &rest _)
            (cond
             ((string-match "Assign" prompt) "reference")
             (t "")))))
  :body (pearl-gtd-process-inbox)
  :asserts (should (pearl-gtd-test-file-contains-p
                    (expand-file-name "reference.org" pearl-gtd-init-base-directory)
                    "* Simple task"))
  :teardown nil)

(pearl-gtd-test-define-story pearl-gtd-test-clarify-user-cancels-midway
  "User cancels midway during clarification."
  :setup (pearl-gtd-init-initialize)
  :files (("inbox.org" "* Task to cancel\n"))
  :mock (((symbol-function 'y-or-n-p) (lambda (&rest _) (signal 'quit nil)))
         ((symbol-function 'read-string) (lambda (&rest _) ""))
         ((symbol-function 'completing-read) (lambda (&rest _) "")))
  :body (progn
         (condition-case err
             (pearl-gtd-process-inbox)
           (quit (setq pearl-gtd-test-caught-error err))))
:asserts (progn
           (should (pearl-gtd-test-file-contains-p
                    (expand-file-name "inbox.org" pearl-gtd-init-base-directory)
                    "* Task to cancel"))
           (should (eq (car pearl-gtd-test-caught-error) 'quit)))
  :teardown nil)

(pearl-gtd-test-define-story pearl-gtd-test-clarify-user-quits-during-rename
  "User quits during rename step."
  :setup (pearl-gtd-init-initialize)
  :files (("inbox.org" "* Task to rename\n"))
  :mock (((symbol-function 'y-or-n-p) (lambda (&rest _) nil))
         ((symbol-function 'read-string) (lambda (prompt &rest _)
                                           (if (string-match "Rename" prompt)
                                               (signal 'quit nil)
                                             ""))))
  :body (progn
         (condition-case err
             (pearl-gtd-process-inbox)
           (quit (setq pearl-gtd-test-caught-error err))))
:asserts (progn
           (should (pearl-gtd-test-file-contains-p
                    (expand-file-name "inbox.org" pearl-gtd-init-base-directory)
                    "* Task to rename"))
           (should (eq (car pearl-gtd-test-caught-error) 'quit)))
  :teardown nil)

(pearl-gtd-test-define-story pearl-gtd-test-clarify-user-quits-during-actionable-check
  "User quits during actionable check."
  :setup (pearl-gtd-init-initialize)
  :files (("inbox.org" "* Task to check\n"))
  :mock (((symbol-function 'y-or-n-p) (lambda (prompt &rest _)
                                         (if (string-match "actionable" prompt)
                                             (signal 'quit nil)
                                           nil)))
         ((symbol-function 'read-string) (lambda (&rest _) ""))
         ((symbol-function 'completing-read) (lambda (&rest _) "")))
  :body (progn
         (condition-case err
             (pearl-gtd-process-inbox)
           (quit (setq pearl-gtd-test-caught-error err))))
:asserts (progn
           (should (pearl-gtd-test-file-contains-p
                    (expand-file-name "inbox.org" pearl-gtd-init-base-directory)
                    "* Task to check"))
           (should (eq (car pearl-gtd-test-caught-error) 'quit)))
  :teardown nil)

(pearl-gtd-test-define-story pearl-gtd-test-clarify-user-processes-empty-inbox
  "User attempts to clarify empty inbox."
  :setup (pearl-gtd-init-initialize)
  :files (("inbox.org" ""))
  :mock nil
  :body (pearl-gtd-process-inbox)
  :asserts (progn
             (should (get-buffer "*Pearl-GTD: Inbox*"))
             (with-current-buffer "*Pearl-GTD: Inbox*"
               (should (search-forward "Inbox is empty" nil t))))
  :teardown (kill-buffer "*Pearl-GTD: Inbox*"))

(pearl-gtd-test-define-story pearl-gtd-test-clarify-user-processes-missing-inbox
  "User attempts to process when inbox file does not exist."
  :setup (pearl-gtd-init-initialize)
  :files nil
  :mock nil
  :body (progn
          (let ((inbox-file (expand-file-name "inbox.org" pearl-gtd-init-base-directory)))
            (when (file-exists-p inbox-file)
              (delete-file inbox-file)))
          (pearl-gtd-process-inbox))
  :asserts (progn
             (should (get-buffer "*Pearl-GTD: Inbox*"))
             (with-current-buffer "*Pearl-GTD: Inbox*"
               (should (search-forward "Inbox is empty" nil t))))
  :teardown (kill-buffer "*Pearl-GTD: Inbox*"))

(pearl-gtd-test-define-story pearl-gtd-test-clarify-user-processes-two-entries-sequentially
  "User clarifies two entries with different decisions."
  :setup (pearl-gtd-init-initialize)
  :files (("inbox.org" "* First task\n* Second task\n"))
  :mock (((symbol-function 'y-or-n-p)
          (lambda (prompt &rest _)
            (cond
             ((string-match "2 minutes" prompt) nil)
             ((string-match "actionable" prompt) t)
             (t nil))))
         ((symbol-function 'read-string)
          (let ((count 0))
            (lambda (prompt &rest _)
              (setq count (1+ count))
              (cond
               ((and (= count 1) (string-match "Rename" prompt)) "Renamed first")
               ((and (= count 2) (string-match "Rename" prompt)) "")
               ((string-match "Add remarks" prompt) "")
               ((string-match "Context" prompt) "@office")
               ((string-match "Schedule" prompt) "")
               ((string-match "Deadline" prompt) "")
               ((string-match "Delegate" prompt) "")
               ((string-match "Project" prompt) "")
               (t "")))))
         ((symbol-function 'completing-read)
          (lambda (prompt _collection &rest _)
            (cond
             ((string-match "Assign" prompt) "reference")
             (t "")))))
  :body (pearl-gtd-process-inbox)
  :asserts (progn
             (should (pearl-gtd-test-file-contains-p
                      (expand-file-name "actions.org" pearl-gtd-init-base-directory)
                      "* TODO Renamed first"))
             (should (pearl-gtd-test-file-contains-p
                      (expand-file-name "actions.org" pearl-gtd-init-base-directory)
                      "* TODO Second task"))
             (should (pearl-gtd-test-inbox-empty-p pearl-gtd-init-base-directory)))
  :teardown nil)

(pearl-gtd-test-define-story pearl-gtd-test-clarify-user-quits-during-context
  "Quitting (C-g) during context input should leave all tasks in inbox."
  :setup (pearl-gtd-init-initialize)
  :files (("inbox.org" "* First task\n:PROPERTIES:\n:ID: quit-1\n:END:\n* Second task\n:PROPERTIES:\n:ID: quit-2\n:END:\n"))
  :mock (((symbol-function 'y-or-n-p) (lambda (&rest _) t))
         ((symbol-function 'read-string)
          (lambda (prompt &rest _)
            (cond
             ((string-match "Rename" prompt) "")
             ((string-match "Remarks" prompt) "")
             ((string-match "Context" prompt) (signal 'quit nil))
             (t ""))))
         ((symbol-function 'completing-read) (lambda (&rest _) "")))
  :body (condition-case nil
            (pearl-gtd-process-inbox)
          (quit nil))
  :asserts (progn
             (should-not (pearl-gtd-test-file-contains-p-bool
                          (expand-file-name "actions.org" pearl-gtd-init-base-directory)
                          "First task"))
             (should-not (pearl-gtd-test-file-contains-p-bool
                          (expand-file-name "actions.org" pearl-gtd-init-base-directory)
                          "Second task")))
  :teardown nil)

(provide 'pearl-gtd-test-clarify)

;;; pearl-gtd-test-clarify.el ends here
