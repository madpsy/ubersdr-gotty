#!/bin/bash

# Test script for the REST API

echo "Testing REST API for command execution..."
echo ""

# Test 1: Simple command
echo "Test 1: Running 'uptime' command"
curl -X POST http://localhost:9980/api/exec \
  -H "Content-Type: application/json" \
  -d '{"command": "uptime"}' \
  2>/dev/null | jq '.'

echo ""
echo "---"
echo ""

# Test 2: Command with output
echo "Test 2: Running 'uname -a' command"
curl -X POST http://localhost:9980/api/exec \
  -H "Content-Type: application/json" \
  -d '{"command": "uname -a"}' \
  2>/dev/null | jq '.'

echo ""
echo "---"
echo ""

# Test 3: Command with timeout
echo "Test 3: Running 'echo hello' with 5 second timeout"
curl -X POST http://localhost:9980/api/exec \
  -H "Content-Type: application/json" \
  -d '{"command": "echo hello", "timeout": 5}' \
  2>/dev/null | jq '.'

echo ""
echo "---"
echo ""

# Test 4: Command that fails
echo "Test 4: Running command that fails"
curl -X POST http://localhost:9980/api/exec \
  -H "Content-Type: application/json" \
  -d '{"command": "ls /nonexistent"}' \
  2>/dev/null | jq '.'

echo ""
echo "Done!"
