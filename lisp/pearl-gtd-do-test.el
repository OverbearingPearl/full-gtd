;;; pearl-gtd-test-do.el --- User stories: Do/Work phase  -*- lexical-binding: t; -*-

;;; Commentary:

;; User stories for executing tasks via single-card sessions.

;;; Code:

(require 'ert)
(require 'pearl-gtd)
(require 'pearl-gtd-test)

;;;; Unit tests for scoring

(ert-deftest pearl-gtd-do-test-score-deadline ()
  "Deadline proximity increases score."
  (let* ((tomorrow (format-time-string "%F" (time-add (current-time) (* 24 3600))))
         (action-a (list :headline "A" :deadline nil))
         (action-b (list :headline "B" :deadline (format "<%s>" tomorrow)))
         (score-a (pearl-gtd-do--score-action action-a))
         (score-b (pearl-gtd-do--score-action action-b)))
    (should (> score-b score-a))))

(ert-deftest pearl-gtd-do-test-score-horizons ()
  "Horizon alignment increases score."
  (let* ((base (list :headline "A"))
         (with-l6 (plist-put (copy-sequence base) :l6 "Purpose"))
         (with-l3 (plist-put (copy-sequence base) :l3 "Area")))
    (should (> (pearl-gtd-do--score-action with-l6) (pearl-gtd-do--score-action base)))
    (should (> (pearl-gtd-do--score-action with-l3) (pearl-gtd-do--score-action base)))))

(ert-deftest pearl-gtd-do-test-score-context-match ()
  "Context match bonus applies when filter matches."
  (let* ((action (list :headline "A" :context "@office"))
         (score-no-filter (pearl-gtd-do--score-action action nil))
         (score-match (pearl-gtd-do--score-action action "office"))
         (score-mismatch (pearl-gtd-do--score-action action "home")))
    (should (> score-match score-no-filter))
    (should (= score-mismatch score-no-filter))))

(ert-deftest pearl-gtd-do-test-score-delegated-penalty ()
  "Delegated actions receive -100 penalty."
  (let* ((base (list :headline "Task" :deadline nil))
         (delegated (plist-put (copy-sequence base) :delegated "Bob")))
    (let ((score-base (pearl-gtd-do--score-action base))
          (score-delegated (pearl-gtd-do--score-action delegated)))
      (should (= (- score-delegated score-base) -100)))))

(ert-deftest pearl-gtd-do-test-score-future-scheduled-penalty ()
  "Future scheduled actions receive -50 penalty."
  (let* ((next-week (format-time-string "<%F>" (time-add (current-time) (* 7 24 3600))))
         (base (list :headline "Task" :deadline nil :scheduled nil))
         (future (plist-put (copy-sequence base) :scheduled next-week)))
    (let ((score-base (pearl-gtd-do--score-action base))
          (score-future (pearl-gtd-do--score-action future)))
      (should (= (- score-future score-base) -50)))))

(ert-deftest pearl-gtd-do-test-sort-actions ()
  "Actions are sorted by score descending."
  (let* ((action-a (list :headline "A" :deadline nil))
         (tomorrow (format-time-string "%F" (time-add (current-time) (* 24 3600))))
         (action-b (list :headline "B" :deadline (format "<%s>" tomorrow)))
         (sorted (pearl-gtd-do--sort-actions (list action-a action-b) nil)))
    (should (string= (plist-get (car sorted) :headline) "B"))))

;;;; Story tests for session workflow

(pearl-gtd-test-define-story pearl-gtd-do-test-session-starts-with-highest-priority
  "Session presents the highest priority action first."
  :setup (pearl-gtd-init-initialize)
  :files (("action.org" "* TODO Low priority\n:PROPERTIES:\n:ID: low-1\n:END:\n* TODO High priority\nDEADLINE: <2026-01-20 Mon>\n:PROPERTIES:\n:ID: high-1\n:END:\n"))
  :mock (((symbol-function 'completing-read) (lambda (&rest _) ""))
         ((symbol-function 'read-string) (lambda (&rest _) "")))
  :body (pearl-gtd-do)
  :asserts (progn
             (should (get-buffer "*Pearl-GTD: Do Session*"))
             (with-current-buffer "*Pearl-GTD: Do Session*"
               (goto-char (point-min))
               (should (search-forward "* High priority" nil t))))
  :teardown (pearl-gtd-test-cleanup-buffers '("*Pearl-GTD: Do Session*")))

(pearl-gtd-test-define-story pearl-gtd-do-test-session-completes-action
  "Done command marks action complete and advances."
  :setup (pearl-gtd-init-initialize)
  :files (("action.org" "* TODO First task\n:PROPERTIES:\n:ID: first-1\n:PROJECT: Test\n:END:\n* TODO Second task\n:PROPERTIES:\n:ID: second-1\n:PROJECT: Test\n:END:\n"))
  :mock (((symbol-function 'completing-read) (lambda (&rest _) ""))
         ((symbol-function 'read-string) (lambda (&rest _) "")))
  :body (progn
          (pearl-gtd-do)
          (with-current-buffer "*Pearl-GTD: Do Session*"
            (pearl-gtd-do--session-done)))
  :asserts (progn
             (should (pearl-gtd-test-file-contains-p
                      (expand-file-name "action.org" pearl-gtd-init-base-directory)
                      "* DONE First task"))
             (with-current-buffer "*Pearl-GTD: Do Session*"
               (goto-char (point-min))
               (should (search-forward "* Second task" nil t))))
  :teardown (pearl-gtd-test-cleanup-buffers '("*Pearl-GTD: Do Session*")))

(pearl-gtd-test-define-story pearl-gtd-do-test-session-snoozes-action
  "Snooze command reschedules action to tomorrow and advances."
  :setup (pearl-gtd-init-initialize)
  :files (("action.org" "* TODO Snooze me\n:PROPERTIES:\n:ID: snooze-1\n:END:\n* TODO Next task\n:PROPERTIES:\n:ID: next-1\n:END:\n"))
  :mock (((symbol-function 'completing-read) (lambda (&rest _) ""))
         ((symbol-function 'read-string) (lambda (&rest _) "")))
  :body (progn
          (pearl-gtd-do)
          (with-current-buffer "*Pearl-GTD: Do Session*"
            (pearl-gtd-do--session-snooze)))
  :asserts (progn
             (let ((tomorrow (format-time-string "%F" (time-add (current-time) (* 24 3600)))))
               (should (pearl-gtd-test-file-contains-p
                        (expand-file-name "action.org" pearl-gtd-init-base-directory)
                        (format "SCHEDULED: <%s" tomorrow))))
             (with-current-buffer "*Pearl-GTD: Do Session*"
               (goto-char (point-min))
               (should (search-forward "* Next task" nil t))))
  :teardown (pearl-gtd-test-cleanup-buffers '("*Pearl-GTD: Do Session*")))

(pearl-gtd-test-define-story pearl-gtd-do-test-session-skip-keeps-mode-active
  "Skip command keeps minor mode active for subsequent keyboard shortcuts."
  :setup (pearl-gtd-init-initialize)
  :files (("action.org" "* TODO First task\n:PROPERTIES:\n:ID: first-1\n:END:\n* TODO Second task\n:PROPERTIES:\n:ID: second-1\n:END:\n"))
  :mock (((symbol-function 'completing-read) (lambda (&rest _) ""))
         ((symbol-function 'read-string) (lambda (&rest _) "")))
  :body (progn
          (pearl-gtd-do)
          (with-current-buffer "*Pearl-GTD: Do Session*"
            (pearl-gtd-do--session-skip)
            (should pearl-gtd-do-session-mode)
            (should (eq (lookup-key pearl-gtd-do-session-mode-map (kbd "s"))
                        #'pearl-gtd-do--session-skip))))
  :asserts (with-current-buffer "*Pearl-GTD: Do Session*"
             (goto-char (point-min))
             (should (search-forward "* Second task" nil t)))
  :teardown (pearl-gtd-test-cleanup-buffers '("*Pearl-GTD: Do Session*")))

(pearl-gtd-test-define-story pearl-gtd-do-test-session-context-filter
  "Context filter shows only matching actions."
  :setup (pearl-gtd-init-initialize)
  :files (("action.org" "* TODO Office task :office:\n:PROPERTIES:\n:ID: office-1\n:END:\n* TODO Home task :home:\n:PROPERTIES:\n:ID: home-1\n:END:\n"))
  :mock nil
  :body (pearl-gtd-do--start-session 'next "office" nil nil)
  :asserts (progn
             (should (get-buffer "*Pearl-GTD: Do Session*"))
             (with-current-buffer "*Pearl-GTD: Do Session*"
               (goto-char (point-min))
               (should (search-forward "* Office task" nil t))
               (should-not (search-forward "* Home task" nil t))))
  :teardown (pearl-gtd-test-cleanup-buffers '("*Pearl-GTD: Do Session*")))

(pearl-gtd-test-define-story pearl-gtd-do-test-session-empty-actions
  "Empty actions file shows session complete."
  :setup (pearl-gtd-init-initialize)
  :files (("action.org" ""))
  :mock (((symbol-function 'completing-read) (lambda (&rest _) ""))
         ((symbol-function 'read-string) (lambda (&rest _) "")))
  :body (pearl-gtd-do)
  :asserts (progn
             (should (get-buffer "*Pearl-GTD: Do Session*"))
             (with-current-buffer "*Pearl-GTD: Do Session*"
               (goto-char (point-min))
               (should (search-forward "Session Complete" nil t))))
  :teardown (pearl-gtd-test-cleanup-buffers '("*Pearl-GTD: Do Session*")))

(pearl-gtd-test-define-story pearl-gtd-do-test-session-delegated-view
  "Delegated session shows delegated TODO tasks."
  :setup (pearl-gtd-init-initialize)
  :files (("action.org" "* TODO Delegated task\n:PROPERTIES:\n:ID: del-1\n:DELEGATED: John\n:END:\n* TODO Own task\n:PROPERTIES:\n:ID: own-1\n:END:\n* DONE Delegated done\n:PROPERTIES:\n:ID: del-done-1\n:DELEGATED: Jane\n:END:\n"))
  :mock (((symbol-function 'completing-read) (lambda (prompt &rest _)
                                                (if (string-match-p "View type" prompt)
                                                    "delegated"
                                                  "")))
         ((symbol-function 'read-string) (lambda (&rest _) "")))
  :body (let ((current-prefix-arg '(4))) (pearl-gtd-do))
  :asserts (progn
             (should (get-buffer "*Pearl-GTD: Delegated Session*"))
             (with-current-buffer "*Pearl-GTD: Delegated Session*"
               (goto-char (point-min))
               (should (search-forward "* Delegated task" nil t))
               (should (search-forward "John" nil t))
               (should-not (search-forward "* Own task" nil t))
               (should-not (search-forward "* Delegated done" nil t))))
  :teardown (pearl-gtd-test-cleanup-buffers '("*Pearl-GTD: Delegated Session*")))

(pearl-gtd-test-define-story pearl-gtd-do-test-session-today-view
  "Today session shows tasks scheduled for today."
  :setup (pearl-gtd-init-initialize)
  :files (("action.org" (format "* TODO Today task\nSCHEDULED: <%s>\n:PROPERTIES:\n:ID: today-1\n:END:\n* TODO Later task\nSCHEDULED: <%s>\n:PROPERTIES:\n:ID: later-1\n:END:\n"
                                  (format-time-string "%F %a")
                                  (format-time-string "%F %a" (time-add (current-time) (* 24 3600))))))
  :mock (((symbol-function 'completing-read) (lambda (prompt &rest _)
                                                (if (string-match-p "View type" prompt)
                                                    "today"
                                                  "")))
         ((symbol-function 'read-string) (lambda (&rest _) "")))
  :body (let ((current-prefix-arg '(4))) (pearl-gtd-do))
  :asserts (progn
             (should (get-buffer "*Pearl-GTD: Today Session*"))
             (with-current-buffer "*Pearl-GTD: Today Session*"
               (goto-char (point-min))
               (should (search-forward "* Today task" nil t))
               (should-not (search-forward "* Later task" nil t))))
  :teardown (pearl-gtd-test-cleanup-buffers '("*Pearl-GTD: Today Session*")))

(pearl-gtd-test-define-story pearl-gtd-do-test-session-rename-action
  "Rename command updates task headline."
  :setup (pearl-gtd-init-initialize)
  :files (("action.org" "* TODO Old name\n:PROPERTIES:\n:ID: rename-1\n:END:\n"))
  :mock (((symbol-function 'completing-read) (lambda (&rest _) ""))
         ((symbol-function 'read-string) (lambda (&rest args)
                                           (if (string-match-p "New task name" (car args))
                                               "New name"
                                             ""))))
  :body (progn
          (pearl-gtd-do)
          (with-current-buffer "*Pearl-GTD: Do Session*"
            (pearl-gtd-do--session-rename)))
  :asserts (progn
             (should (pearl-gtd-test-file-contains-p
                      (expand-file-name "action.org" pearl-gtd-init-base-directory)
                      "* TODO New name"))
             (should-not (pearl-gtd-test-file-contains-p-bool
                          (expand-file-name "action.org" pearl-gtd-init-base-directory)
                          "* TODO Old name")))
  :teardown (pearl-gtd-test-cleanup-buffers '("*Pearl-GTD: Do Session*")))

(pearl-gtd-test-define-story pearl-gtd-do-test-session-change-conditions
  "Change conditions refreshes session with new filters."
  :setup (pearl-gtd-init-initialize)
  :files (("action.org" "* TODO Office task :office:\n:PROPERTIES:\n:ID: ctx-office-1\n:END:\n* TODO Home task :home:\n:PROPERTIES:\n:ID: ctx-home-1\n:END:\n"))
  :mock (((symbol-function 'completing-read) (lambda (&rest args)
                                                (cond ((string-match-p "Context" (car args)) "@home")
                                                      (t ""))))
         ((symbol-function 'read-string) (lambda (&rest _) "")))
  :body (progn
          (pearl-gtd-do)
          (with-current-buffer "*Pearl-GTD: Do Session*"
            (pearl-gtd-do--session-change-conditions)))
  :asserts (with-current-buffer "*Pearl-GTD: Do Session*"
             (goto-char (point-min))
             (should (search-forward "* Home task" nil t))
             (should-not (search-forward "* Office task" nil t)))
  :teardown (pearl-gtd-test-cleanup-buffers '("*Pearl-GTD: Do Session*")))

(pearl-gtd-test-define-story pearl-gtd-do-test-session-edit-notes
  "Press e to edit notes (body) for current action."
  :setup (pearl-gtd-init-initialize)
  :files (("action.org" "* TODO Task\n:PROPERTIES:\n:ID: edit-notes-do-1\n:END:\nOld note\n"))
  :mock (((symbol-function 'completing-read) (lambda (&rest _) ""))
         ((symbol-function 'read-string)
          (lambda (_prompt &optional _initial &rest _) "Updated note")))
  :body (progn
          (pearl-gtd-do)
          (with-current-buffer "*Pearl-GTD: Do Session*"
            (pearl-gtd-do--edit-notes)))
  :asserts (progn
             (should (pearl-gtd-test-file-contains-p
                      (expand-file-name "action.org" pearl-gtd-init-base-directory)
                      "Updated note"))
             (should-not (pearl-gtd-test-file-contains-p-bool
                          (expand-file-name "action.org" pearl-gtd-init-base-directory)
                          "Old note")))
  :teardown (pearl-gtd-test-cleanup-buffers '("*Pearl-GTD: Do Session*")))

(pearl-gtd-test-define-story pearl-gtd-do-test-session-shows-notes
  "Session displays notes from source file."
  :setup (pearl-gtd-init-initialize)
  :files (("action.org" "* TODO Task with notes\n:PROPERTIES:\n:ID: show-notes-1\n:END:\nImportant note content\n"))
  :mock (((symbol-function 'completing-read) (lambda (&rest _) ""))
         ((symbol-function 'read-string) (lambda (&rest _) "")))
  :body (pearl-gtd-do)
  :asserts (progn
             (should (get-buffer "*Pearl-GTD: Do Session*"))
             (with-current-buffer "*Pearl-GTD: Do Session*"
               (goto-char (point-min))
               (should (search-forward "Important note content" nil t))))
  :teardown (pearl-gtd-test-cleanup-buffers '("*Pearl-GTD: Do Session*")))

(pearl-gtd-test-define-story pearl-gtd-do-test-session-jump-to-source
  "Jump command opens source file at task."
  :setup (pearl-gtd-init-initialize)
  :files (("action.org" "* TODO Jump target\n:PROPERTIES:\n:ID: jump-1\n:END:\n"))
  :mock (((symbol-function 'completing-read) (lambda (&rest _) ""))
         ((symbol-function 'read-string) (lambda (&rest _) "")))
  :body (progn
          (pearl-gtd-do)
          (with-current-buffer "*Pearl-GTD: Do Session*"
            (pearl-gtd-do--session-jump)))
  :asserts (progn
             (let ((buf (get-file-buffer (expand-file-name "action.org" pearl-gtd-init-base-directory))))
               (should buf)
               (with-current-buffer buf
                 (should (looking-at-p "\\*+ TODO Jump target")))))
  :teardown (progn
              (pearl-gtd-test-cleanup-buffers '("*Pearl-GTD: Do Session*"))
              (let ((buf (get-file-buffer (expand-file-name "action.org" pearl-gtd-init-base-directory))))
                (when buf (kill-buffer buf)))))

(pearl-gtd-test-define-story pearl-gtd-do-test-session-backlog-count
  "Backlog count is displayed and decrements on done but not skip."
  :setup (pearl-gtd-init-initialize)
  :files (("action.org" "* TODO First task\n:PROPERTIES:\n:ID: first-1\n:PROJECT: Test\n:END:\n* TODO Second task\n:PROPERTIES:\n:ID: second-1\n:PROJECT: Test\n:END:\n* TODO Third task\n:PROPERTIES:\n:ID: third-1\n:PROJECT: Test\n:END:\n"))
  :mock (((symbol-function 'completing-read) (lambda (&rest _) ""))
         ((symbol-function 'read-string) (lambda (&rest _) "")))
  :body (progn
          (pearl-gtd-do)
          (with-current-buffer "*Pearl-GTD: Do Session*"
            ;; Initial backlog should show 3
            (goto-char (point-min))
            (should (search-forward "Backlog: 3 tasks remaining" nil t))
            ;; Skip first task
            (pearl-gtd-do--session-skip)
            ;; After skip, backlog should still show 3 (count unchanged)
            (goto-char (point-min))
            (should (search-forward "Backlog: 3 tasks remaining" nil t))
            ;; Complete second task
            (pearl-gtd-do--session-done)
            ;; After done, backlog should show 2
            (goto-char (point-min))
            (should (search-forward "Backlog: 2 tasks remaining" nil t))))
  :asserts (progn
             (should (get-buffer "*Pearl-GTD: Do Session*"))
             ;; Verify first task is still TODO (skipped)
             (should (pearl-gtd-test-file-contains-p
                      (expand-file-name "action.org" pearl-gtd-init-base-directory)
                      "* TODO First task"))
             ;; Verify second task is DONE
             (should (pearl-gtd-test-file-contains-p
                      (expand-file-name "action.org" pearl-gtd-init-base-directory)
                      "* DONE Second task")))
  :teardown (pearl-gtd-test-cleanup-buffers '("*Pearl-GTD: Do Session*")))

(pearl-gtd-test-define-story pearl-gtd-do-test-session-completes-no-project-task-deletes
  "Done command on no-project task should delete it."
  :setup (pearl-gtd-init-initialize)
  :files (("action.org" (format "* TODO No project task\nDEADLINE: <%s>\n:PROPERTIES:\n:ID: no-proj-1\n:END:\n* TODO Project task\n:PROPERTIES:\n:ID: proj-1\n:PROJECT: Test\n:END:\n"
                                (format-time-string "%F %a"
                                                    (time-add (current-time) (* 24 3600))))))
  :mock (((symbol-function 'completing-read) (lambda (&rest _) ""))
         ((symbol-function 'read-string) (lambda (&rest _) "")))
  :body (progn
          (pearl-gtd-do)
          (with-current-buffer "*Pearl-GTD: Do Session*"
            (pearl-gtd-do--session-done)))
  :asserts (progn
             ;; Verify no-project task is deleted
             (should-not (pearl-gtd-test-file-contains-p-bool
                          (expand-file-name "action.org" pearl-gtd-init-base-directory)
                          "* TODO No project task"))
             ;; Verify project task remains
             (should (pearl-gtd-test-file-contains-p-bool
                      (expand-file-name "action.org" pearl-gtd-init-base-directory)
                      "* TODO Project task"))
             ;; Session should advance to next task
             (with-current-buffer "*Pearl-GTD: Do Session*"
               (goto-char (point-min))
               (should (search-forward "* Project task" nil t))))
  :teardown (pearl-gtd-test-cleanup-buffers '("*Pearl-GTD: Do Session*")))

(pearl-gtd-test-define-story pearl-gtd-do-test-session-deletes-task-when-project-removed-after-start
  "Done deletes a task whose PROJECT is removed after the session starts.
This verifies deletion decision reads PROJECT from the source entry (not from cached session plist)."
  :setup (pearl-gtd-init-initialize)
  :files (("action.org"
           (format "* TODO Task losing project\nDEADLINE: <%s>\n:PROPERTIES:\n:ID: stale-project-1\n:PROJECT: Test\n:END:\n* TODO Remaining project task\n:PROPERTIES:\n:ID: remaining-project-1\n:PROJECT: Test\n:END:\n"
                   (format-time-string "%F %a"
                                       (time-add (current-time) (* 24 3600))))))
  :mock (((symbol-function 'completing-read) (lambda (&rest _) ""))
         ((symbol-function 'read-string) (lambda (&rest _) "")))
  :body (progn
          (pearl-gtd-do)
          ;; Remove PROJECT from the currently targeted entry after session start.
          (pearl-gtd-core-with-entry-at-id "stale-project-1" "action.org"
            (org-delete-property "PROJECT")
            (save-buffer))
          (with-current-buffer "*Pearl-GTD: Do Session*"
            (pearl-gtd-do--session-done)))
  :asserts (progn
             ;; Verify it is deleted because PROJECT is now missing in the source entry.
             (should-not
              (pearl-gtd-test-file-contains-p-bool
               (expand-file-name "action.org" pearl-gtd-init-base-directory)
               "Task losing project"))
             (with-current-buffer "*Pearl-GTD: Do Session*"
               (goto-char (point-min))
               (should (search-forward "* Remaining project task" nil t))))
  :teardown (pearl-gtd-test-cleanup-buffers '("*Pearl-GTD: Do Session*")))

;; Note: Navigation test removed - single-card push mode doesn't support manual next/previous.

(ert-deftest pearl-gtd-do-test-time-completions ()
  "Time input should offer preset options."
  (let ((time-checked nil))
    (cl-letf (((symbol-function 'completing-read)
               (lambda (prompt collection &rest _)
                 (when (string-match-p "[Tt]ime" prompt)
                   (setq time-checked t)
                   (should (member "15" collection))
                   (should (member "30" collection))
                   (should (member "60" collection))
                   (should (member "120" collection))
                   (should (member "240" collection)))
                 ""))
              ((symbol-function 'read-string) (lambda (&rest _) "")))
      (let ((result (pearl-gtd-do--prompt-conditions)))
        (should (listp result))
        (should time-checked)))))

(ert-deftest pearl-gtd-do-test-energy-completions ()
  "Energy input should offer preset levels."
  (let ((energy-checked nil))
    (cl-letf (((symbol-function 'completing-read)
               (lambda (prompt collection &rest _)
                 (when (string-match-p "[Ee]nergy" prompt)
                   (setq energy-checked t)
                   (should (member "high" collection))
                   (should (member "normal" collection))
                   (should (member "low" collection)))
                 ""))
              ((symbol-function 'read-string) (lambda (&rest _) "")))
      (let ((result (pearl-gtd-do--prompt-conditions)))
        (should (listp result))
        (should energy-checked)))))

(ert-deftest pearl-gtd-do-test-view-type-completions ()
  "View type selection should offer next/delegated/today options."
  (let ((current-prefix-arg '(4))
        (view-type-checked nil))
    (cl-letf (((symbol-function 'completing-read)
               (lambda (prompt collection &rest _)
                 (when (string-match-p "View type" prompt)
                   (setq view-type-checked t)
                   (should (member "next" collection))
                   (should (member "delegated" collection))
                   (should (member "today" collection)))
                 "next"))
              ((symbol-function 'read-string) (lambda (&rest _) ""))
              ((symbol-function 'pearl-gtd-do--start-session) (lambda (&rest _) (get-buffer-create "*Pearl-GTD: Do Session*"))))
      (pearl-gtd-do)
      (should (get-buffer "*Pearl-GTD: Do Session*"))
      (should view-type-checked)
      (kill-buffer "*Pearl-GTD: Do Session*"))))

(provide 'pearl-gtd-do-test)

;;; pearl-gtd-do-test.el ends here
