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
MAX_AGE_DAYS=14
TARGET_BRANCH=""
declare -A WT_MAP=()
DETACHED_WTS=()
# 他 process が cwd にしている path (lsof の観測。1 行 1 path)
PROCESS_CWDS=""
readonly PROTECTED_RE='^(develop|master|main|pre-release|release|development|staging|production)$'

usage() {
  cat <<'EOF'
usage: git tidy [<branch>] [--force] [--dry-run] [--no-pull] [--max-age <days>]

  <branch>          checkout & pull 対象 (省略時: origin/HEAD → main → master)
  --force           dirty / 作りかけの worktree も強制削除 (worktree remove --force + branch -D)
  --dry-run         実行対象を stdout に列挙のみ (削除しない)
  --no-pull         pull を skip (現在 branch 上で cleanup のみ)
  --max-age <days>  作りかけ (commit 0) の branch を守る日数 (既定: 14)

  掃除対象は 2 種: (1) <branch> に merge 済みの branch とその worktree
  (2) branch を持たない detached HEAD の linked worktree (clean なもの。
      commit は repo に残るため作業は失われない。dirty は --force のみ)

  merge 済みでも残すもの (skip):
  - 他 process が cwd にしている worktree (--force でも消さない。process を閉じてから)
  - 作成から commit を 1 つも積んでいない branch のうち --max-age 日未満のもの
    (作成直後の branch は merge 済みと区別が付かない。着手中の worker を踏まない)
  - dirty な worktree (--force のみ)
EOF
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -h|--help)   usage; exit 0 ;;
      --force)     FORCE=1; shift ;;
      --dry-run)   DRY_RUN=1; shift ;;
      --no-pull)   NO_PULL=1; shift ;;
      --max-age)
        if [[ $# -lt 2 || ! "$2" =~ ^[0-9]+$ ]]; then
          echo "error: --max-age requires a non-negative integer (days)" >&2; exit 2
        fi
        MAX_AGE_DAYS="$2"; shift 2
        ;;
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

collect_process_cwds() {
  # 他 process の cwd を 1 度だけ観測する。worktree の中に居る process (editor / agent /
  # shell) の足元を消すと、その process には「消えた」としか見えない
  if ! command -v lsof >/dev/null 2>&1; then
    echo "warn: lsof not found; cannot tell whether a worktree is in use by another process" >&2
    return
  fi
  PROCESS_CWDS="$(lsof -d cwd -Fn 2>/dev/null | sed -n 's/^n//p' || true)"
}

in_use_by_process() {
  # $1 = worktree path。その path (配下を含む) を cwd にしている process が居れば 0
  local wt="$1" real p
  [[ -z "$PROCESS_CWDS" ]] && return 1
  real="$(cd "$wt" 2>/dev/null && pwd -P)" || real="$wt"
  while IFS= read -r p; do
    [[ -z "$p" ]] && continue
    if [[ "$p" == "$wt" || "$p" == "$wt/"* || "$p" == "$real" || "$p" == "$real/"* ]]; then
      return 0
    fi
  done <<<"$PROCESS_CWDS"
  return 1
}

untouched_since_created() {
  # $1 = branch。作成時点の SHA から動いていない (commit 0) なら 0。
  # `--merged` は「main の祖先」しか見ないので、作成直後の branch も merge 済みも同じに載る。
  # reflog の最古 entry (branch: Created from …) が作成時点
  local br="$1" created tip
  created="$(git reflog show --format='%H' "refs/heads/$br" 2>/dev/null | tail -n 1)"
  [[ -z "$created" ]] && return 1
  tip="$(git rev-parse --verify --quiet "refs/heads/$br")" || return 1
  [[ "$created" == "$tip" ]]
}

branch_age_days() {
  # $1 = branch。reflog の最古 entry からの経過日数 (reflog が無ければ空)。
  # entry 自身の時刻は %gd (ref@{<unix>}) にしか出ない (%ct は commit の時刻で、作成時点の
  # commit は main 側で古いことがある)
  local br="$1" created_at
  created_at="$(git reflog show --date=unix --format='%gd' "refs/heads/$br" 2>/dev/null \
    | tail -n 1 | sed -n 's/.*@{\([0-9]*\)}$/\1/p')"
  [[ -z "$created_at" ]] && return 0
  echo $(( ( $(date +%s) - created_at ) / 86400 ))
}

fresh_untouched() {
  # $1 = branch。commit 0 かつ --max-age 日未満なら 0 (= 着手中の可能性があるので守る)
  local br="$1" age
  untouched_since_created "$br" || return 1
  age="$(branch_age_days "$br")"
  [[ -n "$age" && "$age" -lt "$MAX_AGE_DAYS" ]]
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
  local skipped_dirty=0 skipped_fresh=0 skipped_in_use=0
  while IFS= read -r br; do
    [[ -z "$br" ]] && continue
    local wt="${WT_MAP[$br]:-}"
    if [[ -n "$wt" ]] && in_use_by_process "$wt"; then
      echo "skip: $br @ $wt is the cwd of another process (close it first; --force does not override)" >&2
      ((skipped++)) || true; ((skipped_in_use++)) || true
      continue
    fi
    if [[ $FORCE -eq 0 ]] && fresh_untouched "$br"; then
      echo "skip: $br has no commits since creation ($(branch_age_days "$br")d < ${MAX_AGE_DAYS}d, may be in progress; use --force or --max-age to override)" >&2
      ((skipped++)) || true; ((skipped_fresh++)) || true
      continue
    fi
    if [[ -n "$wt" ]]; then
      local dirty=0
      if [[ -n "$(git -C "$wt" status --porcelain 2>/dev/null)" ]]; then
        dirty=1
      fi
      if [[ $dirty -eq 1 && $FORCE -eq 0 ]]; then
        echo "skip: $br @ $wt is dirty (use --force to override)" >&2
        ((skipped++)) || true; ((skipped_dirty++)) || true
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
  local summary="summary: removed $removed_branches branches, $removed_worktrees worktrees, skipped $skipped (dirty $skipped_dirty, fresh $skipped_fresh, in-use $skipped_in_use)"
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
  local skipped_dirty=0 skipped_in_use=0
  local wt
  for wt in ${DETACHED_WTS[@]+"${DETACHED_WTS[@]}"}; do
    if in_use_by_process "$wt"; then
      echo "skip: detached worktree $wt is the cwd of another process (close it first; --force does not override)" >&2
      ((skipped++)) || true; ((skipped_in_use++)) || true
      continue
    fi
    local dirty=0
    if [[ -n "$(git -C "$wt" status --porcelain 2>/dev/null)" ]]; then
      dirty=1
    fi
    if [[ $dirty -eq 1 && $FORCE -eq 0 ]]; then
      echo "skip: detached worktree $wt is dirty (use --force to override)" >&2
      ((skipped++)) || true; ((skipped_dirty++)) || true
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
    local summary="summary(detached): removed $removed worktrees, skipped $skipped (dirty $skipped_dirty, in-use $skipped_in_use)"
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
  collect_process_cwds
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
