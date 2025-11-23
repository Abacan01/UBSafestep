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
  final bool isPickingMode;

  const MapScreen({
    Key? key,
    required this.userData,
    required this.userId,
    this.isPickingMode = false,
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
  final TextEditingController _searchController = TextEditingController();

  LatLng? _currentStudentLocation;
  List<LatLng> _safezonePolygons = [];
  List<double> _safezoneRadii = [];
  bool _isLoading = true;
  bool _showSafezones = true;
  double _currentZoom = 13.0;

  // Search and location picking variables
  Timer? _debounce;
  List<Placemark> _searchSuggestions = [];
  List<Location> _searchLocations = [];
  bool _showSuggestions = false;
  LatLng? _pickedLocation;


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

    if (!widget.isPickingMode) {
      _startStudentGPSListener();
    } else {
      // Set the initial picked location to the map's center when picking starts
      WidgetsBinding.instance.addPostFrameCallback((_) {
        setState(() {
          _pickedLocation = _mapController.center;
        });
      });
    }

    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _gpsDataSubscription?.cancel();
    _gpsTimeoutTimer?.cancel();
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onSearchChanged() {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () {
      if (_searchController.text.isNotEmpty) {
        _getSearchSuggestions(_searchController.text);
      } else {
        if (mounted) {
          setState(() {
            _showSuggestions = false;
          });
        }
      }
    });
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
    } catch (e) {
      print('[STUDENT GPS] Failed to start listener: $e');
      _setGPSOffline();
    }
  }

  void _startGPSTimeoutTimer() {
    _gpsTimeoutTimer?.cancel();
    _gpsTimeoutTimer = Timer.periodic(const Duration(seconds: 10), (timer) {
      if (_lastGPSUpdate != null && DateTime.now().difference(_lastGPSUpdate!).inSeconds > 15) {
        if (!_isGPSOffline) {
          print('[STUDENT GPS] No updates - marking as offline');
          _setGPSOffline();
        }
      }
    });
  }

  void _setGPSOffline() {
    if (mounted) setState(() => _isGPSOffline = true);
  }

  void _setGPSOnline() {
    if (mounted) setState(() => _isGPSOffline = false);
  }

  Future<String> _getAddressFromLatLng(LatLng location) async {
    try {
      List<Placemark> placemarks = await placemarkFromCoordinates(location.latitude, location.longitude);
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
      if (_isGPSOffline) _setGPSOnline();
      _checkSafezonesWithStudentLocation(newLocation);
    }
  }

  void _checkSafezonesWithStudentLocation(LatLng location) {
    _locationMonitor.checkAndNotifySafezoneStatus(
      studentId: widget.userData['StudentID'],
      parentGuardianId: widget.userId,
      studentLat: location.latitude,
      studentLng: location.longitude,
    );
  }

  Future<void> _loadMapData() async {
    setState(() => _isLoading = true);
    try {
      final studentData = await _firestoreService.getStudentData(widget.userData['StudentID']);
      if (studentData != null && studentData['lastLatitude'] != null) {
        _currentStudentLocation = LatLng(studentData['lastLatitude'], studentData['lastLongitude']);
      } else {
        _currentStudentLocation = _ubLocation;
      }

      final safezones = await _firestoreService.getSafezonesByParent(widget.userId);
      final safezoneData = _parseSafezoneData(safezones);
      if (mounted) {
        setState(() {
          _safezonePolygons = safezoneData['polygons'];
          _safezoneRadii = safezoneData['radii'];
        });
      }
    } catch (e) {
      print('[MAP] Error loading map data: $e');
      if (mounted) _currentStudentLocation = _ubLocation;
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Map<String, dynamic> _parseSafezoneData(List<Map<String, dynamic>> safezones) {
    List<LatLng> polygons = [];
    List<double> radii = [];
    for (var zone in safezones) {
      final coordinates = zone['Coordinates'];
      if (coordinates is String && coordinates.isNotEmpty) {
        final parts = coordinates.split(',');
        if (parts.length == 2) {
          final lat = double.tryParse(parts[0].trim());
          final lng = double.tryParse(parts[1].trim());
          if (lat != null && lng != null) {
            polygons.add(LatLng(lat, lng));
            radii.add((zone['Radius'] as num? ?? 200.0).toDouble());
          }
        }
      }
    }
    return {'polygons': polygons, 'radii': radii};
  }

  List<LatLng> _generateCirclePoints(LatLng center, double radiusMeters, int segments) {
    final points = <LatLng>[];
    const earthRadius = 6378137.0;
    final lat = center.latitude * math.pi / 180;
    final lon = center.longitude * math.pi / 180;

    for (int i = 0; i <= segments; i++) {
      final bearing = 2 * math.pi * i / segments;
      final angDist = radiusMeters / earthRadius;

      final lat2 = math.asin(math.sin(lat) * math.cos(angDist) + math.cos(lat) * math.sin(angDist) * math.cos(bearing));
      final lon2 = lon + math.atan2(math.sin(bearing) * math.sin(angDist) * math.cos(lat), math.cos(angDist) - math.sin(lat) * math.sin(lat2));

      points.add(LatLng(lat2 * 180 / math.pi, lon2 * 180 / math.pi));
    }
    return points;
  }

  void _zoomIn() => _mapController.move(_mapController.center, _currentZoom + 1);
  void _zoomOut() => _mapController.move(_mapController.center, _currentZoom - 1);

  void _centerOnStudent() {
    if (_currentStudentLocation != null) {
      _mapController.move(_currentStudentLocation!, 15.0);
    }
  }

  void _centerOnUB() => _mapController.move(_ubLocation, 15.0);
  void _toggleSafezones() => setState(() => _showSafezones = !_showSafezones);

  Future<void> _getSearchSuggestions(String query) async {
    if (query.isEmpty) return;
    try {
      List<Location> locations = await locationFromAddress(query);
      List<Placemark> placemarks = [];
      for (var location in locations) {
        try {
          List<Placemark> p = await placemarkFromCoordinates(location.latitude, location.longitude);
          if (p.isNotEmpty) placemarks.add(p.first);
        } catch (e) { /* Ignore */ }
      }
      if (mounted) {
        setState(() {
          _searchSuggestions = placemarks;
          _searchLocations = locations;
          _showSuggestions = true;
        });
      }
    } catch (e) {
      print("Error searching location: $e");
    }
  }

  void _centerOnMyLocation() async {
    setState(() => _isLoading = true);
    try {
      final position = await _locationMonitor.getCurrentLocation();
      if (position != null) {
        final myLocation = LatLng(position.latitude, position.longitude);
        _mapController.move(myLocation, 15.0);
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Could not get current location. Please ensure permissions are granted.'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      print('Error getting location: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final primaryColor = const Color(0xFF862334);
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.isPickingMode ? 'Pick a Location' : 'Live Location Map',
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        backgroundColor: primaryColor,
        foregroundColor: Colors.white,
        actions: [
          if (widget.isPickingMode)
            IconButton(
              icon: const Icon(Icons.check),
              onPressed: () => Navigator.pop(context, _pickedLocation),
              tooltip: 'Confirm Location',
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
              onPositionChanged: (position, hasGesture) {
                if (mounted) {
                  setState(() {
                    _currentZoom = position.zoom ?? _currentZoom;
                    if (widget.isPickingMode) {
                      _pickedLocation = position.center;
                    }
                  });
                }
              },
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.example.ubsafestep',
              ),
              if (_showSafezones)
                PolygonLayer(
                  polygons: List.generate(_safezonePolygons.length, (index) {
                    final points = _generateCirclePoints(_safezonePolygons[index], _safezoneRadii[index], 36);
                    return Polygon(
                      points: points,
                      color: Colors.green.withOpacity(0.2),
                      borderColor: Colors.green,
                      borderStrokeWidth: 2,
                      isFilled: true,
                    );
                  }),
                ),
              if (!widget.isPickingMode)
                MarkerLayer(
                  markers: [
                    if (_currentStudentLocation != null)
                      Marker(
                        point: _currentStudentLocation!,
                        width: 80,
                        height: 80,
                        child: Icon(
                          Icons.person_pin_circle,
                          color: _usingStudentGPS ? (_isGPSOffline ? Colors.orange : Colors.green) : Colors.red,
                          size: 40,
                        ),
                      ),
                    Marker(
                      point: _ubLocation,
                      width: 80,
                      height: 80,
                      child: Icon(Icons.school, color: primaryColor, size: 40),
                    ),
                  ],
                ),
            ],
          ),
          if (widget.isPickingMode)
            const Center(
              child: IgnorePointer(
                child: Icon(
                  Icons.location_pin,
                  color: Colors.red,
                  size: 50,
                ),
              ),
            ),
          Positioned(
            top: 10,
            left: 15,
            right: 15,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(30.0),
                    boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 10)],
                  ),
                  child: TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      hintText: 'Search for a location',
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.only(left: 20, top: 15),
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.search),
                        onPressed: () {
                          _getSearchSuggestions(_searchController.text);
                          FocusScope.of(context).unfocus();
                        },
                      ),
                    ),
                  ),
                ),
                if (_showSuggestions)
                  Card(
                    margin: const EdgeInsets.only(top: 8.0),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.3),
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: _searchSuggestions.length,
                        itemBuilder: (context, index) {
                          final placemark = _searchSuggestions[index];
                          final location = _searchLocations[index];
                          final address = "${placemark.name}, ${placemark.locality}";
                          return ListTile(
                            title: Text(address),
                            onTap: () {
                              _mapController.move(LatLng(location.latitude, location.longitude), 15.0);
                              if (mounted) {
                                setState(() {
                                  _showSuggestions = false;
                                  _searchController.clear();
                                });
                              }
                              FocusScope.of(context).unfocus();
                            },
                          );
                        },
                      ),
                    ),
                  ),
              ],
            ),
          ),
          if (!widget.isPickingMode)
            Positioned(
              right: 16,
              top: 80,
              child: Column(
                children: [
                  _buildMapControlButton(icon: Icons.add, onPressed: _zoomIn, tooltip: 'Zoom In'),
                  _buildMapControlButton(icon: Icons.remove, onPressed: _zoomOut, tooltip: 'Zoom Out'),
                  _buildMapControlButton(icon: Icons.person_pin, onPressed: _centerOnStudent, tooltip: 'Center on Student'),
                  _buildMapControlButton(icon: Icons.my_location, onPressed: _centerOnMyLocation, tooltip: 'My Location'),
                  _buildMapControlButton(icon: Icons.school, onPressed: _centerOnUB, tooltip: 'Center on UB'),
                  _buildMapControlButton(
                    icon: _showSafezones ? Icons.visibility_off : Icons.visibility,
                    onPressed: _toggleSafezones,
                    tooltip: _showSafezones ? 'Hide Safezones' : 'Show Safezones',
                  ),
                ].map((e) => Padding(padding: const EdgeInsets.only(top: 8), child: e)).toList(),
              ),
            ),
          if (_isLoading)
            Container(color: Colors.black.withOpacity(0.5), child: const Center(child: CircularProgressIndicator())),
        ],
      ),
    );
  }

  Widget _buildMapControlButton({required IconData icon, required VoidCallback onPressed, required String tooltip}) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 6)],
      ),
      child: IconButton(
        icon: Icon(icon, color: const Color(0xFF862334)),
        onPressed: onPressed,
        tooltip: tooltip,
        iconSize: 22,
      ),
    );
  }
}
