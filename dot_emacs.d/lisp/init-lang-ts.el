;;; init-lang-ts.el --- TypeScript Development -*- lexical-binding: t; -*-

;;; Commentary:
;; TypeScript/JavaScript/JSON 開発設定 (インデント等)。
;;
;; ファイル→モード対応と grammar 自動取得は treesit-auto が一元管理する
;; (init-treesit.el)。ここで ts-mode を直接 auto-mode-alist にバインド (:mode) すると、
;; grammar 未インストール時に ts-mode 本体の
;;   (unless (treesit-ready-p ...) (error ...))
;; がハードエラーになり、treesit-auto の install フックに到達できない。そのため
;; :mode は使わず :defer t とし、インデント等の設定のみを担う。
;; grammar 不在時のフォールバック (treesit-auto が ready 時に *-ts-mode へ昇格させる):
;;   .json       → js-json-mode    (Emacs 組み込み既定)
;;   .js / .jsx  → javascript-mode (Emacs 組み込み既定; treesit-auto の js :remap 対象)
;;   .ts / .tsx  → grammar ready 時のみ treesit-auto が *-ts-mode を登録 (既定の base mode 無し)

;;; Code:

;; バイトコンパイラ向け宣言 (実体は各 ts-mode 読込時に定義される)
(defvar typescript-ts-mode-indent-offset)
(defvar js-indent-level)
(defvar json-ts-mode-indent-offset)

(defun my/ts-js-indent-setup ()
  "TS/JS バッファのタブ幅とインデント方式を設定する。"
  (setq-local tab-width 2)
  (setq-local indent-tabs-mode nil))

;; ============================================================
;; TypeScript / TSX (Tree-sitter)
;; ============================================================
(use-package typescript-ts-mode
  :straight nil
  :defer t
  :init
  (setq typescript-ts-mode-indent-offset 2)
  :hook
  (typescript-ts-mode . my/ts-js-indent-setup))

;; ============================================================
;; JavaScript (Tree-sitter)
;; ============================================================
;; package 名は `js' (js-ts-mode の実体は js.el にある)。`js-ts-mode' を
;; package 名にすると同名 library が無く、compile 時に use-package が生成する
;; load が "Cannot load js-ts-mode" を出す。
(use-package js
  :straight nil
  :defer t
  :init
  (setq js-indent-level 2)
  :hook
  (js-ts-mode . my/ts-js-indent-setup))

;; ============================================================
;; JSON (Tree-sitter)
;; ============================================================
(use-package json-ts-mode
  :straight nil
  :defer t
  :init
  (setq json-ts-mode-indent-offset 2))

(provide 'init-lang-ts)
;;; init-lang-ts.el ends here
