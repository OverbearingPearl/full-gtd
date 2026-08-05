;;; pearl-gtd-test-setup.el --- User stories: System initialization  -*- lexical-binding: t; -*-

;;; Commentary:

;; User stories for initializing the Pearl-GTD system.

;;; Code:

(require 'ert)
(require 'pearl-gtd-init)
(require 'pearl-gtd-test)

(pearl-gtd-test-define-story pearl-gtd-setup-test-user-initializes-gtd-system-for-first-time
  "User runs M-x pearl-gtd-init-initialize for the first time."
  :setup nil
  :files nil
  :mock nil
  :body (pearl-gtd-init-initialize)
  :asserts (progn
             (should (file-directory-p pearl-gtd-init-base-directory))
             (should (file-exists-p (expand-file-name "inbox.org" pearl-gtd-init-base-directory)))
             (should (file-exists-p (expand-file-name "reference.org" pearl-gtd-init-base-directory)))
             (should (file-exists-p (expand-file-name "someday.org" pearl-gtd-init-base-directory)))
             (should (file-exists-p (expand-file-name "action.org" pearl-gtd-init-base-directory))))
  :teardown nil)

(pearl-gtd-test-define-story pearl-gtd-setup-test-user-reinitializes-without-losing-data
  "User reinitializes system, existing files are preserved."
  :setup (pearl-gtd-init-initialize)
  :files (("inbox.org" "* Existing task\n"))
  :mock nil
  :body (pearl-gtd-init-initialize)
  :asserts (progn
             (should (pearl-gtd-test-file-contains-p
                      (expand-file-name "inbox.org" pearl-gtd-init-base-directory)
                      "* Existing task")))
  :teardown nil)

(pearl-gtd-test-define-story pearl-gtd-setup-test-user-initializes-with-existing-files
  "User initializes system with existing files."
  :setup nil
  :files (("inbox.org" "* Existing task\n"))
  :mock nil
  :body (pearl-gtd-init-initialize)
  :asserts (progn
             (should (file-exists-p (expand-file-name "inbox.org" pearl-gtd-init-base-directory)))
             (should (pearl-gtd-test-file-contains-p
                      (expand-file-name "inbox.org" pearl-gtd-init-base-directory)
                      "* Existing task")))
  :teardown nil)

(pearl-gtd-test-define-story pearl-gtd-setup-test-user-initializes-with-two-existing-files
  "User initializes system with two existing files preserved."
  :setup nil
  :files (("inbox.org" "* Task one\n* Task two\n")
          ("reference.org" "* Existing reference\n"))
  :mock nil
  :body (pearl-gtd-init-initialize)
  :asserts (progn
             (should (pearl-gtd-test-file-contains-p
                      (expand-file-name "inbox.org" pearl-gtd-init-base-directory)
                      "* Task one"))
             (should (pearl-gtd-test-file-contains-p
                      (expand-file-name "inbox.org" pearl-gtd-init-base-directory)
                      "* Task two"))
             (should (pearl-gtd-test-file-contains-p
                      (expand-file-name "reference.org" pearl-gtd-init-base-directory)
                      "* Existing reference")))
  :teardown nil)

(provide 'pearl-gtd-setup-test)

;;; pearl-gtd-setup-test.el ends here
