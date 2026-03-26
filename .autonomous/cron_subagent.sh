#!/bin/bash

# Cron wrapper for subagent-based autonomous development
# Auto-disables at 7 AM

SPAWN_SCRIPT="$HOME/.openclaw/workspace/lan_sync_core/.autonomous/spawn_subagent.sh"
LOG_FILE="$HOME/.openclaw/workspace/lan_sync_core/.autonomous/cron.log"

# Get tomorrow's 7 AM (or today's if before 7 AM)
CURRENT_HOUR=$(date +%H)
if [ "$CURRENT_HOUR" -ge 7 ]; then
    # After 7 AM - get tomorrow's 7 AM
    CUTOFF_TIME=$(date -d "tomorrow 07:00" +%s 2>/dev/null || date -v+1d -v7H -v0M -v0S +%s)
else
    # Before 7 AM - get today's 7 AM
    CUTOFF_TIME=$(date -d "today 07:00" +%s 2>/dev/null || date -v7H -v0M -v0S +%s)
fi

CURRENT_TIME=$(date +%s)

# Check if we've passed 7 AM cutoff
if [ $CURRENT_TIME -ge $CUTOFF_TIME ]; then
    echo "[$(date)] 🛑 Reached 7 AM cutoff. Disabling cron job." | tee -a "$LOG_FILE"
    
    # Remove the cron job
    crontab -l 2>/dev/null | grep -v "lan_sync_subagent" | crontab -
    
    echo "[$(date)] ✅ Autonomous development session ended" | tee -a "$LOG_FILE"
    exit 0
fi

# Run the subagent spawner
bash "$SPAWN_SCRIPT"
