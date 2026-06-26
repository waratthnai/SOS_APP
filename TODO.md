# TODO

## iOS Support

- [ ] **WiFi Direct — iOS not supported**
  - `lib/core/wifi_direct_transport.dart` uses MethodChannel `wifi_direct` → Android only
  - `android/app/src/main/kotlin/.../WifiDirectChannel.kt` has no iOS counterpart
  - Options: implement Multipeer Connectivity or Bonjour-based transport for iOS
  - Other transports (Nearby, BLE, Mesh) should work on iOS already
