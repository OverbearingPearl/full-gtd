;;; pearl-gtd-ui.el --- UI utilities for Pearl-GTD  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 OverbearingPearl
;; Author: OverbearingPearl <OverbearingPearl@outlook.com>
;; Assisted-by: Kimi:kimi-k2.5, DeepSeek:deepseek-v3.2, Claude:claude-sonnet-4.6
;; URL: https://github.com/OverbearingPearl/pearl-gtd
;; SPDX-License-Identifier: MIT

;;; Commentary:

;; Shared UI primitives: table rendering, field escaping, text properties.
;; Pure presentation layer, no business logic.

;;; Code:

(defun pearl-gtd-ui--escape-field (field)
  "Escape pipe characters in FIELD for org-table display."
  (replace-regexp-in-string "|" "\\\\vert{}" field))

(defun pearl-gtd-ui--insert-table-row (headline id file fields &optional project-p)
  "Insert a table row with text properties.
HEADLINE is the display text (escaped).
ID is the entry ID (nil for project rows).
FILE is the source file.
FIELDS is a list of remaining column values (strings or numbers).
If PROJECT-P is non-nil, attach `pearl-gtd-project' property instead of ID."
  (let ((headline-escaped (pearl-gtd-ui--escape-field headline)))
    (insert "| ")
    (let ((start (point)))
      (insert headline-escaped)
      (if project-p
          (put-text-property start (point) 'pearl-gtd-project headline)
        (progn
          (put-text-property start (point) 'pearl-gtd-id id)
          (put-text-property start (point) 'pearl-gtd-file file))))
    (dolist (field fields)
      (insert " | " (if field (format "%s" field) "")))
    (insert " |\n")))

(defun pearl-gtd-ui--anchor-at-point ()
  "Return anchor for current line: (ID-FILE PROJECT LINE).
ID-FILE is (id . file) for task rows; PROJECT is project name for
project rows; LINE is current 1-based line number.
Return nil if current line is not a table data row."
  (save-excursion
    (beginning-of-line)
    (if (not (looking-at "|"))
        nil
      (let ((end (line-end-position))
            (id nil)
            (file nil)
            (project nil))
        (while (and (< (point) end)
                    (not (or (and id file) project)))
          (unless id
            (setq id (get-text-property (point) 'pearl-gtd-id)))
          (unless file
            (setq file (get-text-property (point) 'pearl-gtd-file)))
          (unless project
            (setq project (get-text-property (point) 'pearl-gtd-project)))
          (forward-char 1))
        (when (or (and id file) project)
          (list (and id file (cons id file))
                project
                (line-number-at-pos)))))))

(defun pearl-gtd-ui--goto-row (predicate)
  "Go to first table row where PREDICATE matches a text-property position.
PREDICATE is called with buffer position.
Return non-nil if found."
  (let ((found nil))
    (save-excursion
      (goto-char (point-min))
      (while (and (not found) (not (eobp)))
        (let ((end (line-end-position))
              (pos (point)))
          (while (and (< pos end) (not found))
            (when (funcall predicate pos)
              (setq found (line-beginning-position)))
            (setq pos (1+ pos))))
        (unless found
          (forward-line 1))))
    (when found
      (goto-char found)
      t)))

(defun pearl-gtd-ui--goto-entry (id file)
  "Go to row containing entry ID in FILE."
  (pearl-gtd-ui--goto-row
   (lambda (pos)
     (and (equal (get-text-property pos 'pearl-gtd-id) id)
          (equal (get-text-property pos 'pearl-gtd-file) file)))))

(defun pearl-gtd-ui--goto-project (project)
  "Go to row containing project PROJECT."
  (pearl-gtd-ui--goto-row
   (lambda (pos)
     (equal (get-text-property pos 'pearl-gtd-project) project))))

(defun pearl-gtd-ui--line-data-p ()
  "Return non-nil if current line has task or project text property."
  (save-excursion
    (let ((end (line-end-position))
          (pos (line-beginning-position)))
      (catch 'found
        (while (< pos end)
          (when (or (get-text-property pos 'pearl-gtd-id)
                    (get-text-property pos 'pearl-gtd-project))
            (throw 'found t))
          (setq pos (1+ pos)))
        nil))))

(defun pearl-gtd-ui--goto-line (line)
  "Go to LINE; if not a table data row, go to nearest data row.
Return non-nil if a table data row was found."
  (goto-char (point-min))
  (forward-line (1- line))
  (if (pearl-gtd-ui--line-data-p)
      t
    (let ((target (point)))
      (goto-char target)
      (while (and (not (eobp)) (not (pearl-gtd-ui--line-data-p)))
        (forward-line 1))
      (if (pearl-gtd-ui--line-data-p)
          t
        (goto-char target)
        (while (and (not (bobp)) (not (pearl-gtd-ui--line-data-p)))
          (forward-line -1))
        (if (pearl-gtd-ui--line-data-p)
            t
          (goto-char (point-min))
          nil)))))

(defun pearl-gtd-ui--restore-point-anchor (anchor)
  "Restore point from ANCHOR in current buffer.
ANCHOR is the value returned by `pearl-gtd-ui--anchor-at-point'.
Prefer ID/project match over line fallback; fall back to point-min."
  (when anchor
    (let ((id-file (nth 0 anchor))
          (project (nth 1 anchor))
          (line (nth 2 anchor)))
      (cond
       ((and id-file (pearl-gtd-ui--goto-entry (car id-file) (cdr id-file))))
       ((and project (pearl-gtd-ui--goto-project project)))
       ((pearl-gtd-ui--goto-line line))
       (t (goto-char (point-min)))))))

(provide 'pearl-gtd-ui)

;;; pearl-gtd-ui.el ends here
