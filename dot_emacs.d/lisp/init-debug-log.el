;;; init-debug-log.el --- Persist startup warnings to disk -*- lexical-binding: t; -*-

;;; Commentary:
;; *Messages* / *Warnings* / *Native-compile-Log* / *Compile-Log* を
;; 起動時と終了時に永続ファイルへスナップショットし、
;; Claude Code 等の外部ツールから固定パスで参照可能にする。

;;; Code:

(declare-function no-littering-expand-var-file-name "no-littering")

(defvar my/debug-log-buffers
  '("*Messages*" "*Warnings*" "*Native-compile-Log*" "*Compile-Log*")
  "Buffers to snapshot into startup log.")

(defvar my/debug-log-retention-days 30
  "Delete startup logs whose mtime is older than this many days.")

(defvar my/debug-log-dir nil
  "Directory containing startup log files. Resolved on startup.")

(defvar my/debug-log-current-file nil
  "Path to this session's startup log file.")

(defun my/debug-log--ensure-dir ()
  "Resolve `my/debug-log-dir' under no-littering var/ and create it."
  (let ((dir (no-littering-expand-var-file-name "log/")))
    (make-directory dir t)
    (setq my/debug-log-dir dir)))

(defun my/debug-log--cleanup-old ()
  "Delete startup-*.log files older than `my/debug-log-retention-days'."
  (condition-case err
      (let* ((cutoff (time-subtract (current-time)
                                    (days-to-time my/debug-log-retention-days)))
             (files (directory-files my/debug-log-dir t "^startup-.*\\.log\\'")))
        (dolist (f files)
          (when (time-less-p (file-attribute-modification-time
                              (file-attributes f))
                             cutoff)
            (ignore-errors (delete-file f)))))
    (error (message "debug-log cleanup failed: %s" err))))

(defun my/debug-log--format-buffer (name)
  "Return formatted snapshot section for buffer NAME."
  (let ((buf (get-buffer name)))
    (concat
     (format "\n--- %s ---\n" name)
     (if (and buf (> (buffer-size buf) 0))
         (with-current-buffer buf
           (buffer-substring-no-properties (point-min) (point-max)))
       "no content\n"))))

(defun my/debug-log--write (path)
  "Snapshot configured buffers into PATH."
  (condition-case err
      (with-temp-file path
        (insert "========================================\n")
        (insert (format "Emacs startup log  %s\n"
                        (format-time-string "%Y-%m-%d %H:%M:%S")))
        (insert (format "emacs-version: %s   system: %s\n"
                        emacs-version (symbol-name system-type)))
        (insert "========================================\n")
        (dolist (name my/debug-log-buffers)
          (insert (my/debug-log--format-buffer name))))
    (error (message "debug-log write failed: %s" err))))

(defun my/debug-log--update-latest-symlink ()
  "Refresh latest.log symlink to point at the current session file."
  (condition-case err
      (let ((link (expand-file-name "latest.log" my/debug-log-dir)))
        (when (or (file-exists-p link) (file-symlink-p link))
          (delete-file link))
        (make-symbolic-link my/debug-log-current-file link t))
    (error (message "debug-log symlink failed: %s" err))))

(defun my/debug-log-snapshot-on-startup ()
  "Write startup log, refresh latest.log symlink, cleanup old logs."
  (my/debug-log--ensure-dir)
  (my/debug-log--cleanup-old)
  (setq my/debug-log-current-file
        (expand-file-name
         (format "startup-%s.log" (format-time-string "%Y%m%d-%H%M%S"))
         my/debug-log-dir))
  (my/debug-log--write my/debug-log-current-file)
  (my/debug-log--update-latest-symlink))

(defun my/debug-log-snapshot-on-kill ()
  "Overwrite current session log with the final buffer state."
  (when my/debug-log-current-file
    (my/debug-log--write my/debug-log-current-file)))

;; APPEND=100 にして emacs-startup-hook の最終位置で発火させる。
;; 他モジュールが追加した warning も拾えるようにするため。
(add-hook 'emacs-startup-hook #'my/debug-log-snapshot-on-startup 100)
(add-hook 'kill-emacs-hook #'my/debug-log-snapshot-on-kill)

(provide 'init-debug-log)
;;; init-debug-log.el ends here
