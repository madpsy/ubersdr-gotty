#!/bin/bash
# Tmux session wrapper for GoTTY
# This script handles both normal SSH and session persistence via tmux

# Get SSH user from environment
SSH_USER=${SSH_USER:-${USER:-$(whoami)}}

# Parse URL parameters from GoTTY
SESSION_NAME=""
CMD=""

# Check all arguments for session parameter
for arg in "$@"; do
  if [[ "$arg" == session=* ]]; then
    SESSION_NAME="${arg#session=}"
  elif [[ "$arg" != arg=* ]] && [ -z "$CMD" ]; then
    # First non-session argument is the command
    CMD="$arg"
  fi
done

# Default command if none provided
if [ -z "$CMD" ]; then
  CMD="bash -l"
fi

# If session name provided, use tmux
if [ -n "$SESSION_NAME" ]; then
  # Check if tmux session exists
  if ssh -q -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "${SSH_USER}@host.docker.internal" "tmux has-session -t '$SESSION_NAME' 2>/dev/null"; then
    # Attach to existing session
    exec ssh -q -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -t "${SSH_USER}@host.docker.internal" "tmux attach-session -t '$SESSION_NAME'"
  else
    # Create new detached session first, then attach to it
    # This ensures the session persists when we disconnect
    ssh -q -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "${SSH_USER}@host.docker.internal" "tmux new-session -d -s '$SESSION_NAME' $CMD"
    # Now attach to the session
    exec ssh -q -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -t "${SSH_USER}@host.docker.internal" "tmux attach-session -t '$SESSION_NAME'"
  fi
else
  # No session - direct SSH without tmux (normal mode)
  exec ssh -q -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -t "${SSH_USER}@host.docker.internal" "export TERM=xterm-256color; exec $CMD"
fi
