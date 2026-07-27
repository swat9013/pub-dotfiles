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

# Truncate string with ellipsis
truncate() {
    local str="$1" max="$2"
    if [ "${#str}" -gt "$max" ]; then
        printf '%s…' "${str:0:$((max-1))}"
    else
        printf '%s' "$str"
    fi
}

# Color for usage percentage: green (0-49), yellow (50-79), red (80+)
usage_color() {
    local pct="$1"
    if [ "$pct" -lt 50 ]; then
        printf '%s' "$GREEN"
    elif [ "$pct" -lt 80 ]; then
        printf '%s' "$YELLOW"
    else
        printf '%s' "$RED"
    fi
}

# Render braille dot bar from percentage
render_braille_bar() {
    local pct="$1"
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
    printf '%s' "$bar"
}

# Format reset time from Unix epoch
# Output: "4pm" (same day) or "Mar 6 1pm" (different day)
format_reset_time() {
    local epoch="$1"
    [ -z "$epoch" ] || [ "$epoch" = "null" ] && return

    local today_date reset_date
    today_date=$(date "+%Y-%m-%d")
    reset_date=$(date -r "$epoch" "+%Y-%m-%d" 2>/dev/null) || return

    if [ "$today_date" = "$reset_date" ]; then
        LC_ALL=C date -r "$epoch" "+%-l%p" 2>/dev/null | sed 's/AM/am/;s/PM/pm/'
    else
        LC_ALL=C date -r "$epoch" "+%b %-d %-l%p" 2>/dev/null | sed 's/AM/am/;s/PM/pm/'
    fi
}

# Format a single usage line with braille bar
# Args: label, percentage, reset_epoch
format_usage_line() {
    local label="$1" pct="$2" reset_epoch="$3"
    local color bar reset_str

    # Round to integer
    pct=$(printf '%.0f' "$pct" 2>/dev/null) || pct=0
    [[ ! "$pct" =~ ^[0-9]+$ ]] && pct=0

    color=$(usage_color "$pct")
    bar=$(render_braille_bar "$pct")
    reset_str=$(format_reset_time "$reset_epoch")

    local line="${DIM}${label}${RESET} ${color}${bar}${RESET} $(printf '%2d' "$pct")%"
    [ -n "$reset_str" ] && line="${line}  ${reset_str}"
    printf '%s' "$line"
}

# Read JSON from stdin
input=$(cat)

# Extract values from JSON
CURRENT_DIR=$(echo "$input" | jq -r '.workspace.current_dir // .cwd // "."')
MODEL=$(echo "$input" | jq -r '.model.display_name // "Claude"')

# Append version from model.id ("claude-opus-4-8" → "4.8") only when the
# display_name lacks one — recent versions already embed it ("Opus 4.8").
if ! printf '%s' "$MODEL" | grep -qE '[0-9]'; then
    MODEL_ID=$(echo "$input" | jq -r '.model.id // empty')
    MODEL_VER=$(printf '%s' "$MODEL_ID" | grep -oE '[0-9]+-[0-9]+' | head -1 | tr '-' '.' || true)
    [ -n "$MODEL_VER" ] && MODEL="${MODEL} ${MODEL_VER}"
fi

# Effort level: stdin JSON (2.1.x emits it, possibly as a {level: ...} object)
#   → CLAUDE_EFFORT env (set per-session) → settings.json persisted default
EFFORT=$(echo "$input" | jq -r '
    (.model.effort // .effort_level // .effort) as $e
    | if   $e == null              then empty
      elif ($e | type) == "object" then ($e.level // $e.name // empty)
      else  ($e | tostring) end
' 2>/dev/null) || true
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

# Get git branch, ahead/behind, and change count via a single porcelain call
GIT_BRANCH=""
GIT_AHEAD=0
GIT_BEHIND=0
GIT_CHANGES=0
if git -C "$CURRENT_DIR" rev-parse --git-dir > /dev/null 2>&1; then
    GIT_BRANCH=$(git -C "$CURRENT_DIR" --no-optional-locks branch --show-current 2>/dev/null || echo "")
    if [ -n "$GIT_BRANCH" ]; then
        GIT_STATUS=$(git -C "$CURRENT_DIR" --no-optional-locks status --porcelain=v2 --branch 2>/dev/null || echo "")
        # "# branch.ab +A -B" → ahead/behind vs upstream (absent when no upstream)
        AB_LINE=$(printf '%s\n' "$GIT_STATUS" | grep '^# branch.ab ' || true)
        if [ -n "$AB_LINE" ]; then
            GIT_AHEAD=$(printf '%s' "$AB_LINE" | awk '{print $3}' | tr -d '+')
            GIT_BEHIND=$(printf '%s' "$AB_LINE" | awk '{print $4}' | tr -d '-')
        fi
        # Entry lines start with 1/2/u/? (changed/renamed/unmerged/untracked)
        GIT_CHANGES=$(printf '%s\n' "$GIT_STATUS" | grep -c -E '^(1|2|u|\?) ' || true)
        [[ ! "$GIT_AHEAD" =~ ^[0-9]+$ ]] && GIT_AHEAD=0
        [[ ! "$GIT_BEHIND" =~ ^[0-9]+$ ]] && GIT_BEHIND=0
        [[ ! "$GIT_CHANGES" =~ ^[0-9]+$ ]] && GIT_CHANGES=0
    fi
fi

# Context usage (v2.1.6+)
PERCENT=$(echo "$input" | jq -r '.context_window.used_percentage // 0' | cut -d. -f1)
[[ ! "$PERCENT" =~ ^[0-9]+$ ]] && PERCENT=0

CTX_COLOR=$(usage_color "$PERCENT")

# Sandbox indicator: IS_SANDBOX env (outer wrapper) or first settings file in
# precedence order that has .sandbox.enabled defined.
SANDBOX=""
if [ -n "${IS_SANDBOX:-}" ]; then
    SANDBOX="sbx"
else
    for f in "$CURRENT_DIR/.claude/settings.local.json" \
             "$CURRENT_DIR/.claude/settings.json" \
             "$HOME/.claude/settings.local.json" \
             "$HOME/.claude/settings.json"; do
        [ -f "$f" ] || continue
        val=$(jq -r '.sandbox.enabled // empty' "$f" 2>/dev/null) || continue
        [ -z "$val" ] && continue
        [ "$val" = "true" ] && SANDBOX="sbx"
        break
    done
fi


# Line 1: location context (dir + git branch)
DIR_DISPLAY=$(truncate "$DIR_NAME" "$MAX_DIR")
LINE1="${GREEN}${DIR_DISPLAY}${RESET}"

if [ -n "$GIT_BRANCH" ]; then
    BRANCH_DISPLAY=$(truncate "$GIT_BRANCH" "$MAX_BRANCH")
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
CTX_BAR=$(render_braille_bar "$PERCENT")
LINE2="${DIM}cx${RESET} ${CTX_COLOR}${CTX_BAR}${RESET} $(printf '%2d' "$PERCENT")%  ${MODEL}"
[ -n "$EFFORT" ] && LINE2="${LINE2}${DIM}·${EFFORT}${RESET}"
[ -n "$SANDBOX" ] && LINE2="${LINE2} ${GREEN}${SANDBOX}${RESET}"

printf "%b\n" "$LINE1"
printf "%b\n" "$LINE2"

# Lines 3-4: Rate limits from stdin JSON (v2.1.80+)
FIVE_HOUR_PCT=$(echo "$input" | jq -r '.rate_limits.five_hour.used_percentage // empty' 2>/dev/null) || true
FIVE_HOUR_RESET=$(echo "$input" | jq -r '.rate_limits.five_hour.resets_at // empty' 2>/dev/null) || true
SEVEN_DAY_PCT=$(echo "$input" | jq -r '.rate_limits.seven_day.used_percentage // empty' 2>/dev/null) || true
SEVEN_DAY_RESET=$(echo "$input" | jq -r '.rate_limits.seven_day.resets_at // empty' 2>/dev/null) || true

if [ -n "$FIVE_HOUR_PCT" ]; then
    LINE3=$(format_usage_line "5h" "$FIVE_HOUR_PCT" "$FIVE_HOUR_RESET")
    printf "%b\n" "$LINE3"
fi
if [ -n "$SEVEN_DAY_PCT" ]; then
    LINE4=$(format_usage_line "7d" "$SEVEN_DAY_PCT" "$SEVEN_DAY_RESET")
    printf "%b\n" "$LINE4"
fi
