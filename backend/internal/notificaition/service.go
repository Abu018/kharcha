package notification

import (
	"errors"
	"strings"
	"time"

	"github.com/google/uuid"
)

// deviceTokenTTL is how long a device token stays valid without the app
// registering it again.
const deviceTokenTTL = 60 * 24 * time.Hour

var ErrEmptyToken = errors.New("token is required")

type NotificationService struct {
	repo Repo
}

func NewNotificationService(repo Repo) *NotificationService {
	return &NotificationService{repo: repo}
}

func (s *NotificationService) RegisterDeviceToken(userID uuid.UUID, token string) error {
	token = strings.TrimSpace(token)
	if token == "" {
		return ErrEmptyToken
	}
	return s.repo.SaveDeviceToken(userID, token, time.Now().Add(deviceTokenTTL))
}
