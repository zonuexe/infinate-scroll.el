;;; infinate-scroll.el --- Scrolling transparently to the next or previous buffer  -*- lexical-binding: t; -*-

;; Copyright (C) 2025  USAMI Kenta

;; Author: USAMI Kenta <tadsan@zonu.me>
;; URL: https://github.com/zonuexe/infinate-scroll.el
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
  (declare-function nov-previous-document "ext:nov" (&optional count)))

(defgroup infinate-scroll nil
  "Scrolling transparently to the next or previous buffer."
  :group 'convenience)

(defcustom infinate-scroll-move-cursor-to-boundary t
  "If non-NIL, move the cursor to the buffer's beginning or end after switching.
When enabled, the cursor is moved to the beginning of the buffer
when scrolling down past the first line, or to the end of the buffer
when scrolling up past the last line."
  :type 'boolean
  :safe #'booleanp)

(defcustom infinate-scroll-stop-on-single-file nil
  "If non-NIL, stop infinite scrolling when only one file exists in the directory.
When enabled, infinite scrolling will not attempt to move to the next
or previous file if the directory contains only a single file."
  :type 'boolean
  :safe #'booleanp)

(defcustom infinate-scroll-method-alist
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

(defcustom infinate-scroll-exclued-file-patterns
  (eval-when-compile
    (list (rx "~" eot) ;; matches "foo.txt~"
          (rx bot "#" (+ any) "#" eot) ;; matches "#foo.txt#"
          (rx bot ".#"))) ;; matches ".#foo.txt"
  "List of regex patterns for excluding files from infinite scrolling."
  :type '(list regex))

(defvar-local infinate-scroll-method nil)

(defvar infinate-scroll-lighter " ∞")

(defvar infinate-scroll-mode-map
  (eval-when-compile
    (let ((map (make-keymap)))
      (define-key map [remap scroll-up-command] #'infinate-scroll-scroll-up-command)
      (define-key map [remap scroll-down-command] #'infinate-scroll-scroll-down-command)
      map)))

(define-minor-mode infinate-scroll-mode
  "Minor mode for infinite scrolling across buffers."
  :keymap infinate-scroll-mode-map
  :lighter infinate-scroll-lighter)

(defun infinate-scroll-turn-on ()
  "Enable `infinate-scroll-mode'."
  (infinate-scroll-mode +1))

(defun infinate-scroll--search-next-file (files current-file)
  "Return the next file in FILES after CURRENT-FILE.
If CURRENT-FILE is the last in the list, wrap around to the beginning."
  (unless (and infinate-scroll-stop-on-single-file (eq 1 (length files)))
    (let ((matched (equal (car-safe (last files)) current-file)))
      (cl-loop for file in files
               if matched
               return file
               else do (setq matched (string= file current-file))))))

(defun infinate-scroll--get-sibling-file (direction)
  "Return the next or previous file based on DIRECTION (\\='next or \\='prev)."
  (when buffer-file-name
    (let* ((ext (file-name-extension buffer-file-name))
           (pattern (format "*.%s" ext))
           (exclude-pattern (mapconcat #'identity infinate-scroll-exclued-file-patterns "\\|"))
           (files (cl-remove-if (lambda (f) (string-match-p exclude-pattern f))
                                (file-expand-wildcards pattern)))
           (current-file (file-name-nondirectory buffer-file-name)))
      (pcase direction
        ('next (infinate-scroll--search-next-file files current-file))
        ('prev (infinate-scroll--search-next-file (nreverse files) current-file))))))

(defun infinate-scroll-scroll-up-command (arg)
  "Scroll up and visit the next buffer if at the end of the current buffer.
ARG is passed to the underlying `scroll-up-command'."
  (interactive "^P")
  (let ((pos (point)))
    (unwind-protect
        (scroll-up-command arg)
      (when (eq pos (point))
        (infinate-scroll-visit-sibling-buffer 'next)))))

(defun infinate-scroll-scroll-down-command (arg)
  "Scroll down and visit the prev buffer if at the beginning of the current buffer.
ARG is passed to the underlying `scroll-down-command'."
  (interactive "^P")
  (let ((pos (point)))
    (unwind-protect
        (scroll-down-command arg)
      (when (eq pos (point))
        (infinate-scroll-visit-sibling-buffer 'prev)))))

(defun infinate-scroll--move-cursor (direction)
  "Move the cursor to the beginning or end of the buffer based on DIRECTION.
DIRECTION should be either \\='next or \\='prev:
- \\='next: Move the cursor to the beginning of the buffer.
- \\='prev: Move the cursor to the end of the buffer."
  (pcase direction
    ('next (goto-char (point-min)))
    ('prev (goto-char (point-max)))))

(defun infinate-scroll-visit-sibling-buffer (direction)
  "Visit the next or previous buffer based on DIRECTION.
DIRECTION should be either \\='next or \\='prev."
  (if-let* ((method (or infinate-scroll-method (alist-get major-mode infinate-scroll-method-alist))))
      (prog1 (cond
              ((functionp method) (funcall method 'next))
              ((listp method) (funcall (nth  (if (eq direction 'next) 0 1) method)))
              ((error "Specified unexpected method")))
        (when infinate-scroll-move-cursor-to-boundary
          (infinate-scroll--move-cursor direction)))
    (infinate-scroll-default-visit-buffer-file direction)))

(defun infinate-scroll-default-visit-buffer-file (direction)
  "Visit the next or previous file based on DIRECTION (\\='next or \\='prev)."
  (when-let* ((file (infinate-scroll--get-sibling-file direction)))
    (when-let* ((buf (and infinate-scroll-move-cursor-to-boundary (get-file-buffer file))))
      (with-current-buffer buf
        (infinate-scroll--move-cursor direction)))
    (let (inhibit-message)
      (find-file file))
    (message "Moved to the %s page in buffer: %s." direction file)))

(define-globalized-minor-mode infinate-scroll-global-mode infinate-scroll-mode infinate-scroll-turn-on)

(provide 'infinate-scroll)
;;; infinate-scroll.el ends here
