package profile

import (
	"context"
	"my_app/backend/internal/models"
	"strings"

	"github.com/google/uuid"
)

type Service struct {
	repo Repo
}

func NewService(repo Repo) *Service {
	return &Service{repo: repo}
}

func (s *Service) GetProfile(ctx context.Context, userID uuid.UUID) (models.User, error) {
	return s.repo.GetProfile(ctx, userID)
}

func (s *Service) UpdateProfile(ctx context.Context, userID uuid.UUID, u Update) (models.User, error) {
	u.FirstName = trimmed(u.FirstName)
	u.LastName = trimmed(u.LastName)
	return s.repo.UpdateProfile(ctx, userID, u)
}

func trimmed(s *string) *string {
	if s == nil {
		return nil
	}
	t := strings.TrimSpace(*s)
	return &t
}
