;;; init-git.el --- Git Integration -*- lexical-binding: t; -*-

;;; Commentary:
;; Magit によるGit操作（シンプル構成）

;;; Code:

;; ============================================================
;; Magit
;; ============================================================
(use-package magit
  :bind* (("C-x g"   . magit-status)
          ("C-x m"   . magit-status)
          ("C-x M-g" . magit-dispatch)
          ("C-c M-g" . magit-file-dispatch))
  :custom
  (magit-display-buffer-function
   #'magit-display-buffer-same-window-except-diff-v1)
  (magit-diff-refine-hunk 'all)
  (magit-save-repository-buffers 'dontask))

;; ============================================================
;; diff-hl: Git差分を行単位で可視化
;; ============================================================
(use-package diff-hl
  :hook ((after-init . global-diff-hl-mode)
         (dired-mode . diff-hl-dired-mode)
         (magit-pre-refresh . diff-hl-magit-pre-refresh)
         (magit-post-refresh . diff-hl-magit-post-refresh))
  :config
  ;; ターミナルEmacs用（GUI不要の場合はマージンに表示）
  (unless (display-graphic-p)
    (diff-hl-margin-mode)))

;; ============================================================
;; difftastic: 構文単位の構造的diff (AI生成コードのレビュー向け)
;; ============================================================
;; difft CLI (Brewfile: difftastic) の出力を Emacs バッファ内に描画するため
;; TTY (emacs -nw) で完全動作する。バインドは difftastic-bindings-mode が
;; after-load-functions 経由で magit-diff / magit-blame / magit-file-dispatch /
;; dired に遅延注入する (M-d: diff, M-c: show 等)。
;; 本体 difftastic.el はコマンド呼び出しまで autoload されるので、
;; :defer 1 で軽量な difftastic-bindings のみアイドルロードし startup を保つ。
(use-package difftastic-bindings
  :straight difftastic
  :defer 1
  :config
  (difftastic-bindings-mode))

(provide 'init-git)
;;; init-git.el ends here
