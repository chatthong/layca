#!/usr/bin/env bash
# spawn-qwen-parallel.sh
# Spawns multiple Claude Code sessions each running qwen-ios-senior in tmux panes
# Usage: ./scripts/spawn-qwen-parallel.sh "task1" "task2" "task3"
#   or:  ./scripts/spawn-qwen-parallel.sh   (uses default example tasks)

set -euo pipefail

SESSION="layca-qwen"
LAYCA_DIR="/Users/ter/Desktop/layca"
CLAUDE_BIN="/opt/homebrew/bin/claude"

# Default tasks if none provided
DEFAULT_TASKS=(
  "Use the qwen-ios-senior agent to audit ExportService.swift and suggest improvements"
  "Use the qwen-ios-senior agent to review ContentView.swift for platform-adaptation issues"
  "Use the qwen-ios-senior agent to check AppBackend.swift for concurrency safety"
)

# Use provided args or defaults
if [ "$#" -gt 0 ]; then
  TASKS=("$@")
else
  TASKS=("${DEFAULT_TASKS[@]}")
fi

NUM_TASKS=${#TASKS[@]}

echo "Spawning $NUM_TASKS qwen-ios-senior sessions in tmux session '$SESSION'..."

# Kill existing session if present
tmux kill-session -t "$SESSION" 2>/dev/null || true

# Create new tmux session (first window = pane 0, task 1)
tmux new-session -d -s "$SESSION" -c "$LAYCA_DIR" -x 220 -y 50

# First pane runs task 0
tmux send-keys -t "$SESSION:0.0" \
  "$CLAUDE_BIN --print '${TASKS[0]}'" Enter

# Create additional panes for remaining tasks
for i in $(seq 1 $((NUM_TASKS - 1))); do
  tmux split-window -t "$SESSION:0" -v -c "$LAYCA_DIR"
  tmux send-keys -t "$SESSION:0.$i" \
    "$CLAUDE_BIN --print '${TASKS[$i]}'" Enter
done

# Tile all panes evenly
tmux select-layout -t "$SESSION:0" tiled

# Attach
echo "Attaching to '$SESSION'... (Ctrl-b d to detach)"
tmux attach-session -t "$SESSION"
