#!/bin/bash

# Run ubersdr-gotty container with SSH access to Docker host
docker run --rm -p 9980:9980 \
  --add-host=host.docker.internal:host-gateway \
  -v ~/.ssh:/ssh-keys:ro \
  -e USER=$USER \
  madpsy/ubersdr-gotty:latest
