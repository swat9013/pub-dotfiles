;;; init-project.el --- Project Management -*- lexical-binding: t; -*-

;;; Commentary:
;; project.el (組み込み) によるプロジェクト管理

;;; Code:

;; ============================================================
;; project.el (組み込み)
;; ============================================================
(use-package project
  :straight nil
  :bind-keymap ("C-x p" . project-prefix-map)
  :bind* (("C-c C-f" . project-find-file))  ; counsel-projectile-find-file 置換 (major-mode より優先)
  :custom
  (project-switch-commands
   '((project-find-file "Find file")
     (project-find-regexp "Find regexp")
     (project-find-dir "Find directory")
     (project-vc-dir "VC-Dir")
     (project-eshell "Eshell")
     (consult-ripgrep "Ripgrep" ?r)
     (magit-project-status "Magit" ?m))))

;; ============================================================
;; Consult との統合
;; ============================================================
;; consult-project-buffer でプロジェクト内バッファ切り替え
;; consult-ripgrep で project-root を自動検出

(provide 'init-project)
;;; init-project.el ends here
