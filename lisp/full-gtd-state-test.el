;;; full-gtd-state-test.el --- Unit tests for full-gtd-state  -*- lexical-binding: t; -*-

;;; Commentary:

;; Unit tests for transactional state layer.

;;; Code:

(require 'ert)
(require 'full-gtd-state)
(require 'full-gtd-test)

(ert-deftest full-gtd-state-test-with-file-buffer-creates-and-saves ()
  "With-file-buffer creates file and saves modifications."
  (let ((full-gtd-init-base-directory (make-temp-file "full-gtd-test-" t)))
    (unwind-protect
        (progn
          (full-gtd-state--with-file-buffer "action.org"
            (insert "* TODO Test\n"))
          (should (file-exists-p (expand-file-name "action.org" full-gtd-init-base-directory)))
          (should (full-gtd-test-file-contains-p-bool
                   (expand-file-name "action.org" full-gtd-init-base-directory)
                   "* TODO Test")))
      (let ((buf (get-file-buffer (expand-file-name "action.org" full-gtd-init-base-directory))))
        (when buf (kill-buffer buf)))
      (delete-directory full-gtd-init-base-directory t))))

(ert-deftest full-gtd-state-test-transaction-commits-on-success ()
  "Transaction saves changes when body succeeds."
  (let ((full-gtd-init-base-directory (make-temp-file "full-gtd-test-" t)))
    (unwind-protect
        (let ((file (expand-file-name "action.org" full-gtd-init-base-directory)))
          (write-region "* TODO Before\n" nil file)
          (full-gtd-state--with-transaction '("action.org")
            (full-gtd-state--with-file-buffer "action.org"
              (goto-char (point-max))
              (insert "* TODO After\n")))
          (should (full-gtd-test-file-contains-p-bool file "* TODO After")))
      (let ((buf (get-file-buffer (expand-file-name "action.org" full-gtd-init-base-directory))))
        (when buf (kill-buffer buf)))
      (delete-directory full-gtd-init-base-directory t))))

(ert-deftest full-gtd-state-test-transaction-rolls-back-on-error ()
  "Transaction restores original file content when body signals error."
  (let ((full-gtd-init-base-directory (make-temp-file "full-gtd-test-" t)))
    (unwind-protect
        (let ((file (expand-file-name "action.org" full-gtd-init-base-directory)))
          (write-region "* TODO Original\n" nil file)
          (should-error
           (full-gtd-state--with-transaction '("action.org")
             (full-gtd-state--with-file-buffer "action.org"
               (goto-char (point-max))
               (insert "* TODO Modified\n")
               (error "Simulated failure"))))
          (should (full-gtd-test-file-contains-p-bool file "* TODO Original"))
          (should-not (full-gtd-test-file-contains-p-bool file "* TODO Modified"))
          (should-not (get-file-buffer file)))
      (let ((buf (get-file-buffer (expand-file-name "action.org" full-gtd-init-base-directory))))
        (when buf (kill-buffer buf)))
      (delete-directory full-gtd-init-base-directory t))))

(ert-deftest full-gtd-state-test-transaction-rolls-back-on-quit ()
  "Transaction restores original file content when body signals quit."
  (let ((full-gtd-init-base-directory (make-temp-file "full-gtd-test-" t)))
    (unwind-protect
        (let ((file (expand-file-name "action.org" full-gtd-init-base-directory)))
          (write-region "* TODO Original\n" nil file)
          (condition-case nil
              (full-gtd-state--with-transaction '("action.org")
                (full-gtd-state--with-file-buffer "action.org"
                  (insert "* TODO Modified\n")
                  (signal 'quit nil)))
            (quit nil))
          (should (full-gtd-test-file-contains-p-bool file "* TODO Original"))
          (should-not (full-gtd-test-file-contains-p-bool file "* TODO Modified")))
      (let ((buf (get-file-buffer (expand-file-name "action.org" full-gtd-init-base-directory))))
        (when buf (kill-buffer buf)))
      (delete-directory full-gtd-init-base-directory t))))

(ert-deftest full-gtd-state-test-entry-at-id-found ()
  "With-entry-at-id navigates to correct entry."
  (let ((full-gtd-init-base-directory (make-temp-file "full-gtd-test-" t)))
    (unwind-protect
        (progn
          (write-region "* TODO Task 1\n:PROPERTIES:\n:ID: id-1\n:END:\n* TODO Task 2\n:PROPERTIES:\n:ID: id-2\n:END:\n"
                        nil
                        (expand-file-name "action.org" full-gtd-init-base-directory))
          (full-gtd-state--with-entry-at-id "id-2" "action.org"
            (should (looking-at-p "\\*+ TODO Task 2"))))
      (let ((buf (get-file-buffer (expand-file-name "action.org" full-gtd-init-base-directory))))
        (when buf (kill-buffer buf)))
      (delete-directory full-gtd-init-base-directory t))))

(ert-deftest full-gtd-state-test-entry-at-id-missing ()
  "With-entry-at-id signals error when ID not found."
  (let ((full-gtd-init-base-directory (make-temp-file "full-gtd-test-" t)))
    (unwind-protect
        (progn
          (write-region "* TODO Task\n:PROPERTIES:\n:ID: id-1\n:END:\n"
                        nil
                        (expand-file-name "action.org" full-gtd-init-base-directory))
          (should-error
           (full-gtd-state--with-entry-at-id "missing-id" "action.org"
             (ignore))
           :type 'error))
      (let ((buf (get-file-buffer (expand-file-name "action.org" full-gtd-init-base-directory))))
        (when buf (kill-buffer buf)))
      (delete-directory full-gtd-init-base-directory t))))

(provide 'full-gtd-state-test)

;;; full-gtd-state-test.el ends here
