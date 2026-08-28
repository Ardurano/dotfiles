#!/bin/bash
# Claude Code statusLine script mirroring the user's Starship prompt config
# (~/.config/starship.toml):
#   format = "$directory$git_branch$git_status$cmd_duration$line_break$character"
#
# $cmd_duration and $character are shell-prompt concepts tied to the last
# executed command's runtime/exit code. Claude Code's statusLine reflects the
# current session, not a shell command, so there is no equivalent data to
# show and those two segments are intentionally omitted here.
#
# Segments reproduced, matching Starship's default styles as closely as
# reasonably possible:
#   [directory]   bold cyan, truncation_length=3, truncate_to_repo=true
#   [git_branch]  bold purple, "on <branch-icon> <branch>"
#   [git_status]  bold red, "[<symbols>]" (staged +, modified !, untracked ?,
#                 renamed », conflicted =, stashed $, ahead ⇡N, behind ⇣N)
#
# Session segments (not part of Starship, carried over from the previous
# statusline.sh): model name | session duration | context usage | session
# cost. Context usage and cost are threshold-colored:
#   context: green <150k tokens, yellow 150k-200k, red 200k+
#   cost:    green <$5, yellow $5-15, red $15+

input=$(cat)

cwd=$(command -v jq >/dev/null 2>&1 && printf '%s' "$input" | jq -r '.workspace.current_dir // .cwd // empty')
[ -n "$cwd" ] && cd "$cwd" 2>/dev/null

RESET=$'\033[0m'
CYAN_BOLD=$'\033[1;36m'
PURPLE_BOLD=$'\033[1;35m'
RED_BOLD=$'\033[1;31m'
GREEN_BOLD=$'\033[1;32m'
YELLOW_BOLD=$'\033[1;33m'
BLUE_BOLD=$'\033[1;34m'
GRAY=$'\033[2;37m'
BRANCH_ICON=$''

to_display_path() {
  # Replaces a leading $HOME with ~
  local p="$1"
  case "$p" in
    "$HOME") printf '~' ;;
    "$HOME"/*) printf '~%s' "${p#"$HOME"}" ;;
    *) printf '%s' "$p" ;;
  esac
}

path_depth() {
  # Number of non-empty path components
  local p="$1"
  local -a arr
  IFS='/' read -r -a arr <<< "$p"
  local count=0
  for c in "${arr[@]}"; do
    [ -n "$c" ] && count=$((count + 1))
  done
  echo "$count"
}

# ---- directory ----
raw_dir=$(pwd)
disp_dir=$(to_display_path "$raw_dir")

IFS='/' read -r -a parts <<< "$disp_dir"
clean_parts=()
for c in "${parts[@]}"; do
  [ -n "$c" ] && clean_parts+=("$c")
done
n=${#clean_parts[@]}

truncation_length=3
start=0
if [ "$n" -gt "$truncation_length" ]; then
  start=$((n - truncation_length))
fi

git_root=$(git --no-optional-locks rev-parse --show-toplevel 2>/dev/null)
if [ -n "$git_root" ]; then
  repo_disp=$(to_display_path "$git_root")
  repo_depth=$(path_depth "$repo_disp")
  # truncate_to_repo=true: never truncate away the repository root
  if [ "$repo_depth" -ge 1 ] && [ "$start" -gt "$((repo_depth - 1))" ]; then
    start=$((repo_depth - 1))
  fi
fi

if [ "$start" -gt 0 ]; then
  truncated="..."
  for ((i = start; i < n; i++)); do
    truncated="${truncated}/${clean_parts[$i]}"
  done
  disp_dir="$truncated"
fi

output="${CYAN_BOLD}${disp_dir}${RESET} "

# ---- git branch + status ----
if git --no-optional-locks rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  branch=$(git --no-optional-locks symbolic-ref --quiet --short HEAD 2>/dev/null)
  [ -z "$branch" ] && branch=$(git --no-optional-locks rev-parse --short HEAD 2>/dev/null)

  if [ -n "$branch" ]; then
    output="${output}${PURPLE_BOLD}on ${BRANCH_ICON} ${branch}${RESET} "
  fi

  porcelain=$(git --no-optional-locks status --porcelain=2 --branch 2>/dev/null)

  ahead=$(printf '%s\n' "$porcelain" | awk '/^# branch\.ab/ { gsub("\\+", "", $3); print $3 }')
  behind=$(printf '%s\n' "$porcelain" | awk '/^# branch\.ab/ { gsub("-", "", $4); print $4 }')

  has_staged=0; has_modified=0; has_untracked=0; has_renamed=0; has_conflict=0
  while IFS= read -r line; do
    case "$line" in
      "1 "*|"2 "*)
        xy=$(printf '%s' "$line" | awk '{print $2}')
        x=${xy:0:1}
        y=${xy:1:1}
        [ "$x" != "." ] && has_staged=1
        [ "$y" != "." ] && has_modified=1
        [[ "$line" == "2 "* ]] && has_renamed=1
        ;;
      "u "*) has_conflict=1 ;;
      "? "*) has_untracked=1 ;;
    esac
  done <<< "$porcelain"

  stash_count=$(git --no-optional-locks stash list 2>/dev/null | wc -l | tr -d ' ')

  status_syms=""
  [ "$has_conflict" = "1" ] && status_syms="${status_syms}="
  [ -n "$ahead" ] && [ "$ahead" != "0" ] && status_syms="${status_syms}⇡${ahead}"
  [ -n "$behind" ] && [ "$behind" != "0" ] && status_syms="${status_syms}⇣${behind}"
  [ -n "$stash_count" ] && [ "$stash_count" != "0" ] && status_syms="${status_syms}\$"
  [ "$has_staged" = "1" ] && status_syms="${status_syms}+"
  [ "$has_renamed" = "1" ] && status_syms="${status_syms}»"
  [ "$has_modified" = "1" ] && status_syms="${status_syms}!"
  [ "$has_untracked" = "1" ] && status_syms="${status_syms}?"

  if [ -n "$status_syms" ]; then
    output="${output}${RED_BOLD}[${status_syms}]${RESET} "
  fi
fi

# ---- session info: model | duration | context | cost ----
if command -v jq >/dev/null 2>&1; then
  model=$(printf '%s' "$input" | jq -r '.model.display_name // empty')

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

  used_tokens=$(printf '%s' "$input" | jq -r '.context_window.total_input_tokens // empty')
  total_tokens=$(printf '%s' "$input" | jq -r '.context_window.context_window_size // empty')
  if [ -z "$used_tokens" ] && [ -n "$total_tokens" ]; then
    used_tokens=$(printf '%s' "$input" | jq -r '
      (.context_window.current_usage // empty) as $u
      | if $u then (($u.input_tokens // 0) + ($u.cache_creation_input_tokens // 0) + ($u.cache_read_input_tokens // 0)) else empty end
    ')
  fi

  context_segment=""
  if [ -n "$used_tokens" ] && [ -n "$total_tokens" ]; then
    used_k=$(awk -v v="$used_tokens" 'BEGIN { printf "%.0f", v/1000 }')
    total_k=$(awk -v v="$total_tokens" 'BEGIN { printf "%.0f", v/1000 }')
    context_color="$GREEN_BOLD"
    if awk -v v="$used_tokens" 'BEGIN { exit !(v >= 200000) }'; then
      context_color="$RED_BOLD"
    elif awk -v v="$used_tokens" 'BEGIN { exit !(v >= 150000) }'; then
      context_color="$YELLOW_BOLD"
    fi
    context_segment="${context_color}${used_k}k/${total_k}k ctx${RESET}"
  fi

  cost=$(printf '%s' "$input" | jq -r '.cost.total_cost_usd // empty')
  cost_segment=""
  if [ -n "$cost" ]; then
    cost_fmt=$(awk -v v="$cost" 'BEGIN { printf "%.2f", v }')
    cost_color="$GREEN_BOLD"
    if awk -v v="$cost" 'BEGIN { exit !(v >= 15) }'; then
      cost_color="$RED_BOLD"
    elif awk -v v="$cost" 'BEGIN { exit !(v >= 5) }'; then
      cost_color="$YELLOW_BOLD"
    fi
    cost_segment="${cost_color}\$${cost_fmt} session${RESET}"
  fi

  session_segments=()
  [ -n "$model" ] && session_segments+=("${BLUE_BOLD}${model}${RESET}")
  [ -n "$duration" ] && session_segments+=("${GRAY}${duration}${RESET}")
  [ -n "$context_segment" ] && session_segments+=("$context_segment")
  [ -n "$cost_segment" ] && session_segments+=("$cost_segment")

  if [ "${#session_segments[@]}" -gt 0 ]; then
    session_out=""
    for seg in "${session_segments[@]}"; do
      if [ -z "$session_out" ]; then
        session_out="$seg"
      else
        session_out="${session_out}${GRAY} | ${RESET}${seg}"
      fi
    done
    output="${output}${session_out}"
  fi
fi

printf '%s' "$output"
