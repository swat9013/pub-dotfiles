;;; init-completion.el --- Completion System -*- lexical-binding: t; -*-

;;; Commentary:
;; 補完システムを 1 module に集約（シンプル構成）。
;; minibuffer 系 (Vertico/Orderless/Marginalia/Consult) と
;; in-buffer 系 (Corfu/Cape) をセクションで区分する。

;;; Code:

;; ============================================================
;; バイトコンパイラ向け宣言
;; ============================================================
(defvar consult-buffer)
(defvar consult-recent-file)
(defvar xref-show-xrefs-function)
(defvar xref-show-definitions-function)
(defvar corfu-map)
(defvar cape-dabbrev-min-length)
(declare-function vertico-mode "vertico")
(declare-function marginalia-mode "marginalia")
(declare-function consult-customize "consult")
(declare-function consult-xref "consult-xref")
(declare-function global-corfu-mode "corfu")
(declare-function cape-dabbrev "cape")
(declare-function cape-file "cape")
(declare-function cape-keyword "cape")

;; ============================================================
;; minibuffer 系 (Vertico / Orderless / Marginalia / Consult)
;; ============================================================

;; ------------------------------------------------------------
;; Vertico (ミニバッファ補完UI)
;; ------------------------------------------------------------
(use-package vertico
  :custom
  (vertico-count 15)
  (vertico-cycle t)
  (vertico-resize nil)
  :init
  (vertico-mode 1)
  :config
  ;; vertico-directory 拡張
  (use-package vertico-directory
    :straight nil
    :after vertico
    :bind (:map vertico-map
           ("RET" . vertico-directory-enter)
           ("DEL" . vertico-directory-delete-char)
           ("M-DEL" . vertico-directory-delete-word))
    :hook (rfn-eshadow-update-overlay . vertico-directory-tidy)))

;; ------------------------------------------------------------
;; Orderless (柔軟なマッチング)
;; ------------------------------------------------------------
(use-package orderless
  :custom
  (completion-styles '(orderless basic))
  (completion-category-defaults nil)
  (completion-category-overrides '((file (styles partial-completion))))
  ;; Emacs 31対応
  (completion-pcm-leading-wildcard t))

;; ------------------------------------------------------------
;; Marginalia (注釈表示)
;; ------------------------------------------------------------
(use-package marginalia
  :init
  (marginalia-mode 1))

;; ------------------------------------------------------------
;; Consult (検索・ナビゲーション強化)
;; ------------------------------------------------------------
(use-package consult
  :bind* (("C-s"     . consult-line)           ; isearch 置換 (major-mode より優先)
         ("C-x b"   . consult-buffer)
         ("C-x r b" . consult-bookmark)
         ("C-x C-t" . consult-recent-file)
         ("M-y"     . consult-yank-pop)
         ("M-g g"   . consult-goto-line)
         ("M-g M-g" . consult-goto-line)
         ("M-s r"   . consult-ripgrep)
         ("M-s f"   . consult-find)
         ("C-c C-g" . consult-ripgrep))
  :custom
  (consult-narrow-key "<")
  :config
  ;; プレビュー設定
  (consult-customize
   consult-buffer consult-recent-file
   :preview-key "M-.")

  ;; xref 統合
  (setq xref-show-xrefs-function #'consult-xref
        xref-show-definitions-function #'consult-xref))

;; ============================================================
;; in-buffer 系 (Corfu / Cape)
;; ============================================================

;; ------------------------------------------------------------
;; Corfu (ポップアップ補完)
;; ------------------------------------------------------------
(use-package corfu
  :custom
  (corfu-auto t)              ; 自動補完
  (corfu-auto-delay 0.2)      ; 遅延 (秒)
  (corfu-auto-prefix 2)       ; 最小文字数
  (corfu-cycle t)             ; 循環
  (corfu-preselect 'prompt)   ; 最初の候補を選択しない
  (corfu-scroll-margin 5)
  :bind (:map corfu-map
         ("C-n" . corfu-next)
         ("C-p" . corfu-previous)
         ("C-f" . corfu-insert)
         ("TAB" . corfu-insert)
         ([tab] . corfu-insert)
         ("C-h" . nil))       ; C-h を Backspace として使用可能に
  :init
  (global-corfu-mode 1)
  :config
  ;; ターミナルサポート
  (unless (display-graphic-p)
    (use-package corfu-terminal
      :straight (:host github :repo "wyuenho/emacs-corfu-terminal")
      :config
      (corfu-terminal-mode 1))))

;; ------------------------------------------------------------
;; Cape (補完バックエンド拡張)
;; ------------------------------------------------------------
(use-package cape
  :init
  ;; completion-at-point-functions に追加
  (add-hook 'completion-at-point-functions #'cape-dabbrev)
  (add-hook 'completion-at-point-functions #'cape-file)
  (add-hook 'completion-at-point-functions #'cape-keyword)
  :config
  ;; dabbrev 設定
  (setq cape-dabbrev-min-length 3))

(provide 'init-completion)
;;; init-completion.el ends here
