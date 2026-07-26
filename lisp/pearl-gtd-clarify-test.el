;;; pearl-gtd-test-clarify.el --- Clarify phase tests for new flow  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 OverbearingPearl
;; Author: OverbearingPearl <OverbearingPearl@outlook.com>

;;; Commentary:

;; Tests for the clarify phase of inbox processing.

;;; Code:

(require 'ert)
(require 'pearl-gtd)
(require 'pearl-gtd-test)

(pearl-gtd-test-define-story pearl-gtd-test-clarify-user-skips-clarify-entirely
  "User processes to reference without clarifying."
  :setup (pearl-gtd-init-initialize)
  :files (("inbox.org" "* Raw task\n:PROPERTIES:\n:ID: c1\n:END:\n"))
  :mock (((symbol-function 'pearl-gtd-inbox--read-destination-key) (lambda (_headline) ?r))
         ((symbol-function 'pearl-gtd-inbox--clarify-entry)
          (lambda (_headline) (error "Should not be called when skipping clarify"))))
  :body (pearl-gtd-process-inbox)
  :asserts (progn
             (should (pearl-gtd-test-file-contains-p
                      (expand-file-name "reference.org" pearl-gtd-init-base-directory)
                      "* Raw task"))
             (should (pearl-gtd-test-inbox-empty-p pearl-gtd-init-base-directory)))
  :teardown nil)

(pearl-gtd-test-define-story pearl-gtd-test-clarify-user-clarifies-then-trash
  "User clarifies title and remarks, then trashes."
  :setup (pearl-gtd-init-initialize)
  :files (("inbox.org" "* Bad idea\n:PROPERTIES:\n:ID: c2\n:END:\n"))
  :mock (((symbol-function 'pearl-gtd-inbox--read-destination-key)
          (let ((calls 0))
            (lambda (_headline)
              (setq calls (1+ calls))
              (if (= calls 1) ?c ?t))))  ; First c (clarify), then t (trash)
         ((symbol-function 'pearl-gtd-inbox--clarify-entry)
          (lambda (_headline) (cons "Worse idea" "Actually terrible")))
         ((symbol-function 'pearl-gtd-inbox--collect-action-attrs)
          (lambda () (error "Should not collect attrs for trash"))))
  :body (pearl-gtd-process-inbox)
  :asserts (progn
             ;; Verify original moved to trash (inbox empty)
             (should (pearl-gtd-test-inbox-empty-p pearl-gtd-init-base-directory))
             ;; Clarified content should not appear in reference or actions
             (should-not (pearl-gtd-test-file-contains-p-bool
                          (expand-file-name "reference.org" pearl-gtd-init-base-directory)
                          "Worse idea")))
  :teardown nil)

(pearl-gtd-test-define-story pearl-gtd-test-clarify-user-clarifies-then-action
  "User clarifies then sends to action."
  :setup (pearl-gtd-init-initialize)
  :files (("inbox.org" "* Vague task\n:PROPERTIES:\n:ID: c3\n:END:\n"))
  :mock (((symbol-function 'pearl-gtd-inbox--read-destination-key)
          (let ((calls 0))
            (lambda (_headline)
              (setq calls (1+ calls))
              (if (= calls 1) ?c ?a))))  ; First c, then a
         ((symbol-function 'pearl-gtd-inbox--clarify-entry)
          (lambda (_headline) (cons "Clear action" "Important notes")))
         ((symbol-function 'pearl-gtd-inbox--collect-action-attrs)
          (lambda (&optional _staging-buffer _default-context _default-project)
            '((context . "@office") (schedule . "") (deadline . "")
              (delegate . "") (project . "")))))
  :body (pearl-gtd-process-inbox)
  :asserts (progn
             (should (pearl-gtd-test-file-contains-p
                      (expand-file-name "actions.org" pearl-gtd-init-base-directory)
                      "* TODO Clear action"))
             (should (pearl-gtd-test-file-contains-p
                      (expand-file-name "actions.org" pearl-gtd-init-base-directory)
                      "Important notes"))
             (should (pearl-gtd-test-file-contains-p
                      (expand-file-name "actions.org" pearl-gtd-init-base-directory)
                      ":office:")))
  :teardown nil)

(pearl-gtd-test-define-story pearl-gtd-test-clarify-user-quits-during-clarify
  "User quits (C-g) during clarify input."
  :setup (pearl-gtd-init-initialize)
  :files (("inbox.org" "* Task to clarify\n:PROPERTIES:\n:ID: c4\n:END:\n"))
  :mock (((symbol-function 'pearl-gtd-inbox--read-destination-key) (lambda (_headline) ?c))
         ((symbol-function 'pearl-gtd-inbox--clarify-entry)
          (lambda (_headline) (signal 'quit nil))))
  :body (condition-case nil
            (pearl-gtd-process-inbox)
          (quit (setq pearl-gtd-test-caught-error 'quit)))
  :asserts (progn
             (should (eq pearl-gtd-test-caught-error 'quit))
             (should (pearl-gtd-test-file-contains-p
                      (expand-file-name "inbox.org" pearl-gtd-init-base-directory)
                      "* Task to clarify")))  ; Still in inbox
  :teardown nil)

(pearl-gtd-test-define-story pearl-gtd-test-clarify-user-quits-during-destination
  "User quits at destination selection prompt."
  :setup (pearl-gtd-init-initialize)
  :files (("inbox.org" "* Task to route\n:PROPERTIES:\n:ID: c5\n:END:\n"))
  :mock (((symbol-function 'pearl-gtd-inbox--read-destination-key)
          (lambda (_headline) (signal 'quit nil)))
         ((symbol-function 'pearl-gtd-inbox--clarify-entry)
          (lambda (_headline) (cons nil nil))))
  :body (condition-case nil
            (pearl-gtd-process-inbox)
          (quit (setq pearl-gtd-test-caught-error 'quit)))
  :asserts (progn
             (should (eq pearl-gtd-test-caught-error 'quit))
             (should (pearl-gtd-test-file-contains-p
                      (expand-file-name "inbox.org" pearl-gtd-init-base-directory)
                      "* Task to route")))
  :teardown nil)

(provide 'pearl-gtd-test-clarify)

;;; pearl-gtd-test-clarify.el ends here
