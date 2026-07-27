# Claude Code session management

# List running Claude Code sessions
# Usage: ccl [options]
#   -a, --all    Show all processes including subagents
#   -v, --verbose Show detailed info
function ccl() {
  local show_all=false
  local verbose=false

  while [[ $# -gt 0 ]]; do
    case "$1" in
      -a|--all) show_all=true; shift ;;
      -v|--verbose) verbose=true; shift ;;
      *) shift ;;
    esac
  done

  local pids=($(pgrep '^claude$' 2>/dev/null))

  if [[ ${#pids[@]} -eq 0 ]]; then
    echo "No Claude Code sessions running"
    return 0
  fi

  # Header
  if $verbose; then
    printf "%-7s %-4s %-40s %-20s %s\n" "PID" "TYPE" "DIRECTORY" "STARTED" "ARGS"
    printf "%s\n" "$(printf '%.0s-' {1..100})"
  else
    printf "%-7s %-4s %-40s %s\n" "PID" "TYPE" "DIRECTORY" "STARTED"
    printf "%s\n" "$(printf '%.0s-' {1..80})"
  fi

  local sub_count=0
  local sub_rss=0

  for pid in "${pids[@]}"; do
    local args=$(ps -p $pid -o args= 2>/dev/null)
    [[ -z "$args" ]] && continue

    # Determine type: main session or subagent
    local type="main"
    if [[ "$args" == *"stream-json"* ]]; then
      type="sub"
      local rss=$(ps -p $pid -o rss= 2>/dev/null)
      sub_count=$((sub_count + 1))
      sub_rss=$((sub_rss + ${rss:-0}))
      $show_all || continue
    fi

    # Get working directory (-a for AND condition on macOS)
    local cwd=$(lsof -a -d cwd -p $pid 2>/dev/null | awk 'NR==2 {print $NF}')
    cwd=${cwd/#$HOME/\~}

    # Get start time
    local started=$(ps -p $pid -o lstart= 2>/dev/null | awk '{print $2, $3, $4}')

    # Format output
    if $verbose; then
      local short_args=${args:0:30}
      [[ ${#args} -gt 30 ]] && short_args="${short_args}..."
      printf "%-7s %-4s %-40s %-20s %s\n" "$pid" "$type" "$cwd" "$started" "$short_args"
    else
      printf "%-7s %-4s %-40s %s\n" "$pid" "$type" "$cwd" "$started"
    fi
  done

  # Always show subagent summary when subagents exist
  if [[ $sub_count -gt 0 ]]; then
    local rss_mb=$((sub_rss / 1024))
    echo ""
    echo "Subagents: $sub_count (RSS: ${rss_mb} MB) — use 'cck' to clean up"
  fi
}

# Launch Claude Code with Fable model
function ccf() {
  claude --model claude-fable-5  --effort high --append-system-prompt "基本的にタスクや作業の実行は、適切な粒度でsubagentsに実行手順が明確な指示を与えて委譲すること。あなたは全体進行の俯瞰と立案を行う。自己判断による例外は認める" "$@"
}

# Kill all running subagents
function cck() {
  local pids=($(pgrep '^claude$' 2>/dev/null))
  local count=0
  for pid in "${pids[@]}"; do
    local args=$(ps -p $pid -o args= 2>/dev/null)
    if [[ "$args" == *"stream-json"* ]]; then
      kill -9 $pid 2>/dev/null && ((count++))
    fi
  done
  echo "Killed $count subagent(s)"
}
