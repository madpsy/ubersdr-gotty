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
SESSION_ID=""
FRIENDLY_NAME=""
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
    SESSION_ID="${arg#arg=}"
    NEXT_IS_SESSION=false
    echo "DEBUG: Found session ID: $SESSION_ID" >> /tmp/wrapper-debug.log
  # Support direct session=value format
  elif [[ "$arg" == session=* ]]; then
    SESSION_ID="${arg#session=}"
    echo "DEBUG: Found session ID (direct format): $SESSION_ID" >> /tmp/wrapper-debug.log
  # Support friendly name parameter
  elif [[ "$arg" == name=* ]]; then
    FRIENDLY_NAME="${arg#name=}"
    echo "DEBUG: Found friendly name: $FRIENDLY_NAME" >> /tmp/wrapper-debug.log
  # First non-parameter argument is the command
  elif [[ "$arg" != *=* ]] && [ -z "$CMD" ]; then
    CMD="$arg"
    echo "DEBUG: Found command: $CMD" >> /tmp/wrapper-debug.log
  fi
done

# Default command if none provided
if [ -z "$CMD" ]; then
  CMD="bash -l"
fi

# If session ID provided, use tmux
if [ -n "$SESSION_ID" ]; then
  echo "DEBUG: Using tmux mode with session ID: $SESSION_ID" >> /tmp/wrapper-debug.log
  echo "DEBUG: Friendly name: $FRIENDLY_NAME" >> /tmp/wrapper-debug.log
  
  # Check if tmux session exists (use =SESSION_ID for exact match, not prefix match)
  if ssh -q -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "${SSH_USER}@host.docker.internal" "tmux has-session -t ='$SESSION_ID' 2>/dev/null"; then
    echo "DEBUG: Attaching to existing session" >> /tmp/wrapper-debug.log
    # Attach to existing session (use = for exact match)
    # Set terminal title to user@hostname using escape sequence
    exec ssh -q -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -t "${SSH_USER}@host.docker.internal" "printf '\033]0;%s@%s\007' \"\$USER\" \"\$(hostname)\"; TERM=screen-256color tmux attach-session -t ='$SESSION_ID'"
  else
    echo "DEBUG: Creating new session" >> /tmp/wrapper-debug.log
    # Create new detached session first, then attach to it
    # This ensures the session persists when we disconnect
    # Set TERM to screen-256color for tmux compatibility
    
    # If friendly name provided, set it as the window name
    if [ -n "$FRIENDLY_NAME" ]; then
      ssh -q -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "${SSH_USER}@host.docker.internal" "TERM=screen-256color tmux new-session -d -s '$SESSION_ID' -n '$FRIENDLY_NAME' $CMD"
    else
      ssh -q -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "${SSH_USER}@host.docker.internal" "TERM=screen-256color tmux new-session -d -s '$SESSION_ID' $CMD"
    fi
    
    # Now attach to the session and set terminal title (use = for exact match)
    exec ssh -q -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -t "${SSH_USER}@host.docker.internal" "printf '\033]0;%s@%s\007' \"\$USER\" \"\$(hostname)\"; TERM=screen-256color tmux attach-session -t ='$SESSION_ID'"
  fi
else
  echo "DEBUG: Using direct SSH mode (no session)" >> /tmp/wrapper-debug.log
  # No session - direct SSH without tmux (normal mode)
  # Set terminal title to user@hostname using escape sequence
  exec ssh -q -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -t "${SSH_USER}@host.docker.internal" "printf '\033]0;%s@%s\007' \"\$USER\" \"\$(hostname)\"; export TERM=xterm-256color; exec $CMD"
fi
