;;; pearl-gtd-domain.el --- Domain layer: pure functions for GTD business rules  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 OverbearingPearl
;; Author: OverbearingPearl <OverbearingPearl@outlook.com>
;; Assisted-by: Kimi:kimi-k2.5, DeepSeek:deepseek-v3.2, Claude:claude-sonnet-4.6
;; URL: https://github.com/OverbearingPearl/pearl-gtd
;; SPDX-License-Identifier: MIT

;;; Commentary:

;; Pure computational layer (Domain layer) for GTD business logic.
;; No side effects, no IO, no user interaction.
;; All functions are deterministic and referentially transparent.
;; Trust boundary: internal state assumptions use cl-assert.

;;; Code:

(require 'cl-lib)
(require 'org)
(require 'pearl-gtd-init)

;;;; Data normalization (migrated from pearl-gtd-core)

(defun pearl-gtd-domain--split-values (value-string)
  "Split VALUE-STRING using semicolon separator.
Supports both English (;) and Chinese (；) semicolons.
Trim whitespace from each value.  Filter empty values.
Returns list of strings or nil."
  (when value-string
    (let ((normalized (replace-regexp-in-string "；" ";" value-string)))
      (seq-filter (lambda (s) (not (string-empty-p s)))
                  (mapcar #'string-trim
                          (split-string normalized ";"))))))

(defun pearl-gtd-domain--join-values (values)
  "Join VALUES list using English semicolon separator.
VALUES must be a list of strings.
Returns string."
  (cl-assert (listp values) t "Internal: join-values requires list")
  (mapconcat #'identity values "; "))

(defun pearl-gtd-domain--normalize-project-input (input)
  "Normalize project input: convert Chinese semicolons to English.
Trim whitespace from each value.  Returns nil if empty.
INPUT must be string or nil."
  (when input
    (cl-assert (stringp input) t "Internal: normalize-project-input requires string")
    (let ((trimmed (string-trim input)))
      (if (string-empty-p trimmed)
          nil
        (let ((values (pearl-gtd-domain--split-values trimmed)))
          (if values
              (pearl-gtd-domain--join-values values)
            nil))))))

;;;; Horizon validation (migrated from pearl-gtd-horizons)

(defun pearl-gtd-domain--check-hierarchy-constraint (existing-horizons level)
  "Check hierarchy constraint for setting LEVEL horizon.
EXISTING-HORIZONS is an alist of ((L3_AREA . val) (L4_GOAL . val) ...).
LEVEL must be a symbol: \\='area, \\='goal, \\='vision, \\='purpose,
or \\='principle.
Returns (VALID-P . ERROR-MSG)."
  (cl-assert (memq level '(area goal vision purpose principle))
             t "Internal: invalid horizon level %s" level)
  (let ((l4 (cdr (assoc 'L4_GOAL existing-horizons)))
        (l5 (cdr (assoc 'L5_VISION existing-horizons)))
        (l6-purpose (cdr (assoc 'L6_PURPOSE existing-horizons))))
    (pcase level
      ('area (cons t nil))
      ('goal (cons t nil))
      ('vision (if (and l4 (not (string= l4 "")))
                   (cons t nil)
                 (cons nil "L4 Goal must be set first")))
      ('purpose (if (and l5 (not (string= l5 "")))
                    (cons t nil)
                  (cons nil "L5 Vision must be set first")))
      ('principle (if (and l6-purpose
                           (cl-some (lambda (v) (not (string= v "")))
                                    (pearl-gtd-domain--split-values l6-purpose)))
                      (cons t nil)
                    (cons nil "L6 Purpose must be set first")))
      (_ (cons nil (format "Unknown horizon level: %s" level))))))

;;;; Planning workflow validation

(defun pearl-gtd-domain--planning-input-valid-p (proj-name purpose vision goal)
  "Validate PROJ-NAME, PURPOSE, VISION, and GOAL for required planning fields.
Returns (VALID-P . ERROR-MSG)."
  (cond
   ((or (null proj-name) (string= proj-name ""))
    (cons nil "Project name is required"))
   ((or (null purpose) (string= purpose ""))
    (cons nil "Purpose (L6) is required"))
   ((or (null vision) (string= vision ""))
    (cons nil "Vision (L5) is required"))
   ((or (null goal) (string= goal ""))
    (cons nil "Goal (L4) is required"))
   (t (cons t nil))))

(defun pearl-gtd-domain--require-next-action-p (actions-count)
  "Determine if forced next action is required.
ACTIONS-COUNT is number of next actions created.
Returns t if no next actions exist."
  (zerop actions-count))

;;;; Completion candidates collection

(defun pearl-gtd-domain--collect-unique-properties (property)
  "Collect all unique values for PROPERTY from action.org.
PROPERTY is a string like \"CONTEXT\", \"PROJECT\", \"DELEGATED\",
\"L3_AREA\", etc.
Returns list of strings."
  (let ((file-path (expand-file-name "action.org" pearl-gtd-init-base-directory))
        (values '()))
    (when (file-exists-p file-path)
      (with-temp-buffer
        (insert-file-contents file-path)
        (org-mode)
        (org-map-entries
         (lambda ()
           (let ((val (org-entry-get nil property)))
             (when val
               (dolist (v (pearl-gtd-domain--split-values val))
                 (when (and v (not (string= v "")))
                   (cl-pushnew v values :test #'string=))))))
         nil nil)))
    (sort values #'string<)))

(defun pearl-gtd-domain--collect-context-candidates ()
  "Collect context candidates (with @ prefix) from Org tags."
  (let ((contexts '())
        (files '("action.org" "someday.org" "reference.org" "inbox.org")))
    (dolist (file files)
      (let ((path (expand-file-name file pearl-gtd-init-base-directory)))
        (when (file-exists-p path)
          (with-temp-buffer
            (insert-file-contents path)
            (org-mode)
            (org-map-entries
             (lambda ()
               (dolist (tag (org-get-tags))
                 (unless (member tag org-todo-keywords-1)
                   (cl-pushnew tag contexts :test #'string=))))
             nil nil)))))
    (mapcar (lambda (c) (concat "@" c)) contexts)))

(defun pearl-gtd-domain--collect-project-candidates ()
  "Collect project candidates."
  (pearl-gtd-domain--collect-unique-properties "PROJECT"))

(defun pearl-gtd-domain--collect-delegate-candidates ()
  "Collect delegate candidates."
  (pearl-gtd-domain--collect-unique-properties "DELEGATED"))

(defun pearl-gtd-domain--collect-horizon-candidates (level)
  "Collect horizon candidates for LEVEL.
LEVEL is one of: L3_AREA, L4_GOAL, L5_VISION, L6_PURPOSE,
L6_PRINCIPLE."
  (cl-assert (member level '("L3_AREA" "L4_GOAL" "L5_VISION" "L6_PURPOSE" "L6_PRINCIPLE" "PRINCIPLE"))
             t "Internal: invalid horizon level %s" level)
  (pearl-gtd-domain--collect-unique-properties level))

(defun pearl-gtd-domain--compute-project-horizon (project level entries)
  "Compute PROJECT's horizon for LEVEL across ENTRIES.
ENTRIES is a list of (PROJECTS . HORIZONS) where PROJECTS is a list
of project names and HORIZONS is an alist mapping property names to
raw value strings.  Returns a list of deduplicated values, or nil if
no other action in PROJECT has LEVEL set.  Actions without LEVEL are
ignored."
  (cl-assert (stringp project) t "Internal: project must be string")
  (cl-assert (stringp level) t "Internal: level must be string")
  (let ((intersection :unset))
    (dolist (entry entries)
      (when (member project (car entry))
        (let* ((raw-value (cdr (assoc level (cdr entry))))
               (values (when (and raw-value (not (string= raw-value "")))
                         (delete-dups (pearl-gtd-domain--split-values raw-value)))))
          (when values
            (setq intersection
                  (if (eq intersection :unset)
                      values
                    (cl-intersection intersection values :test #'string=)))))))
    (unless (eq intersection :unset)
      intersection)))

(defun pearl-gtd-domain--combine-project-horizons (project-horizons)
  "Combine PROJECT-HORIZONS lists into a single deduplicated list.
Empty/nil inputs are ignored.  Returns nil if all inputs are empty."
  (let ((result '()))
    (dolist (horizons project-horizons)
      (dolist (value horizons)
        (cl-pushnew value result :test #'string=)))
    (nreverse result)))

(defun pearl-gtd-domain--compute-entry-horizons (projects entries)
  "Compute horizons for an entry belonging to PROJECTS.
For each of L3_AREA, L4_GOAL, L5_VISION, L6_PURPOSE, L6_PRINCIPLE:
single project → intersection of that project's other actions;
multiple projects → union of per-project horizons.
ENTRIES is a list of (PROJECTS . HORIZONS) entries used for horizon
computation.
Returns an alist of (PROPERTY . JOINED-VALUE) for non-empty levels.
PROJECTS may be nil (entry has no project), in which case all levels
are omitted from the result."
  (let ((result '()))
    (dolist (level '("L3_AREA" "L4_GOAL" "L5_VISION" "L6_PURPOSE" "L6_PRINCIPLE"))
      (let* ((per-project
              (mapcar (lambda (proj)
                        (pearl-gtd-domain--compute-project-horizon
                         proj level entries))
                      projects))
             (combined (pearl-gtd-domain--combine-project-horizons per-project)))
        (when combined
          (push (cons level (pearl-gtd-domain--join-values combined))
                result))))
    (nreverse result)))

(provide 'pearl-gtd-domain)

;;; pearl-gtd-domain.el ends here
