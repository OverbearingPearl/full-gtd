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
  :files (("actions.org" "* Task 1 :office:\n* Task 2 :home:\n* Task 3 :office:\n"))
  :mock (((symbol-function 'completing-read)
          (lambda (prompt collection &rest _)
            (cond
             ((string-match "Context" prompt) "@office")
             (t "")))))
  :body (pearl-gtd-do-view-by-context)
  :asserts (progn
             (should (get-buffer "*Pearl-GTD: @office*"))
             (with-current-buffer "*Pearl-GTD: @office*"
               (should (search-forward "Task 1" nil t))
               (should (search-forward "Task 3" nil t))
               (should-not (search-forward "Task 2" nil t))))
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
                      "CLOSED:"))
             (should (test-pearl-gtd-file-contains-p
                      (expand-file-name "actions.org" pearl-gtd-init-base-directory)
                      "DONE")))
  :teardown nil)

(test-pearl-gtd-define-story test-pearl-gtd-do-user-views-all-next-actions
  "User views all next actions regardless of context."
  :setup (pearl-gtd-init-initialize)
  :files (("actions.org" "* Task A :office:\n* Task B :home:\n* Task C :errands:\n"))
  :mock nil
  :body (pearl-gtd-do-view-all-actions)
  :asserts (progn
             (should (get-buffer "*Pearl-GTD: All Actions*"))
             (with-current-buffer "*Pearl-GTD: All Actions*"
               (should (search-forward "Task A" nil t))
               (should (search-forward "Task B" nil t))
               (should (search-forward "Task C" nil t))))
  :teardown (kill-buffer "*Pearl-GTD: All Actions*"))

(test-pearl-gtd-define-story test-pearl-gtd-do-user-views-delegated-tasks
  "User views all delegated tasks."
  :setup (pearl-gtd-init-initialize)
  :files (("actions.org" "* Task X :office:\n:PROPERTIES:\n:DELEGATED: John\n:END:\n"))
  :mock nil
  :body (pearl-gtd-do-view-delegated)
  :asserts (progn
             (should (get-buffer "*Pearl-GTD: Delegated*"))
             (with-current-buffer "*Pearl-GTD: Delegated*"
               (should (search-forward "Task X" nil t))
               (should (search-forward "John" nil t))))
  :teardown (kill-buffer "*Pearl-GTD: Delegated*"))

(test-pearl-gtd-define-story test-pearl-gtd-do-user-filters-by-multiple-contexts
  "User filters actions by multiple contexts."
  :setup (pearl-gtd-init-initialize)
  :files (("actions.org" "* Task 1 :office:\n* Task 2 :home:\n* Task 3 :office:home:\n"))
  :mock (((symbol-function 'completing-read)
          (lambda (prompt collection &rest _)
            (cond
             ((string-match "Select contexts" prompt) "office,home")
             (t "")))))
  :body (pearl-gtd-do-view-by-contexts)
  :asserts (progn
             (should (get-buffer "*Pearl-GTD: Multiple*"))
             (with-current-buffer "*Pearl-GTD: Multiple*"
               (should (search-forward "Task 1" nil t))
               (should (search-forward "Task 2" nil t))
               (should (search-forward "Task 3" nil t))))
  :teardown (kill-buffer "*Pearl-GTD: Multiple*"))

(test-pearl-gtd-define-story test-pearl-gtd-do-user-views-scheduled-for-today
  "User views actions scheduled for today."
  :setup (pearl-gtd-init-initialize)
  :files (("actions.org" (format "* Task today\nSCHEDULED: <%s>\n" (format-time-string "%Y-%m-%d"))))
  :mock nil
  :body (pearl-gtd-do-view-today)
  :asserts (progn
             (should (get-buffer "*Pearl-GTD: Today*"))
             (with-current-buffer "*Pearl-GTD: Today*"
               (should (search-forward "Task today" nil t))))
  :teardown (kill-buffer "*Pearl-GTD: Today*"))

(test-pearl-gtd-define-story test-pearl-gtd-do-user-delegates-task-with-deadline
  "User delegates task to someone with deadline tracking."
  :setup (pearl-gtd-init-initialize)
  :files (("actions.org" "* TODO Task to delegate\n"))
  :mock (((symbol-function 'read-string)
          (lambda (prompt &rest _)
            (cond
             ((string-match "Delegate to" prompt) "Alice")
             ((string-match "Deadline" prompt) "2026-05-15")
             ((string-match "Reminder" prompt) "3")
             (t "")))))
  :body (progn
         (find-file (expand-file-name "actions.org" pearl-gtd-init-base-directory))
         (goto-char (point-min))
         (pearl-gtd-do-delegate-task))
  :asserts (progn
             (should (test-pearl-gtd-file-contains-p
                      (expand-file-name "actions.org" pearl-gtd-init-base-directory)
                      ":DELEGATED:Alice:"))
             (should (test-pearl-gtd-file-contains-p
                      (expand-file-name "actions.org" pearl-gtd-init-base-directory)
                      "DEADLINE:"))
             (should (test-pearl-gtd-file-contains-p
                      (expand-file-name "actions.org" pearl-gtd-init-base-directory)
                      ":REMINDER:3:")))
  :teardown nil)

(test-pearl-gtd-define-story test-pearl-gtd-do-user-tracks-delegation-status
  "User checks status of delegated tasks and sees waiting time."
  :setup (pearl-gtd-init-initialize)
  :files (("actions.org" "* TODO Delegated task\n:PROPERTIES:\n:DELEGATED:Bob\n:DELEGATED_DATE:2026-04-01\n:END:\n"))
  :mock nil
  :body (pearl-gtd-do-view-delegated-with-status)
  :asserts (progn
             (should (get-buffer "*Pearl-GTD: Delegated Status*"))
             (with-current-buffer "*Pearl-GTD: Delegated Status*"
               (should (search-forward "Bob" nil t))
               (should (search-forward "29 days" nil t))))
  :teardown (kill-buffer "*Pearl-GTD: Delegated Status*"))

(test-pearl-gtd-define-story test-pearl-gtd-do-user-sends-reminder-for-overdue-delegation
  "User sends reminder for overdue delegated task."
  :setup (pearl-gtd-init-initialize)
  :files (("actions.org" "* TODO Overdue delegated task\n:PROPERTIES:\n:DELEGATED:Charlie\n:DEADLINE:2026-04-01\n:END:\n"))
  :mock (((symbol-function 'y-or-n-p) (lambda (&rest _) t)))
  :body (progn
         (find-file (expand-file-name "actions.org" pearl-gtd-init-base-directory))
         (goto-char (point-min))
         (pearl-gtd-do-send-delegation-reminder))
  :asserts (progn
             (should (test-pearl-gtd-file-contains-p
                      (expand-file-name "actions.org" pearl-gtd-init-base-directory)
                      ":REMINDER_SENT:")))
  :teardown nil)

(test-pearl-gtd-define-story test-pearl-gtd-do-user-filters-by-context-combinations
  "User filters actions requiring both @office and @computer contexts."
  :setup (pearl-gtd-init-initialize)
  :files (("actions.org" "* Task A :office:\n* Task B :computer:\n* Task C :office:computer:\n* Task D :home:\n"))
  :mock (((symbol-function 'completing-read)
          (lambda (prompt collection &rest _)
            (cond
             ((string-match "Select first context" prompt) "@office")
             ((string-match "Select second context" prompt) "@computer")
             ((string-match "Match mode" prompt) "intersection")
             (t "")))))
  :body (pearl-gtd-do-view-by-context-intersection)
  :asserts (progn
             (should (get-buffer "*Pearl-GTD: @office ∩ @computer*"))
             (with-current-buffer "*Pearl-GTD: @office ∩ @computer*"
               (should (search-forward "Task C" nil t))
               (should-not (search-forward "Task A" nil t))
               (should-not (search-forward "Task B" nil t))
               (should-not (search-forward "Task D" nil t))))
  :teardown (kill-buffer "*Pearl-GTD: @office ∩ @computer*"))

(test-pearl-gtd-define-story test-pearl-gtd-do-user-excludes-context-from-view
  "User views actions excluding specific context."
  :setup (pearl-gtd-init-initialize)
  :files (("actions.org" "* Task at office :office:\n* Task at home :home:\n* Task anywhere :errands:\n"))
  :mock (((symbol-function 'completing-read)
          (lambda (prompt collection &rest _)
            (cond
             ((string-match "Exclude context" prompt) "@office")
             (t "")))))
  :body (pearl-gtd-do-view-excluding-context)
  :asserts (progn
             (should (get-buffer "*Pearl-GTD: Excluding @office*"))
             (with-current-buffer "*Pearl-GTD: Excluding @office*"
               (should (search-forward "Task at home" nil t))
               (should (search-forward "Task anywhere" nil t))
               (should-not (search-forward "Task at office" nil t))))
  :teardown (kill-buffer "*Pearl-GTD: Excluding @office*"))

(provide 'test-pearl-gtd-do)

;;; test-pearl-gtd-do.el ends here
