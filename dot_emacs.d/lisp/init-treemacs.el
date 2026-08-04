;;; init-treemacs.el --- File Tree Sidebar -*- lexical-binding: t; -*-

;;; Commentary:
;; treemacs によるファイルツリーサイドバー
;; TTY (emacs -nw) ではテキストアイコンに自動フォールバックする

;;; Code:

(use-package treemacs
  ;; C-x t t でトグル。tab-prefix-map に追加し tab-bar の他キーは温存する
  :bind (:map tab-prefix-map
              ("t" . treemacs))
  :config
  ;; project.el の現在プロジェクトをワークスペースに自動追従
  (treemacs-project-follow-mode 1))

;; ============================================================
;; 画面幅に応じた自動開閉 (responsive sidebar)
;; ============================================================
;; フレーム全体幅を唯一の真実とし、閾値以上なら treemacs を開き、下回れば
;; 閉じる。tmux ペイン分割/ターミナルリサイズ (SIGWINCH) に追従する。
;; 手動 C-x t t は次のリサイズまでの一時状態 (幅優先)。

(defvar my/treemacs-auto-width-threshold 120
  "treemacs を自動表示するフレーム全体幅 (桁) の下限。
この値を下回ると自動で閉じる。開いたときの編集領域は概ね
\\='幅 - treemacs-width - 1\\='。")

(defvar my/treemacs-sync-timer nil
  "`my/treemacs-sync-to-width' のデバウンス用 idle timer。")

(declare-function treemacs-current-visibility "treemacs-scope")
(declare-function treemacs-select-window "treemacs")
(declare-function treemacs-get-local-window "treemacs-scope")
;; treemacs-current-visibility は define-inline で、展開 body が
;; treemacs-get-local-buffer も呼ぶ
(declare-function treemacs-get-local-buffer "treemacs-scope")

(defun my/treemacs-sync-to-width ()
  "フレーム幅に treemacs の表示状態を一致させる (冪等)。
幅が `my/treemacs-auto-width-threshold' 以上なら開き、下回れば閉じる。
狭いフレームでは treemacs 未ロードのまま何もしない (起動を軽く保つ)。"
  (if (>= (frame-width) my/treemacs-auto-width-threshold)
      (progn
        (require 'treemacs)
        (unless (eq (treemacs-current-visibility) 'visible)
          ;; フォーカスを奪わずに開く
          (save-selected-window (treemacs-select-window))))
    (when (and (featurep 'treemacs)
               (eq (treemacs-current-visibility) 'visible))
      (delete-window (treemacs-get-local-window)))))

(defun my/treemacs-sync-schedule (&rest _)
  "リサイズ追従用デバウンサ。`window-size-change-functions' から呼ぶ。
redisplay 中のウィンドウ改変を避けるため idle timer 経由で同期する。"
  (when (timerp my/treemacs-sync-timer)
    (cancel-timer my/treemacs-sync-timer))
  (setq my/treemacs-sync-timer
        (run-with-idle-timer 0.3 nil #'my/treemacs-sync-to-width)))

(add-hook 'window-size-change-functions #'my/treemacs-sync-schedule)
(add-hook 'emacs-startup-hook #'my/treemacs-sync-to-width)

(provide 'init-treemacs)
;;; init-treemacs.el ends here
