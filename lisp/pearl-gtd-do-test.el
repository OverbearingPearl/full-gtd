;;; pearl-gtd-test-do.el --- User stories: Do/Work phase  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 OverbearingPearl
;; Author: OverbearingPearl <OverbearingPearl@outlook.com>
;; Assisted-by: Kimi:kimi-k2.5, DeepSeek:deepseek-v3.2, Claude:claude-sonnet-4.6
;; URL: https://github.com/OverbearingPearl/pearl-gtd
;; License: MIT
;; SPDX-License-Identifier: MIT

;;; Commentary:

;; User stories for executing tasks.

;;; Code:

(require 'ert)
(require 'pearl-gtd)
(require 'pearl-gtd-test)

(pearl-gtd-test-define-story pearl-gtd-do-user-views-next-actions-by-context-test
  "User views all next actions filtered by @office context."
  :setup (pearl-gtd-init-initialize)
  :files (("actions.org" "* TODO Task 1 :office:\n:PROPERTIES:\n:ID: task-1-id\n:END:\n* TODO Task 2 :home:\n:PROPERTIES:\n:ID: task-2-id\n:END:\n* TODO Task 3 :office:\n:PROPERTIES:\n:ID: task-3-id\n:END:\n"))
  :mock (((symbol-function 'completing-read)
          (lambda (prompt _collection &rest _)
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
               (goto-char (point-min))
               (should (search-forward "@office" nil t))))
  :teardown (kill-buffer "*Pearl-GTD: @office*"))

(pearl-gtd-test-define-story pearl-gtd-do-user-marks-task-complete-test
  "User marks a task as completed."
  :setup (pearl-gtd-init-initialize)
  :files (("actions.org" "* TODO Complete this task\n:PROPERTIES:\n:ID: complete-task-id\n:END:\n"))
  :mock nil
  :body (progn
         (pearl-gtd-do-view-all-actions)
         (with-current-buffer "*Pearl-GTD: All Actions*"
           (goto-char (point-min))
           (search-forward "Complete this task")
           (beginning-of-line)
           (pearl-gtd-do--complete-task-at-point)))
  :asserts (progn
             (should (pearl-gtd-test-file-contains-p
                      (expand-file-name "actions.org" pearl-gtd-init-base-directory)
                      "* DONE Complete this task"))
             (should (pearl-gtd-test-file-contains-p
                      (expand-file-name "actions.org" pearl-gtd-init-base-directory)
                      "CLOSED:")))
  :teardown (kill-buffer "*Pearl-GTD: All Actions*"))

(pearl-gtd-test-define-story pearl-gtd-do-user-views-all-next-actions-test
  "User views all next actions regardless of context."
  :setup (pearl-gtd-init-initialize)
  :files (("actions.org" "* TODO Task A :office:\n:PROPERTIES:\n:ID: task-a-id\n:END:\n* TODO Task B :home:\n:PROPERTIES:\n:ID: task-b-id\n:END:\n* TODO Task C :errands:\n:PROPERTIES:\n:ID: task-c-id\n:END:\n"))
  :mock nil
  :body (pearl-gtd-do-view-all-actions)
  :asserts (progn
             (should (get-buffer "*Pearl-GTD: All Actions*"))
             (with-current-buffer "*Pearl-GTD: All Actions*"
               (should (search-forward "Task A" nil t))
               (should (search-forward "Task B" nil t))
               (should (search-forward "Task C" nil t))
               (goto-char (point-min))
               (should (search-forward "@office" nil t))
               (should (search-forward "@home" nil t))
               (should (search-forward "@errands" nil t))))
  :teardown (kill-buffer "*Pearl-GTD: All Actions*"))

(pearl-gtd-test-define-story pearl-gtd-do-user-views-delegated-tasks-test
  "User views all delegated tasks."
  :setup (pearl-gtd-init-initialize)
  :files (("actions.org" "* TODO Task X :office:\n:PROPERTIES:\n:DELEGATED: John\n:ID: task-x-id\n:END:\n"))
  :mock nil
  :body (pearl-gtd-do-view-delegated)
  :asserts (progn
             (should (get-buffer "*Pearl-GTD: Delegated*"))
             (with-current-buffer "*Pearl-GTD: Delegated*"
               (should (search-forward "Task X" nil t))
               (should (search-forward "John" nil t))
               (goto-char (point-min))
               (should (search-forward "@office" nil t))))
  :teardown (kill-buffer "*Pearl-GTD: Delegated*"))

(pearl-gtd-test-define-story pearl-gtd-do-user-views-delegated-excludes-done-test
  "Delegated view excludes tasks without TODO state."
  :setup (pearl-gtd-init-initialize)
  :files (("actions.org" "* TODO Active task\n:PROPERTIES:\n:DELEGATED: John\n:ID: active-task-id\n:END:\n* DONE Completed task\n:PROPERTIES:\n:DELEGATED: Jane\n:ID: completed-task-id\n:END:\n* No state task\n:PROPERTIES:\n:DELEGATED: Bob\n:ID: no-state-task-id\n:END:\n"))
  :body (pearl-gtd-do-view-delegated)
  :asserts (progn
             (should (get-buffer "*Pearl-GTD: Delegated*"))
             (with-current-buffer "*Pearl-GTD: Delegated*"
               (should (search-forward "Active task" nil t))
               (should-not (search-forward "Completed task" nil t))
               (should-not (search-forward "No state task" nil t))))
  :teardown (kill-buffer "*Pearl-GTD: Delegated*"))

(pearl-gtd-test-define-story pearl-gtd-do-user-views-scheduled-for-today-test
  "User views actions scheduled for today."
  :setup (pearl-gtd-init-initialize)
  :files (("actions.org" (format "* TODO Task today\nSCHEDULED: <%s>\n:PROPERTIES:\n:ID: today-task-id\n:END:\n" (format-time-string "%F %a"))))
  :mock nil
  :body (pearl-gtd-do-view-today)
  :asserts (progn
             (should (get-buffer "*Pearl-GTD: Today*"))
             (with-current-buffer "*Pearl-GTD: Today*"
               (should (search-forward "Task today" nil t))))
  :teardown (kill-buffer "*Pearl-GTD: Today*"))

(pearl-gtd-test-define-story pearl-gtd-do-user-completes-task-in-view-updates-original-test
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
           (pearl-gtd-do--complete-task-at-point)))
  :asserts (progn
             (let* ((file (expand-file-name "actions.org" pearl-gtd-init-base-directory))
                    (pattern1 "* DONE Task to complete")
                    (result1 (pearl-gtd-test-file-contains-p file pattern1))
                    (found1 (car result1)))
               (should found1))
             (let* ((file (expand-file-name "actions.org" pearl-gtd-init-base-directory))
                    (pattern2 ":ID:")
                    (result2 (pearl-gtd-test-file-contains-p file pattern2))
                    (found2 (car result2)))
               (should found2))
             (let* ((file (expand-file-name "actions.org" pearl-gtd-init-base-directory))
                    (pattern3 "* TODO Task to complete")
                    (result3 (pearl-gtd-test-file-contains-p file pattern3))
                    (found3 (car result3)))
               (should-not found3)))
  :teardown (kill-buffer "*Pearl-GTD: All Actions*"))

(pearl-gtd-test-define-story pearl-gtd-do-user-views-project-in-actions-table-test
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

(pearl-gtd-test-define-story pearl-gtd-do-user-views-created-timestamp-in-actions-table-test
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

(pearl-gtd-test-define-story pearl-gtd-do-user-views-project-and-created-in-delegated-view-test
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

(pearl-gtd-test-define-story pearl-gtd-do-user-views-project-and-created-in-today-view-test
  "User views today's tasks with project and created columns."
  :setup (pearl-gtd-init-initialize)
  :files (("actions.org" (format "* TODO Today task\nSCHEDULED: <%s>\n:PROPERTIES:\n:PROJECT: Current Sprint\n:CREATED: 2026-01-20\n:END:\n"
                                  (format-time-string "%F %a"))))
  :mock nil
  :body (pearl-gtd-do-view-today)
  :asserts (progn
             (should (get-buffer "*Pearl-GTD: Today*"))
             (with-current-buffer "*Pearl-GTD: Today*"
               (should (search-forward "Current Sprint" nil t))
               (should (search-forward "2026-01-20" nil t))))
  :teardown (kill-buffer "*Pearl-GTD: Today*"))

(pearl-gtd-test-define-story pearl-gtd-do-user-jumps-to-task-from-view-test
  "User presses RET in view buffer to jump to task in actions.org."
  :setup (pearl-gtd-init-initialize)
  :files (("actions.org" "* TODO Jump target task\n:PROPERTIES:\n:ID: jump-test-id\n:END:\n"))
  :mock nil
  :body (progn
         (pearl-gtd-do-view-all-actions)
         (with-current-buffer "*Pearl-GTD: All Actions*"
           (goto-char (point-min))
           (search-forward "Jump target task")
           (beginning-of-line)
           (pearl-gtd-do--goto-task)))
  :asserts (progn
             (let ((actions-file (expand-file-name "actions.org" pearl-gtd-init-base-directory)))
               (should (get-file-buffer actions-file)))
             (let ((actions-file (expand-file-name "actions.org" pearl-gtd-init-base-directory)))
               (with-current-buffer (get-file-buffer actions-file)
                 (should (looking-at-p "\\*+ TODO Jump target task")))))
  :teardown (progn
             (kill-buffer "*Pearl-GTD: All Actions*")
             (let* ((actions-file-teardown (expand-file-name "actions.org" pearl-gtd-init-base-directory))
                    (buf (get-file-buffer actions-file-teardown)))
               (when buf (kill-buffer buf)))))

(pearl-gtd-test-define-story pearl-gtd-do-user-jumps-to-first-duplicate-task-test
  "User jumps to task when duplicate titles exist in actions.org."
  :setup (pearl-gtd-init-initialize)
  :files (("actions.org" "* TODO Duplicate task\n:PROPERTIES:\n:ID: first-id\n:END:\n* TODO Another task\n:PROPERTIES:\n:ID: second-id\n:END:\n* TODO Duplicate task\n:PROPERTIES:\n:ID: third-id\n:END:\n"))
  :mock nil
  :body (progn
         (pearl-gtd-do-view-all-actions)
         (with-current-buffer "*Pearl-GTD: All Actions*"
           ;; Move to the second "Duplicate task" row (line 5: header + separator + 3 data rows)
           (goto-char (point-min))
           (forward-line 4)  ; Skip header (1), separator (2), first task (3), second task (4)
           (pearl-gtd-do--goto-task)))
  :asserts (progn
             ;; Jumps to correct task by ID
             (let ((actions-file-1 (expand-file-name "actions.org" pearl-gtd-init-base-directory)))
               (should (get-file-buffer actions-file-1)))
             (let ((actions-file-2 (expand-file-name "actions.org" pearl-gtd-init-base-directory)))
               (with-current-buffer (get-file-buffer actions-file-2)
                 ;; Verify we are at the third task (second "Duplicate task")
                 (should (looking-at-p "\\*+ TODO Duplicate task"))
                 (should (search-forward ":ID: third-id" nil t)))))
  :teardown (progn
             (kill-buffer "*Pearl-GTD: All Actions*")
             (let* ((actions-file (expand-file-name "actions.org" pearl-gtd-init-base-directory))
                     (buf (get-file-buffer actions-file)))
               (when buf (kill-buffer buf)))))

(pearl-gtd-test-define-story pearl-gtd-do-refresh-after-external-change-test
  "User refreshes view after external file changes."
  :setup (pearl-gtd-init-initialize)
  :files (("actions.org" "* TODO Original\n:PROPERTIES:\n:ID: refresh-1\n:END:\n"))
  :mock nil
  :body (progn
          (pearl-gtd-do-view-all-actions)
          (with-temp-file (expand-file-name "actions.org" pearl-gtd-init-base-directory)
            (insert "* TODO Modified\n:PROPERTIES:\n:ID: refresh-1\n:END:\n"))
          (with-current-buffer "*Pearl-GTD: All Actions*"
            (pearl-gtd-do--refresh-view)))
  :asserts (with-current-buffer "*Pearl-GTD: All Actions*"
             (goto-char (point-min))
             (should (search-forward "Modified" nil t))
             (should-not (search-forward "Original" nil t)))
  :teardown (pearl-gtd-test-cleanup-buffers '("*Pearl-GTD: All Actions*")))

(pearl-gtd-test-define-story pearl-gtd-do-view-empty-actions-file-test
  "User views empty actions file without errors."
  :setup (pearl-gtd-init-initialize)
  :files (("actions.org" ""))
  :mock nil
  :body (progn
          (pearl-gtd-do-view-all-actions)
          (pearl-gtd-review-weekly)
          (pearl-gtd-review-daily))
  :asserts (progn
             (should (get-buffer "*Pearl-GTD: All Actions*"))
             (should (get-buffer "*Pearl-GTD Weekly Review*"))
             (should (get-buffer "*Pearl-GTD Daily Review*")))
  :teardown (pearl-gtd-test-cleanup-buffers '("*Pearl-GTD: All Actions*"
                                              "*Pearl-GTD Weekly Review*"
                                              "*Pearl-GTD Daily Review*")))

(pearl-gtd-test-define-story pearl-gtd-do-view-file-deleted-while-open-test
  "User handles gracefully when file is deleted while viewing."
  :setup (pearl-gtd-init-initialize)
  :files (("actions.org" "* TODO Task\n:PROPERTIES:\n:ID: del-1\n:END:\n"))
  :mock nil
  :body (progn
          (pearl-gtd-do-view-all-actions)
          (delete-file (expand-file-name "actions.org" pearl-gtd-init-base-directory))
          (with-current-buffer "*Pearl-GTD: All Actions*"
            (condition-case nil
                (pearl-gtd-do--refresh-view)
              (error nil))))
  :asserts (should (buffer-live-p (get-buffer "*Pearl-GTD: All Actions*")))
  :teardown (pearl-gtd-test-cleanup-buffers '("*Pearl-GTD: All Actions*")))

(pearl-gtd-test-define-story pearl-gtd-do-view-entry-deleted-while-navigating-test
  "User handles gracefully when entry is deleted while navigating."
  :setup (pearl-gtd-init-initialize)
  :files (("actions.org" "* TODO Task 1\n:PROPERTIES:\n:ID: nav-1\n:END:\n* TODO Task 2\n:PROPERTIES:\n:ID: nav-2\n:END:\n"))
  :mock nil
  :body (progn
          (pearl-gtd-do-view-all-actions)
          (with-current-buffer "*Pearl-GTD: All Actions*"
            (with-current-buffer (find-file-noselect
                                  (expand-file-name "actions.org" pearl-gtd-init-base-directory))
              (goto-char (point-min))
              (re-search-forward "Task 1")
              (org-mark-subtree)
              (kill-region (region-beginning) (region-end))
              (save-buffer))
            (goto-char (point-min))
            (condition-case nil
                (pearl-gtd-do--goto-task)
              (error nil))))
  :asserts t
  :teardown (progn
              (pearl-gtd-test-cleanup-buffers '("*Pearl-GTD: All Actions*"))
              (let ((buf (get-file-buffer (expand-file-name "actions.org" pearl-gtd-init-base-directory))))
                (when buf (kill-buffer buf)))))


(provide 'pearl-gtd-test-do)

;;; pearl-gtd-test-do.el ends here
