# pub-dotfiles

[chezmoi](https://www.chezmoi.io/) 管理の dotfiles (抜粋)。ファイル命名は chezmoi source 形式 (`dot_*` は展開後 `.*` に対応)。

## 使い方

```bash
brew install chezmoi
chezmoi init --apply https://github.com/swat9013/pub-dotfiles.git
```

## apply 時に走るもの

`run_*` script は `chezmoi apply` の一部として自動実行される。実行させたくない場合は `--exclude=scripts` を付ける (`chezmoi init --apply --exclude=scripts` / `chezmoi apply --exclude=scripts`)。`.chezmoiignore` では抑止できない。

| script | 動作 | 条件 |
|---|---|---|
| `run_onchange_byte-compile-emacs.sh.tmpl` | `~/.emacs.d` の elisp を batch byte-compile | `emacs` と straight.el bootstrap が揃っているときのみ。いずれか欠けていれば何もしない |

`.Brewfile` は配布するが、インストールは自動化していない。必要なら任意のタイミングで実行する。

```bash
brew bundle --global
```

## 別途インストールが要るもの

`.claude/settings.json` の SessionStart hook は `~/.claude/hooks/herdr-agent-state.sh` を呼ぶ。この hook 本体は本リポジトリに含まれない ([herdr](https://herdr.dev) が生成するため)。

- herdr を使うなら `herdr integration install claude` で hook を配置する
- 使わないなら何もしなくてよい。hook は存在チェック付きで呼ばれるので、未導入環境では何も起きない

## `.local` による拡張

`.zshrc` / `.zshenv` / `.gitconfig` は、それぞれ末尾で同名の `.local` ファイルを読む (存在すれば)。マシン固有の設定や identity はそちらに置く。これらは本リポジトリに含まれない。

```bash
# 例: ~/.gitconfig.local
[user]
	name = Your Name
	email = you@example.com
```
