#!/bin/bash
#==============================================================================
# agy-statusline.sh - Antigravity CLI Statusline Script
#==============================================================================
# Layout:
#   Line 1: dir git:branch ↑1↓2 ●3                    (location context)
#   Line 2: cx ⣿⣿⣤     030%  Gemini 4 Argon·low sbx  (session state)
#   Line 3+: <label> ⣿⣿⣿⣿⣿⣀  058%  Nov 22 7am        (each active .quota bucket)
#
# Bucket labels (4 chars, padded):
#   - gemini-argon-wtu-weekly → ag7d
#   - gemini-5h               → gm5h
#   - gemini-weekly / 7d      → gm7d
#   - 3p-5h / claude-5h       → 3p5h
#   - 3p-weekly / claude-7d   → 3p7d
#
# Process budget: Antigravity re-renders the statusline on state changes.
# Keep stdin parsing to one jq call and git to one call, and have helpers
# assign through printf -v instead of being captured by $(...).
#==============================================================================

set -euo pipefail

# ANSI color codes
GREEN='\033[32m'
YELLOW='\033[33m'
RED='\033[31m'
DIM='\033[2m'
RESET='\033[0m'

# Braille dots characters (density: empty → full)
BRAILLE=(' ' '⣀' '⣄' '⣤' '⣦' '⣶' '⣷' '⣿')

# Max lengths for dir/branch (fixed caps to keep lines short)
MAX_DIR=20
MAX_BRANCH=20

# Check jq dependency
if ! command -v jq &> /dev/null; then
    echo "[Antigravity]"
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
    local ul_color ul_bar ul_reset ul_pct ul_lbl

    # Round to integer
    printf -v pct '%.0f' "$pct" 2>/dev/null || pct=0
    [[ ! "$pct" =~ ^[0-9]+$ ]] && pct=0

    usage_color ul_color "$pct"
    render_braille_bar ul_bar "$pct"
    format_reset_time ul_reset "$reset_epoch"
    printf -v ul_pct '%2d' "$pct"
    printf -v ul_lbl '%-4s' "$label"

    local line="${DIM}${ul_lbl}${RESET} ${ul_color}${ul_bar}${RESET} ${ul_pct}%"
    [ -n "$ul_reset" ] && line="${line}  ${ul_reset}"
    printf -v "$out" '%s' "$line"
}

# Read JSON from stdin
input=$(cat)

# Extract header line and one line per active quota bucket in a single jq call.
PARSED=$(printf '%s' "$input" | jq -r '
    def qreset($b):
      if ($b.reset_time // "") != "" then ($b.reset_time | sub("\\.[0-9]+Z$"; "Z") | fromdateiso8601? // "")
      elif ($b.reset_in_seconds // null) != null then (now + $b.reset_in_seconds | floor)
      else "" end;
    def qlabel($k):
      if ($k | test("argon"; "i")) then
        (if ($k | test("5h"; "i")) then "ag5h" else "ag7d" end)
      elif ($k | test("gemini"; "i")) then
        (if ($k | test("5h"; "i")) then "gm5h"
         elif ($k | test("weekly|7d"; "i")) then "gm7d"
         else $k[0:4] end)
      elif ($k | test("3p|claude|gpt"; "i")) then
        (if ($k | test("5h"; "i")) then "3p5h"
         elif ($k | test("weekly|7d"; "i")) then "3p7d"
         else $k[0:4] end)
      else $k[0:4] end;
    def qorder($k):
      if ($k | test("argon"; "i")) then
        (if ($k | test("5h"; "i")) then 1 else 2 end)
      elif ($k | test("gemini"; "i")) then
        (if ($k | test("5h"; "i")) then 3 else 4 end)
      elif ($k | test("3p|claude|gpt"; "i")) then
        (if ($k | test("5h"; "i")) then 5 else 6 end)
      else 9 end;
    ([ (.cwd // .workspace.current_dir // "."),
       (.model.display_name // .model.name // "Antigravity"),
       (.model.id // ""),
       ((.model.effort // .effort_level // .effort) as $e
         | if   $e == null              then ""
           elif ($e | type) == "object" then ($e.level // $e.name // "")
           else  $e end),
       (.context_window.used_percentage // 0),
       (if .sandbox.enabled == true then "sbx" else "" end),
       (.vcs.branch // ""),
       (if .vcs.dirty == true then "1" else "0" end)
     ] | map(tostring) | join("\u001f")),
    ((.quota // {}) | to_entries
      | map(select((.value.disabled // false | not) and (.value.remaining_fraction != null)))
      | sort_by(qorder(.key), .key)
      | .[]
      | [ qlabel(.key),
          ((1 - .value.remaining_fraction) * 100),
          qreset(.value)
        ] | map(tostring) | join("\u001f"))
')

{
    IFS=$'\x1f' read -r CURRENT_DIR MODEL MODEL_ID EFFORT PERCENT \
        STDIN_SANDBOX VCS_BRANCH VCS_DIRTY || true
    QUOTA_LINES=()
    while IFS= read -r qline; do
        [ -n "$qline" ] && QUOTA_LINES+=("$qline")
    done
} <<< "$PARSED"

# Strip trailing " (Low)" / " (Medium)" / ... from Antigravity display_name
# when effort is already present so Line 2 renders "Model·effort" cleanly.
if [[ "$MODEL" =~ ^(.*)\ \(([A-Za-z]+)\)$ ]]; then
    MODEL="${BASH_REMATCH[1]}"
    if [ -z "$EFFORT" ]; then
        case "${BASH_REMATCH[2]}" in
            Low|low)       EFFORT="low" ;;
            Medium|medium) EFFORT="medium" ;;
            High|high)     EFFORT="high" ;;
            XHigh|xhigh)   EFFORT="xhigh" ;;
            Max|max)       EFFORT="max" ;;
        esac
    fi
fi

# Append version from model.id ("claude-opus-5-5" → "5.5") only when the
# display_name lacks one.
if [[ ! "$MODEL" =~ [0-9] ]] && [[ "$MODEL_ID" =~ ([0-9]+)-([0-9]+) ]]; then
    MODEL="${MODEL} ${BASH_REMATCH[1]}.${BASH_REMATCH[2]}"
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
# Fall back to .vcs.{branch,dirty} from stdin JSON when git status yields no branch.
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
        '# branch.ab '*)
            read -r _ _ GIT_AHEAD GIT_BEHIND <<< "$line"
            GIT_AHEAD="${GIT_AHEAD#+}"
            GIT_BEHIND="${GIT_BEHIND#-}"
            ;;
        '1 '*|'2 '*|'u '*|'? '*)
            GIT_CHANGES=$((GIT_CHANGES + 1))
            ;;
    esac
done <<< "$GIT_STATUS"
if [ -z "$GIT_BRANCH" ] && [ -n "$VCS_BRANCH" ]; then
    GIT_BRANCH="$VCS_BRANCH"
    [ "$VCS_DIRTY" = "1" ] && GIT_CHANGES=1
fi
[[ ! "$GIT_AHEAD" =~ ^[0-9]+$ ]] && GIT_AHEAD=0
[[ ! "$GIT_BEHIND" =~ ^[0-9]+$ ]] && GIT_BEHIND=0

# Context usage
PERCENT="${PERCENT%%.*}"
[[ ! "$PERCENT" =~ ^[0-9]+$ ]] && PERCENT=0

usage_color CTX_COLOR "$PERCENT"

SANDBOX=""
if [ -n "$STDIN_SANDBOX" ] || [ -n "${IS_SANDBOX:-}" ]; then
    SANDBOX="sbx"
fi

# Line 1: location context (dir + git branch)
truncate_to DIR_DISPLAY "$DIR_NAME" "$MAX_DIR"
LINE1="${GREEN}${DIR_DISPLAY}${RESET}"

if [ -n "$GIT_BRANCH" ]; then
    truncate_to BRANCH_DISPLAY "$GIT_BRANCH" "$MAX_BRANCH"
    LINE1="${LINE1} ${YELLOW}git:${BRANCH_DISPLAY}${RESET}"
    AB=""
    [ "$GIT_AHEAD" -gt 0 ] && AB="${AB}↑${GIT_AHEAD}"
    [ "$GIT_BEHIND" -gt 0 ] && AB="${AB}↓${GIT_BEHIND}"
    [ -n "$AB" ] && LINE1="${LINE1} ${DIM}${AB}${RESET}"
    [ "$GIT_CHANGES" -gt 0 ] && LINE1="${LINE1} ${YELLOW}●${GIT_CHANGES}${RESET}"
fi

# Line 2: session state (ctx braille bar + model·effort)
render_braille_bar CTX_BAR "$PERCENT"
printf -v PERCENT_STR '%2d' "$PERCENT"
LINE2="${DIM}cx  ${RESET} ${CTX_COLOR}${CTX_BAR}${RESET} ${PERCENT_STR}%  ${MODEL}"
[ -n "$EFFORT" ] && LINE2="${LINE2}${DIM}·${EFFORT}${RESET}"
[ -n "$SANDBOX" ] && LINE2="${LINE2} ${GREEN}${SANDBOX}${RESET}"

printf "%b\n" "$LINE1"
printf "%b\n" "$LINE2"

# Line 3+: All active quota buckets from stdin JSON
for qline in "${QUOTA_LINES[@]+"${QUOTA_LINES[@]}"}"; do
    IFS=$'\x1f' read -r q_label q_pct q_reset <<< "$qline"
    format_usage_line QLINE "$q_label" "$q_pct" "$q_reset"
    printf "%b\n" "$QLINE"
done
