;;; vertico-buffer.el --- Display Vertico in a buffer instead of the minibuffer -*- lexical-binding: t -*-

;; Copyright (C) 2021  Free Software Foundation, Inc.

;; Author: Daniel Mendler <mail@daniel-mendler.de>
;; Maintainer: Daniel Mendler <mail@daniel-mendler.de>
;; Created: 2021
;; Version: 0.1
;; Package-Requires: ((emacs "27.1") (vertico "0.17"))
;; Homepage: https://github.com/minad/vertico

;; This file is part of GNU Emacs.

;; This program is free software: you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <http://www.gnu.org/licenses/>.

;;; Commentary:

;; This package is a Vertico extension, which displays Vertico in a
;; buffer instead of the minibuffer. The buffer display can be enabled
;; by the `vertico-buffer-mode'.

;;; Code:

(require 'vertico)

(defvar-local vertico-buffer--overlay nil)
(defvar-local vertico-buffer--window nil)

(defcustom vertico-buffer-hide-prompt t
  "Hide prompt in the minibuffer."
  :group 'vertico
  :type 'boolean)

(defcustom vertico-buffer-display-action
  '(display-buffer-reuse-window)
  "Display action for the Vertico buffer."
  :group 'vertico
  :type `(choice
          (const :tag "Reuse some window"
                 (display-buffer-reuse-window))
          (const :tag "Below target buffer"
                 (display-buffer-below-selected
                  (window-height . ,(+ 3 vertico-count))))
          (const :tag "Bottom of frame"
                 (display-buffer-at-bottom
                  (window-height . ,(+ 3 vertico-count))))
          (const :tag "Side window on the right"
                 (display-buffer-in-side-window
                  (side . right)
                  (window-width . 0.3)))
          (const :tag "Side window on the left"
                 (display-buffer-in-side-window
                  (side . left)
                  (window-width . 0.3)))
          (const :tag "Side window at the top"
                 (display-buffer-in-side-window
                  (window-height . ,(+ 3 vertico-count))
                  (side . top)))
          (const :tag "Side window at the bottom"
                 (display-buffer-in-side-window
                  (window-height . ,(+ 3 vertico-count))
                  (side . bottom)))
          (sexp :tag "Other")))

(defun vertico-buffer--redisplay (win)
  "Redisplay window WIN."
  (when-let (mbwin (active-minibuffer-window))
    (when (eq (window-buffer mbwin) (current-buffer))
      (let ((old cursor-in-non-selected-windows)
            (new (and (eq (selected-window) mbwin) 'box)))
        (unless (eq new old)
          (setq-local cursor-in-non-selected-windows new)
          (force-mode-line-update t)))
      (when (eq win vertico-buffer--window)
        (setq-local truncate-lines (< (window-point vertico-buffer--window)
                                      (* 0.8 (window-width vertico-buffer--window))))
        (set-window-point vertico-buffer--window (point))
        (when vertico-buffer-hide-prompt
          (set-window-vscroll mbwin 100))))))

(defun vertico-buffer--setup ()
  "Setup minibuffer overlay, which pushes the minibuffer content down."
  (add-hook 'pre-redisplay-functions 'vertico-buffer--redisplay nil 'local)
  (let ((temp (generate-new-buffer "*vertico*")))
    (setq vertico-buffer--window (display-buffer temp vertico-buffer-display-action))
    (set-window-buffer vertico-buffer--window (current-buffer))
    (kill-buffer temp))
  (let ((sym (make-symbol "vertico-buffer--destroy"))
        (mbwin (active-minibuffer-window))
        (depth (recursion-depth))
        (now (window-parameter vertico-buffer--window 'no-other-window))
        (ndow (window-parameter vertico-buffer--window 'no-delete-other-windows)))
    (fset sym (lambda ()
                (when (= depth (recursion-depth))
                  (when (window-live-p vertico-buffer--window)
                    (set-window-parameter vertico-buffer--window 'no-other-window now)
                    (set-window-parameter vertico-buffer--window 'no-delete-other-windows ndow))
                  (when vertico-buffer-hide-prompt
                    (set-window-vscroll mbwin 0))
                  (remove-hook 'minibuffer-exit-hook sym))))
    ;; NOTE: We cannot use a buffer-local minibuffer-exit-hook here.
    ;; The hook will not be called when abnormally exiting the minibuffer
    ;; from another buffer via `keyboard-escape-quit'.
    (add-hook 'minibuffer-exit-hook sym))
  (set-window-parameter vertico-buffer--window 'no-other-window t)
  (set-window-parameter vertico-buffer--window 'no-delete-other-windows t)
  (when vertico-buffer-hide-prompt
    (overlay-put vertico--candidates-ov 'window vertico-buffer--window)
    (when vertico--count-ov
      (overlay-put vertico--count-ov 'window vertico-buffer--window))
    (setq vertico-buffer--overlay (make-overlay (point-max) (point-max) nil t t))
    (overlay-put vertico-buffer--overlay 'window (selected-window))
    (overlay-put vertico-buffer--overlay 'priority 1000)
    (overlay-put vertico-buffer--overlay 'before-string "\n\n"))
  (setq-local show-trailing-whitespace nil
              truncate-lines t
              mode-line-format
              (list (format " %s %s "
                            (propertize "*Vertico*" 'face 'bold)
                            (string-remove-suffix ": " (minibuffer-prompt)))
                    '(:eval (vertico--format-count)))
              cursor-in-non-selected-windows 'box
              vertico-count (- (/ (window-pixel-height vertico-buffer--window)
                                  (default-line-height)) 2)))

;;;###autoload
(define-minor-mode vertico-buffer-mode
  "Display Vertico in a buffer instead of the minibuffer."
  :global t :group 'vertico
  (cond
   (vertico-buffer-mode
    (advice-add #'vertico--setup :after #'vertico-buffer--setup)
    (advice-add #'vertico--resize-window :override #'ignore))
   (t
    (advice-remove #'vertico--setup #'vertico-buffer--setup)
    (advice-remove #'vertico--resize-window #'ignore))))

(provide 'vertico-buffer)
;;; vertico-buffer.el ends here
