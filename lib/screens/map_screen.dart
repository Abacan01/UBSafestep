import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../../services/realtime_database_service.dart';
import '../../services/firestore_service.dart';
import '../../services/location_monitor_service.dart';
import 'dart:math' as math;
import 'dart:async';

class MapScreen extends StatefulWidget {
  final Map<String, dynamic> userData;
  final String userId;
  final Function(LatLng)? onLocationPicked;

  const MapScreen({
    Key? key,
    required this.userData,
    required this.userId,
    this.onLocationPicked,
  }) : super(key: key);

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  final FirestoreService _firestoreService = FirestoreService();
  final LocationMonitorService _locationMonitor = LocationMonitorService();
  final MapController _mapController = MapController();
  final RealtimeDatabaseService _realtimeDatabaseService = RealtimeDatabaseService();

  LatLng? _currentStudentLocation;
  List<LatLng> _safezonePolygons = [];
  List<double> _safezoneRadii = [];
  List<Map<String, dynamic>> _safezones = [];
  bool _isLoading = true;
  bool _showSafezones = true;
  double _currentZoom = 13.0;
  LatLng? _pickedLocation;
  bool _isPickingLocation = false;

  // ==================== UI STATE VARIABLES ====================
  bool _isLocationPanelCollapsed = false;
  bool _isDebugPanelCollapsed = true;
  // ============================================================

  // ==================== STUDENT GPS VARIABLES ====================
  StreamSubscription? _gpsDataSubscription;
  bool _usingStudentGPS = false;
  DateTime? _lastGPSUpdate;
  Timer? _gpsTimeoutTimer;
  bool _isGPSOffline = false;
  // ===============================================================

  // University of Batangas coordinates
  static const LatLng _ubLocation = LatLng(13.7565, 121.0583);

  @override
  void initState() {
    super.initState();
    _loadMapData();

    // ==================== STUDENT GPS INITIALIZATION ====================
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _startStudentGPSListener();
    });
    // ====================================================================
  }

  // ==================== STUDENT GPS METHODS ====================
  @override
  void dispose() {
    _gpsDataSubscription?.cancel();
    _gpsTimeoutTimer?.cancel();
    super.dispose();
  }

  void _startStudentGPSListener() {
    const studentDeviceId = "ESP32_189426166412052";

    print('🛰️ [STUDENT GPS] Starting listener for device: $studentDeviceId');

    try {
      _gpsDataSubscription = _realtimeDatabaseService
          .getArduinoGPSData(studentDeviceId)
          .listen(
        _handleStudentGPSUpdate,
        onError: (error) {
          print('❌ [STUDENT GPS] Error listening: $error');
          _setGPSOffline();
        },
        cancelOnError: false,
      );

      // Start timeout timer to detect when GPS stops sending data
      _startGPSTimeoutTimer();

      _checkDeviceExists(studentDeviceId);
    } catch (e) {
      print('❌ [STUDENT GPS] Failed to start listener: $e');
      _setGPSOffline();
    }
  }

  void _startGPSTimeoutTimer() {
    _gpsTimeoutTimer?.cancel();
    _gpsTimeoutTimer = Timer.periodic(Duration(seconds: 10), (timer) {
      if (_lastGPSUpdate != null) {
        final secondsSinceLastUpdate = DateTime.now().difference(_lastGPSUpdate!).inSeconds;
        if (secondsSinceLastUpdate > 2) { // 15 seconds without update = offline
          if (!_isGPSOffline) {
            print('⚠️ [STUDENT GPS] No updates for $secondsSinceLastUpdate seconds - marking as offline');
            _setGPSOffline();
          }
        }
      }
    });
  }

  void _setGPSOffline() {
    if (mounted) {
      setState(() {
        _isGPSOffline = true;
      });
    }
  }

  void _setGPSOnline() {
    if (mounted) {
      setState(() {
        _isGPSOffline = false;
      });
    }
  }

  void _checkDeviceExists(String deviceId) async {
    try {
      final exists = await _realtimeDatabaseService.checkDeviceExists(deviceId);
      print('📡 [STUDENT GPS] Device exists in database: $exists');

      if (!exists) {
        print('⚠️ [STUDENT GPS] Device $deviceId not found in Realtime Database');
      }
    } catch (e) {
      print('❌ [STUDENT GPS] Error checking device: $e');
    }
  }

  void _handleStudentGPSUpdate(Map<String, dynamic> gpsData) {
    if (gpsData['latitude'] != null && gpsData['longitude'] != null) {
      final newLocation = LatLng(
        (gpsData['latitude'] as num).toDouble(),
        (gpsData['longitude'] as num).toDouble(),
      );

      setState(() {
        _usingStudentGPS = true;
        _lastGPSUpdate = DateTime.now();
        _currentStudentLocation = newLocation;
      });

      // If GPS was offline, mark it as online again
      if (_isGPSOffline) {
        print('✅ [STUDENT GPS] Connection restored');
        _setGPSOnline();
      }

      print('📍 [STUDENT GPS] Real-time update: $newLocation');

      _checkSafezonesWithStudentLocation(newLocation);
    }
  }

  void _checkSafezonesWithStudentLocation(LatLng location) {
    if (_safezonePolygons.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _locationMonitor.checkAndNotifySafezoneStatus(
          studentId: widget.userData['StudentID'],
          parentGuardianId: widget.userId,
          studentLat: location.latitude,
          studentLng: location.longitude,
          locationName: 'Student GPS Location',
        );
      });
    }
  }
  // =============================================================

  Future<void> _loadMapData() async {
    try {
      print('🗺️ [MAP] === Loading Map Data ===');

      final studentData = await _firestoreService.getStudentData(widget.userData['StudentID']);
      print('🗺️ [MAP] Student data loaded: ${studentData != null}');

      if (studentData != null && studentData['lastLatitude'] != null && studentData['lastLongitude'] != null) {
        setState(() {
          _currentStudentLocation = LatLng(
            studentData['lastLatitude'],
            studentData['lastLongitude'],
          );
        });
        print('🗺️ [MAP] Student location: $_currentStudentLocation');
      } else {
        print('🗺️ [MAP] No student location data available');
        setState(() {
          _currentStudentLocation = _ubLocation;
        });
      }

      final safezones = await _firestoreService.getSafezonesByParent(widget.userId);
      print('🗺️ [MAP] Raw safezones from Firestore: ${safezones.length} zones');

      final safezoneData = _parseSafezoneData(safezones);
      setState(() {
        _safezones = safezones;
        _safezonePolygons = safezoneData['polygons'];
        _safezoneRadii = safezoneData['radii'];
      });

      print('🗺️ [MAP] Final safezone polygons: ${_safezonePolygons.length}');

    } catch (e) {
      print('❌ [MAP] Error loading map data: $e');
      setState(() {
        _currentStudentLocation = _ubLocation;
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Map<String, dynamic> _parseSafezoneData(List<Map<String, dynamic>> safezones) {
    List<LatLng> polygons = [];
    List<double> radii = [];

    for (var zone in safezones) {
      final coordinates = zone['Coordinates'];
      final zoneName = zone['Zonename'] ?? 'Unnamed Zone';

      final radius = (zone['Radius'] ?? 200.0) as dynamic;
      final radiusValue = (radius is num) ? radius.toDouble() : 200.0;

      if (coordinates is String && coordinates.isNotEmpty) {
        try {
          final parts = coordinates.split(',');
          if (parts.length == 2) {
            final lat = double.tryParse(parts[0].trim());
            final lng = double.tryParse(parts[1].trim());

            if (lat != null && lng != null) {
              polygons.add(LatLng(lat, lng));
              radii.add(radiusValue);
            }
          }
        } catch (e) {
          print('🗺️ [MAP] Error parsing coordinates: $e');
        }
      }
    }

    return {
      'polygons': polygons,
      'radii': radii,
    };
  }

  // ==================== ENHANCED CIRCLE GENERATION ====================
  List<LatLng> _generateCirclePoints(LatLng center, double radiusMeters, int segments) {
    final points = <LatLng>[];
    final earthRadius = 6378137.0; // Earth's radius in meters

    for (int i = 0; i <= segments; i++) {
      final angle = 2 * math.pi * i / segments;

      // Convert meters to degrees
      final dx = radiusMeters * math.cos(angle) / earthRadius * (180 / math.pi);
      final dy = radiusMeters * math.sin(angle) / earthRadius * (180 / math.pi) / math.cos(center.latitude * math.pi / 180);

      points.add(LatLng(center.latitude + dy, center.longitude + dx));
    }
    return points;
  }

  // Calculate approximate meters per pixel for current zoom level
  double _getMetersPerPixel() {
    // Approximate calculation based on zoom level and latitude
    final latitude = _mapController.center.latitude;
    return (156543.03392 * math.cos(latitude * math.pi / 180) / math.pow(2, _currentZoom));
  }
  // ====================================================================

  void _startLocationPicking() {
    setState(() {
      _isPickingLocation = true;
      _pickedLocation = null;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('🗺️ Tap on the map to select a location'),
        duration: Duration(seconds: 3),
      ),
    );
  }

  void _handleMapTap(TapPosition tapPosition, LatLng latLng) {
    if (_isPickingLocation) {
      setState(() {
        _pickedLocation = latLng;
      });

      if (widget.onLocationPicked != null) {
        widget.onLocationPicked!(latLng);
        Navigator.pop(context);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('📍 Location picked: ${latLng.latitude.toStringAsFixed(6)}, ${latLng.longitude.toStringAsFixed(6)}'),
            action: SnackBarAction(
              label: 'Use This',
              onPressed: () {
                Navigator.pop(context, latLng);
              },
            ),
          ),
        );
      }
    }
  }

  void _cancelLocationPicking() {
    setState(() {
      _isPickingLocation = false;
      _pickedLocation = null;
    });
  }

  Future<void> _refreshLocation() async {
    setState(() {
      _isLoading = true;
    });
    await _loadMapData();

    if (_currentStudentLocation != null) {
      await _locationMonitor.checkAndNotifySafezoneStatus(
        studentId: widget.userData['StudentID'],
        parentGuardianId: widget.userId,
        studentLat: _currentStudentLocation!.latitude,
        studentLng: _currentStudentLocation!.longitude,
        locationName: 'Current Location',
      );
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('📍 Location data refreshed'),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _simulateLocationUpdate() async {
    try {
      final position = await _locationMonitor.getCurrentLocation();
      if (position != null) {
        await _firestoreService.saveStudentLocation(
          studentId: widget.userData['StudentID'],
          latitude: position.latitude,
          longitude: position.longitude,
          locationName: 'Simulated Location',
          timestamp: DateTime.now().toIso8601String(),
        );

        await _locationMonitor.checkAndNotifySafezoneStatus(
          studentId: widget.userData['StudentID'],
          parentGuardianId: widget.userId,
          studentLat: position.latitude,
          studentLng: position.longitude,
          locationName: 'Simulated Location',
        );

        await _loadMapData();

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('📍 Location updated and safe zones checked'),
              backgroundColor: Colors.green,
              duration: Duration(seconds: 3),
            ),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('❌ Could not get current location'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Error updating location: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _zoomIn() {
    final newZoom = _currentZoom + 1;
    _mapController.move(_mapController.center, newZoom);
    setState(() {
      _currentZoom = newZoom;
    });
  }

  void _zoomOut() {
    final newZoom = _currentZoom - 1;
    _mapController.move(_mapController.center, newZoom);
    setState(() {
      _currentZoom = newZoom;
    });
  }

  void _centerOnStudent() {
    if (_currentStudentLocation != null) {
      _mapController.move(_currentStudentLocation!, 15.0);
      setState(() {
        _currentZoom = 15.0;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('📍 Centered on student location'),
          duration: Duration(seconds: 2),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('❌ No student location available'),
          backgroundColor: Colors.orange,
        ),
      );
    }
  }

  void _centerOnUB() {
    _mapController.move(_ubLocation, 15.0);
    setState(() {
      _currentZoom = 15.0;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('🏫 Centered on University of Batangas'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  void _toggleSafezones() {
    setState(() {
      _showSafezones = !_showSafezones;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(_showSafezones ? '✅ Safezones shown' : '🚫 Safezones hidden'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Widget _buildMapControlButton({
    required IconData icon,
    required VoidCallback onPressed,
    required String tooltip,
    Color? backgroundColor,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: backgroundColor ?? Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 6,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: IconButton(
        icon: Icon(icon),
        onPressed: onPressed,
        tooltip: tooltip,
        iconSize: 22,
        color: backgroundColor != null ? Colors.white : const Color(0xFF862334),
      ),
    );
  }

  // ==================== UI HELPER METHODS ====================
  Widget _buildStatusChip({required IconData icon, required String label, required String value, required Color color}) {
    return Expanded(
      child: Container(
        padding: EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Column(
          children: [
            Icon(icon, size: 14, color: color),
            SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(fontSize: 8, color: color, fontWeight: FontWeight.bold),
            ),
            Text(
              value,
              style: TextStyle(fontSize: 10, color: Colors.grey.shade800, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDebugItem({required String label, required String value, required Color color}) {
    return Container(
      margin: EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Container(
            width: 4,
            height: 4,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
            ),
          ),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: TextStyle(color: Colors.grey.shade400, fontSize: 10),
            ),
          ),
          Text(
            value,
            style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final primaryColor = const Color(0xFF862334);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          _isPickingLocation ? 'Pick Location on Map' : 'Live Location Map',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        backgroundColor: primaryColor,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          if (_isPickingLocation)
            IconButton(
              icon: const Icon(Icons.cancel),
              onPressed: _cancelLocationPicking,
              tooltip: 'Cancel Picking',
            )
          else
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _refreshLocation,
              tooltip: 'Refresh Location',
            ),
          if (!_isPickingLocation)
            IconButton(
              icon: const Icon(Icons.my_location),
              onPressed: _simulateLocationUpdate,
              tooltip: 'Update Current Location',
            ),
        ],
      ),
      body: Stack(
        children: [
          // Map
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              center: _currentStudentLocation ?? _ubLocation,
              zoom: _currentZoom,
              maxZoom: 18.0,
              minZoom: 10.0,
              onTap: _handleMapTap,
              onPositionChanged: (position, hasGesture) {
                if (hasGesture) {
                  setState(() {
                    _currentZoom = position.zoom!;
                  });
                }
              },
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.example.ubsafestep',
              ),

              // ==================== ENHANCED SAFEZONE VISUALIZATION ====================
              if (_showSafezones && _safezonePolygons.isNotEmpty)
                PolygonLayer(
                  polygons: _safezonePolygons.asMap().entries.map((entry) {
                    final index = entry.key;
                    final center = entry.value;
                    final radiusMeters = _safezoneRadii[index];
                    final zone = _safezones[index];

                    // Generate circle points with actual geographical coordinates
                    final points = _generateCirclePoints(center, radiusMeters, 36);

                    return Polygon(
                      points: points,
                      color: Colors.green.withOpacity(0.2),
                      borderColor: Colors.green,
                      borderStrokeWidth: 2,
                      isFilled: true,
                    );
                  }).toList(),
                ),

              // Add center markers for safezones
              if (_showSafezones && _safezonePolygons.isNotEmpty)
                MarkerLayer(
                  markers: _safezonePolygons.asMap().entries.map((entry) {
                    final index = entry.key;
                    final point = entry.value;
                    final zone = _safezones[index];
                    final radius = _safezoneRadii[index];

                    return Marker(
                      point: point,
                      width: 40,
                      height: 40,
                      child: Column(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: Colors.green,
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.3),
                                  blurRadius: 4,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: const Icon(
                              Icons.security,
                              color: Colors.white,
                              size: 16,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(4),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.1),
                                  blurRadius: 2,
                                  offset: const Offset(0, 1),
                                ),
                              ],
                            ),
                            child: Text(
                              '${radius.toInt()}m',
                              style: const TextStyle(
                                fontSize: 8,
                                fontWeight: FontWeight.bold,
                                color: Colors.green,
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              // ========================================================================

              if (_currentStudentLocation != null)
                MarkerLayer(
                  markers: [
                    Marker(
                      point: _currentStudentLocation!,
                      width: 80,
                      height: 80,
                      child: Column(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: _usingStudentGPS
                                  ? (_isGPSOffline ? Colors.orange : Colors.green)
                                  : Colors.red,
                              borderRadius: BorderRadius.circular(20),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.3),
                                  blurRadius: 6,
                                  offset: const Offset(0, 3),
                                ),
                              ],
                            ),
                            child: Icon(
                              _usingStudentGPS
                                  ? (_isGPSOffline ? Icons.signal_wifi_off : Icons.person_pin_circle)
                                  : Icons.person_pin_circle,
                              color: Colors.white,
                              size: 30,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(10),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.2),
                                  blurRadius: 4,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: Text(
                              _usingStudentGPS
                                  ? (_isGPSOffline ? 'Offline' : 'Student')
                                  : 'Student',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: _usingStudentGPS
                                    ? (_isGPSOffline ? Colors.orange : Colors.green)
                                    : Colors.red,
                              ),
                            ),
                          ),
                          if (_usingStudentGPS && _lastGPSUpdate != null && !_isGPSOffline) ...[
                            const SizedBox(height: 2),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                              decoration: BoxDecoration(
                                color: Colors.green.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                'Live',
                                style: TextStyle(
                                  fontSize: 8,
                                  color: Colors.green,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                          if (_usingStudentGPS && _isGPSOffline) ...[
                            const SizedBox(height: 2),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                              decoration: BoxDecoration(
                                color: Colors.orange.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                'Offline',
                                style: TextStyle(
                                  fontSize: 8,
                                  color: Colors.orange,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),

              MarkerLayer(
                markers: [
                  Marker(
                    point: _ubLocation,
                    width: 60,
                    height: 60,
                    child: Column(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: primaryColor,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.3),
                                blurRadius: 6,
                                offset: const Offset(0, 3),
                              ),
                            ],
                          ),
                          child: const Icon(
                            Icons.school,
                            color: Colors.white,
                            size: 24,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(8),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.2),
                                blurRadius: 4,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: const Text(
                            'UB',
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF862334),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),

              if (_pickedLocation != null)
                MarkerLayer(
                  markers: [
                    Marker(
                      point: _pickedLocation!,
                      width: 60,
                      height: 60,
                      child: Column(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.blue,
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.3),
                                  blurRadius: 6,
                                  offset: const Offset(0, 3),
                                ),
                              ],
                            ),
                            child: const Icon(
                              Icons.location_pin,
                              color: Colors.white,
                              size: 24,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(8),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.2),
                                  blurRadius: 4,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: const Text(
                              'Picked',
                              style: TextStyle(
                                fontSize: 8,
                                fontWeight: FontWeight.bold,
                                color: Colors.blue,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
            ],
          ),

          // ==================== ENHANCED LOCATION INFO PANEL ====================
          if (_currentStudentLocation != null && !_isPickingLocation)
            Positioned(
              left: 16,
              top: 16,
              child: AnimatedContainer(
                duration: Duration(milliseconds: 400),
                width: _isLocationPanelCollapsed ? 50 : 300,
                height: _isLocationPanelCollapsed ? 50 : 220,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.25),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                  border: Border.all(
                    color: _usingStudentGPS
                        ? (_isGPSOffline ? Colors.orange.withOpacity(0.3) : Colors.green.withOpacity(0.3))
                        : Color(0xFF862334).withOpacity(0.3),
                    width: 1,
                  ),
                ),
                child: _isLocationPanelCollapsed
                    ? Center(
                  child: Container(
                    decoration: BoxDecoration(
                      color: _usingStudentGPS
                          ? (_isGPSOffline ? Colors.orange : Colors.green)
                          : Color(0xFF862334),
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.2),
                          blurRadius: 6,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: IconButton(
                      icon: Icon(
                        _usingStudentGPS
                            ? (_isGPSOffline ? Icons.signal_wifi_off : Icons.person_pin_circle)
                            : Icons.person_pin_circle,
                        color: Colors.white,
                        size: 20,
                      ),
                      onPressed: () {
                        setState(() {
                          _isLocationPanelCollapsed = false;
                        });
                      },
                    ),
                  ),
                )
                    : SingleChildScrollView(
                  physics: NeverScrollableScrollPhysics(),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Header with gradient background
                        Container(
                          width: double.infinity,
                          padding: EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: _usingStudentGPS
                                  ? (_isGPSOffline
                                  ? [Colors.orange.shade50, Colors.orange.shade100]
                                  : [Colors.green.shade50, Colors.green.shade100])
                                  : [Color(0xFF862334).withOpacity(0.1), Color(0xFF862334).withOpacity(0.05)],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Row(
                                children: [
                                  Container(
                                    padding: EdgeInsets.all(6),
                                    decoration: BoxDecoration(
                                      color: _usingStudentGPS
                                          ? (_isGPSOffline ? Colors.orange : Colors.green)
                                          : Color(0xFF862334),
                                      shape: BoxShape.circle,
                                    ),
                                    child: Icon(
                                      _usingStudentGPS
                                          ? (_isGPSOffline ? Icons.signal_wifi_off : Icons.person_pin_circle)
                                          : Icons.person_pin_circle,
                                      color: Colors.white,
                                      size: 18,
                                    ),
                                  ),
                                  SizedBox(width: 8),
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        _usingStudentGPS ? 'STUDENT GPS' : 'STUDENT LOCATION',
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 12,
                                          color: _usingStudentGPS
                                              ? (_isGPSOffline ? Colors.orange : Colors.green)
                                              : Color(0xFF862334),
                                          letterSpacing: 0.5,
                                        ),
                                      ),
                                      if (_usingStudentGPS && _lastGPSUpdate != null)
                                        Text(
                                          _isGPSOffline ? 'Offline' : 'Live Tracking',
                                          style: TextStyle(
                                            fontSize: 10,
                                            color: _isGPSOffline ? Colors.orange.shade600 : Colors.green.shade600,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                    ],
                                  ),
                                ],
                              ),
                              IconButton(
                                icon: Icon(Icons.expand_less, size: 20, color: Colors.grey),
                                onPressed: () {
                                  setState(() {
                                    _isLocationPanelCollapsed = true;
                                  });
                                },
                              ),
                            ],
                          ),
                        ),

                        SizedBox(height: 12),

                        // Coordinates section
                        Container(
                          padding: EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade50,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: Colors.grey.shade200),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(Icons.location_on, size: 14, color: Colors.grey),
                                  SizedBox(width: 4),
                                  Text(
                                    'COORDINATES',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.grey.shade600,
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                ],
                              ),
                              SizedBox(height: 6),
                              Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'Latitude',
                                          style: TextStyle(fontSize: 10, color: Colors.grey),
                                        ),
                                        Text(
                                          _currentStudentLocation!.latitude.toStringAsFixed(6),
                                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'Longitude',
                                          style: TextStyle(fontSize: 10, color: Colors.grey),
                                        ),
                                        Text(
                                          _currentStudentLocation!.longitude.toStringAsFixed(6),
                                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),

                        SizedBox(height: 10),

                        // Status section
                        Row(
                          children: [
                            _buildStatusChip(
                              icon: Icons.security,
                              label: 'Safezones',
                              value: '${_safezones.length}',
                              color: Colors.green,
                            ),
                            SizedBox(width: 8),
                            _buildStatusChip(
                              icon: Icons.visibility,
                              label: 'Status',
                              value: _showSafezones ? 'Visible' : 'Hidden',
                              color: _showSafezones ? Colors.blue : Colors.orange,
                            ),
                            SizedBox(width: 8),
                            _buildStatusChip(
                              icon: Icons.zoom_in_map,
                              label: 'Zoom',
                              value: '${_currentZoom.toStringAsFixed(1)}x',
                              color: Colors.purple,
                            ),
                          ],
                        ),

                        if (_usingStudentGPS && _lastGPSUpdate != null) ...[
                          SizedBox(height: 10),
                          Container(
                            padding: EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: _isGPSOffline ? Colors.orange.shade50 : Colors.green.shade50,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: _isGPSOffline ? Colors.orange.shade100 : Colors.green.shade100),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  _isGPSOffline ? Icons.signal_wifi_off : Icons.update,
                                  size: 12,
                                  color: _isGPSOffline ? Colors.orange : Colors.green,
                                ),
                                SizedBox(width: 6),
                                Text(
                                  _isGPSOffline
                                      ? 'Offline - Last update ${_lastGPSUpdate!.difference(DateTime.now()).inSeconds.abs()}s ago'
                                      : 'Updated ${_lastGPSUpdate!.difference(DateTime.now()).inSeconds.abs()}s ago',
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: _isGPSOffline ? Colors.orange.shade700 : Colors.green.shade700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),

          // ==================== ENHANCED DEBUG PANEL ====================
          Positioned(
            left: 16,
            top: _isLocationPanelCollapsed ? 80 : (_currentStudentLocation != null ? 250 : 80),
            child: AnimatedContainer(
              duration: Duration(milliseconds: 400),
              width: _isDebugPanelCollapsed ? 45 : 220,
              height: _isDebugPanelCollapsed ? 45 : 180,
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.85),
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.3),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
                border: Border.all(color: Colors.grey.shade700),
              ),
              child: _isDebugPanelCollapsed
                  ? Center(
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.grey.shade800,
                    shape: BoxShape.circle,
                  ),
                  child: IconButton(
                    icon: Icon(Icons.bug_report, color: Colors.white, size: 18),
                    onPressed: () {
                      setState(() {
                        _isDebugPanelCollapsed = false;
                      });
                    },
                  ),
                ),
              )
                  : SingleChildScrollView(
                physics: NeverScrollableScrollPhysics(),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.analytics, size: 16, color: Colors.blue.shade300),
                              SizedBox(width: 6),
                              Text(
                                'SYSTEM DEBUG',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 11,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ],
                          ),
                          IconButton(
                            icon: Icon(Icons.close, size: 14, color: Colors.grey.shade400),
                            onPressed: () {
                              setState(() {
                                _isDebugPanelCollapsed = true;
                              });
                            },
                          ),
                        ],
                      ),

                      SizedBox(height: 8),

                      // Safezone stats
                      _buildDebugItem(
                        label: 'Safezones',
                        value: '${_safezones.length}',
                        color: Colors.green.shade400,
                      ),
                      _buildDebugItem(
                        label: 'Polygons',
                        value: '${_safezonePolygons.length}',
                        color: Colors.blue.shade400,
                      ),
                      _buildDebugItem(
                        label: 'Radii',
                        value: '${_safezoneRadii.length}',
                        color: Colors.purple.shade400,
                      ),

                      SizedBox(height: 6),

                      // GPS status with indicator
                      Container(
                        padding: EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: _usingStudentGPS
                              ? (_isGPSOffline ? Colors.orange.withOpacity(0.2) : Colors.green.withOpacity(0.2))
                              : Colors.red.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                color: _usingStudentGPS
                                    ? (_isGPSOffline ? Colors.orange : Colors.green)
                                    : Colors.red,
                                shape: BoxShape.circle,
                              ),
                            ),
                            SizedBox(width: 8),
                            Text(
                              'Student GPS: ${_usingStudentGPS ? (_isGPSOffline ? 'OFFLINE' : 'ACTIVE') : 'INACTIVE'}',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),

                      if (_usingStudentGPS && _lastGPSUpdate != null) ...[
                        SizedBox(height: 4),
                        Text(
                          _isGPSOffline
                              ? 'Last update: ${_lastGPSUpdate!.difference(DateTime.now()).inSeconds.abs()}s ago'
                              : 'Last update: ${_lastGPSUpdate!.difference(DateTime.now()).inSeconds.abs()}s',
                          style: TextStyle(
                            color: _isGPSOffline ? Colors.orange.shade300 : Colors.green.shade300,
                            fontSize: 9,
                          ),
                        ),
                      ],

                      SizedBox(height: 6),

                      // Map stats
                      Row(
                        children: [
                          Expanded(
                            child: _buildDebugItem(
                              label: 'Zoom',
                              value: _currentZoom.toStringAsFixed(1),
                              color: Colors.orange.shade400,
                            ),
                          ),
                          SizedBox(width: 8),
                          Expanded(
                            child: _buildDebugItem(
                              label: 'Meters/Pixel',
                              value: _getMetersPerPixel().toStringAsFixed(1),
                              color: Colors.cyan.shade400,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),

          // Enhanced Loading Indicator
          if (_isLoading)
            Container(
              color: Colors.black.withOpacity(0.4),
              child: Center(
                child: Container(
                  padding: EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.2),
                        blurRadius: 12,
                        offset: Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(
                        valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF862334)),
                        strokeWidth: 4,
                      ),
                      SizedBox(height: 16),
                      Text(
                        'Loading Map Data...',
                        style: TextStyle(
                          color: Color(0xFF862334),
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      SizedBox(height: 8),
                      Text(
                        'Fetching location and safezone information',
                        style: TextStyle(
                          color: Colors.grey.shade600,
                          fontSize: 12,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ),
            ),

          // Enhanced Map Controls (Right Side)
          Positioned(
            right: 16,
            top: 16,
            child: Container(
              padding: EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.15),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Column(
                children: [
                  _buildMapControlButton(
                    icon: Icons.add,
                    onPressed: _zoomIn,
                    tooltip: 'Zoom In',
                  ),
                  const SizedBox(height: 8),
                  _buildMapControlButton(
                    icon: Icons.remove,
                    onPressed: _zoomOut,
                    tooltip: 'Zoom Out',
                  ),
                  const SizedBox(height: 12),
                  _buildMapControlButton(
                    icon: Icons.person_pin_circle,
                    onPressed: _centerOnStudent,
                    tooltip: 'Center on Student',
                  ),
                  const SizedBox(height: 8),
                  _buildMapControlButton(
                    icon: Icons.school,
                    onPressed: _centerOnUB,
                    tooltip: 'Center on University',
                  ),
                  const SizedBox(height: 12),
                  _buildMapControlButton(
                    icon: _showSafezones ? Icons.location_off : Icons.location_on,
                    onPressed: _toggleSafezones,
                    tooltip: _showSafezones ? 'Hide Safezones' : 'Show Safezones',
                  ),
                  const SizedBox(height: 8),
                  if (!_isPickingLocation)
                    _buildMapControlButton(
                      icon: Icons.edit_location,
                      onPressed: _startLocationPicking,
                      tooltip: 'Pick Location',
                      backgroundColor: Colors.blue,
                    ),
                ],
              ),
            ),
          ),

          // Enhanced Picking Mode Indicator
          if (_isPickingLocation)
            Positioned(
              top: MediaQuery.of(context).size.height / 2 - 80,
              left: 0,
              right: 0,
              child: Container(
                padding: const EdgeInsets.all(20),
                margin: const EdgeInsets.symmetric(horizontal: 32),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Colors.blue.shade600, Colors.blue.shade800],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.blue.withOpacity(0.4),
                      blurRadius: 12,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    Icon(Icons.edit_location_alt, color: Colors.white, size: 40),
                    const SizedBox(height: 12),
                    const Text(
                      'Select Location on Map',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Tap anywhere on the map to choose a location',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 14,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    if (_pickedLocation != null) ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Column(
                          children: [
                            Text(
                              'Selected Location:',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            SizedBox(height: 4),
                            Text(
                              '${_pickedLocation!.latitude.toStringAsFixed(6)}, ${_pickedLocation!.longitude.toStringAsFixed(6)}',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),

          // Enhanced Instructions Card
          if (_safezones.isEmpty && !_isLoading && !_isPickingLocation)
            Positioned(
              left: 16,
              right: 16,
              bottom: 16,
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Colors.orange.shade50, Colors.orange.shade100],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.orange.shade200),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.1),
                      blurRadius: 8,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Container(
                      padding: EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.orange.shade500,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(Icons.info, color: Colors.white, size: 20),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'No Safezones Configured',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                              color: Colors.orange.shade800,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Add safezones in the Safe Zones tab to monitor student locations and receive alerts',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.orange.shade700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}