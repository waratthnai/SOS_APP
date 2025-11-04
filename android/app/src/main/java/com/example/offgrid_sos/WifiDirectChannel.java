package com.example.offgrid_sos;

import android.content.Context;
import android.net.wifi.p2p.*;
import io.flutter.plugin.common.MethodChannel;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel.Result;
import io.flutter.plugin.common.EventChannel;

import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

public class WifiDirectChannel {
    private WifiP2pManager manager;
    private WifiP2pManager.Channel channel;
    private EventChannel.EventSink eventSink;

    public WifiDirectChannel(Context context) {
        manager = (WifiP2pManager) context.getSystemService(Context.WIFI_P2P_SERVICE);
        channel = manager.initialize(context, context.getMainLooper(), null);
    }

    public void setEventSink(EventChannel.EventSink sink) {
        eventSink = sink;
    }

    public void discoverPeers(MethodCall call, Result result) {
        manager.discoverPeers(channel, new WifiP2pManager.ActionListener() {
            @Override
            public void onSuccess() {
                result.success(true);
                manager.requestPeers(channel, peers -> {
                    List<Map<String, Object>> peerList = new ArrayList<>();
                    for (WifiP2pDevice device : peers.getDeviceList()) {
                        Map<String, Object> peer = new HashMap<>();
                        peer.put("id", device.deviceAddress);
                        peer.put("name", device.deviceName);
                        peerList.add(peer);
                    }
                    if (eventSink != null) {
                        Map<String, Object> event = new HashMap<>();
                        event.put("type", "peers");
                        event.put("peers", peerList);
                        eventSink.success(event);
                    }
                });
            }
            @Override
            public void onFailure(int reason) { result.error("fail", "Discovery failed", null); }
        });
    }

    public void sendMessage(MethodCall call, Result result) {
        // TODO: Implement socket send logic here
        result.success(true);
        // After sending, you can send message event back:
        if (eventSink != null) {
            Map<String, Object> event = new HashMap<>();
            event.put("type", "message");
            event.put("fromPeerId", "peer_id");
            event.put("body", call.argument("message"));
            eventSink.success(event);
        }
    }

    public void stopDiscovery(MethodCall call, Result result) {
        manager.stopPeerDiscovery(channel, new WifiP2pManager.ActionListener() {
            @Override
            public void onSuccess() { result.success(true); }
            @Override
            public void onFailure(int reason) { result.error("fail", "Stop failed", null); }
        });
    }
}
