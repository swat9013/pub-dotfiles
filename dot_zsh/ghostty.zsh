# Ghostty タブタイトルをカレントディレクトリ末尾に設定する
# (shell-integration-features の title を no-title にした置き換え)

if [[ "$TERM_PROGRAM" == "ghostty" ]]; then
  autoload -Uz add-zsh-hook

  function _ghostty_set_tab_title() {
    print -Pn "\e]2;%1~\a"
  }

  add-zsh-hook precmd _ghostty_set_tab_title
  add-zsh-hook chpwd _ghostty_set_tab_title
fi

# myssh: ssh 接続先ホストを Ghostty タブタイトルに設定するラッパー。
# 直打ち接続と hd (@host) の双方からこの関数を共通利用し、タイトル設定を一元化する。
# ssh 終了後は上の precmd (_ghostty_set_tab_title) が次プロンプトでパス表示へ戻す。
# 非 ghostty では素の ssh と同じ挙動 (タイトルは設定しない)。
function myssh() {
  emulate -L zsh
  if [[ "$TERM_PROGRAM" == "ghostty" ]]; then
    # 引数を取る短オプションは値を読み飛ばし、最初の非オプション語を接続先とする
    local w dest=""
    integer skip=0
    for w in "$@"; do
      if (( skip )); then skip=0; continue; fi
      case $w in
        -[BbcDEeFIiJLlmOopQRSWw]) skip=1 ;;
        -*) ;;
        *) dest=$w; break ;;
      esac
    done
    [[ -n $dest ]] && print -Pn "\e]2;${dest##*@}\a"  # user@ を除去しホスト部のみ
  fi
  command ssh "$@"
}
