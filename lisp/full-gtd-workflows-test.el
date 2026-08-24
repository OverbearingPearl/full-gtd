;;; full-gtd-workflows-test.el --- User stories: End-to-end workflows  -*- lexical-binding: t; -*-

;;; Commentary:

;; Complete user workflows spanning multiple phases.

;;; Code:

(require 'ert)
(require 'full-gtd)
(require 'full-gtd-utils-test)

(full-gtd-test-define-story full-gtd-workflows-test-user-processes-full-gtd-pipeline
  "User captures, clarifies, organizes, and completes processing."
  :setup (full-gtd-init-initialize)
  :files nil
  :mock (((symbol-function 'read-string)
          (lambda (prompt &rest _)
            (cond
             ((string-match "Capture to inbox" prompt) "Buy birthday gift")
             (t ""))))
         ((symbol-function 'full-gtd-inbox--read-destination-key)
          (let ((calls 0))
            (lambda (_headline)
              (setq calls (1+ calls))
              ;; First item: clarify then action
              (if (= calls 1) ?c ?a))))
         ((symbol-function 'full-gtd-inbox--clarify-entry)
          (lambda (_headline &optional _current-notes) (cons "Buy gift for mom" "Check Amazon first")))
         ((symbol-function 'full-gtd-inbox--collect-action-attrs)
          (lambda (&optional _staging-buffer _default-context _default-project)
            '((context . "@errands") (schedule . "") (deadline . "")
              (delegate . "") (project . "")))))
  :body (progn
          (full-gtd-capture)
          (full-gtd-process-inbox))
  :asserts (progn
             (should (full-gtd-test-inbox-empty-p full-gtd-init-base-directory))
             (should (full-gtd-test-file-contains-p
                      (expand-file-name "action.org" full-gtd-init-base-directory)
                      "* TODO Buy gift for mom"))
             (should (full-gtd-test-file-contains-p
                      (expand-file-name "action.org" full-gtd-init-base-directory)
                      "Check Amazon first"))
             (should (full-gtd-test-file-contains-p
                      (expand-file-name "action.org" full-gtd-init-base-directory)
                      ":errands:"))
             ;; Verify ID is preserved after processing
             (should (full-gtd-test-file-contains-p
                      (expand-file-name "action.org" full-gtd-init-base-directory)
                      ":ID:")))
  :teardown nil)

(full-gtd-test-define-story full-gtd-workflows-test-user-interrupts-processing
  "User interrupts processing midway."
  :setup (full-gtd-init-initialize)
  :files (("inbox.org" "* Task to interrupt\n"))
  :mock (((symbol-function 'full-gtd-inbox--read-destination-key) (lambda (_headline) (signal 'quit nil)))
         ((symbol-function 'full-gtd-inbox--clarify-entry) (lambda (_current-notes) (cons nil nil))))
  :body (progn
         (condition-case err
             (full-gtd-process-inbox)
           (quit (setq full-gtd-test-caught-error err))))
  :asserts (progn
           (should (full-gtd-test-file-contains-p
                    (expand-file-name "inbox.org" full-gtd-init-base-directory)
                    "* Task to interrupt"))
           (should (eq (car full-gtd-test-caught-error) 'quit)))
  :teardown nil)

(full-gtd-test-define-story full-gtd-workflows-test-user-processes-mixed-destinations
  "User processes entries with mixed destinations."
  :setup (full-gtd-init-initialize)
  :files (("inbox.org" "* Action task\n* Reference task\n"))
  :mock (((symbol-function 'full-gtd-inbox--read-destination-key)
          (let ((calls 0))
            (lambda (_headline)
              (setq calls (1+ calls))
              (if (= calls 1) ?a ?r))))  ; First action, then reference
         ((symbol-function 'full-gtd-inbox--clarify-entry) (lambda (_headline) (cons nil nil)))
         ((symbol-function 'full-gtd-inbox--collect-action-attrs)
          (lambda (&optional _staging-buffer _default-context _default-project)
            '((context . "@office") (schedule . "") (deadline . "")
              (delegate . "") (project . "")))))
  :body (full-gtd-process-inbox)
  :asserts (progn
             (should (full-gtd-test-file-contains-p
                      (expand-file-name "action.org" full-gtd-init-base-directory)
                      "* TODO Action task"))
             (should (full-gtd-test-file-contains-p
                      (expand-file-name "reference.org" full-gtd-init-base-directory)
                      "* Reference task")))
  :teardown nil)

(full-gtd-test-define-story full-gtd-workflows-test-user-captures-and-processes-two-items
  "User captures two items then processes both."
  :setup (full-gtd-init-initialize)
  :files nil
  :mock (((symbol-function 'read-string)
          (let ((count 0))
            (lambda (prompt &rest _)
              (setq count (1+ count))
              (cond
               ((and (= count 1) (string-match "Capture to inbox" prompt)) "First capture")
               ((and (= count 2) (string-match "Capture to inbox" prompt)) "Second capture")
               (t "")))))
         ((symbol-function 'full-gtd-inbox--read-destination-key) (lambda (_headline) ?r))
         ((symbol-function 'full-gtd-inbox--clarify-entry) (lambda (_headline) (cons nil nil))))
  :body (progn
          (full-gtd-capture)
          (full-gtd-capture)
          (full-gtd-process-inbox))
  :asserts (progn
             (should (full-gtd-test-inbox-empty-p full-gtd-init-base-directory))
             (should (full-gtd-test-file-contains-p
                      (expand-file-name "reference.org" full-gtd-init-base-directory)
                      "* First capture"))
             (should (full-gtd-test-file-contains-p
                      (expand-file-name "reference.org" full-gtd-init-base-directory)
                      "* Second capture")))
  :teardown nil)

(full-gtd-test-define-story full-gtd-workflows-test-user-sees-id-preserved-after-processing
  "ID is preserved when task is moved from inbox to actions."
  :setup (full-gtd-init-initialize)
  :files nil
  :mock (((symbol-function 'read-string)
          (lambda (prompt &rest _)
            (cond
             ((string-match "Capture to inbox" prompt) "Test task")
             (t ""))))
         ((symbol-function 'full-gtd-inbox--read-destination-key) (lambda (_headline) ?a))
         ((symbol-function 'full-gtd-inbox--clarify-entry) (lambda (_headline) (cons nil nil)))
         ((symbol-function 'full-gtd-inbox--collect-action-attrs)
          (lambda (&optional _staging-buffer _default-context _default-project)
            '((context . "@office") (schedule . "") (deadline . "")
              (delegate . "") (project . "")))))
  :body (progn
          (full-gtd-capture)
          (full-gtd-process-inbox))
  :asserts (progn
             ;; Task moved to action.org
             (should (full-gtd-test-file-contains-p
                      (expand-file-name "action.org" full-gtd-init-base-directory)
                      "* TODO Test task"))
             ;; ID preserved in action.org
             (should (full-gtd-test-file-contains-p
                      (expand-file-name "action.org" full-gtd-init-base-directory)
                      ":ID:"))
             ;; Inbox is empty
             (should (full-gtd-test-inbox-empty-p full-gtd-init-base-directory)))
  :teardown nil)

(full-gtd-test-define-story full-gtd-workflows-test-user-sees-duplicate-titles-get-different-ids
  "Same title in different files gets different IDs."
  :setup (full-gtd-init-initialize)
  :files (("action.org" "* TODO Existing task\n:PROPERTIES:\n:ID: existing-id-1\n:END:\n"))
  :mock (((symbol-function 'read-string)
          (lambda (prompt &rest _)
            (cond
             ((string-match "Capture to inbox" prompt) "Buy milk")
             (t "")))))
  :body (full-gtd-capture)
  :asserts (progn
             ;; New entry in inbox
             (should (full-gtd-test-file-contains-p
                      (expand-file-name "inbox.org" full-gtd-init-base-directory)
                      "* Buy milk"))
             ;; New entry has different ID
             (with-temp-buffer
               (insert-file-contents (expand-file-name "inbox.org" full-gtd-init-base-directory))
               (goto-char (point-min))
               (should (search-forward ":ID:" nil t))
               (let ((_id-pos (point)))
                 (should-not (search-forward "existing-id-1" nil t)))))
  :teardown nil)

(full-gtd-test-define-story full-gtd-workflows-test-user-processes-duplicate-titles
  "User captures two tasks with same title, both processed correctly."
  :setup (full-gtd-init-initialize)
  :files nil
  :mock (((symbol-function 'read-string)
          (let ((count 0))
            (lambda (prompt &rest _)
              (setq count (1+ count))
              (cond
               ((and (= count 1) (string-match "Capture to inbox" prompt)) "Task")
               ((and (= count 2) (string-match "Capture to inbox" prompt)) "Task")
               (t "")))))
         ((symbol-function 'full-gtd-inbox--read-destination-key) (lambda (_headline) ?a))
         ((symbol-function 'full-gtd-inbox--clarify-entry) (lambda (_headline) (cons nil nil)))
         ((symbol-function 'full-gtd-inbox--collect-action-attrs)
          (lambda (&optional _staging-buffer _default-context _default-project)
            '((context . "@office") (schedule . "") (deadline . "")
              (delegate . "") (project . "")))))
  :body (progn
          (full-gtd-capture)
          (full-gtd-capture)
          (full-gtd-process-inbox))
  :asserts (progn
             (should (full-gtd-test-inbox-empty-p full-gtd-init-base-directory))
             ;; Should have two tasks in action.org
             (with-temp-buffer
               (insert-file-contents (expand-file-name "action.org" full-gtd-init-base-directory))
               (goto-char (point-min))
               (should (search-forward "* TODO Task" nil t))
               (should (search-forward "* TODO Task" nil t))))
  :teardown nil)

(full-gtd-test-define-story full-gtd-workflows-test-duplicate-ids-in-file
  "Malformed file with duplicate IDs should still allow jumping to first match."
  :setup (full-gtd-init-initialize)
  :files (("action.org" "* TODO Task A\n:PROPERTIES:\n:ID: dup-id\n:END:\n* TODO Task B\n:PROPERTIES:\n:ID: dup-id\n:END:\n"))
  :mock (((symbol-function 'completing-read) (lambda (&rest _) ""))
         ((symbol-function 'read-string) (lambda (&rest _) "")))
  :body (progn
          (full-gtd-do)
          (with-current-buffer "*Full-GTD: Do Session*"
            (goto-char (point-min))
            (search-forward "Task A")
            (beginning-of-line)
            (full-gtd-do--session-jump)))
  :asserts (progn
             (let ((buf (get-file-buffer (expand-file-name "action.org" full-gtd-init-base-directory))))
               (should buf)
               (with-current-buffer buf
                 (should (looking-at-p "\\*+ TODO Task")))))
  :teardown (progn
              (full-gtd-test-cleanup-buffers '("*Full-GTD: Do Session*"))
              (let ((buf (get-file-buffer (expand-file-name "action.org" full-gtd-init-base-directory))))
                (when buf (kill-buffer buf)))))

(full-gtd-test-define-story full-gtd-workflows-test-multi-project-action-inheritance
  "Action linked to multiple projects inherits horizons from all."
  :setup (full-gtd-init-initialize)
  :files (("action.org" "* TODO Shared action\n:PROPERTIES:\n:ID: shared-multi-1\n:PROJECT: Alpha; Beta\n:END:\n"))
  :mock (((symbol-function 'full-gtd-review--get-project-stats)
          (lambda (_proj)
            ;; Return stats that mark both projects as active (have TODOs)
            '("1" "1" "0" "" "" "" "" ""))))
  :body (full-gtd-review-weekly)
  :asserts (progn
             (should (get-buffer "*Full-GTD Weekly Review*"))
             ;; Should appear in project views - look in Active Projects section
             (with-current-buffer "*Full-GTD Weekly Review*"
               (goto-char (point-min))
               (let ((active-pos (search-forward "** Projects - Active" nil t)))
                 (should active-pos)
                 ;; Both projects should be listed
                 (goto-char active-pos)
                 (should (search-forward "Alpha" nil t))
                 (goto-char active-pos)
                 (should (search-forward "Beta" nil t)))))
  :teardown (full-gtd-test-cleanup-buffers '("*Full-GTD Weekly Review*")))

(full-gtd-test-define-story full-gtd-workflows-test-multiple-contexts-on-single-action
  "Action can have multiple context tags."
  :setup (full-gtd-init-initialize)
  :files (("action.org" "* TODO Multi context task :office:\n:PROPERTIES:\n:ID: multi-ctx-1\n:END:\n"))
  :mock nil
  :body (progn
          ;; Add second context manually
          (let ((file (expand-file-name "action.org" full-gtd-init-base-directory)))
            (with-current-buffer (find-file-noselect file)
              (goto-char (point-min))
              (re-search-forward "Multi context task")
              (org-set-tags '("office" "phone"))
              (save-buffer)
              (kill-buffer))))
          (full-gtd-do-view-all-actions)
  :asserts (progn
             (should (get-buffer "*Full-GTD: All Actions*"))
             (with-current-buffer "*Full-GTD: All Actions*"
               (should (search-forward "@office" nil t))
               (should (search-forward "@phone" nil t))))
  :teardown (full-gtd-test-cleanup-buffers '("*Full-GTD: All Actions*")))

(full-gtd-test-define-story full-gtd-workflows-test-extreme-whitespace-in-fields
  "Extreme whitespace in various fields should be handled."
  :setup (full-gtd-init-initialize)
  :files (("inbox.org" "*    Task with lots of spaces    \n:PROPERTIES:\n:ID: ws-extreme-1\n:END:\n"))
  :mock (((symbol-function 'full-gtd-inbox--read-destination-key) (lambda (_headline) ?a))
         ((symbol-function 'full-gtd-inbox--clarify-entry) (lambda (_headline) (cons nil nil)))
         ((symbol-function 'full-gtd-core-read-date) (lambda (&rest _) ""))
         ((symbol-function 'full-gtd-inbox--read-delegate) (lambda () "  Bob  "))
         ((symbol-function 'full-gtd-inbox--read-context) (lambda () "  @office  "))
         ((symbol-function 'full-gtd-inbox--read-project) (lambda () "  ProjA  ;  ProjB  ")))
  :body (full-gtd-process-inbox)
  :asserts (let ((content (with-temp-buffer
                            (insert-file-contents
                             (expand-file-name "action.org" full-gtd-init-base-directory))
                            (buffer-string))))
             ;; All values should be trimmed (allow for whitespace after colon)
             (should (string-match-p ":office:" content))
             (should (string-match-p ":DELEGATED:[ \t]*Bob" content))
             (should (string-match-p ":PROJECT:[ \t]*ProjA; ProjB" content))
             ;; Original whitespace should not be preserved
             (should-not (string-match-p ":  @office  :" content)))
  :teardown nil)

(full-gtd-test-define-story full-gtd-workflows-test-large-number-entries
  "System should handle 100+ entries without significant slowdown."
  :setup (full-gtd-init-initialize)
  :files (("inbox.org" (concat "* Task 1\n:PROPERTIES:\n:ID: perf-1\n:END:\n"
                               (mapconcat (lambda (i)
                                           (format "* Task %d\n:PROPERTIES:\n:ID: perf-%d\n:END:\n" i i))
                                         (number-sequence 2 100) ""))))
  :mock (((symbol-function 'full-gtd-inbox--read-destination-key) (lambda (_headline) ?t))
         ((symbol-function 'full-gtd-inbox--clarify-entry) (lambda (_headline) (cons nil nil))))
  :body (let ((start (float-time)))
          (full-gtd-process-inbox)
          (should (< (- (float-time) start) 30.0)))
  :asserts (should (full-gtd-test-inbox-empty-p full-gtd-init-base-directory))
  :teardown nil)

(provide 'full-gtd-workflows-test)

;;; full-gtd-workflows-test.el ends here
