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

`AppState` itself only holds core lifecycle/orchestration (`_subs()` transport event dispatcher, login/logout, background service). Its `with` clause mixes in several `mixin`s, each in its own `part` file (`lib/core/app_state_*.dart`) sharing the same library via `part of 'app_state.dart';` — this is required because Dart privacy (`_`-prefixed members) is per-*library*, not per-class, so a mixin split across a normal `import` couldn't reach `AppState`'s private fields:
- `app_state_location.dart` — own-position GPS broadcast/stream
- `app_state_connection_monitor.dart` — keep-alive heartbeat + reconnect monitor
- `app_state_stable_peers.dart` — stable peer list + cleanup timer
- `app_state_online_status.dart` — Firebase online-status heartbeat
- `app_state_sos_rescue.dart` — SOS/Rescue mode toggle, broadcast, and incoming peer-status handling
- `app_state_mesh_peers.dart` — peer GPS tracking + mesh relay dedup/TTL/topology stats
- `app_state_emergency_chat.dart` — both P2P emergency chat and friend cloud chat (kept together; they share `_chatMessages`/`_friendChats` helpers too tightly to split further)

Key timers running in `AppState` (across the mixins above):
- Keep Alive: 30s → sends `KEEP_ALIVE:timestamp` to connected peers
- Connection Monitor: 10s → reconnects whenever scanning and no peers connected (all modes)
- Stable Peers cleanup: 5s → removes peers not seen for 45s
- Location Broadcast: 8s → sends GPS to peers

### Chat Systems

Two separate systems:
1. **Emergency P2P chat** (`ChatMessage`) — stored in `lib/core/chat_db.dart` (SQLite), transported over the active P2P transport
2. **Friend cloud chat** (`FriendChatMessage`) — stored in `lib/core/chat_db.dart`, uses Firebase Firestore

### UI Entry Point

`lib/main.dart` only holds `main()` and `OffGridApp`/`OffGridAppState` (the `MaterialApp` + theme wrapper). The top-level screens it used to contain live in `lib/ui/`: `root_nav.dart` (bottom nav), `home_screen.dart`, `settings_screen.dart`, `notifications_screen.dart`.

### Firebase Layer

Online features only: Firestore (friend profiles, cloud messages), Firebase Storage (file sharing), FCM (push notifications via `lib/core/fcm_service.dart`). Firebase is optional — core P2P works fully offline.

### Android Permissions Required

| Permission | Android Version | Purpose |
|---|---|---|
| `ACCESS_FINE_LOCATION` | All | Nearby, WiFi scanning |
| `BLUETOOTH_SCAN/CONNECT/ADVERTISE` | 12+ | Nearby, BLE |
| `NEARBY_WIFI_DEVICES` | 13+ | WiFi component of Nearby |

## Known Active Issues (see note.md)

- **WiFi Direct**: tested and working — do NOT modify. Shows system confirmation dialog on first connect (Android `WifiP2pManager` limitation — unavoidable); peer status/distance not displayed via RSSI (uses GPS diff instead)
- **BLE/Mesh**: not yet tested on real devices
