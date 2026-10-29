#!/bin/bash
# Sourced by every taskhauler template. Loads config + token, exports:
#   URL    base URL (e.g. http://taskhauler.localhost)
#   API    base URL + /api/v1
#   TOKEN  bearer token (access or service-account)
#   H      curl header array
#
# Refreshes/logs in if needed. Exits with a clear message on auth failure.
# Pure POSIX tools (grep, sed, jq, curl). No yq / no PyYAML dependency.

set -e

CFG_DIR=$HOME/.config/taskhauler
CFG=$CFG_DIR/config.yaml
CRED=$CFG_DIR/credentials.yaml

# ---- bootstrap: dir, perms, .gitignore tripwire ----
mkdir -p "$CFG_DIR"
chmod 700 "$CFG_DIR"
if [ ! -f "$CFG_DIR/.gitignore" ]; then
  cat > "$CFG_DIR/.gitignore" <<'EOF'
credentials.yaml
config.yaml
EOF
fi

# ---- flat-YAML scalar getter (trims whitespace) ----
yget() {
  local file=$1 key=$2
  grep -E "^$key:" "$file" 2>/dev/null \
    | sed -E "s/^$key:[[:space:]]*//" \
    | sed -E 's/^[[:space:]]+|[[:space:]]+$//g' \
    | head -1
}

yset() {
  local file=$1 key=$2 value=$3
  if grep -qE "^$key:" "$file" 2>/dev/null; then
    sed -i.bak -E "s|^$key:.*|$key: $value|" "$file" && rm -f "$file.bak"
  else
    printf '%s: %s\n' "$key" "$value" >> "$file"
  fi
}

write_config_yaml() {
  local url=$1 email=$2 access=$3 refresh=$4 exp=$5
  umask 077
  cat > "$CFG" <<EOF
url: $url
email: $email
access_token: $access
refresh_token: $refresh
expires_at: $exp
EOF
  chmod 600 "$CFG"
}

# ---- attempt 1: cached fresh token ----
if [ -f "$CFG" ]; then
  URL=$(yget "$CFG" url)
  EMAIL=$(yget "$CFG" email)
  TOKEN=$(yget "$CFG" access_token)
  REFRESH=$(yget "$CFG" refresh_token)
  EXP=$(yget "$CFG" expires_at)
  NOW=$(date +%s)

  if [ -n "$TOKEN" ] && [ -n "$EXP" ] && [ "$EXP" -gt "$((NOW + 60))" ]; then
    : # fresh enough
  elif [ -n "$REFRESH" ] && [ "$REFRESH" != "null" ]; then
    # ---- attempt 2: refresh ----
    RESP=$(curl -sf -X POST -H 'Content-Type: application/json' \
      -d "$(jq -n --arg r "$REFRESH" '{refresh_token:$r}')" \
      "$URL/api/v1/auth/refresh" 2>/dev/null || true)
    if [ -n "$RESP" ]; then
      NEW_ACCESS=$(echo "$RESP" | jq -r '.access_token // empty')
      NEW_REFRESH=$(echo "$RESP" | jq -r '.refresh_token // empty')
      if [ -n "$NEW_ACCESS" ]; then
        TOKEN=$NEW_ACCESS
        REFRESH=${NEW_REFRESH:-$REFRESH}
        EXP=$((NOW + 3600))
        write_config_yaml "$URL" "$EMAIL" "$TOKEN" "$REFRESH" "$EXP"
      else
        TOKEN=""
      fi
    else
      TOKEN=""
    fi
  else
    TOKEN=""
  fi
fi

# ---- attempt 3: login from credentials.yaml ----
if [ -z "${TOKEN:-}" ]; then
  if [ ! -f "$CRED" ]; then
    cat >&2 <<EOF
ERROR: no usable taskhauler token, and $CRED is missing.

Create the file (it will be deleted automatically after login):

  url: http://taskhauler.localhost
  email: you@example.com
  password: yourpassword

Then re-run.
EOF
    exit 1
  fi
  URL=$(yget "$CRED" url)
  EMAIL=$(yget "$CRED" email)
  PASS=$(yget "$CRED" password)
  RESP=$(curl -sf -X POST -H 'Content-Type: application/json' \
    -d "$(jq -n --arg e "$EMAIL" --arg p "$PASS" '{email:$e,password:$p}')" \
    "$URL/api/v1/auth/login")
  TOKEN=$(echo "$RESP"    | jq -r '.access_token')
  REFRESH=$(echo "$RESP"  | jq -r '.refresh_token // empty')
  EXP=$(($(date +%s) + 3600))
  write_config_yaml "$URL" "$EMAIL" "$TOKEN" "$REFRESH" "$EXP"
  rm -f "$CRED"
fi

API="$URL/api/v1"
H=(-H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json")
export URL API TOKEN