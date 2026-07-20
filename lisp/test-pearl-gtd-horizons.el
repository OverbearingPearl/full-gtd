;;; test-pearl-gtd-horizons.el --- User stories: 6 Horizons  -*- lexical-binding: t; -*-

;;; Commentary:

;; User stories for 6 Horizons of Focus.

;;; Code:

(require 'ert)
(require 'pearl-gtd)
(require 'test-pearl-gtd)

(test-pearl-gtd-define-story test-pearl-gtd-horizons-weekly-review-shows-columns
  "Weekly review shows horizon columns for project and no-project tables."
  :setup (pearl-gtd-init-initialize)
  :files (("actions.org" "* TODO No project task\n:PROPERTIES:\n:ID: np-1\n:END:\n* TODO Project task\n:PROPERTIES:\n:ID: p-1\n:PROJECT: TestProject\n:END:\n"))
  :mock nil
  :body (pearl-gtd-review-weekly)
  :asserts (progn
             (should (get-buffer "*Pearl-GTD Weekly Review*"))
             (with-current-buffer "*Pearl-GTD Weekly Review*"
               ;; Verify Project table has Horizon columns
               (goto-char (point-min))
               (search-forward "** Projects - Active")
               (forward-line 1) ; Skip to table header
               (beginning-of-line)
               (should (search-forward-regexp "|\\s-*Project\\s-*|\\s-*Total\\s-*|\\s-*Todo\\s-*|\\s-*Done\\s-*|\\s-*Next Deadline\\s-*|\\s-*L3_AREA\\s-*|\\s-*L4_GOAL\\s-*|\\s-*L5_VISION\\s-*|\\s-*L6_PURPOSE\\s-*|" nil t))

               ;; Verify No Project table has L3 column only
               (goto-char (point-min))
               (search-forward "** actions.org - No Project")
               (forward-line 1) ; Skip to table header
               (beginning-of-line)
               (should (search-forward-regexp "|\\s-*Headline\\s-*|\\s-*Status\\s-*|\\s-*Scheduled\\s-*|\\s-*Deadline\\s-*|\\s-*Context\\s-*|\\s-*Delegated\\s-*|\\s-*L3_AREA\\s-*|" nil t))
               (should-not (search-forward-regexp "|\\s-*L4\\s-*|" (line-end-position) t))
               (should-not (search-forward-regexp "|\\s-*L5\\s-*|" (line-end-position) t))
               (should-not (search-forward-regexp "|\\s-*L6\\s-*|" (line-end-position) t))))
  :teardown (kill-buffer "*Pearl-GTD Weekly Review*"))

(test-pearl-gtd-define-story test-pearl-gtd-horizons-set-l3-for-no-project-action
  "Set L3 horizon for no-project action in weekly review."
  :setup (pearl-gtd-init-initialize)
  :files (("actions.org" "* TODO No project task\n:PROPERTIES:\n:ID: np-1\n:END:\n"))
  :mock (((symbol-function 'read-string) (lambda (&rest _) "Personal")))
  :body (progn
          (pearl-gtd-review-weekly)
          (with-current-buffer "*Pearl-GTD Weekly Review*"
            (goto-char (point-min))
            (search-forward "** actions.org - No Project")
            (search-forward "No project task")
            (beginning-of-line)
            (pearl-gtd-horizons--edit-l3-at-point)))
  :asserts (let* ((file (expand-file-name "actions.org" pearl-gtd-init-base-directory))
                  (pattern ":L3_AREA: +Personal")
                  (result (test-pearl-gtd-file-contains-p file pattern))
                  (found (car result)))
             (should found))
  :teardown (kill-buffer "*Pearl-GTD Weekly Review*"))

(test-pearl-gtd-define-story test-pearl-gtd-horizons-set-l3-for-project
  "Set L3 horizon for project in weekly review."
  :setup (pearl-gtd-init-initialize)
  :files (("actions.org" "* TODO Project task\n:PROPERTIES:\n:ID: p-1\n:PROJECT: TestProject\n:END:\n"))
  :mock (((symbol-function 'read-string) (lambda (&rest _) "Work")))
  :body (progn
          (pearl-gtd-review-weekly)
          (with-current-buffer "*Pearl-GTD Weekly Review*"
            (goto-char (point-min))
            (search-forward "** Projects - Active")
            (search-forward "TestProject")
            (beginning-of-line)
            (pearl-gtd-horizons--edit-l3-at-point)))
  :asserts (let* ((file (expand-file-name "actions.org" pearl-gtd-init-base-directory))
                  (pattern ":L3_AREA: +Work")
                  (result (test-pearl-gtd-file-contains-p file pattern))
                  (found (car result)))
             (should found))
  :teardown (kill-buffer "*Pearl-GTD Weekly Review*"))

(test-pearl-gtd-define-story test-pearl-gtd-horizons-set-l4-l5-l6-for-project
  "Set L4, L5, L6 horizons for project with hierarchy constraints."
  :setup (pearl-gtd-init-initialize)
  :files (("actions.org" "* TODO Project task\n:PROPERTIES:\n:ID: p-1\n:PROJECT: TestProject\n:L3_AREA: Work\n:END:\n"))
  :mock (((symbol-function 'read-string)
          (lambda (prompt &optional initial _history)
            (cond
             ((string-match "L4" prompt) "Goal: Complete project")
             ((string-match "L5" prompt) "Vision: Professional growth")
             ((string-match "L6" prompt) "Purpose: Make impact")
             (t "")))))
  :body (progn
          (pearl-gtd-review-weekly)
          (with-current-buffer "*Pearl-GTD Weekly Review*"
            (goto-char (point-min))
            (search-forward "** Projects - Active")
            (search-forward "TestProject")
            (beginning-of-line)
            (let ((proj (pearl-gtd-horizons--edit-l4-at-point)))
              (pearl-gtd-horizons--edit-l5-at-point proj)
              (pearl-gtd-horizons--edit-l6-at-point proj))))
  :asserts (progn
             (let* ((file (expand-file-name "actions.org" pearl-gtd-init-base-directory))
                    (pattern1 ":L4_GOAL: +Goal: Complete project")
                    (result1 (test-pearl-gtd-file-contains-p file pattern1))
                    (found1 (car result1)))
               (should found1))
             (let* ((file (expand-file-name "actions.org" pearl-gtd-init-base-directory))
                    (pattern2 ":L5_VISION: +Vision: Professional growth")
                    (result2 (test-pearl-gtd-file-contains-p file pattern2))
                    (found2 (car result2)))
               (should found2))
             (let* ((file (expand-file-name "actions.org" pearl-gtd-init-base-directory))
                    (pattern3 ":L6_PURPOSE: +Purpose: Make impact")
                    (result3 (test-pearl-gtd-file-contains-p file pattern3))
                    (found3 (car result3)))
               (should found3)))
  :teardown (kill-buffer "*Pearl-GTD Weekly Review*"))

(test-pearl-gtd-define-story test-pearl-gtd-horizons-cannot-set-l5-without-l4
  "Cannot set L5_VISION without L4_GOAL set first."
  :setup (pearl-gtd-init-initialize)
  :files (("actions.org" "* TODO Project task\n:PROPERTIES:\n:ID: p-1\n:PROJECT: TestProject\n:L3_AREA: Work\n:END:\n"))
  :mock (((symbol-function 'read-string) (lambda (&rest _) "Vision")))
  :body (progn
          (pearl-gtd-review-weekly)
          (with-current-buffer "*Pearl-GTD Weekly Review*"
            (goto-char (point-min))
            (search-forward "** Projects - Active")
            (search-forward "TestProject")
            (beginning-of-line)
            (condition-case err
                (pearl-gtd-horizons--edit-l5-at-point)
              (error (should (string-match-p "L4 must be set first" (error-message-string err)))))))
  :asserts t
  :teardown (kill-buffer "*Pearl-GTD Weekly Review*"))

(test-pearl-gtd-define-story test-pearl-gtd-horizons-cannot-set-l6-without-l5
  "Cannot set L6 horizon without L5 set first."
  :setup (pearl-gtd-init-initialize)
  :files (("actions.org" "* TODO Project task\n:PROPERTIES:\n:ID: p-1\n:PROJECT: TestProject\n:L3_AREA: Work\n:L4_GOAL: Goal\n:END:\n"))
  :mock (((symbol-function 'read-string) (lambda (&rest _) "Purpose")))
  :body (progn
          (pearl-gtd-review-weekly)
          (with-current-buffer "*Pearl-GTD Weekly Review*"
            (goto-char (point-min))
            (search-forward "** Projects - Active")
            (search-forward "TestProject")
            (beginning-of-line)
            (condition-case err
                (pearl-gtd-horizons--edit-l6-at-point)
              (error (should (string-match-p "L5 must be set first" (error-message-string err)))))))
  :asserts t
  :teardown (kill-buffer "*Pearl-GTD Weekly Review*"))

(test-pearl-gtd-define-story test-pearl-gtd-horizons-project-horizon-inheritance
  "Project horizon inheritance to its actions."
  :setup (pearl-gtd-init-initialize)
  :files (("actions.org" "* TODO Task 1\n:PROPERTIES:\n:ID: t1\n:PROJECT: TestProject\n:END:\n* TODO Task 2\n:PROPERTIES:\n:ID: t2\n:PROJECT: TestProject\n:END:\n"))
  :mock (((symbol-function 'read-string) (lambda (&rest _) "Work")))
  :body (progn
          (pearl-gtd-review-weekly)
          (with-current-buffer "*Pearl-GTD Weekly Review*"
            (goto-char (point-min))
            (search-forward "** Projects - Active")
            (search-forward "TestProject")
            (beginning-of-line)
            (pearl-gtd-horizons--edit-l3-at-point)))
  :asserts (progn
             (let* ((file (expand-file-name "actions.org" pearl-gtd-init-base-directory))
                    (pattern ":L3_AREA: +Work")
                    (result (test-pearl-gtd-file-contains-p file pattern))
                    (found (car result)))
               (should found))
             ;; Both tasks should inherit L3 from project
             (let ((file (expand-file-name "actions.org" pearl-gtd-init-base-directory)))
               (with-temp-buffer
                 (insert-file-contents file)
                 (let ((count 0))
                   (while (re-search-forward ":L3_AREA: +Work" nil t)
                     (cl-incf count))
                   (should (= count 2)))))  ; 2 tasks, no project entry
             )
  :teardown (kill-buffer "*Pearl-GTD Weekly Review*"))

(test-pearl-gtd-define-story test-pearl-gtd-horizons-action-leaves-project-loses-horizon
  "Action leaving project loses project horizon."
  :setup (pearl-gtd-init-initialize)
  :files (("actions.org" "* TODO Task\n:PROPERTIES:\n:ID: t1\n:PROJECT: TestProject\n:L3_AREA: Work\n:END:\n"))
  :mock (((symbol-function 'read-string) (lambda (&rest _) "")))
  :body (progn
          ;; Remove project from task
          (pearl-gtd-review-weekly)
          (with-current-buffer "*Pearl-GTD Weekly Review*"
            (goto-char (point-min))
            (search-forward "** actions.org - Next Actions")
            (search-forward "Task")
            (beginning-of-line)
            (pearl-gtd-review--edit-project-at-point)))
  :asserts (progn
             (let* ((file (expand-file-name "actions.org" pearl-gtd-init-base-directory))
                    (pattern1 ":PROJECT: TestProject")
                    (result1 (test-pearl-gtd-file-contains-p file pattern1))
                    (found1 (car result1)))
               (should-not found1))
             (let* ((file (expand-file-name "actions.org" pearl-gtd-init-base-directory))
                    (pattern2 ":L3_AREA: Work")
                    (result2 (test-pearl-gtd-file-contains-p file pattern2))
                    (found2 (car result2)))
               (should-not found2)))
  :teardown (kill-buffer "*Pearl-GTD Weekly Review*"))

(test-pearl-gtd-define-story test-pearl-gtd-horizons-view-shows-hierarchy
  "Horizon view shows L6 to L3 hierarchy with projects and actions."
  :setup (pearl-gtd-init-initialize)
  :files (("actions.org" "* TODO No project task\n:PROPERTIES:\n:ID: np-1\n:L3_AREA: Personal\n:END:\n* TODO Project task\n:PROPERTIES:\n:ID: p-1\n:PROJECT: TestProject\n:L3_AREA: Work\n:L4_GOAL: Goal\n:L5_VISION: Vision\n:L6_PURPOSE: Purpose\n:END:\n"))
  :mock nil
  :body (pearl-gtd-horizons-view)
  :asserts (progn
             (should (get-buffer "*Pearl-GTD Horizons*"))
             (with-current-buffer "*Pearl-GTD Horizons*"
               ;; Verify hierarchy structure
               (goto-char (point-min))
               (should (search-forward "** Purpose" nil t))
               (should (search-forward "*** Vision" nil t))
               (should (search-forward "**** Goal" nil t))
               (should (search-forward "***** Work" nil t))
               (should (search-forward "****** TestProject" nil t))
               (should (search-forward "******* TODO Project task" nil t))
               (should (search-forward "** Personal" nil t))
               (should (search-forward "*** TODO No project task" nil t))))
  :teardown (kill-buffer "*Pearl-GTD Horizons*"))

(provide 'test-pearl-gtd-horizons)

;;; test-pearl-gtd-horizons.el ends here
