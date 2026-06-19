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
  local candidate base

  for candidate in "${TMPDIR:-}" "${TMP:-}" "${TEMP:-}" /tmp /private/tmp; do
    if [[ -n "$candidate" && -d "$candidate" ]]; then
      base="${candidate%/}"
      mktemp -d "${base}/tart-test.XXXXXX"
      return
    fi
  done

  printf 'no usable temporary directory found\n' >&2
  return 1
}

cleanup_log_dir() {
  if [[ -n "${TEST_TMPDIR:-}" && -d "$TEST_TMPDIR" ]]; then
    rm -rf "$TEST_TMPDIR"
  fi
}

run_tart() {
  local log_dir="$1"
  shift

  if [[ -z "$log_dir" ]]; then
    LAST_OUTPUT="test harness error: empty log directory"
    LAST_STATUS=99
    return
  fi

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

assert_file_nonempty() {
  local path="$1"

  assert_file_exists "$path" || return 1

  if [[ ! -s "$path" ]]; then
    printf 'expected file to be non-empty: %s\n' "$path" >&2
    return 1
  fi
}

assert_file_missing() {
  local path="$1"

  if [[ -e "$path" ]]; then
    printf 'expected path to be missing: %s\n' "$path" >&2
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

  if [[ -z "$log_dir" ]]; then
    printf 'test harness error: empty log directory\n' >&2
    return 1
  fi

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

test_command_help_aliases_are_consistent() {
  run_tart "$TEST_TMPDIR" add --help
  assert_status 0 || return 1
  assert_contains "$LAST_OUTPUT" "Commands:" || return 1
  assert_file_missing "${TEST_TMPDIR}/${TEST_WEEK_START}.log" || return 1

  run_tart "$TEST_TMPDIR" today --help
  assert_status 0 || return 1
  assert_contains "$LAST_OUTPUT" "Usage:" || return 1

  run_tart "$TEST_TMPDIR" init --help
  assert_status 0 || return 1
  assert_contains "$LAST_OUTPUT" "Global options:" || return 1

  run_tart "$TEST_TMPDIR" config --help
  assert_status 0 || return 1
  assert_contains "$LAST_OUTPUT" "Environment:" || return 1

  run_tart "$TEST_TMPDIR" version --help
  assert_status 0 || return 1
  assert_contains "$LAST_OUTPUT" "Usage:" || return 1
}

test_help_and_version_reject_extra_args() {
  run_tart "$TEST_TMPDIR" help extra
  assert_status 2 || return 1
  assert_contains "$LAST_OUTPUT" "help does not accept arguments" || return 1

  run_tart "$TEST_TMPDIR" version extra
  assert_status 2 || return 1
  assert_contains "$LAST_OUTPUT" "version does not accept arguments"
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

test_multiline_add_message_returns_usage_error() {
  run_tart "$TEST_TMPDIR" add $'first line\nsecond line'
  assert_status 2 || return 1
  assert_contains "$LAST_OUTPUT" "entry message must be a single line" || return 1
  assert_file_missing "${TEST_TMPDIR}/${TEST_WEEK_START}.log"
}

test_desktop_core_suite() {
  node "${ROOT_DIR}/tests/test_desktop_core.mjs"
}

test_desktop_renderer_suite() {
  node "${ROOT_DIR}/tests/test_desktop_renderer.mjs"
}

test_desktop_icon_assets_exist() {
  assert_file_nonempty "${ROOT_DIR}/assets/tart-clock-icon.png" || return 1
  assert_file_nonempty "${ROOT_DIR}/assets/tart-clock-icon.icns" || return 1
  assert_file_nonempty "${ROOT_DIR}/assets/tart-clock-icon.ico"
}

test_project_base_generator_smoke() {
  local target_dir package_json readme_html

  target_dir="${TEST_TMPDIR}/focus-journal"

  "${ROOT_DIR}/scripts/create-project-base.sh" "Focus Journal" "$target_dir" >/dev/null || return 1

  assert_file_nonempty "${target_dir}/package.json" || return 1
  assert_file_nonempty "${target_dir}/README.md" || return 1
  assert_file_nonempty "${target_dir}/desktop/main.cjs" || return 1
  assert_file_nonempty "${target_dir}/desktop/app-core.cjs" || return 1
  assert_file_nonempty "${target_dir}/desktop/index.html" || return 1
  assert_file_nonempty "${target_dir}/assets/app-icon.png" || return 1

  package_json="$(<"${target_dir}/package.json")"
  assert_contains "$package_json" '"name": "focus-journal"' || return 1
  assert_contains "$package_json" '"description": "Focus Journal desktop starter generated from tart"' || return 1

  readme_html="$(<"${target_dir}/README.md")"
  assert_contains "$readme_html" '# Focus Journal' || return 1
  assert_contains "$readme_html" '~/Documents/focus-journal' || return 1
}

test_macos_installer_smoke() {
  local app_dir bin_dir output support_dir

  if [[ "$(uname -s)" != "Darwin" ]]; then
    return 0
  fi

  bin_dir="${TEST_TMPDIR}/bin"
  app_dir="${TEST_TMPDIR}/Applications"
  support_dir="${TEST_TMPDIR}/Application Support/tart"

  output="$(
    TART_INSTALL_DIR="$bin_dir" \
      TART_MACOS_APP_DIR="$app_dir" \
      TART_MACOS_SUPPORT_DIR="$support_dir" \
      TART_SKIP_NPM_INSTALL=1 \
      "${ROOT_DIR}/scripts/install-macos.sh" 2>&1
  )" || {
    printf '%s\n' "$output" >&2
    return 1
  }

  assert_file_nonempty "${bin_dir}/tart" || return 1
  assert_file_nonempty "${support_dir}/tart-desktop" || return 1
  assert_file_nonempty "${support_dir}/desktop/main.cjs" || return 1
  assert_file_nonempty "${app_dir}/tart.app/Contents/MacOS/tart" || return 1
  assert_file_nonempty "${app_dir}/tart.app/Contents/Info.plist" || return 1
  assert_file_nonempty "${app_dir}/tart.app/Contents/Resources/tart-clock-icon.icns" || return 1

  assert_eq "tart 0.2.0" "$("${bin_dir}/tart" version)"
}

run_test() {
  local name="$1"
  local fn="$2"

  printf 'test %-48s' "$name"
  if ! TEST_TMPDIR="$(new_log_dir)"; then
    FAIL_COUNT=$((FAIL_COUNT + 1))
    printf 'FAIL\n'
    return
  fi

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
  run_test "command help aliases" test_command_help_aliases_are_consistent
  run_test "help/version extra args" test_help_and_version_reject_extra_args
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
  run_test "multiline add message errors" test_multiline_add_message_returns_usage_error
  run_test "desktop core suite" test_desktop_core_suite
  run_test "desktop renderer suite" test_desktop_renderer_suite
  run_test "desktop icon assets" test_desktop_icon_assets_exist
  run_test "project base generator" test_project_base_generator_smoke
  run_test "macOS installer smoke" test_macos_installer_smoke

  printf '\n%s passed, %s failed\n' "$PASS_COUNT" "$FAIL_COUNT"

  if ((FAIL_COUNT > 0)); then
    return 1
  fi
}

main "$@"
