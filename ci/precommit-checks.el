;;; precommit-checks.el --- Lint and byte-compile checks used by pre-commit

;;; Commentary:

;; Extracted from the inline elisp that used to live in the `emacs-check'
;; hook of .pre-commit-config.yaml.  The hook now loads this file with
;; `load'; everything below is the same check suite, only lifted out of
;; the --eval argument.  This file lives in ci/ (not lisp/) on purpose:
;; the emacs-check hook only enumerates lisp/*.el and the root modules,
;; so tooling files placed here are not subject to the module-prefix and
;; meta-info rules they themselves enforce.
;;
;; This Commentary is the single source of truth for what is enforced.
;; Whenever a check is added, removed, tightened, or relaxed below, YOU
;; MUST update this Commentary in the same change so the two stay in
;; sync.
;;
;; The checks run in `emacs -Q --batch'.  Per-file checks report only
;; failing files; any failure prints to stderr and aborts the commit by
;; exiting non-zero.
;;
;; Global checks (run once, before per-file checks)
;; ------------------------------------------------
;;   dependency-direction
;;     Module requires must obey the module classes derived from the repo
;;     layout.  Allowed require targets per class:
;;       root-main     -> lisp-business
;;       root-test     -> root-main, root-test, lisp-business, lisp-test
;;       lisp-business -> lisp-business
;;       lisp-test     -> root-main, root-test, lisp-business, lisp-test
;;     Requires of features outside this repo (e.g. built-ins) are
;;     ignored.  The repo main file <repo>.el must exist in the repo
;;     root or the hook aborts immediately.
;;
;;   portability
;;     This file is project-agnostic: no project-specific names are
;;     hard-coded anywhere.  The repository name is derived at run time
;;     from `git rev-parse --show-toplevel' and used to locate the root
;;     entry module <repo>.el, whose defcustom forms register the user
;;     options as special variables before test files are byte-compiled.
;;     Copying this file into another elisp project with the same layout
;;     (root main module, optional root test module, lisp/ business and
;;     test sub-modules) works without edits.
;;
;; Per-file checks (applied to each matched .el file)
;; --------------------------------------------------
;;   checkdoc                -- checkdoc-current-buffer, autofix disabled.
;;   package-lint            -- package-lint-current-buffer; the main
;;                              file is pinned to <repo>.el at the repo
;;                              root.
;;   byte-compile            -- byte-compile-file; non-test files are
;;                              loaded after compiling.
;;   format-check            -- no trailing whitespace; no more than one
;;                              consecutive blank line.
;;   heading-comment         -- `;;;' comment lines (except `;;;###'
;;                              autoload cookies) must be surrounded by
;;                              blank lines.
;;   banned-construct        -- forbids `;; package-lint: disable',
;;                              `declare-function', `ignore-errors',
;;                              `eval-and-compile', `when-let', and
;;                              `if-let'; each error message carries a
;;                              suggested replacement.
;;   meta-info               -- header/meta requirements:
;;                              * non-test files require `;; Copyright',
;;                                `;; Author', `;; Assisted-by',
;;                                `;; URL', and
;;                                `;; SPDX-License-Identifier'.
;;                              * test files forbid `;; Copyright',
;;                                `;; Author', `;; Assisted-by',
;;                                `;; URL', `;; Version',
;;                                `;; Package-Requires', `;; Keywords',
;;                                and `;; SPDX-License-Identifier'.
;;                              * `;;; Commentary' is required and must
;;                                be non-empty.
;;                              * `;; Keywords:' entries must be known
;;                                to `finder-known-keywords'.
;;   module-name-consistency -- the file must `(provide '<file-base>)',
;;                              quoted or unquoted.
;;   module-prefix           -- definitions (defun, defmacro, defvar,
;;                              defcustom, defconst, defalias, cl-defun,
;;                              cl-defmacro, ert-deftest) must use the
;;                              `<file-base>-' prefix; `defcustom' uses
;;                              the `<repo>-' prefix; the root main file
;;                              may define `<repo>' as its entry
;;                              command.
;;
;; Checked files, in order: lisp/*.el production (sorted), root
;; <repo>.el, lisp/*-test.el (sorted), root <repo>-test.el.

;;; Code:

(require 'package)
(setq package-load-list '(all))
(package-initialize)
(setq load-prefer-newer t)
(setq load-path (append (list (expand-file-name "lisp") (expand-file-name ".")) load-path))
(require 'checkdoc)
(require 'package-lint)
(require 'finder)
(setq checkdoc-autofix-flag 'never
      p/errors '())
(advice-add 'checkdoc-create-error :before
            (lambda (&rest args)
              (let* ((msg (car args))
                     (pos (or (and (numberp (nth 1 args)) (nth 1 args))
                              (and (numberp (nth 2 args)) (nth 2 args))))
                     (line (and pos (line-number-at-pos pos)))
                     (full (if line
                               (format "%s (line %d)" msg line)
                             msg)))
                (push full p/errors))))

(defun p/buf-str (name)
  (let ((buf (get-buffer name)))
    (if buf (with-current-buffer buf (buffer-string)) "")))

(defun p/indent (s)
  (mapconcat (lambda (line) (concat "    " line))
             (split-string s "\n" t) "\n"))

(defun p/git-toplevel ()
  "Return the toplevel directory of the git repository."
  (with-temp-buffer
    (call-process "git" nil t nil
                  "rev-parse" "--show-toplevel")
    (string-trim (buffer-string))))

(defconst p/blank-line-rx
  (rx line-start (* (any blank)) line-end)
  "Regexp matching an empty or blank-only line.")

(defconst p/trailing-blank-rx
  (rx (+ (any blank)) line-end)
  "Regexp matching trailing blanks at end of line.")

(defconst p/comment-rx
  (rx line-start (* (any blank)) ";;")
  "Regexp matching a line whose first non-blank text is `;;'.")

(defconst p/h3-comment-rx
  (rx line-start (* (any blank)) ";;;")
  "Regexp matching a level-three (`;;;') comment line.")

(defconst p/autoload-cookie-rx
  (rx line-start (* (any blank)) ";;;###")
  "Regexp matching an autoload cookie line.")

(defconst p/keyword-sep-rx
  (rx (+ (any space ",;")))
  "Regexp matching separators in the `Keywords:' meta line.")

(defun p/blank-line-p (s)
  "Return non-nil if S is empty or contains only blanks."
  (string-match-p p/blank-line-rx s))

(defun p/h3-comment-p (s)
  "Return non-nil if S is a `;;;' comment but not an autoload cookie."
  (and (string-match-p p/h3-comment-rx s)
       (not (string-match-p p/autoload-cookie-rx s))))

(defun p/meta-line-p (line prefix &optional allow-indent)
  "Return non-nil if LINE starts with PREFIX; leading blanks allowed when ALLOW-INDENT is non-nil."
  (string-prefix-p prefix
                   (if allow-indent
                       (string-trim-left line)
                     line)))

(defun p/provide-p (file-base)
  "Return non-nil if the current buffer provides FILE-BASE, quoted or unquoted."
  (let ((name (regexp-quote file-base)))
    (save-excursion
      (goto-char (point-min))
      (or (re-search-forward
           (format "(provide[[:space:]]+'%s[[:space:]]*)" name)
           nil t)
          (progn
            (goto-char (point-min))
            (re-search-forward
             (format "(provide[[:space:]]+%s[[:space:]]*)" name)
             nil t))))))

(defun p/heading-comment-errors ()
  "Return a list of style errors for ;;; heading comments."
  (let ((lines (split-string (buffer-string) "\n"))
        (errors nil))
    (when (and lines (string-empty-p (car (last lines))))
      (setq lines (butlast lines)))
    (dotimes (i (length lines))
      (when (p/h3-comment-p (nth i lines))
        (let ((prev-blank
               (or (= i 0)
                   (p/blank-line-p (nth (1- i) lines))))
              (next-blank
               (or (= i (1- (length lines)))
                   (p/blank-line-p (nth (1+ i) lines)))))
          (unless (and prev-blank next-blank)
            (push (format "heading comment (;;;) at line %d must be surrounded by blank lines"
                          (1+ i))
                  errors)))))
    (setq errors (nreverse errors))
    (append errors (p/commentary-line-errors))))

(defun p/commentary-line-errors ()
  "Return errors for commentary lines wider than 80 characters.
Scans the `;;; Commentary' block: it starts at the `;;; Commentary'
heading (a trailing colon, as in `;;; Commentary:', is allowed) and
ends at the next `;;;' heading line.  Autoload cookie lines (e.g.
`;;;###autoload') are neither headings nor block terminators; they
are still width-checked as commentary lines."
  (save-excursion
    (goto-char (point-min))
    (let ((errs '())
          (in-block nil))
      (while (not (eobp))
        (let ((line (buffer-substring-no-properties
                     (line-beginning-position)
                     (line-end-position))))
          (cond
           ((string-match-p "\\`;;;[ \t]*Commentary:?[ \t]*\\'" line)
            (setq in-block t))
           ((and in-block (string-match-p "\\`;;;[ \t]+[^;\t\n]" line))
            ;; A real `;;;' heading (has a space after the semicolons)
            ;; terminates the block; `;;;###autoload' does not.
            (setq in-block nil)))
          (when (and in-block (> (length line) 80))
            (push (format "commentary line wider than 80 characters (line %d)"
                          (line-number-at-pos))
                  errs)))
        (forward-line 1))
      (nreverse errs))))

(defvar p/repo-root-cache nil
  "Cached repository toplevel directory.")

(defun p/repo-root ()
  "Return the repository toplevel directory, cached."
  (or p/repo-root-cache
      (setq p/repo-root-cache (p/git-toplevel))))

(defun p/module-class (file)
  "Return the module class of FILE, or nil if not a repository module.
The classes mirror the repository layout:
  `root-main'     -- <repo>.el in the repository root
  `root-test'     -- <repo>-test.el in the repository root
  `lisp-business' -- lisp/*.el, excluding *-test.el
  `lisp-test'     -- lisp/*-test.el"
  (let* ((root (p/repo-root))
         (repo-name (file-name-nondirectory
                     (directory-file-name root)))
         (lisp-dir (expand-file-name "lisp" root))
         (name (file-name-nondirectory file))
         (in-lisp (file-in-directory-p file lisp-dir)))
    (cond
     ((and (not in-lisp)
           (file-equal-p file
                         (expand-file-name
                          (concat repo-name ".el") root)))
      'root-main)
     ((and (not in-lisp)
           (file-equal-p file
                         (expand-file-name
                          (concat repo-name "-test.el") root)))
      'root-test)
     (in-lisp
      (if (string-suffix-p "-test.el" name)
          'lisp-test
        'lisp-business))
     (t nil))))

(defconst p/module-dependency-rules
  '((root-test     . (root-main root-test lisp-business lisp-test))
    (lisp-test     . (root-main lisp-business lisp-test))
    (root-main     . (lisp-business))
    (lisp-business . (lisp-business)))
  "Allowed require targets per module class; see `p/module-class'.")

(defun p/file-top-level-requires (file)
  "Return feature symbols of all top-level (require ...) forms in FILE.
Accepts both (require 'feature) and (require feature)."
  (with-temp-buffer
    (insert-file-contents file)
    (goto-char (point-min))
    (let ((requires '()))
      (condition-case nil
          (while t
            (let* ((form (read (current-buffer)))
                   (arg (and (consp form)
                             (eq (car form) 'require)
                             (cadr form))))
              ;; `read' turns (require 'x) into
              ;; (require (quote x)); unwrap that quote.
              (when arg
                (when (and (consp arg) (eq (car arg) 'quote))
                  (setq arg (cadr arg)))
                (when (symbolp arg)
                  (push arg requires)))))
        (end-of-file nil))
      (nreverse requires))))

(defun p/dependency-errors (files)
  "Return dependency-direction errors across all FILES.
FILES must be the complete set of repository .el modules.  Each module
may only require modules whose class is permitted by
`p/module-dependency-rules'.  Requires of features outside this
repository (e.g. built-ins) are ignored."
  (let* ((root (p/repo-root))
         (feature-classes
          (let (tbl)
            (dolist (f files tbl)
              (let ((class (p/module-class f)))
                (when class
                  (push (cons (file-name-base f) class)
                        tbl))))))
         (errors '()))
    (dolist (file files)
      (let ((from-class (p/module-class file)))
        (when from-class
          (dolist (feature (p/file-top-level-requires file))
            (let ((to-class
                   (cdr (assoc (symbol-name feature)
                               feature-classes))))
              (when to-class
                (unless (memq to-class
                              (cdr (assoc from-class
                                          p/module-dependency-rules)))
                  (push (format "%s: %s may not require %s `%s'"
                                (file-relative-name file root)
                                from-class to-class
                                (symbol-name feature))
                        errors))))))))
    (nreverse errors)))

(defun p/check-file (file)
  (setq file (expand-file-name file))
  (let ((buf (find-file file))
        (failed nil)
        ;; Collect output; only failing files are printed.
        (report-buf (generate-new-buffer " *p-check*")))
    (let ((standard-output report-buf))
      (dolist (b '("*Warnings*" "*Compile-Log*" "*Messages*"))
        (when (get-buffer b)
          (with-current-buffer b
            (let ((inhibit-read-only t))
              (erase-buffer)))))
      (setq p/errors '())
      (princ (format "===== %s =====\n" file))
      ;; checkdoc
      (ignore-errors (checkdoc-current-buffer t))
      (let ((checkdoc-count (length p/errors)))
        (if (> checkdoc-count 0)
            (progn
              (princ (format "  checkdoc: %s issue(s)\n" checkdoc-count))
              (dolist (e (nreverse p/errors))
                (princ (format "    %s\n" e)))
              (setq failed t))
          (princ "  checkdoc: OK\n")))
      ;; package-lint
      (let* ((root (p/git-toplevel))
             (name (file-name-nondirectory
                    (directory-file-name root))))
        (setq package-lint-main-file
              (expand-file-name (concat name ".el") root)))
      (when (get-buffer "*Package-Lint*")
        (kill-buffer "*Package-Lint*"))
      (package-lint-current-buffer)
      (let ((pl (string-trim (p/buf-str "*Package-Lint*"))))
        (if (or (string-empty-p pl)
                (string= pl "No issues found."))
            (princ "  package-lint: OK\n")
          (progn
            (setq failed t)
            (princ "  package-lint: warning(s)\n")
            (princ (p/indent pl))
            (princ "\n"))))
      ;; byte-compile
      ;; Before compiling, evaluate the file's own top-level
      ;; require features so that their defcustom/defvar forms
      ;; are loaded into the compiler's obarray and the flagged
      ;; names are known as special variables at compile time.
      ;; This applies to all files, including test files, so
      ;; tests need no local defvar declarations for options
      ;; bound in other modules.
      (let ((inhibit-message t)
            (byte-compile-verbose nil)
            (byte-compile-dest-file-function
             (lambda (f)
               (make-temp-file (concat (file-name-nondirectory f) "-") nil ".elc"))))
        (dolist (feature (p/file-top-level-requires file))
          (condition-case nil
              (require feature)
            (error nil)))
        ;; Also require the root entry module, whose feature
        ;; symbol is derived from the repository name.  Its
        ;; defcustom forms are the only place the real user
        ;; options are bound as special variables; the lisp/
        ;; sub-modules carry only bare (defvar name) forward
        ;; declarations, which do not register the variables
        ;; as special when loaded, so loading the root module
        ;; is required to silence unused-lexical-variable
        ;; warnings in test files referencing those options.
        (condition-case nil
            (require (intern (file-name-nondirectory
                              (directory-file-name
                               (p/git-toplevel)))))
          (error nil))
        (let ((compiled-p (byte-compile-file file)))
          ;; `byte-compile-file' returns non-nil on success,
          ;; not the generated byte-code filename.
          (when (and compiled-p
                     (not (string-suffix-p
                           "-test.el"
                           (file-name-nondirectory file))))
            (load (byte-compile-dest-file file) nil t))))
      ;; clear other buffers that may hold duplicate warnings
      (dolist (b '("*Warnings*" "*Messages*"))
        (when (get-buffer b)
          (with-current-buffer b
            (let ((inhibit-read-only t))
              (erase-buffer)))))
      (let ((bc (string-trim (p/buf-str "*Compile-Log*"))))
        (if (string-empty-p bc)
            (princ "  byte-compile: OK\n")
          (progn
            (setq failed t)
            (princ "  byte-compile: warning(s)/error(s)\n")
            (princ (p/indent bc))
            (princ "\n"))))
      ;; format-check
      (let ((format-errors nil)
            (lines (split-string (buffer-string) "\n"))
            (line-num 0)
            (blank-run 0)
            (last-blank-start nil))
        (when (and lines (string-empty-p (car (last lines))))
          (setq lines (butlast lines)))
        (dolist (line lines)
          (setq line-num (1+ line-num))
          (when (and (not (p/blank-line-p line))
                     (string-match-p p/trailing-blank-rx line))
            (push (format "trailing whitespace (line %d)" line-num)
                  format-errors))
          (if (p/blank-line-p line)
              (progn
                (when (= blank-run 0)
                  (setq last-blank-start line-num))
                (setq blank-run (1+ blank-run)))
            (progn
              (when (> blank-run 1)
                (push (format "more than one consecutive blank line (line %d)"
                              last-blank-start)
                      format-errors))
              (setq blank-run 0))))
        (when (> blank-run 1)
          (push (format "more than one consecutive blank line (line %d)"
                        last-blank-start)
                format-errors))
        (if format-errors
            (progn
              (princ "  format-check: issue(s)\n")
              (dolist (e (nreverse format-errors))
                (princ (format "    %s\n" e)))
              (setq failed t))
          (princ "  format-check: OK\n")))
      ;; heading-comment check
      (let ((hc-errors (p/heading-comment-errors)))
        (if hc-errors
            (progn
              (princ "  heading-comment: issue(s)\n")
              (dolist (e (nreverse hc-errors))
                (princ (format "    %s\n" e)))
              (setq failed t))
          (princ "  heading-comment: OK\n")))
      ;; banned-construct check
      (let ((banned-errors nil)
            (banned-line-num 0))
        (dolist (banned-line (split-string (buffer-string) "\n" t))
          (setq banned-line-num (1+ banned-line-num))
          (cond
           ((string-match-p ";; package-lint: disable" banned-line)
            (push (format "banned construct `;; package-lint: disable` (line %d); fix the underlying lint issue instead of suppressing it" banned-line-num)
                  banned-errors))
           ((string-match-p (rx symbol-start "declare-function" symbol-end) banned-line)
            (push (format "banned construct `declare-function` (line %d); require the providing feature instead" banned-line-num)
                  banned-errors))
           ((string-match-p (rx symbol-start "ignore-errors" symbol-end) banned-line)
            (push (format "banned construct `ignore-errors` (line %d); use `condition-case` with a specific error" banned-line-num)
                  banned-errors))
           ((string-match-p (rx symbol-start "eval-and-compile" symbol-end) banned-line)
            (push (format "banned construct `eval-and-compile` (line %d); move the form or require it explicitly" banned-line-num)
                  banned-errors))
           ((string-match-p (rx symbol-start "when-let" symbol-end) banned-line)
            (push (format "banned construct `when-let` (line %d); use `when-let*` instead" banned-line-num)
                  banned-errors))
           ((string-match-p (rx symbol-start "if-let" symbol-end) banned-line)
            (push (format "banned construct `if-let` (line %d); use `if-let*` instead" banned-line-num)
                  banned-errors))))
        (if banned-errors
            (progn
              (princ "  banned-construct: issue(s)\n")
              (dolist (e (nreverse banned-errors))
                (princ (format "    %s\n" e)))
              (setq failed t))
          (princ "  banned-construct: OK\n")))
      ;; meta-info check
      (let* ((is-test (string-suffix-p "-test.el" (file-name-nondirectory file)))
             (header-lines
              (let ((lines nil)
                    (in-header t)
                    (line-num 0))
                (dolist (line (split-string (buffer-string) "\n"))
                  (setq line-num (1+ line-num))
                  (when in-header
                    (if (or (p/blank-line-p line)
                            (string-prefix-p ";;" line))
                        (push (cons line-num line) lines)
                      (setq in-header nil))))
                (nreverse lines)))
             (meta-errors nil)
             (forbidden '(";; Copyright" ";; Author" ";; Assisted-by" ";; URL" ";; Version" ";; Package-Requires" ";; Keywords" ";; SPDX-License-Identifier"))
             (required '(";; Copyright" ";; Author" ";; Assisted-by" ";; URL" ";; SPDX-License-Identifier")))
        ;; ;;; Commentary is required and non-empty
        (dolist (prefix '(";;; Commentary"))
          (let ((commentary-idx nil)
                (has-body nil))
            (dotimes (i (length header-lines))
              (when (and (null commentary-idx)
                         (p/meta-line-p (cdr (nth i header-lines))
                                        prefix))
                (setq commentary-idx i)))
            (unless commentary-idx
              (push (format "missing meta line `%s` in file" prefix)
                    meta-errors))
            (when commentary-idx
              (let ((tail (nthcdr (1+ commentary-idx) header-lines)))
                (dolist (pair tail)
                  (when (and (string-prefix-p ";;" (cdr pair))
                             (not (string-prefix-p ";;;" (cdr pair))))
                    (setq has-body t)))
                (unless has-body
                  (push (format "`%s` has no descriptive content (empty Commentary)" prefix)
                        meta-errors))))))
        (if is-test
            (dolist (pair header-lines)
              (dolist (prefix forbidden)
                (when (p/meta-line-p (cdr pair) prefix t)
                  (push (format "forbidden meta line `%s` in test file (line %d)" prefix (car pair))
                        meta-errors))))
          (dolist (prefix required)
            (unless (let ((found nil))
                      (dolist (pair header-lines)
                        (when (p/meta-line-p (cdr pair) prefix)
                          (setq found t)))
                      found)
              (push (format "missing meta line `%s` in non-test file" prefix)
                    meta-errors))))
        ;; validate Keywords against finder-known-keywords
        (when (not is-test)
          (let ((known (mapcar (lambda (kw)
                                 (downcase (symbol-name (car kw))))
                               finder-known-keywords)))
            (dolist (pair header-lines)
              (when (string-prefix-p ";; Keywords:" (cdr pair))
                (let* ((raw (string-trim (substring (cdr pair)
                                                    (length ";; Keywords:"))))
                       (kws (split-string raw p/keyword-sep-rx t)))
                  (if (null kws)
                      (push (format "empty Keywords: line (line %d)" (car pair))
                            meta-errors)
                    (dolist (kw kws)
                      (unless (member (downcase kw) known)
                        (push (format "unknown keyword `%s` (line %d).  Known keywords: %s"
                                      kw (car pair)
                                      (mapconcat #'identity known ", "))
                              meta-errors)))))))))
        (if meta-errors
            (progn
              (princ "  meta-info: issue(s)\n")
              (dolist (e (nreverse meta-errors))
                (princ (format "    %s\n" e)))
              (setq failed t))
          (princ "  meta-info: OK\n")))
      ;; module-name and filename consistency
      (let ((file-base (file-name-base file))
            (module-errors '()))
        (unless (p/provide-p file-base)
          (push (format "missing (provide '%s) to match filename" file-base)
                module-errors))
        (if module-errors
            (progn
              (princ "  module-name-consistency: issue(s)\n")
              (dolist (e (nreverse module-errors))
                (princ (format "    %s\n" e)))
              (setq failed t))
          (princ "  module-name-consistency: OK\n")))
      ;; prefix coherence for definitions
      ;; `defcustom' names are public API and follow the
      ;; package (`<repo>') prefix per Emacs convention, so
      ;; check them against the repo prefix rather than the
      ;; file-local prefix.  The entry command of the
      ;; package is named after the package itself, so the
      ;; root main file may define `<repo>' on its own.
      ;; Other def-kinds stay scoped to their module.
      (let* ((file-base (file-name-base file))
             (repo-main (eq (p/module-class file) 'root-main))
             (repo-name
              (file-name-nondirectory
               (directory-file-name (p/git-toplevel))))
             (repo-prefix (concat repo-name "-"))
             (expected-prefix (concat file-base "-"))
             (prefix-errors '())
             (def-kinds '(defun defmacro defvar defcustom defconst defalias cl-defun cl-defmacro ert-deftest)))
        (save-excursion
          (goto-char (point-min))
          (condition-case nil
              (while t
                (let* ((pos (point))
                       (line (line-number-at-pos pos))
                       (form (read (current-buffer))))
                  (when (and (listp form)
                             (memq (car form) def-kinds))
                    (let* ((kind (car form))
                           (name (cadr form))
                           (required-prefix
                            (if (eq kind 'defcustom)
                                repo-prefix
                              expected-prefix))
                           (entry-command-p
                            (and repo-main
                                 (eq kind 'defun)
                                 (symbolp name)
                                 (string= (symbol-name name)
                                          repo-name))))
                      (when (and (symbolp name)
                                 (not entry-command-p)
                                 (not (string-prefix-p
                                       required-prefix
                                       (symbol-name name))))
                        (push (format "`%s' at line %d must start with prefix `%s'"
                                      name line required-prefix)
                              prefix-errors))))))
            (end-of-file nil)))
        (if prefix-errors
            (progn
              (princ "  module-prefix: issue(s)\n")
              (dolist (e (nreverse prefix-errors))
                (princ (format "    %s\n" e)))
              (setq failed t))
          (princ "  module-prefix: OK\n")))
      (princ (format "  => %s\n" (if failed "FAILED" "OK"))))
    ;; Only failing files produce output; passing files stay silent.
    (when failed
      (with-current-buffer report-buf
        (princ (buffer-string))))
    (kill-buffer report-buf)
    (when (buffer-live-p buf) (kill-buffer buf))
    failed))

(let* ((failed-any nil)
       ;; Derive repo name from git, not from cwd.
       (git-root (p/git-toplevel))
       (repository-name
        (file-name-nondirectory
         (directory-file-name git-root)))
       (lisp-directory
        (expand-file-name "lisp" git-root))
       (lisp-production-files nil)
       (lisp-test-files nil)
       (lisp-dir-files (when (file-directory-p lisp-directory)
                         (directory-files lisp-directory t nil t)))
       (root-production-file
        (expand-file-name
         (concat repository-name ".el")
         git-root))
       (root-test-file
        (expand-file-name
         (concat repository-name "-test.el")
         git-root))
       ordered-files)
  (dolist (file
           (sort
            lisp-dir-files
            #'string<))
    (when (and (file-regular-p file)
               (string-suffix-p ".el" file))
      (if (string-suffix-p "-test.el" file)
          (push file lisp-test-files)
        (push file lisp-production-files))))
  (unless (file-exists-p root-production-file)
    (princ (format "error: required main file `%s` not found in repository root\n"
                   root-production-file))
    (kill-emacs 1))
  (setq ordered-files
        (append
         (nreverse lisp-production-files)
         (list root-production-file)
         (nreverse lisp-test-files)
         (when (file-exists-p root-test-file)
           (list root-test-file))))
  ;; Global dependency-direction check runs once, before
  ;; per-file linting, across the whole module set.  Stay
  ;; silent when every require is allowed; print the
  ;; concrete violation(s) only when one is detected.
  (let ((dep-errors (p/dependency-errors ordered-files)))
    (when dep-errors
      (princ "===== dependency-direction =====\n")
      (dolist (e dep-errors)
        (princ (format "  %s\n" e)))
      (setq failed-any t)))
  (unwind-protect
      (dolist (file ordered-files)
        (when (p/check-file file)
          (setq failed-any t)))
    (dolist (file ordered-files)
      (let ((elc (concat file "c")))
        (when (file-exists-p elc)
          (delete-file elc)))))
  (when failed-any (kill-emacs 1)))

(provide 'precommit-checks)
;;; precommit-checks.el ends here
