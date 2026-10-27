package postgres

import (
	"context"
	"errors"
	"fmt"
	"my_app/backend/internal/models"
	"my_app/backend/internal/profile"

	"github.com/google/uuid"
	"gorm.io/gorm"
)

func (r *UserRepo) GetProfile(ctx context.Context, userID uuid.UUID) (models.User, error) {
	var user models.User
	err := r.db.WithContext(ctx).First(&user, "id = ?", userID).Error
	if errors.Is(err, gorm.ErrRecordNotFound) {
		return user, profile.ErrNotFound
	}
	return user, err
}

// UpdateProfile changes the given fields in Postgres and, when the name
// changes, in Keycloak too so new access tokens carry it. The database
// change is rolled back if Keycloak cannot be updated.
func (r *UserRepo) UpdateProfile(ctx context.Context, userID uuid.UUID, u profile.Update) (models.User, error) {
	var user models.User
	err := r.db.WithContext(ctx).Transaction(func(tx *gorm.DB) error {
		if err := tx.First(&user, "id = ?", userID).Error; err != nil {
			if errors.Is(err, gorm.ErrRecordNotFound) {
				return profile.ErrNotFound
			}
			return err
		}

		changes := map[string]any{}
		if u.FirstName != nil {
			changes["first_name"] = *u.FirstName
		}
		if u.LastName != nil {
			changes["last_name"] = *u.LastName
		}
		if u.Age != nil {
			changes["age"] = *u.Age
		}
		if u.Salary != nil {
			changes["salary"] = *u.Salary
		}
		if len(changes) == 0 {
			return nil
		}
		if err := tx.Model(&models.User{}).Where("id = ?", userID).Updates(changes).Error; err != nil {
			return err
		}
		if err := tx.First(&user, "id = ?", userID).Error; err != nil {
			return err
		}

		if u.FirstName != nil || u.LastName != nil {
			return r.updateKeycloakName(ctx, userID, user.FirstName, user.LastName)
		}
		return nil
	})
	return user, err
}

func (r *UserRepo) updateKeycloakName(ctx context.Context, userID uuid.UUID, firstName, lastName string) error {
	adminToken, err := r.kc.LoginAdmin(ctx, r.kcConf.AdminUser, r.kcConf.AdminPassword, r.kcConf.AdminRealm)
	if err != nil {
		return fmt.Errorf("keycloak admin login: %w", err)
	}
	kcUser, err := r.kc.GetUserByID(ctx, adminToken.AccessToken, r.kcConf.Realm, userID.String())
	if err != nil {
		return fmt.Errorf("get keycloak user: %w", err)
	}
	kcUser.FirstName = &firstName
	kcUser.LastName = &lastName
	if err := r.kc.UpdateUser(ctx, adminToken.AccessToken, r.kcConf.Realm, *kcUser); err != nil {
		return fmt.Errorf("update keycloak user: %w", err)
	}
	return nil
}
