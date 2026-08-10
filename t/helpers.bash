#!/bin/bash
# Test helper: sources statusline functions without running the main script.
# Bats tests source this file to get access to all functions.

STATUSLINE_TESTING=1
export STATUSLINE_TESTING

# Integration tests run the real script against isolated tmp dirs, but $HOME
# (and so real credentials) leaks through — without this, a bare cache dir
# makes the script fire REAL API fetches whose background writes race test
# teardown. Function-level fetch tests are unaffected: the guard sits in the
# script's main flow, not inside the fetch functions.
STATUSLINE_NO_FETCH=1
export STATUSLINE_NO_FETCH

# Account identity must come from each test, not the host: deva exports
# DEVA_AUTH_TAG (and DEVA_AUTH_METHOD/DETAILS, which the pre-v0.18-deva
# fallback also resolves) inside its containers — any of them leaking in
# would add an account chip and rescope cache dirs in every integration run.
unset DEVA_AUTH_TAG DEVA_AUTH_METHOD DEVA_AUTH_DETAILS STATUSLINE_ACCOUNT ACCOUNT_TAG

# Trace identity must come from each test too: a test host running under
# `deva --trace` / cctrace (this repo's own dev loop, literally) carries the
# capture env and a live instance registry — leaking either in would put a
# [cctrace:PORT] chip into every integration render.
unset CCTRACE_SERVER_PORT CCTRACE_TRACE_FILE CCTRACE_INSTANCE_ID CCTRACE_DATA_DIR DEVA_TRACE NODE_EXTRA_CA_CERTS

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Color constants (needed by functions)
YELLOW='\033[0;33m'
GREEN='\033[0;32m'
RED='\033[0;31m'
BOLD_RED='\033[1;31m'
DIM='\033[2m'
DIM_GREEN='\033[2;32m'
DIM_RED='\033[2;31m'
DIM_YELLOW='\033[2;33m'
CYAN='\033[0;36m'
DIM_CYAN='\033[2;36m'
REVERSE='\033[7m'
NO_REVERSE='\033[27m'
RESET='\033[0m'

# Threshold constants (must match statusline.sh)
FIVE_HOUR_RECOVERY_SECS=1800
SEVEN_DAY_RECOVERY_SECS=43200
QUOTA_BUMP_NOTICE_SECS=60
SEVEN_DAY_WINDOW_SECS=604800
EXTRA_AUTO_UTIL_PCT=50
CACHE_BREAK_MIN_TOKENS=2000
CACHE_BREAK_DROP_PCT=5
CACHE_TTL_DEFAULT="1h"
CACHE_HEAVY_TOKENS=200000
CACHE_GLYPH="≡"
ADVISOR_PACE_MIN_ELAPSED=900
ADVISOR_FLEET_FRESH_SECS=3600
ADVISOR_FLEET_FREE_PCT=40
ADVISOR_EXPIRY_HORIZON_SECS=86400
ADVISOR_SURPLUS_MIN_PCT=30
ADVISOR_UNDERUSE_END_PCT=60
ADVISOR_UNDERUSE_MIN_5H=25
DEBUG_LOG_MAX_BYTES=1048576
USAGE_LOG_MAX_BYTES=33554432

debug_log() {
    :
}

# Source individual functions by extracting them from statusline.sh.
# This is deliberate: we test the actual production code, not copies.
eval "$(awk '
    /^(abbreviate_model_id|get_runtime_model|format_reset_relative|format_reset_absolute|get_reset_seconds|format_duration|should_show_extra|get_cache_health|infer_cache_ttl_class|build_cache_indicator|get_usage_color|get_seven_day_color|seven_day_elapsed|seven_day_pace|weekend_secs_ahead|get_adaptive_ttl|curl_ca_bundle|acquire_lock|reap_stale_lock|fetch_usage_for_session|merge_stdin_rate_limits|rotate_usage_log|build_seven_day_profile|seven_day_forecast|premium_band_level|abbrev_effort|effort_color|_epoch_from_ts|_fmt_epoch|render_bar|format_money_minor|oauth_token_expired|refresh_oauth_credentials_file|is_default_1m_family|get_context_limit|is_1m_model|rotate_debug_log|build_display_path|build_trace_component|delta_flash|delta_flash_part|quota_bump_notice|record_fetch_error|fetch_error_remaining|fetch_error_badge|model_scope_abbrev|build_scoped_quota_display|build_usage_display|build_extra_usage_display|build_user_info|get_user_tier|build_advisor_line|build_advisor_fleet_hint|_seven_day_walk|forecast_pct_per_window|log_usage_snapshot|detect_session_boundary|last_logged_model|run_usage_report|run_check|run_session_summary|run_week)\(\)/ { capture=1 }
    capture { print }
    capture && /^}$/ { capture=0 }
' "$SCRIPT_DIR/statusline.sh")"

strip_ansi() {
    printf '%b' "$1" | sed 's/\x1b\[[0-9;]*m//g'
}
