;;; init-ui.el --- UI Configuration -*- lexical-binding: t; -*-

;;; Commentary:
;; テーマ、フォント設定（シンプル構成）

;;; Code:

;; ============================================================
;; バイトコンパイラ向け宣言
;; ============================================================
(declare-function mac-application-state "macfns" nil t)
(declare-function set-fontset-font "fontset")

;; ============================================================
;; Tokyo Night テーマ (ghostty と統一)
;; ============================================================
;; theme 適用を after-init-hook に逃がして起動 critical path から外す。
;; enable-bold/italic は package load 前に評価されるため :init で先出しする
;; (defvar は既存 binding を上書きしない)。
(use-package doom-themes
  :defer t
  :init
  (setq doom-themes-enable-bold t
        doom-themes-enable-italic t)
  (add-hook 'after-init-hook
            (lambda ()
              (load-theme 'doom-tokyo-night t)
              (doom-themes-org-config))))

;; ============================================================
;; フォント設定 (GUI Emacs 用)
;; ============================================================
(when (display-graphic-p)
  ;; 英字フォント
  (set-face-attribute 'default nil
                      :family "JetBrains Mono"
                      :height 140)

  ;; 日本語フォント
  (set-fontset-font t 'japanese-jisx0208
                    (font-spec :family "Noto Sans CJK JP"))

  ;; 絵文字
  (set-fontset-font t 'emoji
                    (font-spec :family "Noto Color Emoji")))

(provide 'init-ui)
;;; init-ui.el ends here
