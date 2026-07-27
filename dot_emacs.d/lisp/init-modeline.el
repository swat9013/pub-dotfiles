;;; init-modeline.el --- Mode Line Configuration -*- lexical-binding: t; -*-

;;; Commentary:
;; カスタムモードライン設定
;; - 組み込み機能を最大活用
;; - Git/Eglot/Flymake状態表示
;; - minionsでマイナーモード折りたたみ

;;; Code:

;; ============================================================
;; バイトコンパイラ向け宣言
;; ============================================================
(defvar auto-revert-check-vc-info)
(declare-function minions-mode "minions")
(declare-function eglot-current-server "eglot")
(declare-function eglot-project-nickname "eglot")
(declare-function flymake-diagnostic-type "flymake")

;; ============================================================
;; ヘルパー関数
;; ============================================================

(defun my/vc-mode-line ()
  "Format vc-mode for mode-line with Git branch and status."
  (when (and vc-mode buffer-file-name)
    (let* ((backend (vc-backend buffer-file-name))
           (branch (substring-no-properties vc-mode
                     (+ (if (eq backend 'Git) 5 4) 2)))
           (state (vc-state buffer-file-name)))
      (concat
       (propertize " " 'face 'mode-line)
       (propertize branch 'face 'success)
       (pcase state
         ('edited   (propertize "*" 'face 'warning))
         ('added    (propertize "+" 'face 'success))
         ('removed  (propertize "-" 'face 'error))
         ('conflict (propertize "!" 'face 'error))
         ('needs-merge (propertize "M" 'face 'error))
         ('needs-update (propertize "U" 'face 'warning))
         (_ ""))))))

(defun my/eglot-mode-line ()
  "Format Eglot status for mode-line."
  (when (bound-and-true-p eglot--managed-mode)
    (let ((server (eglot-current-server)))
      (if server
          (propertize " LSP" 'face 'success
                      'help-echo (format "Eglot: %s"
                                         (eglot-project-nickname server)))
        (propertize " LSP" 'face 'shadow
                    'help-echo "Eglot: disconnected")))))

(defun my/flymake-mode-line ()
  "Format Flymake diagnostics count for mode-line."
  (when (bound-and-true-p flymake-mode)
    (let ((diags (flymake-diagnostics))
          (errors 0) (warnings 0))
      (dolist (d diags)
        (let ((type (flymake-diagnostic-type d)))
          (cond
           ((memq type '(:error eglot-error)) (cl-incf errors))
           ((memq type '(:warning eglot-warning)) (cl-incf warnings)))))
      (when (or (> errors 0) (> warnings 0))
        (concat
         (when (> errors 0)
           (propertize (format " E:%d" errors) 'face 'error))
         (when (> warnings 0)
           (propertize (format " W:%d" warnings) 'face 'warning)))))))

(defun my/encoding-mode-line ()
  "Format encoding and EOL style for mode-line."
  (when buffer-file-coding-system
    (let* ((sys buffer-file-coding-system)
           (eol-type (coding-system-eol-type sys))
           (coding-base (symbol-name (coding-system-base sys)))
           (coding-str (upcase coding-base)))
      ;; UTF-8/LF は標準なので省略、それ以外のみ表示
      (cond
       ((and (string-prefix-p "UTF-8" coding-str) (eq eol-type 0))
        nil)
       ((eq eol-type 0)
        (format " %s" (substring coding-str 0 (min 8 (length coding-str)))))
       (t
        (format " %s/%s"
                (substring coding-str 0 (min 8 (length coding-str)))
                (pcase eol-type (1 "CRLF") (2 "CR") (_ "?"))))))))

;; ============================================================
;; mode-line-format 定義
;; ============================================================

(setq-default mode-line-format
  '("%e"
    mode-line-front-space

    ;; 変更/読み取り専用状態
    (:eval (cond
            (buffer-read-only
             (propertize " RO " 'face 'error))
            ((buffer-modified-p)
             (propertize " ** " 'face 'warning))
            (t "    ")))

    ;; バッファ名
    mode-line-buffer-identification

    ;; メジャーモード
    " "
    (:eval (propertize (format "(%s)" (format-mode-line mode-name))
                       'face 'shadow))

    ;; Git状態
    (:eval (my/vc-mode-line))

    ;; Eglot/Flymake状態
    (:eval (my/eglot-mode-line))
    (:eval (my/flymake-mode-line))

    ;; 右寄せ
    mode-line-format-right-align

    ;; エンコーディング (UTF-8/LF以外のみ表示)
    (:eval (my/encoding-mode-line))

    ;; 位置
    " "
    mode-line-position

    ;; マイナーモード (minions)
    mode-line-modes

    mode-line-end-spaces))

;; ============================================================
;; minions (マイナーモード折りたたみ)
;; ============================================================

(use-package minions
  :custom
  (minions-mode-line-lighter ";-)")
  (minions-prominent-modes '(flymake-mode))
  :config
  (minions-mode 1))

;; ============================================================
;; vc-mode 最適化
;; ============================================================

;; Git以外のバックエンドを無効化
(setq vc-handled-backends '(Git))

;; auto-revert時のvc情報更新を無効化（フリーズ防止）
;; vc-stateの同期Git呼び出しがブロッキングの原因となるため
(setq auto-revert-check-vc-info nil)

(provide 'init-modeline)
;;; init-modeline.el ends here
