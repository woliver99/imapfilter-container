#!/bin/sh
set -eu

CONFIG_FILE="${IMAPFILTER_CONFIG:-/config/config.lua}"
INTERVAL="${CHECK_INTERVAL:-600}"

log() {
    printf '%s [imapfilter] %s\n' "$(date -u +'%Y-%m-%d %H:%M:%S UTC')" "$*"
}

term_handler() {
    log "Received termination signal. Exiting gracefully..."
    exit 0
}

trap term_handler TERM INT

log "Starting email cleanup loop (interval: ${INTERVAL}s)..."

if [ ! -f "$CONFIG_FILE" ]; then
    log "ERROR: Configuration file not found at $CONFIG_FILE"
    exit 1
fi

while true; do
    log "Running imapfilter..."
    if /usr/local/bin/imapfilter -c "$CONFIG_FILE"; then
        log "imapfilter run completed successfully."
    else
        log "imapfilter exited with status code $?."
    fi
    log "Sleeping for ${INTERVAL}s until next check..."
    sleep "$INTERVAL" &
    wait $!
done
