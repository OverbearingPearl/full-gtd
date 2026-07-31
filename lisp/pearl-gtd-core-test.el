;;; pearl-gtd-core-test.el --- Unit tests for pearl-gtd-core  -*- lexical-binding: t; -*-

;;; Commentary:

;; Low-level unit tests for core utility functions.

;;; Code:

(require 'ert)
(require 'pearl-gtd)
(require 'pearl-gtd-test)

;; Split values tests

(ert-deftest pearl-gtd-core-test-split-values-english-semicolon ()
  "Test splitting values with English semicolon."
  (should (equal (pearl-gtd-core--split-values "Project A; Project B; Project C")
                 '("Project A" "Project B" "Project C"))))

(ert-deftest pearl-gtd-core-test-split-values-chinese-semicolon ()
  "Test splitting values with Chinese semicolon."
  (should (equal (pearl-gtd-core--split-values "Project A；Project B；Project C")
                 '("Project A" "Project B" "Project C"))))

(ert-deftest pearl-gtd-core-test-split-values-mixed-semicolons ()
  "Test splitting values with mixed English and Chinese semicolons."
  (should (equal (pearl-gtd-core--split-values "Project A; Project B；Project C; Project D")
                 '("Project A" "Project B" "Project C" "Project D"))))

(ert-deftest pearl-gtd-core-test-split-values-with-spaces ()
  "Test splitting values containing spaces."
  (should (equal (pearl-gtd-core--split-values "Website Redesign; Marketing Campaign")
                 '("Website Redesign" "Marketing Campaign"))))

(ert-deftest pearl-gtd-core-test-split-values-empty-input ()
  "Test splitting empty or nil input."
  (should (null (pearl-gtd-core--split-values nil)))
  (should (null (pearl-gtd-core--split-values "")))
  (should (null (pearl-gtd-core--split-values "   "))))

(ert-deftest pearl-gtd-core-test-split-values-extra-whitespace ()
  "Test splitting values with extra whitespace (trim verification)."
  (should (equal (pearl-gtd-core--split-values "  Project A  ;  Project B  ;  ")
                 '("Project A" "Project B"))))

(ert-deftest pearl-gtd-core-test-split-values-preserves-comma ()
  "Test that commas are preserved (not treated as separators)."
  (should (equal (pearl-gtd-core--split-values "Company, Inc.; Project B")
                 '("Company, Inc." "Project B"))))

;; Join values tests

(ert-deftest pearl-gtd-core-test-join-values ()
  "Test joining values with English semicolon."
  (should (string= (pearl-gtd-core--join-values '("Project A" "Project B"))
                   "Project A; Project B")))

(ert-deftest pearl-gtd-core-test-join-values-single ()
  "Test joining single value."
  (should (string= (pearl-gtd-core--join-values '("Project A"))
                   "Project A")))

(ert-deftest pearl-gtd-core-test-join-values-empty ()
  "Test joining empty list."
  (should (string= (pearl-gtd-core--join-values '())
                   "")))

;; Normalize project input tests

(ert-deftest pearl-gtd-core-test-normalize-project-input ()
  "Test normalizing project input with various separators."
  (should (string= (pearl-gtd-core--normalize-project-input "Project A；Project B；Project C")
                   "Project A; Project B; Project C")))

(ert-deftest pearl-gtd-core-test-normalize-project-input-nil ()
  "Test normalizing nil input."
  (should (null (pearl-gtd-core--normalize-project-input nil))))

(ert-deftest pearl-gtd-core-test-normalize-project-input-empty ()
  "Test normalizing empty input."
  (should (null (pearl-gtd-core--normalize-project-input ""))))

(ert-deftest pearl-gtd-core-test-normalize-project-input-whitespace-only ()
  "Test that whitespace-only input becomes nil (trim to empty)."
  (should (null (pearl-gtd-core--normalize-project-input "   ")))
  (should (null (pearl-gtd-core--normalize-project-input "\t\n  "))))

(ert-deftest pearl-gtd-core-test-normalize-project-input-trim ()
  "Test that surrounding whitespace is trimmed."
  (should (string= (pearl-gtd-core--normalize-project-input "  Project A; Project B  ")
                   "Project A; Project B")))

(ert-deftest pearl-gtd-core-test-split-values-mixed-separators-with-spaces ()
  "Test splitting values with mixed separators and surrounding whitespace."
  (should (equal (pearl-gtd-core--split-values "  Project A ; Project B ； Project C ;Project D  ")
                 '("Project A" "Project B" "Project C" "Project D"))))

(ert-deftest pearl-gtd-core-test-split-values-tabs-and-spaces ()
  "Test splitting values with tabs and mixed whitespace."
  (should (equal (pearl-gtd-core--split-values "Project A\t;\tProject B  ;\t\tProject C")
                 '("Project A" "Project B" "Project C"))))

(ert-deftest pearl-gtd-core-test-split-values-empty-between-separators ()
  "Test splitting with empty values between separators."
  (should (equal (pearl-gtd-core--split-values "Project A;; Project B；;Project C")
                 '("Project A" "Project B" "Project C"))))

(ert-deftest pearl-gtd-core-test-split-values-single-value-with-spaces ()
  "Test splitting single value with surrounding whitespace."
  (should (equal (pearl-gtd-core--split-values "  Single Project  ")
                 '("Single Project"))))

(ert-deftest pearl-gtd-core-test-join-values-preserves-internal-spaces ()
  "Test that join preserves internal spaces in values."
  (should (string= (pearl-gtd-core--join-values '("Project A" "B" "C"))
                   "Project A; B; C")))

(ert-deftest pearl-gtd-core-test-normalize-project-input-mixed-separators ()
  "Test normalizing input with mixed English and Chinese semicolons."
  (should (string= (pearl-gtd-core--normalize-project-input "Project A；Project B;Project C")
                   "Project A; Project B; Project C")))

(ert-deftest pearl-gtd-core-test-normalize-project-input-only-whitespace ()
  "Test that whitespace-only input becomes nil."
  (should (null (pearl-gtd-core--normalize-project-input "   \t  \n  "))))

(ert-deftest pearl-gtd-core-test-normalize-project-input-mixed-whitespace-separators ()
  "Test normalizing with tabs and spaces around separators."
  (should (string= (pearl-gtd-core--normalize-project-input "P1 \t ; \t P2 ；  P3")
                   "P1; P2; P3")))

;;; Multi-value property completion tests

(ert-deftest pearl-gtd-core-test-read-property-project-multi-value ()
  "Project type uses completing-read-multiple and joins with semicolon."
  (cl-letf (((symbol-function 'completing-read-multiple)
             (lambda (prompt collection &rest _)
               '("ProjA" "ProjB" "ProjC")))
            ((symbol-function 'pearl-gtd-domain--collect-project-candidates)
             (lambda () '("ProjA" "ProjB" "ProjC"))))
    (let ((result (pearl-gtd-core-read-property-with-completion 
                   "Project: " 'project)))
      ;; Should join with English semicolon and space
      (should (string= result "ProjA; ProjB; ProjC")))))

(ert-deftest pearl-gtd-core-test-read-property-context-single-value ()
  "Context type uses single completing-read, not crm."
  (cl-letf (((symbol-function 'completing-read)
             (lambda (prompt collection &rest _) "@office"))
            ((symbol-function 'completing-read-multiple)
             (lambda (&rest _) (error "Should not use crm for context")))
            ((symbol-function 'pearl-gtd-domain--collect-context-candidates)
             (lambda () '("@office" "@home"))))
    (let ((result (pearl-gtd-core-read-property-with-completion 
                   "Context: " 'context)))
      (should (string= result "@office")))))

(ert-deftest pearl-gtd-core-test-read-property-horizon-l3-multi-value ()
  "L3 Area supports multiple values like Project."
  (cl-letf (((symbol-function 'completing-read-multiple)
             (lambda (prompt collection &rest _)
               '("Area1" "Area2")))
            ((symbol-function 'pearl-gtd-domain--collect-horizon-candidates)
             (lambda (_) '("Area1" "Area2" "Area3"))))
    (let ((result (pearl-gtd-core-read-property-with-completion 
                   "Area: " 'l3)))
      (should (string= result "Area1; Area2")))))

(ert-deftest pearl-gtd-core-test-read-property-initial-multi-value-split ()
  "Initial value string is split for crm and rejoined correctly."
  (cl-letf (((symbol-function 'completing-read-multiple)
             (lambda (prompt collection &rest args)
               ;; Verify initial was converted to list (6th arg, index 5, or index 2 in args)
               (let ((initial (nth 2 args)))
                 (should (listp initial))
                 (should (equal initial '("Old1" "Old2"))))
               '("Old1" "Old2" "New3")))
            ((symbol-function 'pearl-gtd-domain--collect-project-candidates)
             (lambda () '("Old1" "Old2" "New3"))))
    (pearl-gtd-core-read-property-with-completion 
     "Project: " 'project "Old1; Old2")))

(ert-deftest pearl-gtd-core-test-read-property-empty-crm-returns-empty-string ()
  "Empty completing-read-multiple returns empty string (not nil)."
  (cl-letf (((symbol-function 'completing-read-multiple)
             (lambda (&rest _) nil))
            ((symbol-function 'pearl-gtd-domain--collect-project-candidates)
             (lambda () '("ProjA"))))
    (let ((result (pearl-gtd-core-read-property-with-completion 
                   "Project: " 'project)))
      (should (string= result "")))))

;;; Date hybrid input tests

(declare-function pearl-gtd-core-read-date "pearl-gtd-core")

(ert-deftest pearl-gtd-core-test-date-today-quick ()
  "Pressing 't' returns today's date string."
  (cl-letf (((symbol-function 'read-key) (lambda () ?t)))
    (let ((result (pearl-gtd-core-read-date 'schedule)))
      (should (string= result (format-time-string "%F"))))))

(ert-deftest pearl-gtd-core-test-date-tomorrow-quick ()
  "Pressing 'T' returns tomorrow's date string."
  (cl-letf (((symbol-function 'read-key) (lambda () ?T)))
    (let ((result (pearl-gtd-core-read-date 'schedule)))
      (should (string= result
                       (format-time-string "%F"
                                           (time-add (current-time) (* 24 3600))))))))

(ert-deftest pearl-gtd-core-test-date-custom-input ()
  "Typing numeric prefix then full date returns custom date string."
  (cl-letf (((symbol-function 'read-key) (lambda () ?2))
            ((symbol-function 'read-string) (lambda (&rest _) "2026-08-15")))
    (let ((result (pearl-gtd-core-read-date 'deadline)))
      (should (string= result "2026-08-15")))))

(provide 'pearl-gtd-core-test)

;;; pearl-gtd-core-test.el ends here
