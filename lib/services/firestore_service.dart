import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class FirestoreService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // Get current user ID
  String get _currentUserId => _auth.currentUser?.uid ?? '';

  // ========== STUDENTS COLLECTION ==========
  Future<void> saveStudentData({
    required String studentId,
    required String firstName,
    required String lastName,
    required String course,
    required int yearLevel,
    required String ubmail,
    required String password,
  }) async {
    try {
      await _firestore.collection('Students').doc(studentId).set({
        'StudentID': studentId,
        'FirstName': firstName,
        'LastName': lastName,
        'Course': course,
        'YearLevel': yearLevel,
        'UBmail': ubmail,
        'Password': password,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      print('Successfully saved student data: $ubmail');
    } catch (e) {
      print('Error saving student data: $e');
      throw 'Failed to save student data: $e';
    }
  }

  Future<Map<String, dynamic>?> getStudentData(String studentId) async {
    try {
      final doc = await _firestore.collection('Students').doc(studentId).get();
      return doc.exists ? doc.data() : null;
    } catch (e) {
      print('Error getting student data: $e');
      return null;
    }
  }

  Future<Map<String, dynamic>?> getStudentByUBmail(String ubmail) async {
    try {
      final query = await _firestore
          .collection('Students')
          .where('UBmail', isEqualTo: ubmail)
          .limit(1)
          .get();

      return query.docs.isNotEmpty ? query.docs.first.data() : null;
    } catch (e) {
      print('Error getting student by UBmail: $e');
      return null;
    }
  }

  // ========== PARENTS/GUARDIAN COLLECTION ==========
  Future<void> saveParentGuardian({
    required String parentGuardianId,
    required String studentId,
    required String ubmail,
    required String password,
  }) async {
    try {
      await _firestore.collection('Parents_Guardian').doc(parentGuardianId).set({
        'ParentGuardianID': parentGuardianId,
        'StudentID': studentId,
        'UBMail': ubmail,
        'Password': password,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      print('Successfully saved parent/guardian data: $ubmail');
    } catch (e) {
      print('Error saving parent/guardian data: $e');
      throw 'Failed to save parent/guardian data: $e';
    }
  }

  Future<Map<String, dynamic>?> getParentGuardian(String parentGuardianId) async {
    try {
      final doc = await _firestore.collection('Parents_Guardian').doc(parentGuardianId).get();
      return doc.exists ? doc.data() : null;
    } catch (e) {
      print('Error getting parent/guardian data: $e');
      return null;
    }
  }

  Future<Map<String, dynamic>?> getParentGuardianByStudent(String studentId) async {
    try {
      final query = await _firestore
          .collection('Parents_Guardian')
          .where('StudentID', isEqualTo: studentId)
          .limit(1)
          .get();

      return query.docs.isNotEmpty ? query.docs.first.data() : null;
    } catch (e) {
      print('Error getting parent/guardian data: $e');
      return null;
    }
  }

  Future<Map<String, dynamic>?> getParentGuardianByUBmail(String ubmail) async {
    try {
      final query = await _firestore
          .collection('Parents_Guardian')
          .where('UBMail', isEqualTo: ubmail)
          .limit(1)
          .get();

      return query.docs.isNotEmpty ? query.docs.first.data() : null;
    } catch (e) {
      print('Error getting parent/guardian by UBmail: $e');
      return null;
    }
  }

  // ========== SAFEZONE COLLECTION ==========
  Future<void> saveSafezone({
    required String safezoneId,
    required String parentGuardianId,
    required String zoneName,
    required String address,
    required String coordinates,
    required double radius,
  }) async {
    try {
      print('💾 [FIRESTORE] Saving safezone with details:');
      print('   - SafezoneID: $safezoneId');
      print('   - ParentGuardianID: $parentGuardianId');
      print('   - Zonename: $zoneName');
      print('   - Address: $address');
      print('   - Coordinates: $coordinates');
      print('   - Radius: $radius');

      // Enhanced duplicate check - check name OR coordinates
      final existingZones = await getSafezonesByParent(parentGuardianId);

      // Check for duplicates by name AND coordinates (exact duplicate)
      final exactDuplicate = existingZones.any((zone) =>
      zone['Zonename'] == zoneName &&
          zone['Coordinates'] == coordinates
      );

      // Also check for duplicates by name only (prevent same name different location)
      final nameDuplicate = existingZones.any((zone) =>
      zone['Zonename'] == zoneName
      );

      if (exactDuplicate) {
        print('[SAFEZONES] Exact duplicate zone found: $zoneName at $coordinates');
        throw 'A safezone with the same name and location already exists!';
      }

      if (nameDuplicate) {
        print('[SAFEZONES] Zone with same name already exists: $zoneName');
        throw 'A safezone with the name "$zoneName" already exists! Please use a different name.';
      }

      // Create the document data with consistent field names
      final safezoneData = {
        'SafezoneID': safezoneId,
        'ParentGuardianID': parentGuardianId,
        'Zonename': zoneName,
        'Address': address,
        'Coordinates': coordinates,
        'Radius': radius,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      };

      print('📝 [FIRESTORE] Saving data: $safezoneData');

      await _firestore.collection('Safezone').doc(safezoneId).set(safezoneData);

      // Verify the save
      final savedDoc = await _firestore.collection('Safezone').doc(safezoneId).get();
      if (savedDoc.exists) {
        print('✅ [FIRESTORE] Safezone saved successfully!');
        print('✅ [FIRESTORE] Verified data: ${savedDoc.data()}');
      } else {
        print('❌ [FIRESTORE] Failed to verify safezone save!');
      }

    } catch (e) {
      print('❌ [FIRESTORE] Error saving safezone: $e');
      print('❌ [FIRESTORE] Stack trace: ${e.toString()}');
      throw e;
    }
  }

  // Enhanced method to check for specific duplicates
  Future<bool> checkDuplicateSafezone({
    required String parentGuardianId,
    required String zoneName,
    required String coordinates,
  }) async {
    try {
      final existingZones = await getSafezonesByParent(parentGuardianId);

      final exactDuplicate = existingZones.any((zone) =>
      zone['Zonename'] == zoneName &&
          zone['Coordinates'] == coordinates
      );

      final nameDuplicate = existingZones.any((zone) =>
      zone['Zonename'] == zoneName
      );

      return exactDuplicate || nameDuplicate;
    } catch (e) {
      print('❌ [SAFEZONES] Error checking duplicate: $e');
      return false;
    }
  }

  Future<List<Map<String, dynamic>>> getSafezonesByParent(String parentGuardianId) async {
    try {
      print('🔍 [FIRESTORE] Fetching safezones for parent: $parentGuardianId');

      // SIMPLE QUERY - Remove orderBy to use your existing index
      final query = await _firestore
          .collection('Safezone')
          .where('ParentGuardianID', isEqualTo: parentGuardianId)
          .get(); // Removed: .orderBy('createdAt', descending: true)

      print('✅ [FIRESTORE] Query results: ${query.docs.length} documents found');

      final safezones = query.docs.map((doc) {
        final data = doc.data();
        print('📍 [FIRESTORE] Safezone found:');
        print('   - ID: ${doc.id}');
        print('   - Name: ${data['Zonename']}');
        print('   - ParentID: ${data['ParentGuardianID']}');
        print('   - Full Data: $data');
        return {
          'SafezoneID': doc.id, // Make sure to include the document ID
          ...data,
        };
      }).toList();

      print('🎯 [FIRESTORE] Total safezones for parent $parentGuardianId: ${safezones.length}');
      return safezones;
    } catch (e) {
      print('❌ [FIRESTORE] Error getting safezones: $e');
      print('❌ [FIRESTORE] Error details: ${e.toString()}');

      // Fallback: Get all and filter manually
      try {
        final allDocs = await _firestore.collection('Safezone').get();
        final filteredZones = allDocs.docs
            .where((doc) => doc.data()['ParentGuardianID'] == parentGuardianId)
            .map((doc) => {
          'SafezoneID': doc.id,
          ...doc.data(),
        })
            .toList();
        print('🔄 [FIRESTORE] Using fallback method, found: ${filteredZones.length} zones');
        return filteredZones;
      } catch (e2) {
        return [];
      }
    }
  }

  Future<void> deleteSafezone(String safezoneId) async {
    try {
      await _firestore.collection('Safezone').doc(safezoneId).delete();
      print('✅ [FIRESTORE] Successfully deleted safezone: $safezoneId');
    } catch (e) {
      print('❌ [FIRESTORE] Error deleting safezone: $e');
      throw 'Failed to delete safezone: $e';
    }
  }

  // ========== TEST METHOD ==========
  Future<void> testSafezoneFlow(String parentGuardianId) async {
    try {
      print('🧪 [TEST] Starting safezone flow test...');

      // Test data
      final testSafezoneId = DateTime.now().millisecondsSinceEpoch.toString();
      final testData = {
        'SafezoneID': testSafezoneId,
        'ParentGuardianID': parentGuardianId,
        'Zonename': 'Test Zone',
        'Address': 'Test Address',
        'Coordinates': '13.7565,121.0583',
        'Radius': 150.0,
        'createdAt': FieldValue.serverTimestamp(),
      };

      // Save test data
      await _firestore.collection('Safezone').doc(testSafezoneId).set(testData);
      print('✅ [TEST] Test safezone saved');

      // Immediately retrieve it
      final results = await getSafezonesByParent(parentGuardianId);
      print('✅ [TEST] Retrieved ${results.length} safezones after save');

    } catch (e) {
      print('❌ [TEST] Error in test flow: $e');
    }
  }

  // ========== LOCATION TRACKING ==========
  Future<void> saveStudentLocation({
    required String studentId,
    required double latitude,
    required double longitude,
    required String locationName,
    required String timestamp,
  }) async {
    try {
      // Save to location history subcollection
      await _firestore
          .collection('Students')
          .doc(studentId)
          .collection('locationHistory')
          .add({
        'latitude': latitude,
        'longitude': longitude,
        'locationName': locationName,
        'timestamp': timestamp,
        'createdAt': FieldValue.serverTimestamp(),
      });

      // Update current location in student document
      await _firestore.collection('Students').doc(studentId).update({
        'lastLocation': locationName,
        'lastLatitude': latitude,
        'lastLongitude': longitude,
        'lastLocationUpdate': timestamp,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      print('Successfully saved student location: $locationName');
    } catch (e) {
      print('Error saving student location: $e');
      throw 'Failed to save student location: $e';
    }
  }

  Future<List<Map<String, dynamic>>> getStudentLocationHistory(String studentId) async {
    try {
      final query = await _firestore
          .collection('Students')
          .doc(studentId)
          .collection('locationHistory')
          .orderBy('createdAt', descending: true)
          .limit(50)
          .get();

      return query.docs.map((doc) {
        final data = doc.data();
        return {
          'id': doc.id,
          ...data,
        };
      }).toList();
    } catch (e) {
      print('Error getting location history: $e');
      return [];
    }
  }

  // Update student safe zone status
  Future<void> updateStudentSafezoneStatus({
    required String studentId,
    required bool isOutsideSafezone,
  }) async {
    try {
      await _firestore.collection('Students').doc(studentId).update({
        'isOutsideSafezone': isOutsideSafezone,
        'lastSafezoneCheck': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      print('Successfully updated student safe zone status: ${isOutsideSafezone ? "OUTSIDE" : "INSIDE"}');
    } catch (e) {
      print('Error updating student safe zone status: $e');
      throw 'Failed to update safe zone status: $e';
    }
  }

  // ========== NOTIFICATION COLLECTION ==========
  Future<void> saveNotification({
    required String notificationId,
    required String parentGuardianId,
    required String studentId,
    required String message,
    required bool emergencySOS,
  }) async {
    try {
      await _firestore.collection('Notification').doc(notificationId).set({
        'NotificationID': notificationId,
        'ParentGuardianID': parentGuardianId,
        'StudentID': studentId,
        'Message': message,
        'Timestamp': FieldValue.serverTimestamp(),
        'EmergencySOS': emergencySOS,
        'createdAt': FieldValue.serverTimestamp(),
        'isRead': false,
      });
      print('Successfully saved notification: $message');
    } catch (e) {
      print('Error saving notification: $e');
      throw 'Failed to save notification: $e';
    }
  }

  Future<List<Map<String, dynamic>>> getParentNotifications(String parentGuardianId) async {
    try {
      final query = await _firestore
          .collection('Notification')
          .where('ParentGuardianID', isEqualTo: parentGuardianId)
          .orderBy('Timestamp', descending: true)
          .get();

      return query.docs.map((doc) => doc.data()).toList();
    } catch (e) {
      print('Error getting notifications: $e');
      return [];
    }
  }

  Future<void> markNotificationAsRead(String notificationId) async {
    try {
      await _firestore.collection('Notification').doc(notificationId).update({
        'isRead': true,
        'readAt': FieldValue.serverTimestamp(),
      });
      print('Successfully marked notification as read: $notificationId');
    } catch (e) {
      print('Error marking notification as read: $e');
    }
  }

  // ========== DEVICE COLLECTION ==========
  Future<void> saveDevice({
    required String deviceId,
    required String deviceName,
    required String status,
  }) async {
    try {
      await _firestore.collection('Device').doc(deviceId).set({
        'DeviceID': deviceId,
        'DeviceName': deviceName,
        'Status': status,
        'Lastsync': FieldValue.serverTimestamp(),
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      print('Successfully saved device: $deviceName');
    } catch (e) {
      print('Error saving device: $e');
      throw 'Failed to save device: $e';
    }
  }

  Future<void> updateDeviceSync(String deviceId) async {
    try {
      await _firestore.collection('Device').doc(deviceId).update({
        'Lastsync': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      print('Successfully updated device sync: $deviceId');
    } catch (e) {
      print('Error updating device sync: $e');
    }
  }

  // ========== TIMELOGS COLLECTION ==========
  Future<void> saveTimelog({
    required String logId,
    required String studentId,
    required String timeIn,
    required String timeOut,
    required String datelog,
    required String location,
  }) async {
    try {
      await _firestore.collection('Timelogs').doc(logId).set({
        'LogID': logId,
        'StudentID': studentId,
        'TimeIn': timeIn,
        'TimeOut': timeOut,
        'Datelog': datelog,
        'Location': location,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      print('Successfully saved timelog for student: $studentId');
    } catch (e) {
      print('Error saving timelog: $e');
      throw 'Failed to save timelog: $e';
    }
  }

  Future<List<Map<String, dynamic>>> getStudentTimelogs(String studentId) async {
    try {
      final query = await _firestore
          .collection('Timelogs')
          .where('StudentID', isEqualTo: studentId)
          .orderBy('Datelog', descending: true)
          .get();

      return query.docs.map((doc) => doc.data()).toList();
    } catch (e) {
      print('Error getting timelogs: $e');
      return [];
    }
  }

  // ========== REPORT COLLECTION ==========
  Future<void> saveReport({
    required String reportId,
    required String studentId,
    required String timeIn,
    required String timeOut,
  }) async {
    try {
      await _firestore.collection('Report').doc(reportId).set({
        'ReportID': reportId,
        'StudentID': studentId,
        'TimeIn': timeIn,
        'TimeOut': timeOut,
        'Timestamp': FieldValue.serverTimestamp(),
        'createdAt': FieldValue.serverTimestamp(),
      });
      print('Successfully saved report for student: $studentId');
    } catch (e) {
      print('Error saving report: $e');
      throw 'Failed to save report: $e';
    }
  }

  // ========== Account Settings ==========
  Future<void> updateParentName(String parentGuardianId, String newName) async {
    try {
      await _firestore.collection('Parents_Guardian').doc(parentGuardianId).update({
        'parentName': newName,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      print('Successfully updated parent name: $newName');
    } catch (e) {
      print('Error updating parent name: $e');
      throw 'Failed to update parent name: $e';
    }
  }

  // ========== ADMIN COLLECTION ==========
  Future<void> saveAdmin({
    required String userId,
    required String username,
    required String password,
    required String role,
  }) async {
    try {
      await _firestore.collection('Admin').doc(userId).set({
        'UserID': userId,
        'Username': username,
        'Password': password,
        'Role': role,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      print('Successfully saved admin: $username');
    } catch (e) {
      print('Error saving admin: $e');
      throw 'Failed to save admin: $e';
    }
  }

  Future<Map<String, dynamic>?> verifyAdmin(String username, String password) async {
    try {
      final query = await _firestore
          .collection('Admin')
          .where('Username', isEqualTo: username)
          .where('Password', isEqualTo: password)
          .limit(1)
          .get();

      return query.docs.isNotEmpty ? query.docs.first.data() : null;
    } catch (e) {
      print('Error verifying admin: $e');
      return null;
    }
  }

  // ========== HELPER METHODS ==========
  String generateId() {
    return DateTime.now().millisecondsSinceEpoch.toString();
  }

  Future<bool> checkStudentExists(String studentId) async {
    try {
      final doc = await _firestore.collection('Students').doc(studentId).get();
      return doc.exists;
    } catch (e) {
      print('Error checking student existence: $e');
      return false;
    }
  }

  Future<void> sendEmergencySOS({
    required String studentId,
    required String parentGuardianId,
    required String message,
    required String location,
  }) async {
    try {
      final notificationId = generateId();
      await saveNotification(
        notificationId: notificationId,
        parentGuardianId: parentGuardianId,
        studentId: studentId,
        message: 'EMERGENCY SOS: $message at $location',
        emergencySOS: true,
      );
      print('Emergency SOS sent successfully');
    } catch (e) {
      print('Error sending emergency SOS: $e');
      throw 'Failed to send emergency SOS: $e';
    }
  }
}