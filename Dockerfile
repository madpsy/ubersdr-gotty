# Build stage
FROM node:20-alpine AS js-builder

WORKDIR /app/js
COPY js/package*.json ./
RUN npm install

COPY js/ ./
RUN npx webpack

# Go build stage
FROM golang:1.24-alpine AS go-builder

RUN apk add --no-cache git make

WORKDIR /app

# Copy all source files
COPY . .

# Build the JavaScript assets first
COPY --from=js-builder /app/js/dist ./js/dist
COPY --from=js-builder /app/js/node_modules ./js/node_modules

# Install go-bindata for asset embedding
RUN go install github.com/go-bindata/go-bindata/v3/go-bindata@latest

# Build assets
RUN make asset

# Initialize go modules and build the application
ARG VERSION=2.0.0-alpha.3
ARG GIT_COMMIT=docker-build
RUN go mod init github.com/yudai/gotty && \
    go mod tidy && \
    go build -ldflags "-X main.Version=${VERSION} -X main.CommitID=${GIT_COMMIT}"

# Final stage
FROM alpine:latest

RUN apk add --no-cache ca-certificates bash openssh-client

WORKDIR /app

COPY --from=go-builder /app/gotty /usr/local/bin/gotty

# Copy the tmux wrapper script
COPY tmux-wrapper.sh /usr/local/bin/tmux-wrapper.sh
RUN chmod +x /usr/local/bin/tmux-wrapper.sh

# Create entrypoint script to handle SSH key permissions and username detection
RUN echo '#!/bin/bash' > /entrypoint.sh && \
    echo '# Ensure .ssh directory exists' >> /entrypoint.sh && \
    echo 'mkdir -p /root/.ssh' >> /entrypoint.sh && \
    echo '' >> /entrypoint.sh && \
    echo '# Handle directory mount at /ssh-keys' >> /entrypoint.sh && \
    echo 'if [ -d /ssh-keys ]; then' >> /entrypoint.sh && \
    echo '  cp -r /ssh-keys/* /root/.ssh/ 2>/dev/null || true' >> /entrypoint.sh && \
    echo 'fi' >> /entrypoint.sh && \
    echo '' >> /entrypoint.sh && \
    echo '# Fix permissions for all SSH keys' >> /entrypoint.sh && \
    echo 'if [ -d /root/.ssh ]; then' >> /entrypoint.sh && \
    echo '  chmod 700 /root/.ssh' >> /entrypoint.sh && \
    echo '  chmod 600 /root/.ssh/* 2>/dev/null || true' >> /entrypoint.sh && \
    echo '  chmod 644 /root/.ssh/*.pub 2>/dev/null || true' >> /entrypoint.sh && \
    echo 'fi' >> /entrypoint.sh && \
    echo '' >> /entrypoint.sh && \
    echo '# Use SSH_USER env var, fallback to USER env var, or default to current user' >> /entrypoint.sh && \
    echo 'export SSH_USER=${SSH_USER:-${USER:-$(whoami)}}' >> /entrypoint.sh && \
    echo '' >> /entrypoint.sh && \
    echo '# If no custom command provided, use wrapper (handles both normal and session modes)' >> /entrypoint.sh && \
    echo 'if [ "$#" -eq 0 ] || [ "$1" = "--permit-write" ]; then' >> /entrypoint.sh && \
    echo '  # Wrapper decides: no session param = direct SSH, session param = tmux' >> /entrypoint.sh && \
    echo '  exec gotty --permit-write --permit-arguments --reconnect /usr/local/bin/tmux-wrapper.sh' >> /entrypoint.sh && \
    echo 'else' >> /entrypoint.sh && \
    echo '  exec gotty "$@"' >> /entrypoint.sh && \
    echo 'fi' >> /entrypoint.sh && \
    chmod +x /entrypoint.sh

# Expose default gotty port
EXPOSE 9980

ENTRYPOINT ["/entrypoint.sh"]
CMD []
