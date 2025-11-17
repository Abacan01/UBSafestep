import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'firestore_service.dart';
import 'package:geocoding/geocoding.dart';

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
        return "${place.name}, ${place.street}, ${place.locality}, ${place.country}";
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
      final safezones = await _firestoreService.getSafezonesByParent(parentGuardianId);
      final locationName = await _getAddressFromCoordinates(studentLat, studentLng);

      if (safezones.isEmpty) {
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
        safezones: safezones,
      );

      final studentData = await _firestoreService.getStudentData(studentId);
      final wasInSafezone = studentData?['isInSafeZone'] ?? false;
      final isInSafezone = safezoneCheck != null;

      await _firestoreService.updateStudentSafezoneStatus(
        studentId: studentId,
        isOutsideSafezone: !isInSafezone,
      );

      if (wasInSafezone != isInSafezone) {
        if (isInSafezone) {
          final zoneName = safezoneCheck!['zone']['Zonename'];
          await _firestoreService.saveNotification(
            notificationId: _firestoreService.generateId(),
            parentGuardianId: parentGuardianId,
            studentId: studentId,
            message: 'Student entered safezone: $zoneName at $locationName',
            emergencySOS: false,
          );
        } else {
          await _firestoreService.saveNotification(
            notificationId: _firestoreService.generateId(),
            parentGuardianId: parentGuardianId,
            studentId: studentId,
            message: 'Student left safezone area at $locationName',
            emergencySOS: true,
          );
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
