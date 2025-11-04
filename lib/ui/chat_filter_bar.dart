import 'package:flutter/material.dart';
import '../core/chat_filter_service.dart';
import '../core/chat_models.dart';

class ChatFilterBar extends StatefulWidget {
  final List<ChatMessage> allMessages;
  final ValueChanged<List<ChatMessage>>? onFilterChanged;

  const ChatFilterBar({
    super.key,
    required this.allMessages,
    this.onFilterChanged,
  });

  @override
  State<ChatFilterBar> createState() => _ChatFilterBarState();
}

class _ChatFilterBarState extends State<ChatFilterBar> {
  final TextEditingController _searchController = TextEditingController();
  final ChatFilterService _filterService = ChatFilterService();

  @override
  void initState() {
    super.initState();
    _filterService.addListener(_onFilterChanged);
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _filterService.removeListener(_onFilterChanged);
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    super.dispose();
  }

  void _onFilterChanged() {
    if (widget.onFilterChanged != null) {
      final filtered = _filterService.filterMessages(widget.allMessages);
      widget.onFilterChanged!(filtered);
    }
  }

  void _onSearchChanged() {
    _filterService.setSearchQuery(_searchController.text);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey[900],
        border: Border(
          bottom: BorderSide(
            color: Colors.grey[700]!,
            width: 1,
          ),
        ),
      ),
      child: Column(
        children: [
          // Search bar
          TextField(
            controller: _searchController,
            decoration: InputDecoration(
              hintText: 'Search messages...',
              hintStyle: TextStyle(color: Colors.grey[400]),
              prefixIcon: Icon(Icons.search, color: Colors.grey[400]),
              suffixIcon: _searchController.text.isNotEmpty
                  ? IconButton(
                      icon: Icon(Icons.clear, color: Colors.grey[400]),
                      onPressed: () {
                        _searchController.clear();
                      },
                    )
                  : null,
              filled: true,
              fillColor: Colors.grey[800],
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(25),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 20,
                vertical: 12,
              ),
            ),
            style: const TextStyle(color: Colors.white),
          ),
          
          const SizedBox(height: 16),
          
          // Filter chips
          ListenableBuilder(
            listenable: _filterService,
            builder: (context, child) {
              final counts = _filterService.getFilterCounts(widget.allMessages);
              
              return SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: ChatFilter.values.map((filter) {
                    final isActive = _filterService.activeFilter == filter;
                    final count = counts[filter] ?? 0;
                    
                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: FilterChip(
                        label: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              filter.icon,
                              size: 16,
                              color: isActive ? Colors.white : filter.color,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              '${filter.displayName} ($count)',
                              style: TextStyle(
                                color: isActive ? Colors.white : filter.color,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                        selected: isActive,
                        onSelected: (_) {
                          _filterService.setFilter(filter);
                        },
                        backgroundColor: Colors.grey[800],
                        selectedColor: filter.color,
                        checkmarkColor: Colors.white,
                        side: BorderSide(
                          color: isActive ? filter.color : Colors.grey[600]!,
                        ),
                      ),
                    );
                  }).toList(),
                ),
              );
            },
          ),
          
          const SizedBox(height: 12),
          
          // Peer filter
          ListenableBuilder(
            listenable: _filterService,
            builder: (context, child) {
              final peers = _filterService.getAvailablePeers(widget.allMessages);
              
              if (peers.length <= 1) return const SizedBox.shrink();
              
              return Row(
                children: [
                  Icon(Icons.people, color: Colors.grey[400], size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      value: _filterService.selectedPeer.isNotEmpty 
                          ? _filterService.selectedPeer 
                          : 'All',
                      decoration: InputDecoration(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        filled: true,
                        fillColor: Colors.grey[800],
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide.none,
                        ),
                      ),
                      dropdownColor: Colors.grey[800],
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                      items: peers.map((peer) {
                        return DropdownMenuItem(
                          value: peer,
                          child: Text(
                            peer,
                            style: const TextStyle(fontSize: 12),
                          ),
                        );
                      }).toList(),
                      onChanged: (value) {
                        if (value != null) {
                          _filterService.setSelectedPeer(value);
                        }
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: Icon(Icons.clear_all, color: Colors.grey[400]),
                    tooltip: 'Clear filters',
                    onPressed: () {
                      _filterService.clearFilters();
                      _searchController.clear();
                    },
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}