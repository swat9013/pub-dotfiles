;;; init-macos.el --- macOS Specific Settings -*- lexical-binding: t; -*-

;;; Commentary:
;; macOS 固有の設定

;;; Code:

;; ============================================================
;; バイトコンパイラ向け宣言
;; ============================================================
(defvar mac-command-modifier)
(defvar mac-option-modifier)
(defvar mac-control-modifier)
(defvar ns-function-modifier)
(defvar ns-use-native-fullscreen)

;; PATH は emacs -nw で親 zsh から継承済み。GUI Emacs.app は不採用 (ADR 0005)
;; のため exec-path-from-shell は撤去。

;; ============================================================
;; macOS キーボード設定
;; ============================================================
(setq mac-command-modifier 'meta)
(setq mac-option-modifier 'super)
(setq mac-control-modifier 'control)

;; fn キー設定
(setq ns-function-modifier 'hyper)

;; ============================================================
;; macOS 特有の挙動調整
;; ============================================================
;; スムーズスクロール
(setq scroll-conservatively 101)

;; フルスクリーン設定
(setq ns-use-native-fullscreen t)

;; タイトルバーにファイルパスを表示
(setq frame-title-format
      '((:eval (if (buffer-file-name)
                   (abbreviate-file-name (buffer-file-name))
                 "%b"))))

;; ============================================================
;; Trash 対応
;; ============================================================
(setq delete-by-moving-to-trash t)
(setq trash-directory "~/.Trash")

(provide 'init-macos)
;;; init-macos.el ends here
