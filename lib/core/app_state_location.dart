part of 'app_state.dart';

/// จัดการ Real-time GPS broadcast/stream ของตัวเอง — แยกออกจาก [AppState] หลัก
/// (Phase 1 ของ CLEANUP_PLAN.md) เพื่อลดขนาดไฟล์ app_state.dart
///
/// ใช้ `part of` (ไม่ใช่ import) เพื่อให้ mixin นี้เข้าถึง private member อื่น ๆ
/// ของ AppState ได้ตรง ๆ ตาม Dart privacy ที่เป็นระดับ library ไม่ใช่ระดับ class
mixin AppStateLocationMixin on ChangeNotifier {
  // ต้องมีสมาชิกเหล่านี้จาก AppState เอง (ประกาศเป็น concrete member อยู่แล้ว)
  Transport get transport;
  List<Peer> get peers;
  bool get isSOSActive;
  bool get isRescueMode;

  StreamSubscription<Position>?
  _locationStreamSubscription; // 📍 Real-time GPS Stream
  Position? _myCurrentPosition; // เก็บตำแหน่งปัจจุบันของตัวเอง

  // 📍 Getter สำหรับตำแหน่งปัจจุบัน (real-time)
  Position? get myCurrentPosition => _myCurrentPosition;

  // 🎯 กำหนด accuracy/distanceFilter ของ GPS stream ตามโหมดปัจจุบัน
  // SOS/Rescue = real-time high-accuracy (ต้องรู้ตำแหน่งแม่นยำเพื่อช่วยเหลือ/นำทาง)
  // Passive = ประหยัดแบต เพราะแค่รอสัญญาณเฉย ๆ ยังไม่ต้องตำแหน่งละเอียดระดับเมตร
  LocationSettings _currentLocationSettings() {
    final isActiveMode = isSOSActive || isRescueMode;
    return LocationSettings(
      accuracy: isActiveMode ? LocationAccuracy.high : LocationAccuracy.medium,
      distanceFilter: isActiveMode ? 5 : 30,
    );
  }

  /// เรียกทุกครั้งที่ SOS/Rescue mode เปลี่ยน เพื่อ restart GPS stream ด้วย
  /// accuracy/distanceFilter ที่เหมาะกับโหมดใหม่ (ไม่ทำอะไรถ้ายังไม่เคยเริ่ม stream)
  void _updateLocationBroadcastMode() {
    if (_locationStreamSubscription != null) {
      _startLocationBroadcast();
    }
  }

  // 📍 เริ่ม Real-time GPS Streaming - อัพเดททันทีเมื่อเคลื่อนที่
  void _startLocationBroadcast() async {
    _locationStreamSubscription?.cancel();

    try {
      // 🔒 เช็ค GPS permission ก่อน
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        Log.d('❌ GPS ถูกปิด - ไม่สามารถ broadcast ตำแหน่งได้');
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          Log.d('❌ ไม่ได้รับ GPS permission - ไม่สามารถ broadcast ตำแหน่งได้');
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        Log.d('❌ GPS permission ถูกปฏิเสธถาวร');
        return;
      }

      // 🎯 LocationSettings ผูกกับโหมด — high-accuracy/real-time เฉพาะตอน SOS/Rescue
      // ที่ต้องการตำแหน่งแม่นยำจริงๆ ส่วนโหมด passive (แค่เปิดแอพเฉยๆ) ใช้ความแม่นยำ
      // ปานกลาง + ระยะห่างกว้างขึ้น เพื่อประหยัดแบตในสถานการณ์ที่อาจไม่มีไฟฟ้า/สัญญาณนาน ๆ
      final locationSettings = _currentLocationSettings();

      // ⚡ ใช้ lastKnownPosition ทันที ก่อนที่ stream จะ fix ได้ (ลด cold-start latency)
      if (_myCurrentPosition == null) {
        Geolocator.getLastKnownPosition().then((last) {
          if (last != null && _myCurrentPosition == null) {
            _myCurrentPosition = last;
            Log.d(
              '📍 [GPS] ใช้ lastKnownPosition: ${last.latitude.toStringAsFixed(5)}, ${last.longitude.toStringAsFixed(5)}',
            );
            notifyListeners();
          }
        });
      }

      Log.d('📍 กำลังเริ่ม Real-time GPS Stream...');

      // 📡 เริ่ม listen GPS stream แบบ real-time
      _locationStreamSubscription =
          Geolocator.getPositionStream(
            locationSettings: locationSettings,
          ).listen(
            (Position position) {
              // ⚡ อัพเดทตำแหน่งปัจจุบันทันที
              _myCurrentPosition = position;

              // 📡 ส่งตำแหน่งไปให้ peers ทันที (ถ้ามี peer)
              if (peers.isNotEmpty) {
                final location = PeerLocation(
                  latitude: position.latitude,
                  longitude: position.longitude,
                  timestamp: DateTime.now(),
                );

                final message = 'GPS_LOC:${location.toString()}';
                transport
                    .sendMessage(message)
                    .then((_) {
                      Log.d(
                        '📍 [Real-time] ส่งตำแหน่ง: ${location.latitude.toStringAsFixed(6)}, ${location.longitude.toStringAsFixed(6)} (±${position.accuracy.toStringAsFixed(1)}m)',
                      );
                    })
                    .catchError((e) {
                      Log.d('❌ ส่งตำแหน่งล้มเหลว: $e');
                    });
              }

              // 🔄 อัพเดท UI ทันที
              notifyListeners();
            },
            onError: (e) {
              Log.d('❌ GPS Stream Error: $e');
              // 🔄 ลองเริ่มใหม่หลัง 5 วินาที
              Future.delayed(const Duration(seconds: 5), () {
                if (_locationStreamSubscription == null) {
                  Log.d('🔄 กำลังลอง restart GPS stream...');
                  _startLocationBroadcast();
                }
              });
            },
          );

      Log.d(
        '✅ เริ่ม Real-time GPS Stream สำเร็จ (อัพเดททุก 5m หรือเมื่อเคลื่อนที่)',
      );

      // Periodic fallback: ส่ง GPS ทุก 30 วินาทีแม้ไม่ขยับ
      Future.doWhile(() async {
        await Future.delayed(const Duration(seconds: 30));
        if (_locationStreamSubscription == null) {
          return false; // หยุดถ้า stream ถูกยกเลิก
        }
        _broadcastCurrentGPS();
        return true;
      });
    } catch (e) {
      Log.d('❌ ไม่สามารถเริ่ม GPS stream: $e');
    }
  }

  /// ส่ง GPS ปัจจุบันให้ peers ทันที (ใช้ตำแหน่งที่แคชไว้ หรือ fetch ใหม่ถ้าไม่มี)
  void _broadcastCurrentGPS() {
    if (peers.isEmpty) return;

    void sendLocation(double lat, double lng) {
      final loc = PeerLocation(
        latitude: lat,
        longitude: lng,
        timestamp: DateTime.now(),
      );
      transport.sendMessage('GPS_LOC:${loc.toString()}').catchError((_) {});
      Log.d(
        '📍 [GPS] broadcast: ${lat.toStringAsFixed(5)}, ${lng.toStringAsFixed(5)}',
      );
    }

    if (_myCurrentPosition != null) {
      sendLocation(_myCurrentPosition!.latitude, _myCurrentPosition!.longitude);
    } else {
      // ยังไม่มีตำแหน่งในแคช → ลอง fetch (medium accuracy = เร็วกว่า high)
      Geolocator.getCurrentPosition(
            desiredAccuracy: LocationAccuracy.medium,
            timeLimit: const Duration(seconds: 8),
          )
          .then((pos) {
            _myCurrentPosition = pos;
            sendLocation(pos.latitude, pos.longitude);
            notifyListeners(); // ให้ UI คำนวณระยะห่างใหม่
          })
          .catchError((e) {
            Log.d('⚠️ [GPS] fetch failed: $e');
          });
    }
  }

  /// เรียกจาก UI เพื่อ retry GPS stream (เช่น หลังให้ permission)
  void retryLocationBroadcast() {
    if (_locationStreamSubscription == null) {
      _startLocationBroadcast();
    }
  }

  // 📍 หยุด Real-time GPS Stream
  void _stopLocationBroadcast() {
    _locationStreamSubscription?.cancel();
    _locationStreamSubscription = null;
    _myCurrentPosition = null;
    Log.d('📍 หยุด Real-time GPS Stream');
  }
}
