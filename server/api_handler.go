package server

import (
	"bytes"
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"os"
	"os/exec"
	"time"
)

// ExecRequest represents the JSON request body for command execution
type ExecRequest struct {
	Command string `json:"command"`
	Timeout int    `json:"timeout,omitempty"` // timeout in seconds, default 30
}

// ExecResponse represents the JSON response for command execution
type ExecResponse struct {
	Stdout   string `json:"stdout"`
	Stderr   string `json:"stderr"`
	ExitCode int    `json:"exit_code"`
	Error    string `json:"error,omitempty"`
	Duration string `json:"duration"`
}

// handleAPIExec handles REST API requests for command execution via SSH
func (server *Server) handleAPIExec(w http.ResponseWriter, r *http.Request) {
	// Only allow POST requests
	if r.Method != http.MethodPost {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}

	// Parse request body
	var req ExecRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, fmt.Sprintf("Invalid JSON: %v", err), http.StatusBadRequest)
		return
	}

	// Validate command
	if req.Command == "" {
		http.Error(w, "Command cannot be empty", http.StatusBadRequest)
		return
	}

	// Set default timeout
	if req.Timeout == 0 {
		req.Timeout = 30
	}

	// Get SSH user from environment
	sshUser := os.Getenv("USER")
	if sshUser == "" {
		sshUser = os.Getenv("SSH_USER")
	}
	if sshUser == "" {
		sshUser = "root"
	}

	// Log the command execution
	log.Printf("API exec request from %s: %s", r.RemoteAddr, req.Command)

	// Execute command via SSH
	startTime := time.Now()

	cmd := exec.Command("ssh",
		"-q", // Quiet mode - suppresses warnings
		"-o", "StrictHostKeyChecking=no",
		"-o", "UserKnownHostsFile=/dev/null",
		"-o", "ConnectTimeout=5",
		fmt.Sprintf("%s@host.docker.internal", sshUser),
		req.Command,
	)

	var stdout, stderr bytes.Buffer
	cmd.Stdout = &stdout
	cmd.Stderr = &stderr

	// Create a channel to signal command completion
	done := make(chan error, 1)
	go func() {
		done <- cmd.Run()
	}()

	// Wait for command to complete or timeout
	var cmdErr error
	select {
	case cmdErr = <-done:
		// Command completed
	case <-time.After(time.Duration(req.Timeout) * time.Second):
		// Timeout - kill the process
		if cmd.Process != nil {
			cmd.Process.Kill()
		}
		cmdErr = fmt.Errorf("command timed out after %d seconds", req.Timeout)
	}

	duration := time.Since(startTime)

	// Prepare response
	response := ExecResponse{
		Stdout:   stdout.String(),
		Stderr:   stderr.String(),
		Duration: duration.String(),
	}

	// Get exit code
	if cmdErr != nil {
		if exitErr, ok := cmdErr.(*exec.ExitError); ok {
			response.ExitCode = exitErr.ExitCode()
		} else {
			response.Error = cmdErr.Error()
			response.ExitCode = -1
		}
	} else {
		response.ExitCode = 0
	}

	// Set response headers
	w.Header().Set("Content-Type", "application/json")

	// Return appropriate HTTP status code
	if response.ExitCode != 0 {
		w.WriteHeader(http.StatusOK) // Still 200, but with non-zero exit code in body
	}

	// Encode and send response
	if err := json.NewEncoder(w).Encode(response); err != nil {
		log.Printf("Failed to encode response: %v", err)
	}

	// Log completion
	log.Printf("API exec completed in %s with exit code %d", duration, response.ExitCode)
}
