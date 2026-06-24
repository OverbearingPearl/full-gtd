;;; test-pearl-gtd-organize.el --- User stories: Organize phase  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 OverbearingPearl

;; Author: OverbearingPearl <OverbearingPearl@outlook.com>
;; Version: 0.1.0
;; Package-Requires: ((emacs "27.1"))
;; Keywords: outlines, tools, convenience, productivity, gtd, org
;; URL: https://github.com/OverbearingPearl/pearl-gtd

;;; Commentary:

;; User stories for organizing items into appropriate categories.

;;; Code:

(require 'ert)
(require 'pearl-gtd)
(require 'test-pearl-gtd)

(test-pearl-gtd-define-story test-pearl-gtd-organize-user-trashes-junk-item
  "User decides item is trash, it disappears completely."
  :setup (pearl-gtd-init-initialize)
  :files (("inbox.org" "* Junk item\n"))
  :mock (((symbol-function 'y-or-n-p) (lambda (&rest _) nil))
         ((symbol-function 'read-string)
          (lambda (prompt &rest _)
            (cond
             ((string-match "Rename" prompt) "")
             ((string-match "Add remarks" prompt) "")
             (t ""))))
         ((symbol-function 'completing-read) (lambda (&rest _) "trash")))
  :body (pearl-gtd-process-inbox)
  :asserts (should (test-pearl-gtd-inbox-empty-p pearl-gtd-init-base-directory))
  :teardown nil)

(test-pearl-gtd-define-story test-pearl-gtd-organize-user-files-item-to-reference
  "User moves 'Article about Emacs' to reference.org."
  :setup (pearl-gtd-init-initialize)
  :files (("inbox.org" "* Article about Emacs\n"))
  :mock (((symbol-function 'y-or-n-p) (lambda (&rest _) nil))
         ((symbol-function 'read-string)
          (lambda (prompt &rest _)
            (cond
             ((string-match "Rename" prompt) "")
             ((string-match "Add remarks" prompt) "")
             (t ""))))
         ((symbol-function 'completing-read) (lambda (&rest _) "reference")))
  :body (pearl-gtd-process-inbox)
  :asserts (test-pearl-gtd-file-contains-p
            (expand-file-name "reference.org" pearl-gtd-init-base-directory)
            "* Article about Emacs")
  :teardown nil)

(test-pearl-gtd-define-story test-pearl-gtd-organize-user-sets-context-at-office
  "User tags task with @office context."
  :setup (pearl-gtd-init-initialize)
  :files (("inbox.org" "* Task for office\n"))
  :mock (((symbol-function 'y-or-n-p)
          (lambda (prompt &rest _)
            (cond
             ((string-match "2 minutes" prompt) nil)
             ((string-match "actionable" prompt) t)
             (t nil))))
         ((symbol-function 'read-string)
          (lambda (prompt &rest _)
            (cond
             ((string-match "Rename" prompt) "")
             ((string-match "Add remarks" prompt) "")
             ((string-match "Context" prompt) "@office")
             ((string-match "Schedule" prompt) "")
             ((string-match "Delegate" prompt) "")
             ((string-match "Project" prompt) "")
             (t ""))))
         ((symbol-function 'completing-read) (lambda (&rest _) "")))
  :body (pearl-gtd-process-inbox)
  :asserts (progn
             (should (test-pearl-gtd-file-contains-p
                      (expand-file-name "actions.org" pearl-gtd-init-base-directory)
                      "* TODO Task for office"))
             (should (test-pearl-gtd-file-contains-p
                      (expand-file-name "actions.org" pearl-gtd-init-base-directory)
                      ":office:")))
  :teardown nil)

(test-pearl-gtd-define-story test-pearl-gtd-organize-user-renames-then-sets-context-and-schedule
  "User renames task and sets @office context with schedule."
  :setup (pearl-gtd-init-initialize)
  :files (("inbox.org" "* Old vague name\n"))
  :mock (((symbol-function 'y-or-n-p)
          (lambda (prompt &rest _)
            (cond
             ((string-match "2 minutes" prompt) nil)
             ((string-match "actionable" prompt) t)
             (t nil))))
         ((symbol-function 'read-string)
          (lambda (prompt &rest _)
            (cond
             ((string-match "Rename" prompt) "Prepare quarterly report")
             ((string-match "Add remarks" prompt) "")
             ((string-match "Context" prompt) "@office")
             ((string-match "Schedule" prompt) "2026-04-15")
             ((string-match "Delegate" prompt) "")
             ((string-match "Project" prompt) "")
             (t ""))))
         ((symbol-function 'completing-read) (lambda (&rest _) "")))
  :body (pearl-gtd-process-inbox)
  :asserts (progn
             (should (test-pearl-gtd-file-contains-p
                      (expand-file-name "actions.org" pearl-gtd-init-base-directory)
                      "* TODO Prepare quarterly report"))
             (should (test-pearl-gtd-file-lacks-p
                      (expand-file-name "actions.org" pearl-gtd-init-base-directory)
                      "* Old vague name"))
             (should (test-pearl-gtd-file-contains-p
                      (expand-file-name "actions.org" pearl-gtd-init-base-directory)
                      ":office:"))
             (should (test-pearl-gtd-file-contains-p
                      (expand-file-name "actions.org" pearl-gtd-init-base-directory)
                      "SCHEDULED"))
             (should (test-pearl-gtd-inbox-empty-p pearl-gtd-init-base-directory)))
  :teardown nil)

(test-pearl-gtd-define-story test-pearl-gtd-organize-user-processes-empty-inbox
  "User processes an empty inbox."
  :setup (pearl-gtd-init-initialize)
  :files (("inbox.org" ""))
  :mock nil
  :body (pearl-gtd-process-inbox)
  :asserts (should (test-pearl-gtd-inbox-empty-p pearl-gtd-init-base-directory))
  :teardown nil)

(test-pearl-gtd-define-story test-pearl-gtd-organize-user-handles-duplicate-titles
  "User processes entries with duplicate titles."
  :setup (pearl-gtd-init-initialize)
  :files (("inbox.org" "* Duplicate task\n* Duplicate task\n"))
  :mock (((symbol-function 'y-or-n-p) (lambda (&rest _) nil))
         ((symbol-function 'read-string)
          (lambda (prompt &rest _)
            (cond
             ((string-match "Rename" prompt) "Renamed task")
             (t ""))))
         ((symbol-function 'completing-read) (lambda (&rest _) "reference")))
  :body (pearl-gtd-process-inbox)
  :asserts (should (test-pearl-gtd-file-contains-p
                    (expand-file-name "reference.org" pearl-gtd-init-base-directory)
                    "* Renamed task"))
  :teardown nil)

(test-pearl-gtd-define-story test-pearl-gtd-organize-user-processes-two-items-differently
  "User processes two items: one to trash, one to reference."
  :setup (pearl-gtd-init-initialize)
  :files (("inbox.org" "* Junk item\n* Keep item\n"))
  :mock (((symbol-function 'y-or-n-p) (lambda (&rest _) nil))
         ((symbol-function 'read-string)
          (let ((count 0))
            (lambda (prompt &rest _)
              (setq count (1+ count))
              (cond
               ((and (= count 1) (string-match "Rename" prompt)) "")
               ((and (= count 3) (string-match "Rename" prompt)) "Important article")
               ((string-match "Add remarks" prompt) "")
               (t "")))))
         ((symbol-function 'completing-read)
          (let ((count 0))
            (lambda (&rest _)
              (setq count (1+ count))
              (if (= count 1) "trash" "reference")))))
  :body (pearl-gtd-process-inbox)
  :asserts (progn
             (should-not (test-pearl-gtd-file-contains-p
                          (expand-file-name "inbox.org" pearl-gtd-init-base-directory)
                          "* Junk item"))
             (should (test-pearl-gtd-file-contains-p
                      (expand-file-name "reference.org" pearl-gtd-init-base-directory)
                      "* Important article"))
             (should (test-pearl-gtd-inbox-empty-p pearl-gtd-init-base-directory)))
  :teardown nil)

(test-pearl-gtd-define-story test-pearl-gtd-organize-user-executes-two-tasks-immediately
  "User executes two 2-minute tasks immediately."
  :setup (pearl-gtd-init-initialize)
  :files (("inbox.org" "* Quick call\n* Quick email\n"))
  :mock (((symbol-function 'y-or-n-p) (lambda (&rest _) t))
         ((symbol-function 'read-string) (lambda (&rest _) ""))
         ((symbol-function 'completing-read) (lambda (&rest _) "")))
  :body (pearl-gtd-process-inbox)
  :asserts (progn
             (should (test-pearl-gtd-inbox-empty-p pearl-gtd-init-base-directory))
             ;; Both should be marked as executed (moved with nil target)
             )
  :teardown nil)

(test-pearl-gtd-define-story test-pearl-gtd-organize-user-quits-during-assign
  "User quits when prompted for assignment target."
  :setup (pearl-gtd-init-initialize)
  :files (("inbox.org" "* Task to assign\n"))
  :mock (((symbol-function 'y-or-n-p) (lambda (&rest _) nil))
         ((symbol-function 'read-string) (lambda (&rest _) ""))
         ((symbol-function 'completing-read) (lambda (&rest _) (signal 'quit nil))))
  :body (progn
         (condition-case err
             (pearl-gtd-process-inbox)
           (quit (setq test-pearl-gtd-caught-error err))))
  :asserts (progn
           (should (test-pearl-gtd-file-contains-p
                    (expand-file-name "inbox.org" pearl-gtd-init-base-directory)
                    "* Task to assign"))
           (should (eq (car test-pearl-gtd-caught-error) 'quit)))
  :teardown nil)

(test-pearl-gtd-define-story test-pearl-gtd-organize-user-links-task-to-multiple-projects
  "User links single task to multiple projects during processing."
  :setup (pearl-gtd-init-initialize)
  :files (("inbox.org" "* Shared task\n:PROPERTIES:\n:ID: shared-1\n:END:\n"))
  :mock (((symbol-function 'y-or-n-p)
          (lambda (prompt &rest _)
            (cond
             ((string-match "2 minutes" prompt) nil)
             ((string-match "actionable" prompt) t)
             (t nil))))
         ((symbol-function 'read-string)
          (lambda (prompt &rest _)
            (cond
             ((string-match "Rename" prompt) "")
             ((string-match "Add remarks" prompt) "")
             ((string-match "Context" prompt) "")
             ((string-match "Schedule" prompt) "")
             ((string-match "Delegate" prompt) "")
             ((string-match "Project" prompt) "Alpha,Beta")
             (t ""))))
         ((symbol-function 'completing-read) (lambda (&rest _) "")))
  :body (pearl-gtd-process-inbox)
  :asserts (progn
             (should (test-pearl-gtd-file-contains-p
                      (expand-file-name "actions.org" pearl-gtd-init-base-directory)
                      "* TODO Shared task"))
             (should (test-pearl-gtd-file-contains-p
                      (expand-file-name "actions.org" pearl-gtd-init-base-directory)
                      ":PROJECT:\\s-*Alpha"))
             (should (test-pearl-gtd-file-contains-p
                      (expand-file-name "actions.org" pearl-gtd-init-base-directory)
                      "Beta"))
             (should (test-pearl-gtd-file-contains-p
                      (expand-file-name "actions.org" pearl-gtd-init-base-directory)
                      ":ID:"))
             (should (test-pearl-gtd-inbox-empty-p pearl-gtd-init-base-directory)))
  :teardown nil)

(provide 'test-pearl-gtd-organize)

;;; test-pearl-gtd-organize.el ends here
