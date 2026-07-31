;;; pearl-gtd-ui.el --- UI utilities for Pearl-GTD  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 OverbearingPearl
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

(defun pearl-gtd-ui--insert-empty-row (column-count)
  "Insert an empty placeholder row with COLUMN-COUNT cells."
  (insert "| (No entries)")
  (dotimes (_ (1- column-count))
    (insert " |"))
  (insert " |\n"))

(provide 'pearl-gtd-ui)

;;; pearl-gtd-ui.el ends here
