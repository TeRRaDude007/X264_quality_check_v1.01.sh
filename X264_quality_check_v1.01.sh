#!/bin/bash
###############################################################################
# TeRRaDude X264_QUALITY_CHECK.sh
#
# Version: 1.0.1
# Date: 2026-11-08
#
# Description:
# Check X264-1080P for releases with inferior codecs when a BluRay.x264
# version of the same movie is available.
#
# Rules:
# - BluRay.H264 is moved when BluRay.x264 exists.
# - WEB.h264 is moved when BluRay.x264 exists.
# - BluRay.x264 is always kept.
# - Releases without a matching BluRay.x264 are left untouched.
#
# Features:
# - SANDBOX_MODE for testing without moving files.
# - Case-insensitive release matching.
# - Movie title, year and resolution matching.
# - Automatic destination directory creation.
# - Destination ownership root:root and permissions 755.
# - Skip directories starting with [NUKED]-.
# - Logging and statistics.
#
# Install & Use:
# - Complete the configuration.
# - chmod +x /glftpd/bin/X264_QUALITY_CHECK.sh.
# - Optional Cron: 0 4 * * * /glftpd/bin/X264_QUALITY_CHECK.sh >/dev/null 2>&1.
#
###############################################################################

# ========================= CONFIGURATION ====================================

SITE_DIR="/glftpd/site/X264-1080P"

DEST_DIR="$SITE_DIR/Better_quality_avalable"

LOG_FILE="/glftpd/ftp-data/logs/x264_quality_check.log"

# SANDBOX_MODE:
# true  = Simulation only (no files moved)
# false = Actually move files

SANDBOX_MODE=false

# Logging
ENABLE_LOGGING=true

# ========================= VARIABLES ========================================

VERSION="1.0.1"

STATS_SCANNED=0
STATS_MOVED=0
STATS_SKIPPED=0
STATS_MATCHED=0

# ========================= FUNCTIONS ========================================

log_message() {

    local MESSAGE="$1"
    local TIMESTAMP

    TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')

    echo "[$TIMESTAMP] $MESSAGE"

    if [[ "$ENABLE_LOGGING" == true ]]; then
        mkdir -p "$(dirname "$LOG_FILE")"
        echo "[$TIMESTAMP] $MESSAGE" >> "$LOG_FILE"
    fi
}

# Normalize release name for comparison.
# Remove release group, source and codec identifiers.

normalize_release() {

    local NAME="$1"

    NAME="${NAME,,}"

    # Remove release group
    NAME=$(printf '%s' "$NAME" | sed -E 's/-[^-]+$//')

    # Remove source and codec identifiers
    NAME=$(printf '%s' "$NAME" | perl -pe '
        s/(^|[._-])(bluray|web-dl|webrip|web|h264|x264)(?=[._-]|$)/$1/ig;
    ')

    # Normalize separators
    NAME=$(printf '%s' "$NAME" | sed -E '
        s/[._-]+/./g;
        s/^\.//;
        s/\.$//;
    ')

    echo "$NAME"
}

# Check if release is an inferior BluRay.H264 release.

is_bluray_h264() {

    local NAME="${1,,}"

    [[ "$NAME" =~ \.bluray\.h264(-|$) ]]
}

# Check if release is an inferior WEB.h264 release.

is_web_h264() {

    local NAME="${1,,}"

    [[ "$NAME" =~ \.web\.h264(-|$) ]]
}

# Check if release is a preferred BluRay.x264 release.

is_bluray_x264() {

    local NAME="${1,,}"

    [[ "$NAME" =~ \.bluray\.x264(-|$) ]]
}

# ========================= MAIN =============================================

main() {

    echo
    echo "=========================================================="
    echo " X264 QUALITY CHECK v$VERSION"
    echo "=========================================================="

    if [[ "$SANDBOX_MODE" == true ]]; then
        log_message "SANDBOX MODE ENABLED - No files will be moved."
    else
        log_message "LIVE MODE ENABLED - Files may be moved."
    fi

    if [[ ! -d "$SITE_DIR" ]]; then
        log_message "ERROR: Site directory does not exist: $SITE_DIR"
        exit 1
    fi

    log_message "Scanning directory: $SITE_DIR"

    # Collect all release directories.
    # Skip directories starting with [NUKED]-.

    mapfile -d '' RELEASES < <(
        find "$SITE_DIR" \
            -mindepth 1 \
            -maxdepth 1 \
            -type d \
            ! -path "$DEST_DIR" \
            ! -name '[NUKED]-*' \
            -print0
    )

    STATS_SCANNED=${#RELEASES[@]}

    log_message "Found $STATS_SCANNED release directories."

    # Process each release.
    for RELEASE_PATH in "${RELEASES[@]}"; do

        RELEASE_NAME=$(basename "$RELEASE_PATH")

        # Only inspect inferior releases.
        if ! is_bluray_h264 "$RELEASE_NAME" &&
           ! is_web_h264 "$RELEASE_NAME"; then

            continue
        fi

        RELEASE_KEY=$(normalize_release "$RELEASE_NAME")

        log_message "Checking: $RELEASE_NAME"
        log_message "Normalized key: $RELEASE_KEY"

        MATCH_FOUND=false

        # Search for a matching BluRay.x264 release.
        for OTHER_PATH in "${RELEASES[@]}"; do

            [[ "$OTHER_PATH" == "$RELEASE_PATH" ]] && continue

            OTHER_NAME=$(basename "$OTHER_PATH")

            if ! is_bluray_x264 "$OTHER_NAME"; then
                continue
            fi

            OTHER_KEY=$(normalize_release "$OTHER_NAME")

            if [[ "$RELEASE_KEY" == "$OTHER_KEY" ]]; then

                MATCH_FOUND=true
                MATCH_RELEASE="$OTHER_NAME"
                break

            fi

        done

        # No preferred release available.
        if [[ "$MATCH_FOUND" == false ]]; then

            log_message "KEEP: No matching BluRay.x264 found: $RELEASE_NAME"

            ((STATS_SKIPPED++))
            continue

        fi

        ((STATS_MATCHED++))

        log_message "MATCH FOUND: $RELEASE_NAME"
        log_message "BETTER VERSION: $MATCH_RELEASE"

        # SANDBOX MODE.
        if [[ "$SANDBOX_MODE" == true ]]; then

            log_message "[SANDBOX] WOULD MOVE: $RELEASE_NAME"
            log_message "[SANDBOX] DESTINATION: $DEST_DIR/"

            ((STATS_MOVED++))
            continue

        fi

        # Create destination directory only when required.
        if [[ ! -d "$DEST_DIR" ]]; then

            mkdir -p "$DEST_DIR" || {
                log_message "ERROR: Could not create destination directory."
                ((STATS_SKIPPED++))
                continue
            }

            # Set destination ownership and permissions.
            chown root:root "$DEST_DIR"
            chmod 755 "$DEST_DIR"

            log_message "Created destination directory: $DEST_DIR"
            log_message "Destination ownership set to root:root"
            log_message "Destination permissions set to 755"

        fi

        # Prevent overwriting existing directories.
        if [[ -e "$DEST_DIR/$RELEASE_NAME" ]]; then

            log_message "SKIP: Destination already exists: $RELEASE_NAME"

            ((STATS_SKIPPED++))
            continue

        fi

        # Move inferior release.
        if mv -- "$RELEASE_PATH" "$DEST_DIR/"; then

            log_message "MOVED: $RELEASE_NAME"
            ((STATS_MOVED++))

        else

            log_message "ERROR: Failed to move: $RELEASE_NAME"
            ((STATS_SKIPPED++))

        fi

    done

    # ========================= STATISTICS ================================

    echo
    echo "=========================================================="
    echo " X264 QUALITY CHECK - RESULTS"
    echo "=========================================================="

    echo "Version:             $VERSION"
    echo "Sandbox mode:        $SANDBOX_MODE"
    echo "Scanned:             $STATS_SCANNED"
    echo "Matches found:       $STATS_MATCHED"
    echo "Moved / Would move:  $STATS_MOVED"
    echo "Skipped:             $STATS_SKIPPED"

    echo "=========================================================="

    log_message "Scan completed."

}

# ========================= EXECUTION ========================================

main "$@"

###############################################################################
# END OF SCRIPT
###############################################################################
