;;; pearl-gtd-domain-test.el --- Unit tests for pearl-gtd-domain  -*- lexical-binding: t; -*-

;;; Commentary:

;; Unit tests for domain layer pure functions.

;;; Code:

(require 'ert)
(require 'pearl-gtd-domain)

;;;; Planning validation tests

(ert-deftest pearl-gtd-domain-test-planning-input-valid-p-all-valid ()
  "All fields provided should return valid."
  (let ((result (pearl-gtd-domain--planning-input-valid-p "Proj" "Purpose" "Vision" "Goal")))
    (should (consp result))
    (should (car result))
    (should (null (cdr result)))))

(ert-deftest pearl-gtd-domain-test-planning-input-valid-p-empty-project ()
  "Empty project name should be invalid."
  (let ((result (pearl-gtd-domain--planning-input-valid-p "" "Purpose" "Vision" "Goal")))
    (should-not (car result))
    (should (string-match-p "Project name" (cdr result)))))

(ert-deftest pearl-gtd-domain-test-planning-input-valid-p-nil-project ()
  "Nil project name should be invalid."
  (let ((result (pearl-gtd-domain--planning-input-valid-p nil "Purpose" "Vision" "Goal")))
    (should-not (car result))))

(ert-deftest pearl-gtd-domain-test-planning-input-valid-p-empty-purpose ()
  "Empty purpose should be invalid."
  (let ((result (pearl-gtd-domain--planning-input-valid-p "Proj" "" "Vision" "Goal")))
    (should-not (car result))
    (should (string-match-p "Purpose" (cdr result)))))

(ert-deftest pearl-gtd-domain-test-planning-input-valid-p-empty-goal ()
  "Empty goal should be invalid."
  (let ((result (pearl-gtd-domain--planning-input-valid-p "Proj" "Purpose" "Vision" "")))
    (should-not (car result))
    (should (string-match-p "Goal" (cdr result)))))

(ert-deftest pearl-gtd-domain-test-planning-input-valid-p-empty-vision ()
  "Empty vision should be valid (optional field)."
  (let ((result (pearl-gtd-domain--planning-input-valid-p "Proj" "Purpose" "" "Goal")))
    (should (car result))
    (should (null (cdr result)))))

(ert-deftest pearl-gtd-domain-test-require-next-action-p-zero ()
  "Zero actions should require forced next action."
  (should (pearl-gtd-domain--require-next-action-p 0)))

(ert-deftest pearl-gtd-domain-test-require-next-action-p-nonzero ()
  "Non-zero actions should not require forced next action."
  (should-not (pearl-gtd-domain--require-next-action-p 1))
  (should-not (pearl-gtd-domain--require-next-action-p 5)))

;;;; Horizon hierarchy tests

(ert-deftest pearl-gtd-domain-test-check-hierarchy-constraint-area ()
  "Area can always be set."
  (let ((result (pearl-gtd-domain--check-hierarchy-constraint '() 'area)))
    (should (car result))))

(ert-deftest pearl-gtd-domain-test-check-hierarchy-constraint-goal ()
  "Goal level should always be valid (no dependency)."
  (let ((result-empty (pearl-gtd-domain--check-hierarchy-constraint '() 'goal))
        (result-with-data (pearl-gtd-domain--check-hierarchy-constraint
                           '((L4_GOAL . "Existing")) 'goal)))
    (should (car result-empty))
    (should (null (cdr result-empty)))
    (should (car result-with-data))
    (should (null (cdr result-with-data)))))

(ert-deftest pearl-gtd-domain-test-check-hierarchy-constraint-vision-without-goal ()
  "Vision without goal should be invalid."
  (let ((result (pearl-gtd-domain--check-hierarchy-constraint
                 '((L4_GOAL . "")) 'vision)))
    (should-not (car result))
    (should (string-match-p "L4 Goal" (cdr result)))))

(ert-deftest pearl-gtd-domain-test-check-hierarchy-constraint-vision-with-goal ()
  "Vision with goal should be valid."
  (let ((result (pearl-gtd-domain--check-hierarchy-constraint
                 '((L4_GOAL . "Goal")) 'vision)))
    (should (car result))))

(ert-deftest pearl-gtd-domain-test-check-hierarchy-constraint-purpose-without-vision ()
  "Purpose without vision should be invalid."
  (let ((result (pearl-gtd-domain--check-hierarchy-constraint
                 '((L5_VISION . "")) 'purpose)))
    (should-not (car result))
    (should (string-match-p "L5 Vision" (cdr result)))))

(ert-deftest pearl-gtd-domain-test-check-hierarchy-constraint-principle-without-purpose ()
  "Principle without purpose should be invalid."
  (let ((result (pearl-gtd-domain--check-hierarchy-constraint
                 '((L6_PURPOSE . "")) 'principle)))
    (should-not (car result))
    (should (string-match-p "L6 Purpose" (cdr result)))))

(ert-deftest pearl-gtd-domain-test-check-hierarchy-constraint-principle-with-purpose ()
  "Principle with purpose should be valid."
  (let ((result (pearl-gtd-domain--check-hierarchy-constraint
                 '((L6_PURPOSE . "Purpose")) 'principle)))
    (should (car result))))

(provide 'pearl-gtd-domain-test)

;;; pearl-gtd-domain-test.el ends here
