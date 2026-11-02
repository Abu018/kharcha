package dto

import (
	"time"

	"github.com/google/uuid"
)

// TemporaryID is the BLE payload the app advertises. The server derives it;
// the phone must not compute it.
type TemporaryID struct {
	TemporaryID     string    `json:"temporary_id"`
	ExpiresAt       time.Time `json:"expires_at"`
	NextTemporaryID string    `json:"next_temporary_id"`
	NextExpiresAt   time.Time `json:"next_expires_at"`
}

// SightingsInput is what a phone POSTs after a BLE scan window.
type SightingsInput struct {
	Sightings []Sighting `json:"sightings"`
}

// Sighting is one ephemeral ID heard over Bluetooth.
type Sighting struct {
	EphemeralID string `json:"ephemeral_id"`
	RSSI        int    `json:"rssi"`
	Seen        int    `json:"seen"`
}

// NearbyUsers is the resolved nearby list. Unknown or ineligible IDs are omitted.
type NearbyUsers struct {
	Users []NearbyUser `json:"users"`
}

// NearbyUser is someone the caller heard over BLE and is allowed to see.
type NearbyUser struct {
	UserID       uuid.UUID     `json:"user_id"`
	EphemeralID  string        `json:"ephemeral_id"`
	FirstName    string        `json:"first_name"`
	LastName     string        `json:"last_name"`
	RSSI         int           `json:"rssi"`
	Seen         int           `json:"seen"`
	InRange      bool          `json:"in_range"`
	SharedGroups []SharedGroup `json:"shared_groups"`
}

// SharedGroup is a group both the caller and the nearby user belong to.
type SharedGroup struct {
	ID   uuid.UUID `json:"id"`
	Name string    `json:"name"`
}
