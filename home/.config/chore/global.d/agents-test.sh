#!/bin/sh
# Checks global:agents:score against fixed accounts: the account furthest behind its
# pace should go first. Then global:agents:pick and global:agents:override, which next
# uses: an --override account always goes first (with --flexible, only while it is
# usable), and stays until --remove-override. Run it with `chore global:agents:test`; it needs $CHORE_EXE.
now=$(date +%s)
fixture=$(jq -n --argjson now "$now" '{claude: {
  personal: {name: "claude-personal", config_dir: "p", email: null,
    five_hour: {used_percentage: 9, remaining_percentage: 91, reset_at: ($now + 6500)},
    seven_day: {used_percentage: 92, remaining_percentage: 8, reset_at: ($now + 85656)}},
  work: {name: "claude-work", config_dir: "w", email: null,
    five_hour: {used_percentage: 51, remaining_percentage: 49, reset_at: ($now + 7055)},
    seven_day: {used_percentage: 6, remaining_percentage: 94, reset_at: ($now + 593255)}}}}')
score() { "$CHORE_EXE" global:agents:score; }
pick() { score | "$CHORE_EXE" global:agents:pick PIN="$(jq -nc --arg o "$1" --arg f "${2:-false}" '
  if $o == "" then {} else {override: $o, flexible: ($f == "true")} end')"; }
fail=0
check() { if [ "$2" = "$3" ]; then echo "PASS $1"; else echo "FAIL $1: got $2, want $3"; fail=1; fi; }

# 1. 2026-10-27 13:12: personal's 8% weekly with a day left is ahead of pace;
#    work's 49% five_hour refills in two hours. Work goes first.
check today "$(printf '%s' "$fixture" | score | jq -r '.[0].account')" claude-work

# 2. Quota about to expire unused goes first: 10% weekly left, an hour from reset.
check expiring "$(printf '%s' "$fixture" | jq --argjson now "$now" '
  .claude.personal.seven_day = {used_percentage: 90, remaining_percentage: 10, reset_at: ($now + 3600)}' |
  score | jq -r '.[0].account')" claude-personal

# 3. A five_hour window spent ahead of pace holds an account back even with weekly to spare.
check five_hour "$(printf '%s' "$fixture" | jq --argjson now "$now" '
  .claude.work.five_hour = {used_percentage: 85, remaining_percentage: 15, reset_at: ($now + 16000)}' |
  score | jq -r '.[0].account')" claude-personal

# 4. No reserve: a low but usable account carries no warning.
check no-reserve "$(printf '%s' "$fixture" | score | jq -r '[.[] | select(has("reserve"))] | length'):$(printf '%s' "$fixture" | score | jq -r '.[] | select(.account == "claude-personal") | .warning')" "0:no warning"

# 5. No override: the fair pick, and no override field.
check no-override "$(printf '%s' "$fixture" | pick '' | jq -r '[.account, .override // "-", .warning] | join(" | ")')" \
  "claude-work | - | no warning"

# 6. --override: the named account is taken over the fair pick.
check override "$(printf '%s' "$fixture" | pick claude-personal | jq -r '[.account, .override, .fair_pick // "-", .warning] | join(" | ")')" \
  "claude-personal | true | - | no warning"

# 7. The pin is strict: an override with no quota left is still taken, and its warning
#    says until when.
check override-spent "$(printf '%s' "$fixture" | jq --argjson now "$now" '
  .claude.personal.seven_day = {used_percentage: 100, remaining_percentage: 0, reset_at: ($now + 3600)}' |
  pick claude-personal | jq -r '.account + " | " + .warning')" \
  "claude-personal | out of quota until its reset"

# 8. --flexible: an override with no quota left is not used, and the warning says why.
check override-flexible "$(printf '%s' "$fixture" | jq --argjson now "$now" '
  .claude.personal.seven_day = {used_percentage: 100, remaining_percentage: 0, reset_at: ($now + 3600)}' |
  pick claude-personal true | jq -r '.account + " | " + .warning')" \
  "claude-work | override claude-personal not used: out of quota until its reset"

# 9. An override naming no account falls back the same way.
check override-unknown "$(printf '%s' "$fixture" | pick claude-nope | jq -r '.account + " | " + .warning')" \
  "claude-work | override claude-nope not used: no such account"

# 10-15. global:agents:override: --override is saved, strict unless --flexible, so a
#        later call without it still gets it, until --remove-override; an account that
#        does not exist is not saved; a file from before --flexible reads as strict.
dir=$(mktemp -d) || exit 1
trap 'rm -rf "$dir"' EXIT
override() { score | "$CHORE_EXE" global:agents:override OVERRIDE_FILE="$dir/override.json" "$@"; }
check override-saved "$(printf '%s' "$fixture" | override OVERRIDE=claude-personal):$(printf '%s' "$fixture" | override)" \
  '{"override":"claude-personal","flexible":false}:{"override":"claude-personal","flexible":false}'
check override-saved-flexible "$(printf '%s' "$fixture" | override OVERRIDE=claude-personal FLEXIBLE=true >/dev/null
  printf '%s' "$fixture" | override)" '{"override":"claude-personal","flexible":true}'
check override-removed "$(printf '%s' "$fixture" | override REMOVE_OVERRIDE=true):$(printf '%s' "$fixture" | override)" "{}:{}"
check override-refused "$(printf '%s' "$fixture" | override OVERRIDE=claude-nope 2>/dev/null; echo "exit $?"):$(printf '%s' "$fixture" | override)" \
  "exit 1:{}"
check flexible-alone "$(printf '%s' "$fixture" | override FLEXIBLE=true 2>/dev/null; echo "exit $?")" "exit 1"
check override-old-file "$(printf '{"override": "claude-work"}' > "$dir/override.json"
  printf '%s' "$fixture" | override)" '{"override":"claude-work","flexible":false}'
exit $fail
