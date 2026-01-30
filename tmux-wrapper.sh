#!/bin/bash
# Tmux session wrapper for GoTTY
# This script handles both normal SSH and session persistence via tmux

# Debug logging
echo "DEBUG: Wrapper called with args: $@" >> /tmp/wrapper-debug.log
echo "DEBUG: Number of args: $#" >> /tmp/wrapper-debug.log

# Get SSH user from environment
SSH_USER=${SSH_USER:-${USER:-$(whoami)}}

# Parse URL parameters from GoTTY
# GoTTY with --permit-arguments passes URL params as: arg=key arg=value arg=key2 arg=value2
SESSION_NAME=""
CMD=""
NEXT_IS_SESSION=false

# Check all arguments
for arg in "$@"; do
  echo "DEBUG: Processing arg: $arg" >> /tmp/wrapper-debug.log
  
  # Check if this is the session parameter marker
  if [[ "$arg" == "arg=session" ]]; then
    NEXT_IS_SESSION=true
    echo "DEBUG: Found session parameter marker" >> /tmp/wrapper-debug.log
  # Check if previous arg was session marker, this is the value
  elif [ "$NEXT_IS_SESSION" = true ] && [[ "$arg" == arg=* ]]; then
    SESSION_NAME="${arg#arg=}"
    NEXT_IS_SESSION=false
    echo "DEBUG: Found session name: $SESSION_NAME" >> /tmp/wrapper-debug.log
  # Also support direct session=value format for backwards compatibility
  elif [[ "$arg" == session=* ]]; then
    SESSION_NAME="${arg#session=}"
    echo "DEBUG: Found session name (direct format): $SESSION_NAME" >> /tmp/wrapper-debug.log
  # First non-arg parameter is the command
  elif [[ "$arg" != arg=* ]] && [ -z "$CMD" ]; then
    CMD="$arg"
    echo "DEBUG: Found command: $CMD" >> /tmp/wrapper-debug.log
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
