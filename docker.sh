#!/bin/bash

# Extract version from Makefile
VERSION=$(grep -oP '^VERSION = \K.*' Makefile)
IMAGE=madpsy/ubersdr-gotty

# Parse command line flags
TAG_LATEST=true
NO_CACHE=""
NO_PUSH=false

for arg in "$@"; do
    case $arg in
        --no-latest)
            TAG_LATEST=false
            echo "Running in --no-latest mode (will not tag as latest)"
            ;;
        --no-cache)
            NO_CACHE="--no-cache"
            echo "Running in --no-cache mode (will rebuild all layers)"
            ;;
        --no-push)
            NO_PUSH=true
            echo "Running in --no-push mode (will not push to Docker Hub or git)"
            ;;
        *)
            echo "Unknown option: $arg"
            echo "Usage: $0 [--no-latest] [--no-cache] [--no-push]"
            exit 1
            ;;
    esac
done

echo "Building version: $VERSION"
echo ""

# Build Docker image with version tag
echo "Building ubersdr-gotty Docker image..."
if ! docker build $NO_CACHE -t $IMAGE:$VERSION -f Dockerfile .; then
    echo "ERROR: Docker build failed!"
    exit 1
fi

echo "Build successful!"

# Tag version as latest (unless --no-latest flag is set)
if [ "$TAG_LATEST" = true ]; then
    echo "Tagging as latest..."
    docker tag $IMAGE:$VERSION $IMAGE:latest
else
    echo "Skipping 'latest' tag (--no-latest flag set)"
fi

# Push tags (unless --no-push flag is set)
if [ "$NO_PUSH" = false ]; then
    echo "Pushing to Docker Hub..."
    docker push $IMAGE:$VERSION

    if [ "$TAG_LATEST" = true ]; then
        docker push $IMAGE:latest
    fi

    # Commit and push version changes (unless --no-latest flag is set)
    if [ "$TAG_LATEST" = true ]; then
        echo "Committing and pushing to git..."
        git add .
        git commit -m "$VERSION"
        git push -v
    else
        echo "Skipping git commit and push (--no-latest flag set)"
    fi
else
    echo "Skipping Docker Hub push and git commit (--no-push flag set)"
fi

echo "Done!"
