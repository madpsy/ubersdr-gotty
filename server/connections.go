package server

import (
	"sync"
	"time"
)

// ConnectionInfo represents information about a connected client
type ConnectionInfo struct {
	ID          string    `json:"id"`
	RemoteAddr  string    `json:"remote_addr"`
	ConnectedAt time.Time `json:"connected_at"`
	SessionName string    `json:"session_name,omitempty"`
	Arguments   string    `json:"arguments,omitempty"`
}

// ConnectionHistoryEntry represents a historical connection record
type ConnectionHistoryEntry struct {
	RemoteAddr     string    `json:"remote_addr"`
	ConnectedAt    time.Time `json:"connected_at"`
	DisconnectedAt time.Time `json:"disconnected_at"`
	Duration       string    `json:"duration"`
	SessionName    string    `json:"session_name,omitempty"`
	Arguments      string    `json:"arguments,omitempty"`
}

// ConnectionTracker tracks active WebSocket connections and maintains history
type ConnectionTracker struct {
	mu          sync.RWMutex
	connections map[string]*ConnectionInfo
	history     []*ConnectionHistoryEntry
	maxHistory  int
}

// NewConnectionTracker creates a new connection tracker
func NewConnectionTracker() *ConnectionTracker {
	return &ConnectionTracker{
		connections: make(map[string]*ConnectionInfo),
		history:     make([]*ConnectionHistoryEntry, 0, 100),
		maxHistory:  100, // Keep last 100 connections
	}
}

// Add adds a new connection to the tracker
func (ct *ConnectionTracker) Add(id, remoteAddr, sessionName, arguments string) {
	ct.mu.Lock()
	defer ct.mu.Unlock()

	ct.connections[id] = &ConnectionInfo{
		ID:          id,
		RemoteAddr:  remoteAddr,
		ConnectedAt: time.Now(),
		SessionName: sessionName,
		Arguments:   arguments,
	}
}

// Remove removes a connection from the tracker and adds it to history
func (ct *ConnectionTracker) Remove(id string) {
	ct.mu.Lock()
	defer ct.mu.Unlock()

	// Get connection info before removing
	if conn, exists := ct.connections[id]; exists {
		// Calculate duration
		disconnectedAt := time.Now()
		duration := disconnectedAt.Sub(conn.ConnectedAt)

		// Create history entry
		historyEntry := &ConnectionHistoryEntry{
			RemoteAddr:     conn.RemoteAddr,
			ConnectedAt:    conn.ConnectedAt,
			DisconnectedAt: disconnectedAt,
			Duration:       formatDuration(duration),
			SessionName:    conn.SessionName,
			Arguments:      conn.Arguments,
		}

		// Add to history (newest first)
		ct.history = append([]*ConnectionHistoryEntry{historyEntry}, ct.history...)

		// Trim history to max size
		if len(ct.history) > ct.maxHistory {
			ct.history = ct.history[:ct.maxHistory]
		}

		// Remove from active connections
		delete(ct.connections, id)
	}
}

// List returns all active connections
func (ct *ConnectionTracker) List() []*ConnectionInfo {
	ct.mu.RLock()
	defer ct.mu.RUnlock()

	connections := make([]*ConnectionInfo, 0, len(ct.connections))
	for _, conn := range ct.connections {
		connections = append(connections, conn)
	}

	return connections
}

// Count returns the number of active connections
func (ct *ConnectionTracker) Count() int {
	ct.mu.RLock()
	defer ct.mu.RUnlock()

	return len(ct.connections)
}

// GetHistory returns the connection history including active connections
func (ct *ConnectionTracker) GetHistory() []*ConnectionHistoryEntry {
	ct.mu.RLock()
	defer ct.mu.RUnlock()

	// Create a combined list starting with active connections
	combined := make([]*ConnectionHistoryEntry, 0, len(ct.connections)+len(ct.history))

	// Add active connections first (they're the most recent)
	for _, conn := range ct.connections {
		entry := &ConnectionHistoryEntry{
			RemoteAddr:     conn.RemoteAddr,
			ConnectedAt:    conn.ConnectedAt,
			DisconnectedAt: time.Time{}, // Zero time indicates still connected
			Duration:       formatDuration(time.Since(conn.ConnectedAt)),
			SessionName:    conn.SessionName,
			Arguments:      conn.Arguments,
		}
		combined = append(combined, entry)
	}

	// Add historical connections
	combined = append(combined, ct.history...)

	return combined
}

// formatDuration formats a duration into a human-readable string
func formatDuration(d time.Duration) string {
	if d < time.Second {
		return "< 1s"
	}

	seconds := int(d.Seconds())
	minutes := seconds / 60
	hours := minutes / 60

	if hours > 0 {
		return formatTime(hours, "h", minutes%60, "m")
	} else if minutes > 0 {
		return formatTime(minutes, "m", seconds%60, "s")
	}
	return formatTime(seconds, "s", 0, "")
}

func formatTime(val1 int, unit1 string, val2 int, unit2 string) string {
	if val2 > 0 {
		return formatInt(val1) + unit1 + " " + formatInt(val2) + unit2
	}
	return formatInt(val1) + unit1
}

func formatInt(n int) string {
	if n < 10 {
		return "0" + string(rune('0'+n))
	}
	// Simple integer to string conversion for small numbers
	result := ""
	for n > 0 {
		result = string(rune('0'+(n%10))) + result
		n /= 10
	}
	return result
}
