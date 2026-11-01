package postgres

import (
	"context"
	"encoding/hex"
	"errors"
	"log"
	"my_app/backend/internal/models"
	"my_app/backend/internal/utils"
	"time"

	"github.com/google/uuid"
	"gorm.io/gorm"
	"gorm.io/gorm/clause"
)

type SecretKey struct {
	db *gorm.DB
}

func NewSecretKeyRepo(db *gorm.DB) *SecretKey {
	return &SecretKey{db: db}
}
func (r *SecretKey) HasSecretKey(userID uuid.UUID) (string, error) {
	var k models.UserPresenceKeys
	err := r.db.Where("user_id = ?", userID).First(&k).Error
	if err == nil {
		return k.SecretKey, nil
	}
	if !errors.Is(err, gorm.ErrRecordNotFound) {
		return "", err
	}
	raw, err := utils.GenerateSecretKey()
	if err != nil {
		return "", err
	}
	k = models.UserPresenceKeys{UserID: userID, SecretKey: hex.EncodeToString(raw)}
	if err := r.db.Clauses(clause.OnConflict{DoNothing: true}).Create(&k).Error; err != nil {
		return "", err
	}
	// Another login may have created it first; read whichever row won.
	err = r.db.Where("user_id = ?", userID).First(&k).Error
	return k.SecretKey, err
}

func (r *SecretKey) GenerateTemporaryID(userID uuid.UUID, key string) error {
	secret, err := hex.DecodeString(key)
	if err != nil {
		return err
	}
	slot := utils.TimeSlot(time.Now())
	if err := r.insertTemporaryID(userID, secret, slot); err != nil {
		return err
	}
	return r.insertTemporaryID(userID, secret, slot+1)
}

// CurrentTemporaryID returns the IDs the phone should advertise now and in
// the next 15-minute slot, creating them if this user has none yet.
func (r *SecretKey) CurrentTemporaryID(userID uuid.UUID) (current, next models.Ephemeral, err error) {
	key, err := r.HasSecretKey(userID)
	if err != nil {
		return models.Ephemeral{}, models.Ephemeral{}, err
	}
	if err := r.GenerateTemporaryID(userID, key); err != nil {
		return models.Ephemeral{}, models.Ephemeral{}, err
	}
	slot := utils.TimeSlot(time.Now())
	current, err = r.lookupTemporaryID(userID, slot)
	if err != nil {
		return models.Ephemeral{}, models.Ephemeral{}, err
	}
	next, err = r.lookupTemporaryID(userID, slot+1)
	if err != nil {
		return models.Ephemeral{}, models.Ephemeral{}, err
	}
	return current, next, nil
}

func (r *SecretKey) lookupTemporaryID(userID uuid.UUID, slot int64) (models.Ephemeral, error) {
	var e models.Ephemeral
	err := r.db.Where("user_id = ? AND time_slot = ?", userID, slot).First(&e).Error
	return e, err
}

func (r *SecretKey) insertTemporaryID(userID uuid.UUID, secret []byte, slot int64) error {
	e := models.Ephemeral{
		UserID:    userID,
		Key:       utils.GenerateTemporaryID(secret, slot),
		TimeSlot:  slot,
		ExpiresAt: utils.SlotEnd(slot),
	}
	// Same user and slot always give the same key, so a repeat write is a no-op.
	return r.db.Clauses(clause.OnConflict{
		Columns:   []clause.Column{{Name: "user_id"}, {Name: "time_slot"}},
		DoNothing: true,
	}).Create(&e).Error
}

// RotateTemporaryIDs writes the current and next 15-minute IDs for every
// user who already has a presence key, then drops expired rows.
func (r *SecretKey) RotateTemporaryIDs() (int, error) {
	var keys []models.UserPresenceKeys
	if err := r.db.Find(&keys).Error; err != nil {
		return 0, err
	}
	slot := utils.TimeSlot(time.Now())
	for _, k := range keys {
		secret, err := hex.DecodeString(k.SecretKey)
		if err != nil {
			return 0, err
		}
		if err := r.insertTemporaryID(k.UserID, secret, slot); err != nil {
			return 0, err
		}
		if err := r.insertTemporaryID(k.UserID, secret, slot+1); err != nil {
			return 0, err
		}
	}
	if err := r.db.Where("expires_at < ?", time.Now()).Delete(&models.Ephemeral{}).Error; err != nil {
		return 0, err
	}
	return len(keys), nil
}

// RunTemporaryIDScheduler writes IDs on startup, then again at every
// 15-minute slot boundary.
func (r *SecretKey) RunTemporaryIDScheduler(ctx context.Context) {
	for {
		n, err := r.RotateTemporaryIDs()
		if err != nil {
			log.Printf("temporary id rotate failed: %v", err)
		} else {
			log.Printf("temporary ids rotated for %d users, slot %d", n, utils.TimeSlot(time.Now()))
		}
		timer := time.NewTimer(time.Until(utils.SlotEnd(utils.TimeSlot(time.Now()))))
		select {
		case <-ctx.Done():
			timer.Stop()
			return
		case <-timer.C:
		}
	}
}
