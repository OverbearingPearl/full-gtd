;;; pearl-gtd-test-horizons.el --- User stories: 6 Horizons  -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: MIT
;; URL: https://github.com/OverbearingPearl/pearl-gtd

;;; Commentary:

;; User stories for 6 Horizons of Focus.

;;; Code:

(eval-and-compile
  (let ((dir (file-name-directory (or load-file-name buffer-file-name))))
    (add-to-list 'load-path (expand-file-name ".." dir))
    (load-file (expand-file-name "pearl-gtd-test.el" dir))))
(require 'ert)
(require 'pearl-gtd)

(pearl-gtd-test-define-story pearl-gtd-test-horizons-user-views-horizon-columns
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

(pearl-gtd-test-define-story pearl-gtd-test-horizons-user-sets-area-for-action
  "Set Area (L3) horizon for no-project action in weekly review."
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
            (pearl-gtd-horizons--edit-area-at-point)))
  :asserts (let* ((file (expand-file-name "actions.org" pearl-gtd-init-base-directory))
                  (pattern ":L3_AREA: +Personal")
                  (result (pearl-gtd-test-file-contains-p file pattern))
                  (found (car result)))
             (should found))
  :teardown (kill-buffer "*Pearl-GTD Weekly Review*"))

(pearl-gtd-test-define-story pearl-gtd-test-horizons-user-sets-area-for-project
  "Set Area (L3) horizon for project in weekly review."
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
            (pearl-gtd-horizons--edit-area-at-point)))
  :asserts (let* ((file (expand-file-name "actions.org" pearl-gtd-init-base-directory))
                  (pattern ":L3_AREA: +Work")
                  (result (pearl-gtd-test-file-contains-p file pattern))
                  (found (car result)))
             (should found))
  :teardown (kill-buffer "*Pearl-GTD Weekly Review*"))

(pearl-gtd-test-define-story pearl-gtd-test-horizons-user-sets-goal-through-purpose
  "Set Goal (L4), Vision (L5), and Purpose (L6) horizons for project with hierarchy constraints."
  :setup (pearl-gtd-init-initialize)
  :files (("actions.org" "* TODO Project task\n:PROPERTIES:\n:ID: p-1\n:PROJECT: TestProject\n:L3_AREA: Work\n:END:\n"))
  :mock (((symbol-function 'read-string)
          (lambda (prompt &optional _initial _history)
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
            (let ((proj (pearl-gtd-horizons--edit-goal-at-point)))
              (pearl-gtd-horizons--edit-vision-at-point proj)
              (pearl-gtd-horizons--edit-purpose-at-point proj))))
  :asserts (progn
             (let* ((file (expand-file-name "actions.org" pearl-gtd-init-base-directory))
                    (pattern1 ":L4_GOAL: +Goal: Complete project")
                    (result1 (pearl-gtd-test-file-contains-p file pattern1))
                    (found1 (car result1)))
               (should found1))
             (let* ((file (expand-file-name "actions.org" pearl-gtd-init-base-directory))
                    (pattern2 ":L5_VISION: +Vision: Professional growth")
                    (result2 (pearl-gtd-test-file-contains-p file pattern2))
                    (found2 (car result2)))
               (should found2))
             (let* ((file (expand-file-name "actions.org" pearl-gtd-init-base-directory))
                    (pattern3 ":L6_PURPOSE: +Purpose: Make impact")
                    (result3 (pearl-gtd-test-file-contains-p file pattern3))
                    (found3 (car result3)))
               (should found3)))
  :teardown (kill-buffer "*Pearl-GTD Weekly Review*"))


(pearl-gtd-test-define-story pearl-gtd-test-horizons-user-sees-horizon-inheritance
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
            (pearl-gtd-horizons--edit-area-at-point)))
  :asserts (progn
             (let* ((file (expand-file-name "actions.org" pearl-gtd-init-base-directory))
                    (pattern ":L3_AREA: +Work")
                    (result (pearl-gtd-test-file-contains-p file pattern))
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

(pearl-gtd-test-define-story pearl-gtd-test-horizons-user-removes-project-clears-horizon
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
                    (result1 (pearl-gtd-test-file-contains-p file pattern1))
                    (found1 (car result1)))
               (should-not found1))
             (let* ((file (expand-file-name "actions.org" pearl-gtd-init-base-directory))
                    (pattern2 ":L3_AREA: Work")
                    (result2 (pearl-gtd-test-file-contains-p file pattern2))
                    (found2 (car result2)))
               (should-not found2)))
  :teardown (kill-buffer "*Pearl-GTD Weekly Review*"))

(pearl-gtd-test-define-story pearl-gtd-test-horizons-user-views-hierarchy
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

(pearl-gtd-test-define-story pearl-gtd-test-horizons-user-clears-area-cascades-to-actions
  "Clearing Area (L3) from project should remove inherited Area from actions."
  :setup (pearl-gtd-init-initialize)
  :files (("actions.org" "* TODO Task 1\n:PROPERTIES:\n:ID: cascade-1\n:PROJECT: TestProj\n:L3_AREA: Work\n:END:\n"))
  :mock (((symbol-function 'read-string) (lambda (&rest _) "")))
  :body (progn
          (pearl-gtd-review-weekly)
          (with-current-buffer "*Pearl-GTD Weekly Review*"
            (goto-char (point-min))
            (search-forward "** Projects - Active")
            (search-forward "TestProj")
            (beginning-of-line)
            (pearl-gtd-horizons--edit-area-at-point)))
  :asserts (let ((content (with-temp-buffer
                            (insert-file-contents
                             (expand-file-name "actions.org" pearl-gtd-init-base-directory))
                            (buffer-string))))
             (should-not (string-match-p ":L3_AREA:" content)))
  :teardown (pearl-gtd-test-cleanup-buffers '("*Pearl-GTD Weekly Review*")))

(pearl-gtd-test-define-story pearl-gtd-test-horizons-constraint-rejects-vision-without-goal
  "User is blocked when attempting to set Vision (L5) without Goal (L4)."
  :setup (pearl-gtd-init-initialize)
  :files (("actions.org" "* TODO Task\n:PROPERTIES:\n:ID: constraint-1\n:PROJECT: ConstraintProj\n:L3_AREA: Area\n:END:\n"))
  :mock (((symbol-function 'read-string) (lambda (&rest _) "VisionValue")))
  :body (progn
          (pearl-gtd-review-weekly)
          (with-current-buffer "*Pearl-GTD Weekly Review*"
            (goto-char (point-min))
            (search-forward "** Projects - Active")
            (search-forward "ConstraintProj")
            (beginning-of-line)
            (condition-case err
                (pearl-gtd-horizons--edit-vision-at-point)
              (error (should (string-match-p "L4 Goal must be set first" (error-message-string err)))))))
  :asserts t
  :teardown (pearl-gtd-test-cleanup-buffers '("*Pearl-GTD Weekly Review*")))

(pearl-gtd-test-define-story pearl-gtd-test-horizons-constraint-rejects-purpose-without-vision
  "User is blocked when attempting to set Purpose (L6) without Vision (L5)."
  :setup (pearl-gtd-init-initialize)
  :files (("actions.org" "* TODO Task\n:PROPERTIES:\n:ID: constraint-2\n:PROJECT: ConstraintProj2\n:L3_AREA: Area\n:L4_GOAL: Goal\n:END:\n"))
  :mock (((symbol-function 'read-string) (lambda (&rest _) "PurposeValue")))
  :body (progn
          (pearl-gtd-review-weekly)
          (with-current-buffer "*Pearl-GTD Weekly Review*"
            (goto-char (point-min))
            (search-forward "** Projects - Active")
            (search-forward "ConstraintProj2")
            (beginning-of-line)
            (condition-case err
                (pearl-gtd-horizons--edit-purpose-at-point)
              (error (should (string-match-p "L5 Vision must be set first" (error-message-string err)))))))
  :asserts t
  :teardown (pearl-gtd-test-cleanup-buffers '("*Pearl-GTD Weekly Review*")))

(pearl-gtd-test-define-story pearl-gtd-test-horizons-constraint-rejects-principle-without-purpose
  "User is blocked when attempting to set L6 Principle without L6 Purpose."
  :setup (pearl-gtd-init-initialize)
  :files (("actions.org" "* TODO Task\n:PROPERTIES:\n:ID: constraint-3\n:PROJECT: ConstraintProj3\n:L3_AREA: Area\n:L4_GOAL: Goal\n:L5_VISION: Vision\n:END:\n"))
  :mock (((symbol-function 'read-string) (lambda (&rest _) "PrincipleValue")))
  :body (progn
          (pearl-gtd-review-weekly)
          (with-current-buffer "*Pearl-GTD Weekly Review*"
            (goto-char (point-min))
            (search-forward "** Projects - Active")
            (search-forward "ConstraintProj3")
            (beginning-of-line)
            (condition-case err
                (pearl-gtd-horizons--edit-principle-at-point)
              (error (should (string-match-p "L6 Purpose must be set first" (error-message-string err)))))))
  :asserts t
  :teardown (pearl-gtd-test-cleanup-buffers '("*Pearl-GTD Weekly Review*")))

(provide 'pearl-gtd-test-horizons)

;;; pearl-gtd-test-horizons.el ends here
