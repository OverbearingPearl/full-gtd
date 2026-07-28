;;; pearl-gtd-state-test.el --- Unit tests for pearl-gtd-state  -*- lexical-binding: t; -*-

;;; Commentary:

;; Unit tests for transactional state layer.

;;; Code:

(require 'ert)
(require 'pearl-gtd-state)
(require 'pearl-gtd-test)

(ert-deftest pearl-gtd-state-test-with-file-buffer-creates-and-saves ()
  "with-file-buffer creates file and saves modifications."
  (let ((pearl-gtd-init-base-directory (make-temp-file "pearl-gtd-test-" t)))
    (unwind-protect
        (progn
          (pearl-gtd-state--with-file-buffer "actions.org"
            (insert "* TODO Test\n"))
          (should (file-exists-p (expand-file-name "actions.org" pearl-gtd-init-base-directory)))
          (should (pearl-gtd-test-file-contains-p-bool
                   (expand-file-name "actions.org" pearl-gtd-init-base-directory)
                   "* TODO Test")))
      (delete-directory pearl-gtd-init-base-directory t))))

(ert-deftest pearl-gtd-state-test-transaction-commits-on-success ()
  "Transaction saves changes when body succeeds."
  (let ((pearl-gtd-init-base-directory (make-temp-file "pearl-gtd-test-" t)))
    (unwind-protect
        (let ((file (expand-file-name "actions.org" pearl-gtd-init-base-directory)))
          (write-region "* TODO Before\n" nil file)
          (pearl-gtd-state--with-transaction '("actions.org")
            (pearl-gtd-state--with-file-buffer "actions.org"
              (goto-char (point-max))
              (insert "* TODO After\n")))
          (should (pearl-gtd-test-file-contains-p-bool file "* TODO After")))
      (delete-directory pearl-gtd-init-base-directory t))))

(ert-deftest pearl-gtd-state-test-transaction-rolls-back-on-error ()
  "Transaction restores original file content when body signals error."
  (let ((pearl-gtd-init-base-directory (make-temp-file "pearl-gtd-test-" t)))
    (unwind-protect
        (let ((file (expand-file-name "actions.org" pearl-gtd-init-base-directory)))
          (write-region "* TODO Original\n" nil file)
          (should-error
           (pearl-gtd-state--with-transaction '("actions.org")
             (pearl-gtd-state--with-file-buffer "actions.org"
               (goto-char (point-max))
               (insert "* TODO Modified\n")
               (error "Simulated failure"))))
          (should (pearl-gtd-test-file-contains-p-bool file "* TODO Original"))
          (should-not (pearl-gtd-test-file-contains-p-bool file "* TODO Modified"))
          (should-not (get-file-buffer file)))
      (delete-directory pearl-gtd-init-base-directory t))))

(ert-deftest pearl-gtd-state-test-transaction-rolls-back-on-quit ()
  "Transaction restores original file content when body signals quit."
  (let ((pearl-gtd-init-base-directory (make-temp-file "pearl-gtd-test-" t)))
    (unwind-protect
        (let ((file (expand-file-name "actions.org" pearl-gtd-init-base-directory)))
          (write-region "* TODO Original\n" nil file)
          (condition-case nil
              (pearl-gtd-state--with-transaction '("actions.org")
                (pearl-gtd-state--with-file-buffer "actions.org"
                  (insert "* TODO Modified\n")
                  (signal 'quit nil)))
            (quit nil))
          (should (pearl-gtd-test-file-contains-p-bool file "* TODO Original"))
          (should-not (pearl-gtd-test-file-contains-p-bool file "* TODO Modified")))
      (delete-directory pearl-gtd-init-base-directory t))))

(ert-deftest pearl-gtd-state-test-entry-at-id-found ()
  "with-entry-at-id navigates to correct entry."
  (let ((pearl-gtd-init-base-directory (make-temp-file "pearl-gtd-test-" t)))
    (unwind-protect
        (progn
          (write-region "* TODO Task 1\n:PROPERTIES:\n:ID: id-1\n:END:\n* TODO Task 2\n:PROPERTIES:\n:ID: id-2\n:END:\n"
                        nil
                        (expand-file-name "actions.org" pearl-gtd-init-base-directory))
          (pearl-gtd-state--with-entry-at-id "id-2" "actions.org"
            (should (looking-at-p "\\*+ TODO Task 2"))))
      (delete-directory pearl-gtd-init-base-directory t))))

(ert-deftest pearl-gtd-state-test-entry-at-id-missing ()
  "with-entry-at-id signals error when ID not found."
  (let ((pearl-gtd-init-base-directory (make-temp-file "pearl-gtd-test-" t)))
    (unwind-protect
        (progn
          (write-region "* TODO Task\n:PROPERTIES:\n:ID: id-1\n:END:\n"
                        nil
                        (expand-file-name "actions.org" pearl-gtd-init-base-directory))
          (should-error
           (pearl-gtd-state--with-entry-at-id "missing-id" "actions.org"
             (ignore))))
      (delete-directory pearl-gtd-init-base-directory t))))

(provide 'pearl-gtd-state-test)

;;; pearl-gtd-state-test.el ends here
