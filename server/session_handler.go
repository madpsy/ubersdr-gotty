package server

import (
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"os"
	"os/exec"
	"strings"
	"time"
)

// SessionInfo represents information about a tmux session
type SessionInfo struct {
	Name       string `json:"name"`
	WindowName string `json:"window_name,omitempty"`
	Created    string `json:"created"`
	Windows    int    `json:"windows"`
	Attached   bool   `json:"attached"`
	LastActive string `json:"last_active"`
}

// SessionListResponse represents the response for listing sessions
type SessionListResponse struct {
	Sessions []SessionInfo `json:"sessions"`
	Count    int           `json:"count"`
}

// SessionActionResponse represents the response for session actions
type SessionActionResponse struct {
	Success bool   `json:"success"`
	Message string `json:"message"`
	Session string `json:"session,omitempty"`
}

// handleSessionList handles GET requests to list all tmux sessions
func (server *Server) handleSessionList(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}

	log.Printf("Session list request from %s", getClientIP(r))

	// Execute tmux list-sessions command via SSH
	cmd := exec.Command("ssh",
		"-q",
		"-o", "StrictHostKeyChecking=no",
		"-o", "UserKnownHostsFile=/dev/null",
		"-o", "ConnectTimeout=5",
		fmt.Sprintf("%s@host.docker.internal", getSSHUser()),
		"tmux list-sessions -F '#{session_name}|#{session_created}|#{session_windows}|#{session_attached}|#{session_activity}' 2>/dev/null || echo 'NO_SESSIONS'",
	)

	output, err := cmd.CombinedOutput()
	if err != nil {
		// If tmux is not installed or no sessions exist, return empty list
		response := SessionListResponse{
			Sessions: []SessionInfo{},
			Count:    0,
		}
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(response)
		return
	}

	outputStr := strings.TrimSpace(string(output))

	// Check if no sessions exist
	if outputStr == "NO_SESSIONS" || outputStr == "" {
		response := SessionListResponse{
			Sessions: []SessionInfo{},
			Count:    0,
		}
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(response)
		return
	}

	// Fetch window names for all sessions
	windowCmd := exec.Command("ssh",
		"-q",
		"-o", "StrictHostKeyChecking=no",
		"-o", "UserKnownHostsFile=/dev/null",
		"-o", "ConnectTimeout=5",
		fmt.Sprintf("%s@host.docker.internal", getSSHUser()),
		"tmux list-windows -a -F '#{session_name}|#{window_index}|#{window_name}' 2>/dev/null",
	)
	windowOutput, _ := windowCmd.CombinedOutput()
	windowMap := parseWindowNames(string(windowOutput))

	// Parse tmux output
	lines := strings.Split(outputStr, "\n")
	sessions := make([]SessionInfo, 0, len(lines))

	for _, line := range lines {
		if line == "" {
			continue
		}

		parts := strings.Split(line, "|")
		if len(parts) != 5 {
			continue
		}

		sessionName := parts[0]
		session := SessionInfo{
			Name:       sessionName,
			WindowName: windowMap[sessionName],
			Created:    formatTimestamp(parts[1]),
			Windows:    parseWindows(parts[2]),
			Attached:   parts[3] == "1",
			LastActive: formatTimestamp(parts[4]),
		}
		sessions = append(sessions, session)
	}

	response := SessionListResponse{
		Sessions: sessions,
		Count:    len(sessions),
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(response)

	log.Printf("Session list completed: %d sessions found", len(sessions))
}

// handleSessionDestroy handles DELETE requests to destroy a tmux session
func (server *Server) handleSessionDestroy(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodDelete && r.Method != http.MethodPost {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}

	// Get session name from query parameter
	sessionName := r.URL.Query().Get("name")
	if sessionName == "" {
		http.Error(w, "Session name is required", http.StatusBadRequest)
		return
	}

	log.Printf("Session destroy request from %s: %s", getClientIP(r), sessionName)

	// Execute tmux kill-session command via SSH
	cmd := exec.Command("ssh",
		"-q",
		"-o", "StrictHostKeyChecking=no",
		"-o", "UserKnownHostsFile=/dev/null",
		"-o", "ConnectTimeout=5",
		fmt.Sprintf("%s@host.docker.internal", getSSHUser()),
		fmt.Sprintf("tmux kill-session -t '%s' 2>&1", sessionName),
	)

	output, err := cmd.CombinedOutput()
	outputStr := strings.TrimSpace(string(output))

	response := SessionActionResponse{
		Session: sessionName,
	}

	if err != nil {
		// Check if session doesn't exist
		if strings.Contains(outputStr, "can't find session") || strings.Contains(outputStr, "no server running") {
			response.Success = false
			response.Message = fmt.Sprintf("Session '%s' not found", sessionName)
			w.Header().Set("Content-Type", "application/json")
			w.WriteHeader(http.StatusNotFound)
			json.NewEncoder(w).Encode(response)
			log.Printf("Session destroy failed: session not found")
			return
		}

		response.Success = false
		response.Message = fmt.Sprintf("Failed to destroy session: %s", outputStr)
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusInternalServerError)
		json.NewEncoder(w).Encode(response)
		log.Printf("Session destroy failed: %v", err)
		return
	}

	response.Success = true
	response.Message = fmt.Sprintf("Session '%s' destroyed successfully", sessionName)

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(response)

	log.Printf("Session destroyed successfully: %s", sessionName)
}

// Helper function to get SSH user from environment
func getSSHUser() string {
	sshUser := os.Getenv("USER")
	if sshUser == "" {
		sshUser = os.Getenv("SSH_USER")
	}
	if sshUser == "" {
		sshUser = "root"
	}
	return sshUser
}

// Helper function to format Unix timestamp
func formatTimestamp(ts string) string {
	// tmux returns Unix timestamp
	if ts == "" {
		return ""
	}

	// Parse as int64
	var timestamp int64
	fmt.Sscanf(ts, "%d", &timestamp)

	if timestamp == 0 {
		return ts
	}

	t := time.Unix(timestamp, 0)
	return t.Format("2006-01-02 15:04:05")
}

// Helper function to parse window count
func parseWindows(w string) int {
	var count int
	fmt.Sscanf(w, "%d", &count)
	return count
}

// ConnectionsListResponse represents the response for listing connections
type ConnectionsListResponse struct {
	Connections []*ConnectionInfo `json:"connections"`
	Count       int               `json:"count"`
}

// handleConnectionsList handles GET requests to list active connections
func (server *Server) handleConnectionsList(w http.ResponseWriter, r *http.Request) {
	if r.Method != "GET" {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}

	connections := server.connections.List()

	response := ConnectionsListResponse{
		Connections: connections,
		Count:       len(connections),
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(response)
}

// ConnectionHistoryResponse represents the response for connection history
type ConnectionHistoryResponse struct {
	History []*ConnectionHistoryEntry `json:"history"`
	Count   int                       `json:"count"`
}

// handleConnectionsHistory handles GET requests to retrieve connection history
func (server *Server) handleConnectionsHistory(w http.ResponseWriter, r *http.Request) {
	if r.Method != "GET" {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}

	history := server.connections.GetHistory()

	response := ConnectionHistoryResponse{
		History: history,
		Count:   len(history),
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(response)
}

// Helper function to parse window names from tmux output
// Returns a map of session_name -> first_window_name
func parseWindowNames(output string) map[string]string {
	windowMap := make(map[string]string)
	lines := strings.Split(strings.TrimSpace(output), "\n")

	for _, line := range lines {
		if line == "" {
			continue
		}

		parts := strings.Split(line, "|")
		if len(parts) != 3 {
			continue
		}

		sessionName := parts[0]
		windowIndex := parts[1]
		windowName := parts[2]

		// Only store the first window (index 0) name for each session
		// This is where we store the friendly name
		if windowIndex == "0" && windowName != "" {
			windowMap[sessionName] = windowName
		}
	}

	return windowMap
}
