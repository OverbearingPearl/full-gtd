;;; full-gtd-domain-test.el --- Unit tests for full-gtd-domain  -*- lexical-binding: t; -*-

;;; Commentary:

;; Unit tests for domain layer pure functions.

;;; Code:

(require 'ert)
(require 'full-gtd-domain)

;;;; Planning validation tests

(ert-deftest full-gtd-domain-test-planning-input-valid-p-all-valid ()
  "All fields provided should return valid."
  (let ((result (full-gtd-domain--planning-input-valid-p "Proj" "Purpose" "Vision" "Goal")))
    (should (consp result))
    (should (car result))
    (should (null (cdr result)))))

(ert-deftest full-gtd-domain-test-planning-input-valid-p-empty-project ()
  "Empty project name should be invalid."
  (let ((result (full-gtd-domain--planning-input-valid-p "" "Purpose" "Vision" "Goal")))
    (should-not (car result))
    (should (string-match-p "Project name" (cdr result)))))

(ert-deftest full-gtd-domain-test-planning-input-valid-p-nil-project ()
  "Nil project name should be invalid."
  (let ((result (full-gtd-domain--planning-input-valid-p nil "Purpose" "Vision" "Goal")))
    (should-not (car result))))

(ert-deftest full-gtd-domain-test-planning-input-valid-p-empty-purpose ()
  "Empty purpose should be invalid."
  (let ((result (full-gtd-domain--planning-input-valid-p "Proj" "" "Vision" "Goal")))
    (should-not (car result))
    (should (string-match-p "Purpose" (cdr result)))))

(ert-deftest full-gtd-domain-test-planning-input-valid-p-empty-goal ()
  "Empty goal should be invalid."
  (let ((result (full-gtd-domain--planning-input-valid-p "Proj" "Purpose" "Vision" "")))
    (should-not (car result))
    (should (string-match-p "Goal" (cdr result)))))

(ert-deftest full-gtd-domain-test-planning-input-valid-p-empty-vision ()
  "Empty vision should be invalid (required field)."
  (let ((result (full-gtd-domain--planning-input-valid-p "Proj" "Purpose" "" "Goal")))
    (should-not (car result))
    (should (string-match-p "Vision" (cdr result)))))

(ert-deftest full-gtd-domain-test-require-next-action-p-zero ()
  "Zero actions should require forced next action."
  (should (full-gtd-domain--require-next-action-p 0)))

(ert-deftest full-gtd-domain-test-require-next-action-p-nonzero ()
  "Non-zero actions should not require forced next action."
  (should-not (full-gtd-domain--require-next-action-p 1))
  (should-not (full-gtd-domain--require-next-action-p 5)))

;;;; Horizon hierarchy tests

(ert-deftest full-gtd-domain-test-check-hierarchy-constraint-area ()
  "Area can always be set."
  (let ((result (full-gtd-domain--check-hierarchy-constraint '() 'area)))
    (should (car result))))

(ert-deftest full-gtd-domain-test-check-hierarchy-constraint-goal ()
  "Goal level should always be valid (no dependency)."
  (let ((result-empty (full-gtd-domain--check-hierarchy-constraint '() 'goal))
        (result-with-data (full-gtd-domain--check-hierarchy-constraint
                           '((L4_GOAL . "Existing")) 'goal)))
    (should (car result-empty))
    (should (null (cdr result-empty)))
    (should (car result-with-data))
    (should (null (cdr result-with-data)))))

(ert-deftest full-gtd-domain-test-check-hierarchy-constraint-vision-without-goal ()
  "Vision without goal should be invalid."
  (let ((result (full-gtd-domain--check-hierarchy-constraint
                 '((L4_GOAL . "")) 'vision)))
    (should-not (car result))
    (should (string-match-p "L4 Goal" (cdr result)))))

(ert-deftest full-gtd-domain-test-check-hierarchy-constraint-vision-with-goal ()
  "Vision with goal should be valid."
  (let ((result (full-gtd-domain--check-hierarchy-constraint
                 '((L4_GOAL . "Goal")) 'vision)))
    (should (car result))))

(ert-deftest full-gtd-domain-test-check-hierarchy-constraint-purpose-without-vision ()
  "Purpose without vision should be invalid."
  (let ((result (full-gtd-domain--check-hierarchy-constraint
                 '((L5_VISION . "")) 'purpose)))
    (should-not (car result))
    (should (string-match-p "L5 Vision" (cdr result)))))

(ert-deftest full-gtd-domain-test-check-hierarchy-constraint-principle-without-purpose ()
  "Principle without purpose should be invalid."
  (let ((result (full-gtd-domain--check-hierarchy-constraint
                 '((L6_PURPOSE . "")) 'principle)))
    (should-not (car result))
    (should (string-match-p "L6 Purpose" (cdr result)))))

(ert-deftest full-gtd-domain-test-check-hierarchy-constraint-principle-with-purpose ()
  "Principle with purpose should be valid."
  (let ((result (full-gtd-domain--check-hierarchy-constraint
                 '((L6_PURPOSE . "Purpose")) 'principle)))
    (should (car result))))

;;;; Horizon computation tests

(ert-deftest full-gtd-domain-test-compute-project-horizon-intersection ()
  "Intersection of values across actions in the same project."
  (let ((entries
         (list (cons '("ProjA") '(("L3_AREA" . "Area1; Area2")
                                  ("L4_GOAL" . "Goal1")))
               (cons '("ProjA" "ProjB") '(("L3_AREA" . "Area2; Area3")
                                          ("L4_GOAL" . "Goal1; Goal2"))))))
    ;; ProjA: Area1;Area2 ∩ Area2;Area3 = Area2
    (should (equal (full-gtd-domain--compute-project-horizon "ProjA" "L3_AREA" entries)
                   '("Area2")))
    ;; ProjA: Goal1 ∩ Goal1;Goal2 = Goal1
    (should (equal (full-gtd-domain--compute-project-horizon "ProjA" "L4_GOAL" entries)
                   '("Goal1")))
    ;; ProjB: only second entry has ProjB, values = Area2;Area3
    (should (equal (full-gtd-domain--compute-project-horizon "ProjB" "L3_AREA" entries)
                   '("Area2" "Area3")))))

(ert-deftest full-gtd-domain-test-compute-project-horizon-ignores-missing-level ()
  "Actions without the level or with empty value are ignored."
  (let ((entries (list (cons '("ProjA") '(("L3_AREA" . "Area1; Area2")))
                       (cons '("ProjA") '(("L3_AREA" . "")))
                       (cons '("ProjA") '(("L3_AREA" . nil))))))
    (should (equal (full-gtd-domain--compute-project-horizon "ProjA" "L3_AREA" entries)
                   '("Area1" "Area2")))))

(ert-deftest full-gtd-domain-test-compute-project-horizon-no-intersection ()
  "Disjoint values yield nil."
  (let ((entries (list (cons '("ProjA") '(("L3_AREA" . "Area1")))
                       (cons '("ProjA") '(("L3_AREA" . "Area2"))))))
    (should (null (full-gtd-domain--compute-project-horizon "ProjA" "L3_AREA" entries)))))

(ert-deftest full-gtd-domain-test-compute-project-horizon-no-actions ()
  "No entries or no matching project yields nil."
  (should (null (full-gtd-domain--compute-project-horizon "ProjA" "L3_AREA" '())))
  (should (null (full-gtd-domain--compute-project-horizon
                 "ProjA" "L3_AREA"
                 (list (cons '("ProjB") '(("L3_AREA" . "Area1"))))))))

(ert-deftest full-gtd-domain-test-combine-project-horizons-union ()
  "Union deduplicates and ignores nil inputs."
  (should (equal (full-gtd-domain--combine-project-horizons
                  '(("Area1" "Area2") ("Area2" "Area3")))
                 '("Area1" "Area2" "Area3")))
  (should (equal (full-gtd-domain--combine-project-horizons
                  '(nil ("Area2") ("Area3")))
                 '("Area2" "Area3"))))

(ert-deftest full-gtd-domain-test-combine-project-horizons-empty ()
  "All-empty inputs yield nil."
  (should (null (full-gtd-domain--combine-project-horizons '(nil nil))))
  (should (null (full-gtd-domain--combine-project-horizons '()))))

(ert-deftest full-gtd-domain-test-compute-entry-horizons-single-project ()
  "Single project: intersection across all five levels."
  (let* ((entries '((("ProjA")
                     ("L3_AREA" . "Area1; Area2")
                     ("L4_GOAL" . "Goal1")
                     ("L5_VISION" . "Vision1")
                     ("L6_PURPOSE" . "Purpose1")
                     ("L6_PRINCIPLE" . "Principle1"))
                    (("ProjA")
                     ("L3_AREA" . "Area2; Area3")
                     ("L4_GOAL" . "Goal1; Goal2")
                     ("L5_VISION" . "Vision1; Vision2")
                     ("L6_PURPOSE" . "Purpose2")
                     ("L6_PRINCIPLE" . "Principle1; Principle2"))))
         (result (full-gtd-domain--compute-entry-horizons '("ProjA") entries)))
    (should (equal (cdr (assoc "L3_AREA" result)) "Area2"))
    (should (equal (cdr (assoc "L4_GOAL" result)) "Goal1"))
    (should (equal (cdr (assoc "L5_VISION" result)) "Vision1"))
    (should (null (assoc "L6_PURPOSE" result)))
    (should (equal (cdr (assoc "L6_PRINCIPLE" result)) "Principle1"))))

(ert-deftest full-gtd-domain-test-compute-entry-horizons-multi-project-union ()
  "Multiple projects: union of per-project intersections."
  (let* ((entries '((("ProjA") ("L3_AREA" . "Area1; Area2") ("L4_GOAL" . "GoalA"))
                    (("ProjB") ("L3_AREA" . "Area2; Area3") ("L4_GOAL" . "GoalB"))))
         (result (full-gtd-domain--compute-entry-horizons '("ProjA" "ProjB") entries)))
    (should (equal (cdr (assoc "L3_AREA" result)) "Area1; Area2; Area3"))
    (should (equal (cdr (assoc "L4_GOAL" result)) "GoalA; GoalB"))))

(ert-deftest full-gtd-domain-test-compute-entry-horizons-no-project ()
  "No project yields empty alist."
  (let ((entries '((("ProjA") ("L3_AREA" . "Area1")))))
    (should (null (full-gtd-domain--compute-entry-horizons nil entries)))))

(ert-deftest full-gtd-domain-test-compute-entry-horizons-only-action ()
  "Entry is the only action in its project → all levels empty."
  (let* ((entries '((("OtherProj") ("L3_AREA" . "AreaX"))))
         (result (full-gtd-domain--compute-entry-horizons '("ProjA") entries)))
    (should (null result))))

;;;; Group actions by project

(defun full-gtd-domain-test--make-entry (headline status id project &optional context)
  "Build an entry list in `full-gtd-core-filter-entries' shape.
HEADLINE, STATUS, and ID are strings.  PROJECT is a project string,
possibly nil for no-project entries.  CONTEXT defaults to \"\"."
  (list headline "@tag" status nil nil project "2026-01-01" id
        "action.org" nil (or context "") nil nil nil nil))

(ert-deftest full-gtd-domain-test-group-actions-single-project ()
  "Actions of one project are grouped and preserve order."
  (let* ((org-done-keywords '("DONE"))
         (entries
          (list
           (full-gtd-domain-test--make-entry "A" "TODO" "id-a" "ProjA")
           (full-gtd-domain-test--make-entry "B" "DONE" "id-b" "ProjA")))
         (result (full-gtd-domain--group-actions-by-project entries)))
    (should (= (length result) 1))
    (should (string= (caar result) "ProjA"))
    (let ((actions (cdar result)))
      (should (= (length actions) 2))
      (should (string= (cdr (assq 'headline (car actions))) "A"))
      (should (string= (cdr (assq 'headline (cadr actions))) "B"))
      (should (string= (cdr (assq 'status (car actions))) "TODO"))
      (should (cdr (assq 'done-p (cadr actions)))))))

(ert-deftest full-gtd-domain-test-group-actions-multi-project-duplicates ()
  "An entry shared by multiple projects appears under each project."
  (let* ((org-done-keywords '("DONE"))
         (entries
          (list
           (full-gtd-domain-test--make-entry "Shared" "TODO" "id-1" "Alpha; Beta")))
         (result (full-gtd-domain--group-actions-by-project entries)))
    (should (= (length result) 2))
    (should (string= (caar result) "Alpha"))
    (should (string= (caadr result) "Beta"))
    (dolist (pair result)
      (should (= (length (cdr pair)) 1))
      (should (string= (cdr (assq 'id (car (cdr pair)))) "id-1")))))

(ert-deftest full-gtd-domain-test-group-actions-excludes-no-project ()
  "Entries without PROJECT are omitted from the result."
  (let* ((entries
          (list
           (full-gtd-domain-test--make-entry "NoProj" "TODO" "id-x" nil)
           (full-gtd-domain-test--make-entry "WithProj" "TODO" "id-y" "ProjA")))
         (result (full-gtd-domain--group-actions-by-project entries)))
    (should (= (length result) 1))
    (should (string= (caar result) "ProjA"))
    (should (= (length (cdar result)) 1))
    (should (string= (cdr (assq 'headline (car (cdar result)))) "WithProj"))))

(ert-deftest full-gtd-domain-test-group-actions-empty-list ()
  "Empty input yields empty alist."
  (should (null (full-gtd-domain--group-actions-by-project nil)))
  (should (null (full-gtd-domain--group-actions-by-project '()))))

(ert-deftest full-gtd-domain-test-collect-project-candidates ()
  "Project candidates are deduplicated PROJECT values, sorted."
  (let ((full-gtd-init-base-directory (make-temp-file "full-gtd-test-" t)))
    (unwind-protect
        (progn
          (write-region "* TODO A\n:PROPERTIES:\n:ID: cand-a\n:PROJECT: Alpha; Beta\n:END:\n* TODO B\n:PROPERTIES:\n:ID: cand-b\n:PROJECT: Beta\n:END:\n* DONE C\n:PROPERTIES:\n:ID: cand-c\n:PROJECT: Gamma\n:END:\n"
                        nil
                        (expand-file-name "action.org" full-gtd-init-base-directory))
          (should (equal (full-gtd-domain--collect-project-candidates)
                         '("Alpha" "Beta" "Gamma"))))
      (delete-directory full-gtd-init-base-directory t))))

(ert-deftest full-gtd-domain-test-collect-delegate-candidates ()
  "Delegate candidates are deduplicated DELEGATED values, sorted."
  (let ((full-gtd-init-base-directory (make-temp-file "full-gtd-test-" t)))
    (unwind-protect
        (progn
          (write-region "* TODO A\n:PROPERTIES:\n:ID: cand-d\n:DELEGATED: Bob\n:END:\n* TODO B\n:PROPERTIES:\n:ID: cand-e\n:DELEGATED: Alice\n:END:\n"
                        nil
                        (expand-file-name "action.org" full-gtd-init-base-directory))
          (should (equal (full-gtd-domain--collect-delegate-candidates)
                         '("Alice" "Bob"))))
      (delete-directory full-gtd-init-base-directory t))))

(ert-deftest full-gtd-domain-test-collect-horizon-candidates-invalid-level ()
  "Invalid horizon levels should signal an error."
  (should-error
   (full-gtd-domain--collect-horizon-candidates "L2_AREA")
   :type 'error))

(provide 'full-gtd-domain-test)

;;; full-gtd-domain-test.el ends here
