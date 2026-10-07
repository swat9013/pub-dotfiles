;;; early-init.el --- Early Init -*- lexical-binding: t; -*-

;;; Commentary:
;; Emacs 27+ で init.el より前に読み込まれる設定
;; GC最適化、UI早期無効化、パッケージシステム制御

;;; Code:

;; ============================================================
;; GC最適化 - 起動時は閾値を最大に
;; ============================================================
(setq gc-cons-threshold most-positive-fixnum
      gc-cons-percentage 0.6)

;; ============================================================
;; package.el の自動初期化を無効化 (straight.el 使用のため)
;; ============================================================
(setq package-enable-at-startup nil)

;; ============================================================
;; UI要素の早期無効化 (フラッシュ防止)
;; ============================================================
(push '(menu-bar-lines . 0) default-frame-alist)
(push '(tool-bar-lines . 0) default-frame-alist)
(push '(vertical-scroll-bars) default-frame-alist)

;; フレームサイズの自動調整を無効化
(setq frame-inhibit-implied-resize t)

;; ============================================================
;; Native Compilation 設定 (Emacs 29+)
;; ============================================================
;; early-init の compile 時点では comp.el 未ロードで defcustom が存在しないため
;; 宣言のみ置く (実体は native-comp ビルドの runtime で定義される)。
;; deny-list 側の変数は quote した symbol 越しにしか触らないので defvar は不要
;; (free variable warning は出ない)。
(defvar native-comp-async-report-warnings-errors)

(when (featurep 'native-compile)
  ;; 警告を抑制
  (setq native-comp-async-report-warnings-errors 'silent)

  ;; 自分の設定ファイルを遅延 native-compile の対象から外す。
  ;; 遅延コンパイルの worker は .el を素の環境で読むため、straight 経由で
  ;; 実行時に読み込まれる use-package macro を知らない。その結果
  ;; `(use-package foo ...)` が展開されずに関数呼び出しとして .eln に焼かれ、
  ;; load 時に .elc を差し置いて使われて `void-variable foo` で init が中断する。
  ;; .eln は run_onchange_byte-compile-emacs.sh が use-package をロード済みの
  ;; プロセス内で AOT 生成するので、遅延コンパイルは不要。
  ;; deny-list は comp.el の defcustom で、early-init の時点では未ロード = 未 bound。
  ;; defcustom は既に値のある変数を上書きしないので、先に set しておけば効く
  ;; (boundp で gate すると常に false になり、設定が丸ごと無視される)。
  ;; 判定対象の file 名は .el のことも .elc のこともあるため両方に当てる。
  (let ((deny (format "\\`%s\\(early-init\\|init\\|lisp/init-[^/]*\\)\\.elc?\\'"
                      (regexp-quote (expand-file-name user-emacs-directory))))
        ;; Emacs 29 で native-comp-deferred-compilation-deny-list から改名された。
        (var (if (>= emacs-major-version 29)
                 'native-comp-jit-compilation-deny-list
               'native-comp-deferred-compilation-deny-list)))
    (set var (cons deny (and (boundp var) (symbol-value var)))))

  ;; ネイティブコンパイルキャッシュの場所
  (when (fboundp 'startup-redirect-eln-cache)
    (startup-redirect-eln-cache
     (convert-standard-filename
      (expand-file-name "var/eln-cache/" user-emacs-directory)))))

;; ============================================================
;; その他の早期設定
;; ============================================================
;; file-name-handler-alist を一時的に無効化（起動高速化）
(defvar my/file-name-handler-alist file-name-handler-alist)
(setq file-name-handler-alist nil)

;; 起動完了後に復元
(add-hook 'emacs-startup-hook
          (lambda ()
            (setq file-name-handler-alist my/file-name-handler-alist)))

;;; early-init.el ends here
