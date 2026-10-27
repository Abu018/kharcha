package profile

import (
	"context"
	"errors"
	"my_app/backend/internal/models"

	"github.com/google/uuid"
)

// ErrNotFound is returned when the signed-in user has no local profile row.
var ErrNotFound = errors.New("profile not found")

// Update holds the fields to change; nil fields are left as they are.
type Update struct {
	FirstName *string
	LastName  *string
	Age       *int
	Salary    *int64
}

type Repo interface {
	GetProfile(ctx context.Context, userID uuid.UUID) (models.User, error)
	UpdateProfile(ctx context.Context, userID uuid.UUID, u Update) (models.User, error)
}
