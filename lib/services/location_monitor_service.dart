import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'firestore_service.dart';

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

          ('📍 Checking zone: ${zone['Zonename']}');
          ('   - Zone location: $zoneLat, $zoneLng');
          ('   - Student location: $studentLat, $studentLng');
          ('   - Distance: ${distance.toStringAsFixed(2)}m');
          ('   - Radius: ${radius}m');
          ('   - Is within radius: ${distance <= radius}');

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

  // Monitor and notify safezone status
  Future<void> checkAndNotifySafezoneStatus({
    required String studentId,
    required String parentGuardianId,
    required double studentLat,
    required double studentLng,
    required String locationName,
  }) async {
    try {
      // Get all safezones for this parent
      final safezones = await _firestoreService.getSafezonesByParent(parentGuardianId);

      if (safezones.isEmpty) {
        print('⚠️ No safezones configured for parent: $parentGuardianId');
        return;
      }

      // Check if student is in any safezone
      final safezoneCheck = await checkStudentInSafezone(
        studentId: studentId,
        studentLat: studentLat,
        studentLng: studentLng,
        safezones: safezones,
      );

      // Get current student data to check previous status
      final studentData = await _firestoreService.getStudentData(studentId);
      final wasInSafezone = studentData?['isInSafeZone'] ?? false;
      final isInSafezone = safezoneCheck != null;

      ('🔄 Safezone Status Check:');
      ('   - Student: $studentId');
      ('   - Was in safezone: $wasInSafezone');
      ('   - Is in safezone: $isInSafezone');
      ('   - Location: $locationName');

      // Update student status
      await _firestoreService.updateStudentSafezoneStatus(
        studentId: studentId,
        isOutsideSafezone: !isInSafezone,
      );

      // Send notifications only if status changed
      if (wasInSafezone != isInSafezone) {
        if (isInSafezone) {
          // Student entered safezone
          final zoneName = safezoneCheck!['zone']['Zonename'];
          await _firestoreService.saveNotification(
            notificationId: _firestoreService.generateId(),
            parentGuardianId: parentGuardianId,
            studentId: studentId,
            message: '✅ Student entered safezone: $zoneName at $locationName',
            emergencySOS: false,
          );
          ('📨 Sent safezone entry notification for: $zoneName');
        } else {
          // Student left safezone
          await _firestoreService.saveNotification(
            notificationId: _firestoreService.generateId(),
            parentGuardianId: parentGuardianId,
            studentId: studentId,
            message: '🚨 Student left safezone area at $locationName',
            emergencySOS: true, // Mark as emergency when leaving safezone
          );
          ('📨 Sent safezone exit notification');
        }
      } else {
        ('ℹ️ No status change - no notification sent');
      }

    } catch (e) {
      ('❌ Error in safezone monitoring: $e');
    }
  }

  // Get current device location
  Future<Position?> getCurrentLocation() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        ('❌ Location services are disabled');
        return null;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          ('❌ Location permissions are denied');
          return null;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        ('❌ Location permissions are permanently denied');
        return null;
      }

      return await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.best,
      );
    } catch (e) {
      ('❌ Error getting location: $e');
      return null;
    }
  }
}