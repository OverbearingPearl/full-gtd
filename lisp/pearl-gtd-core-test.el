;;; pearl-gtd-core-test.el --- Unit tests for pearl-gtd-core  -*- lexical-binding: t; -*-

;;; Commentary:

;; Low-level unit tests for core utility functions.

;;; Code:

(require 'ert)
(require 'pearl-gtd)
(require 'pearl-gtd-test)

;; Split values tests

(ert-deftest pearl-gtd-test-core-split-values-english-semicolon ()
  "Test splitting values with English semicolon."
  (should (equal (pearl-gtd-core--split-values "Project A; Project B; Project C")
                 '("Project A" "Project B" "Project C")
          )
  )
)

(ert-deftest pearl-gtd-test-core-split-values-chinese-semicolon ()
  "Test splitting values with Chinese semicolon."
  (should (equal (pearl-gtd-core--split-values "Project A；Project B；Project C")
                 '("Project A" "Project B" "Project C")
          )
  )
)

(ert-deftest pearl-gtd-test-core-split-values-mixed-semicolons ()
  "Test splitting values with mixed English and Chinese semicolons."
  (should (equal (pearl-gtd-core--split-values "Project A; Project B；Project C; Project D")
                 '("Project A" "Project B" "Project C" "Project D")
          )
  )
)

(ert-deftest pearl-gtd-test-core-split-values-with-spaces ()
  "Test splitting values containing spaces."
  (should (equal (pearl-gtd-core--split-values "Website Redesign; Marketing Campaign")
                 '("Website Redesign" "Marketing Campaign")
          )
  )
)

(ert-deftest pearl-gtd-test-core-split-values-empty-input ()
  "Test splitting empty or nil input."
  (should (null (pearl-gtd-core--split-values nil)))
  (should (null (pearl-gtd-core--split-values "")))
  (should (null (pearl-gtd-core--split-values "   ")))
)

(ert-deftest pearl-gtd-test-core-split-values-extra-whitespace ()
  "Test splitting values with extra whitespace (trim verification)."
  (should (equal (pearl-gtd-core--split-values "  Project A  ;  Project B  ;  ")
                 '("Project A" "Project B")
          )
  )
)

(ert-deftest pearl-gtd-test-core-split-values-preserves-comma ()
  "Test that commas are preserved (not treated as separators)."
  (should (equal (pearl-gtd-core--split-values "Company, Inc.; Project B")
                 '("Company, Inc." "Project B")
          )
  )
)

;; Join values tests

(ert-deftest pearl-gtd-test-core-join-values ()
  "Test joining values with English semicolon."
  (should (string= (pearl-gtd-core--join-values '("Project A" "Project B"))
                   "Project A; Project B"
          )
  )
)

(ert-deftest pearl-gtd-test-core-join-values-single ()
  "Test joining single value."
  (should (string= (pearl-gtd-core--join-values '("Project A"))
                   "Project A"
          )
  )
)

(ert-deftest pearl-gtd-test-core-join-values-empty ()
  "Test joining empty list."
  (should (string= (pearl-gtd-core--join-values '())
                   ""
          )
  )
)

;; Normalize project input tests

(ert-deftest pearl-gtd-test-core-normalize-project-input ()
  "Test normalizing project input with various separators."
  (should (string= (pearl-gtd-core--normalize-project-input "Project A；Project B；Project C")
                   "Project A; Project B; Project C"
          )
  )
)

(ert-deftest pearl-gtd-test-core-normalize-project-input-nil ()
  "Test normalizing nil input."
  (should (null (pearl-gtd-core--normalize-project-input nil)))
)

(ert-deftest pearl-gtd-test-core-normalize-project-input-empty ()
  "Test normalizing empty input."
  (should (null (pearl-gtd-core--normalize-project-input "")))
)

(ert-deftest pearl-gtd-test-core-normalize-project-input-whitespace-only ()
  "Test that whitespace-only input becomes nil (trim to empty)."
  (should (null (pearl-gtd-core--normalize-project-input "   ")))
  (should (null (pearl-gtd-core--normalize-project-input "\t\n  ")))
)

(ert-deftest pearl-gtd-test-core-normalize-project-input-trim ()
  "Test that surrounding whitespace is trimmed."
  (should (string= (pearl-gtd-core--normalize-project-input "  Project A; Project B  ")
                   "Project A; Project B"
          )
  )
)

(ert-deftest pearl-gtd-test-core-split-values-mixed-separators-with-spaces ()
  "Test splitting values with mixed separators and surrounding whitespace."
  (should (equal (pearl-gtd-core--split-values "  Project A ; Project B ； Project C ;Project D  ")
                 '("Project A" "Project B" "Project C" "Project D")
          )
  )
)

(ert-deftest pearl-gtd-test-core-split-values-tabs-and-spaces ()
  "Test splitting values with tabs and mixed whitespace."
  (should (equal (pearl-gtd-core--split-values "Project A\t;\tProject B  ;\t\tProject C")
                 '("Project A" "Project B" "Project C")
          )
  )
)

(ert-deftest pearl-gtd-test-core-split-values-empty-between-separators ()
  "Test splitting with empty values between separators."
  (should (equal (pearl-gtd-core--split-values "Project A;; Project B；;Project C")
                 '("Project A" "Project B" "Project C")
          )
  )
)

(ert-deftest pearl-gtd-test-core-split-values-single-value-with-spaces ()
  "Test splitting single value with surrounding whitespace."
  (should (equal (pearl-gtd-core--split-values "  Single Project  ")
                 '("Single Project")
          )
  )
)

(ert-deftest pearl-gtd-test-core-join-values-preserves-internal-spaces ()
  "Test that join preserves internal spaces in values."
  (should (string= (pearl-gtd-core--join-values '("Project A" "B" "C"))
                   "Project A; B; C"
          )
  )
)

(ert-deftest pearl-gtd-test-core-normalize-project-input-mixed-separators ()
  "Test normalizing input with mixed English and Chinese semicolons."
  (should (string= (pearl-gtd-core--normalize-project-input "Project A；Project B;Project C")
                   "Project A; Project B; Project C"
          )
  )
)

(ert-deftest pearl-gtd-test-core-normalize-project-input-only-whitespace ()
  "Test that whitespace-only input becomes nil."
  (should (null (pearl-gtd-core--normalize-project-input "   \t  \n  ")))
)

(ert-deftest pearl-gtd-test-core-normalize-project-input-mixed-whitespace-separators ()
  "Test normalizing with tabs and spaces around separators."
  (should (string= (pearl-gtd-core--normalize-project-input "P1 \t ; \t P2 ；  P3")
                   "P1; P2; P3"
          )
  )
)

(provide 'pearl-gtd-core-test)

;;; pearl-gtd-core-test.el ends here
