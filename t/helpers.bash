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
RESET='\033[0m'

# Threshold constants (must match statusline.sh)
FIVE_HOUR_COUNTDOWN_SECS=7200
FIVE_HOUR_RECOVERY_SECS=1800
SEVEN_DAY_COUNTDOWN_SECS=259200
SEVEN_DAY_RECOVERY_SECS=43200
EXTRA_AUTO_UTIL_PCT=50

debug_log() {
    :
}

# Source individual functions by extracting them from statusline.sh.
# This is deliberate: we test the actual production code, not copies.
eval "$(awk '
    /^(abbreviate_model_id|format_reset_relative|get_reset_seconds|format_duration|should_show_extra|get_usage_color|get_seven_day_color|get_adaptive_ttl|render_bar|format_money_minor|oauth_token_expired|refresh_oauth_credentials_file|get_context_limit|is_1m_model|build_display_path|build_usage_display|build_extra_usage_display|build_user_info|get_user_tier)\(\)/ { capture=1 }
    capture { print }
    capture && /^}$/ { capture=0 }
' "$SCRIPT_DIR/statusline.sh")"

strip_ansi() {
    printf '%b' "$1" | sed 's/\x1b\[[0-9;]*m//g'
}
