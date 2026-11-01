package dto

import "time"

// TemporaryID is the BLE payload the app advertises. The server derives it;
// the phone must not compute it.
type TemporaryID struct {
	TemporaryID     string    `json:"temporary_id"`
	ExpiresAt       time.Time `json:"expires_at"`
	NextTemporaryID string    `json:"next_temporary_id"`
	NextExpiresAt   time.Time `json:"next_expires_at"`
}
