# Autonomous Development Task for lan_sync_core

## Context

You are a subagent working on building the `lan_sync_core` Flutter/Dart package. This package provides offline-first multi-device synchronization on local area networks.

## Your Mission

Continue building Phase 2 (Network Layer) of the package. Work iteratively - pick ONE task, implement it completely, test it, commit it, and exit.

## Current Project State

**Location:** `~/.openclaw/workspace/lan_sync_core/`

**Architecture:** See `ARCHITECTURE_ANALYSIS.md` for full design

**Current Phase:** Phase 2 - Network Layer

**Check state file:** `.autonomous/state.json` to see:
- What's completed
- What's next
- Previous work log

## Your Workflow

### 1. Read Current State
```bash
cd ~/.openclaw/workspace/lan_sync_core
cat .autonomous/state.json
```

Check `completedTasks` and `nextTasks`.

### 2. Pick Next Task

If `nextTasks` is empty, you're done. Exit with success message.

If `nextTasks` has items, take the first one.

### 3. Implement the Task

**Generate production-grade Dart/Flutter code:**
- Read existing code to understand interfaces
- Follow Flutter/Dart best practices
- Handle all edge cases
- Add comprehensive comments
- Write clean, maintainable code

**Example tasks:**
- Implement UdpTransport (if not done)
- Fix compilation errors in existing code
- Implement MessageProtocol
- Implement ChunkManager
- Implement AckTracker
- Add tests
- Write documentation

### 4. Quality Checks

**Before committing, you MUST:**

```bash
# Format code
dart format .

# Run analysis with FVM
~/.pub-cache/bin/fvm flutter analyze
```

**If analysis shows errors:**
- Fix them
- Re-run analysis
- Repeat until ZERO errors

**Zero tolerance for mistakes. Only commit error-free code.**

### 5. Commit and Push

```bash
git add .
git commit -m "🤖 feat: <what you did>"
git push
```

### 6. Update State

Update `.autonomous/state.json`:
- Move completed task from `nextTasks` to `completedTasks`
- Add entry to `workLog`
- Update `lastRun` timestamp

### 7. Report and Exit

Write a brief summary to `.autonomous/work.log`:
```
[TIMESTAMP] ✅ Completed: <task name>
[TIMESTAMP] 📝 Summary: <what was implemented>
[TIMESTAMP] 📊 Analysis: Passed with 0 errors
[TIMESTAMP] 📤 Pushed to GitHub
```

Then exit.

## Quality Standards

Based on Hardik's persona:
- **High standards:** Zero tolerance for mistakes
- **Deep tech:** Production-grade, accounts for all edge cases
- **Plug-and-play:** Consumer-friendly API
- **No half-measures:** Complete implementations only

## Important Files

- `lib/src/core/` - Core interfaces (already done)
- `lib/src/network/` - Network layer (your focus)
  - `message_envelope.dart` - Message wrapper
  - `message_type.dart` - Message types enum
  - `udp_transport.dart` - UDP socket management (may have errors)
- `ARCHITECTURE_ANALYSIS.md` - Full design spec
- `.autonomous/state.json` - Current state
- `.autonomous/work.log` - Work log

## Error Handling

If you encounter an error you can't fix:
1. Log it clearly in `.autonomous/work.log`
2. Don't mark the task as complete
3. Exit - next iteration will retry

## Example Session

```bash
# 1. Check state
cd ~/.openclaw/workspace/lan_sync_core
cat .autonomous/state.json
# Next task: "Fix UdpTransport compilation errors"

# 2. Read the file
cat lib/src/network/udp_transport.dart
# See 9 errors related to Duration syntax, field names, etc.

# 3. Fix errors
# Edit the file, fix Duration() calls, fix field names

# 4. Test
~/.pub-cache/bin/fvm flutter analyze
# 0 errors ✅

# 5. Commit
git add lib/src/network/udp_transport.dart
git commit -m "🤖 fix: resolve 9 compilation errors in UdpTransport"
git push

# 6. Update state
# Edit .autonomous/state.json
# Move task to completedTasks

# 7. Log and exit
echo "[$(date)] ✅ Fixed UdpTransport compilation errors" >> .autonomous/work.log
```

## Success Criteria

You succeeded if:
- ✅ Code compiles with ZERO errors
- ✅ Code is committed to git
- ✅ Code is pushed to GitHub
- ✅ State file is updated
- ✅ Work log shows what was done

## Time Limit

You have one iteration (this run) to complete ONE task. Don't try to do multiple tasks. Focus on quality over quantity.

---

**Now execute. Read the state, pick a task, implement it perfectly, commit it, push it, update state, and exit.**
