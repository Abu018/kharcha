package register

import (
	"errors"
	"my_app/backend/internal/dto"

	"github.com/google/uuid"
)

var ErrEmailTaken = errors.New("Email already registered")
var ErrInvalidCredentials = errors.New("Error Invalid Credentials")
var ErrInvalidRefreshToken = errors.New("invalid or expired refresh token")

type Repo interface {
	Register(user_name, first_name, last_name, password, email string) (uuid.UUID, error)
	Login(email, password string) (dto.LoginResponse, error)
}
