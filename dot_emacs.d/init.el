;;; init.el --- Main Init -*- lexical-binding: t; -*-

;;; Commentary:
;; Emacs設定のエントリポイント
;; straight.el + use-package によるモダンなパッケージ管理

;;; Code:

;; ============================================================
;; バイトコンパイラ向け宣言
;; ============================================================
(defvar straight-use-package-by-default)
(defvar use-package-always-ensure)
(defvar use-package-verbose)
(defvar use-package-minimum-reported-time)
(declare-function straight-use-package "straight")
(declare-function no-littering-expand-var-file-name "no-littering")
(declare-function no-littering-expand-etc-file-name "no-littering")

;; ============================================================
;; 起動時間計測
;; ============================================================
(defun my/display-startup-time ()
  "Display startup time and GC count."
  (message "Emacs loaded in %s with %d garbage collections."
           (format "%.2f seconds"
                   (float-time (time-subtract after-init-time before-init-time)))
           gcs-done))
(add-hook 'emacs-startup-hook #'my/display-startup-time)

;; ============================================================
;; straight.el ブートストラップ
;; ============================================================
(defvar bootstrap-version)
(let ((bootstrap-file
       (expand-file-name "straight/repos/straight.el/bootstrap.el"
                         user-emacs-directory))
      (bootstrap-version 7))
  (unless (file-exists-p bootstrap-file)
    (with-current-buffer
        (url-retrieve-synchronously
         "https://raw.githubusercontent.com/radian-software/straight.el/develop/install.el"
         'silent 'inhibit-cookies)
      (goto-char (point-max))
      (eval-print-last-sexp)))
  (load bootstrap-file nil 'nomessage))

;; ============================================================
;; use-package 統合
;; ============================================================
(straight-use-package 'use-package)
(setq straight-use-package-by-default t)
(setq use-package-always-ensure nil)  ; straight.el が管理

;; use-package のログ設定
;; EMACS_STARTUP_PROFILE=1 のときだけ verbose を有効化する。通常起動では
;; `*Messages*` を "Loading package ..." / "Configuring package ..." で汚さない。
;; benchmark CLI (scripts/emacs-startup-benchmark.sh) は自動でこの env を立てる。
(when (equal (getenv "EMACS_STARTUP_PROFILE") "1")
  (setq use-package-verbose t)
  (setq use-package-minimum-reported-time 0.001))

;; ============================================================
;; no-littering (ファイル整理) - 最初に読み込む
;; ============================================================
(use-package no-littering
  :config
  ;; auto-save ファイルの場所
  (setq auto-save-file-name-transforms
        `((".*" ,(no-littering-expand-var-file-name "auto-save/") t)))

  ;; custom-file の場所
  (setq custom-file (no-littering-expand-etc-file-name "custom.el"))
  (when (file-exists-p custom-file)
    (load custom-file 'noerror 'nomessage)))

;; ============================================================
;; lisp/ モジュール読み込み
;; ============================================================
(defun my/load-module (name)
  "Load a module from lisp/ directory."
  (load (expand-file-name name
                          (expand-file-name "lisp" user-emacs-directory))
        nil 'nomessage))

;; モジュール読み込み順序
;; init-debug-log は最初に読み込み、後続モジュールの warning も取り逃さない
(my/load-module "init-debug-log")
(my/load-module "init-core")
(my/load-module "init-keybinds")
(my/load-module "init-completion")
(my/load-module "init-project")
(my/load-module "init-treemacs")
(my/load-module "init-git")
(my/load-module "init-lsp")
(my/load-module "init-treesit")
(my/load-module "init-lang-ruby")
(my/load-module "init-lang-ts")
(my/load-module "init-lang-web")
(my/load-module "init-editing")
(my/load-module "init-ui")
(my/load-module "init-modeline")

;; macOS 固有設定
(when (eq system-type 'darwin)
  (my/load-module "init-macos"))

;; ============================================================
;; 起動後の処理
;; ============================================================
(add-hook 'emacs-startup-hook
          (lambda ()
            ;; GC閾値を適正値に戻す (16MB)
            (setq gc-cons-threshold (* 16 1024 1024)
                  gc-cons-percentage 0.1)))

;;; init.el ends here
