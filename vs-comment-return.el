;;; vs-comment-return.el --- Comment return like Visual Studio  -*- lexical-binding: t; -*-

;; Copyright (C) 2023-2025 Shen, Jen-Chieh

;; Author: Shen, Jen-Chieh <jcs090218@gmail.com>
;; Maintainer: Shen, Jen-Chieh <jcs090218@gmail.com>
;; URL: https://github.com/emacs-vs/vs-comment-return
;; Version: 0.2.0
;; Package-Requires: ((emacs "28.1"))
;; Keywords: convenience

;; This file is not part of GNU Emacs.

;; This program is free software: you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program. If not, see <https://www.gnu.org/licenses/>.

;;; Commentary:
;;
;; Comment return like Visual Studio.
;;

;;; Code:

(defgroup vs-comment-return nil
  "Comment return like Visual Studio."
  :prefix "vs-comment-return-"
  :group 'convenience
  :link '(url-link :tag "Repository" "https://github.com/emacs-vs/vs-comment-return"))

(defcustom vs-comment-return-inhibit-prefix
  '("//" "--" "#")
  "Exclude these comment prefixes."
  :type '(list string)
  :group 'vs-comment-return)

(defcustom vs-comment-return-keep-suffix nil
  "Do not expand suffix comment symbol."
  :type 'boolean
  :group 'vs-comment-return)

(defcustom vs-comment-return-cancel-after nil
  "If non-nil, remove the prefix after returning twice."
  :type 'boolean
  :group 'vs-comment-return)

;;
;; (@* "Entry" )
;;

(defun vs-comment-return-mode--enable ()
  "Enable `vs-comment-return' in current buffer."
  (advice-add (key-binding (kbd "RET")) :around #'vs-comment-return--advice-around))

(defun vs-comment-return-mode--disable ()
  "Disable `vs-comment-return' in current buffer."
  (advice-remove (key-binding (kbd "RET")) #'vs-comment-return--advice-around))

;;;###autoload
(define-minor-mode vs-comment-return-mode
  "Minor mode `vs-comment-return-mode'."
  :lighter " VS-ComRet"
  :group vs-comment-return
  (if vs-comment-return-mode (vs-comment-return-mode--enable)
    (vs-comment-return-mode--disable)))

;;
;; (@* "Util" )
;;

(defun vs-comment-return--before-char-string ()
  "Get the before character as the `string'."
  (if (char-before) (string (char-before)) ""))

(defun vs-comment-return--string-match-mut-p (str1 str2)
  "Mutual way to check STR1 and STR2 with function `string-match-p'."
  (and (stringp str1) (stringp str2)
       (or (string-match-p str1 str2) (string-match-p str2 str1))))

(defun vs-comment-return--comment-p ()
  "Return non-nil if it's inside comment."
  (nth 4 (syntax-ppss)))

(defun vs-comment-return--goto-start-comment ()
  "Go to the start of the comment."
  (while (and (vs-comment-return--comment-p)
              (not (bobp)))
    (ignore-errors (forward-char -1)))
  ;; Ensure the beginning of the syntax.
  (when (re-search-backward "[[:space:]]" (line-beginning-position) t)
    (forward-char 1)))

(defun vs-comment-return--goto-end-comment ()
  "Go to the end of the comment."
  (while (and (vs-comment-return--comment-p)
              (not (eobp)))
    (ignore-errors (forward-char 1)))
  ;; Ensure the end of the syntax.
  (when (re-search-forward "[[:space:]]" (line-end-position) t)
    (forward-char -1)))

(defun vs-comment-return--comment-start-point ()
  "Return comment start point."
  (save-excursion (vs-comment-return--goto-start-comment) (point)))

(defun vs-comment-return--comment-end-point ()
  "Return comment end point."
  (save-excursion (vs-comment-return--goto-end-comment) (point)))

(defun vs-comment-return--multiline-comment-p ()
  "Return non-nil, if current point inside multi-line comment block."
  (let* ((start (vs-comment-return--comment-start-point))
         (end   (vs-comment-return--comment-end-point))
         (old-major-mode major-mode)
         (start-point (1+ (- (point) start)))
         (content (buffer-substring start end)))
    (with-temp-buffer
      (insert content)
      (goto-char start-point)
      (insert "\n")
      (delay-mode-hooks (funcall old-major-mode))
      (ignore-errors (font-lock-ensure))
      (vs-comment-return--comment-p))))

(defun vs-comment-return--indent ()
  "Indent entire comment region."
  (indent-region (vs-comment-return--comment-start-point)
                 (vs-comment-return--comment-end-point)))

(defun vs-comment-return--re-search-forward-end (regexp &optional bound)
  "Repeatedly search REGEXP to BOUND."
  (let ((repeat (1- (length regexp))))
    (while (re-search-forward regexp bound t)
      (backward-char repeat))))  ; Always move backward to search repeatedly!

(defun vs-comment-return--line-empty-p ()
  "Current line empty, but accept spaces/tabs in there.  (not absolute)."
  (save-excursion (beginning-of-line) (looking-at "[[:space:]\t]*$")))

(defun vs-comment-return--infront-first-char-at-line-p (&optional pt)
  "Return non-nil if there is nothing infront of the right from the PT."
  (save-excursion
    (when pt (goto-char pt))
    (null (re-search-backward "[^ \t]" (line-beginning-position) t))))

;;
;; (@* "Cancelling" )
;;

(defvar-local vs-comment-return--return-last-p nil
  "Store weather we hit return twice in a row.")

(defun vs-comment-return--pre-command (&rest _)
  "Execution before command's execution."
  (add-hook 'post-self-insert-hook #'vs-comment-return--post-self-insert nil t)
  (add-hook 'post-command-hook #'vs-comment-return--post-command nil t)
  ;; De-register ourselves!
  (remove-hook 'pre-command-hook #'vs-comment-return--pre-command t))

(defun vs-comment-return--post-command (&rest _)
  "Execution after command's execution."
  ;; De-register ourselves!
  (remove-hook 'post-command-hook #'vs-comment-return--post-command t)
  ;; XXX: Don't know why `cmake-mode' doesn't run `post-self-insert-hook'
  ;; on its own; handle it!
  (when (memq #'vs-comment-return--post-self-insert post-self-insert-hook)
    (vs-comment-return--post-self-insert))
  ;; Cancel action!
  (remove-hook 'post-self-insert-hook #'vs-comment-return--post-self-insert t))

(defun vs-comment-return--post-self-insert (&rest _)
  "Execution after self insertion."
  (when (and vs-comment-return-cancel-after
             (memq last-command-event '(?\n ?\r))
             (vs-comment-return--line-empty-p))
    ;; At this point, it means we have enter the return twice in a row. The
    ;; previous line above must be a empty comment line, which is safe to
    ;; be removed.
    (forward-line -1)
    (delete-region (1- (line-beginning-position)) (line-end-position))
    (forward-line 1))
  ;; De-register ourselves!
  (remove-hook 'post-self-insert-hook #'vs-comment-return--post-self-insert t))

;;
;; (@* "Core" )
;;

(defun vs-comment-return--backward-until-not-comment ()
  "Move backward to the point when it's not comment."
  (save-excursion
    (while (and (vs-comment-return--comment-p)
                (not (bolp)))
      (backward-char 1))
    (if (re-search-backward "[ \t\n]" (line-beginning-position) t)
        (1+ (point))
      (line-beginning-position))))

(defun vs-comment-return--get-comment-prefix ()
  "Return comment prefix string."
  (save-excursion
    (end-of-line)
    (let ((comment-start-skip (or comment-start-skip comment-start)))
      (ignore-errors (comment-search-backward (line-beginning-position) t)))
    ;; Double check if comment exists
    (unless (= (point) (line-beginning-position))
      (unless (string= (vs-comment-return--before-char-string) " ")
        (unless (re-search-forward "[ \t]" (line-end-position) t)
          (goto-char (line-end-position))))
      (buffer-substring (vs-comment-return--backward-until-not-comment) (point)))))

(defun vs-comment-return--comment-doc-p (prefix)
  "Return non-nil if comment (PREFIX) is a valid document."
  (when prefix
    (let ((trimmed (string-trim comment-start)))
      (with-temp-buffer
        (insert prefix)
        (goto-char (point-min))
        (vs-comment-return--re-search-forward-end trimmed (line-end-position))
        (ignore-errors (forward-char 1))
        (delete-region (point-min) (point))
        (string-empty-p (string-trim (buffer-string)))))))

(defun vs-comment-return--doc-only-line-column (prefix)
  "Return nil there is code interaction within the same line; else we return
the column of the line.

We use PREFIX for navigation; we search it, then check what is infront."
  (when prefix
    (save-excursion
      ;; Handle nested comment.
      ;;
      ;; That's why we have an empty while loop here.
      (while (search-backward (string-trim prefix) (line-beginning-position) t))
      (when (vs-comment-return--infront-first-char-at-line-p)
        (current-column)))))

(defun vs-comment-return--next-line-comment-prefix ()
  "Return non-nil when next line is a comment."
  (unless (eobp)
    (save-excursion
      (forward-line 1)
      (end-of-line)
      (vs-comment-return--get-comment-prefix))))

(defun vs-comment-return--empty-comment-p (prefix)
  "Return non-nil if current line comment is empty (PREFIX only)."
  (when prefix
    (let* ((line (thing-at-point 'line))
           (line (string-trim line))
           (content (string-replace (string-trim prefix) "" line)))
      (string-empty-p (string-trim content)))))

(defun vs-comment-return--advice-around (func &rest args)
  "Advice bind around return (FUNC and ARGS)."
  (if (not vs-comment-return-mode)
      (apply func args)
    (vs-comment-return--do-return func args)))

(defun vs-comment-return--comment-line (prefix &optional column)
  "Insert PREFIX comment with COLUMN for alignment."
  (when column
    (when (vs-comment-return--line-empty-p)
      (delete-region (line-beginning-position) (line-end-position)))
    (indent-to-column column))
  (insert (string-trim prefix) " "))

(defun vs-comment-return--pick-shorter-prefix (prefix1 prefix2)
  "Pick shorter prefix between PREFIX1 and PREFIX2."
  (cond ((and (stringp prefix1) (stringp prefix2))
         (if (<= (length prefix1) (length prefix2))
             prefix1
           prefix2))
        ((stringp prefix1) prefix1)
        (t prefix2)))

(defun vs-comment-return--do-return (func args)
  "Do VS like comment return (FUNC and ARGS)."
  (cond
   ((not (vs-comment-return--comment-p))
    (apply func args))
   ;; Multi-line comment
   ((vs-comment-return--multiline-comment-p)
    (apply func args)
    (vs-comment-return--c-like-return))
   ;; Single line comment
   (t
    (let* ((prefix         (vs-comment-return--get-comment-prefix))
           (doc-line       (vs-comment-return--comment-doc-p prefix))
           (empty-comment  (vs-comment-return--empty-comment-p prefix))
           (prefix-next-ln (vs-comment-return--next-line-comment-prefix))
           (next-doc-line  (vs-comment-return--comment-doc-p prefix-next-ln))
           (column         (vs-comment-return--doc-only-line-column prefix))
           (column-next-ln (save-excursion
                             (forward-line 1) (end-of-line)
                             (vs-comment-return--doc-only-line-column prefix-next-ln))))
      (apply func args)  ; make return
      (when
          (and (vs-comment-return--infront-first-char-at-line-p)  ; must on newline
               column  ; Is comment line?
               (or (and
                    ;; Check if the command style matches.
                    (vs-comment-return--string-match-mut-p prefix-next-ln prefix)
                    ;; Check current comment and next comment is all document lines.
                    doc-line next-doc-line column-next-ln)
                   (and doc-line             ; if previous doc line
                        (not empty-comment)  ; if previous comment line is not empty
                        (not (member (string-trim prefix) vs-comment-return-inhibit-prefix)))))
        ;; Why shorter prefix is chosen? Most of the document string prefix are
        ;; shorter one. For example,
        ;;
        ;; For Lua,
        ;;
        ;; --- (longer)
        ;; --  (shoter)
        ;;
        ;; For C-like multi-line comment,
        ;;
        ;; /** (longer)
        ;;  *  (shorter)
        ;;  */
        ;;
        ;; In general, most programming languages uses the shorter prefix.
        ;; It kinda make sense since it's nicer and most of them want to enlarge
        ;; the splitter or start of the section!
        (let ((shorter-prefix (vs-comment-return--pick-shorter-prefix prefix prefix-next-ln)))
          (vs-comment-return--comment-line shorter-prefix column))
        ;; Here we handle the cancel action!
        (when (and vs-comment-return-cancel-after
                   (not prefix-next-ln))  ; only happens when next line is not comment
          (add-hook 'pre-command-hook #'vs-comment-return--pre-command nil t)
          (remove-hook 'post-command-hook #'vs-comment-return--post-command t)
          (remove-hook 'post-self-insert-hook #'vs-comment-return--post-self-insert t)))))))

;;
;; (@* "C-like" )
;;

(defun vs-comment-return--c-like-multiline-comment-p ()
  "Return non-nil if we are in c-like multiline comment."
  (save-excursion
    (when (comment-search-backward (point-min) t)
      (string-prefix-p "/*" (vs-comment-return--get-comment-prefix)))))

(defun vs-comment-return--c-like-return ()
  "Do C-like comment return for /**/."
  (when (vs-comment-return--c-like-multiline-comment-p)
    (delete-region (line-beginning-position) (point))
    (vs-comment-return--comment-line "* ")
    (vs-comment-return--indent)
    (when (and (not vs-comment-return-keep-suffix)
               (save-excursion (search-forward "*/" (line-end-position) t)))
      (save-excursion
        (insert "\n")
        (indent-for-tab-command)))))

(provide 'vs-comment-return)
;;; vs-comment-return.el ends here
