;;; init-lang-web.el --- Web Development -*- lexical-binding: t; -*-

;;; Commentary:
;; HTML/CSS/Web 開発設定

;;; Code:

;; ============================================================
;; web-mode (ERB, PHP, テンプレート)
;; ============================================================
(use-package web-mode
  :mode (("\\.phtml\\'"     . web-mode)
         ("\\.tpl\\.php\\'" . web-mode)
         ("\\.jsp\\'"       . web-mode)
         ("\\.as[cp]x\\'"   . web-mode)
         ("\\.erb\\'"       . web-mode)
         ("\\.html?\\'"     . web-mode)
         ("\\.ejs\\'"       . web-mode)
         ("\\.vue\\'"       . web-mode))
  :custom
  (web-mode-markup-indent-offset 2)
  (web-mode-css-indent-offset 2)
  (web-mode-code-indent-offset 2)
  (web-mode-style-padding 0)
  (web-mode-script-padding 0)
  (web-mode-enable-auto-pairing t)
  (web-mode-enable-auto-closing t)
  :config
  (add-hook 'web-mode-hook
            (lambda ()
              (setq-local tab-width 2)
              (setq-local indent-tabs-mode nil))))

;; ============================================================
;; CSS / SCSS
;; ============================================================
;; package 名は `css-mode' (css-ts-mode / scss-mode の実体は css-mode.el にある)。
;; `.css' → css-mode、`.scss' → scss-mode は built-in の auto-mode-alist に
;; 登録済みなので :mode は張らない。ts-mode への昇格は treesit-auto が
;; grammar ready 時のみ行う (init-treesit.el の方針。:mode で css-ts-mode を
;; 直接バインドすると grammar 未 ready 時にハードエラーになる)。
;;
;; 外部 scss-mode package (MELPA) は使わない。top-level で legacy flymake の
;; `flymake-allowed-file-name-masks' に push しており、当該変数が削除された
;; 現行 Emacs では load 時に void-variable で落ちる (upstream は 2018 年で停止)。
(use-package css-mode
  :straight nil
  :defer t
  :custom
  (css-indent-offset 2))

;; ============================================================
;; Markdown
;; ============================================================
(use-package markdown-mode
  :mode (("\\.md\\'" . markdown-mode)
         ("\\.markdown\\'" . markdown-mode)
         ("\\.mdc\\'" . markdown-mode))
  :custom
  (markdown-enable-wiki-links nil)
  ;; buffer-side rich display
  (markdown-fontify-code-blocks-natively t)  ; fence を各言語 mode で syntax color
  (markdown-hide-markup t)                   ; **bold** の ** を隠す WYSIWYG 風
  ;; NOTE: markdown-header-scaling は :height 属性を使うため TTY (emacs -nw) では
  ;; 完全な no-op。GUI Emacs 用機能。TTY では下記 :custom-face の underline 等で差別化する
  ;; char-displayable-p遅延回避
  (markdown-url-compose-char ?∞)
  (markdown-blockquote-display-char "▌")
  (markdown-hr-display-char ?─)
  (markdown-definition-display-char ?⁘)
  ;; Enterでリスト項目を継続
  (markdown-indent-on-enter 'indent-and-new-item)
  ;; プレビュー用 processor (M-x markdown-preview / markdown-live-preview-mode)
  (markdown-command "cmark-gfm -e table -e strikethrough -e tasklist -e autolink")
  ;; Chrome preview の見た目 (github-markdown-css v5 の dark-only 変種で全体黒に固定)
  (markdown-css-paths '("https://cdn.jsdelivr.net/npm/github-markdown-css@5/github-markdown-dark.min.css"))
  (markdown-xhtml-header-content
   (concat
    "<style>"
    "html,body{background:#0d1117;color-scheme:dark;}"
    "body{margin:0;}"
    ".markdown-body{box-sizing:border-box;max-width:980px;margin:0 auto;padding:45px;}"
    "@media(max-width:767px){.markdown-body{padding:15px;}}"
    "</style>"))
  (markdown-xhtml-body-preamble "<article class=\"markdown-body\">")
  (markdown-xhtml-body-epilogue "</article>")
  :custom-face
  ;; TTY 差別化: header は theme の outline-N 色 + bold、h1/h2 だけ underline で階層強調
  (markdown-header-face-1 ((t (:inherit outline-1 :weight bold :underline t))))
  (markdown-header-face-2 ((t (:inherit outline-2 :weight bold :underline t))))
  (markdown-header-face-3 ((t (:inherit outline-3 :weight bold))))
  (markdown-header-face-4 ((t (:inherit outline-4 :weight bold))))
  (markdown-header-face-5 ((t (:inherit outline-5 :weight bold))))
  (markdown-header-face-6 ((t (:inherit outline-6 :weight bold))))
  ;; bold/italic は weight/slant のみで色は theme fg (header と混同されない)
  (markdown-bold-face ((t (:inherit bold :foreground unspecified))))
  (markdown-italic-face ((t (:inherit italic :foreground unspecified))))
  ;; link は underline 明示 (URL/リンクテキストの識別性を上げる)
  (markdown-link-face ((t (:inherit link :underline t))))
  (markdown-url-face ((t (:inherit link :underline t :slant italic))))
  ;; inline code は constant color で目立たせる
  (markdown-inline-code-face ((t (:inherit font-lock-constant-face))))
  :config
  (add-hook 'markdown-mode-hook
            (lambda ()
              ;; ターミナル環境でfont-lock/jit-lock最適化
              (when (not (display-graphic-p))
                (setq-local font-lock-maximum-decoration 2)
                (setq-local jit-lock-defer-time 0.1)
                (setq-local jit-lock-stealth-time 1.0)
                (setq-local jit-lock-chunk-size 500))
              ;; markdown では行末空白を削除しない (改行のため)
              (setq-local delete-trailing-whitespace-before-save nil)
              ;; TABでインデント、S-TABでアンインデント
              (local-set-key (kbd "TAB") 'tab-to-tab-stop)
              (local-set-key (kbd "<backtab>") 'indent-rigidly-left-to-tab-stop)
              ;; Enterでリスト継続（electric-indentは無効化）
              (electric-indent-local-mode -1)
              ;; GFMチェックボックス挿入 (markdown-mode 固有なので local 設定)
              ;; グローバルキーバインド (C-c C-f / C-c C-r / M-{ / M-} / M-p / M-n)
              ;; は init-keybinds.el 等で bind-key* (override-global-map) に置かれ
              ;; major-mode より優先されるため、ここでの再設定は不要。
              (local-set-key (kbd "C-c C-t") 'markdown-insert-gfm-checkbox))))

;; ============================================================
;; YAML (Tree-sitter)
;; ============================================================
(use-package yaml-ts-mode
  :straight nil
  :mode (("\\.yml\\'" . yaml-ts-mode)
         ("\\.yaml\\'" . yaml-ts-mode)
         ("\\.dig\\'" . yaml-ts-mode)
         ("\\.yml\\.liquid\\'" . yaml-ts-mode)))

;; ============================================================
;; その他の設定ファイル
;; ============================================================
(use-package dockerfile-ts-mode
  :straight nil
  :mode "Dockerfile\\'")

;; gitconfig-mode (git-modes パッケージに含まれる)
(use-package git-modes
  :mode (("\\.gitconfig\\'" . gitconfig-mode)
         ("\\.git/config\\'" . gitconfig-mode)
         ("\\.gitignore\\'" . gitignore-mode)
         ("\\.gitattributes\\'" . gitattributes-mode)))

(use-package nginx-mode
  :mode "nginx\\(.*\\)\\.conf[^/]*\\'")

(use-package ssh-config-mode
  :mode (("\\.ssh/config\\'" . ssh-config-mode)
         ("sshd?_config\\'" . ssh-config-mode)
         ("known_hosts\\'" . ssh-known-hosts-mode)
         ("authorized_keys2?\\'" . ssh-authorized-keys-mode))
  :hook (ssh-config-mode . turn-on-font-lock))

(provide 'init-lang-web)
;;; init-lang-web.el ends here
