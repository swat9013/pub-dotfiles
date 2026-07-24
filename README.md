# pub-dotfiles

`swat9013` の [chezmoi](https://www.chezmoi.io/) 管理 dotfiles から、公開しても差し支えない一部 file を継続的に publish したもの。

## 構成

- ファイル命名は chezmoi source そのまま (`dot_*` は展開後 `.` に対応する)
- **chezmoi user 前提**。この repo を直接 clone しても動作しない。`chezmoi` で apply することを想定している
- 全 file は private 側 (`swat9013/dotfiles`) の manifest から自動生成される。この repo に直接 commit しても次回 release で消える

## 参考: chezmoi での使い方

```bash
brew install chezmoi
chezmoi init --apply https://github.com/swat9013/pub-dotfiles.git
```

## License

MIT (private 側 `LICENSE` 未整備。追って同期予定)

## Contact

<https://github.com/swat9013>
