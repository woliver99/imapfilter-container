#!/bin/sh
set -eu

DEFAULT_ENGINE="/usr/local/share/imapfilter/engine.lua"
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

# Resolve configuration file (user override vs built-in modular engine)
if [ ! -f "$CONFIG_FILE" ]; then
    if [ -f "$DEFAULT_ENGINE" ]; then
        CONFIG_FILE="$DEFAULT_ENGINE"
        log "Using built-in modular rule engine ($CONFIG_FILE)"
    else
        log "ERROR: Configuration file not found at $CONFIG_FILE"
        exit 1
    fi
else
    log "Using mounted configuration file ($CONFIG_FILE)"
fi

log "Starting email cleanup loop (interval: ${INTERVAL}s)..."

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
