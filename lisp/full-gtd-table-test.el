;;; full-gtd-table-test.el --- Tests for Full-GTD table utilities  -*- lexical-binding: t; -*-

;;; Commentary:

;; Tests for non-destructive Org table column-width handling.

;;; Code:

(require 'cl-lib)
(require 'ert)
(require 'org)
(require 'full-gtd-table)

(defun full-gtd-test-table--display-state (start end)
  "Return display-related properties between START and END."
  (let ((position start)
        (state '()))
    (while (< position end)
      (push (list (get-char-property position 'display)
                  (get-char-property position 'invisible))
            state)
      (setq position (1+ position)))
    (nreverse state)))

(ert-deftest full-gtd-table-width-cookie-preserves-complete-content ()
  "A constrained column must retain its complete buffer contents."
  (with-temp-buffer
    (org-mode)
    (full-gtd-table-insert-header
     '("Headline" ("L3 Area" . 20) "Unconstrained"))
    (full-gtd-table-insert-row
     "Task"
     "task-id"
     "action.org"
     '("This horizon value is substantially longer than twenty characters"
       "This unconstrained value must remain fully visible"))
    (full-gtd-table-finalize)
    (should (string-match-p
             "|[ \t]*<[ \t]*20[ \t]*>[ \t]*|"
             (buffer-substring-no-properties (point-min) (point-max))))
    (goto-char (point-min))
    (should (get-char-property (point) 'invisible))
    (should (string-match-p
             (regexp-quote
              "This horizon value is substantially longer than twenty characters")
             (buffer-substring-no-properties (point-min) (point-max))))
    (should (string-match-p
             (regexp-quote
              "This unconstrained value must remain fully visible")
             (buffer-substring-no-properties (point-min) (point-max))))))

(ert-deftest full-gtd-table-width-cookie-can-toggle-without-changing-text ()
  "Org column-width toggling must only change the display layer."
  (with-temp-buffer
    (org-mode)
    (full-gtd-table-insert-header
     '("Headline" ("L3 Area" . 20)))
    (full-gtd-table-insert-row
     "Task"
     "task-id"
     "action.org"
     '("This horizon value is substantially longer than twenty characters"))
    (full-gtd-table-finalize)
    (goto-char (point-min))
    (re-search-forward
     (regexp-quote
      "This horizon value is substantially longer than twenty characters"))
    (org-table-goto-column 2)
    (let* ((text-before
            (buffer-substring-no-properties (point-min) (point-max)))
           (field-start
            (save-excursion
              (search-backward "|")
              (1+ (point))))
           (field-end
            (save-excursion
              (search-forward "|")
              (1- (point))))
           (display-before
            (full-gtd-test-table--display-state field-start field-end)))
      (should
       (cl-some (lambda (properties)
                  (cl-some #'identity properties))
                display-before))
      (org-table-toggle-column-width)
      (should (equal text-before
                     (buffer-substring-no-properties (point-min) (point-max))))
      (should-not
       (equal display-before
              (full-gtd-test-table--display-state field-start field-end)))
      (org-table-toggle-column-width)
      (should (equal text-before
                     (buffer-substring-no-properties (point-min) (point-max)))))))

(ert-deftest full-gtd-table-finalize-does-not-expand-org-width-columns ()
  "Finalization must preserve the constrained state created by Org."
  (with-temp-buffer
    (org-mode)
    (full-gtd-table-insert-header
     '("Headline" ("L3 Area" . 20)))
    (full-gtd-table-insert-row
     "Task"
     "task-id"
     "action.org"
     '("This horizon value is substantially longer than twenty characters"))
    (let ((toggle-count 0))
      (cl-letf (((symbol-function 'org-table-toggle-column-width)
                 (lambda ()
                   (setq toggle-count (1+ toggle-count)))))
        (full-gtd-table-finalize))
      (should (= toggle-count 0)))))

(ert-deftest full-gtd-table-finalize-shrinks-columns-in-multiple-tables ()
  "Every table in a buffer must independently start in a shrunk state.
This reproduces the Weekly Review / Horizon View scenario where many
tables share the same buffer and column positions."
  (with-temp-buffer
    (org-mode)
    (dotimes (_ 2)
      (full-gtd-table-insert-header
       '("Headline" ("L3 Area" . 20)))
      (full-gtd-table-insert-row
       "Task"
       "task-id"
       "action.org"
       '("This horizon value is substantially longer than twenty characters"))
      (full-gtd-table-finalize)
      (goto-char (point-max))
      (insert "\n"))
    (goto-char (point-min))
    (dotimes (_ 2)
      (re-search-forward
       (regexp-quote
        "This horizon value is substantially longer than twenty characters"))
      (let* ((field-end
              (save-excursion
                (search-forward "|")
                (1- (point))))
             (display-state
              (full-gtd-test-table--display-state (point) field-end)))
        (should
         (cl-some (lambda (properties)
                    (cl-some #'identity properties))
                  display-state))))))

(ert-deftest full-gtd-table-shrink-buffer-restores-constrained-display ()
  "Final buffer shrinking must restore width constraints after post-processing."
  (with-temp-buffer
    (org-mode)
    (full-gtd-table-insert-header
     '("Headline" ("L3 Area" . 20)))
    (full-gtd-table-insert-row
     "Task"
     "task-id"
     "action.org"
     '("This horizon value is substantially longer than twenty characters"))
    (full-gtd-table-finalize)
    (remove-list-of-text-properties
     (point-min) (point-max) '(display invisible))
    (full-gtd-table-shrink-buffer)
    (re-search-backward
     (regexp-quote
      "This horizon value is substantially longer than twenty characters"))
    (let ((field-end
           (save-excursion
             (search-forward "|")
             (1- (point)))))
      (should
       (cl-some
        (lambda (properties)
          (cl-some #'identity properties))
        (full-gtd-test-table--display-state (point) field-end))))))

(full-gtd-table-define-navigators "full-gtd-test-table")

(ert-deftest full-gtd-table-column-navigation-stays-in-row ()
  "Horizontal navigation moves one column and never crosses a row boundary."
  (with-temp-buffer
    (org-mode)
    (full-gtd-table-insert-header '("First" "Second" "Third"))
    (full-gtd-table-insert-row
     "Task"
     "task-id"
     "action.org"
     '("Value 2" "Value 3"))
    (full-gtd-table-finalize)
    (goto-char (point-min))
    (while (not (eq (full-gtd-table-line-type) 'data))
      (forward-line 1))
    (let ((row (line-number-at-pos)))
      (org-table-goto-column 1)
      (full-gtd-test-table--next-column)
      (should (= (org-table-current-column) 2))
      (full-gtd-test-table--next-column)
      (should (= (org-table-current-column) 3))
      (full-gtd-test-table--next-column)
      (should (= (org-table-current-column) 3))
      (should (= (line-number-at-pos) row))
      (full-gtd-test-table--previous-column)
      (should (= (org-table-current-column) 2))
      (full-gtd-test-table--previous-column)
      (should (= (org-table-current-column) 1))
      (full-gtd-test-table--previous-column)
      (should (= (org-table-current-column) 1))
      (should (= (line-number-at-pos) row)))))

(ert-deftest full-gtd-table-width-cookie-row-is-not-data ()
  "Width-cookie rows must be excluded from table navigation."
  (with-temp-buffer
    (org-mode)
    (full-gtd-table-insert-header
     '("Headline" ("L3 Area" . 20)))
    (goto-char (point-min))
    (should (eq (full-gtd-table-line-type) 'cookie))
    (forward-line 1)
    (should (eq (full-gtd-table-line-type) 'header))
    (forward-line 1)
    (should (eq (full-gtd-table-line-type) 'separator))))

(provide 'full-gtd-table-test)

;;; full-gtd-table-test.el ends here
