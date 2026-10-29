#!/usr/bin/env bash
# Claude Code status line
# Displays: model | modes | ctx% | 5h% | 7d% | 7d-opus% | cost | dir | git-origin | git-branch | git-dirty

export GIT_OPTIONAL_LOCKS=0

input=$(cat)

cwd=$(echo "$input"      | jq -r '.workspace.current_dir // .cwd // ""')
used_pct=$(echo "$input" | jq -r '.context_window.used_percentage // empty')
model=$(echo "$input"    | jq -r '(.model.display_name // .model // "") | select(. != "")')
cost=$(echo "$input"     | jq -r '.cost.total_cost_usd // empty')

# Which session this is. Both are in the payload: session_name is the friendly one
# (the agent's name, e.g. "homelab-server"), session_id the UUID that names the
# transcript on disk. The name is what you recognise; the id is what you need when
# two sessions share a name, or when digging a transcript out of
# ~/.claude-w/projects/. So the name is shown when there is one and the id's first
# block is appended to tell same-named sessions apart.
session_name=$(echo "$input" | jq -r '.session_name // empty')
session_id=$(echo "$input"   | jq -r '.session_id // empty')

# Which account this session is signed in as. NOT in the status-line payload --
# that carries the model, workspace, cost and rate limits, and says nothing about
# who is logged in. The logged-in identity lives in ~/.claude.json, so it is read
# from there rather than from stdin. Worth showing because the account signed into
# Claude and the account the work belongs to are not always the same one.
email=$(jq -r '.oauthAccount.emailAddress // empty' "$CLAUDE_CONFIG_DIR/.claude.json" 2>/dev/null)

# Rate limits, as Claude Code reports them.
#
# The buckets this build has are five_hour and seven_day, the weekly one split
# per model (seven_day_opus, seven_day_sonnet). There is NO monthly bucket -- the
# "monthly" in the CLI belongs to enterprise spend limits, which are dollars set
# by an admin rather than usage against a subscription. So two windows are shown,
# three when the Opus weekly cap is being tracked.
#
# There is no monthly window. The "monthly" figure elsewhere in Claude is the
# extra-usage credit SPEND limit -- dollars beyond the subscription, reported only
# by GET /api/oauth/usage and null while credits are off. Nothing is invented to
# fill a gap that is not there.
five_pct=$(echo "$input"   | jq -r '.rate_limits.five_hour.used_percentage // empty')
five_reset=$(echo "$input" | jq -r '.rate_limits.five_hour.resets_at // empty')
week_pct=$(echo "$input"   | jq -r '.rate_limits.seven_day.used_percentage // empty')
week_reset=$(echo "$input" | jq -r '.rate_limits.seven_day.resets_at // empty')
opus_pct=$(echo "$input"   | jq -r '.rate_limits.seven_day_opus.used_percentage // empty')
opus_reset=$(echo "$input" | jq -r '.rate_limits.seven_day_opus.resets_at // empty')

# -- Colours (bright/bold, vivid) --
RESET='\033[0m'
BOLD='\033[1m'
CYAN='\033[1;96m'
GREEN='\033[1;92m'
YELLOW='\033[1;93m'
RED='\033[1;91m'
MAGENTA='\033[1;95m'
PURPLE='\033[0;95m'
BLUE='\033[1;94m'
WHITE='\033[1;97m'

# --------------------------------------------------------------------------
# 1. Model name
# --------------------------------------------------------------------------
model_part=""
if [[ -n "$model" ]]; then
    model_part=$(printf "${WHITE}${model}${RESET}")
fi

# --------------------------------------------------------------------------
# 2. Active modes (only shown when enabled)
# --------------------------------------------------------------------------
# CLAUDE_CODE_FAST_MODE is set to "true" when /fast is active.
mode_part=""
if [[ "${CLAUDE_CODE_FAST_MODE:-}" == "true" ]]; then
    mode_part=$(printf "${MAGENTA}FAST${RESET}")
fi

# --------------------------------------------------------------------------
# 3. Context percentage used (colour-coded)
# --------------------------------------------------------------------------
ctx_part=""
if [[ -n "$used_pct" ]]; then
    pct_int=${used_pct%.*}
    if   (( pct_int >= 80 )); then ctx_colour="$RED"
    elif (( pct_int >= 50 )); then ctx_colour="$YELLOW"
    else                           ctx_colour="$GREEN"
    fi
    ctx_part=$(printf "${ctx_colour}ctx ${pct_int}%%${RESET}")
fi

# --------------------------------------------------------------------------
# 3b. Quota used, per rate-limit window
# --------------------------------------------------------------------------
# The percentage answers "how much is left"; the reset answers "when does this
# stop mattering", which is the other half of the same question -- 90% with four
# hours to go is a problem, and 90% at two minutes to nine is not.
#
# A clock time rather than a countdown, because it is the one you can plan
# around: "22:59" tells you to go and do something else, where "in 2h58m" has to
# be added to the time before it means that. The day is put in front when the
# reset is not today, which the seven-day windows almost never are -- a bare
# "09:00" for something four days away reads as this morning.
reset_at() {
    local at=$1
    [[ -z "$at" ]] && return
    if [[ "$(date -r "$at" +%F 2>/dev/null)" == "$(date +%F)" ]]; then
        date -r "$at" +%H:%M 2>/dev/null
    else
        date -r "$at" "+%a %H:%M" 2>/dev/null
    fi
}

quota_part() {
    local label=$1 pct=$2 reset=$3 int colour text when
    [[ -z "$pct" ]] && return
    # Rounded rather than truncated: the payload carries values like
    # 28.999999999999996, and reporting that as 28 is off by a percent for no
    # reason other than how it was stored.
    int=$(printf "%.0f" "$pct" 2>/dev/null) || return
    if   (( int >= 90 )); then colour="$RED"
    elif (( int >= 70 )); then colour="$YELLOW"
    else                       colour="$GREEN"
    fi
    text="${label} ${int}%%"
    when=$(reset_at "$reset")
    [[ -n "$when" ]] && text+=" (reset ${when})"
    printf "${colour}${text}${RESET}"
}

five_part=$(quota_part "5h" "$five_pct" "$five_reset")
week_part=$(quota_part "7d" "$week_pct" "$week_reset")
# Only when the payload carries it. The Opus weekly cap is the one that bites on
# an Opus-heavy week, and it is absent on plans and models that do not track it.
opus_part=$(quota_part "7d-opus" "$opus_pct" "$opus_reset")

# --------------------------------------------------------------------------
# 3. Current directory (~ for home)
# --------------------------------------------------------------------------
short_dir="${cwd/#$HOME/(HOME)}"
dir_part=$(printf "${CYAN}${BOLD}${short_dir}${RESET}")

# --------------------------------------------------------------------------
# 4-6. Git fields (gracefully omitted outside a git repo)
# --------------------------------------------------------------------------
origin_part=""
branch_part=""
dirty_part=""

if git -C "$cwd" rev-parse --is-inside-work-tree --no-optional-locks >/dev/null 2>&1; then

    # 4. Remote origin URL
    origin=$(git -C "$cwd" remote get-url origin 2>/dev/null)
    if [[ -n "$origin" ]]; then
        origin_part=$(printf "${BLUE}${origin}${RESET}")
    fi

    # 5. Branch (or short SHA when detached)
    branch=$(git -C "$cwd" symbolic-ref --short HEAD 2>/dev/null \
             || git -C "$cwd" rev-parse --short HEAD 2>/dev/null)

    # 6. Dirty status: staged (+) unstaged (~) untracked (?)
    staged=0; unstaged=0; untracked=0
    while IFS= read -r line; do
        x="${line:0:1}"; y="${line:1:1}"
        [[ "$x" != " " && "$x" != "?" ]] && (( staged++ ))
        [[ "$y" == "M" || "$y" == "D" ]]  && (( unstaged++ ))
        [[ "$x" == "?" ]]                  && (( untracked++ ))
    done < <(git -C "$cwd" status --porcelain --no-optional-locks 2>/dev/null)

    dirty_str=""
    (( staged    > 0 )) && dirty_str+=" +${staged}"
    (( unstaged  > 0 )) && dirty_str+=" ~${unstaged}"
    (( untracked > 0 )) && dirty_str+=" ?${untracked}"
    dirty_str="${dirty_str# }"   # trim leading space

    if [[ -n "$dirty_str" ]]; then
        branch_part=$(printf "${YELLOW}${branch}${RESET}")
        dirty_part=$(printf "${YELLOW}${dirty_str}${RESET}")
    else
        branch_part=$(printf "${GREEN}${branch}${RESET}")
    fi
fi

# --------------------------------------------------------------------------
# Session cost
# --------------------------------------------------------------------------
cost_part=""
if [[ -n "$cost" ]]; then
    cost_fmt=$(printf "%.4f" "$cost" 2>/dev/null)
    cost_part=$(printf "${GREEN}\$${cost_fmt}${RESET}")
fi

# --------------------------------------------------------------------------
# Assemble parts, separated by " | "
# --------------------------------------------------------------------------
email_part=""
if [[ -n "$email" ]]; then
    email_part=$(printf "${MAGENTA}${email}${RESET}")
fi

session_part=""
if [[ -n "$session_name" ]]; then
    if [[ -n "$session_id" ]]; then
        session_part=$(printf "${PURPLE}${session_name}:${session_id%%-*}${RESET}")
    else
        session_part=$(printf "${PURPLE}${session_name}${RESET}")
    fi
elif [[ -n "$session_id" ]]; then
    # Unnamed session: the id alone still beats showing nothing, since it is what
    # `claude --resume` and the transcript filename both use.
    session_part=$(printf "${PURPLE}${session_id%%-*}${RESET}")
fi

sep=$(printf " ${WHITE}|${RESET} ")
parts=()
[[ -n "$email_part"   ]] && parts+=("$email_part")
[[ -n "$session_part" ]] && parts+=("$session_part")
[[ -n "$model_part"  ]] && parts+=("$model_part")
[[ -n "$mode_part"   ]] && parts+=("$mode_part")
[[ -n "$ctx_part"    ]] && parts+=("$ctx_part")
[[ -n "$five_part"   ]] && parts+=("$five_part")
[[ -n "$week_part"   ]] && parts+=("$week_part")
[[ -n "$opus_part"   ]] && parts+=("$opus_part")
[[ -n "$cost_part"   ]] && parts+=("$cost_part")
parts+=("$dir_part")
[[ -n "$origin_part" ]] && parts+=("$origin_part")
[[ -n "$branch_part" ]] && parts+=("$branch_part")
[[ -n "$dirty_part"  ]] && parts+=("$dirty_part")

result=""
for part in "${parts[@]}"; do
    [[ -n "$result" ]] && result+="$sep"
    result+="$part"
done

printf "%b\n" "$result"
