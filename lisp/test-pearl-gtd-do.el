;;; test-pearl-gtd-do.el --- User stories: Do/Work phase  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 OverbearingPearl

;; Author: OverbearingPearl <OverbearingPearl@outlook.com>
;; Version: 0.1.0
;; Package-Requires: ((emacs "27.1"))
;; Keywords: outlines, tools, convenience, productivity, gtd, org
;; URL: https://github.com/OverbearingPearl/pearl-gtd

;;; Commentary:

;; User stories for executing tasks.

;;; Code:

(require 'ert)
(require 'pearl-gtd)
(require 'test-pearl-gtd)

(test-pearl-gtd-define-story test-pearl-gtd-do-user-views-next-actions-by-context
  "User views all next actions filtered by @office context."
  :setup (pearl-gtd-init-initialize)
  :files (("actions.org" "* TODO Task 1 :office:\n* TODO Task 2 :home:\n* TODO Task 3 :office:\n"))
  :mock (((symbol-function 'completing-read)
          (lambda (prompt collection &rest _)
            (cond
             ((string-match "Select context" prompt) "@office")
             (t "")))))
  :body (pearl-gtd-do-view-by-context)
  :asserts (progn
             (should (get-buffer "*Pearl-GTD: @office*"))
             (with-current-buffer "*Pearl-GTD: @office*"
               (should (search-forward "Task 1" nil t))
               (should (search-forward "Task 3" nil t))
               (should-not (search-forward "Task 2" nil t))
               ;; Verify Context column displays "@office" format
               (goto-char (point-min))
               (should (search-forward "@office" nil t))))
  :teardown (kill-buffer "*Pearl-GTD: @office*"))

(test-pearl-gtd-define-story test-pearl-gtd-do-user-marks-task-complete
  "User marks a task as completed."
  :setup (pearl-gtd-init-initialize)
  :files (("actions.org" "* TODO Complete this task\n"))
  :mock nil
  :body (progn
         (find-file (expand-file-name "actions.org" pearl-gtd-init-base-directory))
         (goto-char (point-min))
         (pearl-gtd-do-complete-task))
  :asserts (progn
             (should (test-pearl-gtd-file-contains-p
                      (expand-file-name "actions.org" pearl-gtd-init-base-directory)
                      "DONE"))
             (should (test-pearl-gtd-file-contains-p
                      (expand-file-name "actions.org" pearl-gtd-init-base-directory)
                      "CLOSED:")))
  :teardown nil)

(test-pearl-gtd-define-story test-pearl-gtd-do-user-views-all-next-actions
  "User views all next actions regardless of context."
  :setup (pearl-gtd-init-initialize)
  :files (("actions.org" "* TODO Task A :office:\n* TODO Task B :home:\n* TODO Task C :errands:\n"))
  :mock nil
  :body (pearl-gtd-do-view-all-actions)
  :asserts (progn
             (should (get-buffer "*Pearl-GTD: All Actions*"))
             (with-current-buffer "*Pearl-GTD: All Actions*"
               (should (search-forward "Task A" nil t))
               (should (search-forward "Task B" nil t))
               (should (search-forward "Task C" nil t))
               ;; Verify Context column displays tags with @ prefix
               (goto-char (point-min))
               (should (search-forward "@office" nil t))
               (should (search-forward "@home" nil t))
               (should (search-forward "@errands" nil t))))
  :teardown (kill-buffer "*Pearl-GTD: All Actions*"))

(test-pearl-gtd-define-story test-pearl-gtd-do-user-views-delegated-tasks
  "User views all delegated tasks."
  :setup (pearl-gtd-init-initialize)
  :files (("actions.org" "* TODO Task X :office:\n:PROPERTIES:\n:DELEGATED: John\n:END:\n"))
  :mock nil
  :body (pearl-gtd-do-view-delegated)
  :asserts (progn
             (should (get-buffer "*Pearl-GTD: Delegated*"))
             (with-current-buffer "*Pearl-GTD: Delegated*"
               (should (search-forward "Task X" nil t))
               (should (search-forward "John" nil t))
               ;; Verify Context column displays tags with @ prefix
               (goto-char (point-min))
               (should (search-forward "@office" nil t))))
  :teardown (kill-buffer "*Pearl-GTD: Delegated*"))

(test-pearl-gtd-define-story test-pearl-gtd-do-user-views-delegated-excludes-done
  "Delegated view excludes tasks without TODO state."
  :setup (pearl-gtd-init-initialize)
  :files (("actions.org" "* TODO Active task\n:PROPERTIES:\n:DELEGATED: John\n:END:\n* DONE Completed task\n:PROPERTIES:\n:DELEGATED: Jane\n:END:\n* No state task\n:PROPERTIES:\n:DELEGATED: Bob\n:END:\n"))
  :body (pearl-gtd-do-view-delegated)
  :asserts (progn
             (should (get-buffer "*Pearl-GTD: Delegated*"))
             (with-current-buffer "*Pearl-GTD: Delegated*"
               (should (search-forward "Active task" nil t))
               (should-not (search-forward "Completed task" nil t))
               (should-not (search-forward "No state task" nil t))))
  :teardown (kill-buffer "*Pearl-GTD: Delegated*"))

(test-pearl-gtd-define-story test-pearl-gtd-do-user-views-scheduled-for-today
  "User views actions scheduled for today."
  :setup (pearl-gtd-init-initialize)
  :files (("actions.org" (format "* TODO Task today\nSCHEDULED: <%s>\n" (format-time-string "%Y-%m-%d"))))
  :mock nil
  :body (pearl-gtd-do-view-today)
  :asserts (progn
             (should (get-buffer "*Pearl-GTD: Today*"))
             (with-current-buffer "*Pearl-GTD: Today*"
               (should (search-forward "Task today" nil t))))
  :teardown (kill-buffer "*Pearl-GTD: Today*"))

(test-pearl-gtd-define-story test-pearl-gtd-do-user-completes-task-in-view-updates-original
  "User completes task in view buffer, original file is updated."
  :setup (pearl-gtd-init-initialize)
  :files (("actions.org" "* TODO Task to complete :office:\n:PROPERTIES:\n:ID: test-id-2\n:END:\n"))
  :mock nil
  :body (progn
         (pearl-gtd-do-view-all-actions)
         (with-current-buffer "*Pearl-GTD: All Actions*"
           (goto-char (point-min))
           (search-forward "Task to complete")
           (beginning-of-line)
           (pearl-gtd-do-complete-task-at-point)))
  :asserts (progn
             (should (test-pearl-gtd-file-contains-p
                      (expand-file-name "actions.org" pearl-gtd-init-base-directory)
                      "* DONE Task to complete"))
             (should (test-pearl-gtd-file-contains-p
                      (expand-file-name "actions.org" pearl-gtd-init-base-directory)
                      ":ID:"))  ; Verify ID exists
             (should-not (test-pearl-gtd-file-contains-p
                          (expand-file-name "actions.org" pearl-gtd-init-base-directory)
                          "* TODO Task to complete")))
  :teardown (kill-buffer "*Pearl-GTD: All Actions*"))

(test-pearl-gtd-define-story test-pearl-gtd-do-user-views-project-in-actions-table
  "User views actions and sees associated project."
  :setup (pearl-gtd-init-initialize)
  :files (("actions.org" "* TODO Task with project\n:PROPERTIES:\n:PROJECT: Website Redesign\n:END:\n"))
  :mock nil
  :body (pearl-gtd-do-view-all-actions)
  :asserts (progn
             (should (get-buffer "*Pearl-GTD: All Actions*"))
             (with-current-buffer "*Pearl-GTD: All Actions*"
               (should (search-forward "Website Redesign" nil t))))
  :teardown (kill-buffer "*Pearl-GTD: All Actions*"))

(test-pearl-gtd-define-story test-pearl-gtd-do-user-views-created-timestamp-in-actions-table
  "User views actions and sees created timestamp."
  :setup (pearl-gtd-init-initialize)
  :files (("actions.org" "* TODO Task with timestamp\n:PROPERTIES:\n:CREATED: 2026-01-15 10:30:00\n:END:\n"))
  :mock nil
  :body (pearl-gtd-do-view-all-actions)
  :asserts (progn
             (should (get-buffer "*Pearl-GTD: All Actions*"))
             (with-current-buffer "*Pearl-GTD: All Actions*"
               (should (search-forward "2026-01-15" nil t))))
  :teardown (kill-buffer "*Pearl-GTD: All Actions*"))

(test-pearl-gtd-define-story test-pearl-gtd-do-user-views-project-and-created-in-delegated-view
  "User views delegated tasks with project and created columns."
  :setup (pearl-gtd-init-initialize)
  :files (("actions.org" "* TODO Delegated task\n:PROPERTIES:\n:DELEGATED: Bob\n:PROJECT: Marketing Campaign\n:CREATED: 2026-01-10\n:END:\n"))
  :mock nil
  :body (pearl-gtd-do-view-delegated)
  :asserts (progn
             (should (get-buffer "*Pearl-GTD: Delegated*"))
             (with-current-buffer "*Pearl-GTD: Delegated*"
               (should (search-forward "Marketing Campaign" nil t))
               (should (search-forward "2026-01-10" nil t))))
  :teardown (kill-buffer "*Pearl-GTD: Delegated*"))

(test-pearl-gtd-define-story test-pearl-gtd-do-user-views-project-and-created-in-today-view
  "User views today's tasks with project and created columns."
  :setup (pearl-gtd-init-initialize)
  :files (("actions.org" (format "* TODO Today task\nSCHEDULED: <%s>\n:PROPERTIES:\n:PROJECT: Current Sprint\n:CREATED: 2026-01-20\n:END:\n"
                                  (format-time-string "%Y-%m-%d"))))
  :mock nil
  :body (pearl-gtd-do-view-today)
  :asserts (progn
             (should (get-buffer "*Pearl-GTD: Today*"))
             (with-current-buffer "*Pearl-GTD: Today*"
               (should (search-forward "Current Sprint" nil t))
               (should (search-forward "2026-01-20" nil t))))
  :teardown (kill-buffer "*Pearl-GTD: Today*"))

(provide 'test-pearl-gtd-do)

;;; test-pearl-gtd-do.el ends here
