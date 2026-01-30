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

// ConnectionTracker tracks active WebSocket connections
type ConnectionTracker struct {
	mu          sync.RWMutex
	connections map[string]*ConnectionInfo
}

// NewConnectionTracker creates a new connection tracker
func NewConnectionTracker() *ConnectionTracker {
	return &ConnectionTracker{
		connections: make(map[string]*ConnectionInfo),
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

// Remove removes a connection from the tracker
func (ct *ConnectionTracker) Remove(id string) {
	ct.mu.Lock()
	defer ct.mu.Unlock()

	delete(ct.connections, id)
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
