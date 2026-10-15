#!/bin/bash
#==============================================================================
# claude-statusline.sh - Claude Code Statusline Script
#==============================================================================
# Four-line layout:
#   Line 1: dir git:branch ↑1↓2 ●3                   (location context)
#   Line 2: cx ⣿⣿⣤     030%  Model 4.8·effort sbx   (session state)
#   Line 3: 5h ⣿⣿⣿⣿⣿⣀   050%  Reset 4pm            (5-hour usage)
#   Line 4: 7d ⣿⣿⣿⣿⣿⣿⣷  080%  Reset Mar 6 1pm      (7-day usage)
#
# sbx badge (Line 2): shown in green when the session runs in a sandbox.
# Sources checked in precedence order:
#   1. IS_SANDBOX env (outer wrapper such as bubblewrap)
#   2. .sandbox.enabled in project settings.local.json → project settings.json
#      → user settings.local.json → user settings.json
# (Matches claude v2.1's isSandboxEnabledInSettings, which reads
#  settings.sandbox.enabled; stdin JSON exposes no sandbox field.)
#
# Lines 3-4 appear only when rate_limits data is available in stdin JSON.
#
# Braille dots (density 8 levels): ' ⣀⣄⣤⣦⣶⣷⣿'
#
# Color scheme:
#   - Directory: Green
#   - Git branch: Yellow
#   - Context/Usage %: Green (0-49), Yellow (50-79), Red (80+)
#   - Git change count (●N): Yellow
#   - Git ahead/behind (↑↓) & effort level: Dim
#   - Session title: Cyan
#
# Process budget: Claude Code re-renders the statusline on every conversation
# update, in every running session, so each external command or $(...) fork
# is paid many times per second (and tracked one by one by endpoint
# monitoring). Keep stdin parsing to one jq call and git to one call, and have
# helpers assign through printf -v instead of being captured by $(...).
#==============================================================================

set -euo pipefail

# ANSI color codes
GREEN='\033[32m'
YELLOW='\033[33m'
RED='\033[31m'
CYAN='\033[36m'
DIM='\033[2m'
RESET='\033[0m'

# Braille dots characters (density: empty → full)
BRAILLE=(' ' '⣀' '⣄' '⣤' '⣦' '⣶' '⣷' '⣿')

# Max lengths for dir/branch (fixed caps to keep lines short)
MAX_DIR=20
MAX_BRANCH=20

# Check jq dependency
if ! command -v jq &> /dev/null; then
    echo "[Claude]"
    exit 0
fi

# Truncate string with ellipsis into the variable named by $1
truncate_to() {
    local out="$1" str="$2" max="$3"
    if [ "${#str}" -gt "$max" ]; then
        printf -v "$out" '%s…' "${str:0:$((max-1))}"
    else
        printf -v "$out" '%s' "$str"
    fi
}

# Color for usage percentage: green (0-49), yellow (50-79), red (80+)
usage_color() {
    local out="$1" pct="$2"
    if [ "$pct" -lt 50 ]; then
        printf -v "$out" '%s' "$GREEN"
    elif [ "$pct" -lt 80 ]; then
        printf -v "$out" '%s' "$YELLOW"
    else
        printf -v "$out" '%s' "$RED"
    fi
}

# Render braille dot bar from percentage
render_braille_bar() {
    local out="$1" pct="$2"
    local width=8
    pct=$(( pct > 100 ? 100 : pct ))
    pct=$(( pct < 0 ? 0 : pct ))
    local bar=""
    for ((i=0; i<width; i++)); do
        local seg_start=$(( i * 100 / width ))
        local seg_end=$(( (i + 1) * 100 / width ))
        if [ "$pct" -ge "$seg_end" ]; then
            bar+="${BRAILLE[7]}"
        elif [ "$pct" -le "$seg_start" ]; then
            bar+="${BRAILLE[0]}"
        else
            local frac=$(( (pct - seg_start) * 7 / (seg_end - seg_start) ))
            [ "$frac" -gt 7 ] && frac=7
            bar+="${BRAILLE[$frac]}"
        fi
    done
    printf -v "$out" '%s' "$bar"
}

# Format reset time from Unix epoch
# Output: "4pm" (same day) or "Mar 6 1pm" (different day)
TODAY=""
format_reset_time() {
    local out="$1" epoch="$2"
    printf -v "$out" '%s' ""
    [ -z "$epoch" ] || [ "$epoch" = "null" ] && return

    # One date call yields every field; today's date is fetched once per run
    local fields reset_date hour mon day
    fields=$(LC_ALL=C date -r "$epoch" "+%Y-%m-%d %-l%p %b %-d" 2>/dev/null) || return 0
    read -r reset_date hour mon day <<< "$fields"
    hour="${hour/AM/am}"
    hour="${hour/PM/pm}"
    [ -z "$TODAY" ] && TODAY=$(date "+%Y-%m-%d")

    if [ "$TODAY" = "$reset_date" ]; then
        printf -v "$out" '%s' "$hour"
    else
        printf -v "$out" '%s %s %s' "$mon" "$day" "$hour"
    fi
}

# Format a single usage line with braille bar
# Args: output variable, label, percentage, reset_epoch
format_usage_line() {
    local out="$1" label="$2" pct="$3" reset_epoch="$4"
    # Distinct names: bash locals are dynamically scoped, so a helper's own
    # `local bar` would shadow a caller variable named `bar` and swallow the
    # printf -v assignment.
    local ul_color ul_bar ul_reset ul_pct

    # Round to integer
    printf -v pct '%.0f' "$pct" 2>/dev/null || pct=0
    [[ ! "$pct" =~ ^[0-9]+$ ]] && pct=0

    usage_color ul_color "$pct"
    render_braille_bar ul_bar "$pct"
    format_reset_time ul_reset "$reset_epoch"
    printf -v ul_pct '%2d' "$pct"

    local line="${DIM}${label}${RESET} ${ul_color}${ul_bar}${RESET} ${ul_pct}%"
    [ -n "$ul_reset" ] && line="${line}  ${ul_reset}"
    printf -v "$out" '%s' "$line"
}

# Read JSON from stdin
input=$(cat)

# Extract every stdin value in one jq call, joined by the ASCII unit separator
# (a non-whitespace IFS keeps empty fields in place).
# Effort level: stdin JSON (2.1.x emits it, possibly as a {level: ...} object)
#   → CLAUDE_EFFORT env (set per-session) → settings.json persisted default
FIELDS=$(printf '%s' "$input" | jq -r '
    [ (.workspace.current_dir // .cwd // "."),
      (.model.display_name // "Claude"),
      (.model.id // ""),
      ((.model.effort // .effort_level // .effort) as $e
        | if   $e == null              then ""
          elif ($e | type) == "object" then ($e.level // $e.name // "")
          else  $e end),
      (.context_window.used_percentage // 0),
      (.rate_limits.five_hour.used_percentage // ""),
      (.rate_limits.five_hour.resets_at // ""),
      (.rate_limits.seven_day.used_percentage // ""),
      (.rate_limits.seven_day.resets_at // "")
    ] | map(tostring) | join("\u001f")')
IFS=$'\x1f' read -r CURRENT_DIR MODEL MODEL_ID EFFORT PERCENT \
    FIVE_HOUR_PCT FIVE_HOUR_RESET SEVEN_DAY_PCT SEVEN_DAY_RESET <<< "$FIELDS" || true

# Append version from model.id ("claude-opus-4-8" → "4.8") only when the
# display_name lacks one — recent versions already embed it ("Opus 4.8").
if [[ ! "$MODEL" =~ [0-9] ]] && [[ "$MODEL_ID" =~ ([0-9]+)-([0-9]+) ]]; then
    MODEL="${MODEL} ${BASH_REMATCH[1]}.${BASH_REMATCH[2]}"
fi

[ -z "$EFFORT" ] && EFFORT="${CLAUDE_EFFORT:-}"
if [ -z "$EFFORT" ] && [ -f "$HOME/.claude/settings.json" ]; then
    EFFORT=$(jq -r '.effortLevel // empty' "$HOME/.claude/settings.json" 2>/dev/null) || true
fi


# Shorten directory name
if [ "$CURRENT_DIR" = "$HOME" ]; then
    DIR_NAME="~"
elif [ "$CURRENT_DIR" = "/" ]; then
    DIR_NAME="/"
else
    DIR_NAME="${CURRENT_DIR##*/}"
fi

# Get git branch, ahead/behind, and change count via a single porcelain call.
# It fails outside a repository; a detached HEAD shows no git segment.
GIT_BRANCH=""
GIT_AHEAD=0
GIT_BEHIND=0
GIT_CHANGES=0
GIT_STATUS=$(git -C "$CURRENT_DIR" --no-optional-locks status --porcelain=v2 --branch 2>/dev/null) || GIT_STATUS=""
while IFS= read -r line; do
    case "$line" in
        '# branch.head '*)
            GIT_BRANCH="${line#\# branch.head }"
            [ "$GIT_BRANCH" = "(detached)" ] && GIT_BRANCH=""
            ;;
        # "# branch.ab +A -B" → ahead/behind vs upstream (absent when no upstream)
        '# branch.ab '*)
            read -r _ _ GIT_AHEAD GIT_BEHIND <<< "$line"
            GIT_AHEAD="${GIT_AHEAD#+}"
            GIT_BEHIND="${GIT_BEHIND#-}"
            ;;
        # Entry lines start with 1/2/u/? (changed/renamed/unmerged/untracked)
        '1 '*|'2 '*|'u '*|'? '*)
            GIT_CHANGES=$((GIT_CHANGES + 1))
            ;;
    esac
done <<< "$GIT_STATUS"
[[ ! "$GIT_AHEAD" =~ ^[0-9]+$ ]] && GIT_AHEAD=0
[[ ! "$GIT_BEHIND" =~ ^[0-9]+$ ]] && GIT_BEHIND=0

# Context usage (v2.1.6+)
PERCENT="${PERCENT%%.*}"
[[ ! "$PERCENT" =~ ^[0-9]+$ ]] && PERCENT=0

usage_color CTX_COLOR "$PERCENT"

# Sandbox indicator: IS_SANDBOX env (outer wrapper) or the first settings file,
# in precedence order, whose .sandbox.enabled is set (false counts as unset).
SANDBOX=""
if [ -n "${IS_SANDBOX:-}" ]; then
    SANDBOX="sbx"
else
    SETTINGS_FILES=()
    for f in "$CURRENT_DIR/.claude/settings.local.json" \
             "$CURRENT_DIR/.claude/settings.json" \
             "$HOME/.claude/settings.local.json" \
             "$HOME/.claude/settings.json"; do
        [ -f "$f" ] && SETTINGS_FILES+=("$f")
    done
    if [ "${#SETTINGS_FILES[@]}" -gt 0 ]; then
        val=$(jq -rn 'first(inputs | .sandbox.enabled // empty)' "${SETTINGS_FILES[@]}" 2>/dev/null) || val=""
        [ "$val" = "true" ] && SANDBOX="sbx"
    fi
fi


# Line 1: location context (dir + git branch)
truncate_to DIR_DISPLAY "$DIR_NAME" "$MAX_DIR"
LINE1="${GREEN}${DIR_DISPLAY}${RESET}"

if [ -n "$GIT_BRANCH" ]; then
    truncate_to BRANCH_DISPLAY "$GIT_BRANCH" "$MAX_BRANCH"
    LINE1="${LINE1} ${YELLOW}git:${BRANCH_DISPLAY}${RESET}"
    # ahead/behind vs upstream (omit zeros; whole group hidden when in sync)
    AB=""
    [ "$GIT_AHEAD" -gt 0 ] && AB="${AB}↑${GIT_AHEAD}"
    [ "$GIT_BEHIND" -gt 0 ] && AB="${AB}↓${GIT_BEHIND}"
    [ -n "$AB" ] && LINE1="${LINE1} ${DIM}${AB}${RESET}"
    # change count (staged + unstaged + untracked); hidden when clean
    [ "$GIT_CHANGES" -gt 0 ] && LINE1="${LINE1} ${YELLOW}●${GIT_CHANGES}${RESET}"
fi

# Line 2: session state (ctx braille bar + model·effort)
render_braille_bar CTX_BAR "$PERCENT"
printf -v PERCENT_STR '%2d' "$PERCENT"
LINE2="${DIM}cx${RESET} ${CTX_COLOR}${CTX_BAR}${RESET} ${PERCENT_STR}%  ${MODEL}"
[ -n "$EFFORT" ] && LINE2="${LINE2}${DIM}·${EFFORT}${RESET}"
[ -n "$SANDBOX" ] && LINE2="${LINE2} ${GREEN}${SANDBOX}${RESET}"

printf "%b\n" "$LINE1"
printf "%b\n" "$LINE2"

# Lines 3-4: Rate limits from stdin JSON (v2.1.80+)
if [ -n "$FIVE_HOUR_PCT" ]; then
    format_usage_line LINE3 "5h" "$FIVE_HOUR_PCT" "$FIVE_HOUR_RESET"
    printf "%b\n" "$LINE3"
fi
if [ -n "$SEVEN_DAY_PCT" ]; then
    format_usage_line LINE4 "7d" "$SEVEN_DAY_PCT" "$SEVEN_DAY_RESET"
    printf "%b\n" "$LINE4"
fi
