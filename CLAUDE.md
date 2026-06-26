# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Commands

```bash
flutter pub get                          # install dependencies
flutter run                             # run debug on connected device
flutter build apk --release             # release APK
flutter build apk --debug               # debug APK
flutter analyze                         # static analysis
```

## Architecture Overview

**OffGrid SOS** — offline P2P emergency communication app (no internet required for core features).

### Transport Layer

Abstract interface: `lib/core/transport.dart` — defines `Transport`, `Peer`, `Message`, `ReceivedFile`, `DiscoveryState`.

Four implementations (switchable at runtime via `AppState.selectedProtocol`):
- `lib/core/nearby_transport.dart` — Google Nearby Connections (`P2P_CLUSTER`, serviceId `com.example.offgrid_sos.nearby`). Primary P2P module.
- `lib/core/ble_transport.dart` — BLE GATT, dual Central+Peripheral roles, 15s scan restart.
- `lib/core/mesh_transport.dart` — Wraps `NearbyTransport`, adds TTL-based multi-hop routing (HELLO/PEER_LIST_REQUEST every 30s).
- `lib/core/wifi_direct_transport.dart` — MethodChannel `wifi_direct` → native Android `WifiP2pManager`, periodic discovery every 45s.

### State Management

`AppState` (`lib/core/app_state.dart`) is a top-level `final` global singleton (`ChangeNotifier`). No Provider/Riverpod — accessed directly as `appState`. Initialized in `lib/main.dart`, device name set from SharedPreferences before UI starts.

Key timers running in `AppState`:
- Keep Alive: 30s → sends `KEEP_ALIVE:timestamp` to connected peers
- Connection Monitor: 10s → reconnects only when SOS/Rescue status active
- Stable Peers cleanup: 5s → removes peers not seen for 45s
- Location Broadcast: 8s → sends GPS to peers

Mock peers (debug UI) are stored in `_mockPeers` (separate from `_peers`) so transport events don't clear them.

### Chat Systems

Two separate systems:
1. **Emergency P2P chat** (`ChatMessage`) — stored in `lib/core/chat_db.dart` (SQLite), transported over the active P2P transport
2. **Friend cloud chat** (`FriendChatMessage`) — stored in `lib/core/chat_db.dart`, uses Firebase Firestore

### Firebase Layer

Online features only: Firestore (friend profiles, cloud messages), Firebase Storage (file sharing), FCM (push notifications via `lib/core/fcm_service.dart`). Firebase is optional — core P2P works fully offline.

### Android Permissions Required

| Permission | Android Version | Purpose |
|---|---|---|
| `ACCESS_FINE_LOCATION` | All | Nearby, WiFi scanning |
| `BLUETOOTH_SCAN/CONNECT/ADVERTISE` | 12+ | Nearby, BLE |
| `NEARBY_WIFI_DEVICES` | 13+ | WiFi component of Nearby |

## Known Active Issues (see note.md)

- **WiFi Direct**: shows system confirmation dialog on first connect; peer status/distance not displayed
- **BLE/Mesh**: not yet tested on real devices
- **`MeshTransport._startPeriodicScan()`**: timer fires every 20s but body is empty — no actual restart happens
- **Multiple transport listeners**: switching transport via `_subs()` adds new `onPeers.listen` without cancelling old one
- **Connection Monitor** only auto-reconnects when SOS or Rescue status is active — passive mode has no reconnect
