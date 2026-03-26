#!/bin/bash

# Subagent-based Autonomous Development
# Spawns an OpenClaw subagent to do actual intelligent work

set -e

PROJECT_DIR="$HOME/.openclaw/workspace/lan_sync_core"
AUTONOMOUS_DIR="$PROJECT_DIR/.autonomous"
LOCK_FILE="$AUTONOMOUS_DIR/subagent.lock"
LOG_FILE="$AUTONOMOUS_DIR/work.log"
STATE_FILE="$AUTONOMOUS_DIR/state.json"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1" | tee -a "$LOG_FILE"
}

warn() {
    echo -e "${YELLOW}[$(date '+%Y-%m-%d %H:%M:%S')] WARNING:${NC} $1" | tee -a "$LOG_FILE"
}

error() {
    echo -e "${RED}[$(date '+%Y-%m-%d %H:%M:%S')] ERROR:${NC} $1" | tee -a "$LOG_FILE"
}

# Check for lock
if [ -f "$LOCK_FILE" ]; then
    LOCK_AGE=$(($(date +%s) - $(stat -c %Y "$LOCK_FILE" 2>/dev/null || stat -f %m "$LOCK_FILE")))
    if [ $LOCK_AGE -lt 600 ]; then  # 10 minutes
        warn "Previous subagent still running (lock age: ${LOCK_AGE}s). Skipping."
        exit 0
    else
        warn "Stale lock found (age: ${LOCK_AGE}s). Removing."
        rm -f "$LOCK_FILE"
    fi
fi

# Create lock
echo $$ > "$LOCK_FILE"
trap "rm -f $LOCK_FILE" EXIT

log "🚀 Spawning autonomous development subagent..."

# Check if there are tasks remaining
TASKS_REMAINING=$(cat "$STATE_FILE" | python3 -c "import sys, json; data=json.load(sys.stdin); print(len(data.get('nextTasks', [])))")

if [ "$TASKS_REMAINING" -eq 0 ]; then
    log "✅ All tasks complete. No work to do."
    exit 0
fi

log "📋 ${TASKS_REMAINING} tasks remaining"

# Spawn the subagent using OpenClaw sessions
# The subagent will read subagent_task.md as its instructions
cd "$PROJECT_DIR"

openclaw sessions spawn \
    --runtime subagent \
    --mode run \
    --task "$(cat $AUTONOMOUS_DIR/subagent_task.md)" \
    --label "lan_sync_dev" \
    --cwd "$PROJECT_DIR" \
    --cleanup delete \
    --timeout 300 \
    2>&1 | tee -a "$LOG_FILE"

RESULT=$?

if [ $RESULT -eq 0 ]; then
    log "✅ Subagent completed successfully"
else
    error "Subagent failed with code $RESULT"
fi

exit $RESULT
