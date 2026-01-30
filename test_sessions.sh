#!/bin/bash

# Test script for session management API
# Make sure the container is running and tmux is installed on the host

BASE_URL="http://localhost:9980"

echo "=== Testing Session Management API ==="
echo ""

echo "1. List all sessions (should be empty initially)"
curl -s "${BASE_URL}/api/sessions" | jq .
echo ""
echo ""

echo "2. Create a session via web interface:"
echo "   Open: ${BASE_URL}/?arg=top&session=test-session"
echo "   Press Enter when ready to continue..."
read

echo "3. List sessions again (should show test-session)"
curl -s "${BASE_URL}/api/sessions" | jq .
echo ""
echo ""

echo "4. Create another session:"
echo "   Open: ${BASE_URL}/?arg=htop&session=monitoring"
echo "   Press Enter when ready to continue..."
read

echo "5. List all sessions"
curl -s "${BASE_URL}/api/sessions" | jq .
echo ""
echo ""

echo "6. Destroy test-session"
curl -s -X POST "${BASE_URL}/api/sessions/destroy?name=test-session" | jq .
echo ""
echo ""

echo "7. List sessions (test-session should be gone)"
curl -s "${BASE_URL}/api/sessions" | jq .
echo ""
echo ""

echo "8. Try to destroy non-existent session"
curl -s -X POST "${BASE_URL}/api/sessions/destroy?name=nonexistent" | jq .
echo ""
echo ""

echo "9. Destroy monitoring session"
curl -s -X POST "${BASE_URL}/api/sessions/destroy?name=monitoring" | jq .
echo ""
echo ""

echo "10. Final session list (should be empty)"
curl -s "${BASE_URL}/api/sessions" | jq .
echo ""

echo "=== Test Complete ==="
