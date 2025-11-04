import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:geolocator/geolocator.dart';

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  GoogleMapController? mapController;
  bool _locationGranted = false;
  LatLng? _currentLatLng;

  final LatLng _center = const LatLng(13.7563, 100.5018); // Bangkok

  @override
  void initState() {
    super.initState();
    _checkPermissionAndLocate();
  }

  Future<void> _checkPermissionAndLocate() async {
    final status = await Permission.location.request();
    if (status.isGranted) {
      Position pos = await Geolocator.getCurrentPosition();
      setState(() {
        _locationGranted = true;
        _currentLatLng = LatLng(pos.latitude, pos.longitude);
      });
      // รอให้ mapController พร้อมก่อนค่อย animateCamera
      if (mapController != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          mapController!.animateCamera(
            CameraUpdate.newCameraPosition(
              CameraPosition(target: _currentLatLng!, zoom: 16),
            ),
          );
        });
      }
    } else {
      setState(() {
        _locationGranted = false;
      });
    }
  }

  void _onMapCreated(GoogleMapController controller) {
    mapController = controller;
    // ถ้าได้ตำแหน่งแล้ว ให้ซูมไปทันทีหลัง frame สร้างเสร็จ
    if (_locationGranted && _currentLatLng != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        mapController!.animateCamera(
          CameraUpdate.newCameraPosition(
            CameraPosition(target: _currentLatLng!, zoom: 16),
          ),
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Map')),
      body: !_locationGranted
          ? const Center(child: Text('กรุณาอนุญาต Location เพื่อแสดงแผนที่'))
          : GoogleMap(
              onMapCreated: _onMapCreated,
              initialCameraPosition: CameraPosition(
                target: _currentLatLng ?? _center,
                zoom: 12,
              ),
              myLocationEnabled: true,
              zoomControlsEnabled: true,
            ),
    );
  }
}
