package postgres

import (
	"context"
	"errors"
	"fmt"
	"log"
	"my_app/backend/internal/dto"
	"my_app/backend/internal/models"
	"my_app/backend/internal/register"
	"my_app/backend/internal/utils"
	"net/http"
	"strings"

	"github.com/Nerzal/gocloak/v13"
	"github.com/google/uuid"
	"gorm.io/gorm"
)

type UserRepo struct {
	db     *gorm.DB
	kc     *gocloak.GoCloak
	kcConf utils.KeycloakConfig
}

func NewUserRepo(db *gorm.DB, kcConf utils.KeycloakConfig) *UserRepo {
	return &UserRepo{db: db, kc: gocloak.NewClient(kcConf.URL), kcConf: kcConf}
}

func (r *UserRepo) Register(username, firstName, lastName, password, email string) (uuid.UUID, error) {
	ctx := context.Background()
	client := r.kc
	realm := r.kcConf.Realm
	adminToken, err := client.LoginAdmin(ctx, r.kcConf.AdminUser, r.kcConf.AdminPassword, r.kcConf.AdminRealm)
	if err != nil {
		return uuid.Nil, err
	}
	user := gocloak.User{
		Username:  gocloak.StringP(username),
		Email:     gocloak.StringP(email),
		Enabled:   gocloak.BoolP(true),
		FirstName: gocloak.StringP(firstName),
		LastName:  gocloak.StringP(lastName),
	}

	createdUserID, err := client.CreateUser(ctx, adminToken.AccessToken, realm, user)
	if err != nil {
		var apiErr *gocloak.APIError
		if errors.As(err, &apiErr) && apiErr.Code == http.StatusConflict {
			return uuid.Nil, register.ErrEmailTaken
		}
		if strings.Contains(err.Error(), "409") {
			return uuid.Nil, register.ErrEmailTaken
		}
		return uuid.Nil, fmt.Errorf("create keycloak user: %w", err)
	}

	if err := client.SetPassword(ctx, adminToken.AccessToken, createdUserID, realm, password, false); err != nil {
		_ = client.DeleteUser(ctx, adminToken.AccessToken, realm, createdUserID)
		return uuid.Nil, err
	}

	id, err := uuid.Parse(createdUserID)
	if err != nil {
		_ = client.DeleteUser(ctx, adminToken.AccessToken, realm, createdUserID)
		return uuid.Nil, err
	}

	u := models.User{
		BaseModel: models.BaseModel{ID: id},
		FirstName: firstName,
		LastName:  lastName,
		Email:     email,
	}
	if err := r.db.Create(&u).Error; err != nil {
		_ = client.DeleteUser(ctx, adminToken.AccessToken, realm, createdUserID)
		if errors.Is(err, gorm.ErrDuplicatedKey) {
			return uuid.Nil, register.ErrEmailTaken
		}
		return uuid.Nil, err
	}
	return id, nil
}
func (r *UserRepo) Login(email, password string) (dto.LoginResponse, error) {
	// offline_access makes the refresh token an offline token, which outlives
	// the 30-minute SSO session so the app can keep the user signed in.
	token, err := r.kc.GetToken(context.Background(), r.kcConf.Realm, gocloak.TokenOptions{
		ClientID:     &r.kcConf.ClientID,
		ClientSecret: &r.kcConf.ClientSecret,
		GrantType:    gocloak.StringP("password"),
		Username:     &email,
		Password:     &password,
		Scope:        gocloak.StringP("openid offline_access"),
	})
	if err != nil {
		log.Printf("Error authenticating: %v", err)
		return dto.LoginResponse{}, register.ErrInvalidCredentials
	}
	resp := dto.LoginResponse{
		AccessToken:      token.AccessToken,
		RefreshToken:     token.RefreshToken,
		TokenType:        token.TokenType,
		ExpiresIn:        token.ExpiresIn,
		RefreshExpiresIn: token.RefreshExpiresIn,
	}
	return resp, nil

}
