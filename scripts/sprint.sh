#!/usr/bin/env bash
# ─── Sprint Parallel Agent Runner ────────────────────────────────────────────
# Usage: ./scripts/sprint.sh <sprint-name> <cmd1> [cmd2] [cmd3] [cmd4]
#
# Opens a tmux window named after the sprint, splits into N panes (one per cmd),
# and runs each command in its own pane in parallel.
#
# Example — Sprint 2 with 3 agents:
#   ./scripts/sprint.sh sprint2 \
#     "claude --print 'implement F1 turn-taking'" \
#     "claude --print 'implement T2 adaptive probe'" \
#     "claude --print 'implement UI3 border accent'"

set -e
SESSION="${LAYCA_SESSION:-layca}"
SPRINT="$1"
shift
CMDS=("$@")
COUNT="${#CMDS[@]}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

if [ "$COUNT" -eq 0 ]; then
    echo "Usage: $0 <sprint-name> <cmd1> [cmd2] [cmd3] [cmd4]"
    exit 1
fi

# Create or reuse session
if ! tmux has-session -t "$SESSION" 2>/dev/null; then
    tmux new-session -d -s "$SESSION" -c "$ROOT"
fi

# Create a new window for this sprint
tmux new-window -t "$SESSION" -n "$SPRINT" -c "$ROOT"

# First pane already exists — run command 1
tmux send-keys -t "$SESSION:$SPRINT.1" "${CMDS[0]}" Enter

# Create additional panes for commands 2..N
for i in $(seq 1 $((COUNT - 1))); do
    CMD="${CMDS[$i]}"
    PANE=$((i + 1))

    if [ "$((i % 2))" -eq 1 ]; then
        # Odd: vertical split of current pane
        tmux split-window -t "$SESSION:$SPRINT" -v -c "$ROOT"
    else
        # Even: horizontal split creates a new column
        tmux split-window -t "$SESSION:$SPRINT.$i" -h -c "$ROOT"
    fi

    tmux send-keys -t "$SESSION:$SPRINT.$PANE" "$CMD" Enter
done

# Balance the layout
tmux select-layout -t "$SESSION:$SPRINT" tiled

# Focus pane 1
tmux select-pane -t "$SESSION:$SPRINT.1"

echo "✅  Sprint '$SPRINT' running in window '$SESSION:$SPRINT' with $COUNT panes."
echo "   Attach: tmux attach -t $SESSION && Ctrl-a, then select window '$SPRINT'"
