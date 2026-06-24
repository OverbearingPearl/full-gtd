;;; pearl-gtd-core.el --- Core infrastructure for pearl-gtd  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 OverbearingPearl

;; Author: OverbearingPearl <OverbearingPearl@outlook.com>
;; Version: 0.1.0
;; Package-Requires: ((emacs "27.1") (org "9.4"))
;; Keywords: outlines, tools, convenience, productivity, gtd, org
;; URL: https://github.com/OverbearingPearl/pearl-gtd

;;; Commentary:

;; This file provides core infrastructure for Pearl-GTD, including
;; predicates, filters, and data collection utilities used by other modules.

;;; Code:

(require 'org)
(require 'pearl-gtd-init)

;;;; Predicates

(defun pearl-gtd-core-entry-todo-p ()
  "Return non-nil if current entry is a TODO item."
  (string= (org-get-todo-state) "TODO"))

(defun pearl-gtd-core-entry-context-p (contexts)
  "Return non-nil if current entry has any of CONTEXTS.
CONTEXTS is a list of normalized context strings (without @ prefix)."
  (when contexts
    (let ((tags (org-get-tags-at)))
      (cl-intersection tags contexts :test #'string=))))

(defun pearl-gtd-core-entry-scheduled-today-p ()
  "Return non-nil if current entry is scheduled for today."
  (let ((scheduled (org-entry-get nil "SCHEDULED"))
        (today-string (format-time-string "%Y-%m-%d")))
    (and scheduled (string-match-p today-string scheduled))))

(defun pearl-gtd-core-entry-delegated-p ()
  "Return non-nil if current entry is delegated."
  (org-entry-get nil "DELEGATED"))

(defun pearl-gtd-core-entry-overdue-p ()
  "Return non-nil if current entry is overdue."
  (let ((scheduled (org-entry-get nil "SCHEDULED")))
    (and scheduled (time-less-p (org-time-string-to-time scheduled) (current-time)))))

;;;; Filters

(defun pearl-gtd-core-filter-entries (file-path predicates)
  "Filter entries in FILE-PATH using PREDICATES.
PREDICATES is a list of predicate functions to apply.
Each predicate is called with no arguments in the context of the entry.
Return list of entries that pass all predicates."
  (let ((entries '()))
    (when (file-exists-p file-path)
      (with-temp-buffer
        (insert-file-contents file-path)
        (org-mode)
        (org-map-entries
         (lambda ()
           (when (cl-every (lambda (pred) (funcall pred)) predicates)
             (let* ((head (org-get-heading t t))
                    (id (org-entry-get nil "ID"))
                    (tags (org-get-tags-at))
                    (todo-state (org-get-todo-state))
                    (scheduled (org-entry-get nil "SCHEDULED"))
                    (delegated (org-entry-get nil "DELEGATED"))
                    (project (org-entry-get nil "PROJECT"))
                    (created (org-entry-get nil "CREATED")))
               ;; Attach ID as text property to headline for precise navigation
               (when id
                 (put-text-property 0 (length head) 'pearl-gtd-id id head))
               (push (list head
                          (mapconcat (lambda (c) (concat "@" c)) tags ",")
                          (or todo-state "")
                          (or scheduled "")
                          (or delegated "")
                          (or project "")
                          (or created ""))
                     entries))))
         nil nil)))
    (nreverse entries)))

;;;; Data Collection

(defun pearl-gtd-core-collect-contexts (file-path)
  "Collect all unique context tags from FILE-PATH."
  (let ((contexts '()))
    (when (file-exists-p file-path)
      (with-temp-buffer
        (insert-file-contents file-path)
        (org-mode)
        (org-map-entries
         (lambda ()
           (when (string= (org-get-todo-state) "TODO")
             (dolist (tag (org-get-tags-at))
               (cl-pushnew tag contexts :test #'string=))))
         nil nil)))
    (mapcar (lambda (c) (concat "@" c)) contexts)))

(provide 'pearl-gtd-core)

;;; pearl-gtd-core.el ends here
