;;; pearl-gtd-state.el --- Thin state layer for Pearl-GTD  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 OverbearingPearl
;; Author: OverbearingPearl <OverbearingPearl@outlook.com>
;; SPDX-License-Identifier: MIT

;;; Commentary:

;; Thin state layer: transactional file operations.
;; All side effects on GTD data files go through this layer.
;; Trust boundary: external (filesystem) errors are captured and rolled back;
;; internal state violations use cl-assert and crash immediately.

;;; Code:

(require 'cl-lib)

(defmacro pearl-gtd-state--with-file-buffer (file-path &rest body)
  "Execute BODY in buffer of FILE-PATH (expanded relative to base dir).
Buffer is saved if modified after BODY."
  (declare (indent 1))
  `(let* ((file-path-expanded (expand-file-name ,file-path pearl-gtd-init-base-directory))
          (buf (find-file-noselect file-path-expanded)))
     (with-current-buffer buf
       (org-mode)
       (widen)
       (prog1
           (progn ,@body)
         (when (buffer-modified-p)
           (save-buffer))))))

(defmacro pearl-gtd-state--with-entry-at-id (id file &rest body)
  "Execute BODY with point at entry ID in FILE.
Signals error if entry not found (internal state violation)."
  (declare (indent 2))
  `(pearl-gtd-state--with-file-buffer ,file
     (goto-char (point-min))
     (let ((id-val ,id))
       (unless (re-search-forward (concat ":ID:[ \t]+" (regexp-quote id-val)) nil t)
         (error "Internal: entry %s not found in %s" id-val ,file))
       (org-back-to-heading)
       ,@body)))

(defun pearl-gtd-state--snapshot (file)
  "Create memory snapshot of FILE for transaction.
Returns (FILE PATH CONTENT-STRING-OR-NIL)."
  (let ((path (expand-file-name file pearl-gtd-init-base-directory)))
    (list file path (when (file-exists-p path)
                      (with-temp-buffer
                        (insert-file-contents path)
                        (buffer-string))))))

(defun pearl-gtd-state--rollback (snapshots)
  "Restore files from SNAPSHOTS and kill visiting buffers."
  (dolist (snap snapshots)
    (let ((path (cadr snap))
          (content (caddr snap)))
      (when-let ((buf (find-buffer-visiting path)))
        (with-current-buffer buf
          (set-buffer-modified-p nil))
        (kill-buffer buf))
      (if content
          (with-temp-file path
            (insert content))
        (when (file-exists-p path)
          (delete-file path))))))

(defmacro pearl-gtd-state--with-transaction (files &rest body)
  "Execute BODY with transactional safety on FILES.
If any signal, rollback to original state and re-signal."
  (declare (indent 1))
  `(let ((snapshots (mapcar #'pearl-gtd-state--snapshot ,files)))
     (condition-case err
         (progn ,@body)
       (t
        (pearl-gtd-state--rollback snapshots)
        (signal (car err) (cdr err))))))

(provide 'pearl-gtd-state)

;;; pearl-gtd-state.el ends here
