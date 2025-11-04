import 'package:flutter/material.dart';
import 'chat_models.dart';

enum ChatFilter {
  all,
  text,
  images,
  videos,
  emergency,
  recent,
  older,
}

class ChatFilterService extends ChangeNotifier {
  static final ChatFilterService _instance = ChatFilterService._internal();
  factory ChatFilterService() => _instance;
  ChatFilterService._internal();

  ChatFilter _activeFilter = ChatFilter.all;
  String _searchQuery = '';
  String _selectedPeer = '';

  ChatFilter get activeFilter => _activeFilter;
  String get searchQuery => _searchQuery;
  String get selectedPeer => _selectedPeer;

  void setFilter(ChatFilter filter) {
    _activeFilter = filter;
    notifyListeners();
  }

  void setSearchQuery(String query) {
    _searchQuery = query;
    notifyListeners();
  }

  void setSelectedPeer(String peer) {
    _selectedPeer = peer;
    notifyListeners();
  }

  void clearFilters() {
    _activeFilter = ChatFilter.all;
    _searchQuery = '';
    _selectedPeer = '';
    notifyListeners();
  }

  List<ChatMessage> filterMessages(List<ChatMessage> messages) {
    var filtered = messages;

    // Filter by selected peer
    if (_selectedPeer.isNotEmpty && _selectedPeer != 'All') {
      filtered = filtered.where((msg) => 
        msg.from == _selectedPeer
      ).toList();
    }

    // Filter by message type
    switch (_activeFilter) {
      case ChatFilter.text:
        filtered = filtered.where((msg) => 
          msg.type == ChatType.text
        ).toList();
        break;
      case ChatFilter.images:
        filtered = filtered.where((msg) => 
          msg.type == ChatType.image
        ).toList();
        break;
      case ChatFilter.videos:
        filtered = filtered.where((msg) => 
          msg.type == ChatType.video
        ).toList();
        break;
      case ChatFilter.emergency:
        filtered = filtered.where((msg) => 
          msg.text != null && (
            msg.text!.toLowerCase().contains('sos') ||
            msg.text!.toLowerCase().contains('emergency') ||
            msg.text!.toLowerCase().contains('help')
          )
        ).toList();
        break;
      case ChatFilter.recent:
        final oneDayAgo = DateTime.now().subtract(const Duration(days: 1));
        filtered = filtered.where((msg) => 
          msg.time.isAfter(oneDayAgo)
        ).toList();
        break;
      case ChatFilter.older:
        final oneDayAgo = DateTime.now().subtract(const Duration(days: 1));
        filtered = filtered.where((msg) => 
          msg.time.isBefore(oneDayAgo)
        ).toList();
        break;
      case ChatFilter.all:
        // No additional filtering
        break;
    }

    // Filter by search query
    if (_searchQuery.isNotEmpty) {
      filtered = filtered.where((msg) => 
        (msg.text != null && msg.text!.toLowerCase().contains(_searchQuery.toLowerCase())) ||
        msg.from.toLowerCase().contains(_searchQuery.toLowerCase())
      ).toList();
    }

    return filtered;
  }

  List<String> getAvailablePeers(List<ChatMessage> messages) {
    final peers = <String>{'All'};
    
    for (final msg in messages) {
      if (msg.from.isNotEmpty && msg.from != 'me') {
        peers.add(msg.from);
      }
    }

    return peers.toList()..sort();
  }

  Map<ChatFilter, int> getFilterCounts(List<ChatMessage> messages) {
    final counts = <ChatFilter, int>{};
    final oneDayAgo = DateTime.now().subtract(const Duration(days: 1));

    counts[ChatFilter.all] = messages.length;
    counts[ChatFilter.text] = messages.where((msg) => 
      msg.type == ChatType.text
    ).length;
    counts[ChatFilter.images] = messages.where((msg) => 
      msg.type == ChatType.image
    ).length;
    counts[ChatFilter.videos] = messages.where((msg) => 
      msg.type == ChatType.video
    ).length;
    counts[ChatFilter.emergency] = messages.where((msg) => 
      msg.text != null && (
        msg.text!.toLowerCase().contains('sos') ||
        msg.text!.toLowerCase().contains('emergency') ||
        msg.text!.toLowerCase().contains('help')
      )
    ).length;
    counts[ChatFilter.recent] = messages.where((msg) => 
      msg.time.isAfter(oneDayAgo)
    ).length;
    counts[ChatFilter.older] = messages.where((msg) => 
      msg.time.isBefore(oneDayAgo)
    ).length;

    return counts;
  }
}

extension ChatFilterExtension on ChatFilter {
  String get displayName {
    switch (this) {
      case ChatFilter.all:
        return 'All';
      case ChatFilter.text:
        return 'Text';
      case ChatFilter.images:
        return 'Images';
      case ChatFilter.videos:
        return 'Videos';
      case ChatFilter.emergency:
        return 'Emergency';
      case ChatFilter.recent:
        return 'Recent';
      case ChatFilter.older:
        return 'Older';
    }
  }

  IconData get icon {
    switch (this) {
      case ChatFilter.all:
        return Icons.all_inclusive;
      case ChatFilter.text:
        return Icons.text_fields;
      case ChatFilter.images:
        return Icons.image;
      case ChatFilter.videos:
        return Icons.video_library;
      case ChatFilter.emergency:
        return Icons.emergency;
      case ChatFilter.recent:
        return Icons.schedule;
      case ChatFilter.older:
        return Icons.history;
    }
  }

  Color get color {
    switch (this) {
      case ChatFilter.all:
        return Colors.blue;
      case ChatFilter.text:
        return Colors.green;
      case ChatFilter.images:
        return Colors.purple;
      case ChatFilter.videos:
        return Colors.orange;
      case ChatFilter.emergency:
        return Colors.red;
      case ChatFilter.recent:
        return Colors.cyan;
      case ChatFilter.older:
        return Colors.grey;
    }
  }
}