package dto

import "github.com/google/uuid"

type LoginResponse struct {
	AccessToken      string    `json:"access_token"`
	RefreshToken     string    `json:"refresh_token"`
	TokenType        string    `json:"token_type"`
	ExpiresIn        int       `json:"expires_in"`
	RefreshExpiresIn int       `json:"refresh_expires_in"`
	UserId           uuid.UUID `json:"user_id"`
	UserName         string    `json:"user_name"`
}
