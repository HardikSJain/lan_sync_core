#!/bin/bash

# Cron wrapper that runs work.sh and self-disables at 7 AM tomorrow

WORK_SCRIPT="$HOME/.openclaw/workspace/lan_sync_core/.autonomous/work.sh"
CRON_FILE="$HOME/.openclaw/workspace/lan_sync_core/.autonomous/lan_sync_cron"

# Get tomorrow's 7 AM timestamp
TOMORROW_7AM=$(date -d "tomorrow 07:00" +%s 2>/dev/null || date -v+1d -v7H -v0M -v0S +%s)
CURRENT_TIME=$(date +%s)

# Check if we've passed 7 AM tomorrow
if [ $CURRENT_TIME -ge $TOMORROW_7AM ]; then
    echo "[$(date)] 🛑 Reached 7 AM cutoff. Disabling cron job."
    
    # Remove the cron job
    crontab -l | grep -v "lan_sync_cron_wrapper" | crontab -
    
    # Mark as complete
    echo "[$(date)] Autonomous development session ended" >> "$HOME/.openclaw/workspace/lan_sync_core/.autonomous/work.log"
    
    exit 0
fi

# Run the work script
bash "$WORK_SCRIPT"
