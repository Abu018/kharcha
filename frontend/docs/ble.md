# Kharcha Frontend: BLE Advertising and Nearby Device Scanning

This document explains the mobile-app work required to broadcast a
user's rotating temporary ID over Bluetooth Low Energy (BLE), detect
other Kharcha users nearby, and send detections to the Go backend.

> **Important:** BLE advertising and scanning must run on the mobile
> device. The Go backend does not control the phone's Bluetooth
> hardware. The backend **creates, stores, and rotates** temporary IDs.
> The app only fetches the current ID and puts it in the advertisement.
> The phone never sees the permanent secret and never computes HMAC.

## 1. Architecture at a glance

Each participating phone can perform both roles:

-   **Advertiser:** broadcasts its own Kharcha BLE advertisement
    containing the temporary ID the backend issued.
-   **Scanner:** discovers other Kharcha advertisements and extracts
    their temporary IDs and RSSI values.

Typical flow:

1.  After sign-in, the authenticated app calls
    `GET /api/v1/presence/temporary-id`.
2.  The backend returns the current 16-character ID and when it expires
    (plus the next slot, so the phone can rotate without a gap).
3.  The app puts that ID in BLE Service Data and starts advertising.
    It does **not** derive the ID from a secret.
4.  At `expires_at`, the app advertises `next_temporary_id` (if it
    already has it) and fetches the new pair from the backend.
5.  The app scans for advertisements containing the Kharcha service
    UUID.
6.  It extracts the temporary ID, records RSSI, and counts repeated
    sightings during a short scan window.
7.  It sends the sightings to the Go backend over HTTPS.
8.  The backend looks the IDs up in the `ephemeral` table and returns
    eligible users.
9.  The payer confirms the people to include in the split.

## 2. What belongs in the frontend and backend?

  ------------------------------------------------------------------------------
  Responsibility                       Mobile frontend                Go backend
  -------------------------- ------------------------- -------------------------
  Create a user's permanent                                                  Yes
  secret                                               

  Store the permanent secret                                                 Yes
  securely in PostgreSQL                               

  HMAC the secret with the                                                   Yes
  15-minute time slot                                  

  Store current/next                                                         Yes
  temporary IDs in                                     
  `ephemeral`                                          

  Rotate IDs at each slot                                                    Yes
  boundary (`RunTemporaryID                            
  Scheduler`)                                          

  Deliver `{temporary_id,                                                    Yes
  expires_at}` to the                                  
  authenticated device                                 

  Fetch the current ID over                        Yes 
  HTTPS                                                

  Put the ID in BLE Service                        Yes 
  Data                                                 

  Advertise and scan using                         Yes 
  BLE                                                  

  Extract temporary IDs and                        Yes 
  RSSI                                                 

  Send sightings to the API                        Yes 

  Match IDs to eligible                                                      Yes
  users (lookup `ephemeral`)                           

  Return nearby-user                                                         Yes
  suggestions                                          
  ------------------------------------------------------------------------------

The permanent secret **never leaves the server**. Do not put HMAC, time
slots, or Keychain storage of a presence secret in the app.

## 3. Temporary ID from the backend

The backend creates one permanent secret per user (`UserPresenceKeys`)
and derives a new ID every 15 minutes:

``` text
time_slot    = floor(unix_time / 900)
temporary_id = hex(first 8 bytes of HMAC-SHA256(secret, slot_as_decimal))
```

That algorithm lives only in Go (`utils.GenerateTemporaryID`). The app
must not reimplement it.

`RunTemporaryIDScheduler` writes the current and next slot for every
user who has a secret, on process start and at each slot boundary.
Login also writes those two rows so a brand-new user does not wait for
the next tick.

### Fetch contract

``` http
GET /api/v1/presence/temporary-id
Authorization: Bearer <access-token>
```

Example response envelope:

``` json
{
  "success": true,
  "message": "temporary id",
  "data": {
    "temporary_id": "a1b2c3d4e5f60718",
    "expires_at": "2026-11-02T04:15:00Z",
    "next_temporary_id": "9f8e7d6c5b4a3210",
    "next_expires_at": "2026-11-02T04:30:00Z"
  }
}
```

-   `temporary_id` is 16 lowercase hex characters. Advertise this.
-   `expires_at` is the end of the current 15-minute slot (UTC).
-   `next_temporary_id` / `next_expires_at` are the following slot, so
    the advertiser can switch at the boundary even if the network is
    slow.
-   Call this whenever advertising starts, when the cached ID has
    expired, and after a token refresh that starts a new session.
-   Do not cache the ID past `expires_at`. In-memory is enough; it is
    about to be broadcast over BLE anyway.

## 4. Embedding the temporary ID in BLE

Use a dedicated Kharcha BLE Service UUID. The mobile advertiser places
the backend-issued ID in the service's **Service Data** field.

Conceptual advertisement:

``` text
BLE advertisement
├── Kharcha Service UUID: <agreed-service-uuid>
└── Service Data:
    └── temporary ID bytes: <temporary_id from the API>
```

The UUID identifies the Kharcha advertisement format. The Service Data
carries the temporary ID.

The exact mobile API call depends on the framework and operating system.
Use a BLE library that supports both: - Advertising with a custom
service UUID and service data. - Scanning advertisements and reading
service data and RSSI.

Do not use the phone's Bluetooth device name as the user's identity. Do
not require pairing or a GATT connection just to discover an
advertisement.

### Advertisement size

Legacy BLE advertising packets have a small payload budget (commonly 31
bytes for the advertising data). The service UUID and 8-byte ID are
small enough for legacy packets. Extended advertising is not supported
consistently across all phones and OS versions.

## 5. Advertising flow

When the user enables nearby discovery or enters an appropriate app
flow:

1.  Check Bluetooth availability and permissions.
2.  Check that the device supports BLE peripheral advertising.
3.  `GET /api/v1/presence/temporary-id` (or reuse an in-memory ID that
    has not reached `expires_at`).
4.  Encode `temporary_id` as 8 raw bytes (decode the hex).
5.  Start BLE advertising with the Kharcha service UUID and Service
    Data.
6.  At `expires_at`, switch Service Data to `next_temporary_id` and
    fetch the next pair from the backend.
7.  Stop advertising when the user disables discovery, logs out, or the
    discovery session ends.

Conceptual pseudocode:

``` text
pair = GET /api/v1/presence/temporary-id

startBLEAdvertising(
    serviceUUID = KHARCHA_SERVICE_UUID,
    serviceData = hexDecode(pair.temporary_id)
)

on pair.expires_at:
    updateServiceData(hexDecode(pair.next_temporary_id))
    pair = GET /api/v1/presence/temporary-id
```

The pseudocode describes the flow, not a drop-in library API.

## 6. Scanning flow

When the payer taps **Find Nearby Friends**:

1.  Check Bluetooth state and scan permissions.
2.  Start scanning for the Kharcha service UUID.
3.  For each matching advertisement, read its Service Data.
4.  Encode the 8 bytes as 16 lowercase hex characters (the same form
    the backend stored).
5.  Read RSSI from the scan result.
6.  Aggregate repeated detections by temporary ID during a short scan
    window.
7.  Send the resulting sightings to the backend.
8.  Stop scanning when the window ends or the user cancels.

Example aggregated data:

``` json
{
  "sightings": [
    {
      "ephemeral_id": "a1b2c3d4e5f60718",
      "rssi": -58,
      "seen": 4
    },
    {
      "ephemeral_id": "1122334455667788",
      "rssi": -83,
      "seen": 1
    }
  ]
}
```

Field meanings:

-   `ephemeral_id`: temporary ID extracted from BLE Service Data.
-   `rssi`: a documented signal-strength statistic, such as the average
    RSSI during the scan window.
-   `seen`: number of matching advertisements observed during that
    window.

Avoid sending every raw scan callback if you can aggregate locally. Do
not assume `seen` means a precise number of seconds or a distance
measurement.

## 7. Sending sightings to the Go backend

Send the aggregated results to an authenticated HTTPS endpoint, for
example:

``` http
POST /api/v1/presence/sightings
Authorization: Bearer <access-token>
Content-Type: application/json
```

Example request:

``` json
{
  "sightings": [
    {
      "ephemeral_id": "a1b2c3d4e5f60718",
      "rssi": -58,
      "seen": 4
    }
  ]
}
```

The backend should derive the payer's user ID from the authenticated
session/token, not trust a `user_id` supplied in the request. The
backend should validate ID format (16 lowercase hex characters), scan
window freshness, rate limits, and whether a matched user is eligible
to be suggested (for example, a member of a shared group).

Matching is a lookup of `ephemeral.key` for the current (and still-valid
previous) slot. The backend does not ask the phone to help compute IDs.

## 8. RSSI and nearby filtering

RSSI is a rough radio-signal measurement, usually expressed in dBm.
Values closer to zero are stronger:

    Example RSSI General interpretation
  -------------- ------------------------
         -45 dBm Strong
         -60 dBm Fairly strong
         -75 dBm Weaker
         -90 dBm Very weak

These values do **not** map reliably to exact distances. Walls, bodies,
phone orientation, antenna design, interference, and device differences
all affect RSSI.

Use RSSI and repeated sightings as signals for ranking or filtering, not
proof that a person is physically present. Tune thresholds through
real-world testing. Always let the payer confirm suggested participants
before creating a split.

## 9. Permissions and platform limitations

BLE behavior differs between Android and iOS and between OS versions.

The mobile implementation must: - Request the appropriate Bluetooth
permissions for the OS version. - Explain why Kharcha needs
nearby-device discovery. - Handle Bluetooth being disabled, permission
denial, unsupported advertising, and scan failures. - Handle app
backgrounding, screen lock, battery-saving modes, and OS throttling. -
Test advertising and scanning on actual Android and iPhone devices.

Do not promise continuous background advertising or scanning. Mobile
operating systems restrict background BLE behavior, and iOS and Android
have different rules. Prefer a user-initiated, time-limited discovery
session around the expense-splitting flow. Review the current platform
documentation and the chosen BLE library's limitations before
implementation.

## 10. Security and privacy checklist

-   [ ] Advertise only the backend-issued temporary ID, never the
    permanent secret.
-   [ ] Keep the permanent secret on the server only. The app must not
    download it, store it, or HMAC it.
-   [ ] Use a cryptographically secure random secret generated by the
    backend.
-   [ ] Use HTTPS and authenticated API requests.
-   [ ] Treat `expires_at` from the API as the rotation clock; do not
    hard-code 15 minutes in Dart.
-   [ ] Apply rate limits and reject malformed or stale sightings.
-   [ ] Remember that a captured advertisement can be replayed until
    `expires_at`; rotating IDs alone do not prevent replay.
-   [ ] Do not treat RSSI as proof of physical presence.
-   [ ] Ask the payer to confirm participants.
-   [ ] Provide clear controls to enable/disable discovery.
-   [ ] Minimize retention of raw sightings; keep only what is needed
    for the feature.

For stronger protection against replay or deliberate spoofing, design a
separate challenge-response or authenticated connection step. A rotating
broadcast ID by itself is a discovery hint, not proof of identity or
presence.

## 11. Suggested frontend modules

Keep BLE responsibilities separate from screens and API calls. One
possible structure:

``` text
frontend/lib/
├── api/
│   └── presence_api.dart          # GET /api/v1/presence/temporary-id
├── models/
│   └── temporary_id.dart
├── services/
│   └── presence_service.dart      # cache + refresh at expires_at
└── features/presence/             # later, when BLE is wired
    ├── ble_advertiser
    ├── ble_scanner
    ├── sightings_aggregator
    └── find_nearby_friends_screen
```

There is no `temporary_id` HMAC helper and no Keystore entry for a
presence secret.

## 12. Before writing BLE-specific code

`GET /api/v1/presence/temporary-id` and the in-app fetch/refresh loop
are already implemented. Remaining decisions:

1.  Exact Kharcha service UUID.
2.  Sightings API request/response contract (`POST
    /api/v1/presence/sightings` is not served yet).
3.  Supported OS versions and background-discovery expectations.

**Implementation order:** first advertise and scan between two physical
phones using the ID from `GET /api/v1/presence/temporary-id`; then POST
sightings and participant confirmation.
