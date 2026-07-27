#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# dependencies = []
# ///
"""
cleanup-claude-projects.py: ~/.claude.json の残骸 projects エントリを削除する

Claude Code は Bash sandbox profile を ~/.claude.json の projects エントリ等から
構築して argv で渡すため、残骸エントリの蓄積で ARG_MAX (1MB) を超え E2BIG が
頻発する。本スクリプトはパスが存在しない (missing) projects エントリに加え、
「パスは実在するが長期間セッションのない」(inactive) エントリも既定で削除して
肥大化を防ぐ。inactive の判定根拠:

- ~/.claude.json のエントリ内に信頼できる最終セッション時刻フィールドは存在しない
  (lastSessionModified を持つのはごく一部のみ)
- 唯一のデータ源は ~/.claude/projects/<encoded-path>/*.jsonl (transcript)。
  Claude Code 自身が cleanupPeriodDays (既定 30 日) で古い transcript を自動削除
  するため「transcript が存在しない」≈「保持期間内にセッションなし」が成立する。
  日付計算は不要で、*.jsonl の存在チェックのみでよい
- パス→ディレクトリ名のエンコード規則: '/'・'.'・'_' をすべて '-' に置換
  (例: /Users/foo/.claude → -Users-foo--claude)
- 削除で失われるのは再承認系フラグのみ (trust dialog、CLAUDE.md external includes
  承認、MCP 有効化選択) であることを実測確認済み。mcpServers 定義・ignorePatterns・
  history・allowedTools は全削除候補で空。権限グラント本体は各 repo の
  .claude/settings.local.json にあり影響しない

Claude Code 稼働中に ~/.claude.json を外部編集すると in-memory 状態で上書きされ
変更が消える既知バグ (anthropics/claude-code#27941) があるため、対話 CLI が
1 つでも走っていれば何もせず exit 0 でスキップする。--dry-run は読み取り専用の
ため guard をバイパスして削除候補を列挙する。

対話 CLI の検出には ps コマンドラインを見る。pgrep -x claude は使えない:
Claude Code CLI は起動直後に process.title を version 文字列 ('2.1.218' 等) に
書き換えるため kernel p_comm が 'claude' ではなくなり、対話セッションを取り
こぼす。逆に plugin が spawn する Haiku subagent は argv[0]='.../claude' で
残るため pgrep -x が誤検出する。~/.claude.json を書き換えるのは対話 CLI のみで、
--input-format stream-json で親に制御される subagent は書き換え主体ではない。

書き込みは backup (~/.claude.json.bak) 作成後、同一ディレクトリの tmp ファイルへ
書いて os.replace する atomic write。projects 以外のキーと dict の挿入順は保持する。
"""

import argparse
import json
import os
import pathlib
import shutil
import stat
import subprocess
import sys
import tempfile
from collections.abc import Callable

PREFIX = "cleanup-claude-projects:"


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument(
        "--dry-run",
        action="store_true",
        help="削除対象パスを列挙するのみで書き込まない（guard もバイパスする）",
    )
    return p.parse_args(argv)


def is_interactive_claude(command_line: str) -> bool:
    """ps -o command 行 1 本が対話 claude CLI か判定する純粋関数。

    - argv[0] の basename が 'claude' であること
    - --input-format flag を持たない (これがあると親 CLI が stream-json で
      制御している subagent なので ~/.claude.json は書き換えない)
    """
    tokens = command_line.split()
    if not tokens:
        return False
    if pathlib.PurePosixPath(tokens[0]).name != "claude":
        return False
    if "--input-format" in tokens:
        return False
    return True


def count_interactive_claude(ps_lines: list[str]) -> int:
    """ps -Axo command= の出力行から対話 claude CLI をカウントする純粋関数。"""
    return sum(1 for line in ps_lines if is_interactive_claude(line))


def count_claude_processes() -> int:
    """稼働中の対話 claude CLI プロセス数を返す。判別ロジックはモジュール docstring 参照。"""
    result = subprocess.run(["ps", "-Axo", "command="], capture_output=True, text=True)
    if result.returncode != 0:
        return 0
    return count_interactive_claude(result.stdout.splitlines())


def extract_stale_projects(
    projects: dict[str, object], path_exists: Callable[[str], bool]
) -> list[str]:
    """パスが存在しない projects キーを列挙する純粋関数。"""
    return [path for path in projects if not path_exists(path)]


def encode_project_dir(path: str) -> str:
    """project パスを ~/.claude/projects/ 配下のディレクトリ名へ変換する純粋関数。

    Claude Code のエンコード規則: '/'・'.'・'_' をすべて '-' に置換する。
    例: /Users/foo/.claude → -Users-foo--claude、/a/b_c.d → -a-b-c-d
    """
    return path.replace("/", "-").replace(".", "-").replace("_", "-")


def extract_inactive_projects(
    projects: dict[str, object],
    path_exists: Callable[[str], bool],
    has_transcript: Callable[[str], bool],
) -> list[str]:
    """パスは実在するが transcript のない projects キーを列挙する純粋関数。

    パス消滅エントリは extract_stale_projects (missing 側) の担当なので含めない。
    """
    return [path for path in projects if path_exists(path) and not has_transcript(path)]


def default_has_transcript(path: str) -> bool:
    """~/.claude/projects/<encoded>/ に *.jsonl が 1 つでもあるか判定する。"""
    transcript_dir = (
        pathlib.Path(os.path.expanduser("~/.claude/projects")) / encode_project_dir(path)
    )
    return any(transcript_dir.glob("*.jsonl"))


def run(
    config_path: pathlib.Path,
    dry_run: bool,
    claude_process_count: int,
    has_transcript: Callable[[str], bool] = default_has_transcript,
) -> int:
    if not dry_run and claude_process_count > 0:
        print(f"{PREFIX} skipped: claude process running ({claude_process_count} found)")
        return 0

    try:
        config = json.loads(config_path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as e:
        print(f"{PREFIX} ERROR: cannot read {config_path}: {e}", file=sys.stderr)
        return 1

    projects = config.get("projects")
    if not isinstance(projects, dict):
        print(f"{PREFIX} no projects dict, nothing to do")
        return 0

    missing = extract_stale_projects(projects, os.path.exists)
    inactive = extract_inactive_projects(projects, os.path.exists, has_transcript)
    stale = missing + inactive
    removed_desc = f"{len(missing)} missing + {len(inactive)} inactive"

    if dry_run:
        for path in missing:
            print(f"{PREFIX} would remove (missing): {path}")
        for path in inactive:
            print(f"{PREFIX} would remove (inactive): {path}")
        print(
            f"{PREFIX} dry-run: {removed_desc}, "
            f"{len(projects) - len(stale)} remaining of {len(projects)}"
        )
        return 0

    if not stale:
        print(f"{PREFIX} removed {removed_desc} entries, {len(projects)} remaining")
        return 0

    backup_path = pathlib.Path(str(config_path) + ".bak")
    try:
        shutil.copy2(config_path, backup_path)
    except OSError as e:
        print(f"{PREFIX} ERROR: backup to {backup_path} failed: {e}", file=sys.stderr)
        return 1

    for path in stale:
        del projects[path]

    mode = stat.S_IMODE(config_path.stat().st_mode)
    fd, tmp_name = tempfile.mkstemp(dir=config_path.parent, prefix=config_path.name + ".tmp")
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            json.dump(config, f, ensure_ascii=False, indent=2)
            f.write("\n")
        os.chmod(tmp_name, mode)
        os.replace(tmp_name, config_path)
    except OSError as e:
        os.unlink(tmp_name)
        print(f"{PREFIX} ERROR: write to {config_path} failed: {e}", file=sys.stderr)
        return 1

    print(f"{PREFIX} removed {removed_desc} entries, {len(projects)} remaining")
    return 0


def main(args: argparse.Namespace) -> int:
    config_path = pathlib.Path(os.path.expanduser("~/.claude.json"))
    return run(config_path, dry_run=args.dry_run, claude_process_count=count_claude_processes())


if __name__ == "__main__":
    try:
        sys.exit(main(parse_args()))
    except KeyboardInterrupt:
        sys.exit(130)
