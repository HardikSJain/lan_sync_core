# Test Run - Subagent System

Testing the new subagent-based autonomous development system before enabling cron.

## Test Command

```bash
cd ~/.openclaw/workspace/lan_sync_core
bash .autonomous/spawn_subagent.sh
```

This will:
1. Check for lock file
2. Check remaining tasks
3. Spawn a subagent with the task instructions
4. Subagent will pick first task from queue
5. Subagent will implement it
6. Subagent will test, commit, push
7. Subagent will update state and exit

## Expected Output

```
[2026-03-26 06:45:00] 🚀 Spawning autonomous development subagent...
[2026-03-26 06:45:01] 📋 13 tasks remaining
[Subagent session output...]
[2026-03-26 06:45:XX] ✅ Subagent completed successfully
```

## What the Subagent Should Do

Read state.json → First task is "Fix compilation errors in UdpTransport"

The subagent should:
1. Read `lib/src/network/udp_transport.dart`
2. Identify the 9 compilation errors
3. Fix them (Duration syntax, field names, etc.)
4. Run `fvm flutter analyze` → 0 errors
5. Commit: "🤖 fix: resolve 9 compilation errors in UdpTransport"
6. Push to GitHub
7. Update state.json (move task to completedTasks)
8. Exit

## Verification

After test run:
1. Check git log: `git log --oneline -1`
2. Check GitHub for new commit
3. Check state.json: task should be in completedTasks
4. Check work.log for subagent output

## If Test Succeeds

Enable cron:
```bash
(crontab -l; echo "*/15 * * * * $HOME/.openclaw/workspace/lan_sync_core/.autonomous/cron_subagent.sh >> $HOME/.openclaw/workspace/lan_sync_core/.autonomous/cron.log 2>&1  # lan_sync_subagent") | crontab -
```

## If Test Fails

Debug and fix before enabling cron.
