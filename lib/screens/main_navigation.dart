import 'package:flutter/material.dart';
import 'dart:async';
import 'dashboard_screen.dart';
import 'notifications_screen.dart';
import 'map_screen.dart';
import 'safe_zones_screen.dart';
import 'settings_screen.dart';
import '../services/realtime_database_service.dart';
import '../services/sos_alert_service.dart';
import '../services/firestore_service.dart';
import '../services/push_notifications_service.dart';

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
  final RealtimeDatabaseService _realtimeDatabaseService = RealtimeDatabaseService();
  final SOSAlertService _sosAlertService = SOSAlertService();
  final FirestoreService _firestoreService = FirestoreService();
  StreamSubscription<bool>? _sosSubscription;
  bool _previousSOSStatus = false;
  PushNotificationsService? _push;

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
    _startSOSListener();
    _initPush();
  }

  @override
  void dispose() {
    _sosSubscription?.cancel();
    _animationController.dispose();
    super.dispose();
  }

  Future<void> _initPush() async {
    // Register device token for this parent so Cloud Functions can push to it.
    _push = PushNotificationsService(
      parentGuardianId: widget.userId,
      onToken: (token) => _firestoreService.addParentFcmToken(
        parentGuardianId: widget.userId,
        token: token,
      ),
      onNotificationTap: (data) {
        // Open Alerts tab
        if (mounted) {
          setState(() => _selectedIndex = 1);
        }
      },
    );
    await _push!.init();
  }

  void _startSOSListener() {
    const studentDeviceId = "ESP32_189426166412052";
    print('🚨 [SOS] Starting SOS listener for device: $studentDeviceId');

    _sosSubscription = _realtimeDatabaseService.getSOSStatus(studentDeviceId).listen(
      (isSOSActive) {
        print('🚨 [SOS] Status changed: $isSOSActive (previous: $_previousSOSStatus)');
        
        // Only show alert when SOS changes from false to true
        if (isSOSActive && !_previousSOSStatus) {
          print('🚨 [SOS] Emergency detected! Showing alert...');
          if (mounted) {
            _sosAlertService.showSOSAlert(context);
          }
        }
        
        // Dismiss alert when SOS becomes false
        if (!isSOSActive && _previousSOSStatus) {
          print('🚨 [SOS] Emergency cleared. Dismissing alert...');
          _sosAlertService.dismissSOSAlert();
        }
        
        _previousSOSStatus = isSOSActive;
      },
      onError: (error) {
        print('❌ [SOS] Error listening to SOS status: $error');
      },
    );
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