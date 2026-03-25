#!/bin/bash

# lan_sync_core Autonomous Development Script
# Runs iteratively to build the package from architecture to completion

set -e

PROJECT_DIR="$HOME/.openclaw/workspace/lan_sync_core"
AUTONOMOUS_DIR="$PROJECT_DIR/.autonomous"
STATE_FILE="$AUTONOMOUS_DIR/state.json"
LOCK_FILE="$AUTONOMOUS_DIR/work.lock"
LOG_FILE="$AUTONOMOUS_DIR/work.log"

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

log() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1" | tee -a "$LOG_FILE"
}

warn() {
    echo -e "${YELLOW}[$(date '+%Y-%m-%d %H:%M:%S')] WARNING:${NC} $1" | tee -a "$LOG_FILE"
}

error() {
    echo -e "${RED}[$(date '+%Y-%m-%d %H:%M:%S')] ERROR:${NC} $1" | tee -a "$LOG_FILE"
}

# Check if work is already in progress
if [ -f "$LOCK_FILE" ]; then
    LOCK_AGE=$(($(date +%s) - $(stat -c %Y "$LOCK_FILE" 2>/dev/null || stat -f %m "$LOCK_FILE")))
    if [ $LOCK_AGE -lt 1800 ]; then  # 30 minutes
        warn "Work already in progress (lock age: ${LOCK_AGE}s). Skipping this run."
        exit 0
    else
        warn "Stale lock found (age: ${LOCK_AGE}s). Removing and proceeding."
        rm -f "$LOCK_FILE"
    fi
fi

# Create lock
echo $$ > "$LOCK_FILE"
trap "rm -f $LOCK_FILE" EXIT

log "🚀 Starting autonomous development session..."

# Navigate to project
cd "$PROJECT_DIR"

# Call the main Python work script
python3 "$AUTONOMOUS_DIR/autonomous_dev.py"

log "✅ Development session complete"
