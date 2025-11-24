import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geocoding/geocoding.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../services/realtime_database_service.dart';
import '../../services/firestore_service.dart';
import '../../services/location_monitor_service.dart';
import 'dart:math' as math;
import 'dart:async';

class MapScreen extends StatefulWidget {
  final Map<String, dynamic> userData;
  final String userId;
  final bool isPickingMode;
  final double? previewRadius;

  const MapScreen({
    Key? key,
    required this.userData,
    required this.userId,
    this.isPickingMode = false,
    this.previewRadius,
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
  List<String> _safezoneNames = [];
  List<IconData> _safezoneIcons = [];
  List<LatLng> _safezoneMarkerPositions = [];
  List<bool> _safezoneIsPredefined = [];
  bool _isLoading = true;
  bool _showSafezones = true;
  double _currentZoom = 13.0;
  double _previewRadius = 150.0; // For radius preview in picking mode

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
    _previewRadius = widget.previewRadius ?? 150.0;
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
      // Only start timeout timer if we don't already have offline status from database
      // The timer will check for new updates
      if (!_isGPSOffline) {
        _startGPSTimeoutTimer();
      } else {
        // If already offline, start timer to check if it comes back online
        _startGPSTimeoutTimer();
      }
    } catch (e) {
      print('[STUDENT GPS] Failed to start listener: $e');
      _setGPSOffline();
    }
  }

  void _startGPSTimeoutTimer() {
    _gpsTimeoutTimer?.cancel();
    
    // Check immediately first, then set up periodic checks
    _checkGPSStatusImmediately();
    
    _gpsTimeoutTimer = Timer.periodic(const Duration(seconds: 10), (timer) async {
      await _checkGPSStatusImmediately();
    });
  }

  Future<void> _checkGPSStatusImmediately() async {
    if (_lastGPSUpdate != null) {
      final secondsSinceUpdate = DateTime.now().difference(_lastGPSUpdate!).inSeconds;
      if (secondsSinceUpdate > 3) {
        // No updates received for more than 3 seconds - mark as offline
        if (!_isGPSOffline) {
          print('[STUDENT GPS] No updates for ${secondsSinceUpdate}s - marking as offline');
          _setGPSOffline();
        }
      }
      // Don't mark as online here - only _handleStudentGPSUpdate should mark as online
      // This ensures we only show online when actually receiving real-time updates
    } else if (_usingStudentGPS) {
        // If we're using GPS but have no update timestamp, check database
        try {
          final studentData = await _firestoreService.getStudentData(widget.userData['StudentID']);
          if (studentData != null) {
            final lastUpdate = studentData['lastLocationUpdate'];
            if (lastUpdate != null) {
              DateTime? lastUpdateTime;
              if (lastUpdate is Timestamp) {
                lastUpdateTime = lastUpdate.toDate();
              } else if (lastUpdate is String) {
                try {
                  lastUpdateTime = DateTime.parse(lastUpdate);
                } catch (e) {
                  print('[STUDENT GPS] Error parsing timestamp: $e');
                }
              }
              
              if (lastUpdateTime != null) {
                _lastGPSUpdate = lastUpdateTime;
                final secondsSinceUpdate = DateTime.now().difference(lastUpdateTime).inSeconds;
                // Only mark as offline if stale, but don't mark as online based on database alone
                if (secondsSinceUpdate > 3) {
                  if (!_isGPSOffline) {
                    print('[STUDENT GPS] Database check - offline (${secondsSinceUpdate}s ago)');
                    _setGPSOffline();
                  }
                }
                // Don't mark as online here - wait for real-time update confirmation
              }
            }
          }
        } catch (e) {
          print('[STUDENT GPS] Error checking database: $e');
        }
      }
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
        // Build address with comprehensive priority: thoroughfare/street > name (establishment) > subLocality > locality
        List<String> addressParts = [];
        
        // Helper to check if a string looks like a Plus Code or encoded value
        bool _isValidAddressPart(String? value) {
          if (value == null || value.isEmpty) return false;
          // Filter out Plus Code patterns (e.g., "R5jm+fmh") and other encoded values
          if (RegExp(r'^[A-Z0-9]+\+[A-Z0-9]+$').hasMatch(value)) return false;
          if (value.length < 3) return false; // Too short to be meaningful
          return true;
        }
        
        // Helper to check if value is already in addressParts
        bool _isAlreadyAdded(String? value) {
          return value != null && addressParts.contains(value);
        }
        
        // Priority 1: Try to get thoroughfare (road name) - this is the actual street/road name
        if (_isValidAddressPart(place.thoroughfare)) {
          addressParts.add(place.thoroughfare!);
        }
        // If thoroughfare not available, try street (which combines subThoroughfare + thoroughfare)
        else if (_isValidAddressPart(place.street)) {
          addressParts.add(place.street!);
        }
        
        // Priority 2: If no street/road name, try to get establishment name (nearest place)
        if (addressParts.isEmpty && _isValidAddressPart(place.name)) {
          addressParts.add(place.name!);
        }
        
        // Priority 3: Add subLocality (neighborhood/area) if available
        if (_isValidAddressPart(place.subLocality) && !_isAlreadyAdded(place.subLocality)) {
          addressParts.add(place.subLocality!);
        }
        
        // Priority 4: Add locality (city) if available
        if (_isValidAddressPart(place.locality) && !_isAlreadyAdded(place.locality)) {
          addressParts.add(place.locality!);
        }
        
        // Priority 5: If we still don't have a street/establishment, try name again (might be a landmark)
        if (addressParts.length <= 1 && _isValidAddressPart(place.name) && !_isAlreadyAdded(place.name)) {
          // Insert name before city if we only have city
          if (addressParts.length == 1 && addressParts.first == place.locality) {
            addressParts.insert(0, place.name!);
          } else if (!_isAlreadyAdded(place.name)) {
            addressParts.insert(0, place.name!);
          }
        }
        
        // Fallback to administrativeArea if we have nothing else
        if (addressParts.isEmpty && _isValidAddressPart(place.administrativeArea)) {
          addressParts.add(place.administrativeArea!);
        }
        
        return addressParts.isNotEmpty ? addressParts.join(', ') : "Unknown Location";
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
        
        // Check if GPS is offline based on last update timestamp
        final lastUpdate = studentData['lastLocationUpdate'];
        if (lastUpdate != null) {
          DateTime? lastUpdateTime;
          
          // Handle different timestamp formats
          if (lastUpdate is Timestamp) {
            lastUpdateTime = lastUpdate.toDate();
          } else if (lastUpdate is String) {
            try {
              lastUpdateTime = DateTime.parse(lastUpdate);
            } catch (e) {
              print('[MAP] Error parsing timestamp: $e');
            }
          }
          
          if (lastUpdateTime != null) {
            final secondsSinceUpdate = DateTime.now().difference(lastUpdateTime).inSeconds;
            _lastGPSUpdate = lastUpdateTime;
            
            // Always start as offline - only mark as online when we receive real-time updates
            // The database timestamp might be stale even if it's recent
            _usingStudentGPS = true; // We have GPS data
            _isGPSOffline = true; // Start offline until we confirm real-time updates
            print('[MAP] GPS initial state - last update was ${secondsSinceUpdate}s ago, waiting for real-time confirmation');
          } else {
            // No valid timestamp, assume offline if we have location data
            _usingStudentGPS = studentData['lastLatitude'] != null;
            _isGPSOffline = _usingStudentGPS;
          }
        } else {
          // No timestamp available
          _usingStudentGPS = studentData['lastLatitude'] != null;
          _isGPSOffline = _usingStudentGPS;
        }
      } else {
        _currentStudentLocation = _ubLocation;
        _usingStudentGPS = false;
        _isGPSOffline = false;
      }

      final parentSafezones = await _firestoreService.getSafezonesByParent(widget.userId);
      final predefinedSafezones = _firestoreService.getPredefinedSafezones();
      // Combine parent safezones with predefined safezones
      final allSafezones = [...parentSafezones, ...predefinedSafezones];
      final safezoneData = _parseSafezoneData(allSafezones);
      if (mounted) {
        // Don't set GPS status here - let the real-time listener and timeout timer handle it
        // This ensures we only show online when actually receiving updates
        
        setState(() {
          _safezonePolygons = safezoneData['polygons'];
          _safezoneRadii = safezoneData['radii'];
          _safezoneNames = safezoneData['names'];
          _safezoneIcons = safezoneData['icons'];
          _safezoneMarkerPositions = safezoneData['markerPositions'];
          _safezoneIsPredefined = safezoneData['isPredefined'] ?? [];
        });
        
        // Center map on student location after data is loaded
        if (!widget.isPickingMode && _currentStudentLocation != null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              Future.delayed(const Duration(milliseconds: 100), () {
                if (mounted) {
                  _animateToLocation(_currentStudentLocation!, 15.0);
                }
              });
            }
          });
        }
      }
    } catch (e) {
      print('[MAP] Error loading map data: $e');
      if (mounted) {
        _currentStudentLocation = _ubLocation;
        _usingStudentGPS = false;
        _isGPSOffline = false;
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Map<String, dynamic> _parseSafezoneData(List<Map<String, dynamic>> safezones) {
    List<LatLng> polygons = [];
    List<double> radii = [];
    List<String> names = [];
    List<IconData> icons = [];
    List<LatLng> markerPositions = [];
    List<bool> isPredefined = [];
    
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
            names.add(zone['Zonename'] ?? 'Safezone');
            
            // Check if this is a predefined safezone
            final isPredefinedZone = zone['isPredefined'] == true || 
                _firestoreService.isPredefinedSafezone(coordinates);
            isPredefined.add(isPredefinedZone);
            
            // Get icon from stored data or use default based on name
            final iconCodePoint = zone['IconCodePoint'];
            IconData icon;
            if (iconCodePoint != null && iconCodePoint is int) {
              icon = IconData(iconCodePoint, fontFamily: 'MaterialIcons');
            } else {
              icon = _getSafezoneIcon(zone['Zonename'] ?? 'Safezone');
            }
            icons.add(icon);
            markerPositions.add(LatLng(lat, lng));
          }
        }
      }
    }
    
    // Adjust marker positions to prevent overlap
    final adjustedPositions = _adjustMarkerPositions(markerPositions);
    
    return {
      'polygons': polygons, 
      'radii': radii, 
      'names': names, 
      'icons': icons,
      'markerPositions': adjustedPositions,
      'isPredefined': isPredefined,
    };
  }

  // Calculate distance between two points in meters
  double _calculateDistance(LatLng point1, LatLng point2) {
    const earthRadius = 6378137.0; // Earth radius in meters
    final lat1 = point1.latitude * math.pi / 180;
    final lat2 = point2.latitude * math.pi / 180;
    final dLat = (point2.latitude - point1.latitude) * math.pi / 180;
    final dLng = (point2.longitude - point1.longitude) * math.pi / 180;

    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(lat1) * math.cos(lat2) *
        math.sin(dLng / 2) * math.sin(dLng / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));

    return earthRadius * c;
  }

  // Adjust marker positions to prevent overlap (minimum 50 meters apart)
  List<LatLng> _adjustMarkerPositions(List<LatLng> positions) {
    if (positions.length <= 1) return positions;

    final adjusted = List<LatLng>.from(positions);
    const minDistance = 50.0; // Minimum distance in meters
    const offsetStep = 0.0001; // Small offset in degrees (approximately 11 meters)

    for (int i = 0; i < adjusted.length; i++) {
      for (int j = i + 1; j < adjusted.length; j++) {
        final distance = _calculateDistance(adjusted[i], adjusted[j]);
        
        if (distance < minDistance) {
          // Calculate offset direction (perpendicular to line between points)
          final dx = adjusted[j].longitude - adjusted[i].longitude;
          final dy = adjusted[j].latitude - adjusted[i].latitude;
          final angle = math.atan2(dy, dx);
          
          // Offset both markers in opposite directions
          final offsetLat1 = adjusted[i].latitude + offsetStep * math.cos(angle + math.pi / 2);
          final offsetLng1 = adjusted[i].longitude + offsetStep * math.sin(angle + math.pi / 2);
          final offsetLat2 = adjusted[j].latitude - offsetStep * math.cos(angle + math.pi / 2);
          final offsetLng2 = adjusted[j].longitude - offsetStep * math.sin(angle + math.pi / 2);
          
          adjusted[i] = LatLng(offsetLat1, offsetLng1);
          adjusted[j] = LatLng(offsetLat2, offsetLng2);
        }
      }
    }

    return adjusted;
  }

  IconData _getSafezoneIcon(String name) {
    final lowerName = name.toLowerCase();
    if (lowerName.contains('home')) return Icons.home;
    if (lowerName.contains('school') || lowerName.contains('university')) return Icons.school;
    if (lowerName.contains('park')) return Icons.park;
    return Icons.location_on;
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

  // Smooth animated map movement
  Future<void> _animateToLocation(LatLng target, double targetZoom, {Duration duration = const Duration(milliseconds: 800)}) async {
    if (!mounted) return;
    
    final startCenter = _mapController.center;
    final startZoom = _currentZoom;
    
    // Use AnimationController-like approach with Timer
    final tickDuration = const Duration(milliseconds: 16); // ~60fps
    final totalTicks = duration.inMilliseconds ~/ tickDuration.inMilliseconds;
    var currentTick = 0;
    
    Timer.periodic(tickDuration, (timer) {
      if (!mounted || currentTick >= totalTicks) {
        timer.cancel();
        // Ensure we end at exact target
        _mapController.move(target, targetZoom);
        setState(() {
          _currentZoom = targetZoom;
        });
        return;
      }
      
      final progress = currentTick / totalTicks;
      // Use easeInOutCubic curve for smooth animation
      final easedProgress = _easeInOutCubic(progress);
      
      // Interpolate position
      final currentLat = startCenter.latitude + (target.latitude - startCenter.latitude) * easedProgress;
      final currentLng = startCenter.longitude + (target.longitude - startCenter.longitude) * easedProgress;
      final currentZoom = startZoom + (targetZoom - startZoom) * easedProgress;
      
      _mapController.move(LatLng(currentLat, currentLng), currentZoom);
      setState(() {
        _currentZoom = currentZoom;
      });
      
      currentTick++;
    });
  }

  // Easing function for smooth animation
  double _easeInOutCubic(double t) {
    return t < 0.5
        ? 4 * t * t * t
        : 1 - math.pow(-2 * t + 2, 3) / 2;
  }

  void _zoomIn() {
    final targetZoom = _currentZoom + 1;
    _animateToLocation(_mapController.center, targetZoom, duration: const Duration(milliseconds: 300));
  }

  void _zoomOut() {
    final targetZoom = _currentZoom - 1;
    _animateToLocation(_mapController.center, targetZoom, duration: const Duration(milliseconds: 300));
  }

  void _centerOnStudent() {
    if (_currentStudentLocation != null) {
      _animateToLocation(_currentStudentLocation!, 15.0);
    }
  }

  void _centerOnUB() => _animateToLocation(_ubLocation, 15.0);
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
        // Zoom to maximum level (18.0) for very precise location
        _animateToLocation(myLocation, 18.0, duration: const Duration(milliseconds: 1000));
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
        title: Row(
          children: [
            Padding(
              padding: const EdgeInsets.only(right: 8.0),
              child: Image.asset(
                'asset/UBlogo.png',
                width: 50,
                height: 50,
                errorBuilder: (context, error, stackTrace) =>
                    const Icon(Icons.error_outline, color: Colors.white),
              ),
            ),
            Expanded(
              child: Container(
                alignment: Alignment.center,
                child: Text(
                  widget.isPickingMode ? 'Pick a Location' : 'Live Location Map',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                ),
              ),
            ),
            const SizedBox(width: 50),
          ],
        ),
        backgroundColor: primaryColor,
        foregroundColor: Colors.white,
        actions: [
          if (widget.isPickingMode)
            IconButton(
              icon: const Icon(Icons.check),
              onPressed: () => Navigator.pop(context, {
                'location': _pickedLocation,
                'radius': _previewRadius,
              }),
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
                    final isPredefined = index < _safezoneIsPredefined.length && _safezoneIsPredefined[index];
                    final zoneColor = isPredefined ? primaryColor : Colors.green;
                    return Polygon(
                      points: points,
                      color: zoneColor.withOpacity(0.2),
                      borderColor: zoneColor,
                      borderStrokeWidth: 2,
                      isFilled: true,
                    );
                  }),
                ),
              // Preview radius circle when picking location
              if (widget.isPickingMode && _pickedLocation != null)
                PolygonLayer(
                  polygons: [
                    Polygon(
                      points: _generateCirclePoints(_pickedLocation!, _previewRadius, 36),
                      color: Colors.blue.withOpacity(0.2),
                      borderColor: Colors.blue,
                      borderStrokeWidth: 3,
                      isFilled: true,
                    ),
                  ],
                ),
              if (!widget.isPickingMode)
                MarkerLayer(
                  markers: [
                    // Safezone markers
                    if (_showSafezones)
                      ...List.generate(_safezonePolygons.length, (index) {
                        final icon = index < _safezoneIcons.length 
                            ? _safezoneIcons[index] 
                            : Icons.location_on;
                        // Use adjusted position if available, otherwise use original
                        final markerPoint = index < _safezoneMarkerPositions.length
                            ? _safezoneMarkerPositions[index]
                            : _safezonePolygons[index];
                        final isPredefined = index < _safezoneIsPredefined.length && _safezoneIsPredefined[index];
                        final zoneColor = isPredefined ? primaryColor : Colors.green;
                        return Marker(
                          point: markerPoint,
                          width: 60,
                          height: 60,
                          child: Icon(
                            icon,
                            color: zoneColor,
                            size: 40,
                          ),
                        );
                      }),
                    // Student location marker
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
          if (widget.isPickingMode)
            Positioned(
              right: 16,
              top: 80,
              child: Column(
                children: [
                  _buildMapControlButton(
                    icon: Icons.my_location,
                    onPressed: _centerOnMyLocation,
                    tooltip: 'My Current Location',
                  ),
                  const SizedBox(height: 8),
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
                ],
              ),
            ),
          // Radius preview control in picking mode
          if (widget.isPickingMode)
            Positioned(
              bottom: 20,
              left: 16,
              right: 16,
              child: Card(
                elevation: 4,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Safezone Radius Preview',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                          Text(
                            '${_previewRadius.round()}m',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                              color: const Color(0xFF862334),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Slider(
                        value: _previewRadius,
                        min: 50,
                        max: 1000,
                        divisions: 19,
                        label: '${_previewRadius.round()}m',
                        onChanged: (value) {
                          setState(() {
                            _previewRadius = value;
                          });
                        },
                      ),
                      Text(
                        'Adjust the radius to see the safezone coverage area',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
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
                          // Build address with street name priority
                          List<String> addressParts = [];
                          if (placemark.street != null && placemark.street!.isNotEmpty) {
                            addressParts.add(placemark.street!);
                          }
                          if (placemark.name != null && placemark.name!.isNotEmpty && placemark.name != placemark.street) {
                            addressParts.add(placemark.name!);
                          }
                          if (placemark.subLocality != null && placemark.subLocality!.isNotEmpty) {
                            addressParts.add(placemark.subLocality!);
                          }
                          if (placemark.locality != null && placemark.locality!.isNotEmpty) {
                            addressParts.add(placemark.locality!);
                          }
                          final address = addressParts.isNotEmpty ? addressParts.join(', ') : "${placemark.name ?? ''}, ${placemark.locality ?? ''}";
                          return ListTile(
                            title: Text(address),
                            onTap: () {
                              _animateToLocation(LatLng(location.latitude, location.longitude), 15.0);
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
          // Map Legend
          if (!widget.isPickingMode)
            Positioned(
              bottom: 20,
              left: 16,
              child: Card(
                elevation: 4,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Map Legend',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                          color: Color(0xFF862334),
                        ),
                      ),
                      const SizedBox(height: 8),
                      _buildLegendItem(
                        icon: Icons.person_pin_circle,
                        color: _usingStudentGPS 
                            ? (_isGPSOffline ? Colors.orange : Colors.green) 
                            : Colors.red,
                        label: _usingStudentGPS 
                            ? (_isGPSOffline ? 'Student (Offline)' : 'Student (Online)')
                            : 'Student (No GPS)',
                      ),
                      const SizedBox(height: 6),
                      _buildLegendItem(
                        icon: Icons.location_on,
                        color: Colors.green,
                        label: 'Safezone',
                      ),
                      const SizedBox(height: 6),
                      _buildLegendItem(
                        icon: Icons.school,
                        color: const Color(0xFF862334),
                        label: 'Predefined Zone',
                      ),
                    ],
                  ),
                ),
              ),
            ),
          if (_isLoading)
            Container(color: Colors.black.withOpacity(0.5), child: const Center(child: CircularProgressIndicator())),
        ],
      ),
    );
  }

  Widget _buildLegendItem({
    required IconData icon,
    required Color color,
    required String label,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(width: 8),
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            color: Colors.black87,
          ),
        ),
      ],
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
