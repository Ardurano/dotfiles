#!/usr/bin/env bash
# Claude Code statusLine script.
# Reads the session JSON on stdin and prints:
#   Model | Duration | NN% ctx (USEDk/TOTALk) | $X.XX session
# The context segment is omitted gracefully if context_window data is absent.

input=$(cat)

if ! command -v jq >/dev/null 2>&1; then
  # No jq available: best-effort fallback using a plain string match.
  printf '%s' "$input" | grep -o '"display_name"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed -E 's/.*"([^"]*)"$/\1/'
  exit 0
fi

model=$(printf '%s' "$input" | jq -r '.model.display_name // "Claude"')

duration_ms=$(printf '%s' "$input" | jq -r '.cost.total_duration_ms // empty')
duration=""
if [ -n "$duration_ms" ]; then
  total_seconds=$(( duration_ms / 1000 ))
  h=$(( total_seconds / 3600 ))
  m=$(( (total_seconds % 3600) / 60 ))
  s=$(( total_seconds % 60 ))
  if [ "$h" -ge 1 ]; then
    duration="${h}h${m}m"
  elif [ "$m" -ge 1 ]; then
    duration="${m}m${s}s"
  else
    duration="${s}s"
  fi
fi

used_pct=$(printf '%s' "$input" | jq -r '.context_window.used_percentage // empty')
used_tokens=$(printf '%s' "$input" | jq -r '.context_window.total_input_tokens // empty')
total_tokens=$(printf '%s' "$input" | jq -r '.context_window.context_window_size // empty')

# Older payload shapes may not carry total_input_tokens directly; derive it
# from the current_usage breakdown when available.
if [ -z "$used_tokens" ] && [ -n "$total_tokens" ]; then
  used_tokens=$(printf '%s' "$input" | jq -r '
    (.context_window.current_usage // empty) as $u
    | if $u then (($u.input_tokens // 0) + ($u.cache_creation_input_tokens // 0) + ($u.cache_read_input_tokens // 0)) else empty end
  ')
fi

context_segment=""
if [ -n "$used_pct" ] && [ -n "$used_tokens" ] && [ -n "$total_tokens" ]; then
  used_k=$(awk -v v="$used_tokens" 'BEGIN { printf "%.0f", v/1000 }')
  total_k=$(awk -v v="$total_tokens" 'BEGIN { printf "%.0f", v/1000 }')
  pct=$(awk -v v="$used_pct" 'BEGIN { printf "%.0f", v }')
  context_segment="${pct}% ctx (${used_k}k/${total_k}k)"
fi

cost=$(printf '%s' "$input" | jq -r '.cost.total_cost_usd // empty')
cost_segment=""
if [ -n "$cost" ]; then
  cost_fmt=$(awk -v v="$cost" 'BEGIN { printf "%.2f", v }')
  cost_segment="\$${cost_fmt} session"
fi

segments=()
[ -n "$model" ] && segments+=("$model")
[ -n "$duration" ] && segments+=("$duration")
[ -n "$context_segment" ] && segments+=("$context_segment")
[ -n "$cost_segment" ] && segments+=("$cost_segment")

out=""
for seg in "${segments[@]}"; do
  if [ -z "$out" ]; then
    out="$seg"
  else
    out="$out | $seg"
  fi
done

printf '%s' "$out"
