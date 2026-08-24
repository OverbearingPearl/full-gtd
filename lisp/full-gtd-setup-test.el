;;; full-gtd-setup-test.el --- User stories: System initialization  -*- lexical-binding: t; -*-

;;; Commentary:

;; User stories for initializing the Full-GTD system.

;;; Code:

(require 'ert)
(require 'full-gtd)
(require 'full-gtd-test-utils)

(full-gtd-test-define-story full-gtd-setup-test-user-initializes-gtd-system-for-first-time
  "User runs M-x full-gtd-init-initialize for the first time."
  :setup nil
  :files nil
  :mock nil
  :body (full-gtd-init-initialize)
  :asserts (progn
             (should (file-directory-p full-gtd-init-base-directory))
             (should (file-exists-p (expand-file-name "inbox.org" full-gtd-init-base-directory)))
             (should (file-exists-p (expand-file-name "reference.org" full-gtd-init-base-directory)))
             (should (file-exists-p (expand-file-name "someday.org" full-gtd-init-base-directory)))
             (should (file-exists-p (expand-file-name "action.org" full-gtd-init-base-directory))))
  :teardown nil)

(full-gtd-test-define-story full-gtd-setup-test-user-reinitializes-without-losing-data
  "User reinitializes system, existing files are preserved."
  :setup (full-gtd-init-initialize)
  :files (("inbox.org" "* Existing task\n"))
  :mock nil
  :body (full-gtd-init-initialize)
  :asserts (progn
             (should (full-gtd-test-file-contains-p
                      (expand-file-name "inbox.org" full-gtd-init-base-directory)
                      "* Existing task")))
  :teardown nil)

(full-gtd-test-define-story full-gtd-setup-test-user-initializes-with-existing-files
  "User initializes system with existing files."
  :setup nil
  :files (("inbox.org" "* Existing task\n"))
  :mock nil
  :body (full-gtd-init-initialize)
  :asserts (progn
             (should (file-exists-p (expand-file-name "inbox.org" full-gtd-init-base-directory)))
             (should (full-gtd-test-file-contains-p
                      (expand-file-name "inbox.org" full-gtd-init-base-directory)
                      "* Existing task")))
  :teardown nil)

(full-gtd-test-define-story full-gtd-setup-test-user-initializes-with-two-existing-files
  "User initializes system with two existing files preserved."
  :setup nil
  :files (("inbox.org" "* Task one\n* Task two\n")
          ("reference.org" "* Existing reference\n"))
  :mock nil
  :body (full-gtd-init-initialize)
  :asserts (progn
             (should (full-gtd-test-file-contains-p
                      (expand-file-name "inbox.org" full-gtd-init-base-directory)
                      "* Task one"))
             (should (full-gtd-test-file-contains-p
                      (expand-file-name "inbox.org" full-gtd-init-base-directory)
                      "* Task two"))
             (should (full-gtd-test-file-contains-p
                      (expand-file-name "reference.org" full-gtd-init-base-directory)
                      "* Existing reference")))
  :teardown nil)

(provide 'full-gtd-setup-test)

;;; full-gtd-setup-test.el ends here
