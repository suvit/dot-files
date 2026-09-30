#!/usr/bin/env bash
# Claude Code status line: time | model | folder | git branch | plan | context
# Reads the status-line JSON payload from stdin and prints one line.

input=$(cat)

# --- Extract a value from the JSON: jq if available, otherwise python3 ---
get() {
  if command -v jq >/dev/null 2>&1; then
    printf '%s' "$input" | jq -r "$1 // empty" 2>/dev/null
  else
    printf '%s' "$input" | python3 -c '
import json, sys
try:
    data = json.load(sys.stdin)
except Exception:
    sys.exit(0)
node = data
for key in sys.argv[1].lstrip(".").split("."):
    if isinstance(node, dict) and node.get(key) is not None:
        node = node[key]
    else:
        sys.exit(0)
print(node)
' "$1" 2>/dev/null
  fi
}

model=$(get '.model.display_name')
dir=$(get '.workspace.current_dir')
[ -z "$dir" ] && dir=$(get '.cwd')

# --- Shorten $HOME to ~ ---
short=""
if [ -n "$dir" ]; then
  case "$dir" in
    "$HOME")   short="~" ;;
    "$HOME"/*) short="~${dir#"$HOME"}" ;;
    *)         short="$dir" ;;
  esac
fi

# --- Git branch + dirty marker (skips optional locks) ---
gitseg=""
if [ -n "$dir" ] && [ -d "$dir" ]; then
  branch=$(git -C "$dir" --no-optional-locks rev-parse --abbrev-ref HEAD 2>/dev/null) || branch=""
  if [ -n "$branch" ]; then
    mark=""
    [ -n "$(git -C "$dir" --no-optional-locks status --porcelain 2>/dev/null)" ] && mark="*"
    gitseg="${branch}${mark}"
  fi
fi

# --- Colors ---
C_MODEL=$'\033[35m'  # magenta
C_DIR=$'\033[36m'    # cyan
C_GIT=$'\033[32m'    # green
C_OK=$'\033[32m'     # green: remaining >= yellow cutoff
C_WARN=$'\033[33m'   # yellow: remaining >= red cutoff (below yellow cutoff)
C_CRIT=$'\033[31m'   # red: remaining < red cutoff
C_SEP=$'\033[2m'     # dim
C_RST=$'\033[0m'

# --- Percent helpers ---
rem_fmt() { # $1 = used percentage -> print remaining, rounded to integer
  LC_ALL=C awk -v v="$1" 'BEGIN { printf "%.0f", 100 - v }'
}
num_ok() { [[ "$1" =~ ^[0-9]+([.][0-9]+)?$ ]]; }
color_for() { # $1 = remaining %, $2 = yellow-below cutoff, $3 = red-below cutoff
  if [ "$1" -ge "$2" ]; then printf '%s' "$C_OK"
  elif [ "$1" -ge "$3" ]; then printf '%s' "$C_WARN"
  else printf '%s' "$C_CRIT"
  fi
}

# --- Plan limits: remaining % per window; skip any window that is absent ---
planseg=""
for win in five_hour seven_day; do
  used=$(printf '%s' "$input" | get ".rate_limits.${win}.used_percentage")
  if [ -n "$used" ] && num_ok "$used"; then
    case "$win" in
      five_hour) label="5h" ;;
      seven_day) label="7d" ;;
    esac
    rem=$(rem_fmt "$used")
    part="$(color_for "$rem" 50 20)${label}:${rem}%${C_RST}"
    if [ -n "$planseg" ]; then planseg+=" $part"; else planseg="$part"; fi
  fi
done

# --- Provider from ANTHROPIC_BASE_URL: picks the quota source below ---
provider=""
case "${ANTHROPIC_BASE_URL:-}" in
  *token-plan.*|*dashscope*) provider="alibaba" ;;  # no public usage API (console-only), no fallback segment
  *z.ai*|*bigmodel.cn*)      provider="zai" ;;
  *)                         provider="other" ;;
esac

# --- Plan limits fallback: z.ai quota endpoint (only when no native data and provider=zai) ---
ZAI_QUOTA_URL='https://api.z.ai/api/monitor/usage/quota/limit'
ZAI_QUOTA_CACHE=/tmp/claude-zai-quota.json
ZAI_QUOTA_TS=/tmp/claude-zai-quota.ts
zai_resp_ok() { # $1 = response body; true when code==200 and data.limits is an array
  if command -v jq >/dev/null 2>&1; then
    printf '%s' "$1" | jq -e '.code == 200 and (.data.limits | type == "array")' >/dev/null 2>&1
  else
    printf '%s' "$1" | python3 -c '
import json, sys
try:
    d = json.load(sys.stdin)
    ok = d.get("code") == 200 and isinstance((d.get("data") or {}).get("limits"), list)
except Exception:
    ok = False
sys.exit(0 if ok else 1)
'
  fi
}
zai_pct() { # stdin = response body; $1 = unit (3 = 5h window, 6 = weekly window)
  if command -v jq >/dev/null 2>&1; then
    jq -r --argjson u "$1" '[.data.limits[]? | select(.unit == $u)][0].percentage // empty' 2>/dev/null
  else
    python3 -c '
import json, sys
try:
    d = json.load(sys.stdin)
except Exception:
    sys.exit(0)
try:
    unit = int(sys.argv[1])
except ValueError:
    sys.exit(0)
for item in (d.get("data") or {}).get("limits") or []:
    if item.get("unit") == unit and item.get("percentage") is not None:
        print(item["percentage"])
        break
' "$1" 2>/dev/null
  fi
}
if [ -z "$planseg" ] && [ "$provider" = zai ]; then
  zai_key=""
  for k in ZAI_API_KEY Z_AI_API_KEY ZAI_CODING_API_KEY ANTHROPIC_AUTH_TOKEN; do
    v="${!k:-}"
    if [ -n "$v" ]; then zai_key="$v"; break; fi
  done
  if [ -n "$zai_key" ] && command -v curl >/dev/null 2>&1; then
    now=$(date +%s)
    ats=0
    [ -f "$ZAI_QUOTA_TS" ] && ats=$(cat "$ZAI_QUOTA_TS" 2>/dev/null)
    case "$ats" in ''|*[!0-9]*) ats=0 ;; esac
    body=""
    if [ "$now" -ge $((ats + 60)) ]; then
      printf '%s' "$now" > "$ZAI_QUOTA_TS" 2>/dev/null   # rate-limit attempts to 1 per 60s
      body=$(curl -sS -m 5 -H "Authorization: Bearer $zai_key" "$ZAI_QUOTA_URL" 2>/dev/null) || body=""
      if [ -n "$body" ] && zai_resp_ok "$body"; then
        printf '%s' "$body" > "$ZAI_QUOTA_CACHE" 2>/dev/null
      else
        body=""
      fi
    fi
    if [ -z "$body" ] && [ -s "$ZAI_QUOTA_CACHE" ]; then
      mtime=$(date -r "$ZAI_QUOTA_CACHE" +%s 2>/dev/null)
      case "$mtime" in ''|*[!0-9]*) mtime=0 ;; esac
      if [ "$now" -le $((mtime + 21600)) ]; then         # cache usable for ~6 hours
        cached=$(cat "$ZAI_QUOTA_CACHE" 2>/dev/null)
        if [ -n "$cached" ] && zai_resp_ok "$cached"; then body="$cached"; fi
      fi
    fi
    if [ -n "$body" ]; then
      p5=$(printf '%s' "$body" | zai_pct 3)              # unit 3 = 5-hour window
      p7=$(printf '%s' "$body" | zai_pct 6)              # unit 6 = weekly window
      if [ -n "$p5" ] && num_ok "$p5"; then
        r=$(rem_fmt "$p5")                               # percentage is USED; render remaining
        planseg="$(color_for "$r" 50 20)5h:${r}%${C_RST}"
      fi
      if [ -n "$p7" ] && num_ok "$p7"; then
        r=$(rem_fmt "$p7")
        part="$(color_for "$r" 50 20)7d:${r}%${C_RST}"
        if [ -n "$planseg" ]; then planseg+=" $part"; else planseg="$part"; fi
      fi
    fi
  fi
fi

# --- Context: remaining % (fall back to 100 - used_percentage) ---
ctxseg=""
ctxrem=$(printf '%s' "$input" | get '.context_window.remaining_percentage')
if [ -z "$ctxrem" ] || ! num_ok "$ctxrem"; then
  ctxused=$(printf '%s' "$input" | get '.context_window.used_percentage')
  if [ -n "$ctxused" ] && num_ok "$ctxused"; then
    ctxrem=$(rem_fmt "$ctxused")
  else
    ctxrem=""
  fi
fi
if [ -n "$ctxrem" ]; then
  ctxseg="$(color_for "$ctxrem" 80 50)ctx:${ctxrem}%${C_RST}"
fi

# --- Assemble one colored line ---

ts=$(date '+%d.%m %H:%M')
sep="${C_SEP} | ${C_RST}"
parts=()
[ -n "$model" ]   && parts+=("${C_MODEL}${model}${C_RST}")
[ -n "$short" ]   && parts+=("${C_DIR}${short}${C_RST}")
[ -n "$gitseg" ]  && parts+=("${C_GIT}${gitseg}${C_RST}")
[ -n "$planseg" ] && parts+=("$planseg")
[ -n "$ctxseg" ]  && parts+=("$ctxseg")

out=""
for i in "${!parts[@]}"; do
  [ "$i" -gt 0 ] && out+="$sep"
  out+="${parts[$i]}"
done

printf '%s\n' "${C_SEP}[${ts}]${C_RST}${out:+ }${out}"
