;;; init-editing.el --- Editing Enhancements -*- lexical-binding: t; -*-

;;; Commentary:
;; 編集支援パッケージ（シンプル構成）。
;; OSC52 clipboard 共有 (clipetty) もここに含む。

;;; Code:

;; ============================================================
;; バイトコンパイラ向け宣言
;; ============================================================
(declare-function diminish "diminish")

;; ============================================================
;; editorconfig
;; ============================================================
(use-package editorconfig
  :diminish editorconfig-mode
  :config
  (editorconfig-mode 1))

;; ============================================================
;; avy (画面内ジャンプ)
;; ============================================================
(use-package avy
  :bind* (("C-c SPC" . avy-goto-char-timer)
          ("C-c C-SPC" . avy-goto-char-2)
          ("M-g w" . avy-goto-word-1)
          ("M-g l" . avy-goto-line))
  :custom
  (avy-timeout-seconds 0.5)
  (avy-style 'at-full)
  (avy-background t))

;; ============================================================
;; string-inflection (命名規則変換)
;; ============================================================
(use-package string-inflection
  :bind* ("C-c C-u" . string-inflection-all-cycle))

;; ============================================================
;; diminish (モードライン整理)
;; ============================================================
(use-package diminish
  :config
  (with-eval-after-load 'abbrev
    (diminish 'abbrev-mode))
  (with-eval-after-load 'autorevert
    (diminish 'auto-revert-mode))
  (with-eval-after-load 'whitespace
    (diminish 'global-whitespace-mode)))

;; ============================================================
;; clipetty (OSC52 クリップボード共有)
;; ============================================================
;; OSC52 emit でクリップボードを macOS pasteboard と同期する。
;; GUI Emacs では clipetty 内部判定で no-op。TTY/ssh+tmux 環境では
;; OSC52 を terminal stack (tmux → Ghostty) 経由で送出する。
;; after-init hook を使うので読み込み順序自体は緩い。
(use-package clipetty
  :hook (after-init . global-clipetty-mode))

(provide 'init-editing)
;;; init-editing.el ends here
