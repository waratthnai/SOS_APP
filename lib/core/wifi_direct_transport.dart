import 'dart:async';
import 'package:flutter/services.dart';
import 'transport.dart';

class WifiDirectTransport implements Transport {
  final _peersCtrl = StreamController<List<Peer>>.broadcast();
  final _msgCtrl = StreamController<Message>.broadcast();
  DiscoveryState _state = DiscoveryState.idle;

  static const platform = MethodChannel('wifi_direct');
  static const eventChannel = EventChannel('wifi_direct/events');
  StreamSubscription? _eventSub;

  @override
  DiscoveryState get discoveryState => _state;

  @override
  Stream<List<Peer>> get onPeers => _peersCtrl.stream;

  @override
  Stream<Message> get onMessage => _msgCtrl.stream;

  @override
  Future<void> startDiscovery() async {
    _state = DiscoveryState.scanning;
    await platform.invokeMethod('discoverPeers');
    _eventSub?.cancel();
    _eventSub = eventChannel.receiveBroadcastStream().listen((event) {
      if (event is Map && event['type'] == 'peers') {
        final peers = (event['peers'] as List)
            .map((p) => Peer(id: p['id'], name: p['name']))
            .toList();
        _peersCtrl.add(peers);
      } else if (event is Map && event['type'] == 'message') {
        _msgCtrl.add(Message(
          fromPeerId: event['fromPeerId'],
          body: event['body'],
          time: DateTime.now(),
        ));
      }
    });
  }

  @override
  Future<void> stopDiscovery() async {
    _state = DiscoveryState.idle;
    await platform.invokeMethod('stopDiscovery');
    _eventSub?.cancel();
    _peersCtrl.add([]);
  }

  @override
  Future<void> sendMessage(String body, {Peer? to}) async {
    await platform.invokeMethod('sendMessage', {
      'message': body,
      'peerId': to?.id,
    });
    _msgCtrl.add(Message(
      fromPeerId: 'me',
      toPeerId: to?.id,
      body: '[WiFiDirect] $body',
      time: DateTime.now(),
    ));
  }

  @override
  Future<void> sendFile(String filePath, {Peer? to}) async {
    // TODO: Implement WiFi Direct file transfer (Feature #7)
    throw UnimplementedError('WiFi Direct file transfer not yet implemented');
  }

  @override
  Future<void> dispose() async {
    _eventSub?.cancel();
    await _peersCtrl.close();
    await _msgCtrl.close();
  }
}
