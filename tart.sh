#!/usr/bin/env bash
set -euo pipefail

# tart - Task Activity Reporting Tool
#
# Defaults:
#   TART_LOGDIR -> ~/Documents/tart
#
# Each week is stored as: YYYY-MM-DD.log (the Monday of that ISO week)
# Entry format: YYYY-MM-DD <message>

readonly TART_VERSION="0.2.0"
TART_LOGDIR="${TART_LOGDIR:-${HOME}/Documents/tart}"
TART_ARGS=()
TART_FORCE_ADD=0

print_usage() {
  cat <<'EOF_HELP'
tart - Task Activity Reporting Tool

Usage:
  tart [global options] [command] [arguments]

Quick use:
  tart                         Show the current week's log
  tart "message"               Add a task entry for today

Commands:
  add <message...>             Add a task entry for today
  list [--week <ref>]          Show entries for a week
  today                        Show today's entries
  week [<ref>]                 Show entries for the week containing <ref>
  path [<ref>]                 Print the log file path for a week
  init                         Create the log directory
  config                       Show resolved configuration
  version                      Show version
  help                         Show help

Week refs:
  YYYY-MM-DD                   Any date in the target week
  YYYY-Www                     ISO week, for example 2026-W18

Global options:
  --log-dir <path>             Override TART_LOGDIR for this run
  -h, --help                   Show help
  -v, --version                Show version

Legacy aliases:
  -t, --today                  Same as: tart today
  -tw, --this-week             Same as: tart list
  --week <ref>                 Same as: tart week <ref>

Environment:
  TART_LOGDIR                  Default: ~/Documents/tart
EOF_HELP
}

print_version() {
  printf 'tart %s\n' "$TART_VERSION"
}

usage_error() {
  printf 'tart: %s\n' "$1" >&2
  printf "Run 'tart help' for usage.\n" >&2
  exit 2
}

require_no_args() {
  local command="$1"
  shift

  if (($# > 0)); then
    usage_error "${command} does not accept arguments"
  fi
}

ensure_tart_dirs() {
  mkdir -p "$TART_LOGDIR"
}

today_date() {
  date +%F
}

is_date_literal() {
  [[ "${1:-}" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]
}

is_iso_week_ref() {
  [[ "${1:-}" =~ ^[0-9]{4}-W[0-9]{2}$ ]]
}

offset_date() {
  local date_string="$1"
  local days="$2"
  local shifted gnu_modifier sign abs_days

  if ((days < 0)); then
    gnu_modifier="${days} days"
  else
    gnu_modifier="+${days} days"
  fi

  if shifted="$(date -d "${date_string} ${gnu_modifier}" +%F 2>/dev/null)"; then
    printf '%s\n' "$shifted"
    return 0
  fi

  sign="+"
  abs_days="$days"
  if ((days < 0)); then
    sign="-"
    abs_days=$((-days))
  fi

  date -j -v"${sign}${abs_days}d" -f "%F" "$date_string" +%F
}

date_is_valid() {
  local date_string="$1"
  local normalized

  is_date_literal "$date_string" || return 1
  normalized="$(offset_date "$date_string" 0 2>/dev/null)" || return 1

  [[ "$normalized" == "$date_string" ]]
}

weekday_number() {
  local date_string="$1"
  local dow

  if dow="$(date -d "$date_string" +%u 2>/dev/null)"; then
    printf '%s\n' "$dow"
    return 0
  fi

  date -j -f "%F" "$date_string" +%u
}

iso_week_for_date() {
  local date_string="$1"
  local iso_week

  if iso_week="$(date -d "$date_string" +%G-W%V 2>/dev/null)"; then
    printf '%s\n' "$iso_week"
    return 0
  fi

  date -j -f "%F" "$date_string" +%G-W%V
}

week_start_for_date() {
  local date_string="$1"
  local dow offset

  date_is_valid "$date_string" || return 1

  dow="$(weekday_number "$date_string")"
  offset=$((dow - 1))

  if ((offset == 0)); then
    printf '%s\n' "$date_string"
  else
    offset_date "$date_string" "$((-offset))"
  fi
}

week_start_for_iso_week() {
  local week_ref="$1"
  local iso_year iso_week iso_week_number jan4 jan4_dow first_monday week_start

  if [[ ! "$week_ref" =~ ^([0-9]{4})-W([0-9]{2})$ ]]; then
    return 1
  fi

  iso_year="${BASH_REMATCH[1]}"
  iso_week="${BASH_REMATCH[2]}"
  iso_week_number=$((10#${iso_week}))

  if ((iso_week_number < 1 || iso_week_number > 53)); then
    return 1
  fi

  jan4="${iso_year}-01-04"
  jan4_dow="$(weekday_number "$jan4")"
  first_monday="$(offset_date "$jan4" "$((1 - jan4_dow))")"
  week_start="$(offset_date "$first_monday" "$(((iso_week_number - 1) * 7))")"

  [[ "$(iso_week_for_date "$week_start")" == "$week_ref" ]] || return 1
  printf '%s\n' "$week_start"
}

week_start_from_ref() {
  local ref="${1:-}"

  if [[ -z "$ref" ]]; then
    ref="$(today_date)"
  fi

  if is_date_literal "$ref"; then
    week_start_for_date "$ref" || usage_error "invalid date: ${ref}"
    return 0
  fi

  if is_iso_week_ref "$ref"; then
    week_start_for_iso_week "$ref" || usage_error "invalid ISO week: ${ref}"
    return 0
  fi

  usage_error "invalid week reference: ${ref} (expected YYYY-MM-DD or YYYY-Www)"
}

log_file_for_week_start() {
  local week_start="$1"

  printf '%s/%s.log\n' "$TART_LOGDIR" "$week_start"
}

log_file_for_week_ref() {
  local ref="${1:-}"
  local week_start

  week_start="$(week_start_from_ref "$ref")"
  log_file_for_week_start "$week_start"
}

append_tart_entry() {
  local entry="$*"
  local today week_start file

  if [[ -z "${entry//[[:space:]]/}" ]]; then
    usage_error "missing entry message"
  fi

  today="$(today_date)"
  week_start="$(week_start_from_ref "$today")"
  file="$(log_file_for_week_start "$week_start")"

  ensure_tart_dirs
  printf '%s %s\n' "$today" "$entry" >> "$file"
  printf 'Logged: %s %s\n' "$today" "$entry"
}

show_week_entries() {
  local ref="${1:-}"
  local week_start file

  week_start="$(week_start_from_ref "$ref")"
  file="$(log_file_for_week_start "$week_start")"

  if [[ ! -f "$file" ]]; then
    printf 'No entries yet for week %s.\n' "$week_start"
    return 0
  fi

  cat "$file"
}

show_today_entries() {
  local today file

  today="$(today_date)"
  file="$(log_file_for_week_ref "$today")"

  if [[ ! -f "$file" ]]; then
    printf 'No entries yet for today.\n'
    return 0
  fi

  grep -E "^${today} " "$file" || printf 'No entries yet for today.\n'
}

cmd_add() {
  if [[ "${1:-}" == "--" ]]; then
    shift
  fi

  append_tart_entry "$@"
}

cmd_list() {
  local week_ref=""

  while (($# > 0)); do
    case "$1" in
      -h|--help)
        print_usage
        return 0
        ;;
      --week)
        shift
        if [[ -z "${1:-}" ]]; then
          usage_error "missing value for --week"
        fi
        week_ref="$1"
        ;;
      --week=*)
        week_ref="${1#*=}"
        if [[ -z "$week_ref" ]]; then
          usage_error "missing value for --week"
        fi
        ;;
      *)
        usage_error "unexpected argument for list: $1"
        ;;
    esac
    shift
  done

  show_week_entries "$week_ref"
}

cmd_today() {
  require_no_args "today" "$@"
  show_today_entries
}

cmd_week() {
  if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    print_usage
    return 0
  fi

  if (($# > 1)); then
    usage_error "week accepts at most one reference"
  fi

  show_week_entries "${1:-}"
}

cmd_path() {
  if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    print_usage
    return 0
  fi

  if (($# > 1)); then
    usage_error "path accepts at most one reference"
  fi

  log_file_for_week_ref "${1:-}"
}

cmd_init() {
  require_no_args "init" "$@"
  ensure_tart_dirs
  printf 'Initialized tart log directory: %s\n' "$TART_LOGDIR"
}

cmd_config() {
  local current_week current_file

  require_no_args "config" "$@"
  current_week="$(week_start_from_ref)"
  current_file="$(log_file_for_week_start "$current_week")"

  printf 'version=%s\n' "$TART_VERSION"
  printf 'log_dir=%s\n' "$TART_LOGDIR"
  printf 'current_week=%s\n' "$current_week"
  printf 'current_file=%s\n' "$current_file"
}

parse_global_options() {
  while (($# > 0)); do
    case "$1" in
      --log-dir)
        shift
        if [[ -z "${1:-}" ]]; then
          usage_error "missing value for --log-dir"
        fi
        TART_LOGDIR="$1"
        ;;
      --log-dir=*)
        TART_LOGDIR="${1#*=}"
        if [[ -z "$TART_LOGDIR" ]]; then
          usage_error "missing value for --log-dir"
        fi
        ;;
      --)
        shift
        TART_FORCE_ADD=1
        TART_ARGS=("$@")
        return 0
        ;;
      *)
        break
        ;;
    esac
    shift
  done

  TART_ARGS=("$@")
}

main() {
  parse_global_options "$@"
  set -- "${TART_ARGS[@]}"

  if [[ "$TART_FORCE_ADD" == "1" ]]; then
    cmd_add "$@"
    return 0
  fi

  local command="${1:-list}"

  case "$command" in
    -h|--help|help|\?)
      print_usage
      ;;
    -v|--version|version)
      print_version
      ;;
    -t|--today)
      shift
      require_no_args "today" "$@"
      show_today_entries
      ;;
    -tw|--this-week)
      shift
      require_no_args "this-week" "$@"
      show_week_entries
      ;;
    --week)
      shift
      if [[ -z "${1:-}" ]]; then
        usage_error "missing value for --week"
      fi
      cmd_week "$@"
      ;;
    add|log)
      shift
      cmd_add "$@"
      ;;
    list|show)
      shift
      cmd_list "$@"
      ;;
    today)
      shift
      cmd_today "$@"
      ;;
    week)
      shift
      cmd_week "$@"
      ;;
    path)
      shift
      cmd_path "$@"
      ;;
    init)
      shift
      cmd_init "$@"
      ;;
    config|doctor)
      shift
      cmd_config "$@"
      ;;
    --*|-*)
      usage_error "unknown option: ${command}"
      ;;
    *)
      cmd_add "$@"
      ;;
  esac
}

main "$@"
