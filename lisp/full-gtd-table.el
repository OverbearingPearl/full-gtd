;;; full-gtd-table.el --- Unified Org table utilities for Full-GTD  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 OverbearingPearl
;; Author: OverbearingPearl <OverbearingPearl@outlook.com>
;; Assisted-by: DeepSeek:deepseek-v4-flash
;; URL: https://github.com/OverbearingPearl/full-gtd
;; SPDX-License-Identifier: MIT

;;; Commentary:

;; Centralized Org table rendering and navigation.
;; Provides structured line-type detection, Org-native width cookies,
;; non-destructive data-row insertion, row text-property management,
;; anchoring/restoration, and
;; navigation macros.
;; Replaces scattered regex-based header skipping, hardcoded
;; header/separator strings, and duplicated row-property handling
;; across full-gtd-review.el, full-gtd-horizons.el,
;; full-gtd-project-utils.el, and full-gtd-inbox.el.
;; This module is the single entry point for all Org table concerns.

;;; Code:

(require 'cl-lib)
(require 'org)
(require 'org-table)

;;;; Text properties

(defconst full-gtd-table-prop-id 'full-gtd-id
  "Text property key for entry ID on table rows.")

(defconst full-gtd-table-prop-file 'full-gtd-file
  "Text property key for source file on table rows.")

(defconst full-gtd-table-prop-project 'full-gtd-project
  "Text property key for project name on table rows.")

;;;; Line classification

(defun full-gtd-table--width-cookie-line-p ()
  "Return non-nil if the current line is a table width-cookie row."
  (save-excursion
    (beginning-of-line)
    (when (looking-at "|")
      (let ((fields (mapcar #'string-trim
                            (split-string
                             (buffer-substring-no-properties
                              (line-beginning-position)
                              (line-end-position))
                             "|" nil)))
            (found nil)
            (valid t))
        (dolist (field fields)
          (cond
           ((string-empty-p field))
           ((string-match-p "\\`<[0-9]+>\\'" field)
            (setq found t))
           (t
            (setq valid nil))))
        (and valid found)))))

(defun full-gtd-table-line-type ()
  "Classify current line as `cookie', `header', `separator', `data', or `other'.
A cookie row contains only Org table width cookies and empty fields.
A header row is a table row immediately followed by a separator row.
A separator row is one matching `|[-+]'."
  (save-excursion
    (beginning-of-line)
    (cond
     ((not (looking-at "|")) 'other)
     ((full-gtd-table--width-cookie-line-p) 'cookie)
     ((looking-at "|[-+]") 'separator)
     ((progn (forward-line 1)
             (and (not (eobp))
                  (looking-at "|[-+]")))
      'header)
     (t 'data))))

;;;; Row metadata

(defun full-gtd-table--prop-at-point (prop)
  "Return PROP text property value from current line, or nil.
Scans the whole line for PROP."
  (save-excursion
    (beginning-of-line)
    (let ((end (line-end-position))
          (value nil))
      (while (and (not value) (< (point) end))
        (setq value (get-text-property (point) prop))
        (forward-char 1))
      value)))

(defun full-gtd-table-entry-at-point ()
  "Return (ID . FILE) from current table row, or nil if not a task row."
  (let ((id (full-gtd-table--prop-at-point full-gtd-table-prop-id))
        (file (full-gtd-table--prop-at-point full-gtd-table-prop-file)))
    (when (and id file)
      (cons id file))))

(defun full-gtd-table-project-at-point ()
  "Return project name from current table row, or nil."
  (full-gtd-table--prop-at-point full-gtd-table-prop-project))

;;;; Rendering

(defun full-gtd-table--escape-field (field)
  "Escape pipe characters in FIELD for org-table display."
  (replace-regexp-in-string "|" "\\\\vert{}" field))

(defun full-gtd-table--column-title (column)
  "Return the title represented by COLUMN.
COLUMN is either a title string or a (TITLE . WIDTH) pair."
  (if (consp column)
      (car column)
    column))

(defun full-gtd-table--column-width (column)
  "Return the positive Org display width represented by COLUMN, or nil."
  (when (consp column)
    (let ((width (cdr column)))
      (when (and (integerp width) (> width 0))
        width))))

(defun full-gtd-table-insert-header (columns)
  "Insert an Org table header and matching separator for COLUMNS.
Each column is either a title string for unconstrained display, or a
\(TITLE . WIDTH) pair.  Constrained columns use Org width cookies, so
alignment truncates only the display layer and `C-c TAB' toggles the
current column between constrained and complete display."
  (let* ((titles (mapcar #'full-gtd-table--column-title columns))
         (widths (mapcar #'full-gtd-table--column-width columns))
         (header (concat "| " (mapconcat #'identity titles " | ") " |\n"))
         (cells (mapcar (lambda (title)
                          (make-string (max 3 (+ (length title) 2)) ?-))
                        titles))
         (separator (concat "|" (mapconcat #'identity cells "|") "|\n")))
    (when (cl-some #'identity widths)
      (insert
       "| "
       (mapconcat
        (lambda (width)
          (if width (format "<%d>" width) ""))
        widths
        " | ")
       " |\n"))
    (insert header)
    (insert separator)))

(defun full-gtd-table--hide-width-cookie (table-begin)
  "Hide the width-cookie row at TABLE-BEGIN from visual display."
  (save-excursion
    (goto-char table-begin)
    (when (full-gtd-table--width-cookie-line-p)
      (let ((overlay (make-overlay
                      (line-beginning-position)
                      (min (point-max) (1+ (line-end-position))))))
        (overlay-put overlay 'invisible t)
        (overlay-put overlay 'evaporate t)
        (overlay-put overlay 'full-gtd-table-width-cookie t)))))

(defun full-gtd-table-finalize ()
  "Align the current Org table, shrinking width-constrained columns.
Uses Org's public `org-table-shrink' to force every column with a
width cookie into its constrained display state, and expand every
column without one.  This runs on every call so each freshly rendered
view starts collapsed regardless of any prior `C-c TAB' state left
over in the buffer.  Width-cookie rows remain in the buffer for Org's
native `C-c TAB' support, but are hidden from visual display.  Buffer
text is never modified; only the display layer is affected."
  (let ((table-begin (save-excursion (org-table-begin))))
    (org-table-align)
    (save-excursion
      (goto-char table-begin)
      (org-table-shrink))
    (full-gtd-table--hide-width-cookie table-begin)))

(defun full-gtd-table-shrink-buffer ()
  "Restore constrained display for every width-cookie table in this buffer.
Run this after all rendering and metadata post-processing so later buffer
changes cannot leave initially constrained columns expanded."
  (when (fboundp 'font-lock-ensure)
    (font-lock-ensure (point-min) (point-max)))
  (save-excursion
    (goto-char (point-min))
    (while (not (eobp))
      (when (full-gtd-table--width-cookie-line-p)
        (let ((table-begin (line-beginning-position)))
          (org-table-shrink)
          (full-gtd-table--hide-width-cookie table-begin)))
      (forward-line 1))))

(defun full-gtd-table-insert-row (headline id file fields &optional project-p widths)
  "Insert a table data row with text properties.
HEADLINE is the display text (escaped).
ID is the entry ID (nil for project rows).
FILE is the source file.
FIELDS is a list of remaining column values (strings or numbers).
If PROJECT-P is non-nil, attach `full-gtd-table-prop-project' to
HEADLINE instead of ID/FILE.
WIDTHS is retained for call compatibility but ignored; display widths
belong to header column descriptors and are implemented by Org."
  (ignore widths)
  (let ((headline-escaped (full-gtd-table--escape-field headline)))
    (insert "| ")
    (let ((start (point)))
      (insert headline-escaped)
      (if project-p
          (put-text-property start (point) full-gtd-table-prop-project headline)
        (progn
          (put-text-property start (point) full-gtd-table-prop-id id)
          (put-text-property start (point) full-gtd-table-prop-file file))))
    (dolist (field fields)
      (insert " | ")
      (insert (if field (format "%s" field) "")))
    (insert " |\n")))

;;;; Data row boundaries

(defun full-gtd-table-data-row-boundaries ()
  "Return (FIRST-DATA-ROW . LAST-DATA-ROW) buffer positions.
Locates data rows by scanning from point-min forward and from
point-max backward, skipping all non-data lines."
  (save-excursion
    (goto-char (point-min))
    (while (and (not (eobp))
                (not (eq (full-gtd-table-line-type) 'data)))
      (forward-line 1))
    (let ((first-data (line-beginning-position)))
      (goto-char (point-max))
      (forward-line -1)
      (while (and (not (bobp))
                  (not (eq (full-gtd-table-line-type) 'data)))
        (forward-line -1))
      (cons first-data (line-beginning-position)))))

;;;; Navigation

(defmacro full-gtd-table-define-navigators (prefix)
  "Define table navigation commands for PREFIX.
Creates PREFIX--next-row, PREFIX--previous-row, and
PREFIX--skip-line-p using structural line-type detection."
  (let ((next-fn (intern (concat prefix "--next-row")))
        (prev-fn (intern (concat prefix "--previous-row")))
        (skip-fn (intern (concat prefix "--skip-line-p"))))
    `(progn
       (defun ,skip-fn ()
         "Return non-nil if current line should be skipped during navigation."
         (not (eq (full-gtd-table-line-type) 'data)))
       (defun ,next-fn ()
         "Move to the next data row in the table."
         (interactive)
         (let* ((boundaries (full-gtd-table-data-row-boundaries))
                (last (cdr boundaries)))
           (if (>= (line-beginning-position) last)
               (beep)
             (forward-line 1)
             (while (and (not (eobp)) (,skip-fn))
               (forward-line 1))
             (org-table-goto-column 1))))
       (defun ,prev-fn ()
         "Move to the previous data row in the table."
         (interactive)
         (let* ((boundaries (full-gtd-table-data-row-boundaries))
                (first (car boundaries)))
           (if (<= (line-beginning-position) first)
               (beep)
             (forward-line -1)
             (while (and (not (bobp)) (,skip-fn))
               (forward-line -1))
             (org-table-goto-column 1)))))))

;;;; Anchoring and point restoration

(defun full-gtd-table-anchor-at-point ()
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
            (setq id (get-text-property (point) full-gtd-table-prop-id)))
          (unless file
            (setq file (get-text-property (point) full-gtd-table-prop-file)))
          (unless project
            (setq project (get-text-property (point) full-gtd-table-prop-project)))
          (forward-char 1))
        (when (or (and id file) project)
          (list (and id file (cons id file))
                project
                (line-number-at-pos)))))))

(defun full-gtd-table--goto-row (predicate)
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

(defun full-gtd-table--goto-entry (id file)
  "Go to row containing entry ID in FILE."
  (full-gtd-table--goto-row
   (lambda (pos)
     (and (equal (get-text-property pos full-gtd-table-prop-id) id)
          (equal (get-text-property pos full-gtd-table-prop-file) file)))))

(defun full-gtd-table--goto-project (project)
  "Go to row containing project PROJECT."
  (full-gtd-table--goto-row
   (lambda (pos)
     (equal (get-text-property pos full-gtd-table-prop-project) project))))

(defun full-gtd-table--line-data-p ()
  "Return non-nil if current line has task or project text property."
  (save-excursion
    (let ((end (line-end-position))
          (pos (line-beginning-position)))
      (catch 'found
        (while (< pos end)
          (when (or (get-text-property pos full-gtd-table-prop-id)
                    (get-text-property pos full-gtd-table-prop-project))
            (throw 'found t))
          (setq pos (1+ pos)))
        nil))))

(defun full-gtd-table--goto-line (line)
  "Go to LINE; if not a table data row, go to nearest data row.
Return non-nil if a table data row was found."
  (goto-char (point-min))
  (forward-line (1- line))
  (if (full-gtd-table--line-data-p)
      t
    (let ((target (point)))
      (goto-char target)
      (while (and (not (eobp)) (not (full-gtd-table--line-data-p)))
        (forward-line 1))
      (if (full-gtd-table--line-data-p)
          t
        (goto-char target)
        (while (and (not (bobp)) (not (full-gtd-table--line-data-p)))
          (forward-line -1))
        (if (full-gtd-table--line-data-p)
            t
          (goto-char (point-min))
          nil)))))

(defun full-gtd-table-restore-point-anchor (anchor)
  "Restore point from ANCHOR in current buffer.
ANCHOR is the value returned by `full-gtd-table-anchor-at-point'.
Prefer ID/project match over line fallback; fall back to point-min."
  (when anchor
    (let ((id-file (nth 0 anchor))
          (project (nth 1 anchor))
          (line (nth 2 anchor)))
      (cond
       ((and id-file (full-gtd-table--goto-entry (car id-file) (cdr id-file))))
       ((and project (full-gtd-table--goto-project project)))
       ((full-gtd-table--goto-line line))
       (t (goto-char (point-min)))))))

(provide 'full-gtd-table)

;;; full-gtd-table.el ends here
