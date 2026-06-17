;;; test-pearl-gtd-workflows.el --- User stories: End-to-end workflows  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 OverbearingPearl

;; Author: OverbearingPearl <OverbearingPearl@outlook.com>
;; Version: 0.1.0
;; Package-Requires: ((emacs "27.1"))
;; Keywords: outlines, tools, convenience, productivity, gtd, org
;; URL: https://github.com/OverbearingPearl/pearl-gtd

;;; Commentary:

;; Complete user workflows spanning multiple phases.

;;; Code:

(require 'ert)
(require 'pearl-gtd)
(require 'test-pearl-gtd)

(test-pearl-gtd-define-story test-pearl-gtd-workflows-user-processes-full-gtd-pipeline
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
          (lambda (prompt collection &rest _)
            (cond
             ((string-match "Assign" prompt) "reference")
             (t "")))))
  :body (progn
          (pearl-gtd-capture)
          (pearl-gtd-process-inbox))
  :asserts (progn
             (should (test-pearl-gtd-inbox-empty-p pearl-gtd-init-base-directory))
             (should (test-pearl-gtd-file-contains-p
                      (expand-file-name "actions.org" pearl-gtd-init-base-directory)
                      "* TODO Buy gift for mom"))
             (should (test-pearl-gtd-file-contains-p
                      (expand-file-name "actions.org" pearl-gtd-init-base-directory)
                      "Check Amazon first"))
             (should (test-pearl-gtd-file-contains-p
                      (expand-file-name "actions.org" pearl-gtd-init-base-directory)
                      ":errands:"))
             ;; Verify ID is preserved after processing
             (should (test-pearl-gtd-file-contains-p
                      (expand-file-name "actions.org" pearl-gtd-init-base-directory)
                      ":ID:")))
  :teardown nil)

(test-pearl-gtd-define-story test-pearl-gtd-workflows-user-interrupts-processing
  "User interrupts processing midway."
  :setup (pearl-gtd-init-initialize)
  :files (("inbox.org" "* Task to interrupt\n"))
  :mock (((symbol-function 'read-string) (lambda (&rest _) (signal 'quit nil)))
         ((symbol-function 'y-or-n-p) (lambda (&rest _) t)))
  :body (progn
         (condition-case err
             (pearl-gtd-process-inbox)
           (quit (setq test-pearl-gtd-caught-error err))))
:asserts (progn
           (should (test-pearl-gtd-file-contains-p
                    (expand-file-name "inbox.org" pearl-gtd-init-base-directory)
                    "* Task to interrupt"))
           (should (eq (car test-pearl-gtd-caught-error) 'quit)))
  :teardown nil)

(test-pearl-gtd-define-story test-pearl-gtd-workflows-user-processes-mixed-destinations
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
        (lambda (prompt collection &rest _)
          (cond
           ((string-match "Assign" prompt) "reference")
           (t "")))))
  :body (pearl-gtd-process-inbox)
  :asserts (progn
             (should (test-pearl-gtd-file-contains-p
                      (expand-file-name "actions.org" pearl-gtd-init-base-directory)
                      "* TODO Action task"))
             (should (test-pearl-gtd-file-contains-p
                      (expand-file-name "reference.org" pearl-gtd-init-base-directory)
                      "* Reference task")))
  :teardown nil)

(test-pearl-gtd-define-story test-pearl-gtd-workflows-user-processes-empty-inbox
  "User processes empty inbox workflow."
  :setup (pearl-gtd-init-initialize)
  :files (("inbox.org" ""))
  :mock nil
  :body (pearl-gtd-process-inbox)
  :asserts (should (test-pearl-gtd-inbox-empty-p pearl-gtd-init-base-directory))
  :teardown (when (get-buffer "*Pearl-GTD: Inbox*")
              (with-current-buffer "*Pearl-GTD: Inbox*"
                (setq buffer-read-only nil))
              (kill-buffer "*Pearl-GTD: Inbox*")))

(test-pearl-gtd-define-story test-pearl-gtd-workflows-user-captures-and-processes-two-items
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
          (lambda (prompt collection &rest _)
            (cond
             ((string-match "Assign" prompt) "reference")
             (t "")))))
  :body (progn
          (pearl-gtd-capture)
          (pearl-gtd-capture)
          (pearl-gtd-process-inbox))
  :asserts (progn
             (should (test-pearl-gtd-inbox-empty-p pearl-gtd-init-base-directory))
             (should (test-pearl-gtd-file-contains-p
                      (expand-file-name "reference.org" pearl-gtd-init-base-directory)
                      "* First capture"))
             (should (test-pearl-gtd-file-contains-p
                      (expand-file-name "reference.org" pearl-gtd-init-base-directory)
                      "* Second capture")))
  :teardown nil)

(test-pearl-gtd-define-story test-pearl-gtd-workflows-id-preserved-after-processing
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
          (lambda (prompt collection &rest _)
            (cond
             ((string-match "Assign" prompt) "actions")
             (t "")))))
  :body (progn
          (pearl-gtd-capture)
          (pearl-gtd-process-inbox))
  :asserts (progn
             ;; Task moved to actions.org
             (should (test-pearl-gtd-file-contains-p
                      (expand-file-name "actions.org" pearl-gtd-init-base-directory)
                      "* TODO Test task"))
             ;; ID preserved in actions.org
             (should (test-pearl-gtd-file-contains-p
                      (expand-file-name "actions.org" pearl-gtd-init-base-directory)
                      ":ID:"))
             ;; Inbox is empty
             (should (test-pearl-gtd-inbox-empty-p pearl-gtd-init-base-directory)))
  :teardown nil)

(test-pearl-gtd-define-story test-pearl-gtd-workflows-duplicate-titles-different-files
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
             (should (test-pearl-gtd-file-contains-p
                      (expand-file-name "inbox.org" pearl-gtd-init-base-directory)
                      "* Buy milk"))
             ;; New entry has different ID
             (with-temp-buffer
               (insert-file-contents (expand-file-name "inbox.org" pearl-gtd-init-base-directory))
               (goto-char (point-min))
               (should (search-forward ":ID:" nil t))
               (let ((id-pos (point)))
                 (should-not (search-forward "existing-id-1" nil t)))))
  :teardown nil)

(test-pearl-gtd-define-story test-pearl-gtd-workflows-user-processes-duplicate-titles
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
          (lambda (prompt collection &rest _)
            (cond
             ((string-match "Assign" prompt) "actions")
             (t "")))))
  :body (progn
          (pearl-gtd-capture)
          (pearl-gtd-capture)
          (pearl-gtd-process-inbox))
  :asserts (progn
             (should (test-pearl-gtd-inbox-empty-p pearl-gtd-init-base-directory))
             ;; Should have two tasks in actions.org
             (with-temp-buffer
               (insert-file-contents (expand-file-name "actions.org" pearl-gtd-init-base-directory))
               (goto-char (point-min))
               (should (search-forward "* TODO Task" nil t))
               (should (search-forward "* TODO Task" nil t))))
  :teardown nil)

(provide 'test-pearl-gtd-workflows)

;;; test-pearl-gtd-workflows.el ends here
