import 'package:flutter/material.dart';
import 'dashboard_screen.dart';
import 'notifications_screen.dart';
import 'map_screen.dart';
import 'safe_zones_screen.dart';
import 'settings_screen.dart';

class MainNavigation extends StatefulWidget {
  final Map<String, dynamic> userData;
  final String userId;

  const MainNavigation({
    Key? key,
    required this.userData,
    required this.userId,
  }) : super(key: key);

  @override
  State<MainNavigation> createState() => _MainNavigationState();
}

class _MainNavigationState extends State<MainNavigation> with SingleTickerProviderStateMixin {
  int _selectedIndex = 0;
  late AnimationController _animationController;

  List<Widget> get _pages => <Widget>[
    DashboardScreen(
      userData: widget.userData,
      userId: widget.userId,
    ),
    NotificationsScreen(
      userData: widget.userData,
      userId: widget.userId,
    ),
    MapScreen(
      userData: widget.userData,
      userId: widget.userId,
    ),
    SafeZonesScreen(
      userData: widget.userData,
      userId: widget.userId,
    ),
    SettingsScreen(
      userData: widget.userData,
      userId: widget.userId,
    ),
  ];

  static const List<BottomNavigationBarItem> _bottomNavItems = [
    BottomNavigationBarItem(
      icon: Icon(Icons.home_outlined),
      activeIcon: Icon(Icons.home),
      label: 'Dashboard',
    ),
    BottomNavigationBarItem(
      icon: Icon(Icons.notifications_outlined),
      activeIcon: Icon(Icons.notifications),
      label: 'Alerts',
    ),
    BottomNavigationBarItem(
      icon: Icon(Icons.map_outlined),
      activeIcon: Icon(Icons.map),
      label: 'Map',
    ),
    BottomNavigationBarItem(
      icon: Icon(Icons.location_on_outlined),
      activeIcon: Icon(Icons.location_on),
      label: 'Zones',
    ),
    BottomNavigationBarItem(
      icon: Icon(Icons.settings_outlined),
      activeIcon: Icon(Icons.settings),
      label: 'Settings',
    ),
  ];

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 250),
        child: _pages[_selectedIndex],
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 8,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: BottomNavigationBar(
          selectedItemColor: const Color(0xFF862334),
          unselectedItemColor: Colors.grey,
          backgroundColor: Colors.white,
          elevation: 15,
          currentIndex: _selectedIndex,
          onTap: _onItemTapped,
          type: BottomNavigationBarType.fixed,
          selectedLabelStyle: const TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 12,
          ),
          unselectedLabelStyle: const TextStyle(
            fontWeight: FontWeight.normal,
            fontSize: 11,
          ),
          items: _bottomNavItems,
        ),
      ),
    );
  }
}