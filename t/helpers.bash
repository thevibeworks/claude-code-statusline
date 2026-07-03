#!/bin/bash
# Test helper: sources statusline functions without running the main script.
# Bats tests source this file to get access to all functions.

STATUSLINE_TESTING=1
export STATUSLINE_TESTING

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Color constants (needed by functions)
YELLOW='\033[0;33m'
GREEN='\033[0;32m'
RED='\033[0;31m'
DIM='\033[2m'
DIM_GREEN='\033[2;32m'
DIM_RED='\033[2;31m'
DIM_YELLOW='\033[2;33m'
CYAN='\033[0;36m'
DIM_CYAN='\033[2;36m'
BOLD='\033[22;1m'
NO_BOLD='\033[22m'
RESET='\033[0m'

# Threshold constants (must match statusline.sh)
FIVE_HOUR_RECOVERY_SECS=1800
SEVEN_DAY_RECOVERY_SECS=43200
QUOTA_BUMP_NOTICE_SECS=60
SEVEN_DAY_WINDOW_SECS=604800
EXTRA_AUTO_UTIL_PCT=50
CACHE_BREAK_MIN_TOKENS=2000
CACHE_BREAK_DROP_PCT=5
DEBUG_LOG_MAX_BYTES=1048576
USAGE_LOG_MAX_BYTES=33554432

debug_log() {
    :
}

# Source individual functions by extracting them from statusline.sh.
# This is deliberate: we test the actual production code, not copies.
eval "$(awk '
    /^(abbreviate_model_id|get_runtime_model|format_reset_relative|get_reset_seconds|format_duration|should_show_extra|get_cache_health|infer_cache_ttl_class|format_cache_active_time|build_cache_indicator|get_usage_color|get_seven_day_color|seven_day_elapsed|seven_day_pace|weekend_secs_ahead|get_adaptive_ttl|reap_stale_lock|merge_stdin_rate_limits|rotate_usage_log|build_seven_day_profile|seven_day_forecast|premium_band_level|abbrev_effort|effort_color|_epoch_from_ts|_fmt_epoch|render_bar|format_money_minor|oauth_token_expired|refresh_oauth_credentials_file|is_default_1m_family|get_context_limit|is_1m_model|rotate_debug_log|build_display_path|quota_bump_notice|build_usage_display|build_extra_usage_display|build_user_info|get_user_tier)\(\)/ { capture=1 }
    capture { print }
    capture && /^}$/ { capture=0 }
' "$SCRIPT_DIR/statusline.sh")"

strip_ansi() {
    printf '%b' "$1" | sed 's/\x1b\[[0-9;]*m//g'
}
