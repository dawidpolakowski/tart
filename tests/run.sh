#!/usr/bin/env bash
set -u

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TART_BIN="${ROOT_DIR}/tart.sh"
TEST_TODAY="2026-04-30"
TEST_WEEK_START="2026-04-27"

PASS_COUNT=0
FAIL_COUNT=0
LAST_OUTPUT=""
LAST_STATUS=0
TEST_TMPDIR=""

new_log_dir() {
  mktemp -d "${TMPDIR:-/private/tmp}/tart-test.XXXXXX"
}

cleanup_log_dir() {
  if [[ -n "${TEST_TMPDIR:-}" && -d "$TEST_TMPDIR" ]]; then
    rm -rf "$TEST_TMPDIR"
  fi
}

run_tart() {
  local log_dir="$1"
  shift

  LAST_OUTPUT="$(TART_LOGDIR="$log_dir" TART_TODAY="$TEST_TODAY" "$TART_BIN" "$@" 2>&1)"
  LAST_STATUS=$?
}

assert_status() {
  local expected="$1"

  if [[ "$LAST_STATUS" -ne "$expected" ]]; then
    printf 'expected status %s, got %s\noutput:\n%s\n' "$expected" "$LAST_STATUS" "$LAST_OUTPUT" >&2
    return 1
  fi
}

assert_eq() {
  local expected="$1"
  local actual="$2"

  if [[ "$actual" != "$expected" ]]; then
    printf 'expected:\n%s\nactual:\n%s\n' "$expected" "$actual" >&2
    return 1
  fi
}

assert_contains() {
  local haystack="$1"
  local needle="$2"

  if [[ "$haystack" != *"$needle"* ]]; then
    printf 'expected output to contain:\n%s\nactual:\n%s\n' "$needle" "$haystack" >&2
    return 1
  fi
}

assert_file_exists() {
  local path="$1"

  if [[ ! -f "$path" ]]; then
    printf 'expected file to exist: %s\n' "$path" >&2
    return 1
  fi
}

assert_file_eq() {
  local path="$1"
  local expected="$2"
  local actual

  assert_file_exists "$path" || return 1
  actual="$(<"$path")"
  assert_eq "$expected" "$actual"
}

write_week_log() {
  local log_dir="$1"
  local content="$2"

  mkdir -p "$log_dir"
  printf '%s\n' "$content" > "${log_dir}/${TEST_WEEK_START}.log"
}

test_help_and_version() {
  run_tart "$TEST_TMPDIR" help
  assert_status 0 || return 1
  assert_contains "$LAST_OUTPUT" "Usage:" || return 1
  assert_contains "$LAST_OUTPUT" "Commands:" || return 1

  run_tart "$TEST_TMPDIR" version
  assert_status 0 || return 1
  assert_eq "tart 0.2.0" "$LAST_OUTPUT"
}

test_init_creates_log_dir() {
  run_tart "$TEST_TMPDIR" init
  assert_status 0 || return 1
  assert_eq "Initialized tart log directory: ${TEST_TMPDIR}" "$LAST_OUTPUT" || return 1

  if [[ ! -d "$TEST_TMPDIR" ]]; then
    printf 'expected log directory to exist: %s\n' "$TEST_TMPDIR" >&2
    return 1
  fi
}

test_add_writes_to_current_week_file() {
  run_tart "$TEST_TMPDIR" add implemented enterprise tests
  assert_status 0 || return 1
  assert_eq "Logged: ${TEST_TODAY} implemented enterprise tests" "$LAST_OUTPUT" || return 1
  assert_file_eq "${TEST_TMPDIR}/${TEST_WEEK_START}.log" "${TEST_TODAY} implemented enterprise tests"
}

test_quick_add_remains_backwards_compatible() {
  run_tart "$TEST_TMPDIR" quick compatibility entry
  assert_status 0 || return 1
  assert_eq "Logged: ${TEST_TODAY} quick compatibility entry" "$LAST_OUTPUT" || return 1
  assert_file_eq "${TEST_TMPDIR}/${TEST_WEEK_START}.log" "${TEST_TODAY} quick compatibility entry"
}

test_dash_prefixed_messages_are_supported() {
  run_tart "$TEST_TMPDIR" -- -dash-prefixed note
  assert_status 0 || return 1
  assert_eq "Logged: ${TEST_TODAY} -dash-prefixed note" "$LAST_OUTPUT" || return 1
  assert_file_eq "${TEST_TMPDIR}/${TEST_WEEK_START}.log" "${TEST_TODAY} -dash-prefixed note"
}

test_list_defaults_to_current_week() {
  write_week_log "$TEST_TMPDIR" "${TEST_TODAY} reviewed command dispatch"

  run_tart "$TEST_TMPDIR"
  assert_status 0 || return 1
  assert_eq "${TEST_TODAY} reviewed command dispatch" "$LAST_OUTPUT" || return 1

  run_tart "$TEST_TMPDIR" list
  assert_status 0 || return 1
  assert_eq "${TEST_TODAY} reviewed command dispatch" "$LAST_OUTPUT"
}

test_today_filters_current_date() {
  write_week_log "$TEST_TMPDIR" "2026-04-29 previous day
${TEST_TODAY} current day"

  run_tart "$TEST_TMPDIR" today
  assert_status 0 || return 1
  assert_eq "${TEST_TODAY} current day" "$LAST_OUTPUT" || return 1

  run_tart "$TEST_TMPDIR" --today
  assert_status 0 || return 1
  assert_eq "${TEST_TODAY} current day" "$LAST_OUTPUT"
}

test_week_references_normalize_to_monday() {
  local expected_path="${TEST_TMPDIR}/${TEST_WEEK_START}.log"

  run_tart "$TEST_TMPDIR" path 2026-04-30
  assert_status 0 || return 1
  assert_eq "$expected_path" "$LAST_OUTPUT" || return 1

  run_tart "$TEST_TMPDIR" path 2026-W18
  assert_status 0 || return 1
  assert_eq "$expected_path" "$LAST_OUTPUT" || return 1

  write_week_log "$TEST_TMPDIR" "${TEST_TODAY} normalized ISO week"
  run_tart "$TEST_TMPDIR" list --week 2026-W18
  assert_status 0 || return 1
  assert_eq "${TEST_TODAY} normalized ISO week" "$LAST_OUTPUT"
}

test_legacy_week_aliases() {
  write_week_log "$TEST_TMPDIR" "${TEST_TODAY} legacy alias entry"

  run_tart "$TEST_TMPDIR" --this-week
  assert_status 0 || return 1
  assert_eq "${TEST_TODAY} legacy alias entry" "$LAST_OUTPUT" || return 1

  run_tart "$TEST_TMPDIR" --week 2026-04-30
  assert_status 0 || return 1
  assert_eq "${TEST_TODAY} legacy alias entry" "$LAST_OUTPUT"
}

test_config_uses_resolved_values() {
  local expected="version=0.2.0
log_dir=${TEST_TMPDIR}
current_week=${TEST_WEEK_START}
current_file=${TEST_TMPDIR}/${TEST_WEEK_START}.log"

  run_tart "$TEST_TMPDIR" config
  assert_status 0 || return 1
  assert_eq "$expected" "$LAST_OUTPUT"
}

test_global_log_dir_overrides_environment() {
  local override_dir
  override_dir="${TEST_TMPDIR}/override"

  run_tart "$TEST_TMPDIR" --log-dir "$override_dir" add overridden directory
  assert_status 0 || return 1
  assert_eq "Logged: ${TEST_TODAY} overridden directory" "$LAST_OUTPUT" || return 1
  assert_file_eq "${override_dir}/${TEST_WEEK_START}.log" "${TEST_TODAY} overridden directory"
}

test_invalid_date_returns_usage_error() {
  run_tart "$TEST_TMPDIR" path 2026-02-30
  assert_status 2 || return 1
  assert_contains "$LAST_OUTPUT" "invalid date: 2026-02-30"
}

test_invalid_iso_week_returns_usage_error() {
  run_tart "$TEST_TMPDIR" path 2021-W53
  assert_status 2 || return 1
  assert_contains "$LAST_OUTPUT" "invalid ISO week: 2021-W53"
}

test_missing_add_message_returns_usage_error() {
  run_tart "$TEST_TMPDIR" add
  assert_status 2 || return 1
  assert_contains "$LAST_OUTPUT" "missing entry message"
}

run_test() {
  local name="$1"
  local fn="$2"

  TEST_TMPDIR="$(new_log_dir)"
  printf 'test %-48s' "$name"

  if "$fn"; then
    PASS_COUNT=$((PASS_COUNT + 1))
    printf 'ok\n'
  else
    FAIL_COUNT=$((FAIL_COUNT + 1))
    printf 'FAIL\n'
  fi

  cleanup_log_dir
  TEST_TMPDIR=""
}

main() {
  run_test "help and version" test_help_and_version
  run_test "init creates log dir" test_init_creates_log_dir
  run_test "add writes to current week file" test_add_writes_to_current_week_file
  run_test "quick add remains compatible" test_quick_add_remains_backwards_compatible
  run_test "dash-prefixed messages" test_dash_prefixed_messages_are_supported
  run_test "list defaults to current week" test_list_defaults_to_current_week
  run_test "today filters current date" test_today_filters_current_date
  run_test "week refs normalize to Monday" test_week_references_normalize_to_monday
  run_test "legacy week aliases" test_legacy_week_aliases
  run_test "config uses resolved values" test_config_uses_resolved_values
  run_test "global log dir override" test_global_log_dir_overrides_environment
  run_test "invalid date errors" test_invalid_date_returns_usage_error
  run_test "invalid ISO week errors" test_invalid_iso_week_returns_usage_error
  run_test "missing add message errors" test_missing_add_message_returns_usage_error

  printf '\n%s passed, %s failed\n' "$PASS_COUNT" "$FAIL_COUNT"

  if ((FAIL_COUNT > 0)); then
    return 1
  fi
}

main "$@"
