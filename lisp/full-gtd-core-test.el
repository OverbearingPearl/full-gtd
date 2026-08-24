;;; full-gtd-core-test.el --- Unit tests for full-gtd-core  -*- lexical-binding: t; -*-

;;; Commentary:

;; Low-level unit tests for core utility functions.

;;; Code:

(require 'ert)
(require 'full-gtd)
(require 'full-gtd-test-utils)

;; Split values tests

(ert-deftest full-gtd-core-test-split-values-english-semicolon ()
  "Test splitting values with English semicolon."
  (should (equal (full-gtd-core--split-values "Project A; Project B; Project C")
                 '("Project A" "Project B" "Project C"))))

(ert-deftest full-gtd-core-test-split-values-chinese-semicolon ()
  "Test splitting values with Chinese semicolon."
  (should (equal (full-gtd-core--split-values "Project A；Project B；Project C")
                 '("Project A" "Project B" "Project C"))))

(ert-deftest full-gtd-core-test-split-values-mixed-semicolons ()
  "Test splitting values with mixed English and Chinese semicolons."
  (should (equal (full-gtd-core--split-values "Project A; Project B；Project C; Project D")
                 '("Project A" "Project B" "Project C" "Project D"))))

(ert-deftest full-gtd-core-test-split-values-with-spaces ()
  "Test splitting values containing spaces."
  (should (equal (full-gtd-core--split-values "Website Redesign; Marketing Campaign")
                 '("Website Redesign" "Marketing Campaign"))))

(ert-deftest full-gtd-core-test-split-values-empty-input ()
  "Test splitting empty or nil input."
  (should (null (full-gtd-core--split-values nil)))
  (should (null (full-gtd-core--split-values "")))
  (should (null (full-gtd-core--split-values "   "))))

(ert-deftest full-gtd-core-test-split-values-extra-whitespace ()
  "Test splitting values with extra whitespace (trim verification)."
  (should (equal (full-gtd-core--split-values "  Project A  ;  Project B  ;  ")
                 '("Project A" "Project B"))))

(ert-deftest full-gtd-core-test-split-values-preserves-comma ()
  "Test that commas are preserved (not treated as separators)."
  (should (equal (full-gtd-core--split-values "Company, Inc.; Project B")
                 '("Company, Inc." "Project B"))))

;; Join values tests

(ert-deftest full-gtd-core-test-join-values ()
  "Test joining values with English semicolon."
  (should (string= (full-gtd-core--join-values '("Project A" "Project B"))
                   "Project A; Project B")))

(ert-deftest full-gtd-core-test-join-values-single ()
  "Test joining single value."
  (should (string= (full-gtd-core--join-values '("Project A"))
                   "Project A")))

(ert-deftest full-gtd-core-test-join-values-empty ()
  "Test joining empty list."
  (should (string= (full-gtd-core--join-values '())
                   "")))

;; Normalize project input tests

(ert-deftest full-gtd-core-test-normalize-project-input ()
  "Test normalizing project input with various separators."
  (should (string= (full-gtd-core--normalize-project-input "Project A；Project B；Project C")
                   "Project A; Project B; Project C")))

(ert-deftest full-gtd-core-test-normalize-project-input-nil ()
  "Test normalizing nil input."
  (should (null (full-gtd-core--normalize-project-input nil))))

(ert-deftest full-gtd-core-test-normalize-project-input-empty ()
  "Test normalizing empty input."
  (should (null (full-gtd-core--normalize-project-input ""))))

(ert-deftest full-gtd-core-test-normalize-project-input-whitespace-only ()
  "Test that whitespace-only input becomes nil (trim to empty)."
  (should (null (full-gtd-core--normalize-project-input "   ")))
  (should (null (full-gtd-core--normalize-project-input "\t\n  "))))

(ert-deftest full-gtd-core-test-normalize-project-input-trim ()
  "Test that surrounding whitespace is trimmed."
  (should (string= (full-gtd-core--normalize-project-input "  Project A; Project B  ")
                   "Project A; Project B")))

(ert-deftest full-gtd-core-test-split-values-mixed-separators-with-spaces ()
  "Test splitting values with mixed separators and surrounding whitespace."
  (should (equal (full-gtd-core--split-values "  Project A ; Project B ； Project C ;Project D  ")
                 '("Project A" "Project B" "Project C" "Project D"))))

(ert-deftest full-gtd-core-test-split-values-tabs-and-spaces ()
  "Test splitting values with tabs and mixed whitespace."
  (should (equal (full-gtd-core--split-values "Project A\t;\tProject B  ;\t\tProject C")
                 '("Project A" "Project B" "Project C"))))

(ert-deftest full-gtd-core-test-split-values-empty-between-separators ()
  "Test splitting with empty values between separators."
  (should (equal (full-gtd-core--split-values "Project A;; Project B；;Project C")
                 '("Project A" "Project B" "Project C"))))

(ert-deftest full-gtd-core-test-split-values-single-value-with-spaces ()
  "Test splitting single value with surrounding whitespace."
  (should (equal (full-gtd-core--split-values "  Single Project  ")
                 '("Single Project"))))

(ert-deftest full-gtd-core-test-join-values-preserves-internal-spaces ()
  "Test that join preserves internal spaces in values."
  (should (string= (full-gtd-core--join-values '("Project A" "B" "C"))
                   "Project A; B; C")))

(ert-deftest full-gtd-core-test-normalize-project-input-mixed-separators ()
  "Test normalizing input with mixed English and Chinese semicolons."
  (should (string= (full-gtd-core--normalize-project-input "Project A；Project B;Project C")
                   "Project A; Project B; Project C")))

(ert-deftest full-gtd-core-test-normalize-project-input-only-whitespace ()
  "Test that whitespace-only input becomes nil."
  (should (null (full-gtd-core--normalize-project-input "   \t  \n  "))))

(ert-deftest full-gtd-core-test-normalize-project-input-mixed-whitespace-separators ()
  "Test normalizing with tabs and spaces around separators."
  (should (string= (full-gtd-core--normalize-project-input "P1 \t ; \t P2 ；  P3")
                   "P1; P2; P3")))

;;; Multi-value property completion tests

(ert-deftest full-gtd-core-test-read-property-project-multi-value ()
  "Project type uses \`completing-read-multiple' and joins with semicolon."
  (cl-letf (((symbol-function 'completing-read-multiple)
             (lambda (_prompt _collection &rest _)
               '("ProjA" "ProjB" "ProjC")))
            ((symbol-function 'full-gtd-domain--collect-project-candidates)
             (lambda () '("ProjA" "ProjB" "ProjC"))))
    (let ((result (full-gtd-core-read-property-with-completion
                   "Project: " 'project)))
      (should (string= result "ProjA; ProjB; ProjC")))))

(ert-deftest full-gtd-core-test-read-property-context-single-value ()
  "Context type uses single \`completing-read', not crm."
  (cl-letf (((symbol-function 'completing-read)
             (lambda (_prompt _collection &rest _) "@office"))
            ((symbol-function 'completing-read-multiple)
             (lambda (&rest _) (error "Should not use crm for context")))
            ((symbol-function 'full-gtd-domain--collect-context-candidates)
             (lambda () '("@office" "@home"))))
    (let ((result (full-gtd-core-read-property-with-completion
                   "Context: " 'context)))
      (should (string= result "@office")))))

(ert-deftest full-gtd-core-test-read-property-horizon-l3-multi-value ()
  "L3 Area supports multiple values like Project."
  (cl-letf (((symbol-function 'completing-read-multiple)
             (lambda (_prompt _collection &rest _)
               '("Area1" "Area2")))
            ((symbol-function 'full-gtd-domain--collect-horizon-candidates)
             (lambda (_) '("Area1" "Area2" "Area3"))))
    (let ((result (full-gtd-core-read-property-with-completion
                   "Area: " 'l3)))
      (should (string= result "Area1; Area2")))))

(ert-deftest full-gtd-core-test-read-property-initial-multi-value-string ()
  "Multi-value initial input is a normalized string accepted by crm."
  (cl-letf (((symbol-function 'completing-read-multiple)
             (lambda (_prompt _collection &optional _predicate _require-match initial-input &rest _)
               (should (stringp initial-input))
               (should (string= initial-input "Old1; Old2"))
               '("Old1" "Old2" "New3")))
            ((symbol-function 'full-gtd-domain--collect-project-candidates)
             (lambda () '("Old1" "Old2" "New3"))))
    (should
     (string=
      (full-gtd-core-read-property-with-completion
       "Project: " 'project " Old1；Old2 ")
      "Old1; Old2; New3"))))

(ert-deftest full-gtd-core-test-read-property-empty-crm-returns-empty-string ()
  "Empty \`completing-read-multiple' returns empty string (not nil)."
  (cl-letf (((symbol-function 'completing-read-multiple)
             (lambda (&rest _) nil))
            ((symbol-function 'full-gtd-domain--collect-project-candidates)
             (lambda () '("ProjA"))))
    (let ((result (full-gtd-core-read-property-with-completion
                   "Project: " 'project)))
      (should (string= result "")))))

;;; Date hybrid input tests

(ert-deftest full-gtd-core-test-date-today-quick ()
  "Pressing 't' returns today's date string."
  (cl-letf (((symbol-function 'read-key) (lambda () ?t)))
    (let ((result (full-gtd-core-read-date 'schedule)))
      (should (string= result (format-time-string "%F"))))))

(ert-deftest full-gtd-core-test-date-tomorrow-quick ()
  "Pressing 'T' returns tomorrow's date string."
  (cl-letf (((symbol-function 'read-key) (lambda () ?T)))
    (let ((result (full-gtd-core-read-date 'schedule)))
      (should (string= result
                       (format-time-string "%F"
                                           (time-add (current-time) (* 24 3600))))))))

(ert-deftest full-gtd-core-test-date-custom-input ()
  "Typing numeric prefix then full date returns custom date string."
  (cl-letf (((symbol-function 'read-key) (lambda () ?2))
            ((symbol-function 'read-string) (lambda (&rest _) "2026-08-15")))
    (let ((result (full-gtd-core-read-date 'deadline)))
      (should (string= result "2026-08-15")))))

(ert-deftest full-gtd-core-test-get-set-entry-notes ()
  "Get and set entry notes using body manipulation."
  (let ((full-gtd-init-base-directory (make-temp-file "full-gtd-test-" t)))
    (unwind-protect
        (progn
          (write-region "* TODO Test\n:PROPERTIES:\n:ID: notes-1\n:END:\nInitial body\n"
                        nil
                        (expand-file-name "action.org" full-gtd-init-base-directory))
          (full-gtd-core-with-entry-at-id "notes-1" "action.org"
            (should (string= (full-gtd-core--get-entry-notes) "Initial body"))
            (full-gtd-core--set-entry-notes "Changed")
            (should (string= (full-gtd-core--get-entry-notes) "Changed"))
            (full-gtd-core--set-entry-notes "")
            (should (null (full-gtd-core--get-entry-notes)))))
      (let ((buf (get-file-buffer (expand-file-name "action.org" full-gtd-init-base-directory))))
        (when buf (kill-buffer buf)))
      (delete-directory full-gtd-init-base-directory t))))

(ert-deftest full-gtd-core-test-entry-notes-bounds-with-subheadings ()
  "Test that entry notes bounds correctly exclude subheadings."
  (let ((full-gtd-init-base-directory (make-temp-file "full-gtd-test-" t)))
    (unwind-protect
        (progn
          (write-region "* TODO Test entry with subheadings\n:PROPERTIES:\n:ID: notes-sub-1\n:END:\nThis is the main body text.\n\n** Subheading 1\nContent under subheading 1.\n\n** Subheading 2\nContent under subheading 2.\n"
                        nil
                        (expand-file-name "action.org" full-gtd-init-base-directory))
          (full-gtd-core-with-entry-at-id "notes-sub-1" "action.org"
            (let ((notes (full-gtd-core--get-entry-notes)))
              (should (string= (string-trim notes) "This is the main body text."))
              (should-not (string-match-p "Subheading 1" notes))
              (should-not (string-match-p "Subheading 2" notes)))))
      (let ((buf (get-file-buffer (expand-file-name "action.org" full-gtd-init-base-directory))))
        (when buf (kill-buffer buf)))
      (delete-directory full-gtd-init-base-directory t))))

(ert-deftest full-gtd-core-test-entry-notes-bounds-without-subheadings ()
  "Test that entry notes bounds work correctly for entries without subheadings."
  (let ((full-gtd-init-base-directory (make-temp-file "full-gtd-test-" t)))
    (unwind-protect
        (progn
          (write-region "* TODO Simple entry\n:PROPERTIES:\n:ID: notes-simple-1\n:END:\nThis is the main body text.\n\nSome more notes here.\n"
                        nil
                        (expand-file-name "action.org" full-gtd-init-base-directory))
          (full-gtd-core-with-entry-at-id "notes-simple-1" "action.org"
            (let ((notes (full-gtd-core--get-entry-notes)))
              (should (string= (string-trim notes) "This is the main body text.\n\nSome more notes here.")))))
      (let ((buf (get-file-buffer (expand-file-name "action.org" full-gtd-init-base-directory))))
        (when buf (kill-buffer buf)))
      (delete-directory full-gtd-init-base-directory t))))

(ert-deftest full-gtd-core-test-entry-notes-bounds-with-sibling ()
  "Test that entry notes bounds correctly stop before sibling heading."
  (let ((full-gtd-init-base-directory (make-temp-file "full-gtd-test-" t)))
    (unwind-protect
        (progn
          (write-region "* TODO First entry\n:PROPERTIES:\n:ID: notes-sibling-1\n:END:\nThis is the body of first entry.\n\n* TODO Second entry\n:PROPERTIES:\n:ID: notes-sibling-2\n:END:\nThis is second entry.\n"
                        nil
                        (expand-file-name "action.org" full-gtd-init-base-directory))
          (full-gtd-core-with-entry-at-id "notes-sibling-1" "action.org"
            (let ((notes (full-gtd-core--get-entry-notes)))
              (should (string= (string-trim notes) "This is the body of first entry."))
              (should-not (string-match-p "Second entry" notes)))))
      (let ((buf (get-file-buffer (expand-file-name "action.org" full-gtd-init-base-directory))))
        (when buf (kill-buffer buf)))
      (delete-directory full-gtd-init-base-directory t))))

(ert-deftest full-gtd-core-test-entry-notes-bounds-empty-notes ()
  "Test that empty notes return nil."
  (let ((full-gtd-init-base-directory (make-temp-file "full-gtd-test-" t)))
    (unwind-protect
        (progn
          (write-region "* TODO Empty notes entry\n:PROPERTIES:\n:ID: notes-empty-1\n:END:\n"
                        nil
                        (expand-file-name "action.org" full-gtd-init-base-directory))
          (full-gtd-core-with-entry-at-id "notes-empty-1" "action.org"
            (let ((notes (full-gtd-core--get-entry-notes)))
              (should (null notes)))))
      (let ((buf (get-file-buffer (expand-file-name "action.org" full-gtd-init-base-directory))))
        (when buf (kill-buffer buf)))
      (delete-directory full-gtd-init-base-directory t))))

(ert-deftest full-gtd-core-test-entry-notes-bounds-empty-with-sibling ()
  "Test that empty notes with sibling heading returns correct bounds."
  (let ((full-gtd-init-base-directory (make-temp-file "full-gtd-test-" t)))
    (unwind-protect
        (progn
          (write-region "* TODO Empty entry\n:PROPERTIES:\n:ID: empty-sib-1\n:END:\n* TODO Next sibling\n:PROPERTIES:\n:ID: empty-sib-2\n:END:\nBody of sibling\n"
                        nil
                        (expand-file-name "action.org" full-gtd-init-base-directory))
          (full-gtd-core-with-entry-at-id "empty-sib-1" "action.org"
            (let ((notes (full-gtd-core--get-entry-notes)))
              (should (null notes))
              (let ((bounds (full-gtd-core--entry-notes-bounds)))
                (should (< (car bounds) (cdr bounds)))
                (let ((content (buffer-substring (car bounds) (cdr bounds))))
                  (should (string= (string-trim content) ""))
                  (should-not (string-match-p "Next sibling" content))
                  (should-not (string-match-p "Body of sibling" content)))))))
      (let ((buf (get-file-buffer (expand-file-name "action.org" full-gtd-init-base-directory))))
        (when buf (kill-buffer buf)))
      (delete-directory full-gtd-init-base-directory t))))

(ert-deftest full-gtd-core-test-set-entry-notes-meta-end-same-line ()
  "Setting notes when :END: is directly followed by text inserts a newline."
  (let ((full-gtd-init-base-directory (make-temp-file "full-gtd-test-" t)))
    (unwind-protect
        (progn
          (write-region "* TODO Task\n:PROPERTIES:\n:ID: same-line-1\n:END:Existing text\n"
                        nil
                        (expand-file-name "action.org" full-gtd-init-base-directory))
          (full-gtd-core-with-entry-at-id "same-line-1" "action.org"
            (full-gtd-core--set-entry-notes "New body"))
          (let ((content (with-temp-buffer
                           (insert-file-contents
                            (expand-file-name "action.org" full-gtd-init-base-directory))
                           (buffer-string))))
            (should (string-match-p ":END:\nNew body\n" content))
            (should-not (string-match-p "Existing text" content))))
      (let ((buf (get-file-buffer (expand-file-name "action.org" full-gtd-init-base-directory))))
        (when buf (kill-buffer buf)))
      (delete-directory full-gtd-init-base-directory t))))

(provide 'full-gtd-core-test)

;;; full-gtd-core-test.el ends here
