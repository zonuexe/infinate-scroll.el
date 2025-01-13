;;; infinite-scroll.el --- Transparent buffer switching during scroll operations -*- lexical-binding: t; -*-

;; Copyright (C) 2025  USAMI Kenta

;; Author: USAMI Kenta <tadsan@zonu.me>
;; URL: https://github.com/zonuexe/infinite-scroll.el
;; Keywords: convenience
;; Version: 0.0.1
;; Package-Requires: ((emacs "29.1"))
;; License: GPL-3.0-or-later

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <https://www.gnu.org/licenses/>.

;;; Commentary:

;; This package provides functionality for seamlessly scrolling to
;; the next or previous buffer when the end or beginning of a buffer
;; is reached.  It operates transparently, allowing users to navigate
;; through related files (e.g., files with same extensions) without
;; needing to manually switch buffers.

;;; Code:
(require 'cl-lib)
(eval-when-compile
  (require 'rx)
  (declare-function nov-next-document "ext:nov" (&optional count))
  (declare-function nov-previous-document "ext:nov" (&optional count))
  (declare-function evil-scroll-up "ext:evil-command" (count))
  (declare-function evil-scroll-down "ext:evil-command" (count)))

;; Custom variables
(defgroup infinite-scroll nil
  "Scrolling transparently to the next or previous buffer."
  :group 'convenience)

(defcustom infinite-scroll-move-cursor-to-boundary t
  "If non-NIL, move the cursor to the buffer's beginning or end after switching.
When enabled, the cursor is moved to the beginning of the buffer
when scrolling down past the first line, or to the end of the buffer
when scrolling up past the last line."
  :type 'boolean
  :safe #'booleanp)

(defcustom infinite-scroll-stop-on-single-file nil
  "If non-NIL, stop infinite scrolling when only one file exists in the directory.
When enabled, infinite scrolling will not attempt to move to the next
or previous file if the directory contains only a single file."
  :type 'boolean
  :safe #'booleanp)

(defvar-local infinite-scroll-method nil)

(defcustom infinite-scroll-method-alist
  (eval-when-compile
    `((doc-view-mode . (doc-view-next-page doc-view-previous-page))
      (help-mode . (help-goto-next-page help-goto-previous-page))
      (Info-mode . (Info-next Info-prev))
      (nov-mode . (nov-next-document nov-previous-document))))
  "An alist mapping major modes to scrolling methods.
Each entry maps a major mode to specific functions for handling
`next' and `prev' actions."
  :type '(alist :key symbol
                :value :value (list (function :tag "Next function")
                                    (function :tag "Previous function"))))

(defcustom infinite-scroll-sibling-file-filter 'same-ext
  "Determines which files are included when scrolling between sibling files."
  :type '(choice (const :tag "Files with the same extension as the current buffer" same-ext)
                 (const :tag "All files in the directory" all))
  :safe (lambda (v) (memq v '(same-ext all))))

(defcustom infinite-scroll-exclued-file-patterns
  (eval-when-compile
    (list (rx "~" eot)                 ;; matches "foo.txt~"
          (rx bot "#" (+ any) "#" eot) ;; matches "#foo.txt#"
          (rx bot ".#")))              ;; matches ".#foo.txt"
  "List of regex patterns for excluding files from infinite scrolling."
  :type '(list regex))

;; Internal functions
(defun infinite-scroll--search-next-file (files current-file)
  "Return the next file in FILES after CURRENT-FILE.
If CURRENT-FILE is the last in the list, wrap around to the beginning."
  (unless (and infinite-scroll-stop-on-single-file (eq 1 (length files)))
    (let ((matched (equal (car-safe (last files)) current-file)))
      (cl-loop for file in files
               if matched
               return file
               else do (setq matched (string= file current-file))))))

(defun infinite-scroll--collect-sibling-files ()
  "Collect sibling files in the current directory based on the filter setting.
This function uses `infinite-scroll-sibling-file-filter` to determine
which files to include:
- If the filter is \\='same-ext, only files with the same extension as
  the current buffer are included.
- If the filter is \\='all, all files in the directory are included.

Excluded files are determined by `infinite-scroll-exclued-file-patterns'."
  (let* ((exclude-pattern (mapconcat #'identity infinite-scroll-exclued-file-patterns "\\|"))
         (files (pcase infinite-scroll-sibling-file-filter
                  ('all (file-expand-wildcards "*"))
                  ('same-ext (let* ((ext (file-name-extension buffer-file-name))
                                    (pattern (format "*.%s" ext)))
                               (file-expand-wildcards pattern))))))
    (cl-remove-if (lambda (f) (string-match-p exclude-pattern f))
                  files)))

(defun infinite-scroll--get-sibling-file (direction)
  "Return the next or previous file based on DIRECTION (\\='next or \\='prev)."
  (when buffer-file-name
    (let* ((files (infinite-scroll--collect-sibling-files))
           (current-file (file-name-nondirectory buffer-file-name)))
      (pcase direction
        ('next (infinite-scroll--search-next-file files current-file))
        ('prev (infinite-scroll--search-next-file (nreverse files) current-file))))))

(defun infinite-scroll--move-cursor (direction)
  "Move the cursor to the beginning or end of the buffer based on DIRECTION.
DIRECTION should be either \\='next or \\='prev:
- \\='next: Move the cursor to the beginning of the buffer.
- \\='prev: Move the cursor to the end of the buffer."
  (pcase direction
    ('next (goto-char (point-min)))
    ('prev (goto-char (point-max)))))

(defun infinite-scroll-visit-sibling-buffer (direction)
  "Visit the next or previous buffer based on DIRECTION.
DIRECTION should be either \\='next or \\='prev."
  (if-let* ((method (or infinite-scroll-method (alist-get major-mode infinite-scroll-method-alist))))
      (prog1 (cond
              ((functionp method) (funcall method 'next))
              ((listp method) (funcall (nth  (if (eq direction 'next) 0 1) method)))
              ((error "Specified unexpected method")))
        (when infinite-scroll-move-cursor-to-boundary
          (infinite-scroll--move-cursor direction)))
    (infinite-scroll-default-visit-buffer-file direction)))

(defun infinite-scroll-default-visit-buffer-file (direction)
  "Visit the next or previous file based on DIRECTION (\\='next or \\='prev)."
  (when-let* ((file (infinite-scroll--get-sibling-file direction)))
    (when-let* ((buf (and infinite-scroll-move-cursor-to-boundary (get-file-buffer file))))
      (with-current-buffer buf
        (infinite-scroll--move-cursor direction)))
    (let (inhibit-message)
      (find-file file)
      (message "Moved to the %s page in buffer: %s." direction file))))

;; Wrapper commands
(defun infinite-scroll-scroll-up-command (arg)
  "Scroll up and visit the next buffer if at the end of the current buffer.
ARG is passed to the underlying `scroll-up-command'."
  (interactive "^P")
  (let ((pos (point)))
    (unwind-protect
        (scroll-up-command arg)
      (when (eq pos (point))
        (infinite-scroll-visit-sibling-buffer 'next)))))

(defun infinite-scroll-scroll-down-command (arg)
  "Scroll down and visit the prev buffer if at the beginning of the current buffer.
ARG is passed to the underlying `scroll-down-command'."
  (interactive "^P")
  (let ((pos (point)))
    (unwind-protect
        (scroll-down-command arg)
      (when (eq pos (point))
        (infinite-scroll-visit-sibling-buffer 'prev)))))

(defun infinite-scroll-forward-page (&optional count)
  "Move forward COUNT pages, or switch to the next buffer at the buffer's end.
This function attempts to move forward by COUNT pages using `forward-page`.
If the cursor remains at the same position (indicating the end of the buffer),
it switches to the next related buffer."
  (interactive "p")
  (let ((pos (point)))
    (forward-page count)
    (when (eq pos (point))
      (infinite-scroll-visit-sibling-buffer 'next))))

(defun infinite-scroll-backward-page (&optional count)
  "Move backward COUNT pages, or switch to the previous buffer at the start.
This function attempts to move backward by COUNT pages using `backward-page`.
If the cursor remains at the same position (indicating the beginning of
the buffer), it switches to the previous related buffer."
  (interactive "p")
  (let ((pos (point)))
    (backward-page count)
    (when (eq pos (point))
      (infinite-scroll-visit-sibling-buffer 'prev))))

(defun infinite-scroll-evil-scroll-down (count)
  ""
  (interactive (list (when current-prefix-arg (prefix-numeric-value current-prefix-arg))))
  (let ((pos (point)))
    (unwind-protect
        (evil-scroll-down count)
      (when (eq pos (point))
        (infinite-scroll-visit-sibling-buffer 'next)))))

(defun infinite-scroll-evil-scroll-up (count)
  ""
  (interactive (list (when current-prefix-arg (prefix-numeric-value current-prefix-arg))))
  (let ((pos (point)))
    (unwind-protect
        (evil-scroll-up count)
      (when (eq pos (point))
        (infinite-scroll-visit-sibling-buffer 'prev)))))

;; Minor modes
(defvar infinite-scroll-lighter " ∞")

(defvar infinite-scroll-mode-map
  (eval-when-compile
    (let ((map (make-keymap)))
      (define-key map [remap scroll-up-command] #'infinite-scroll-scroll-up-command)
      (define-key map [remap scroll-down-command] #'infinite-scroll-scroll-down-command)
      (define-key map [remap backward-page] #'infinite-scroll-backward-page)
      (define-key map [remap forward-page] #'infinite-scroll-forward-page)
      (define-key map [remap evil-scroll-down] #'infinite-scroll-evil-scroll-down)
      (define-key map [remap evil-scroll-up] #'infinite-scroll-evil-scroll-up)
      map)))

;;;###autoload
(define-minor-mode infinite-scroll-mode
  "Minor mode for infinite scrolling across buffers."
  :keymap infinite-scroll-mode-map
  :lighter infinite-scroll-lighter)

;;;###autoload
(defun infinite-scroll-turn-on ()
  "Enable `infinite-scroll-mode'."
  (infinite-scroll-mode +1))

;;;###autoload
(define-globalized-minor-mode infinite-scroll-global-mode infinite-scroll-mode infinite-scroll-turn-on)

(provide 'infinite-scroll)
;;; infinite-scroll.el ends here
