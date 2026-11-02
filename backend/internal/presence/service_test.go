package presence

import (
	"testing"
	"time"

	"my_app/backend/internal/dto"
	"my_app/backend/internal/models"
	"my_app/backend/internal/utils"

	"github.com/google/uuid"
)

type fakeRepo struct {
	rows   []models.Ephemeral
	groups map[uuid.UUID][]dto.SharedGroup
	keys   []string
	min    int64
	max    int64
}

func (f *fakeRepo) LookupEphemeral(keys []string, minSlot, maxSlot int64) ([]models.Ephemeral, error) {
	f.keys, f.min, f.max = keys, minSlot, maxSlot
	var out []models.Ephemeral
	want := map[string]struct{}{}
	for _, k := range keys {
		want[k] = struct{}{}
	}
	for _, row := range f.rows {
		if _, ok := want[row.Key]; ok {
			out = append(out, row)
		}
	}
	return out, nil
}

func (f *fakeRepo) SharedGroups(_ uuid.UUID, others []uuid.UUID) (map[uuid.UUID][]dto.SharedGroup, error) {
	out := map[uuid.UUID][]dto.SharedGroup{}
	for _, id := range others {
		if g := f.groups[id]; len(g) > 0 {
			out[id] = g
		}
	}
	return out, nil
}

func TestResolveMapsEligibleSightings(t *testing.T) {
	viewer := uuid.MustParse("00000000-0000-0000-0000-000000000001")
	amit := uuid.MustParse("00000000-0000-0000-0000-000000000002")
	stranger := uuid.MustParse("00000000-0000-0000-0000-000000000003")
	groupID := uuid.MustParse("00000000-0000-0000-0000-0000000000aa")
	svc := NewService(&fakeRepo{
		rows: []models.Ephemeral{
			{UserID: viewer, Key: "aaaaaaaaaaaaaaaa", User: models.User{FirstName: "Me"}},
			{UserID: amit, Key: "1122334455667788", User: models.User{BaseModel: models.BaseModel{ID: amit}, FirstName: "Amit", LastName: "Shah"}},
			{UserID: stranger, Key: "deadbeefdeadbeef", User: models.User{FirstName: "Eve"}},
		},
		groups: map[uuid.UUID][]dto.SharedGroup{
			amit: {{ID: groupID, Name: "Goa trip"}},
		},
	})

	got, err := svc.Resolve(viewer, []dto.Sighting{
		{EphemeralID: "not-an-id", RSSI: -20, Seen: 9},
		{EphemeralID: "AAAAAAAAAAAAAAA", RSSI: -30, Seen: 2}, // own, too short
		{EphemeralID: "aaaaaaaaaaaaaaaa", RSSI: -40, Seen: 3},
		{EphemeralID: "1122334455667788", RSSI: -58, Seen: 4},
		{EphemeralID: "deadbeefdeadbeef", RSSI: -50, Seen: 2},
		{EphemeralID: "ffffffffffffffff", RSSI: -45, Seen: 1},
	})
	if err != nil {
		t.Fatal(err)
	}
	if len(got.Users) != 1 {
		t.Fatalf("users = %#v, want only Amit", got.Users)
	}
	u := got.Users[0]
	if u.UserID != amit || u.FirstName != "Amit" || u.LastName != "Shah" {
		t.Errorf("user = %+v", u)
	}
	if u.EphemeralID != "1122334455667788" || u.RSSI != -58 || u.Seen != 4 || !u.InRange {
		t.Errorf("radio = %+v", u)
	}
	if len(u.SharedGroups) != 1 || u.SharedGroups[0].Name != "Goa trip" {
		t.Errorf("groups = %+v", u.SharedGroups)
	}
}

func TestResolveMergesDuplicateIdsAndRanksByRssi(t *testing.T) {
	viewer := uuid.New()
	near := uuid.New()
	far := uuid.New()
	svc := NewService(&fakeRepo{
		rows: []models.Ephemeral{
			{UserID: near, Key: "1111111111111111", User: models.User{FirstName: "Near"}},
			{UserID: far, Key: "2222222222222222", User: models.User{FirstName: "Far"}},
		},
		groups: map[uuid.UUID][]dto.SharedGroup{
			near: {{Name: "Flat"}},
			far:  {{Name: "Flat"}},
		},
	})

	got, err := svc.Resolve(viewer, []dto.Sighting{
		{EphemeralID: "1111111111111111", RSSI: -80, Seen: 1},
		{EphemeralID: "1111111111111111", RSSI: -40, Seen: 2},
		{EphemeralID: "2222222222222222", RSSI: -90, Seen: 1},
	})
	if err != nil {
		t.Fatal(err)
	}
	if len(got.Users) != 2 {
		t.Fatalf("len = %d", len(got.Users))
	}
	if got.Users[0].FirstName != "Near" || got.Users[0].RSSI != -40 || got.Users[0].Seen != 3 {
		t.Errorf("first = %+v", got.Users[0])
	}
	if got.Users[1].FirstName != "Far" || got.Users[1].InRange {
		t.Errorf("second = %+v", got.Users[1])
	}
}

func TestResolveLooksUpCurrentAndAdjacentSlots(t *testing.T) {
	repo := &fakeRepo{}
	svc := NewService(repo)
	now := time.Date(2026, 11, 2, 4, 20, 0, 0, time.UTC)
	svc.now = func() time.Time { return now }

	if _, err := svc.Resolve(uuid.New(), []dto.Sighting{
		{EphemeralID: "a1b2c3d4e5f60718", RSSI: -50, Seen: 1},
	}); err != nil {
		t.Fatal(err)
	}
	slot := utils.TimeSlot(now)
	if repo.min != slot-1 || repo.max != slot+1 {
		t.Errorf("slots %d..%d, want %d..%d", repo.min, repo.max, slot-1, slot+1)
	}
}

func TestResolveEmptyInput(t *testing.T) {
	got, err := NewService(&fakeRepo{}).Resolve(uuid.New(), nil)
	if err != nil {
		t.Fatal(err)
	}
	if got.Users == nil || len(got.Users) != 0 {
		t.Errorf("users = %#v, want []", got.Users)
	}
}
