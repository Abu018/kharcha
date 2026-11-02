package presence

import (
	"regexp"
	"sort"
	"strings"
	"time"

	"my_app/backend/internal/dto"
	"my_app/backend/internal/models"
	"my_app/backend/internal/utils"

	"github.com/google/uuid"
)

const (
	// MaxSightings is the most IDs a phone may report in one request.
	MaxSightings = 50
	// InRangeRSSI is the weakest signal that still counts as nearby.
	InRangeRSSI = -85
)

var hexID = regexp.MustCompile(`^[0-9a-f]{16}$`)

type Repo interface {
	LookupEphemeral(keys []string, minSlot, maxSlot int64) ([]models.Ephemeral, error)
	SharedGroups(viewer uuid.UUID, others []uuid.UUID) (map[uuid.UUID][]dto.SharedGroup, error)
}

type Service struct {
	repo Repo
	now  func() time.Time
}

func NewService(repo Repo) *Service {
	return &Service{repo: repo, now: time.Now}
}

// Resolve maps BLE sightings to people who share a group with the caller.
// Unknown, expired, own, and non-group IDs are dropped, not returned as errors.
func (s *Service) Resolve(viewer uuid.UUID, in []dto.Sighting) (dto.NearbyUsers, error) {
	empty := dto.NearbyUsers{Users: []dto.NearbyUser{}}
	heard := mergeSightings(in)
	if len(heard) == 0 {
		return empty, nil
	}
	keys := make([]string, 0, len(heard))
	for id := range heard {
		keys = append(keys, id)
	}
	slot := utils.TimeSlot(s.now())
	rows, err := s.repo.LookupEphemeral(keys, slot-1, slot+1)
	if err != nil {
		return empty, err
	}

	type match struct {
		user models.User
		id   string
		rssi int
		seen int
	}
	byUser := map[uuid.UUID]*match{}
	for _, row := range rows {
		if row.UserID == viewer {
			continue
		}
		s, ok := heard[row.Key]
		if !ok {
			continue
		}
		existing := byUser[row.UserID]
		if existing == nil {
			byUser[row.UserID] = &match{user: row.User, id: row.Key, rssi: s.RSSI, seen: s.Seen}
			continue
		}
		existing.seen += s.Seen
		if s.RSSI > existing.rssi {
			existing.rssi = s.RSSI
			existing.id = row.Key
		}
	}
	if len(byUser) == 0 {
		return empty, nil
	}
	others := make([]uuid.UUID, 0, len(byUser))
	for id := range byUser {
		others = append(others, id)
	}
	groups, err := s.repo.SharedGroups(viewer, others)
	if err != nil {
		return empty, err
	}

	users := make([]dto.NearbyUser, 0, len(byUser))
	for id, m := range byUser {
		shared := groups[id]
		if len(shared) == 0 {
			continue
		}
		users = append(users, dto.NearbyUser{
			UserID:       id,
			EphemeralID:  m.id,
			FirstName:    m.user.FirstName,
			LastName:     m.user.LastName,
			RSSI:         m.rssi,
			Seen:         m.seen,
			InRange:      m.rssi >= InRangeRSSI,
			SharedGroups: shared,
		})
	}
	sort.Slice(users, func(i, j int) bool {
		if users[i].RSSI != users[j].RSSI {
			return users[i].RSSI > users[j].RSSI
		}
		return users[i].EphemeralID < users[j].EphemeralID
	})
	return dto.NearbyUsers{Users: users}, nil
}

func mergeSightings(in []dto.Sighting) map[string]dto.Sighting {
	out := map[string]dto.Sighting{}
	for _, s := range in {
		id := strings.ToLower(strings.TrimSpace(s.EphemeralID))
		if !hexID.MatchString(id) {
			continue
		}
		seen := s.Seen
		if seen < 1 {
			seen = 1
		}
		existing, ok := out[id]
		if !ok {
			out[id] = dto.Sighting{EphemeralID: id, RSSI: s.RSSI, Seen: seen}
			continue
		}
		existing.Seen += seen
		if s.RSSI > existing.RSSI {
			existing.RSSI = s.RSSI
		}
		out[id] = existing
	}
	return out
}
