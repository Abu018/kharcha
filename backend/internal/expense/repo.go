package expense

import (
	"errors"
	"my_app/backend/internal/models"

	"github.com/google/uuid"
)

// ErrDuplicate is returned by Create when the user already has a transaction
// with the same SourceRef.
var ErrDuplicate = errors.New("transaction already recorded")

type Repo interface {
	Create(tx *models.Transaction) error
	List(userID uuid.UUID, limit int) ([]models.Transaction, error)
	// Uncategorized returns transactions still waiting for a category.
	Uncategorized(limit int) ([]models.Transaction, error)
	SetCategory(id uuid.UUID, category string) error
}
