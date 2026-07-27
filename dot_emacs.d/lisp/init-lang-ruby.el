;;; init-lang-ruby.el --- Ruby Development -*- lexical-binding: t; -*-

;;; Commentary:
;; Ruby/Rails 開発設定

;;; Code:

;; ============================================================
;; バイトコンパイラ向け宣言
;; ============================================================
(defvar ruby-end-insert-newline)

;; ============================================================
;; Ruby 基本設定
;; ============================================================
(use-package ruby-ts-mode
  :straight nil
  :mode (("\\.rb\\'"      . ruby-ts-mode)
         ("Capfile\\'"    . ruby-ts-mode)
         ("Gemfile\\'"    . ruby-ts-mode)
         ("[Ra]kefile\\'" . ruby-ts-mode)
         ("\\.rake\\'"    . ruby-ts-mode)
         ("Berksfile\\'"  . ruby-ts-mode)
         ("Schemafile\\'" . ruby-ts-mode)
         ("\\.rabl\\'"    . ruby-ts-mode))
  :custom
  ;; マジックコメント無効化
  (ruby-insert-encoding-magic-comment nil)
  :config
  ;; 行末空白削除を有効
  (add-hook 'ruby-ts-mode-hook
            (lambda ()
              (setq-local delete-trailing-whitespace-before-save t))))

;; ruby-mode (Tree-sitter 非対応時のフォールバック)
;; :defer t で eager load を止める。ruby-ts-mode 側の :mode で .rb 等の
;; auto-mode-alist は張られており、grammar 未 ready 時は treesit-auto の
;; 動的 remap によって ruby-mode 本体が呼ばれた時点で load → :config が走る
;; (advice が installed される)。Ruby ファイルを一切開かない起動 (batch 含む)
;; では load されない。
(use-package ruby-mode
  :straight nil
  :defer t
  :custom
  (ruby-insert-encoding-magic-comment nil)
  (ruby-deep-indent-paren-style nil)
  :config
  ;; カスタムインデント (閉じ括弧の位置調整)
  (define-advice ruby-indent-line (:after (&rest _) unindent-closing-paren)
    "Adjust indentation for closing parentheses."
    (let ((column (current-column))
          indent offset)
      (save-excursion
        (back-to-indentation)
        (let ((state (syntax-ppss)))
          (setq offset (- column (current-column)))
          (when (and (eq (char-after) ?\))
                     (not (zerop (car state))))
            (goto-char (cadr state))
            (setq indent (current-indentation)))))
      (when indent
        (indent-line-to indent)
        (when (> offset 0) (forward-char offset))))))

;; ============================================================
;; ruby-end (end 自動挿入)
;; ============================================================
(use-package ruby-end
  :hook ((ruby-mode . ruby-end-mode)
         (ruby-ts-mode . ruby-end-mode))
  :config
  (setq ruby-end-insert-newline nil))

(provide 'init-lang-ruby)
;;; init-lang-ruby.el ends here
