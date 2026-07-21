;;; test-pearl-gtd-setup.el --- User stories: System initialization  -*- lexical-binding: t; -*-

;; License: MIT
;; URL: https://github.com/OverbearingPearl/pearl-gtd
;; Package-Requires: ((emacs "27.1") (ert "1.0") (cl-lib "0.5"))

;;; Commentary:

;; User stories for initializing the Pearl-GTD system.

;;; Code:

(require 'ert)
(require 'pearl-gtd-init)
(require 'test-pearl-gtd)

(test-pearl-gtd-define-story test-pearl-gtd-setup-user-initializes-gtd-system-for-first-time
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
             (should (file-exists-p (expand-file-name "actions.org" pearl-gtd-init-base-directory))))
  :teardown nil)

(test-pearl-gtd-define-story test-pearl-gtd-setup-user-reinitializes-without-losing-data
  "User reinitializes system, existing files are preserved."
  :setup (pearl-gtd-init-initialize)
  :files (("inbox.org" "* Existing task\n"))
  :mock nil
  :body (pearl-gtd-init-initialize)
  :asserts (progn
             (should (test-pearl-gtd-file-contains-p
                      (expand-file-name "inbox.org" pearl-gtd-init-base-directory)
                      "* Existing task")))
  :teardown nil)

(test-pearl-gtd-define-story test-pearl-gtd-setup-user-initializes-with-existing-files
  "User initializes system with existing files."
  :setup nil
  :files (("inbox.org" "* Existing task\n"))
  :mock nil
  :body (pearl-gtd-init-initialize)
  :asserts (progn
             (should (file-exists-p (expand-file-name "inbox.org" pearl-gtd-init-base-directory)))
             (should (test-pearl-gtd-file-contains-p
                      (expand-file-name "inbox.org" pearl-gtd-init-base-directory)
                      "* Existing task")))
  :teardown nil)

(test-pearl-gtd-define-story test-pearl-gtd-setup-user-initializes-with-two-existing-files
  "User initializes system with two existing files preserved."
  :setup nil
  :files (("inbox.org" "* Task one\n* Task two\n")
          ("reference.org" "* Existing reference\n"))
  :mock nil
  :body (pearl-gtd-init-initialize)
  :asserts (progn
             (should (test-pearl-gtd-file-contains-p
                      (expand-file-name "inbox.org" pearl-gtd-init-base-directory)
                      "* Task one"))
             (should (test-pearl-gtd-file-contains-p
                      (expand-file-name "inbox.org" pearl-gtd-init-base-directory)
                      "* Task two"))
             (should (test-pearl-gtd-file-contains-p
                      (expand-file-name "reference.org" pearl-gtd-init-base-directory)
                      "* Existing reference")))
  :teardown nil)

(provide 'test-pearl-gtd-setup)

;;; test-pearl-gtd-setup.el ends here
