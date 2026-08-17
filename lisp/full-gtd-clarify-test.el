;;; full-gtd-test-clarify.el --- Clarify phase tests for new flow  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 OverbearingPearl
;; Author: OverbearingPearl <OverbearingPearl@outlook.com>

;;; Commentary:

;; Tests for the clarify phase of inbox processing.

;;; Code:

(require 'ert)
(require 'full-gtd)
(require 'full-gtd-test)

(full-gtd-test-define-story full-gtd-clarify-test-user-skips-clarify-entirely
  "User processes to reference without clarifying."
  :setup (full-gtd-init-initialize)
  :files (("inbox.org" "* Raw task\n:PROPERTIES:\n:ID: c1\n:END:\n"))
  :mock (((symbol-function 'full-gtd-inbox--read-destination-key) (lambda (_headline) ?r))
         ((symbol-function 'full-gtd-inbox--clarify-entry)
          (lambda (_current-notes) (error "Should not be called when skipping clarify"))))
  :body (full-gtd-process-inbox)
  :asserts (progn
             (should (full-gtd-test-file-contains-p
                      (expand-file-name "reference.org" full-gtd-init-base-directory)
                      "* Raw task"))
             (should (full-gtd-test-inbox-empty-p full-gtd-init-base-directory)))
  :teardown nil)

(full-gtd-test-define-story full-gtd-clarify-test-user-clarifies-then-trash
  "User clarifies title and notes, then trashes."
  :setup (full-gtd-init-initialize)
  :files (("inbox.org" "* Bad idea\n:PROPERTIES:\n:ID: c2\n:END:\n"))
  :mock (((symbol-function 'full-gtd-inbox--read-destination-key)
          (let ((calls 0))
            (lambda (_headline)
              (setq calls (1+ calls))
              (if (= calls 1) ?c ?t))))  ; First c (clarify), then t (trash)
         ((symbol-function 'full-gtd-inbox--clarify-entry)
          (lambda (_headline &optional _current-notes) (cons "Worse idea" "Actually terrible")))
         ((symbol-function 'full-gtd-inbox--collect-action-attrs)
          (lambda () (error "Should not collect attrs for trash"))))
  :body (full-gtd-process-inbox)
  :asserts (progn
             ;; Verify original moved to trash (inbox empty)
             (should (full-gtd-test-inbox-empty-p full-gtd-init-base-directory))
             ;; Clarified content should not appear in reference or actions
             (should-not (full-gtd-test-file-contains-p-bool
                          (expand-file-name "reference.org" full-gtd-init-base-directory)
                          "Worse idea")))
  :teardown nil)

(full-gtd-test-define-story full-gtd-clarify-test-user-clarifies-then-action
  "User clarifies then sends to action."
  :setup (full-gtd-init-initialize)
  :files (("inbox.org" "* Vague task\n:PROPERTIES:\n:ID: c3\n:END:\n"))
  :mock (((symbol-function 'full-gtd-inbox--read-destination-key)
          (let ((calls 0))
            (lambda (_headline)
              (setq calls (1+ calls))
              (if (= calls 1) ?c ?a))))  ; First c, then a
         ((symbol-function 'full-gtd-inbox--clarify-entry)
          (lambda (_headline &optional _current-notes) (cons "Clear action" "Important notes")))
         ((symbol-function 'full-gtd-inbox--collect-action-attrs)
          (lambda (&optional _staging-buffer _default-context _default-project)
            '((context . "@office") (schedule . "") (deadline . "")
              (delegate . "") (project . "")))))
  :body (full-gtd-process-inbox)
  :asserts (progn
             (should (full-gtd-test-file-contains-p
                      (expand-file-name "action.org" full-gtd-init-base-directory)
                      "* TODO Clear action"))
             (should (full-gtd-test-file-contains-p
                      (expand-file-name "action.org" full-gtd-init-base-directory)
                      "Important notes"))
             (should (full-gtd-test-file-contains-p
                      (expand-file-name "action.org" full-gtd-init-base-directory)
                      ":office:")))
  :teardown nil)

(full-gtd-test-define-story full-gtd-clarify-test-user-clears-notes-with-second-clarify
  "User can clear existing notes by pressing c again and deleting the default text."
  :setup (full-gtd-init-initialize)
  :files (("inbox.org" "* Task\n:PROPERTIES:\n:ID: c7\n:END:\n"))
  :mock (((symbol-function 'full-gtd-inbox--read-destination-key)
          (let ((calls 0))
            (lambda (_headline)
              (setq calls (1+ calls))
              (if (<= calls 2) ?c ?r))))
         ((symbol-function 'full-gtd-inbox--clarify-entry)
          (let ((first  t))
            (lambda (_headline &optional _current-notes)
              (if first
                  (progn
                    (setq first nil)
                    (cons nil "Old note"))
                (cons nil "")))))
         ((symbol-function 'full-gtd-inbox--collect-action-attrs)
          (lambda (&optional _staging-buffer _default-context _default-project)
            '((context . "") (schedule . "") (deadline . "")
              (delegate . "") (project . "")))))
  :body (full-gtd-process-inbox)
  :asserts (progn
             (should (full-gtd-test-file-lacks-p
                      (expand-file-name "reference.org" full-gtd-init-base-directory)
                      "Old note"))
             (should (full-gtd-test-inbox-empty-p full-gtd-init-base-directory)))
  :teardown nil)

(full-gtd-test-define-story full-gtd-clarify-test-user-quits-during-clarify
  "User quits (C-g) during clarify input."
  :setup (full-gtd-init-initialize)
  :files (("inbox.org" "* Task to clarify\n:PROPERTIES:\n:ID: c4\n:END:\n"))
  :mock (((symbol-function 'full-gtd-inbox--read-destination-key) (lambda (_headline) ?c))
         ((symbol-function 'full-gtd-inbox--clarify-entry)
          (lambda (_headline &optional _current-notes) (signal 'quit nil))))
  :body (condition-case nil
            (full-gtd-process-inbox)
          (quit (setq full-gtd-test-caught-error 'quit)))
  :asserts (progn
             (should (eq full-gtd-test-caught-error 'quit))
             (should (full-gtd-test-file-contains-p
                      (expand-file-name "inbox.org" full-gtd-init-base-directory)
                      "* Task to clarify")))  ; Still in inbox
  :teardown nil)

(full-gtd-test-define-story full-gtd-clarify-test-user-quits-during-destination
  "User quits at destination selection prompt."
  :setup (full-gtd-init-initialize)
  :files (("inbox.org" "* Task to route\n:PROPERTIES:\n:ID: c5\n:END:\n"))
  :mock (((symbol-function 'full-gtd-inbox--read-destination-key)
          (lambda (_headline) (signal 'quit nil)))
         ((symbol-function 'full-gtd-inbox--clarify-entry)
          (lambda (_headline) (cons nil nil))))
  :body (condition-case nil
            (full-gtd-process-inbox)
          (quit (setq full-gtd-test-caught-error 'quit)))
  :asserts (progn
             (should (eq full-gtd-test-caught-error 'quit))
             (should (full-gtd-test-file-contains-p
                      (expand-file-name "inbox.org" full-gtd-init-base-directory)
                      "* Task to route")))
  :teardown nil)

(provide 'full-gtd-clarify-test)

;;; full-gtd-clarify-test.el ends here
