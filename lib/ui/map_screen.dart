import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:geolocator/geolocator.dart';
import '../core/app_state.dart';
import '../core/transport.dart';

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  GoogleMapController? _mapController;
  bool _locationGranted = false;
  LatLng? _currentLatLng;

  static const LatLng _defaultCenter = LatLng(13.7563, 100.5018);

  @override
  void initState() {
    super.initState();
    _checkPermissionAndLocate();
  }

  Future<void> _checkPermissionAndLocate() async {
    final status = await Permission.location.request();
    if (!mounted) return;
    if (status.isGranted) {
      final pos = await Geolocator.getCurrentPosition();
      if (!mounted) return;
      final target = LatLng(pos.latitude, pos.longitude);
      setState(() {
        _locationGranted = true;
        _currentLatLng = target;
      });
      _mapController?.animateCamera(
        CameraUpdate.newCameraPosition(CameraPosition(target: target, zoom: 15)),
      );
    } else {
      setState(() => _locationGranted = false);
    }
  }

  void _onMapCreated(GoogleMapController controller) {
    _mapController = controller;
    if (_locationGranted && _currentLatLng != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        controller.animateCamera(
          CameraUpdate.newCameraPosition(
              CameraPosition(target: _currentLatLng!, zoom: 15)),
        );
      });
    }
  }

  /// สร้าง markers จาก peerLocations — keyed by peerId
  Set<Marker> _buildMarkers() {
    final markers = <Marker>{};
    final locations = appState.peerLocations;
    final stablePeers = appState.stablePeers;

    for (final entry in locations.entries) {
      final peerId = entry.key;
      final loc = entry.value;

      // หาชื่อ peer จาก stablePeers
      final peer = stablePeers.cast<Peer?>().firstWhere(
            (p) => p?.id == peerId,
            orElse: () => null,
          );
      final peerName = peer?.name ?? peerId;

      // ตรวจสถานะ SOS/Rescue โดยเช็คทั้ง peerId และ peerName
      final isEmergency =
          appState.isEmergencySOSPeer(peerName) || appState.isEmergencySOSPeer(peerId);
      final isSOSActive =
          appState.isSOSPeer(peerName) || appState.isSOSPeer(peerId);
      final isSOSMode =
          appState.isSOSModePeer(peerName) || appState.isSOSModePeer(peerId);
      final isRescue =
          appState.isRescuePeer(peerName) || appState.isRescuePeer(peerId);

      final double hue;
      final String statusLabel;
      if (isEmergency) {
        hue = BitmapDescriptor.hueRed;
        statusLabel = '🚨 SOS ฉุกเฉิน!';
      } else if (isSOSActive) {
        hue = BitmapDescriptor.hueRose;
        statusLabel = '🆘 ขอความช่วยเหลือ';
      } else if (isSOSMode) {
        hue = BitmapDescriptor.hueOrange;
        statusLabel = '⚠️ โหมด SOS';
      } else if (isRescue) {
        hue = BitmapDescriptor.hueAzure;
        statusLabel = '🚑 หน่วยกู้ภัย';
      } else {
        hue = BitmapDescriptor.hueGreen;
        statusLabel = '✅ ปกติ';
      }

      // แสดงเวลาที่รับข้อมูลล่าสุด
      final age = DateTime.now().difference(loc.timestamp);
      final ageLabel = age.inMinutes > 0 ? '${age.inMinutes} นาทีที่แล้ว' : 'เมื่อกี้';

      markers.add(Marker(
        markerId: MarkerId(peerId),
        position: LatLng(loc.latitude, loc.longitude),
        icon: BitmapDescriptor.defaultMarkerWithHue(hue),
        infoWindow: InfoWindow(
          title: peerName,
          snippet: '$statusLabel • $ageLabel',
        ),
      ));
    }

    return markers;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('แผนที่')),
      body: !_locationGranted
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.location_off, size: 48, color: Colors.grey),
                  const SizedBox(height: 12),
                  const Text('กรุณาอนุญาต Location เพื่อแสดงแผนที่'),
                  const SizedBox(height: 12),
                  ElevatedButton(
                    onPressed: _checkPermissionAndLocate,
                    child: const Text('ขออนุญาตอีกครั้ง'),
                  ),
                ],
              ),
            )
          : ListenableBuilder(
              listenable: appState,
              builder: (context, _) {
                final markers = _buildMarkers();
                return Stack(
                  children: [
                    GoogleMap(
                      onMapCreated: _onMapCreated,
                      initialCameraPosition: CameraPosition(
                        target: _currentLatLng ?? _defaultCenter,
                        zoom: 15,
                      ),
                      myLocationEnabled: true,
                      myLocationButtonEnabled: true,
                      zoomControlsEnabled: true,
                      markers: markers,
                    ),
                    _Legend(peerCount: markers.length),
                  ],
                );
              },
            ),
    );
  }
}

class _Legend extends StatelessWidget {
  final int peerCount;
  const _Legend({required this.peerCount});

  @override
  Widget build(BuildContext context) {
    return Positioned(
      bottom: 80,
      left: 12,
      child: Card(
        color: Colors.black.withValues(alpha: 0.75),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'พบอุปกรณ์ $peerCount เครื่อง',
                style: const TextStyle(color: Colors.white70, fontSize: 11),
              ),
              const SizedBox(height: 6),
              _LegendItem(color: Colors.red, label: 'SOS ฉุกเฉิน'),
              _LegendItem(color: Colors.pink, label: 'ขอความช่วยเหลือ'),
              _LegendItem(color: Colors.orange, label: 'โหมด SOS'),
              _LegendItem(color: Colors.lightBlue, label: 'หน่วยกู้ภัย'),
              _LegendItem(color: Colors.green, label: 'ปกติ'),
            ],
          ),
        ),
      ),
    );
  }
}

class _LegendItem extends StatelessWidget {
  final Color color;
  final String label;
  const _LegendItem({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 12, height: 12, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 6),
          Text(label, style: const TextStyle(color: Colors.white, fontSize: 11)),
        ],
      ),
    );
  }
}
