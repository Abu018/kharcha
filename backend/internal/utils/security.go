package utils

import (
	"crypto/hmac"
	"crypto/rand"
	"crypto/sha256"
	"encoding/hex"
	"strconv"
	"time"
)

const TemporaryIDSlot = 15 * time.Minute

func GenerateSecretKey() ([]byte, error) {
	key := make([]byte, 32)

	_, err := rand.Read(key)
	if err != nil {
		return nil, err
	}

	return key, nil
}

func SlotSeconds() int64 {
	return int64(TemporaryIDSlot / time.Second)
}

func TimeSlot(t time.Time) int64 {
	return t.Unix() / SlotSeconds()
}

func SlotEnd(slot int64) time.Time {
	return time.Unix((slot+1)*SlotSeconds(), 0)
}

func GenerateTemporaryID(secret []byte, slot int64) string {
	message := strconv.FormatInt(slot, 10)

	h := hmac.New(sha256.New, secret)
	h.Write([]byte(message))

	hash := h.Sum(nil)

	return hex.EncodeToString(hash[:8])
}
