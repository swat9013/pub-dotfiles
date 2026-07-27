;;; early-init.el --- Early Init -*- lexical-binding: t; -*-

;;; Commentary:
;; Emacs 27+ で init.el より前に読み込まれる設定
;; GC最適化、UI早期無効化、パッケージシステム制御

;;; Code:

;; ============================================================
;; GC最適化 - 起動時は閾値を最大に
;; ============================================================
(setq gc-cons-threshold most-positive-fixnum
      gc-cons-percentage 0.6)

;; ============================================================
;; package.el の自動初期化を無効化 (straight.el 使用のため)
;; ============================================================
(setq package-enable-at-startup nil)

;; ============================================================
;; UI要素の早期無効化 (フラッシュ防止)
;; ============================================================
(push '(menu-bar-lines . 0) default-frame-alist)
(push '(tool-bar-lines . 0) default-frame-alist)
(push '(vertical-scroll-bars) default-frame-alist)

;; フレームサイズの自動調整を無効化
(setq frame-inhibit-implied-resize t)

;; ============================================================
;; Native Compilation 設定 (Emacs 29+)
;; ============================================================
(when (featurep 'native-compile)
  ;; 警告を抑制
  (setq native-comp-async-report-warnings-errors 'silent)

  ;; ネイティブコンパイルキャッシュの場所
  (when (fboundp 'startup-redirect-eln-cache)
    (startup-redirect-eln-cache
     (convert-standard-filename
      (expand-file-name "var/eln-cache/" user-emacs-directory)))))

;; ============================================================
;; その他の早期設定
;; ============================================================
;; file-name-handler-alist を一時的に無効化（起動高速化）
(defvar my/file-name-handler-alist file-name-handler-alist)
(setq file-name-handler-alist nil)

;; 起動完了後に復元
(add-hook 'emacs-startup-hook
          (lambda ()
            (setq file-name-handler-alist my/file-name-handler-alist)))

;;; early-init.el ends here
