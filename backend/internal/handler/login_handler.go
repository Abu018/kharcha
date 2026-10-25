package handler

import (
	"encoding/json"
	"errors"
	"log"
	"my_app/backend/internal/adapters/response"
	"my_app/backend/internal/register"
	"net/http"

	"github.com/go-playground/validator/v10"
	"github.com/google/uuid"
)

type RefreshTokenInput struct {
	RefreshToken string `json:"refresh_token"`
}
type Register struct {
	UserName  string `json:"user_name" validate:"required,min=2,max=50"`
	FirstName string `json:"first_name" validate:"required,min=2,max=50"`
	LastName  string `json:"last_name"  validate:"max=50"`
	Password  string `json:"password"   validate:"required,min=8,max=72"`
	Email     string `json:"email"      validate:"required,email"`
}
type LoginResponse struct {
	AccessToken      string    `json:"access_token"`
	RefreshToken     string    `json:"refresh_token"`
	TokenType        string    `json:"token_type"`
	ExpiresIn        int       `json:"expires_in"`
	RefreshExpiresIn int       `json:"refresh_expires_in"`
	UserId           uuid.UUID `json:"user_id"`
	UserName         string    `json:"user_name"`
}

type LoginInput struct {
	Email    string `json:"email"`
	Password string `json:"password"`
}

var validate = validator.New()

type AuthHandler struct {
	auth *register.AuthService
}

func NewAuthHandler(auth *register.AuthService) *AuthHandler {
	return &AuthHandler{auth: auth}
}
func (h *AuthHandler) Register(w http.ResponseWriter, r *http.Request) {
	var input Register
	if err := json.NewDecoder(r.Body).Decode(&input); err != nil {
		response.JSON(w, http.StatusBadRequest, response.Response{Success: false, Message: "invalid JSON"})
		return
	}
	if input.UserName == "" || input.FirstName == "" || input.LastName == "" || input.Password == "" || input.Email == "" {
		response.JSON(w, http.StatusBadRequest, response.Response{Success: false, Message: "invalid input"})
		return
	}
	_, err := h.auth.Register(input.UserName, input.FirstName, input.LastName, input.Password, input.Email)
	if err != nil {
		switch {
		case errors.Is(err, register.ErrEmailTaken):
			response.JSON(w, http.StatusConflict, response.Response{Success: false, Message: "email already registered"})
		default:
			log.Printf("register failed: %v", err)
			response.JSON(w, http.StatusInternalServerError, response.Response{Success: false, Message: "Internal Server Error"})
		}
		return
	}
	response.JSON(w, 200, response.Response{Success: true, Message: "Success"})

}
func (h *AuthHandler) Login(w http.ResponseWriter, r *http.Request) {
	var input LoginInput
	if err := json.NewDecoder(r.Body).Decode(&input); err != nil {
		response.JSON(w, http.StatusBadRequest, response.Response{Success: false, Message: "invalid JSON"})
		return
	}
	if input.Email == "" || input.Password == "" {
		response.JSON(w, http.StatusBadRequest, response.Response{Success: false, Message: "Invalid Input"})
		return
	}
	result, err := h.auth.Login(input.Email, input.Password)
	if err != nil {
		if errors.Is(err, register.ErrInvalidCredentials) {
			response.JSON(w, http.StatusUnauthorized, response.Response{Success: false, Message: "invalid email or password"})
			return
		}
		log.Printf("login failed: %v", err)
		response.JSON(w, http.StatusInternalServerError, response.Response{Success: false, Message: "Internal Server Error"})
		return
	}
	response.JSON(w, http.StatusOK, response.Response{Success: true, Message: "Login successful", Data: result})
}
func (h *AuthHandler) RefreshToken(w http.ResponseWriter, r *http.Request) {
	var input RefreshTokenInput
	if err := json.NewDecoder(r.Body).Decode(&input); err != nil {
		response.JSON(w, http.StatusBadRequest, response.Response{Success: false, Message: "invalid JSON"})
		return
	}
	if input.RefreshToken == "" {
		response.JSON(w, http.StatusBadRequest, response.Response{Success: false, Message: "refresh_token is required"})
		return
	}
	result, err := h.auth.RefreshToken(input.RefreshToken)
	if err != nil {
		if errors.Is(err, register.ErrInvalidRefreshToken) {
			response.JSON(w, http.StatusUnauthorized, response.Response{Success: false, Message: "invalid or expired refresh token"})
			return
		}
		log.Printf("refresh token failed: %v", err)
		response.JSON(w, http.StatusBadGateway, response.Response{Success: false, Message: "failed to refresh token"})
		return
	}
	response.JSON(w, http.StatusOK, response.Response{Success: true, Message: "Success", Data: result})
}
