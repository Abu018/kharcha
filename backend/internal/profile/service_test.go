package profile

import (
	"context"
	"my_app/backend/internal/models"
	"testing"

	"github.com/google/uuid"
)

type fakeRepo struct {
	got Update
}

func (f *fakeRepo) GetProfile(context.Context, uuid.UUID) (models.User, error) {
	return models.User{}, nil
}

func (f *fakeRepo) UpdateProfile(_ context.Context, _ uuid.UUID, u Update) (models.User, error) {
	f.got = u
	return models.User{}, nil
}

func TestUpdateProfileTrimsNamesAndKeepsOmittedFields(t *testing.T) {
	repo := &fakeRepo{}
	first, age := "  Ada ", 36

	if _, err := NewService(repo).UpdateProfile(context.Background(), uuid.New(), Update{FirstName: &first, Age: &age}); err != nil {
		t.Fatal(err)
	}
	if repo.got.FirstName == nil || *repo.got.FirstName != "Ada" {
		t.Errorf("FirstName = %v, want Ada", repo.got.FirstName)
	}
	if repo.got.LastName != nil || repo.got.Salary != nil {
		t.Errorf("omitted fields should stay nil: %+v", repo.got)
	}
	if repo.got.Age == nil || *repo.got.Age != 36 {
		t.Errorf("Age = %v, want 36", repo.got.Age)
	}
}
