;;; remind-bindings.el --- Reminders for your init bindings -*- lexical-binding: t; -*-

;; Copright (C) 2020 Mehmet Tekman <mtekman89@gmail.com>

;; Author: Mehmet Tekman
;; URL: https://github.com/mtekman/omni-quotes-rememberbindings.el
;; Keywords: outlines
;; Package-Requires: ((emacs "24.4") (omni-quotes))
;; Version: 0.2

;;; Commentary:

;; This package parses your Emacs init file for use-package or
;; global-set-key calls and summarizes the bindings it detects on a
;; package by package basis.
;;
;; The package makes use of the omni-quotes package to give you
;; a small reminder during idle periods.

;;; Code:
(defgroup remind-bindings nil
  "Group for remembering bindings."
  :group 'emacs)

(defgroup remind-bindings-format nil
  "Group for formatting how the reminders are displayed"
  :group 'remind-bindings)

(defvar remind-bindings--quoteslist nil
  "List of string to prompt users during idle times")

(defcustom remind-bindings-initfile nil
  "The Emacs init file with your bindings in it."
  :type 'string
  :group 'remind-bindings)

(defcustom remind-bindings--format-bincom "%s → %s"
  "The format for displaying the binding (first %s) and the command (last %s)."
  :type 'string
  :group 'remind-bindings-format)

(defcustom remind-bindings--format-packbincom "[%s] %s"
  "The format for displaying the package (first %s) and the bindings (last %s)."
  :type 'string
  :group 'remind-bindings-format)

(defcustom remind-bindings--format-bindingsep " | "
  "The separator between the bindings of the same package."
  :type 'string
  :group 'remind-bindings-format)

(defun remind-bindings-nextusepackage ()
  "Get the name and parenthesis bounds of the next ‘use-package’."
  (interactive)
  (search-forward "(use-package")
  (beginning-of-line)
  (let* ((bound (show-paren--default))
         (inner (nth 0 bound))
         (outer (nth 3 bound)))
    (if (not bound)
        (progn (move-end-of-line 1) nil)
      (search-forward "use-package " outer t)
      (let* ((beg (point))
             (end (progn
                    (search-forward-regexp "\\( \\|)\\|$\\)" outer)
                    (point)))
             (name (buffer-substring-no-properties beg end)))
        (goto-char outer)
        `(,name ,inner ,outer)))))

(defun remind-bindings-nextglobalkeybind ()
  "Get the binding and name of the next ‘global-set-key’."
  (interactive)
  (search-forward "(global-set-key ") ;; throw error if no more
  (beginning-of-line) ;; get the total bounds
  (let* ((bound (show-paren--default))
         (first (nth 0 bound))
         (last (nth 3 bound)))
    (search-forward "global-set-key " last)
    (let* ((bound (show-paren--default))
           (keybf (nth 0 bound))
           (keybl (nth 3 bound))
           (keyb (buffer-substring-no-properties
                  keybf keybl)))
      (when (search-forward "kbd \"" keybl t)
        (let ((beg (point))
              (end (search-forward "\"" keybl)))
          (setq keyb (buffer-substring-no-properties
                      beg (- end 1)))))
    ;; Try to grab the command, quote or interactive
      (condition-case nofuncstart
          (progn (unless (search-forward "(interactive) " last t)
                   (unless (search-forward "'" last t)
                     (unless (search-forward "(" last t))))
                 (let* ((func
                         (buffer-substring-no-properties
                          (point) (- last 1)))
                        (package-name (or (remind-bindings-fromfunc-getpackagename func)
                                          remind-bindings-initfile)))
                   (end-of-line)
                   (let ((bname (format remind-bindings--format-bincom keyb func)))
                     `(,package-name ,bname))))
        (error
         ;; Move to end of line and give nil
         (end-of-line))))))

(defun remind-bindings-getglobal ()
  "Process entire Emacs init.el for global bindings and build an alist map grouped on "
  (interactive)
  (with-current-buffer remind-bindings-initfile
    (save-excursion
      (goto-char 0)
      (let ((globbers nil)
            (stop nil)
            (testfn 'string=))
        (condition-case err
            (while (not stop)
              (let ((glob (remind-bindings-nextglobalkeybind)))
                (when glob
                  (let ((pname (string-trim (first glob)))
                        (binde (last glob)))
                    (if (map-contains-key globbers pname testfn)
                        (let* ((values (map-elt globbers pname nil testfn))
                               (newvls (append values binde)))
                          (map-put globbers pname newvls testfn))
                      ;; if it doesn't exist, initialise
                      (map-put globbers pname binde testfn)))
                  (end-of-line))))
          (error
           (end-of-line)
           (setq stop t)))
        (map-into globbers 'hash-table)))))

(defun remind-bindings-fromfunc-getpackagename (fname)
  "Get the name of the package the FNAME belongs to.  Return nil if none found."
  (interactive)
  (let ((packname (symbol-file (intern fname))))
    (when packname
      (let* ((bnamext (car (last (split-string packname "/")))))
        ;; name without extension
        (car (split-string bnamext "\\."))))))

(defun remind-bindings-bindsinpackage (packinfo)
  "Return the name and bindings for the current package named and bounded by PACKINFO."
  (interactive)
  (let ((bindlist (list (nth 0 packinfo))) ;; package name is first
        (inner (nth 1 packinfo))
        (outer (nth 2 packinfo)))
    (when inner
      (goto-char inner)
      (save-excursion
        (search-forward ":bind " outer t)
        (while (search-forward-regexp "\( ?\"[^)]*\" ?\. [^\") ]*\)" outer t)
          (save-excursion
            (let* ((end (- (point) 1))
                   (sta (+ (search-backward "(") 1))
                   (juststr (buffer-substring-no-properties sta end))
                   (bin-comm (split-string juststr " . ")))
              (let* ((bin  (nth 1 (split-string (car bin-comm) "\"")))
                     (comm (car (cdr bin-comm)))
                     (psnickle (format remind-bindings--format-bincom bin comm)))
                (add-to-list 'bindlist psnickle t)))))
        bindlist))))


(defun remind-bindings-getusepackages ()
  "Process entire Emacs init.el for package bindings."
  (interactive)
  (with-current-buffer remind-bindings-initfile
    (save-excursion
      (goto-char 0)
      (let ((packbinds nil)
            (stop nil))
        (while (not stop)
          (condition-case err
              (let ((packinfo (remind-bindings-nextusepackage)))
                (when (nth 1 packinfo) ;; has bounds
                  (let ((binds (remind-bindings-bindsinpackage packinfo)))
                    (message (car binds))
                    (when (nth 1 binds)
                      (push binds packbinds)))))
            (error
             ;; End of file
             (setq stop t)))
          (end-of-line))
        (map-into packbinds 'hash-table)))))

(defun remind-bindings-combine-lists (map1 map2)
  "Take the package bindings from MAP1 and MAP2 and merge them on package name"
  (map-merge-with 'hash-table 'append map1 map2))

(defun remind-bindings-makequotes (hashtable)
  "Convert a hashtable of bindings into a single formatted list."
  (interactive)
  (let ((total))
    (maphash
     (lambda (packname bindings)
       (let ((fmt (format
                   remind-bindings--format-packbincom
                   packname
                   (mapconcat 'identity bindings
                              remind-bindings--format-bindingsep))))
         (push fmt total)))
     hashtable)
    total))

(defun remind-bindings-initialise ()
  (unless remind-bindings--quoteslist
    (let ((globals (remind-bindings-getglobal))
          (usepack (remind-bindings-getusepackages)))
      (let* ((comb (remind-bindings-combine-lists globals usepack)))
        (setq remind-bindings--quoteslist
              (remind-bindings-makequotes comb)))))
  (omni-quotes-set-populate remind-bindings--quoteslist "bindings"))

(provide 'remind-bindings)
;;; remind-bindings.el ends here
