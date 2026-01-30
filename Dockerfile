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

# Create entrypoint script to handle SSH key permissions and username detection
RUN echo '#!/bin/bash' > /entrypoint.sh && \
    echo 'if [ -d /ssh-keys ]; then' >> /entrypoint.sh && \
    echo '  mkdir -p /root/.ssh' >> /entrypoint.sh && \
    echo '  cp -r /ssh-keys/* /root/.ssh/ 2>/dev/null || true' >> /entrypoint.sh && \
    echo '  chmod 700 /root/.ssh' >> /entrypoint.sh && \
    echo '  chmod 600 /root/.ssh/* 2>/dev/null || true' >> /entrypoint.sh && \
    echo '  chmod 644 /root/.ssh/*.pub 2>/dev/null || true' >> /entrypoint.sh && \
    echo 'fi' >> /entrypoint.sh && \
    echo '' >> /entrypoint.sh && \
    echo '# Detect username from SSH keys ownership or use SSH_USER env var' >> /entrypoint.sh && \
    echo 'if [ -z "$SSH_USER" ] && [ -d /ssh-keys ]; then' >> /entrypoint.sh && \
    echo '  SSH_USER=$(stat -c "%U" /ssh-keys 2>/dev/null || echo "root")' >> /entrypoint.sh && \
    echo 'fi' >> /entrypoint.sh && \
    echo 'SSH_USER=${SSH_USER:-root}' >> /entrypoint.sh && \
    echo '' >> /entrypoint.sh && \
    echo '# If no custom command provided, use default SSH command with detected user' >> /entrypoint.sh && \
    echo 'if [ "$#" -eq 0 ] || [ "$1" = "--permit-write" ]; then' >> /entrypoint.sh && \
    echo '  exec gotty --permit-write --reconnect bash -c "ssh ${SSH_USER}@host.docker.internal"' >> /entrypoint.sh && \
    echo 'else' >> /entrypoint.sh && \
    echo '  exec gotty "$@"' >> /entrypoint.sh && \
    echo 'fi' >> /entrypoint.sh && \
    chmod +x /entrypoint.sh

# Expose default gotty port
EXPOSE 8080

ENTRYPOINT ["/entrypoint.sh"]
CMD []
