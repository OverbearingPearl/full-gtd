;;; test-pearl-gtd-review.el --- User stories: Review phase  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 OverbearingPearl

;; Author: OverbearingPearl <OverbearingPearl@outlook.com>
;; Version: 0.1.0
;; Package-Requires: ((emacs "27.1"))
;; Keywords: outlines, tools, convenience, productivity, gtd, org
;; URL: https://github.com/OverbearingPearl/pearl-gtd

;;; Commentary:

;; User stories for periodic reviews.

;;; Code:

(require 'ert)
(require 'pearl-gtd)
(require 'test-pearl-gtd)

(test-pearl-gtd-define-story test-pearl-gtd-review-user-runs-daily-review
  "User runs daily review to check today's actions and inbox."
  :setup (pearl-gtd-init-initialize)
  :files (("inbox.org" "* New idea\n")
          ("actions.org" (format "* TODO Daily task\nSCHEDULED: <%s>\n" (format-time-string "%Y-%m-%d"))))
  :mock nil
  :body (pearl-gtd-review-daily)
  :asserts (progn
             (should (get-buffer "*Pearl-GTD Daily Review*"))
             (with-current-buffer "*Pearl-GTD Daily Review*"
               (should (search-forward "Daily task" nil t))
               (should (search-forward "New idea" nil t))))
  :teardown (kill-buffer "*Pearl-GTD Daily Review*"))

(test-pearl-gtd-define-story test-pearl-gtd-review-user-runs-weekly-review
  "User runs weekly review across all lists."
  :setup (pearl-gtd-init-initialize)
  :files (("inbox.org" "* Unprocessed\n")
          ("actions.org" "* TODO Weekly task\n")
          ("projects.org" "* Active project\n")
          ("someday.org" "* Maybe later\n"))
  :mock (((symbol-function 'y-or-n-p) (lambda (&rest _) t)))
  :body (pearl-gtd-review-weekly)
  :asserts (progn
             (should (get-buffer "*Pearl-GTD Weekly Review*"))
             (with-current-buffer "*Pearl-GTD Weekly Review*"
               (should (search-forward "Unprocessed" nil t))
               (should (search-forward "Weekly task" nil t))
               (should (search-forward "Active project" nil t))
               (should (search-forward "Maybe later" nil t))))
  :teardown (kill-buffer "*Pearl-GTD Weekly Review*"))

(test-pearl-gtd-define-story test-pearl-gtd-review-user-filters-undelegated-tasks
  "User reviews tasks that are not delegated."
  :setup (pearl-gtd-init-initialize)
  :files (("actions.org" "* Task A\n:PROPERTIES:\n:DELEGATED: John\n:END:\n* Task B\n"))
  :mock nil
  :body (pearl-gtd-review-undelegated)
  :asserts (progn
             (should (get-buffer "*Pearl-GTD: Undelegated*"))
             (with-current-buffer "*Pearl-GTD: Undelegated*"
               (should (search-forward "Task B" nil t))
               (should-not (search-forward "Task A" nil t))))
  :teardown (kill-buffer "*Pearl-GTD: Undelegated*"))

(test-pearl-gtd-define-story test-pearl-gtd-review-user-edits-task-in-review-window
  "User edits a task directly from review buffer."
  :setup (pearl-gtd-init-initialize)
  :files (("actions.org" (format "* TODO Old task name\nSCHEDULED: <%s>\n" (format-time-string "%Y-%m-%d"))))
  :mock (((symbol-function 'read-string) (lambda (&rest _) "Updated task name")))
  :body (progn
         (pearl-gtd-review-daily)
         (with-current-buffer "*Pearl-GTD Daily Review*"
           (goto-char (point-min))
           (search-forward "Old task name")
           (pearl-gtd-review-edit-task)))
  :asserts (progn
             (should (test-pearl-gtd-file-contains-p
                      (expand-file-name "actions.org" pearl-gtd-init-base-directory)
                      "* TODO Updated task name"))
             (should-not (test-pearl-gtd-file-contains-p
                          (expand-file-name "actions.org" pearl-gtd-init-base-directory)
                          "Old task name")))
  :teardown (kill-buffer "*Pearl-GTD Daily Review*"))

(test-pearl-gtd-define-story test-pearl-gtd-review-user-checks-overdue-tasks
  "User reviews overdue scheduled tasks."
  :setup (pearl-gtd-init-initialize)
  :files (("actions.org" "* TODO Overdue task\nSCHEDULED: <2026-01-01>\n"))
  :mock nil
  :body (pearl-gtd-review-overdue)
  :asserts (progn
             (should (get-buffer "*Pearl-GTD: Overdue*"))
             (with-current-buffer "*Pearl-GTD: Overdue*"
               (should (search-forward "Overdue task" nil t))))
  :teardown (kill-buffer "*Pearl-GTD: Overdue*"))

(test-pearl-gtd-define-story test-pearl-gtd-review-user-checks-stuck-projects
  "User reviews projects with no next actions."
  :setup (pearl-gtd-init-initialize)
  :files (("projects.org" "* Stuck project\n:PROPERTIES:\n:CREATED: 2026-01-01\n:END:\n")
          ("actions.org" ""))
  :mock nil
  :body (pearl-gtd-review-stuck-projects)
  :asserts (progn
             (should (get-buffer "*Pearl-GTD: Stuck Projects*"))
             (with-current-buffer "*Pearl-GTD: Stuck Projects*"
               (should (search-forward "Stuck project" nil t))))
  :teardown (kill-buffer "*Pearl-GTD: Stuck Projects*"))

(test-pearl-gtd-define-story test-pearl-gtd-review-user-sets-deadline-with-reminder
  "User sets deadline with automatic reminder before due date."
  :setup (pearl-gtd-init-initialize)
  :files (("actions.org" "* TODO Task with deadline\n"))
  :mock (((symbol-function 'read-string)
          (lambda (prompt &rest _)
            (cond
             ((string-match "Deadline" prompt) "2026-05-20")
             ((string-match "Reminder days" prompt) "2")
             (t "")))))
  :body (progn
         (find-file (expand-file-name "actions.org" pearl-gtd-init-base-directory))
         (goto-char (point-min))
         (pearl-gtd-review-set-deadline))
  :asserts (progn
             (should (test-pearl-gtd-file-contains-p
                      (expand-file-name "actions.org" pearl-gtd-init-base-directory)
                      "DEADLINE: <2026-05-20"))
             (should (test-pearl-gtd-file-contains-p
                      (expand-file-name "actions.org" pearl-gtd-init-base-directory)
                      ":REMINDER_DAYS: 2")))
  :teardown nil)

(test-pearl-gtd-define-story test-pearl-gtd-review-user-views-upcoming-deadlines
  "User views tasks with deadlines in next 7 days."
  :setup (pearl-gtd-init-initialize)
  :files (("actions.org" (format "* TODO Near deadline\nDEADLINE: <%s>\n* TODO Far deadline\nDEADLINE: <%s>\n"
                                  (format-time-string "%Y-%m-%d" (time-add (current-time) (days-to-time 3)))
                                  (format-time-string "%Y-%m-%d" (time-add (current-time) (days-to-time 30))))))
  :mock nil
  :body (pearl-gtd-review-view-upcoming-deadlines)
  :asserts (progn
             (should (get-buffer "*Pearl-GTD: Upcoming Deadlines*"))
             (with-current-buffer "*Pearl-GTD: Upcoming Deadlines*"
               (should (search-forward "Near deadline" nil t))
               (should-not (search-forward "Far deadline" nil t))))
  :teardown (kill-buffer "*Pearl-GTD: Upcoming Deadlines*"))

(test-pearl-gtd-define-story test-pearl-gtd-review-user-receives-due-reminders
  "User checks and receives notifications for due reminders."
  :setup (pearl-gtd-init-initialize)
  :files (("actions.org" (format "* TODO Task with reminder\nDEADLINE: <%s>\n:PROPERTIES:\n:REMINDER_DAYS: 0\n:END:\n"
                                  (format-time-string "%Y-%m-%d"))))
  :mock nil
  :body (pearl-gtd-review-check-reminders)
  :asserts (progn
             (should (get-buffer "*Pearl-GTD: Reminders*"))
             (with-current-buffer "*Pearl-GTD: Reminders*"
               (should (search-forward "Task with reminder" nil t))))
  :teardown (kill-buffer "*Pearl-GTD: Reminders*"))

(test-pearl-gtd-define-story test-pearl-gtd-review-user-tracks-delegation-status
  "User checks status of delegated tasks and sees waiting time."
  :setup (pearl-gtd-init-initialize)
  :files (("actions.org" (format "* TODO Delegated task\n:PROPERTIES:\n:DELEGATED: Bob\n:DELEGATED_DATE: <%s>\n:END:\n"
                                  (format-time-string "%Y-%m-%d" (time-subtract (current-time) (days-to-time 54))))))
  :mock nil
  :body (pearl-gtd-review-track-delegation-status)
  :asserts (progn
             (should (get-buffer "*Pearl-GTD: Delegated Status*"))
             (with-current-buffer "*Pearl-GTD: Delegated Status*"
               (goto-char (point-min))
               (should (search-forward "Bob" nil t))
               (should (search-forward "54 days" nil t))))
  :teardown (kill-buffer "*Pearl-GTD: Delegated Status*"))

(test-pearl-gtd-define-story test-pearl-gtd-review-user-sends-reminder-for-overdue-delegation
  "User sends reminder for overdue delegated task."
  :setup (pearl-gtd-init-initialize)
  :files (("actions.org" "* TODO Overdue delegated task\nDEADLINE: <2026-04-01>\n:PROPERTIES:\n:DELEGATED: Charlie\n:END:\n"))
  :mock (((symbol-function 'y-or-n-p) (lambda (&rest _) t)))
  :body (progn
         (find-file (expand-file-name "actions.org" pearl-gtd-init-base-directory))
         (goto-char (point-min))
         (pearl-gtd-review-send-delegation-reminder))
  :asserts (progn
             (should (test-pearl-gtd-file-contains-p
                      (expand-file-name "actions.org" pearl-gtd-init-base-directory)
                      ":REMINDER_SENT:")))
  :teardown nil)

(provide 'test-pearl-gtd-review)

;;; test-pearl-gtd-review.el ends here
