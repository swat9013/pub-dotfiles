;;; init-core.el --- Core Settings -*- lexical-binding: t; -*-

;;; Commentary:
;; 基本設定、エンコーディング、UI、カスタム関数

;;; Code:

;; ============================================================
;; 言語・エンコーディング設定
;; ============================================================
(set-language-environment "japanese")
(prefer-coding-system 'utf-8-unix)
(set-terminal-coding-system 'utf-8)
(set-keyboard-coding-system 'utf-8)
(set-buffer-file-coding-system 'utf-8)
(set-default-coding-systems 'utf-8)

;; East Asian Ambiguous 文字 (—— U+2014 等) のカーソルずれ対策。
;; set-language-environment "japanese" は ambiguous 幅文字を全角(2)で計算するが、
;; ghostty (TTY) は Unicode 標準準拠で半角(1)描画するため幅が食い違いカーソルがずれる。
;; 端末の描画(半角)に合わせて Emacs 側も ambiguous=半角に戻す。
(use-default-char-width-table)

;; ============================================================
;; 基本UI設定
;; ============================================================
(use-package emacs
  :straight nil
  :custom
  ;; 起動画面
  (inhibit-startup-screen t)
  (initial-scratch-message nil)

  ;; ダイアログ
  (use-dialog-box nil)
  (use-short-answers t)  ; yes/no → y/n

  ;; ベル
  (ring-bell-function 'ignore)

  ;; 編集
  (indent-tabs-mode nil)
  (tab-width 4)
  (require-final-newline t)
  (delete-selection-mode t)

  ;; バックアップ・自動保存 (no-littering が管理)
  (make-backup-files nil)
  (auto-save-default nil)
  (create-lockfiles nil)
  (backup-inhibited t)

  ;; シンボリックリンク
  (vc-follow-symlinks t)

  ;; スクロール
  (scroll-conservatively 101)
  (scroll-margin 3)
  (scroll-step 3)
  (scroll-preserve-screen-position t)
  (mouse-wheel-scroll-amount '(1 ((shift) . 1)))
  (mouse-wheel-progressive-speed nil)
  (mouse-wheel-follow-mouse t)

  ;; C-v/M-v で限界に達したら先頭/末尾に移動
  (scroll-error-top-bottom t)

  ;; 行の扱い
  (kill-whole-line t)  ; C-k で行全体を削除
  (truncate-lines nil)

  :init
  ;; UIモード
  (tool-bar-mode -1)
  (menu-bar-mode -1)
  (when (fboundp 'scroll-bar-mode)
    (scroll-bar-mode -1))
  (blink-cursor-mode -1)
  (xterm-mouse-mode 1)
  (mouse-wheel-mode 1)

  ;; 表示モード
  (column-number-mode 1)
  (line-number-mode 1)
  (global-display-line-numbers-mode 1)
  (global-auto-revert-mode 1)
  (electric-pair-mode 1)
  (show-paren-mode 1)
  (transient-mark-mode 1)
  (auto-compression-mode 1)
  (auto-image-file-mode 1)
  (which-function-mode 1))

;; show-paren-mode 設定
(setq show-paren-style 'mixed)

;; ============================================================
;; SGR mouse: サイドボタン (mouse-8/mouse-9) を正しく識別する
;; ============================================================
;; Emacs 30 同梱の xt-mouse.el は SGR mouse の button code を
;; `(logand code 3)' で下位 2bit に圧縮するため、code 128 (back) /
;; 129 (forward) が mouse-1 / mouse-2 と衝突する。
;; SGR 1006 で code >= 128 のときは +8 オフセットで mouse-8 以降に
;; マップし直す。Emacs 31 で改善されたら除去する。
(with-eval-after-load 'xt-mouse
  (defun xterm-mouse--read-event-sequence (&optional extension)
    (pcase-let*
        ((`(,code . ,_) (xterm-mouse--read-number-from-terminal extension))
         (`(,x . ,_)    (xterm-mouse--read-number-from-terminal extension))
         (`(,y . ,c)    (xterm-mouse--read-number-from-terminal extension))
         (side  (>= code 128))
         (wheel (and (not side) (/= (logand code 64) 0)))
         (move  (/= (logand code 32) 0))
         (ctrl  (/= (logand code 16) 0))
         (meta  (/= (logand code 8) 0))
         (shift (/= (logand code 4) 0))
         (down (and (not wheel)
                    (not move)
                    (if extension
                        (eq c ?M)
                      (/= (logand code 3) 3))))
         (btn (cond
               (side
                (+ (logand code 3) 8))
               ((or extension down wheel)
                (+ (logand code 3) (if wheel 4 1)))
               ((terminal-parameter nil 'xterm-mouse-last-down)
                (string-to-number
                 (substring
                  (symbol-name
                   (car (terminal-parameter nil 'xterm-mouse-last-down)))
                  -1)))
               (t 1)))
         (sym
          (if move 'mouse-movement
            (intern
             (concat
              (if ctrl "C-" "")
              (if meta "M-" "")
              (if shift "S-" "")
              (if down "down-" "")
              (let ((remap (alist-get btn mouse-wheel-buttons)))
                (if remap
                    (symbol-name remap)
                  (format "mouse-%d" btn))))))))
      (list sym (1- x) (1- y)))))

;; ============================================================
;; 履歴・セッション管理
;; ============================================================
(use-package recentf
  :straight nil
  :custom
  (recentf-max-saved-items 200)
  (recentf-auto-cleanup 'never)
  (recentf-exclude '("\\.recentf" "COMMIT_EDITMSG"))
  :config
  (recentf-mode 1)
  ;; no-littering ディレクトリを除外
  (with-eval-after-load 'no-littering
    (add-to-list 'recentf-exclude no-littering-var-directory)
    (add-to-list 'recentf-exclude no-littering-etc-directory))
  ;; 自動保存
  (setq recentf-auto-save-timer
        (run-with-idle-timer 30 t 'recentf-save-list)))

(use-package savehist
  :straight nil
  :custom
  (history-length 100)
  :config
  (savehist-mode 1))

(use-package saveplace
  :straight nil
  :config
  (save-place-mode 1))

;; ============================================================
;; Whitespace (全角スペース・タブ可視化)
;; ============================================================
(use-package whitespace
  :straight nil
  :custom
  (whitespace-style '(tabs tab-mark spaces space-mark))
  (whitespace-space-regexp "\\(\x3000+\\)")
  (whitespace-display-mappings
   '((space-mark ?\x3000 [?\〼])
     (tab-mark   ?\t     [?\xBB ?\t])))
  :config
  ;; whitespace の face 色はテーマ (doom-tokyo-night) に委ねる
  (global-whitespace-mode 1))

;; 行末空白表示
(setq-default show-trailing-whitespace t)

;; ============================================================
;; 行末空白削除 (保存時)
;; ============================================================
(defvar delete-trailing-whitespace-before-save t
  "If non-nil, delete trailing whitespace before saving.")

(defun my/delete-trailing-whitespace ()
  "Delete trailing whitespace if enabled."
  (when delete-trailing-whitespace-before-save
    (delete-trailing-whitespace)))

(add-hook 'before-save-hook #'my/delete-trailing-whitespace)

;; ============================================================
;; カスタム関数
;; ============================================================
(defun move-line-down ()
  "Move current line down."
  (interactive)
  (let ((col (current-column)))
    (save-excursion
      (forward-line)
      (transpose-lines 1))
    (forward-line)
    (move-to-column col)))

(defun move-line-up ()
  "Move current line up."
  (interactive)
  (let ((col (current-column)))
    (save-excursion
      (forward-line)
      (transpose-lines -1))
    (move-to-column col)))

(defun revert-buffer-no-confirm (&optional force-reverting)
  "Revert buffer without confirmation.
With FORCE-REVERTING, revert even if modified."
  (interactive "P")
  (if (or force-reverting (not (buffer-modified-p)))
      (revert-buffer :ignore-auto :noconfirm)
    (error "The buffer has been modified")))

(defun all-indent ()
  "Indent the entire buffer."
  (interactive)
  (save-excursion
    (indent-region (point-min) (point-max))))

(defun electric-indent ()
  "Indent region if active, otherwise indent entire buffer."
  (interactive)
  (if (use-region-p)
      (indent-region (region-beginning) (region-end))
    (all-indent)))

(provide 'init-core)
;;; init-core.el ends here
