;;; init-treesit.el --- Tree-sitter Configuration -*- lexical-binding: t; -*-

;;; Commentary:
;; Tree-sitter (Emacs 29+ 組み込み) による構文解析

;;; Code:

;; ============================================================
;; バイトコンパイラ向け宣言
;; ============================================================
(defvar treesit-language-source-alist)
(declare-function treesit-auto-add-to-auto-mode-alist "treesit-auto")
(declare-function global-treesit-auto-mode "treesit-auto")

;; ============================================================
;; treesit-auto (自動インストール・モード切り替え)
;; ============================================================
;; :defer t + :hook で prog-mode-hook 初回発火時に load + configure する。
;; eager load 時 0.35s 消費していた起動コスト (#47/#49) をユーザ操作直後まで遅延させ、
;; batch (`emacs --batch -l init.el`) では hook 未発火のため一切 load されない。
;;
;; :hook のシンボル `global-treesit-auto-mode' は use-package が autoload を生成する。
;; 初回発火の順序: prog-mode-hook → autoload → treesit-auto.el load → :custom → :config
;; (treesit-auto-add-to-auto-mode-alist) → global-treesit-auto-mode 本体が実行され
;; set-auto-mode-0 advice を install する。初回 buffer 自身は既に base mode に確定して
;; いるため remap されないが、2 件目以降の buffer は従来通り ts-mode へ昇格する。
(use-package treesit-auto
  :defer t
  :hook (prog-mode . global-treesit-auto-mode)
  :custom
  ;; grammar 不在の base mode (例 .json→js-json-mode) を開いた時点で prompt なしに
  ;; 自動取得し、revert で ts-mode へ昇格する。下の add-to-auto-mode-alist を 'all に
  ;; せず ts-mode を直接バインドしないことで初めて install フックに到達でき機能する。
  (treesit-auto-install t)
  :config
  ;; 引数なし = ready な grammar のみ ts-mode を auto-mode-alist へ登録する。
  ;; 'all を渡すと grammar 未インストールでも ts-mode を直接バインドし、ts-mode 本体の
  ;; (unless (treesit-ready-p ...) (error ...)) でハードエラー → install フックに到達
  ;; できず treesit-auto-install が死にコード化する (json grammar warning の根本原因)。
  (treesit-auto-add-to-auto-mode-alist))

;; ============================================================
;; Tree-sitter 文法ソース設定 (手動インストール用)
;; ============================================================
;; NOTE: 一部の grammar (yaml, markdown 等) は C++ ソースで配布されており、
;; treesit-install-language-grammar がローカルビルド時に `c++` を要求する。
;; Linux ホストでは OS パッケージで gcc-c++ / g++ を別途 install すること
;; (docs/ssh-remote-setup-guide.md「前提」参照)。
(setq treesit-language-source-alist
      '((bash       "https://github.com/tree-sitter/tree-sitter-bash")
        (c          "https://github.com/tree-sitter/tree-sitter-c")
        (cpp        "https://github.com/tree-sitter/tree-sitter-cpp")
        (css        "https://github.com/tree-sitter/tree-sitter-css")
        (dockerfile "https://github.com/camdencheek/tree-sitter-dockerfile")
        (elisp      "https://github.com/Wilfred/tree-sitter-elisp")
        (go         "https://github.com/tree-sitter/tree-sitter-go")
        (html       "https://github.com/tree-sitter/tree-sitter-html")
        (javascript "https://github.com/tree-sitter/tree-sitter-javascript"
                    "master" "src")
        (json       "https://github.com/tree-sitter/tree-sitter-json")
        (markdown   "https://github.com/ikatyang/tree-sitter-markdown")
        (python     "https://github.com/tree-sitter/tree-sitter-python")
        (ruby       "https://github.com/tree-sitter/tree-sitter-ruby")
        (rust       "https://github.com/tree-sitter/tree-sitter-rust")
        (toml       "https://github.com/tree-sitter/tree-sitter-toml")
        (tsx        "https://github.com/tree-sitter/tree-sitter-typescript"
                    "master" "tsx/src")
        (typescript "https://github.com/tree-sitter/tree-sitter-typescript"
                    "master" "typescript/src")
        (yaml       "https://github.com/ikatyang/tree-sitter-yaml")))

;; ============================================================
;; 一括インストール関数
;; ============================================================
(defun my/treesit-install-all-grammars ()
  "Install all Tree-sitter grammars."
  (interactive)
  (mapc #'treesit-install-language-grammar
        (mapcar #'car treesit-language-source-alist)))

;; ============================================================
;; major-mode リマッピング
;; ============================================================
;; treesit-auto が set-auto-mode-0 への advice で major-mode-remap-alist を
;; バッファローカルに動的構築する (ready な grammar のみ base→ts へ remap し、
;; 未 ready は remap しない = base mode フォールバックでハードエラーを回避)。
;; 静的な (setq major-mode-remap-alist ...) は未 ready でも無条件に remap して
;; フォールバックを潰し、ts-mode のハードエラーを誘発するため置かない。

(provide 'init-treesit)
;;; init-treesit.el ends here
