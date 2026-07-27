# Emacs 設定

Emacs 30+ 向けのシンプルな設定。

## 特徴

- **straight.el** によるパッケージ管理（再現性重視）
- **Vertico/Corfu** スタックによるモダン補完
- **Eglot + Tree-sitter** によるIDE機能
- **シンプル構成** （必要最小限のパッケージ）

## ディレクトリ構成

```
.emacs.d/
├── early-init.el       # 最速で読み込まれる設定
├── init.el             # エントリポイント
├── lisp/               # モジュール群 (init.el の読み込み順)
│   ├── init-debug-log.el   # 起動 warning の永続化
│   ├── init-core.el        # 基本設定
│   ├── init-keybinds.el    # キーバインド
│   ├── init-completion.el  # 補完 (Vertico/Consult/Corfu/Cape)
│   ├── init-project.el     # プロジェクト管理 (project.el)
│   ├── init-treemacs.el    # ファイルツリーサイドバー
│   ├── init-git.el         # Git (Magit/diff-hl)
│   ├── init-lsp.el         # LSP (Eglot)
│   ├── init-treesit.el     # Tree-sitter
│   ├── init-lang-ruby.el   # Ruby
│   ├── init-lang-ts.el     # TypeScript/JavaScript
│   ├── init-lang-web.el    # Web開発
│   ├── init-editing.el     # 編集支援 + OSC52 clipboard (clipetty)
│   ├── init-ui.el          # UI/テーマ
│   ├── init-modeline.el    # モードライン
│   └── init-macos.el       # macOS固有
├── straight/           # straight.el (自動生成)
│   └── versions/       # ロックファイル
├── var/                # データファイル (no-littering)
└── etc/                # 設定ファイル (no-littering)
```

## パッケージ一覧

### 補完
| パッケージ | 役割 |
|-----------|------|
| **Vertico** | ミニバッファ補完UI |
| **Orderless** | 空白区切りマッチング |
| **Marginalia** | 補完候補に注釈表示 |
| **Consult** | 検索・ナビゲーション |
| **Corfu** | インバッファ補完 |
| **Cape** | 補完バックエンド拡張 |

### 開発
| パッケージ | 役割 |
|-----------|------|
| **Eglot** | LSP (組み込み) |
| **Tree-sitter** | シンタックス (組み込み) |
| **Magit** | Git操作 |

### 編集
| パッケージ | 役割 |
|-----------|------|
| **avy** | 画面内ジャンプ |
| **string-inflection** | 命名規則変換 |
| **editorconfig** | プロジェクト設定 |

### UI
| パッケージ | 役割 |
|-----------|------|
| **doom-themes** | テーマ (doom-tokyo-night) |

## キーバインド

### 基本

| キー | コマンド | 説明 |
|-----|---------|------|
| `C-h` | backward-delete-char | Backspace |
| `C-x C-g` | goto-line | 行ジャンプ |
| `C-c C-r` | revert-buffer-no-confirm | ファイル再読込 |
| `C-x C-i` | electric-indent | バッファ全体インデント |

### ウィンドウ・バッファ

| キー | コマンド |
|-----|---------|
| `C-c <arrow>` | windmove-* |
| `M-}` / `M-{` | next/previous-buffer |
| `M-p` / `M-n` | scroll-down/up |

### 検索・ナビゲーション (Consult)

| キー | コマンド | 説明 |
|-----|---------|------|
| `C-s` | consult-line | バッファ内検索 |
| `C-x b` | consult-buffer | バッファ切替 |
| `C-x C-t` | consult-recent-file | 最近のファイル |
| `M-y` | consult-yank-pop | キルリング |
| `C-x r b` | consult-bookmark | ブックマーク |
| `M-g g` | consult-goto-line | 行ジャンプ |
| `M-s r` | consult-ripgrep | ripgrep検索 |
| `C-c C-g` | consult-ripgrep | ripgrep検索 |

### プロジェクト

| キー | コマンド |
|-----|---------|
| `C-x p` | project-prefix-map |
| `C-c C-f` | project-find-file |

### Git (Magit)

| キー | コマンド |
|-----|---------|
| `C-x g` / `C-x m` | magit-status |

### ジャンプ (Avy)

| キー | コマンド |
|-----|---------|
| `C-c SPC` | avy-goto-char-timer |
| `M-g w` | avy-goto-word-1 |
| `M-g l` | avy-goto-line |

## LSP (Eglot)

### 対応言語サーバー

| 言語 | サーバー | インストール |
|-----|---------|-------------|
| TypeScript/JS | typescript-language-server | `npm i -g typescript-language-server typescript` |
| Ruby | solargraph | `gem install solargraph` |
| CSS | eglot 内蔵デフォルト (css-language-server) | `npm i -g vscode-langservers-extracted` |

> HTML (`.html`) は web-mode で開かれ Eglot は未配線。Ruby/TS/JS は `eglot-server-programs` に明示登録、CSS は eglot 内蔵デフォルトに依存する。

## Tree-sitter

### 文法インストール

```
M-x my/treesit-install-all-grammars
```

### モードマッピング

| 旧モード | 新モード |
|---------|---------|
| ruby-mode | ruby-ts-mode |
| typescript-mode | typescript-ts-mode |
| js-mode | js-ts-mode |
| css-mode | css-ts-mode |
| yaml-mode | yaml-ts-mode |

## テーマ

**doom-tokyo-night** (doom-themes)

`init-ui.el` で `(load-theme 'doom-tokyo-night t)` を単一ロード。ライト/ダーク自動切替は未実装。

## トラブルシューティング

### デバッグ起動

```bash
emacs --debug-init
```

### 最小構成で起動

```bash
emacs -Q
```

### パッケージ更新後の問題

```bash
rm -rf ~/.emacs.d/straight/build
```

## 依存関係

### 必須

- Emacs 30+
- Git (straight.el 用)
- C コンパイラ (Tree-sitter 文法ビルド用)

### 推奨

- ripgrep (`brew install ripgrep`)
- fd (`brew install fd`)
