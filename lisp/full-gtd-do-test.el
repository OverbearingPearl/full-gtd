;;; full-gtd-do-test.el --- User stories: Do/Work phase  -*- lexical-binding: t; -*-

;;; Commentary:

;; User stories for executing tasks via single-card sessions.

;;; Code:

(require 'ert)
(require 'full-gtd)
(require 'full-gtd-utils-test)

;;;; Unit tests for scoring

(ert-deftest full-gtd-do-test-score-deadline ()
  "Deadline proximity increases score."
  (let* ((tomorrow (format-time-string "%F" (time-add (current-time) (* 24 3600))))
         (action-a (list :headline "A" :deadline nil))
         (action-b (list :headline "B" :deadline (format "<%s>" tomorrow)))
         (score-a (full-gtd-do--score-action action-a))
         (score-b (full-gtd-do--score-action action-b)))
    (should (> score-b score-a))))

(ert-deftest full-gtd-do-test-score-horizons ()
  "Horizon alignment increases score."
  (let* ((base (list :headline "A"))
         (with-l6 (plist-put (copy-sequence base) :l6 "Purpose"))
         (with-l3 (plist-put (copy-sequence base) :l3 "Area")))
    (should (> (full-gtd-do--score-action with-l6) (full-gtd-do--score-action base)))
    (should (> (full-gtd-do--score-action with-l3) (full-gtd-do--score-action base)))))

(ert-deftest full-gtd-do-test-score-context-match ()
  "Context match bonus applies when filter matches."
  (let* ((action (list :headline "A" :context "@office"))
         (score-no-filter (full-gtd-do--score-action action nil))
         (score-match (full-gtd-do--score-action action "office"))
         (score-mismatch (full-gtd-do--score-action action "home")))
    (should (> score-match score-no-filter))
    (should (= score-mismatch score-no-filter))))

(ert-deftest full-gtd-do-test-score-delegated-penalty ()
  "Delegated actions receive -100 penalty."
  (let* ((base (list :headline "Task" :deadline nil))
         (delegated (plist-put (copy-sequence base) :delegated "Bob")))
    (let ((score-base (full-gtd-do--score-action base))
          (score-delegated (full-gtd-do--score-action delegated)))
      (should (= (- score-delegated score-base) -100)))))

(ert-deftest full-gtd-do-test-score-future-scheduled-penalty ()
  "Future scheduled actions receive -50 penalty."
  (let* ((next-week (format-time-string "<%F>" (time-add (current-time) (* 7 24 3600))))
         (base (list :headline "Task" :deadline nil :scheduled nil))
         (future (plist-put (copy-sequence base) :scheduled next-week)))
    (let ((score-base (full-gtd-do--score-action base))
          (score-future (full-gtd-do--score-action future)))
      (should (= (- score-future score-base) -50)))))

(ert-deftest full-gtd-do-test-sort-actions ()
  "Actions are sorted by score descending."
  (let* ((action-a (list :headline "A" :deadline nil))
         (tomorrow (format-time-string "%F" (time-add (current-time) (* 24 3600))))
         (action-b (list :headline "B" :deadline (format "<%s>" tomorrow)))
         (sorted (full-gtd-do--sort-actions (list action-a action-b) nil)))
    (should (string= (plist-get (car sorted) :headline) "B"))))

;;;; Story tests for session workflow

(full-gtd-test-define-story full-gtd-do-test-session-starts-with-highest-priority
  "Session presents the highest priority action first."
  :setup (full-gtd-init-initialize)
  :files (("action.org" "* TODO Low priority\n:PROPERTIES:\n:ID: low-1\n:END:\n* TODO High priority\nDEADLINE: <2026-01-20 Mon>\n:PROPERTIES:\n:ID: high-1\n:END:\n"))
  :mock (((symbol-function 'completing-read) (lambda (&rest _) ""))
         ((symbol-function 'read-string) (lambda (&rest _) "")))
  :body (full-gtd-do)
  :asserts (progn
             (should (get-buffer "*Full-GTD: Do Session*"))
             (with-current-buffer "*Full-GTD: Do Session*"
               (goto-char (point-min))
               (should (search-forward "* High priority" nil t))))
  :teardown (full-gtd-test-cleanup-buffers '("*Full-GTD: Do Session*")))

(full-gtd-test-define-story full-gtd-do-test-session-completes-action
  "Done command marks action complete and advances."
  :setup (full-gtd-init-initialize)
  :files (("action.org" "* TODO First task\n:PROPERTIES:\n:ID: first-1\n:PROJECT: Test\n:END:\n* TODO Second task\n:PROPERTIES:\n:ID: second-1\n:PROJECT: Test\n:END:\n"))
  :mock (((symbol-function 'completing-read) (lambda (&rest _) ""))
         ((symbol-function 'read-string) (lambda (&rest _) "")))
  :body (progn
          (full-gtd-do)
          (with-current-buffer "*Full-GTD: Do Session*"
            (full-gtd-do--session-done)))
  :asserts (progn
             (should (full-gtd-test-file-contains-p
                      (expand-file-name "action.org" full-gtd-init-base-directory)
                      "* DONE First task"))
             (with-current-buffer "*Full-GTD: Do Session*"
               (goto-char (point-min))
               (should (search-forward "* Second task" nil t))))
  :teardown (full-gtd-test-cleanup-buffers '("*Full-GTD: Do Session*")))

(full-gtd-test-define-story full-gtd-do-test-session-snoozes-action
  "Snooze command reschedules action to tomorrow and advances."
  :setup (full-gtd-init-initialize)
  :files (("action.org" "* TODO Snooze me\n:PROPERTIES:\n:ID: snooze-1\n:END:\n* TODO Next task\n:PROPERTIES:\n:ID: next-1\n:END:\n"))
  :mock (((symbol-function 'completing-read) (lambda (&rest _) ""))
         ((symbol-function 'read-string) (lambda (&rest _) "")))
  :body (progn
          (full-gtd-do)
          (with-current-buffer "*Full-GTD: Do Session*"
            (full-gtd-do--session-snooze)))
  :asserts (progn
             (let ((tomorrow (format-time-string "%F" (time-add (current-time) (* 24 3600)))))
               (should (full-gtd-test-file-contains-p
                        (expand-file-name "action.org" full-gtd-init-base-directory)
                        (format "SCHEDULED: <%s" tomorrow))))
             (with-current-buffer "*Full-GTD: Do Session*"
               (goto-char (point-min))
               (should (search-forward "* Next task" nil t))))
  :teardown (full-gtd-test-cleanup-buffers '("*Full-GTD: Do Session*")))

(full-gtd-test-define-story full-gtd-do-test-session-skip-keeps-mode-active
  "Skip command keeps minor mode active for subsequent keyboard shortcuts."
  :setup (full-gtd-init-initialize)
  :files (("action.org" "* TODO First task\n:PROPERTIES:\n:ID: first-1\n:END:\n* TODO Second task\n:PROPERTIES:\n:ID: second-1\n:END:\n"))
  :mock (((symbol-function 'completing-read) (lambda (&rest _) ""))
         ((symbol-function 'read-string) (lambda (&rest _) "")))
  :body (progn
          (full-gtd-do)
          (with-current-buffer "*Full-GTD: Do Session*"
            (full-gtd-do--session-skip)
            (should full-gtd-do-session-mode)
            (should (eq (lookup-key full-gtd-do-session-mode-map (kbd "s"))
                        #'full-gtd-do--session-skip))))
  :asserts (with-current-buffer "*Full-GTD: Do Session*"
             (goto-char (point-min))
             (should (search-forward "* Second task" nil t)))
  :teardown (full-gtd-test-cleanup-buffers '("*Full-GTD: Do Session*")))

(full-gtd-test-define-story full-gtd-do-test-session-context-filter
  "Context filter shows only matching actions."
  :setup (full-gtd-init-initialize)
  :files (("action.org" "* TODO Office task :office:\n:PROPERTIES:\n:ID: office-1\n:END:\n* TODO Home task :home:\n:PROPERTIES:\n:ID: home-1\n:END:\n"))
  :mock nil
  :body (full-gtd-do--start-session 'next "office" nil nil)
  :asserts (progn
             (should (get-buffer "*Full-GTD: Do Session*"))
             (with-current-buffer "*Full-GTD: Do Session*"
               (goto-char (point-min))
               (should (search-forward "* Office task" nil t))
               (should-not (search-forward "* Home task" nil t))))
  :teardown (full-gtd-test-cleanup-buffers '("*Full-GTD: Do Session*")))

(full-gtd-test-define-story full-gtd-do-test-session-empty-actions
  "Empty actions file shows session complete."
  :setup (full-gtd-init-initialize)
  :files (("action.org" ""))
  :mock (((symbol-function 'completing-read) (lambda (&rest _) ""))
         ((symbol-function 'read-string) (lambda (&rest _) "")))
  :body (full-gtd-do)
  :asserts (progn
             (should (get-buffer "*Full-GTD: Do Session*"))
             (with-current-buffer "*Full-GTD: Do Session*"
               (goto-char (point-min))
               (should (search-forward "Session Complete" nil t))))
  :teardown (full-gtd-test-cleanup-buffers '("*Full-GTD: Do Session*")))

(full-gtd-test-define-story full-gtd-do-test-session-delegated-view
  "Delegated session shows delegated TODO tasks."
  :setup (full-gtd-init-initialize)
  :files (("action.org" "* TODO Delegated task\n:PROPERTIES:\n:ID: del-1\n:DELEGATED: John\n:END:\n* TODO Own task\n:PROPERTIES:\n:ID: own-1\n:END:\n* DONE Delegated done\n:PROPERTIES:\n:ID: del-done-1\n:DELEGATED: Jane\n:END:\n"))
  :mock (((symbol-function 'completing-read) (lambda (prompt &rest _)
                                                (if (string-match-p "View type" prompt)
                                                    "delegated"
                                                  "")))
         ((symbol-function 'read-string) (lambda (&rest _) "")))
  :body (let ((current-prefix-arg '(4))) (full-gtd-do))
  :asserts (progn
             (should (get-buffer "*Full-GTD: Delegated Session*"))
             (with-current-buffer "*Full-GTD: Delegated Session*"
               (goto-char (point-min))
               (should (search-forward "* Delegated task" nil t))
               (should (search-forward "John" nil t))
               (should-not (search-forward "* Own task" nil t))
               (should-not (search-forward "* Delegated done" nil t))))
  :teardown (full-gtd-test-cleanup-buffers '("*Full-GTD: Delegated Session*")))

(full-gtd-test-define-story full-gtd-do-test-session-today-view
  "Today session shows tasks scheduled for today."
  :setup (full-gtd-init-initialize)
  :files (("action.org" (format "* TODO Today task\nSCHEDULED: <%s>\n:PROPERTIES:\n:ID: today-1\n:END:\n* TODO Later task\nSCHEDULED: <%s>\n:PROPERTIES:\n:ID: later-1\n:END:\n"
                                  (format-time-string "%F %a")
                                  (format-time-string "%F %a" (time-add (current-time) (* 24 3600))))))
  :mock (((symbol-function 'completing-read) (lambda (prompt &rest _)
                                                (if (string-match-p "View type" prompt)
                                                    "today"
                                                  "")))
         ((symbol-function 'read-string) (lambda (&rest _) "")))
  :body (let ((current-prefix-arg '(4))) (full-gtd-do))
  :asserts (progn
             (should (get-buffer "*Full-GTD: Today Session*"))
             (with-current-buffer "*Full-GTD: Today Session*"
               (goto-char (point-min))
               (should (search-forward "* Today task" nil t))
               (should-not (search-forward "* Later task" nil t))))
  :teardown (full-gtd-test-cleanup-buffers '("*Full-GTD: Today Session*")))

(full-gtd-test-define-story full-gtd-do-test-session-rename-action
  "Rename command updates task headline."
  :setup (full-gtd-init-initialize)
  :files (("action.org" "* TODO Old name\n:PROPERTIES:\n:ID: rename-1\n:END:\n"))
  :mock (((symbol-function 'completing-read) (lambda (&rest _) ""))
         ((symbol-function 'read-string) (lambda (&rest args)
                                           (if (string-match-p "New task name" (car args))
                                               "New name"
                                             ""))))
  :body (progn
          (full-gtd-do)
          (with-current-buffer "*Full-GTD: Do Session*"
            (full-gtd-do--session-rename)))
  :asserts (progn
             (should (full-gtd-test-file-contains-p
                      (expand-file-name "action.org" full-gtd-init-base-directory)
                      "* TODO New name"))
             (should-not (full-gtd-test-file-contains-p-bool
                          (expand-file-name "action.org" full-gtd-init-base-directory)
                          "* TODO Old name")))
  :teardown (full-gtd-test-cleanup-buffers '("*Full-GTD: Do Session*")))

(full-gtd-test-define-story full-gtd-do-test-session-change-conditions
  "Change conditions refreshes session with new filters."
  :setup (full-gtd-init-initialize)
  :files (("action.org" "* TODO Office task :office:\n:PROPERTIES:\n:ID: ctx-office-1\n:END:\n* TODO Home task :home:\n:PROPERTIES:\n:ID: ctx-home-1\n:END:\n"))
  :mock (((symbol-function 'completing-read) (lambda (&rest args)
                                                (cond ((string-match-p "Context" (car args)) "@home")
                                                      (t ""))))
         ((symbol-function 'read-string) (lambda (&rest _) "")))
  :body (progn
          (full-gtd-do)
          (with-current-buffer "*Full-GTD: Do Session*"
            (full-gtd-do--session-change-conditions)))
  :asserts (with-current-buffer "*Full-GTD: Do Session*"
             (goto-char (point-min))
             (should (search-forward "* Home task" nil t))
             (should-not (search-forward "* Office task" nil t)))
  :teardown (full-gtd-test-cleanup-buffers '("*Full-GTD: Do Session*")))

(full-gtd-test-define-story full-gtd-do-test-session-edit-notes
  "Press e to edit notes (body) for current action."
  :setup (full-gtd-init-initialize)
  :files (("action.org" "* TODO Task\n:PROPERTIES:\n:ID: edit-notes-do-1\n:END:\nOld note\n"))
  :mock (((symbol-function 'completing-read) (lambda (&rest _) ""))
         ((symbol-function 'read-string)
          (lambda (_prompt &optional _initial &rest _) "Updated note")))
  :body (progn
          (full-gtd-do)
          (with-current-buffer "*Full-GTD: Do Session*"
            (full-gtd-do--edit-notes)))
  :asserts (progn
             (should (full-gtd-test-file-contains-p
                      (expand-file-name "action.org" full-gtd-init-base-directory)
                      "Updated note"))
             (should-not (full-gtd-test-file-contains-p-bool
                          (expand-file-name "action.org" full-gtd-init-base-directory)
                          "Old note")))
  :teardown (full-gtd-test-cleanup-buffers '("*Full-GTD: Do Session*")))

(full-gtd-test-define-story full-gtd-do-test-session-shows-notes
  "Session displays notes from source file."
  :setup (full-gtd-init-initialize)
  :files (("action.org" "* TODO Task with notes\n:PROPERTIES:\n:ID: show-notes-1\n:END:\nImportant note content\n"))
  :mock (((symbol-function 'completing-read) (lambda (&rest _) ""))
         ((symbol-function 'read-string) (lambda (&rest _) "")))
  :body (full-gtd-do)
  :asserts (progn
             (should (get-buffer "*Full-GTD: Do Session*"))
             (with-current-buffer "*Full-GTD: Do Session*"
               (goto-char (point-min))
               (should (search-forward "Important note content" nil t))))
  :teardown (full-gtd-test-cleanup-buffers '("*Full-GTD: Do Session*")))

(full-gtd-test-define-story full-gtd-do-test-session-jump-to-source
  "Jump command opens source file at task."
  :setup (full-gtd-init-initialize)
  :files (("action.org" "* TODO Jump target\n:PROPERTIES:\n:ID: jump-1\n:END:\n"))
  :mock (((symbol-function 'completing-read) (lambda (&rest _) ""))
         ((symbol-function 'read-string) (lambda (&rest _) "")))
  :body (progn
          (full-gtd-do)
          (with-current-buffer "*Full-GTD: Do Session*"
            (full-gtd-do--session-jump)))
  :asserts (progn
             (let ((buf (get-file-buffer (expand-file-name "action.org" full-gtd-init-base-directory))))
               (should buf)
               (with-current-buffer buf
                 (should (looking-at-p "\\*+ TODO Jump target")))))
  :teardown (progn
              (full-gtd-test-cleanup-buffers '("*Full-GTD: Do Session*"))
              (let ((buf (get-file-buffer (expand-file-name "action.org" full-gtd-init-base-directory))))
                (when buf (kill-buffer buf)))))

(full-gtd-test-define-story full-gtd-do-test-session-backlog-count
  "Backlog count is displayed and decrements on done but not skip."
  :setup (full-gtd-init-initialize)
  :files (("action.org" "* TODO First task\n:PROPERTIES:\n:ID: first-1\n:PROJECT: Test\n:END:\n* TODO Second task\n:PROPERTIES:\n:ID: second-1\n:PROJECT: Test\n:END:\n* TODO Third task\n:PROPERTIES:\n:ID: third-1\n:PROJECT: Test\n:END:\n"))
  :mock (((symbol-function 'completing-read) (lambda (&rest _) ""))
         ((symbol-function 'read-string) (lambda (&rest _) "")))
  :body (progn
          (full-gtd-do)
          (with-current-buffer "*Full-GTD: Do Session*"
            ;; Initial backlog should show 3
            (goto-char (point-min))
            (should (search-forward "Backlog: 3 tasks remaining" nil t))
            ;; Skip first task
            (full-gtd-do--session-skip)
            ;; After skip, backlog should still show 3 (count unchanged)
            (goto-char (point-min))
            (should (search-forward "Backlog: 3 tasks remaining" nil t))
            ;; Complete second task
            (full-gtd-do--session-done)
            ;; After done, backlog should show 2
            (goto-char (point-min))
            (should (search-forward "Backlog: 2 tasks remaining" nil t))))
  :asserts (progn
             (should (get-buffer "*Full-GTD: Do Session*"))
             ;; Verify first task is still TODO (skipped)
             (should (full-gtd-test-file-contains-p
                      (expand-file-name "action.org" full-gtd-init-base-directory)
                      "* TODO First task"))
             ;; Verify second task is DONE
             (should (full-gtd-test-file-contains-p
                      (expand-file-name "action.org" full-gtd-init-base-directory)
                      "* DONE Second task")))
  :teardown (full-gtd-test-cleanup-buffers '("*Full-GTD: Do Session*")))

(full-gtd-test-define-story full-gtd-do-test-session-completes-no-project-task-deletes
  "Done command on no-project task should delete it."
  :setup (full-gtd-init-initialize)
  :files (("action.org" (format "* TODO No project task\nDEADLINE: <%s>\n:PROPERTIES:\n:ID: no-proj-1\n:END:\n* TODO Project task\n:PROPERTIES:\n:ID: proj-1\n:PROJECT: Test\n:END:\n"
                                (format-time-string "%F %a"
                                                    (time-add (current-time) (* 24 3600))))))
  :mock (((symbol-function 'completing-read) (lambda (&rest _) ""))
         ((symbol-function 'read-string) (lambda (&rest _) "")))
  :body (progn
          (full-gtd-do)
          (with-current-buffer "*Full-GTD: Do Session*"
            (full-gtd-do--session-done)))
  :asserts (progn
             ;; Verify no-project task is deleted
             (should-not (full-gtd-test-file-contains-p-bool
                          (expand-file-name "action.org" full-gtd-init-base-directory)
                          "* TODO No project task"))
             ;; Verify project task remains
             (should (full-gtd-test-file-contains-p-bool
                      (expand-file-name "action.org" full-gtd-init-base-directory)
                      "* TODO Project task"))
             ;; Session should advance to next task
             (with-current-buffer "*Full-GTD: Do Session*"
               (goto-char (point-min))
               (should (search-forward "* Project task" nil t))))
  :teardown (full-gtd-test-cleanup-buffers '("*Full-GTD: Do Session*")))

(full-gtd-test-define-story full-gtd-do-test-session-deletes-task-when-project-removed-after-start
  "Done deletes a task whose PROJECT is removed after the session starts.
This verifies deletion decision reads PROJECT from the source entry (not from cached session plist)."
  :setup (full-gtd-init-initialize)
  :files (("action.org"
           (format "* TODO Task losing project\nDEADLINE: <%s>\n:PROPERTIES:\n:ID: stale-project-1\n:PROJECT: Test\n:END:\n* TODO Remaining project task\n:PROPERTIES:\n:ID: remaining-project-1\n:PROJECT: Test\n:END:\n"
                   (format-time-string "%F %a"
                                       (time-add (current-time) (* 24 3600))))))
  :mock (((symbol-function 'completing-read) (lambda (&rest _) ""))
         ((symbol-function 'read-string) (lambda (&rest _) "")))
  :body (progn
          (full-gtd-do)
          ;; Remove PROJECT from the currently targeted entry after session start.
          (full-gtd-core-with-entry-at-id "stale-project-1" "action.org"
            (org-delete-property "PROJECT")
            (save-buffer))
          (with-current-buffer "*Full-GTD: Do Session*"
            (full-gtd-do--session-done)))
  :asserts (progn
             ;; Verify it is deleted because PROJECT is now missing in the source entry.
             (should-not
              (full-gtd-test-file-contains-p-bool
               (expand-file-name "action.org" full-gtd-init-base-directory)
               "Task losing project"))
             (with-current-buffer "*Full-GTD: Do Session*"
               (goto-char (point-min))
               (should (search-forward "* Remaining project task" nil t))))
  :teardown (full-gtd-test-cleanup-buffers '("*Full-GTD: Do Session*")))

;; Note: Navigation test removed - single-card push mode doesn't support manual next/previous.

(ert-deftest full-gtd-do-test-time-completions ()
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
      (let ((result (full-gtd-do--prompt-conditions)))
        (should (listp result))
        (should time-checked)))))

(ert-deftest full-gtd-do-test-energy-completions ()
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
      (let ((result (full-gtd-do--prompt-conditions)))
        (should (listp result))
        (should energy-checked)))))

(ert-deftest full-gtd-do-test-view-type-completions ()
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
              ((symbol-function 'full-gtd-do--start-session) (lambda (&rest _) (get-buffer-create "*Full-GTD: Do Session*"))))
      (full-gtd-do)
      (should (get-buffer "*Full-GTD: Do Session*"))
      (should view-type-checked)
      (kill-buffer "*Full-GTD: Do Session*"))))

;;;; Additional branch coverage

(ert-deftest full-gtd-do-test-days-until-nil-and-invalid ()
  "Nil or unparseable dates return nil instead of crashing."
  (should (null (full-gtd-do--days-until nil)))
  (should (null (full-gtd-do--days-until "not-a-date"))))

(ert-deftest full-gtd-do-test-format-date-relative-labels ()
  "Format-date annotates overdue and near dates; distant or bad input passes through."
  (let ((overdue (format-time-string "<%F>"
                                     (time-subtract (current-time) (* 3 24 3600))))
        (later-today (format-time-string "<%F %H:%M>"
                                         (time-add (current-time) 1800)))
        (soon (format-time-string "<%F>"
                                  (time-add (current-time) (* 5 24 3600))))
        (far (format-time-string "<%F>"
                                 (time-add (current-time) (* 30 24 3600)))))
    (should (string-match-p "overdue" (full-gtd-do--format-date overdue)))
    (should (string-match-p "in [0-9]+ days"
                            (full-gtd-do--format-date later-today)))
    (should (string-match-p "in [0-9]+ days" (full-gtd-do--format-date soon)))
    (should (string= far (full-gtd-do--format-date far)))
    (should (string= "bogus" (full-gtd-do--format-date "bogus")))))

(ert-deftest full-gtd-do-test-score-deadline-buckets ()
  "Deadline scoring maps each distance onto its configured weight."
  (let ((half-day (format-time-string "<%F>" (time-add (current-time) 43200)))
        (two-days (format-time-string "<%F>"
                                      (time-add (current-time) (* 2 24 3600))))
        (five-days (format-time-string "<%F>"
                                       (time-add (current-time) (* 5 24 3600))))
        (overdue (format-time-string "<%F>"
                                     (time-subtract (current-time) (* 2 24 3600)))))
    (should (= (full-gtd-do--score-action (list :deadline overdue)) 100))
    (should (= (full-gtd-do--score-action (list :deadline half-day)) 50))
    (should (= (full-gtd-do--score-action (list :deadline two-days)) 30))
    (should (= (full-gtd-do--score-action (list :deadline five-days)) 15))))

(ert-deftest full-gtd-do-test-score-horizons-and-empty-strings ()
  "Empty-string fields score nothing; set horizons and project add weight."
  (should (= (full-gtd-do--score-action
              (list :l3 "" :l4 "" :l5 "" :l6 "" :project "" :delegated ""))
             0))
  (should (= (full-gtd-do--score-action
              (list :l3 "A" :l4 "B" :l5 "C" :l6 "D" :project "P"))
             55)))

(ert-deftest full-gtd-do-test-score-scheduled-today-and-past ()
  "Only today's schedule earns the bonus; past schedules earn no penalty."
  (let ((today (format-time-string "<%F>" (current-time)))
        (past (format-time-string "<%F>"
                                  (time-subtract (current-time) (* 3 24 3600)))))
    (should (= (full-gtd-do--score-action (list :scheduled today)) 20))
    (should (= (full-gtd-do--score-action (list :scheduled past)) 0))))

(ert-deftest full-gtd-do-test-score-context-multi-value ()
  "Context bonus applies when the filter matches any listed context."
  (let ((action (list :context "@office,@home")))
    (should (= (full-gtd-do--score-action action "home") 10))
    (should (= (full-gtd-do--score-action action "car") 0))))

(full-gtd-test-define-story full-gtd-do-test-session-help-and-quit
  "Help prints the command hint; quit closes the session window."
  :setup (full-gtd-init-initialize)
  :files (("action.org" "* TODO Task\n:PROPERTIES:\n:ID: hq-1\n:END:\n"))
  :mock (((symbol-function 'completing-read) (lambda (&rest _) ""))
         ((symbol-function 'read-string) (lambda (&rest _) "")))
  :body (progn
          (full-gtd-do)
          (with-current-buffer "*Full-GTD: Do Session*"
            (full-gtd-do--session-help)
            (should full-gtd-do-session-mode)
            (full-gtd-do--session-quit)))
  :asserts (should (get-buffer "*Full-GTD: Do Session*"))
  :teardown (full-gtd-test-cleanup-buffers '("*Full-GTD: Do Session*")))

(full-gtd-test-define-story full-gtd-do-test-session-done-continues-same-conditions
  "Done on the last action re-collects with the same conditions when confirmed."
  :setup (full-gtd-init-initialize)
  :files (("action.org" "* TODO Only task\n:PROPERTIES:\n:ID: cont-1\n:PROJECT: Test\n:END:\n"))
  :mock (((symbol-function 'completing-read) (lambda (&rest _) ""))
         ((symbol-function 'read-string) (lambda (&rest _) ""))
         ((symbol-function 'read-char-choice) (lambda (&rest _) ?y)))
  :body (progn
          (full-gtd-do)
          (with-current-buffer "*Full-GTD: Do Session*"
            (full-gtd-do--session-done)
            (goto-char (point-min))
            (should (search-forward "Session Complete" nil t))))
  :asserts (should (full-gtd-test-file-contains-p
                    (expand-file-name "action.org" full-gtd-init-base-directory)
                    "* DONE Only task"))
  :teardown (full-gtd-test-cleanup-buffers '("*Full-GTD: Do Session*")))

(full-gtd-test-define-story full-gtd-do-test-session-done-decline-changes-conditions
  "Declining the continuation prompt opens the change-conditions prompts."
  :setup (full-gtd-init-initialize)
  :files (("action.org" "* TODO Only task\n:PROPERTIES:\n:ID: cont-2\n:PROJECT: Test\n:END:\n"))
  :mock (((symbol-function 'completing-read) (lambda (&rest _) ""))
         ((symbol-function 'read-string) (lambda (&rest _) ""))
         ((symbol-function 'read-char-choice) (lambda (&rest _) ?n))
         ((symbol-function 'full-gtd-do--prompt-conditions)
          (lambda () (list "nomatch" nil nil))))
  :body (progn
          (full-gtd-do)
          (with-current-buffer "*Full-GTD: Do Session*"
            (full-gtd-do--session-done)
            (goto-char (point-min))
            (should (search-forward "nomatch" nil t))))
  :asserts (should (full-gtd-test-file-contains-p
                    (expand-file-name "action.org" full-gtd-init-base-directory)
                    "* DONE Only task"))
  :teardown (full-gtd-test-cleanup-buffers '("*Full-GTD: Do Session*")))

(full-gtd-test-define-story full-gtd-do-test-session-skip-continues-same-conditions
  "Skip on the last action re-collects the still-pending task when confirmed."
  :setup (full-gtd-init-initialize)
  :files (("action.org" "* TODO Recurring\n:PROPERTIES:\n:ID: cont-3\n:END:\n"))
  :mock (((symbol-function 'completing-read) (lambda (&rest _) ""))
         ((symbol-function 'read-string) (lambda (&rest _) ""))
         ((symbol-function 'read-char-choice) (lambda (&rest _) ?y)))
  :body (progn
          (full-gtd-do)
          (with-current-buffer "*Full-GTD: Do Session*"
            (full-gtd-do--session-skip)
            (goto-char (point-min))
            (should (search-forward "* Recurring" nil t))))
  :asserts (should (full-gtd-test-file-contains-p
                    (expand-file-name "action.org" full-gtd-init-base-directory)
                    "* TODO Recurring"))
  :teardown (full-gtd-test-cleanup-buffers '("*Full-GTD: Do Session*")))

(full-gtd-test-define-story full-gtd-do-test-session-snooze-decline-changes-conditions
  "Declining after a snooze re-filters with the newly entered conditions."
  :setup (full-gtd-init-initialize)
  :files (("action.org" "* TODO Later\n:PROPERTIES:\n:ID: cont-4\n:END:\n"))
  :mock (((symbol-function 'completing-read) (lambda (&rest _) ""))
         ((symbol-function 'read-string) (lambda (&rest _) ""))
         ((symbol-function 'read-char-choice) (lambda (&rest _) ?n))
         ((symbol-function 'full-gtd-do--prompt-conditions)
          (lambda () (list "nomatch" nil nil))))
  :body (progn
          (full-gtd-do)
          (with-current-buffer "*Full-GTD: Do Session*"
            (full-gtd-do--session-snooze)
            (goto-char (point-min))
            (should (search-forward "Session Complete" nil t))))
  :asserts (should (full-gtd-test-file-contains-p
                    (expand-file-name "action.org" full-gtd-init-base-directory)
                    (format "SCHEDULED: <%s"
                            (format-time-string "%F"
                                                (time-add (current-time) (* 24 3600))))))
  :teardown (full-gtd-test-cleanup-buffers '("*Full-GTD: Do Session*")))

(full-gtd-test-define-story full-gtd-do-test-session-renders-full-details
  "Card renders every populated field, notes, and the singular backlog form."
  :setup (full-gtd-init-initialize)
  :files (("action.org"
           (concat "* TODO Detailed task :office:\n"
                   (format "DEADLINE: <%s> SCHEDULED: <%s>\n"
                           (format-time-string "%F %a" (time-add (current-time) (* 2 24 3600)))
                           (format-time-string "%F %a" (time-add (current-time) (* 5 24 3600))))
                   ":PROPERTIES:\n:ID: full-card-1\n:PROJECT: DetailProj\n:DELEGATED: Alice\n:CREATED: 2026-01-01\n"
                   ":L3_AREA: Work\n:L4_GOAL: Goal\n:L5_VISION: Vision\n:L6_PURPOSE: Purpose\n:END:\n"
                   "\nBody note line\n")))
  :mock (((symbol-function 'completing-read) (lambda (&rest _) ""))
         ((symbol-function 'read-string) (lambda (&rest _) "")))
  :body (progn
          (full-gtd-do)
          (with-current-buffer "*Full-GTD: Do Session*"
            (goto-char (point-min))
            (should (search-forward "* Detailed task" nil t))
            (should (search-forward "Backlog: 1 task remaining" nil t))
            (should (search-forward "| Project" nil t))
            (should (search-forward "| Context" nil t))
            (should (search-forward "| Deadline" nil t))
            (should (search-forward "| Scheduled" nil t))
            (should (search-forward "| Delegated" nil t))
            (should (search-forward "| Created" nil t))
            (should (search-forward "L6 Purpose" nil t))
            (should (search-forward "L5 Vision" nil t))
            (should (search-forward "L4 Goal" nil t))
            (should (search-forward "L3 Area" nil t))
            (should (search-forward "Body note line" nil t))))
  :asserts (should (full-gtd-test-file-contains-p
                    (expand-file-name "action.org" full-gtd-init-base-directory)
                    ":L6_PURPOSE: Purpose"))
  :teardown (full-gtd-test-cleanup-buffers '("*Full-GTD: Do Session*")))

(provide 'full-gtd-do-test)

;;; full-gtd-do-test.el ends here
