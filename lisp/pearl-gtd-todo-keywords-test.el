;;; pearl-gtd-todo-keywords-test.el --- Tests for custom org-todo-keywords  -*- lexical-binding: t; -*-

;;; Commentary:

;; Regression tests ensuring production code works with custom
;; org-todo-keywords (uppercase, lowercase, and multi-sequence).
;; These tests bind org-todo-keywords before exercising the code
;; paths that previously hardcoded "TODO"/"DONE".

;;; Code:

(require 'ert)
(require 'pearl-gtd)
(require 'pearl-gtd-test)

(ert-deftest pearl-gtd-todo-keywords-test-default-todo-keyword ()
  "Helper returns first not-done keyword, falling back to TODO."
  (let ((org-not-done-keywords '("NEXT"))
        (org-done-keywords '("DONE")))
    (should (string= (pearl-gtd-core--default-todo-keyword) "NEXT")))
  (let ((org-not-done-keywords nil))
    (should (string= (pearl-gtd-core--default-todo-keyword) "TODO"))))

(ert-deftest pearl-gtd-todo-keywords-test-collect-contexts-custom ()
  "collect-contexts respects custom NOT_DONE keywords."
  (let* ((org-todo-keywords '((sequence "TODO" "DOING" "DONE")))
         (pearl-gtd-init-base-directory (make-temp-file "pearl-gtd-test-" t)))
    (unwind-protect
        (progn
          (write-region "* TODO Office :office:\n:PROPERTIES:\n:ID: t1\n:END:\n* DOING Home :home:\n:PROPERTIES:\n:ID: t2\n:END:\n* DONE Finished :done-ctx:\n:PROPERTIES:\n:ID: t3\n:END:\n"
                        nil
                        (expand-file-name "action.org" pearl-gtd-init-base-directory))
          (let ((contexts (pearl-gtd-core-collect-contexts
                           (expand-file-name "action.org" pearl-gtd-init-base-directory))))
            (should (member "@office" contexts))
            (should (member "@home" contexts))
            (should-not (member "@done-ctx" contexts))))
      (delete-directory pearl-gtd-init-base-directory t))))

(ert-deftest pearl-gtd-todo-keywords-test-context-candidates-filter-todo ()
  "domain-context-candidates excludes custom todo keywords from tags."
  (let* ((org-todo-keywords '((sequence "TODO" "DOING" "DONE")))
         (pearl-gtd-init-base-directory (make-temp-file "pearl-gtd-test-" t)))
    (unwind-protect
        (progn
          (write-region "* TODO Task :office:\n:PROPERTIES:\n:ID: t1\n:END:\n* DOING Another :DOING:\n:PROPERTIES:\n:ID: t2\n:END:\n"
                        nil
                        (expand-file-name "action.org" pearl-gtd-init-base-directory))
          (let ((candidates (pearl-gtd-domain--collect-context-candidates)))
            (should (member "@office" candidates))
            (should-not (member "@DOING" candidates))))
      (delete-directory pearl-gtd-init-base-directory t))))

(ert-deftest pearl-gtd-todo-keywords-test-multi-sequence-lowercase ()
  "Lowercase multi-sequence workflows are handled correctly."
  (let* ((org-todo-keywords '((sequence "todo" "doing" "done")
                              (sequence "waiting" "cancelled")))
         (pearl-gtd-init-base-directory (make-temp-file "pearl-gtd-test-" t)))
    (unwind-protect
        (progn
          (write-region "* todo Office :office:\n:PROPERTIES:\n:ID: t1\n:END:\n* waiting Home :home:\n:PROPERTIES:\n:ID: t2\n:END:\n* done Finished :alex:\n:PROPERTIES:\n:ID: t3\n:END:\n"
                        nil
                        (expand-file-name "action.org" pearl-gtd-init-base-directory))
          (let ((contexts (pearl-gtd-core-collect-contexts
                           (expand-file-name "action.org" pearl-gtd-init-base-directory))))
            (should (member "@office" contexts))
            (should (member "@home" contexts))
            (should-not (member "@alex" contexts)))
          (let ((org-not-done-keywords '("todo" "doing" "waiting")))
            (should (string= (pearl-gtd-core--default-todo-keyword) "todo"))))
      (delete-directory pearl-gtd-init-base-directory t))))

(provide 'pearl-gtd-todo-keywords-test)

;;; pearl-gtd-todo-keywords-test.el ends here
