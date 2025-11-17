import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geocoding/geocoding.dart';
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
  final RealtimeDatabaseService _realtimeDatabaseService =
      RealtimeDatabaseService();

  LatLng? _currentStudentLocation;
  List<LatLng> _safezonePolygons = [];
  List<double> _safezoneRadii = [];
  List<Map<String, dynamic>> _safezones = [];
  bool _isLoading = true;
  bool _showSafezones = true;
  double _currentZoom = 13.0;
  LatLng? _pickedLocation;
  bool _isPickingLocation = false;

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

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _startStudentGPSListener();
    });
  }

  @override
  void dispose() {
    _gpsDataSubscription?.cancel();
    _gpsTimeoutTimer?.cancel();
    super.dispose();
  }

  void _startStudentGPSListener() {
    const studentDeviceId = "ESP32_189426166412052";
    print('[STUDENT GPS] Starting listener for device: $studentDeviceId');

    try {
      _gpsDataSubscription =
          _realtimeDatabaseService.getArduinoGPSData(studentDeviceId).listen(
        _handleStudentGPSUpdate,
        onError: (error) {
          print('[STUDENT GPS] Error listening: $error');
          _setGPSOffline();
        },
        cancelOnError: false,
      );
      _startGPSTimeoutTimer();
      _checkDeviceExists(studentDeviceId);
    } catch (e) {
      print('[STUDENT GPS] Failed to start listener: $e');
      _setGPSOffline();
    }
  }

  void _startGPSTimeoutTimer() {
    _gpsTimeoutTimer?.cancel();
    _gpsTimeoutTimer = Timer.periodic(const Duration(seconds: 10), (timer) {
      if (_lastGPSUpdate != null) {
        final secondsSinceLastUpdate =
            DateTime.now().difference(_lastGPSUpdate!).inSeconds;
        if (secondsSinceLastUpdate > 15) {
          if (!_isGPSOffline) {
            print(
                '[STUDENT GPS] No updates for $secondsSinceLastUpdate seconds - marking as offline');
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
      print('[STUDENT GPS] Device exists in database: $exists');
      if (!exists) {
        print('[STUDENT GPS] Device $deviceId not found in Realtime Database');
      }
    } catch (e) {
      print('[STUDENT GPS] Error checking device: $e');
    }
  }

  Future<String> _getAddressFromLatLng(LatLng location) async {
    try {
      List<Placemark> placemarks = await placemarkFromCoordinates(
        location.latitude,
        location.longitude,
      );
      if (placemarks.isNotEmpty) {
        final place = placemarks.first;
        return "${place.name}, ${place.street}, ${place.locality}";
      }
      return "Unknown Location";
    } catch (e) {
      print("Error getting address: $e");
      return "Could not get address";
    }
  }

  void _handleStudentGPSUpdate(Map<String, dynamic> gpsData) async {
    if (gpsData['latitude'] != null && gpsData['longitude'] != null) {
      final newLocation = LatLng(
        (gpsData['latitude'] as num).toDouble(),
        (gpsData['longitude'] as num).toDouble(),
      );

      final locationName = await _getAddressFromLatLng(newLocation);

      await _firestoreService.saveStudentLocation(
        studentId: widget.userData['StudentID'],
        latitude: newLocation.latitude,
        longitude: newLocation.longitude,
        locationName: locationName,
        timestamp: DateTime.now().toIso8601String(),
      );

      if (mounted) {
        setState(() {
          _usingStudentGPS = true;
          _lastGPSUpdate = DateTime.now();
          _currentStudentLocation = newLocation;
        });
      }

      if (_isGPSOffline) {
        print('[STUDENT GPS] Connection restored');
        _setGPSOnline();
      }

      print('[STUDENT GPS] Real-time update: $newLocation ($locationName)');
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
        );
      });
    }
  }

  Future<void> _loadMapData() async {
    try {
      print('[MAP] === Loading Map Data ===');

      final studentData =
          await _firestoreService.getStudentData(widget.userData['StudentID']);
      print('[MAP] Student data loaded: ${studentData != null}');

      if (studentData != null &&
          studentData['lastLatitude'] != null &&
          studentData['lastLongitude'] != null) {
        setState(() {
          _currentStudentLocation = LatLng(
            studentData['lastLatitude'],
            studentData['lastLongitude'],
          );
        });
        print('[MAP] Student location: $_currentStudentLocation');
      } else {
        print('[MAP] No student location data available');
        setState(() {
          _currentStudentLocation = _ubLocation;
        });
      }

      final safezones =
          await _firestoreService.getSafezonesByParent(widget.userId);
      print('[MAP] Raw safezones from Firestore: ${safezones.length} zones');

      final safezoneData = _parseSafezoneData(safezones);
      if (mounted) {
        setState(() {
          _safezones = safezones;
          _safezonePolygons = safezoneData['polygons'];
          _safezoneRadii = safezoneData['radii'];
        });
      }

      print('[MAP] Final safezone polygons: ${_safezonePolygons.length}');
    } catch (e) {
      print('[MAP] Error loading map data: $e');
      if (mounted) {
        setState(() {
          _currentStudentLocation = _ubLocation;
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Map<String, dynamic> _parseSafezoneData(
      List<Map<String, dynamic>> safezones) {
    List<LatLng> polygons = [];
    List<double> radii = [];

    for (var zone in safezones) {
      final coordinates = zone['Coordinates'];
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
          print('[MAP] Error parsing coordinates: $e');
        }
      }
    }

    return {
      'polygons': polygons,
      'radii': radii,
    };
  }

  List<LatLng> _generateCirclePoints(
      LatLng center, double radiusMeters, int segments) {
    final points = <LatLng>[];
    final earthRadius = 6378137.0;

    for (int i = 0; i <= segments; i++) {
      final angle = 2 * math.pi * i / segments;

      final dx = radiusMeters *
          math.cos(angle) /
          earthRadius *
          (180 / math.pi);
      final dy = radiusMeters *
          math.sin(angle) /
          earthRadius *
          (180 / math.pi) /
          math.cos(center.latitude * math.pi / 180);

      points.add(LatLng(center.latitude + dy, center.longitude + dx));
    }
    return points;
  }

  void _startLocationPicking() {
    setState(() {
      _isPickingLocation = true;
      _pickedLocation = null;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Tap on the map to select a location'),
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
            content: Text(
                'Location picked: ${latLng.latitude.toStringAsFixed(6)}, ${latLng.longitude.toStringAsFixed(6)}'),
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
    if (!mounted) return;
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
      );
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Location data refreshed'),
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
        final location = LatLng(position.latitude, position.longitude);
        final locationName = await _getAddressFromLatLng(location);

        await _firestoreService.saveStudentLocation(
          studentId: widget.userData['StudentID'],
          latitude: position.latitude,
          longitude: position.longitude,
          locationName: locationName,
          timestamp: DateTime.now().toIso8601String(),
        );

        await _locationMonitor.checkAndNotifySafezoneStatus(
          studentId: widget.userData['StudentID'],
          parentGuardianId: widget.userId,
          studentLat: position.latitude,
          studentLng: position.longitude,
        );

        await _loadMapData();

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Location updated and safe zones checked'),
              backgroundColor: Colors.green,
              duration: Duration(seconds: 3),
            ),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Could not get current location'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error updating location: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _zoomIn() {
    final newZoom = _currentZoom + 1;
    _mapController.move(_mapController.center, newZoom);
  }

  void _zoomOut() {
    final newZoom = _currentZoom - 1;
    _mapController.move(_mapController.center, newZoom);
  }

  void _centerOnStudent() {
    if (_currentStudentLocation != null) {
      _mapController.move(_currentStudentLocation!, 15.0);
      if (mounted) {
        setState(() {
          _currentZoom = 15.0;
        });
      }
    }
  }

  void _centerOnUB() {
    _mapController.move(_ubLocation, 15.0);
    if (mounted) {
      setState(() {
        _currentZoom = 15.0;
      });
    }
  }

  void _toggleSafezones() {
    if (mounted) {
      setState(() {
        _showSafezones = !_showSafezones;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final primaryColor = const Color(0xFF862334);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          _isPickingLocation ? 'Pick Location on Map' : 'Live Location Map',
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
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
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              center: _currentStudentLocation ?? _ubLocation,
              zoom: _currentZoom,
              maxZoom: 18.0,
              minZoom: 10.0,
              onTap: _handleMapTap,
              onPositionChanged: (position, hasGesture) {
                if (hasGesture && mounted) {
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
              if (_showSafezones && _safezonePolygons.isNotEmpty)
                PolygonLayer(
                  polygons: _safezonePolygons.asMap().entries.map((entry) {
                    final index = entry.key;
                    final center = entry.value;
                    final radiusMeters = _safezoneRadii[index];
                    final points =
                        _generateCirclePoints(center, radiusMeters, 36);

                    return Polygon(
                      points: points,
                      color: Colors.green.withOpacity(0.2),
                      borderColor: Colors.green,
                      borderStrokeWidth: 2,
                      isFilled: true,
                    );
                  }).toList(),
                ),
              if (_showSafezones && _safezonePolygons.isNotEmpty)
                MarkerLayer(
                  markers: _safezonePolygons.asMap().entries.map((entry) {
                    return Marker(
                      point: entry.value,
                      width: 40,
                      height: 40,
                      child: const Icon(
                        Icons.security,
                        color: Colors.green,
                        size: 30,
                      ),
                    );
                  }).toList(),
                ),
              if (_currentStudentLocation != null)
                MarkerLayer(
                  markers: [
                    Marker(
                      point: _currentStudentLocation!,
                      width: 80,
                      height: 80,
                      child: Icon(
                        Icons.person_pin_circle,
                        color: _usingStudentGPS
                            ? (_isGPSOffline ? Colors.orange : Colors.green)
                            : Colors.red,
                        size: 40,
                      ),
                    ),
                  ],
                ),
              MarkerLayer(
                markers: [
                  Marker(
                    point: _ubLocation,
                    width: 80,
                    height: 80,
                    child: Icon(
                      Icons.school,
                      color: primaryColor,
                      size: 40,
                    ),
                  ),
                ],
              ),
              if (_pickedLocation != null)
                MarkerLayer(
                  markers: [
                    Marker(
                      point: _pickedLocation!,
                      width: 80,
                      height: 80,
                      child: const Icon(
                        Icons.location_pin,
                        color: Colors.blue,
                        size: 40,
                      ),
                    ),
                  ],
                ),
            ],
          ),
          Positioned(
            right: 16,
            top: 16,
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
                  icon: Icons.my_location,
                  onPressed: _centerOnStudent,
                  tooltip: 'Center on Student',
                ),
                const SizedBox(height: 8),
                _buildMapControlButton(
                  icon: Icons.school,
                  onPressed: _centerOnUB,
                  tooltip: 'Center on UB',
                ),
                const SizedBox(height: 12),
                _buildMapControlButton(
                  icon: _showSafezones
                      ? Icons.visibility_off
                      : Icons.visibility,
                  onPressed: _toggleSafezones,
                  tooltip: _showSafezones ? 'Hide Safezones' : 'Show Safezones',
                ),
              ],
            ),
          ),
          if (_isLoading)
            Container(
              color: Colors.black.withOpacity(0.5),
              child: const Center(
                child: CircularProgressIndicator(),
              ),
            ),
        ],
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
}
