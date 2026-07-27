;;; init-lsp.el --- LSP Configuration -*- lexical-binding: t; -*-

;;; Commentary:
;; Eglot (組み込み) によるLSP設定

;;; Code:

;; ============================================================
;; バイトコンパイラ向け宣言
;; ============================================================
(defvar eglot-mode-map)
(declare-function eglot-format-buffer "eglot")

;; ============================================================
;; Eglot (Emacs 29+ 組み込み)
;; ============================================================
(use-package eglot
  :straight nil
  :hook ((ruby-mode        . eglot-ensure)
         (ruby-ts-mode     . eglot-ensure)
         (typescript-mode  . eglot-ensure)
         (typescript-ts-mode . eglot-ensure)
         (tsx-ts-mode      . eglot-ensure)
         (js-mode          . eglot-ensure)
         (js-ts-mode       . eglot-ensure)
         (html-mode        . eglot-ensure)
         (css-mode         . eglot-ensure)
         (css-ts-mode      . eglot-ensure))
  :custom
  (eglot-autoshutdown t)              ; 不要になったらサーバー終了
  (eglot-events-buffer-size 0)        ; パフォーマンス向上
  (eglot-sync-connect nil)            ; 非同期接続
  (eglot-confirm-server-initiated-edits nil)
  :config
  ;; 言語サーバー設定
  (add-to-list 'eglot-server-programs
               '((ruby-mode ruby-ts-mode) . ("solargraph" "socket" "--port" :autoport)))
  (add-to-list 'eglot-server-programs
               '((typescript-mode typescript-ts-mode tsx-ts-mode)
                 . ("typescript-language-server" "--stdio")))
  (add-to-list 'eglot-server-programs
               '((js-mode js-ts-mode) . ("typescript-language-server" "--stdio"))))

;; ============================================================
;; Eglot + Consult 統合
;; ============================================================
(use-package consult-eglot
  :after (consult eglot)
  :bind (:map eglot-mode-map
         ("M-g s" . consult-eglot-symbols)))

;; ============================================================
;; 自動フォーマット (保存時)
;; ============================================================
;; Tide の tide-format-before-save 相当
;; 必要に応じてモードごとに有効化
(defun my/eglot-format-on-save ()
  "Format buffer with eglot before save."
  (when (bound-and-true-p eglot--managed-mode)
    (eglot-format-buffer)))

;; フォーマットを有効にしたいモードで追加
;; (add-hook 'typescript-ts-mode-hook
;;           (lambda ()
;;             (add-hook 'before-save-hook #'my/eglot-format-on-save nil t)))

(provide 'init-lsp)
;;; init-lsp.el ends here
