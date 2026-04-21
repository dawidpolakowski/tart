#!/usr/bin/env bash
set -euo pipefail

# tart - Task Activity Reporting Tool
#
# Defaults:
#   TART_LOGDIR -> ~/Documents/tart
#
# Each week stored as: YYYY-MM-DD.log (the Monday of that ISO week)
# Entry format: YYYY-MM-DD <message>

TART_LOGDIR="${TART_LOGDIR:-${HOME}/Documents/tart}"

ensure_tart_dirs() {
  mkdir -p "$TART_LOGDIR"
}

show_tart_help() {
  cat <<'EOF_HELP'
╭─ tart (Task Activity Reporting Tool)
│ Usage:
│   tart                        → View current week's log
│   tart "message"             → Log a task
│   tart --today | -t          → View today's entries
│   tart --this-week | -tw     → View current week
│   tart --week YYYY-MM-DD     → View the week file by its Monday date
│   tart -h|--help             → Help
╰──────────────────────────────────────
EOF_HELP
}

# Return the weekday number (1-7, Monday=1) for a YYYY-MM-DD date.
weekday_number() {
  local date_string="$1"

  if dow="$(date -d "$date_string" +%u 2>/dev/null)"; then
    printf '%s\n' "$dow"
    return
  fi

  date -j -f "%F" "$date_string" +%u
}

# Subtract a number of days from a YYYY-MM-DD date.
subtract_days() {
  local date_string="$1"
  local days="$2"

  if date -d "$date_string -${days} days" +%F >/dev/null 2>&1; then
    date -d "$date_string -${days} days" +%F
    return
  fi

  date -j -v -"${days}"d -f "%F" "$date_string" +%F
}

# Return the Monday date for the week containing the given YYYY-MM-DD date.
week_start_for_date() {
  local date_string="${1:-$(date +%F)}"
  local dow offset

  dow="$(weekday_number "$date_string")"
  offset=$((dow - 1))

  if [[ "$offset" -eq 0 ]]; then
    printf '%s\n' "$date_string"
  else
    subtract_days "$date_string" "$offset"
  fi
}

# Return the Monday date for an ISO week reference like YYYY-Www.
week_start_for_iso_week() {
  local week_ref="$1"
  local iso_year iso_week jan4 jan4_dow first_monday week_start

  if [[ ! "$week_ref" =~ ^([0-9]{4})-W([0-9]{2})$ ]]; then
    return 1
  fi

  iso_year="${BASH_REMATCH[1]}"
  iso_week="${BASH_REMATCH[2]}"
  jan4="${iso_year}-01-04"
  jan4_dow="$(weekday_number "$jan4")"
  first_monday="$(subtract_days "$jan4" "$((jan4_dow - 1))")"
  week_start="$(subtract_days "$first_monday" "$(( (10#${iso_week} - 1) * 7 ))")"
  printf '%s\n' "$week_start"
}

get_week_file() {
  local week_ref="${1:-}"

  if [[ -n "$week_ref" ]]; then
    if [[ "$week_ref" =~ ^[0-9]{4}-W[0-9]{2}$ ]]; then
      local week_start
      week_start="$(week_start_for_iso_week "$week_ref")"
      printf '%s.log\n' "$week_start"
    elif [[ "$week_ref" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
      printf '%s.log\n' "$week_ref"
    else
      printf '%s.log\n' "$week_ref"
    fi
  else
    printf '%s.log\n' "$(week_start_for_date)"
  fi
}

current_week_path() {
  echo "$TART_LOGDIR/$(get_week_file)"
}

week_path_for() {
  local week_ref="$1"
  echo "$TART_LOGDIR/$(get_week_file "$week_ref")"
}

append_tart_entry() {
  local entry="$*"
  local file
  file="$(current_week_path)"

  printf '%s %s\n' "$(date +%F)" "$entry" >> "$file"
  printf '✓ %s\n' "$entry"
}

show_week_entries() {
  local file="$1"

  if [[ ! -f "$file" ]]; then
    echo "No entries yet for this week."
    return
  fi

  cat "$file"
}

show_today_entries() {
  local file today
  file="$(current_week_path)"
  today="$(date +%F)"

  if [[ ! -f "$file" ]]; then
    echo "No entries yet for today."
    return
  fi

  grep -E "^${today} " "$file" || echo "No entries yet for today."
}

main() {
  ensure_tart_dirs

  case "${1:-}" in
    -h|--help|help|?)
      show_tart_help
      ;;
    --today|-t)
      show_today_entries
      ;;
    --this-week|-tw)
      show_week_entries "$(current_week_path)"
      ;;
    --week)
      if [[ -z "${2:-}" ]]; then
        echo "Usage: tart --week YYYY-MM-DD" >&2
        exit 1
      fi
      show_week_entries "$(week_path_for "$2")"
      ;;
    "")
      show_week_entries "$(current_week_path)"
      ;;
    *)
      append_tart_entry "$*"
      ;;
  esac
}

main "$@"
