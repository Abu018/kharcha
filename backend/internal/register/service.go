package register

import (
	"encoding/json"
	"fmt"
	"my_app/backend/internal/dto"
	"my_app/backend/internal/utils"
	"net/http"
	"net/url"
	"strings"
	"time"

	"github.com/google/uuid"
)

type AuthService struct {
	repo Repo
	kc   utils.KeycloakConfig
}

func NewAuthService(repo Repo, kc utils.KeycloakConfig) *AuthService {
	return &AuthService{repo: repo, kc: kc}
}

var keycloakClient = &http.Client{Timeout: 15 * time.Second}

type Token struct {
	AccessToken  string `json:"access_token"`
	RefreshToken string `json:"refresh_token"`
	TokenType    string `json:"token_type"`
	ExpiresIn    int    `json:"expires_in"`
}

func (r AuthService) Register(user_name, first_name, last_name, password, email string) (uuid.UUID, error) {
	ok, err := r.repo.Register(user_name, first_name, last_name, password, email)
	if err != nil {
		return uuid.Nil, err
	}
	return ok, nil
}
func (r AuthService) Login(email, password string) (dto.LoginResponse, error) {
	ok, err := r.repo.Login(email, password)
	if err != nil {
		return dto.LoginResponse{}, err
	}
	return ok, nil
}
func (r *AuthService) RefreshToken(
	refreshToken string,
) (Token, error) {
	var result Token

	data := url.Values{}
	data.Set("client_id", r.kc.ClientID)
	data.Set("client_secret", r.kc.ClientSecret)
	data.Set("grant_type", "refresh_token")
	data.Set("refresh_token", refreshToken)

	endpoint := strings.TrimRight(r.kc.URL, "/") +
		"/realms/" + url.PathEscape(r.kc.Realm) +
		"/protocol/openid-connect/token"

	resp, err := keycloakClient.PostForm(endpoint, data)
	if err != nil {
		return Token{}, err
	}
	defer resp.Body.Close()

	// Keycloak answers 400 invalid_grant for expired or revoked refresh tokens.
	if resp.StatusCode == http.StatusBadRequest || resp.StatusCode == http.StatusUnauthorized {
		return Token{}, ErrInvalidRefreshToken
	}
	if resp.StatusCode != http.StatusOK {
		return Token{}, fmt.Errorf(
			"keycloak returned status: %d", resp.StatusCode,
		)
	}

	if err := json.NewDecoder(resp.Body).Decode(&result); err != nil {
		return Token{}, err
	}

	return result, nil
}
