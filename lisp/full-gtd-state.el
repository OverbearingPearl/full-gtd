;;; full-gtd-state.el --- Thin state layer for Full-GTD  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 OverbearingPearl
;; Author: OverbearingPearl <OverbearingPearl@outlook.com>
;; Assisted-by: Kimi:kimi-k2.5, DeepSeek:deepseek-v3.2, Claude:claude-sonnet-4.6
;; URL: https://github.com/OverbearingPearl/full-gtd
;; SPDX-License-Identifier: MIT

;;; Commentary:

;; Thin state layer: transactional file operations.
;; All side effects on GTD data files go through this layer.
;; Trust boundary: external (filesystem) errors are captured and rolled back;
;; internal state violations use cl-assert and crash immediately.

;;; Code:

(require 'cl-lib)
(require 'org)
(require 'full-gtd-init)

(defmacro full-gtd-state--with-file-buffer (file-path &rest body)
  "Execute BODY in buffer of FILE-PATH (expanded relative to base dir).
Buffer is saved if modified after BODY."
  (declare (indent 1))
  `(let* ((file-path-expanded (expand-file-name ,file-path full-gtd-init-base-directory))
          (buf (find-file-noselect file-path-expanded)))
     (with-current-buffer buf
       (org-mode)
       (widen)
       (prog1
           (progn ,@body)
         (when (buffer-modified-p)
           (save-buffer))))))

(defmacro full-gtd-state--with-entry-at-id (id file &rest body)
  "Execute BODY with point at entry ID in FILE.
Signals error if entry not found (internal state violation)."
  (declare (indent 2))
  `(full-gtd-state--with-file-buffer ,file
     (goto-char (point-min))
     (let ((id-val ,id))
       (unless (re-search-forward (concat ":ID:[ \t]+" (regexp-quote id-val)) nil t)
         (error "Internal: entry %s not found in %s" id-val ,file))
       (org-back-to-heading)
       ,@body)))

(defun full-gtd-state--snapshot (file)
  "Create memory snapshot of FILE for transaction.
Returns (FILE PATH CONTENT-STRING-OR-NIL)."
  (let ((path (expand-file-name file full-gtd-init-base-directory)))
    (list file path (when (file-exists-p path)
                      (with-temp-buffer
                        (insert-file-contents path)
                        (buffer-string))))))

(defun full-gtd-state--rollback (snapshots)
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

(defmacro full-gtd-state--with-transaction (files &rest body)
  "Execute BODY with transactional safety on FILES.
If any signal, rollback to original state and re-signal."
  (declare (indent 1))
  `(let ((snapshots (mapcar #'full-gtd-state--snapshot ,files)))
     (condition-case err
         (progn ,@body)
       (t
        (full-gtd-state--rollback snapshots)
        (signal (car err) (cdr err))))))

(provide 'full-gtd-state)

;;; full-gtd-state.el ends here
