#!/bin/bash

# Run ubersdr-gotty container with SSH access to Docker host
# Usage: ./run.sh [ssh_key_path]
# Example: ./run.sh ~/.ssh/my_key
#
# Access the terminal at http://localhost:9980/
# Run specific commands via URL: http://localhost:9980/?arg=btop
#
# Session Manager UI: http://localhost:9980/sessions
#
# Persistent sessions (requires tmux on host):
#   http://localhost:9980/?arg=btop&session=monitoring  - Run btop in persistent session
#   http://localhost:9980/?session=monitoring           - Attach to existing session
#
# Session management API:
#   GET  http://localhost:9980/api/sessions             - List all sessions
#   POST http://localhost:9980/api/sessions/destroy?name=SESSION - Destroy a session

SSH_KEY_PATH="${1:-$HOME/.ssh}"

if [ -f "$SSH_KEY_PATH" ]; then
    # Specific key file provided
    KEY_NAME=$(basename "$SSH_KEY_PATH")
    KEY_DIR=$(dirname "$SSH_KEY_PATH")
    PUB_KEY="${SSH_KEY_PATH}.pub"
    
    echo "Using specific SSH key: $SSH_KEY_PATH"
    
    # Check if public key exists
    if [ ! -f "$PUB_KEY" ]; then
        echo "Warning: Public key not found at $PUB_KEY"
        echo "Continuing anyway, but SSH may fail..."
    fi
    
    # Mount specific key files
    docker run --rm -p 9980:9980 \
      --add-host=host.docker.internal:host-gateway \
      -v "$SSH_KEY_PATH:/root/.ssh/id_rsa:ro" \
      $([ -f "$PUB_KEY" ] && echo "-v $PUB_KEY:/root/.ssh/id_rsa.pub:ro") \
      -e USER=$USER \
      madpsy/ubersdr-gotty:latest
      
elif [ -d "$SSH_KEY_PATH" ]; then
    # Directory provided, mount entire directory
    echo "Using SSH directory: $SSH_KEY_PATH"
    docker run --rm -p 9980:9980 \
      --add-host=host.docker.internal:host-gateway \
      -v "$SSH_KEY_PATH:/ssh-keys:ro" \
      -e USER=$USER \
      madpsy/ubersdr-gotty:latest
      
else
    echo "Error: SSH key path not found: $SSH_KEY_PATH"
    echo ""
    echo "Usage: $0 [ssh_key_path]"
    echo ""
    echo "Examples:"
    echo "  $0                          # Use default ~/.ssh directory"
    echo "  $0 ~/.ssh/my_key            # Use specific key file"
    echo "  $0 ~/.ssh/gotty_key         # Use dedicated passwordless key"
    exit 1
fi
