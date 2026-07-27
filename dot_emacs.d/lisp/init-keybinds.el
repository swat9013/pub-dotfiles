;;; init-keybinds.el --- Key Bindings -*- lexical-binding: t; -*-

;;; Commentary:
;; グローバルキーバインド設定
;; 個人キーバインドは bind-key* (override-global-map) に置く。
;; override-global-map は emulation-mode-map-alists 経由で major-mode の
;; ローカルマップより上に位置するため、major-mode が同キー (例: markdown-mode
;; の C-c C-f) を奪わない。global-set-key だと major-mode マップに負ける。

;;; Code:

;; bind-key* / override-global-map を使う (use-package 同梱の bind-key)。
;; init.el の use-package セットアップ後にロードされるが byte-compile 順序の保険。
(require 'bind-key)

;; ============================================================
;; 基本キーバインド
;; ============================================================
;; C-h を Backspace に (Emacs 標準では help)
(bind-key* "C-h" 'backward-delete-char)

;; 行ジャンプ
(bind-key* "C-x C-g" 'goto-line)

;; ファイル再読込
(bind-key* "C-c C-r" 'revert-buffer-no-confirm)

;; 全体インデント
(bind-key* "C-x C-i" 'electric-indent)

;; ============================================================
;; ウィンドウ操作
;; ============================================================
(bind-key* "C-c <left>"  'windmove-left)
(bind-key* "C-c <down>"  'windmove-down)
(bind-key* "C-c <up>"    'windmove-up)
(bind-key* "C-c <right>" 'windmove-right)

;; ============================================================
;; 行移動
;; ============================================================
(bind-key* "M-[ b" 'move-line-down)
(bind-key* "M-[ a" 'move-line-up)

;; ============================================================
;; スクロール
;; ============================================================
(bind-key* "M-p" 'scroll-down-command)
(bind-key* "M-n" 'scroll-up-command)

;; ============================================================
;; バッファ切り替え
;; ============================================================
(bind-key* "M-}" 'next-buffer)
(bind-key* "M-{" 'previous-buffer)

;; マウスサイドボタン (戻る/進む) でバッファ切替。
;; xterm-mouse-mode が SGR mouse protocol 経由で button 8/9 を受信する前提。
(bind-key* "<mouse-8>" 'previous-buffer)
(bind-key* "<mouse-9>" 'next-buffer)

(provide 'init-keybinds)
;;; init-keybinds.el ends here
