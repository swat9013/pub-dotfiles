#!/usr/bin/env bash
# ~/.local/bin/git-tidy.sh
# git tidy: main/master 最新化 + merged branch/worktree 掃除 + detached worktree 掃除
# 要件: bash 4+ (declare -A / associative array 使用のため)
set -euo pipefail
IFS=$'\n\t'

if (( BASH_VERSINFO[0] < 4 )); then
  echo "error: git-tidy requires bash 4+ (found bash ${BASH_VERSION})" >&2
  echo "  macOS 標準 /bin/bash は 3.2。Homebrew bash を PATH 先頭に配置してください" >&2
  exit 2
fi

FORCE=0
DRY_RUN=0
NO_PULL=0
TARGET_BRANCH=""
declare -A WT_MAP=()
DETACHED_WTS=()
readonly PROTECTED_RE='^(develop|master|main|pre-release|release|development|staging|production)$'

usage() {
  cat <<'EOF'
usage: git tidy [<branch>] [--force] [--dry-run] [--no-pull]

  <branch>    checkout & pull 対象 (省略時: origin/HEAD → main → master)
  --force     dirty worktree も強制削除 (worktree remove --force + branch -D)
  --dry-run   実行対象を stdout に列挙のみ (削除しない)
  --no-pull   pull を skip (現在 branch 上で cleanup のみ)

  掃除対象は 2 種: (1) <branch> に merge 済みの branch とその worktree
  (2) branch を持たない detached HEAD の linked worktree (clean なもの。
      commit は repo に残るため作業は失われない。dirty は --force のみ)
EOF
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -h|--help)   usage; exit 0 ;;
      --force)     FORCE=1; shift ;;
      --dry-run)   DRY_RUN=1; shift ;;
      --no-pull)   NO_PULL=1; shift ;;
      -*)          echo "unknown flag: $1" >&2; usage >&2; exit 2 ;;
      *)
        if [[ -n "$TARGET_BRANCH" ]]; then
          echo "unexpected argument: $1" >&2; exit 2
        fi
        TARGET_BRANCH="$1"; shift
        ;;
    esac
  done
}

run_cmd() {
  local label="$1"; shift
  if [[ $DRY_RUN -eq 1 ]]; then
    echo "would: $label"
  else
    "$@"
  fi
}

preflight() {
  if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "error: not inside a git work tree" >&2
    exit 2
  fi
  local git_dir common_dir
  git_dir="$(git rev-parse --git-dir)"
  common_dir="$(git rev-parse --git-common-dir)"
  if [[ "$(cd "$git_dir" && pwd)" != "$(cd "$common_dir" && pwd)" ]]; then
    echo "warn: running from a linked worktree; checkout/pull will affect this worktree only" >&2
  fi
}

resolve_target_branch() {
  if [[ -n "$TARGET_BRANCH" ]]; then
    return
  fi
  local head_ref candidate
  if head_ref="$(git symbolic-ref --quiet refs/remotes/origin/HEAD 2>/dev/null)"; then
    # prefix-strip で '/' 含む branch 名 (release/1.0 等) も正しく抽出
    TARGET_BRANCH="${head_ref#refs/remotes/origin/}"
    return
  fi
  for candidate in main master; do
    if git show-ref --verify --quiet "refs/heads/$candidate"; then
      TARGET_BRANCH="$candidate"
      return
    fi
  done
  echo "error: could not resolve default branch (no origin/HEAD, no local main or master)" >&2
  exit 2
}

checkout_and_pull() {
  if [[ $NO_PULL -eq 1 ]]; then
    echo "skip pull (--no-pull)"
    return
  fi
  local current
  current="$(git rev-parse --abbrev-ref HEAD)"
  if [[ "$current" != "$TARGET_BRANCH" ]]; then
    run_cmd "git checkout $TARGET_BRANCH" git checkout "$TARGET_BRANCH"
  fi
  run_cmd "git pull --ff-only" git pull --ff-only
}

prune_remotes() {
  run_cmd "git fetch --prune" git fetch --prune
}

list_merged_branches() {
  # dry-run でも列挙自体は read-only なので実行する (worktree map と一致させるため)
  # '*' (現在 HEAD) のみ除外。'+' (他 worktree checkout) は残す — その worktree
  # を先に remove してから branch -d するのが git tidy の主目的
  git branch --merged "$TARGET_BRANCH" \
    | grep -vE '^\*' \
    | sed 's/^[[:space:]]*//' \
    | sed 's/^+ //' \
    | grep -vxE "$PROTECTED_RE" || true
}

build_worktree_map() {
  # porcelain の先頭 block は必ず main working tree。detached でも絶対に消さない
  local path="" branch="" is_main=1
  while IFS= read -r line; do
    case "$line" in
      "worktree "*) path="${line#worktree }"; branch="" ;;
      "branch refs/heads/"*)
        branch="${line#branch refs/heads/}"
        WT_MAP["$branch"]="$path"
        ;;
      "detached")
        if [[ $is_main -eq 0 && -n "$path" ]]; then
          DETACHED_WTS+=("$path")
        fi
        ;;
      "") path=""; branch=""; is_main=0 ;;
    esac
  done < <(git worktree list --porcelain)
}

cleanup() {
  local merged="$1"
  local removed_branches=0 removed_worktrees=0 skipped=0 failed=0
  while IFS= read -r br; do
    [[ -z "$br" ]] && continue
    local wt="${WT_MAP[$br]:-}"
    if [[ -n "$wt" ]]; then
      local dirty=0
      if [[ -n "$(git -C "$wt" status --porcelain 2>/dev/null)" ]]; then
        dirty=1
      fi
      if [[ $dirty -eq 1 && $FORCE -eq 0 ]]; then
        echo "skip: $br @ $wt is dirty (use --force to override)" >&2
        ((skipped++)) || true
        continue
      fi
      local wt_ok=1
      if [[ $dirty -eq 1 ]]; then
        run_cmd "git worktree remove --force $wt" git worktree remove --force "$wt" || wt_ok=0
      else
        run_cmd "git worktree remove $wt" git worktree remove "$wt" || wt_ok=0
      fi
      if [[ $wt_ok -eq 0 ]]; then
        echo "warn: worktree remove failed for $br @ $wt, skipping branch delete" >&2
        ((failed++)) || true
        continue
      fi
      ((removed_worktrees++)) || true
    fi
    local br_ok=1
    if [[ $FORCE -eq 1 ]]; then
      run_cmd "git branch -D $br" git branch -D "$br" || br_ok=0
    else
      run_cmd "git branch -d $br" git branch -d "$br" || br_ok=0
    fi
    if [[ $br_ok -eq 0 ]]; then
      echo "warn: branch delete failed for $br" >&2
      ((failed++)) || true
      continue
    fi
    ((removed_branches++)) || true
  done <<<"$merged"
  local summary="summary: removed $removed_branches branches, $removed_worktrees worktrees, skipped $skipped dirty"
  if [[ $failed -gt 0 ]]; then
    summary+=", failed $failed"
  fi
  echo "$summary"
}

cleanup_detached() {
  # branch を持たない linked worktree は list_merged_branches に載らないため別掃除。
  # detached HEAD の commit は repo に残る (reflog/オブジェクトは消えない) ので
  # clean なら安全に消せる。dirty は --force のみ。
  local removed=0 skipped=0 failed=0
  local wt
  for wt in ${DETACHED_WTS[@]+"${DETACHED_WTS[@]}"}; do
    local dirty=0
    if [[ -n "$(git -C "$wt" status --porcelain 2>/dev/null)" ]]; then
      dirty=1
    fi
    if [[ $dirty -eq 1 && $FORCE -eq 0 ]]; then
      echo "skip: detached worktree $wt is dirty (use --force to override)" >&2
      ((skipped++)) || true
      continue
    fi
    local wt_ok=1
    if [[ $dirty -eq 1 ]]; then
      run_cmd "git worktree remove --force $wt (detached)" git worktree remove --force "$wt" || wt_ok=0
    else
      run_cmd "git worktree remove $wt (detached)" git worktree remove "$wt" || wt_ok=0
    fi
    if [[ $wt_ok -eq 0 ]]; then
      echo "warn: worktree remove failed for detached $wt (locked?)" >&2
      ((failed++)) || true
      continue
    fi
    ((removed++)) || true
  done
  if (( removed + skipped + failed > 0 )); then
    local summary="summary(detached): removed $removed worktrees, skipped $skipped dirty"
    if [[ $failed -gt 0 ]]; then
      summary+=", failed $failed"
    fi
    echo "$summary"
  fi
}

main() {
  parse_args "$@"
  preflight
  resolve_target_branch
  checkout_and_pull
  prune_remotes
  build_worktree_map
  local merged
  merged="$(list_merged_branches)"
  if [[ -z "$merged" ]]; then
    echo "no merged branches to clean up"
  else
    cleanup "$merged"
  fi
  cleanup_detached
  run_cmd "git worktree prune" git worktree prune
}

main "$@"
