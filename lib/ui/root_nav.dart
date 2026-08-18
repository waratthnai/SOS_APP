import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:offgrid_sos/ui/friends_screen.dart';
import 'package:offgrid_sos/ui/profile_screen.dart';
import 'package:offgrid_sos/ui/chat_history_screen.dart';
import 'package:offgrid_sos/ui/home_screen.dart';
import 'package:offgrid_sos/ui/settings_screen.dart';

class RootNav extends StatefulWidget {
  const RootNav({super.key});

  @override
  State<RootNav> createState() => _RootNavState();
}

class _RootNavState extends State<RootNav> {
  int _index = 0;

  final _pages = [
    const HomeScreen(),
    const ChatHistoryScreen(),
    const FriendsScreen(),
    const ProfileScreen(),
    const SettingsScreen(),
  ];

  final _items = const [
    _NavItem(icon: Icons.home_rounded, label: 'Home'),
    _NavItem(icon: Icons.chat_bubble_outline_rounded, label: 'Chat'),
    _NavItem(icon: Icons.people_outline_rounded, label: 'Friends'),
    _NavItem(icon: Icons.person_outline_rounded, label: 'Profile'),
    _NavItem(icon: Icons.settings_outlined, label: 'Settings'),
  ];

  void _onNavTap(int i) {
    setState(() => _index = i);
  }

  void _onHorizontalDrag(DragUpdateDetails details) {
    if (details.primaryDelta != null && details.primaryDelta!.abs() > 10) {
      if (details.primaryDelta! < 0 && _index < _pages.length - 1) {
        setState(() => _index += 1);
      } else if (details.primaryDelta! > 0 && _index > 0) {
        setState(() => _index -= 1);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      body: GestureDetector(
        onHorizontalDragUpdate: _onHorizontalDrag,
        child: _pages[_index],
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: cs.surface,
          border: Border(top: BorderSide(color: cs.outlineVariant, width: 0.5)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 12,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: SafeArea(
          top: false,
          child: SizedBox(
            height: 56,
            child: Row(
              children: List.generate(_items.length, (i) {
                final item = _items[i];
                final selected = i == _index;
                return Expanded(
                  child: GestureDetector(
                    onTap: () {
                      HapticFeedback.lightImpact();
                      _onNavTap(i);
                    },
                    behavior: HitTestBehavior.opaque,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          item.icon,
                          color: selected ? cs.primary : cs.onSurfaceVariant,
                          size: 24,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          item.label,
                          style: TextStyle(
                            color: selected ? cs.primary : cs.onSurfaceVariant,
                            fontSize: 10,
                            fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }),
            ),
          ),
        ),
      ),
    );
  }
}

class _NavItem {
  final IconData icon;
  final String label;
  const _NavItem({required this.icon, required this.label});
}

