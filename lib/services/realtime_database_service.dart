import 'package:firebase_database/firebase_database.dart';

class RealtimeDatabaseService {
  final DatabaseReference _database = FirebaseDatabase.instance.ref();

  // Get real-time GPS data from Arduino (Realtime Database)
  Stream<Map<String, dynamic>> getArduinoGPSData(String deviceId) {
    final ref = _database.child('devices/$deviceId');

    return ref.onValue.map((event) {
      final data = event.snapshot.value;
      print('📡 [RTDB] Raw data received: $data');

      if (data != null && data is Map) {
        final gpsData = {
          'latitude': _parseDouble(data['latitude']),
          'longitude': _parseDouble(data['longitude']),
          'timestamp': data['timestamp'] ?? DateTime.now().millisecondsSinceEpoch,
          'satellites': data['satellites'] ?? 0,
          'speed': _parseDouble(data['speed']),
          'altitude': _parseDouble(data['altitude']),
          'hdop': _parseDouble(data['hdop']),
          'connection_type': data['connection_type'] ?? 'unknown',
          'device_id': data['device_id'] ?? deviceId,
        };

        print('📍 [RTDB] Parsed GPS data: $gpsData');
        return gpsData;
      }

      print('❌ [RTDB] No data or invalid format');
      return {};
    });
  }

  double _parseDouble(dynamic value) {
    if (value == null) return 0.0;
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? 0.0;
    return 0.0;
  }

  // Send data to Realtime Database (if needed)
  Future<void> sendData(String path, Map<String, dynamic> data) async {
    try {
      await _database.child(path).set(data);
      print('✅ [RTDB] Data sent successfully to $path');
    } catch (e) {
      print('❌ [RTDB] Error sending data: $e');
    }
  }

  // Check if device exists in Realtime Database
  Future<bool> checkDeviceExists(String deviceId) async {
    try {
      final snapshot = await _database.child('devices/$deviceId').once();
      return snapshot.snapshot.value != null;
    } catch (e) {
      print('❌ [RTDB] Error checking device: $e');
      return false;
    }
  }
}