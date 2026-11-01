package utils

import (
	"bytes"
	"testing"
	"time"
)

func TestGenerateTemporaryIDIsDeterministicAndSlotScoped(t *testing.T) {
	secret := bytes.Repeat([]byte{1}, 32)
	a := GenerateTemporaryID(secret, 100)
	b := GenerateTemporaryID(secret, 100)
	if a != b {
		t.Fatalf("same slot produced %q and %q", a, b)
	}
	if len(a) != 16 {
		t.Fatalf("temporary id length %d, want 16 hex chars", len(a))
	}
	if GenerateTemporaryID(secret, 101) == a {
		t.Fatal("different slots produced the same id")
	}
}

func TestTimeSlotMatchesFifteenMinutes(t *testing.T) {
	slot := int64(1_888_888)
	start := time.Unix(slot*SlotSeconds(), 0)
	if TimeSlot(start) != slot {
		t.Fatalf("TimeSlot(%v) = %d, want %d", start, TimeSlot(start), slot)
	}
	if TimeSlot(start.Add(TemporaryIDSlot-time.Second)) != slot {
		t.Fatal("times in the same 15-minute window should share a slot")
	}
	if TimeSlot(start.Add(TemporaryIDSlot)) == slot {
		t.Fatal("the next 15-minute window should be a new slot")
	}
	if !SlotEnd(slot).Equal(start.Add(TemporaryIDSlot)) {
		t.Fatalf("SlotEnd = %v, want %v", SlotEnd(slot), start.Add(TemporaryIDSlot))
	}
}
