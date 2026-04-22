import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'firestore_service.dart';
import 'package:geocoding/geocoding.dart';
import 'push_notifications_service.dart';

class LocationMonitorService {
  final FirestoreService _firestoreService = FirestoreService();
  final Distance _distanceCalculator = Distance();

  // Calculate distance between two coordinates in meters
  double calculateDistance(LatLng point1, LatLng point2) {
    return _distanceCalculator.as(LengthUnit.Meter, point1, point2);
  }

  // Check if student is within any safezone
  Future<Map<String, dynamic>?> checkStudentInSafezone({
    required String studentId,
    required double studentLat,
    required double studentLng,
    required List<Map<String, dynamic>> safezones,
  }) async {
    final studentLocation = LatLng(studentLat, studentLng);

    for (final zone in safezones) {
      final coordinates = zone['Coordinates'] as String;
      final radius = (zone['Radius'] as num?)?.toDouble() ?? 200.0; // Default to 200m if not set

      // Parse coordinates
      final parts = coordinates.split(',');
      if (parts.length == 2) {
        final zoneLat = double.tryParse(parts[0].trim());
        final zoneLng = double.tryParse(parts[1].trim());

        if (zoneLat != null && zoneLng != null) {
          final zoneLocation = LatLng(zoneLat, zoneLng);
          final distance = calculateDistance(studentLocation, zoneLocation);

          if (distance <= radius) {
            return {
              'zone': zone,
              'distance': distance,
              'isWithinRadius': true,
            };
          }
        }
      }
    }

    return null;
  }

  Future<String> _getAddressFromCoordinates(double lat, double lng) async {
    try {
      final placemarks = await placemarkFromCoordinates(lat, lng);
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
        
        return addressParts.isNotEmpty ? addressParts.join(', ') : 'Unknown Location';
      }
      return 'Unknown Location';
    } catch (e) {
      print('Error getting address from coordinates: $e');
      return 'Unknown Location';
    }
  }

  // Monitor and notify safezone status
  Future<void> checkAndNotifySafezoneStatus({
    required String studentId,
    required String parentGuardianId,
    required double studentLat,
    required double studentLng,
  }) async {
    try {
      final parentSafezones = await _firestoreService.getSafezonesByParent(parentGuardianId);
      final predefinedSafezones = _firestoreService.getPredefinedSafezones();
      
      // Combine parent safezones with predefined safezones
      final allSafezones = [...parentSafezones, ...predefinedSafezones];
      
      final locationName = await _getAddressFromCoordinates(studentLat, studentLng);

      if (allSafezones.isEmpty) {
        print('No safezones configured for parent: $parentGuardianId. Student is considered outside safezone.');
        await _firestoreService.updateStudentSafezoneStatus(
          studentId: studentId,
          isOutsideSafezone: true,
        );
        return;
      }

      final safezoneCheck = await checkStudentInSafezone(
        studentId: studentId,
        studentLat: studentLat,
        studentLng: studentLng,
        safezones: allSafezones,
      );

      final studentData = await _firestoreService.getStudentData(studentId);
      
      // CORRECTED LOGIC: Check 'isOutsideSafezone' field correctly
      final bool wasOutsideSafezone = studentData?['isOutsideSafezone'] ?? true;
      final bool wasInSafezone = !wasOutsideSafezone;
      
      final bool isInSafezone = safezoneCheck != null;
      final String? currentSafezoneName = isInSafezone 
          ? safezoneCheck['zone']['Zonename'] as String?
          : null;

      // Check if this is a new safezone entry (student just entered or changed safezones)
      final String? previousSafezoneName = studentData?['currentSafezoneName'] as String?;
      
      await _firestoreService.updateStudentSafezoneStatus(
        studentId: studentId,
        isOutsideSafezone: !isInSafezone,
        currentSafezoneName: currentSafezoneName,
      );

      // Update entry time only if student entered a new safezone (not already in it)
      if (isInSafezone && 
          currentSafezoneName != null && 
          previousSafezoneName != currentSafezoneName) {
        await _firestoreService.updateSafezoneEntryTime(
          studentId: studentId,
          safezoneName: currentSafezoneName,
        );
      }

      // Check if this is a predefined safezone
      final zoneCoordinates = safezoneCheck?['zone']?['Coordinates'] as String?;
      final isPredefinedZone = zoneCoordinates != null && 
          _firestoreService.isPredefinedSafezone(zoneCoordinates);
      
      // Debug logging
      if (zoneCoordinates != null) {
        print('🔍 [PREDEFINED ZONES] Checking coordinates: $zoneCoordinates');
        print('🔍 [PREDEFINED ZONES] Is predefined: $isPredefinedZone');
      }
      
      if (wasInSafezone != isInSafezone) {
        // STATUS CHANGE: ENTERED or LEFT
        if (isInSafezone) {
          final zoneName = safezoneCheck['zone']['Zonename'];
          print('🟢 [SAFEZONE] Student ENTERED safezone: $zoneName');
          print('📍 [SAFEZONE] Location: $locationName');
          print('👨‍👩‍👧 [SAFEZONE] Sending notification to parent: $parentGuardianId');
          
          final notificationMessage = 'Student entered safezone: $zoneName at $locationName';
          
          // Show local notification immediately in notification tray
          await PushNotificationsService.showSafezoneNotificationStatic(
            title: '🟢 Safezone Entry',
            body: notificationMessage,
            isEntry: true,
          );
          
          await _firestoreService.saveNotification(
            notificationId: _firestoreService.generateId(),
            parentGuardianId: parentGuardianId,
            studentId: studentId,
            message: notificationMessage,
            emergencySOS: false,
          );
          
          print('✅ [SAFEZONE] Entry notification saved to Firestore');
          print('✅ [SAFEZONE] Local notification displayed in notification tray');
          print('⏳ [SAFEZONE] Cloud Function should also send FCM push notification...');
          
          // If predefined zone, save time in to PredefinedZones collection
          if (isPredefinedZone) {
            print('✅ [PREDEFINED ZONES] Student entered predefined zone: $zoneName');
            final now = DateTime.now();
            final timeIn = '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
            
            // Get SafezoneID and Radius from the predefined zone
            // zoneCoordinates is guaranteed to be non-null when isPredefinedZone is true
            final predefinedZoneInfo = _firestoreService.getPredefinedSafezoneByCoordinates(zoneCoordinates);
            if (predefinedZoneInfo != null) {
              final safezoneID = predefinedZoneInfo['SafezoneID'] as String;
              final radius = (predefinedZoneInfo['Radius'] as num).toDouble();
              
              try {
                // Save to new PredefinedZones collection with only required fields
                await _firestoreService.savePredefinedZoneEntry(
                  studentId: studentId,
                  safezoneID: safezoneID,
                  radius: radius,
                  timeIn: timeIn,
                  timeOut: null,
                  duration: null,
                );
                print('✅ [PREDEFINED ZONES] Successfully saved to PredefinedZones collection');
              } catch (e) {
                print('❌ [PREDEFINED ZONES] Error saving to PredefinedZones: $e');
              }
            }
            
            // Also save to Timelogs for backward compatibility
            await _firestoreService.savePredefinedZoneTimelog(
              studentId: studentId,
              zoneName: zoneName,
              coordinates: zoneCoordinates,
              timeIn: timeIn,
              eventType: 'TimeIn',
            );
          }
        } else {
          print('🔴 [SAFEZONE] Student LEFT safezone area');
          print('📍 [SAFEZONE] Current location: $locationName');
          print('👨‍👩‍👧 [SAFEZONE] Sending notification to parent: $parentGuardianId');
          
          final notificationMessage = 'Student left safezone area at $locationName';
          
          // Show local notification immediately in notification tray
          await PushNotificationsService.showSafezoneNotificationStatic(
            title: '🔴 Safezone Exit',
            body: notificationMessage,
            isEntry: false,
          );
          
          await _firestoreService.saveNotification(
            notificationId: _firestoreService.generateId(),
            parentGuardianId: parentGuardianId,
            studentId: studentId,
            message: notificationMessage,
            emergencySOS: false, // Not an emergency - only SOS button triggers emergency
          );
          
          print('✅ [SAFEZONE] Exit notification saved to Firestore');
          print('✅ [SAFEZONE] Local notification displayed in notification tray');
          print('⏳ [SAFEZONE] Cloud Function should also send FCM push notification...');
          
          // If predefined zone, save time out to PredefinedZones collection
          // Check if the previous zone was a predefined zone
          final previousZoneName = studentData?['currentSafezoneName'] as String?;
          if (previousZoneName != null) {
            // Find which predefined zone the student was in
            for (final predefinedZone in predefinedSafezones) {
              final predefinedCoords = predefinedZone['Coordinates'] as String;
              final predefinedZoneName = predefinedZone['Zonename'] as String;
              // Check if the previous zone name matches this predefined zone
              if (previousZoneName.contains(predefinedZoneName) ||
                  predefinedZoneName == previousZoneName) {
                final safezoneID = predefinedZone['SafezoneID'] as String;
                final radius = (predefinedZone['Radius'] as num).toDouble();
                final now = DateTime.now();
                final timeOut = '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
                
                // Get today's entry to calculate duration
                final todayEntry = await _firestoreService.getTodayPredefinedZoneEntry(
                  studentId: studentId,
                  safezoneID: safezoneID,
                );
                
                String? duration;
                if (todayEntry != null && todayEntry['TimeIn'] != null) {
                  duration = _firestoreService.calculateDuration(
                    todayEntry['TimeIn'],
                    timeOut,
                  );
                }
                
                // Save to new PredefinedZones collection with duration
                await _firestoreService.savePredefinedZoneEntry(
                  studentId: studentId,
                  safezoneID: safezoneID,
                  radius: radius,
                  timeIn: todayEntry?['TimeIn'] ?? '',
                  timeOut: timeOut,
                  duration: duration,
                );
                
                // Also save to Timelogs for backward compatibility
                await _firestoreService.savePredefinedZoneTimelog(
                  studentId: studentId,
                  zoneName: predefinedZoneName,
                  coordinates: predefinedCoords,
                  timeIn: todayEntry?['TimeIn'] ?? '',
                  timeOut: timeOut,
                  eventType: 'TimeOut',
                );
                break;
              }
            }
          }
        }
      } else if (!isInSafezone) {
        // CONTINUOUSLY OUTSIDE: Check for significant movement to notify
        // To avoid spamming, check the last notification
        final lastNotification = await _firestoreService.getLastNotification(parentGuardianId);
        
        if (lastNotification != null) {
          final lastMessage = lastNotification['Message'] as String;
          
          // If the last message was also about being outside or movement, check if location changed
          if (lastMessage.contains('left safezone') || lastMessage.contains('outside safezone')) {
            // We don't want to spam if the location description hasn't changed roughly
            if (!lastMessage.contains(locationName)) {
               await _firestoreService.saveNotification(
                notificationId: _firestoreService.generateId(),
                parentGuardianId: parentGuardianId,
                studentId: studentId,
                message: 'Student is outside safezone at $locationName',
                emergencySOS: false, // Not an emergency, just an update
              );
            }
          }
        }
      }
    } catch (e) {
      print('Error in safezone monitoring: $e');
    }
  }

  // Get current device location
  Future<Position?> getCurrentLocation() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        return null;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          return null;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        return null;
      }

      return await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.best,
      );
    } catch (e) {
      print('Error getting location: $e');
      return null;
    }
  }
}
