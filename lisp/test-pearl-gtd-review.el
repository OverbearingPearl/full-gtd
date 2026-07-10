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

(test-pearl-gtd-define-story test-pearl-gtd-review-daily-shows-separated-sections
  "Daily review shows Today, Next Actions, and Inbox in separate tables."
  :setup (pearl-gtd-init-initialize)
  :files (("inbox.org" "* New idea\n:PROPERTIES:\n:ID: d-1\n:CREATED: 2026-01-15\n:END:\n")
          ("actions.org" "* TODO Today task\nSCHEDULED: <2026-01-15 Thu>\n:PROPERTIES:\n:ID: d-2\n:PROJECT: Web\n:CREATED: 2026-01-10\n:END:\n* TODO Next task\n:PROPERTIES:\n:ID: d-3\n:PROJECT: App\n:CREATED: 2026-01-11\n:END:\n* DONE Completed today task\nCLOSED: [2026-01-15 Thu 10:00]\n:PROPERTIES:\n:ID: d-4\n:END:\n"))
  :mock (((symbol-function 'current-time) (lambda () (encode-time 0 0 0 15 1 2026 t))))
  :body (pearl-gtd-review-daily)
  :asserts (progn
             (should (get-buffer "*Pearl-GTD Daily Review*"))
             (with-current-buffer "*Pearl-GTD Daily Review*"
               ;; Verify sections exist
               (goto-char (point-min))
               (should (search-forward "** actions.org - Today" nil t))
               (should (search-forward "** actions.org - Completed Today" nil t))
               (should (search-forward "** actions.org - Next Actions" nil t))
               (should (search-forward "** inbox.org - Inbox" nil t))
               ;; Verify Today task is in Today section, not in Next Actions
               (goto-char (point-min))
               (let* ((today-start (search-forward "** actions.org - Today"))
                      (today-end (save-excursion
                                   (search-forward "** actions.org - Next Actions" nil t)
                                   (line-beginning-position))))
                 ;; Verify Today task is in Today section
                 (goto-char today-start)
                 (should (search-forward "Today task" today-end t))
                 ;; Verify Next task is NOT in Today section
                 (goto-char today-start)
                 (should-not (search-forward "Next task" today-end t)))
               ;; Verify Next Actions contains Next task but not Today task
               (goto-char (point-min))
               (let* ((next-start (search-forward "** actions.org - Next Actions"))
                      (next-end (point-max)))
                 (goto-char next-start)
                 (should (search-forward "Next task" next-end t))
                 (goto-char next-start)
                 (should-not (search-forward "Today task" next-end t)))
               ;; Verify Today section has 7 columns (no Created)
               (goto-char (point-min))
               (search-forward "** actions.org - Today")
               (forward-line 1)
               (beginning-of-line)
               (should (search-forward-regexp "|[ \t]*Headline[ \t]*|[ \t]*Status[ \t]*|[ \t]*Scheduled[ \t]*|[ \t]*Deadline[ \t]*|[ \t]*Context[ \t]*|[ \t]*Delegated[ \t]*|[ \t]*Project[ \t]*|" nil t))
               ;; Verify Inbox section has only 2 columns (Headline and Created)
               (goto-char (point-min))
               (search-forward "** inbox.org - Inbox")
               (forward-line 1)
               (beginning-of-line)
               (should (search-forward-regexp "|[ \t]*Headline[ \t]*|[ \t]*Created[ \t]*|" nil t))
               (should-not (search-forward-regexp "|[ \t]*Status[ \t]*|" (line-end-position) t))
               (should-not (search-forward-regexp "|[ \t]*Scheduled[ \t]*|" (line-end-position) t))
               (should-not (search-forward-regexp "|[ \t]*Deadline[ \t]*|" (line-end-position) t))
               (should-not (search-forward-regexp "|[ \t]*Context[ \t]*|" (line-end-position) t))
               (should-not (search-forward-regexp "|[ \t]*Delegated[ \t]*|" (line-end-position) t))
               (should-not (search-forward-regexp "|[ \t]*Project[ \t]*|" (line-end-position) t))
               ;; Verify GTD workflow order: Today → Completed Today → Next Actions → Inbox
               (goto-char (point-min))
               (let ((pos-today (search-forward "** actions.org - Today" nil t))
                     (pos-completed (search-forward "** actions.org - Completed Today" nil t))
                     (pos-next (search-forward "** actions.org - Next Actions" nil t))
                     (pos-inbox (search-forward "** inbox.org - Inbox" nil t)))
                 (should (< pos-today pos-completed))
                 (should (< pos-completed pos-next))
                 (should (< pos-next pos-inbox)))
               ;; Verify completed task is in Completed Today section and not in Today
               (goto-char (point-min))
               (let* ((today-start (search-forward "** actions.org - Today"))
                      (today-end (save-excursion
                                   (search-forward "** actions.org - Completed Today" nil t)
                                   (line-beginning-position))))
                 (goto-char today-start)
                 (should-not (search-forward "Completed today task" today-end t)))
               (goto-char (point-min))
               (search-forward "** actions.org - Completed Today")
               (should (search-forward "Completed today task" nil t))))
  :teardown (kill-buffer "*Pearl-GTD Daily Review*"))

(test-pearl-gtd-define-story test-pearl-gtd-review-weekly-shows-all-sections
  "Weekly review aggregates all lists and action sub-views into separate tables."
  :setup (pearl-gtd-init-initialize)
  :files (("inbox.org" "* Unprocessed\n:PROPERTIES:\n:ID: w-1\n:END:\n")
          ("actions.org" "* TODO Normal action\n:PROPERTIES:\n:ID: w-2\n:PROJECT: Active project\n:END:\n* TODO Overdue task\nSCHEDULED: <2026-01-01 Wed>\n:PROPERTIES:\n:ID: w-overdue\n:END:\n* TODO Delegated task\n:PROPERTIES:\n:ID: w-del\n:DELEGATED: Bob\n:END:\n* DONE Completed today task\nCLOSED: [2026-01-15 Thu 10:00]\n:PROPERTIES:\n:ID: w-done-today\n:END:\n* TODO No project task\n:PROPERTIES:\n:ID: w-no-proj\n:END:\n")
          ("someday.org" "* Maybe later\n:PROPERTIES:\n:ID: w-4\n:END:\n"))
  :mock (((symbol-function 'current-time) (lambda () (encode-time 0 0 0 15 1 2026))))
  :body (pearl-gtd-review-weekly)
  :asserts (progn
             (should (get-buffer "*Pearl-GTD Weekly Review*"))
             (with-current-buffer "*Pearl-GTD Weekly Review*"
               ;; Verify all sections present
               (goto-char (point-min))
               (should (search-forward "** inbox.org - Inbox" nil t))
               (should (search-forward "** actions.org - Overdue" nil t))
               (should (search-forward "** actions.org - Upcoming Deadlines" nil t))
               (should (search-forward "** actions.org - Completed" nil t))
               (should (search-forward "** actions.org - Delegated" nil t))
               (should (search-forward "** actions.org - Next Actions" nil t))
               (should (search-forward "** Projects - Stuck" nil t))
               (should (search-forward "** Projects - Active" nil t))
               (should (search-forward "** actions.org - No Project" nil t))
               (should (search-forward "** someday.org - Someday" nil t))
               ;; Verify content isolation
               (goto-char (point-min))
               (search-forward "** actions.org - Overdue")
               (should (search-forward "Overdue task" nil t))
               (goto-char (point-min))
               (search-forward "** actions.org - Delegated")
               (should (search-forward "Delegated task" nil t))
               ;; Verify No Project section content
               (goto-char (point-min))
               (search-forward "** actions.org - No Project")
               (should (search-forward "No project task" nil t))
               ;; Verify No Project section has correct columns (no Project column and no Created column)
               (goto-char (point-min))
               (search-forward "** actions.org - No Project")
               (forward-line 1) ; Skip to table header (next line after title)
               (beginning-of-line)
               (should (search-forward-regexp "|\\s-*Headline\\s-*|\\s-*Status\\s-*|\\s-*Scheduled\\s-*|\\s-*Deadline\\s-*|\\s-*Context\\s-*|\\s-*Delegated\\s-*|" nil t))
               (should-not (search-forward-regexp "|\\s-*Project\\s-*|" (line-end-position) t))
               (should-not (search-forward-regexp "|\\s-*Created\\s-*|" (line-end-position) t))
               ;; Verify GTD weekly review order: Inbox → Overdue/Upcoming → Completed → Delegated → Next Actions → Projects → No Project → Someday
               (goto-char (point-min))
               (let ((positions (list (search-forward "** inbox.org - Inbox" nil t)
                                      (search-forward "** actions.org - Overdue" nil t)
                                      (search-forward "** actions.org - Upcoming Deadlines" nil t)
                                      (search-forward "** actions.org - Completed" nil t)
                                      (search-forward "** actions.org - Delegated" nil t)
                                      (search-forward "** actions.org - Next Actions" nil t)
                                      (search-forward "** Projects - Stuck" nil t)
                                      (search-forward "** Projects - Active" nil t)
                                      (search-forward "** actions.org - No Project" nil t)
                                      (search-forward "** someday.org - Someday" nil t))))
                 (should (equal positions (sort (copy-sequence positions) #'<))))))
  :teardown (kill-buffer "*Pearl-GTD Weekly Review*"))

(test-pearl-gtd-define-story test-pearl-gtd-review-edit-context-with-default
  "Press 'c' to edit context with current value as default."
  :setup (pearl-gtd-init-initialize)
  :files (("actions.org" (concat "* TODO Task with context\nSCHEDULED: <" (format-time-string "%Y-%m-%d %a") ">\n:PROPERTIES:\n:ID: edit-ctx-1\n:CONTEXT: home\n:PROJECT: Test\n:CREATED: 2026-01-15\n:END:\n")))
  :mock (((symbol-function 'read-string)
          (lambda (prompt &optional initial _history)
            (should (string-match-p "home" initial))
            "office")))
  :body (progn
          (pearl-gtd-review-daily)
          (with-current-buffer "*Pearl-GTD Daily Review*"
            (goto-char (point-min))
            (search-forward "** actions.org - Today")
            (search-forward "Task with context")
            (beginning-of-line)
            (pearl-gtd-review--edit-context-at-point)))
  :asserts (progn
             (should (test-pearl-gtd-file-contains-p
                      (expand-file-name "actions.org" pearl-gtd-init-base-directory)
                      ":CONTEXT:\\s-*office")))
  :teardown (kill-buffer "*Pearl-GTD Daily Review*"))

(test-pearl-gtd-define-story test-pearl-gtd-review-remove-context-by-empty-input
  "Press 'c' and delete all to remove context property."
  :setup (pearl-gtd-init-initialize)
  :files (("actions.org" (concat "* TODO Task to clear\nSCHEDULED: <" (format-time-string "%Y-%m-%d %a") ">\n:PROPERTIES:\n:ID: edit-ctx-2\n:CONTEXT: home\n:PROJECT: Test\n:CREATED: 2026-01-15\n:END:\n")))
  :mock (((symbol-function 'read-string)
          (lambda (_prompt &optional initial _history)
            (should (string= initial "home"))
            "")))
  :body (progn
          (pearl-gtd-review-daily)
          (with-current-buffer "*Pearl-GTD Daily Review*"
            (goto-char (point-min))
            (search-forward "** actions.org - Today")
            (search-forward "Task to clear")
            (beginning-of-line)
            (pearl-gtd-review--edit-context-at-point)))
  :asserts (should-not (test-pearl-gtd-file-contains-p
                        (expand-file-name "actions.org" pearl-gtd-init-base-directory)
                        ":CONTEXT:"))
  :teardown (kill-buffer "*Pearl-GTD Daily Review*"))

(test-pearl-gtd-define-story test-pearl-gtd-review-edit-delegated-with-default
  "Press 'd' to edit delegated with current value shown."
  :setup (pearl-gtd-init-initialize)
  :files (("actions.org" "* TODO Delegated task\n:PROPERTIES:\n:ID: edit-del-1\n:DELEGATED: John\n:PROJECT: Test\n:CREATED: 2026-01-15\n:END:\n"))
  :mock (((symbol-function 'read-string)
          (lambda (_prompt &optional initial _history)
            (should (string= initial "John"))
            "Bob")))
  :body (progn
          (pearl-gtd-review-weekly)
          (with-current-buffer "*Pearl-GTD Weekly Review*"
            (goto-char (point-min))
            (search-forward "** actions.org - Delegated")
            (search-forward "Delegated task")
            (beginning-of-line)
            (pearl-gtd-review--edit-delegated-at-point)))
  :asserts (progn
             (should (test-pearl-gtd-file-contains-p
                      (expand-file-name "actions.org" pearl-gtd-init-base-directory)
                      ":DELEGATED: Bob"))
             (should-not (test-pearl-gtd-file-contains-p
                          (expand-file-name "actions.org" pearl-gtd-init-base-directory)
                          ":DELEGATED: John")))
  :teardown (kill-buffer "*Pearl-GTD Weekly Review*"))

(test-pearl-gtd-define-story test-pearl-gtd-review-edit-schedule-with-default
  "Press 't' to edit scheduled date with current value as default."
  :setup (pearl-gtd-init-initialize)
  :files (("actions.org" (concat "* TODO Scheduled task\nSCHEDULED: <" (format-time-string "%Y-%m-%d %a") ">\n:PROPERTIES:\n:ID: edit-sch-1\n:PROJECT: Test\n:CREATED: 2026-01-15\n:END:\n")))
  :mock (((symbol-function 'read-string)
          (lambda (_prompt &optional initial _history)
            (should (string-match-p (format-time-string "%Y-%m-%d") (or initial "")))
            "2026-05-15")))
  :body (progn
          (pearl-gtd-review-daily)
          (with-current-buffer "*Pearl-GTD Daily Review*"
            (goto-char (point-min))
            (search-forward "** actions.org - Today")
            (search-forward "Scheduled task")
            (beginning-of-line)
            (pearl-gtd-review--edit-scheduled-at-point)))
  :asserts (progn
             (should (test-pearl-gtd-file-contains-p
                      (expand-file-name "actions.org" pearl-gtd-init-base-directory)
                      "SCHEDULED: <2026-05-15"))
             (should-not (test-pearl-gtd-file-contains-p
                          (expand-file-name "actions.org" pearl-gtd-init-base-directory)
                          "SCHEDULED: <2026-01-01")))
  :teardown (kill-buffer "*Pearl-GTD Daily Review*"))

(test-pearl-gtd-define-story test-pearl-gtd-review-jump-to-task-from-table
  "Press RET to jump to task in source file."
  :setup (pearl-gtd-init-initialize)
  :files (("actions.org" "* TODO Jump target\n:PROPERTIES:\n:ID: jump-1\n:PROJECT: Test\n:CREATED: 2026-01-15\n:END:\n"))
  :mock nil
  :body (progn
          (pearl-gtd-review-weekly)
          (with-current-buffer "*Pearl-GTD Weekly Review*"
            (goto-char (point-min))
            (search-forward "** actions.org - Next Actions")
            (search-forward "Jump target")
            (beginning-of-line)
            (pearl-gtd-review--goto-task-at-point)))
  :asserts (progn
             (should (get-file-buffer (expand-file-name "actions.org" pearl-gtd-init-base-directory)))
             (with-current-buffer (get-file-buffer (expand-file-name "actions.org" pearl-gtd-init-base-directory))
               (should (looking-at-p "\\*+ TODO Jump target"))))
  :teardown (progn
             (kill-buffer "*Pearl-GTD Weekly Review*")
             (let ((buf (get-file-buffer (expand-file-name "actions.org" pearl-gtd-init-base-directory))))
               (when buf (kill-buffer buf)))))

(test-pearl-gtd-define-story test-pearl-gtd-review-keybinding-set-deadline
  "Press 's' in review buffer to set deadline for task at point."
  :setup (pearl-gtd-init-initialize)
  :files (("actions.org" "* TODO Task for deadline\n:PROPERTIES:\n:ID: dl-1\n:PROJECT: Test\n:CREATED: 2026-01-15\n:END:\n"))
  :mock (((symbol-function 'read-string)
          (lambda (prompt &rest _)
            (cond
             ((string-match "Deadline" prompt) "2026-05-20")
             ((string-match "Reminder" prompt) "2")
             (t "")))))
  :body (progn
          (pearl-gtd-review-weekly)
          (with-current-buffer "*Pearl-GTD Weekly Review*"
            (goto-char (point-min))
            (search-forward "** actions.org - Next Actions")
            (search-forward "Task for deadline")
            (beginning-of-line)
            (pearl-gtd-review--set-deadline-at-point)))
  :asserts (progn
             (should (test-pearl-gtd-file-contains-p
                      (expand-file-name "actions.org" pearl-gtd-init-base-directory)
                      "DEADLINE: <2026-05-20"))
             (should (test-pearl-gtd-file-contains-p
                      (expand-file-name "actions.org" pearl-gtd-init-base-directory)
                      ":REMINDER_DAYS: 2")))
  :teardown (kill-buffer "*Pearl-GTD Weekly Review*"))

(test-pearl-gtd-define-story test-pearl-gtd-review-user-edits-task-in-review-window
  "User edits a task directly from review buffer."
  :setup (pearl-gtd-init-initialize)
  :files (("actions.org" "* TODO Old task name\n:PROPERTIES:\n:ID: edit-old-1\n:PROJECT: Test\n:CREATED: 2026-01-15\n:END:\n"))
  :mock (((symbol-function 'read-string) (lambda (&rest _) "Updated task name")))
  :body (progn
          (pearl-gtd-review-weekly)
          (with-current-buffer "*Pearl-GTD Weekly Review*"
            (goto-char (point-min))
            (search-forward "** actions.org - Next Actions")
            (search-forward "Old task name")
            (beginning-of-line)
            (pearl-gtd-review--rename-task-at-point)))
  :asserts (progn
             (should (test-pearl-gtd-file-contains-p
                      (expand-file-name "actions.org" pearl-gtd-init-base-directory)
                      "* TODO Updated task name"))
             (should-not (test-pearl-gtd-file-contains-p
                          (expand-file-name "actions.org" pearl-gtd-init-base-directory)
                          "* TODO Old task name")))
  :teardown (kill-buffer "*Pearl-GTD Weekly Review*"))

(test-pearl-gtd-define-story test-pearl-gtd-review-jump-across-sections-and-files
  "RET jump works correctly from tasks in different sections and source files."
  :setup (pearl-gtd-init-initialize)
  :files (("actions.org" "* TODO Today task\nSCHEDULED: <2026-01-15 Thu>\n:PROPERTIES:\n:ID: jump-sec-1\n:END:\n* TODO Next task\n:PROPERTIES:\n:ID: jump-sec-2\n:END:\n")
          ("inbox.org" "* Inbox item\n:PROPERTIES:\n:ID: jump-sec-3\n:END:\n"))
  :mock (((symbol-function 'current-time) (lambda () (encode-time 0 0 0 15 1 2026))))
  :body (progn
          (pearl-gtd-review-daily)
          (with-current-buffer "*Pearl-GTD Daily Review*"
            (goto-char (point-min))
            (search-forward "** actions.org - Next Actions")
            (search-forward "Next task")
            (beginning-of-line)
            (pearl-gtd-review--goto-task-at-point)))
  :asserts (progn
             (should (get-file-buffer (expand-file-name "actions.org" pearl-gtd-init-base-directory)))
             (with-current-buffer (get-file-buffer (expand-file-name "actions.org" pearl-gtd-init-base-directory))
               (should (looking-at-p "\\*+ TODO Next task"))))
  :teardown (progn
              (kill-buffer "*Pearl-GTD Daily Review*")
              (let ((buf (get-file-buffer (expand-file-name "actions.org" pearl-gtd-init-base-directory))))
                (when buf (kill-buffer buf)))))

(test-pearl-gtd-define-story test-pearl-gtd-review-project-row-shows-stats
  "Project row displays total, todo, done counts and next deadline."
  :setup (pearl-gtd-init-initialize)
  :files (("actions.org" "* TODO Task 1\n:PROPERTIES:\n:ID: p1-1\n:PROJECT: Website\n:END:\n* DONE Task 2\n:PROPERTIES:\n:ID: p1-2\n:PROJECT: Website\n:END:\n* TODO Task 3\nDEADLINE: <2026-05-20>\n:PROPERTIES:\n:ID: p1-3\n:PROJECT: Website\n:END:\n"))
  :mock nil
  :body (pearl-gtd-review-weekly)
  :asserts (progn
             (should (get-buffer "*Pearl-GTD Weekly Review*"))
             (with-current-buffer "*Pearl-GTD Weekly Review*"
               (goto-char (point-min))
               (search-forward "** Projects - Active")
               (forward-line 3)
               (beginning-of-line)
               (should (search-forward-regexp "|\\s-*Website\\s-*|\\s-*3\\s-*|\\s-*2\\s-*|\\s-*1\\s-*|\\s-*<2026-05-20[^>]*>\\s-*|" (line-end-position) t))))
  :teardown (kill-buffer "*Pearl-GTD Weekly Review*"))

(test-pearl-gtd-define-story test-pearl-gtd-review-jump-to-project-tasks
  "Press RET on project row opens project task sub-view."
  :setup (pearl-gtd-init-initialize)
  :files (("actions.org" "* TODO Task A\n:PROPERTIES:\n:ID: proj-a-1\n:PROJECT: Alpha\n:END:\n* TODO Task B\n:PROPERTIES:\n:ID: proj-a-2\n:PROJECT: Alpha\n:END:\n"))
  :mock nil
  :body (progn
          (pearl-gtd-review-weekly)
          (with-current-buffer "*Pearl-GTD Weekly Review*"
            (goto-char (point-min))
            (search-forward "** Projects - Active")
            (search-forward "Alpha")
            (beginning-of-line)
            (pearl-gtd-review--goto-task-at-point)))
  :asserts (progn
             (should (get-buffer "*Pearl-GTD Project: Alpha*"))
             (with-current-buffer "*Pearl-GTD Project: Alpha*"
               (should (search-forward "Task A" nil t))
               (should (search-forward "Task B" nil t))))
  :teardown (progn
              (kill-buffer "*Pearl-GTD Weekly Review*")
              (when (get-buffer "*Pearl-GTD Project: Alpha*")
                (kill-buffer "*Pearl-GTD Project: Alpha*"))))

(test-pearl-gtd-define-story test-pearl-gtd-review-return-from-project-view
  "Press q in project sub-view returns to weekly review."
  :setup (pearl-gtd-init-initialize)
  :files (("actions.org" "* TODO Task\n:PROPERTIES:\n:ID: ret-1\n:PROJECT: Beta\n:END:\n"))
  :mock nil
  :body (progn
          (pearl-gtd-review-weekly)
          (with-current-buffer "*Pearl-GTD Weekly Review*"
            (goto-char (point-min))
            (search-forward "** Projects - Active")
            (search-forward "Beta")
            (beginning-of-line)
            (pearl-gtd-review--goto-task-at-point))
          (with-current-buffer "*Pearl-GTD Project: Beta*"
            (pearl-gtd-review--quit-or-return)))
  :asserts (progn
             (should-not (get-buffer "*Pearl-GTD Project: Beta*"))
             (should (get-buffer "*Pearl-GTD Weekly Review*")))
  :teardown (when (get-buffer "*Pearl-GTD Weekly Review*")
              (kill-buffer "*Pearl-GTD Weekly Review*")))

(test-pearl-gtd-define-story test-pearl-gtd-review-stuck-project-shows-zero-todo
  "Stuck project shows zero todo count."
  :setup (pearl-gtd-init-initialize)
  :files (("actions.org" "* DONE Completed task\n:PROPERTIES:\n:ID: stuck-1\n:PROJECT: StuckProj\n:END:\n* Scheduled but no todo\nSCHEDULED: <2026-04-10 Fri>\n:PROPERTIES:\n:ID: stuck-2\n:PROJECT: StuckProj\n:END:\n"))
  :mock nil
  :body (pearl-gtd-review-weekly)
  :asserts (progn
             (should (get-buffer "*Pearl-GTD Weekly Review*"))
             (with-current-buffer "*Pearl-GTD Weekly Review*"
               (goto-char (point-min))
               (search-forward "** Projects - Stuck")
               (forward-line 3)
               (beginning-of-line)
               (should (search-forward-regexp "|\\s-*StuckProj\\s-*|\\s-*2\\s-*|\\s-*0\\s-*|\\s-*1\\s-*|" (line-end-position) t))))
  :teardown (kill-buffer "*Pearl-GTD Weekly Review*"))

(test-pearl-gtd-define-story test-pearl-gtd-review-project-exact-match-not-substring
  "Project names that are substrings of each other are matched exactly."
  :setup (pearl-gtd-init-initialize)
  :files (("actions.org" "* DONE P1 task\n:PROPERTIES:\n:ID: exact-1\n:PROJECT: P1\n:END:\n* TODO P10 task\n:PROPERTIES:\n:ID: exact-2\n:PROJECT: P10\n:END:\n"))
  :mock nil
  :body (pearl-gtd-review-weekly)
  :asserts (progn
             (should (get-buffer "*Pearl-GTD Weekly Review*"))
             (with-current-buffer "*Pearl-GTD Weekly Review*"
               ;; Get section boundaries first
               (goto-char (point-min))
               (let* ((stuck-pos (search-forward "** Projects - Stuck"))
                      (active-pos (search-forward "** Projects - Active"))
                      (someday-pos (search-forward "** someday.org - Someday"))
                      (stuck-start stuck-pos)
                      (stuck-end active-pos)
                      (active-start active-pos)
                      (active-end someday-pos))
                 ;; P1 has no TODO, must appear in Stuck
                 (goto-char stuck-start)
                 (should (re-search-forward "|\\s-*P1\\s-*|" stuck-end t))
                 (goto-char stuck-start)
                 (should-not (re-search-forward "|\\s-*P10\\s-*|" stuck-end t))
                 ;; P10 has TODO, must appear in Active
                 (goto-char active-start)
                 (should (re-search-forward "|\\s-*P10\\s-*|" active-end t))
                 (goto-char active-start)
                 (should-not (re-search-forward "|\\s-*P1\\s-*|" active-end t)))
               ;; Verify P1 stats: Total=1, Todo=0, Done=1
               (goto-char (point-min))
               (search-forward "** Projects - Stuck")
               (search-forward "P1")
               (beginning-of-line)
               (should (search-forward-regexp "|\\s-*P1\\s-*|\\s-*1\\s-*|\\s-*0\\s-*|\\s-*1\\s-*|" (line-end-position) t))
               ;; Verify P10 stats: Total=1, Todo=1, Done=0
               (goto-char (point-min))
               (search-forward "** Projects - Active")
               (search-forward "P10")
               (beginning-of-line)
               (should (search-forward-regexp "|\\s-*P10\\s-*|\\s-*1\\s-*|\\s-*1\\s-*|\\s-*0\\s-*|" (line-end-position) t))))
  :teardown (kill-buffer "*Pearl-GTD Weekly Review*"))

(test-pearl-gtd-define-story test-pearl-gtd-review-weekly-no-project-table-no-project-column
  "No Project table should not have Project column and should be after Project sections."
  :setup (pearl-gtd-init-initialize)
  :files (("actions.org" "* TODO No project task 1\n:PROPERTIES:\n:ID: np-1\n:CREATED: 2026-01-15\n:END:\n* TODO No project task 2\nSCHEDULED: <2026-01-20 Fri>\n:PROPERTIES:\n:ID: np-2\n:CONTEXT: home\n:CREATED: 2026-01-16\n:END:\n* TODO Project task\n:PROPERTIES:\n:ID: p-1\n:PROJECT: TestProject\n:CREATED: 2026-01-17\n:END:\n"))
  :mock (((symbol-function 'current-time) (lambda () (encode-time 0 0 0 15 1 2026))))
  :body (pearl-gtd-review-weekly)
  :asserts (progn
             (should (get-buffer "*Pearl-GTD Weekly Review*"))
             (with-current-buffer "*Pearl-GTD Weekly Review*"
               ;; Verify No Project section is after Project sections
               (goto-char (point-min))
               (let ((pos-active (search-forward "** Projects - Active" nil t))
                     (pos-no-project (search-forward "** actions.org - No Project" nil t))
                     (pos-someday (search-forward "** someday.org - Someday" nil t)))
                 (should (< pos-active pos-no-project))
                 (should (< pos-no-project pos-someday)))
               ;; Verify No Project table has correct columns (6 columns: no Project and no Created)
               (goto-char (point-min))
               (search-forward "** actions.org - No Project")
               (forward-line 1) ; Skip to table header
               (beginning-of-line)
               (let ((line (buffer-substring (line-beginning-position) (line-end-position))))
                 ;; Count pipe separators - should be 7 pipes for 6 columns
                 (let ((pipe-count (cl-count ?| line)))
                   (should (= pipe-count 7)))
                 ;; Verify column headers
                 (should (string-match-p "Headline" line))
                 (should (string-match-p "Status" line))
                 (should (string-match-p "Scheduled" line))
                 (should (string-match-p "Deadline" line))
                 (should (string-match-p "Context" line))
                 (should (string-match-p "Delegated" line))
                 (should-not (string-match-p "Project" line))
                 (should-not (string-match-p "Created" line)))
               ;; Verify data rows also have correct number of columns
               (goto-char (point-min))
               (search-forward "** actions.org - No Project")
               (search-forward "|---------") ; Separator line
               (forward-line 1)
               (while (and (not (eobp)) (looking-at "|"))
                 (let ((line (buffer-substring (line-beginning-position) (line-end-position))))
                   (let ((pipe-count (cl-count ?| line)))
                     (should (= pipe-count 7))) ; 6 columns + closing pipe
                   (should (string-match-p "No project task" line))
                   (should-not (string-match-p "TestProject" line)))
                 (forward-line 1))))
  :teardown (kill-buffer "*Pearl-GTD Weekly Review*"))

(provide 'test-pearl-gtd-review)

;;; test-pearl-gtd-review.el ends here
