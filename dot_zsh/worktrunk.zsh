# Worktrunk workflow helpers
# /wt スキルをターミナルから1コマンドで起動する

function wt-init() {
    claude --model sonnet "/wt init"
}

function wt-switch() {
    if [[ $# -eq 0 ]]; then
        echo "Usage: wt-switch <task-description>" >&2
        return 1
    fi

    local branches convention prompt raw branch_name

    branches=$(git branch --format='%(refname:short)' 2>/dev/null | tail -10 | paste -sd, -)

    if [[ -f CLAUDE.md ]]; then
        convention=$(grep -i -A2 'branch' CLAUDE.md 2>/dev/null | head -5)
    fi

    prompt="Output ONLY a git branch name. No explanation, no quotes, no backticks.
Rules: kebab-case, max 30 chars, English, lowercase.
${convention:+Project convention: ${convention}
}Existing branches for style reference: ${branches}
Task: $*"

    raw=$(claude -p --tools "" --output-format json --model haiku "$prompt" 2>/dev/null)
    branch_name=$(printf '%s' "$raw" | python3 -c "import sys, json; data = json.load(sys.stdin); print(data[-1].get('result', ''))" 2>/dev/null | tr -d '`"'\'' \n')

    if [[ -z "$branch_name" || "$branch_name" == "null" ]]; then
        echo "Failed to generate branch name" >&2
        return 1
    fi

    wt switch --create -y "$branch_name"
}

function wt-home() {
    wt switch '^'
}
