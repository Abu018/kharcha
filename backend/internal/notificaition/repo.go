package notification

import (
	"time"

	"github.com/google/uuid"
)

type Repo interface {
	// SaveDeviceToken stores the token for the user, or moves its expiry
	// forward if the user already registered it.
	SaveDeviceToken(userID uuid.UUID, token string, expireIn time.Time) error
}
