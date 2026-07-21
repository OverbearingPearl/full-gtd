;;; pearl-gtd-test-workflows.el --- User stories: End-to-end workflows  -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: MIT
;; URL: https://github.com/OverbearingPearl/pearl-gtd

;;; Commentary:

;; Complete user workflows spanning multiple phases.

;;; Code:

(require 'ert)
(require 'pearl-gtd)
(require 'pearl-gtd-test)

(pearl-gtd-test-define-story pearl-gtd-test-workflows-user-processes-full-gtd-pipeline
  "User captures, clarifies, organizes, and completes processing."
  :setup (pearl-gtd-init-initialize)
  :files nil
  :mock (((symbol-function 'read-string)
          (lambda (prompt &rest _)
            (cond
             ((string-match "Enter item" prompt) "Buy birthday gift")
             ((string-match "Rename" prompt) "Buy gift for mom")
             ((string-match "Add remarks" prompt) "Check Amazon first")
             ((string-match "Context" prompt) "@errands")
             ((string-match "Schedule" prompt) "")
             ((string-match "Delegate" prompt) "")
             ((string-match "Project" prompt) "")
             (t ""))))
         ((symbol-function 'y-or-n-p)
          (lambda (prompt &rest _)
            (cond
             ((string-match "2 minutes" prompt) nil)
             ((string-match "actionable" prompt) t)
             (t nil))))
         ((symbol-function 'completing-read)
          (lambda (prompt _collection &rest _)
            (cond
             ((string-match "Assign" prompt) "reference")
             (t "")))))
  :body (progn
          (pearl-gtd-capture)
          (pearl-gtd-process-inbox))
  :asserts (progn
             (should (pearl-gtd-test-inbox-empty-p pearl-gtd-init-base-directory))
             (should (pearl-gtd-test-file-contains-p
                      (expand-file-name "actions.org" pearl-gtd-init-base-directory)
                      "* TODO Buy gift for mom"))
             (should (pearl-gtd-test-file-contains-p
                      (expand-file-name "actions.org" pearl-gtd-init-base-directory)
                      "Check Amazon first"))
             (should (pearl-gtd-test-file-contains-p
                      (expand-file-name "actions.org" pearl-gtd-init-base-directory)
                      ":errands:"))
             ;; Verify ID is preserved after processing
             (should (pearl-gtd-test-file-contains-p
                      (expand-file-name "actions.org" pearl-gtd-init-base-directory)
                      ":ID:")))
  :teardown nil)

(pearl-gtd-test-define-story pearl-gtd-test-workflows-user-interrupts-processing
  "User interrupts processing midway."
  :setup (pearl-gtd-init-initialize)
  :files (("inbox.org" "* Task to interrupt\n"))
  :mock (((symbol-function 'read-string) (lambda (&rest _) (signal 'quit nil)))
         ((symbol-function 'y-or-n-p) (lambda (&rest _) t)))
  :body (progn
         (condition-case err
             (pearl-gtd-process-inbox)
           (quit (setq pearl-gtd-test-caught-error err))))
:asserts (progn
           (should (pearl-gtd-test-file-contains-p
                    (expand-file-name "inbox.org" pearl-gtd-init-base-directory)
                    "* Task to interrupt"))
           (should (eq (car pearl-gtd-test-caught-error) 'quit)))
  :teardown nil)

(pearl-gtd-test-define-story pearl-gtd-test-workflows-user-processes-mixed-destinations
  "User processes entries with mixed destinations."
  :setup (pearl-gtd-init-initialize)
  :files (("inbox.org" "* Action task\n* Reference task\n"))
  :mock (((symbol-function 'y-or-n-p)
        (lambda (prompt &rest _)
          (cond
           ((string-match "Action task.*actionable" prompt) t)
           ((string-match "Action task.*2 minutes" prompt) nil)
           ((string-match "Reference task.*actionable" prompt) nil)
           (t t))))
       ((symbol-function 'read-string)
        (lambda (prompt &rest _)
          (cond
           ((string-match "Rename" prompt) "")
           ((string-match "Add remarks" prompt) "")
           ((string-match "Context.*Action task" prompt) "@office")
           ((string-match "Assign.*Reference" prompt) "reference")
           (t ""))))
       ((symbol-function 'completing-read)
        (lambda (prompt _collection &rest _)
          (cond
           ((string-match "Assign" prompt) "reference")
           (t "")))))
  :body (pearl-gtd-process-inbox)
  :asserts (progn
             (should (pearl-gtd-test-file-contains-p
                      (expand-file-name "actions.org" pearl-gtd-init-base-directory)
                      "* TODO Action task"))
             (should (pearl-gtd-test-file-contains-p
                      (expand-file-name "reference.org" pearl-gtd-init-base-directory)
                      "* Reference task")))
  :teardown nil)


(pearl-gtd-test-define-story pearl-gtd-test-workflows-user-captures-and-processes-two-items
  "User captures two items then processes both."
  :setup (pearl-gtd-init-initialize)
  :files nil
  :mock (((symbol-function 'read-string)
          (let ((count 0))
            (lambda (prompt &rest _)
              (setq count (1+ count))
              (cond
               ((and (= count 1) (string-match "Enter item" prompt)) "First capture")
               ((and (= count 2) (string-match "Enter item" prompt)) "Second capture")
               ((string-match "Rename" prompt) "")
               ((string-match "Add remarks" prompt) "")
               ((string-match "Assign" prompt) "reference")
               (t "")))))
         ((symbol-function 'y-or-n-p) (lambda (&rest _) nil))
         ((symbol-function 'completing-read)
          (lambda (prompt _collection &rest _)
            (cond
             ((string-match "Assign" prompt) "reference")
             (t "")))))
  :body (progn
          (pearl-gtd-capture)
          (pearl-gtd-capture)
          (pearl-gtd-process-inbox))
  :asserts (progn
             (should (pearl-gtd-test-inbox-empty-p pearl-gtd-init-base-directory))
             (should (pearl-gtd-test-file-contains-p
                      (expand-file-name "reference.org" pearl-gtd-init-base-directory)
                      "* First capture"))
             (should (pearl-gtd-test-file-contains-p
                      (expand-file-name "reference.org" pearl-gtd-init-base-directory)
                      "* Second capture")))
  :teardown nil)

(pearl-gtd-test-define-story pearl-gtd-test-workflows-user-sees-id-preserved-after-processing
  "ID is preserved when task is moved from inbox to actions."
  :setup (pearl-gtd-init-initialize)
  :files nil
  :mock (((symbol-function 'read-string)
          (lambda (prompt &rest _)
            (cond
             ((string-match "Enter item" prompt) "Test task")
             ((string-match "Rename" prompt) "")
             ((string-match "Add remarks" prompt) "")
             ((string-match "Context" prompt) "@office")
             ((string-match "Schedule" prompt) "")
             ((string-match "Delegate" prompt) "")
             ((string-match "Project" prompt) "")
             (t ""))))
         ((symbol-function 'y-or-n-p)
          (lambda (prompt &rest _)
            (cond
             ((string-match "2 minutes" prompt) nil)
             ((string-match "actionable" prompt) t)
             (t nil))))
         ((symbol-function 'completing-read)
          (lambda (prompt _collection &rest _)
            (cond
             ((string-match "Assign" prompt) "actions")
             (t "")))))
  :body (progn
          (pearl-gtd-capture)
          (pearl-gtd-process-inbox))
  :asserts (progn
             ;; Task moved to actions.org
             (should (pearl-gtd-test-file-contains-p
                      (expand-file-name "actions.org" pearl-gtd-init-base-directory)
                      "* TODO Test task"))
             ;; ID preserved in actions.org
             (should (pearl-gtd-test-file-contains-p
                      (expand-file-name "actions.org" pearl-gtd-init-base-directory)
                      ":ID:"))
             ;; Inbox is empty
             (should (pearl-gtd-test-inbox-empty-p pearl-gtd-init-base-directory)))
  :teardown nil)

(pearl-gtd-test-define-story pearl-gtd-test-workflows-user-sees-duplicate-titles-get-different-ids
  "Same title in different files gets different IDs."
  :setup (pearl-gtd-init-initialize)
  :files (("actions.org" "* TODO Buy milk\n:PROPERTIES:\n:ID: existing-id-1\n:END:\n"))
  :mock (((symbol-function 'read-string)
          (lambda (prompt &rest _)
            (cond
             ((string-match "Enter item" prompt) "Buy milk")
             (t "")))))
  :body (pearl-gtd-capture)
  :asserts (progn
             ;; New entry in inbox
             (should (pearl-gtd-test-file-contains-p
                      (expand-file-name "inbox.org" pearl-gtd-init-base-directory)
                      "* Buy milk"))
             ;; New entry has different ID
             (with-temp-buffer
               (insert-file-contents (expand-file-name "inbox.org" pearl-gtd-init-base-directory))
               (goto-char (point-min))
               (should (search-forward ":ID:" nil t))
               (let ((_id-pos (point)))
                 (should-not (search-forward "existing-id-1" nil t)))))
  :teardown nil)

(pearl-gtd-test-define-story pearl-gtd-test-workflows-user-processes-duplicate-titles
  "User captures two tasks with same title, both processed correctly."
  :setup (pearl-gtd-init-initialize)
  :files nil
  :mock (((symbol-function 'read-string)
          (let ((count 0))
            (lambda (prompt &rest _)
              (setq count (1+ count))
              (cond
               ((and (= count 1) (string-match "Enter item" prompt)) "Task")
               ((and (= count 2) (string-match "Enter item" prompt)) "Task")
               ((string-match "Rename" prompt) "")
               ((string-match "Add remarks" prompt) "")
               ((string-match "Context" prompt) "@office")
               ((string-match "Schedule" prompt) "")
               ((string-match "Delegate" prompt) "")
               ((string-match "Project" prompt) "")
               (t "")))))
         ((symbol-function 'y-or-n-p)
          (lambda (prompt &rest _)
            (cond
             ((string-match "2 minutes" prompt) nil)
             ((string-match "actionable" prompt) t)
             (t nil))))
         ((symbol-function 'completing-read)
          (lambda (prompt _collection &rest _)
            (cond
             ((string-match "Assign" prompt) "actions")
             (t "")))))
  :body (progn
          (pearl-gtd-capture)
          (pearl-gtd-capture)
          (pearl-gtd-process-inbox))
  :asserts (progn
             (should (pearl-gtd-test-inbox-empty-p pearl-gtd-init-base-directory))
             ;; Should have two tasks in actions.org
             (with-temp-buffer
               (insert-file-contents (expand-file-name "actions.org" pearl-gtd-init-base-directory))
               (goto-char (point-min))
               (should (search-forward "* TODO Task" nil t))
               (should (search-forward "* TODO Task" nil t))))
  :teardown nil)

(pearl-gtd-test-define-story pearl-gtd-test-workflows-duplicate-ids-in-file
  "Malformed file with duplicate IDs should still allow jumping to first match."
  :setup (pearl-gtd-init-initialize)
  :files (("actions.org" "* TODO Task A\n:PROPERTIES:\n:ID: dup-id\n:END:\n* TODO Task B\n:PROPERTIES:\n:ID: dup-id\n:END:\n"))
  :mock nil
  :body (progn
          (pearl-gtd-do-view-all-actions)
          (with-current-buffer "*Pearl-GTD: All Actions*"
            (goto-char (point-min))
            (search-forward "Task B")
            (beginning-of-line)
            (pearl-gtd-do--goto-task)))
  :asserts (progn
             (let ((buf (get-file-buffer (expand-file-name "actions.org" pearl-gtd-init-base-directory))))
               (should buf)
               (with-current-buffer buf
                 (should (looking-at-p "\\*+ TODO Task")))))
  :teardown (progn
              (pearl-gtd-test-cleanup-buffers '("*Pearl-GTD: All Actions*"))
              (let ((buf (get-file-buffer (expand-file-name "actions.org" pearl-gtd-init-base-directory))))
                (when buf (kill-buffer buf)))))

(pearl-gtd-test-define-story pearl-gtd-test-workflows-large-number-entries
  "System should handle 100+ entries without significant slowdown."
  :setup (pearl-gtd-init-initialize)
  :files (("inbox.org" (concat "* Task 1\n:PROPERTIES:\n:ID: perf-1\n:END:\n"
                               (mapconcat (lambda (i)
                                           (format "* Task %d\n:PROPERTIES:\n:ID: perf-%d\n:END:\n" i i))
                                         (number-sequence 2 100) ""))))
  :mock (((symbol-function 'y-or-n-p) (lambda (&rest _) nil))
         ((symbol-function 'read-string) (lambda (&rest _) ""))
         ((symbol-function 'completing-read) (lambda (&rest _) "trash")))
  :body (let ((start (float-time)))
          (pearl-gtd-process-inbox)
          (should (< (- (float-time) start) 10.0)))
  :asserts (should (pearl-gtd-test-inbox-empty-p pearl-gtd-init-base-directory))
  :teardown nil)

(provide 'pearl-gtd-test-workflows)

;;; pearl-gtd-test-workflows.el ends here
