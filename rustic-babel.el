;;; rustic-babel.el --- Org babel facilities for rustic -*-lexical-binding: t-*-

;; This file is distributed under the terms of both the MIT license and the
;; Apache License (version 2.0).

;;; Code:

(require 'org)
(require 'ob)
(require 'ob-eval)
(require 'ob-ref)
(require 'ob-core)

(add-to-list 'org-babel-tangle-lang-exts '("rust" . "rs"))

(defcustom rustic-babel-display-compilation-buffer nil
  "Whether to display compilation buffer."
  :type 'boolean
  :group 'rustic-mode)

(defvar rustic-babel-buffer-name '((:default . "*rust-babel*")))

(defvar rustic-babel-process-name "rustic-babel-process"
  "Process name for org-babel rust compilation processes.")

(defvar rustic-babel-compilation-buffer "*rustic-babel-compilation-buffer*"
  "Buffer name for org-babel rust compilation process buffers.")

(defvar rustic-babel-dir nil
  "Holds the latest rust babel project directory.")

(defvar rustic-babel-src-location nil
  "Marker, holding location of last evaluated src block.")

(defvar rustic-babel-params nil
  "Babel parameters.")

(defun rustic-babel-eval (dir)
  "Start a rust babel compilation process."
  (let* ((err-buff (get-buffer-create rustic-babel-compilation-buffer))
         (default-directory dir)
         (coding-system-for-read 'binary)
         (process-environment (nconc
	                           (list (format "TERM=%s" "ansi"))
                               process-environment))
         (params '("cargo" "build"))
         (inhibit-read-only t))
    (with-current-buffer err-buff
      (erase-buffer)
      (setq-local default-directory dir)
      (rustic-compilation-mode))
    (if rustic-babel-display-compilation-buffer
     (display-buffer err-buff))
    (let ((proc (make-process
                 :name rustic-babel-process-name
                 :buffer err-buff
                 :command params
                 :filter #'rustic-compile-filter
                 :sentinel #'rustic-babel-sentinel))))))

(defun rustic-babel-sentinel (proc string)
  "Sentinel for rust babel compilation processes."
  (let ((proc-buffer (process-buffer proc))
        (inhibit-read-only t))
    (if (zerop (process-exit-status proc))
        (let* ((default-directory rustic-babel-dir) 
               (result (shell-command-to-string "cargo run --quiet"))
               (result-params (list (cdr (assq :results rustic-babel-params))))
               (params rustic-babel-params)
               (marker rustic-babel-src-location))
          (with-current-buffer (marker-buffer marker)
            (goto-char marker)
            (org-babel-remove-result rustic-info)
            (org-babel-insert-result result result-params rustic-info))
          (unless rustic-babel-display-compilation-buffer
           (kill-buffer proc-buffer)))
      (pop-to-buffer proc-buffer))))

(defun rustic-babel-generate-project ()
  "Create rust project in `org-babel-temporary-directory'."
  (let* ((default-directory org-babel-temporary-directory)
         (dir (make-temp-file-internal "cargo" 0 "" nil)))
    (shell-command-to-string (format "cargo new %s --bin --quiet" dir))
    (setq rustic-babel-dir (expand-file-name dir))))

(defun rustic-babel-cargo-toml (dir params)
  "Append crates to Cargo.toml."
  (let ((crates (cdr (assq :crates params)))
        (toml (expand-file-name "Cargo.toml" dir))
        (str ""))
    (dolist (crate crates)
      (setq str (concat str (car crate) " = " "\"" (cdr crate) "\"" "\n")))
    (write-region str nil toml t)))

(defun org-babel-execute:rust (body params)
  "Execute a block of Rust code with Babel."
  (let* ((full-body (org-element-property :value (org-element-at-point)))
         (dir (rustic-babel-generate-project))
         (project (car (reverse (split-string rustic-babel-dir "\\/"))))
         (main (expand-file-name "main.rs" (concat dir "/src"))))
    (setq rustic-info (org-babel-get-src-block-info))
    (rustic-babel-cargo-toml dir params)
    (setq rustic-babel-params params)
    (let ((default-directory dir))
      (write-region full-body nil main nil 0)
      (rustic-babel-eval dir)
      (setq rustic-babel-src-location (set-marker (make-marker) (point) (current-buffer)))
      project)))

(provide 'rustic-babel)
;;; rustic-babel.el ends here
