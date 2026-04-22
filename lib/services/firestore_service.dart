import 'package:cloud_firestore/cloud_firestore.dart';

class FirestoreService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // ========== STUDENTS COLLECTION ==========
  Future<void> saveStudentData({
    required String studentId,
    required String firstName,
    required String lastName,
    required int yearLevel,
    required String ubmail,
    required String password,
  }) async {
    try {
      await _firestore.collection('Students').doc(studentId).set({
        'StudentID': studentId,
        'FirstName': firstName,
        'LastName': lastName,
        'YearLevel': yearLevel,
        'UBmail': ubmail,
        'Password': password,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true)); // Use merge to avoid overwriting existing fields
      print('Successfully saved student data: $ubmail');
    } catch (e) {
      print('Error saving student data: $e');
      throw 'Failed to save student data: $e';
    }
  }

  Future<void> updateStudentName({
    required String studentId,
    required String firstName,
    required String lastName,
  }) async {
    try {
      await _firestore.collection('Students').doc(studentId).update({
        'FirstName': firstName,
        'LastName': lastName,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      print('Successfully updated student name for ID: $studentId');
    } catch (e) {
      print('Error updating student name: $e');
      throw 'Failed to update student name: $e';
    }
  }

  Future<void> updateStudentYearLevel({
    required String studentId,
    required int yearLevel,
  }) async {
    try {
      await _firestore.collection('Students').doc(studentId).update({
        'YearLevel': yearLevel,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      print('Successfully updated student year level for ID: $studentId');
    } catch (e) {
      print('Error updating student year level: $e');
      throw 'Failed to update student year level: $e';
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
    required String parentName,
    required String relationship,
  }) async {
    try {
      await _firestore.collection('Parents_Guardian').doc(parentGuardianId).set({
        'ParentGuardianID': parentGuardianId,
        'StudentID': studentId,
        'UBMail': ubmail,
        'Password': password,
        'parentName': parentName,
        'relationship': relationship,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      print('Successfully saved parent/guardian data: $ubmail');
    } catch (e) {
      print('Error saving parent/guardian data: $e');
      throw 'Failed to save parent/guardian data: $e';
    }
  }

  // ========== FCM TOKENS ==========
  Future<void> addParentFcmToken({
    required String parentGuardianId,
    required String token,
  }) async {
    try {
      await _firestore.collection('Parents_Guardian').doc(parentGuardianId).set({
        'fcmTokens': FieldValue.arrayUnion([token]),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      print('✅ [FCM] Saved token for parent: $parentGuardianId');
    } catch (e) {
      print('❌ [FCM] Error saving token: $e');
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
    int? iconCodePoint,
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
      zone['SafezoneID'] != safezoneId && // Exclude current zone if editing
          zone['Zonename'] == zoneName &&
          zone['Coordinates'] == coordinates
      );

      // Also check for duplicates by name only (prevent same name different location)
      final nameDuplicate = existingZones.any((zone) =>
      zone['SafezoneID'] != safezoneId && // Exclude current zone if editing
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
        if (iconCodePoint != null) 'IconCodePoint': iconCodePoint,
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
    String? currentSafezoneName,
  }) async {
    try {
      final updateData = {
        'isOutsideSafezone': isOutsideSafezone,
        'lastSafezoneCheck': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      };
      
      // Store current safezone name and entry time if student is inside a safezone
      if (isOutsideSafezone) {
        updateData['currentSafezoneName'] = FieldValue.delete();
        updateData['safezoneEntryTime'] = FieldValue.delete();
        // Store exit time when leaving safezone
        updateData['safezoneExitTime'] = FieldValue.serverTimestamp();
      } else if (currentSafezoneName != null) {
        updateData['currentSafezoneName'] = currentSafezoneName;
        updateData['safezoneExitTime'] = FieldValue.delete();
        // Only set entry time if it doesn't exist (first entry) or if safezone changed
        // We'll check this in the location monitor service
      }
      
      await _firestore.collection('Students').doc(studentId).update(updateData);
      print('Successfully updated student safe zone status: ${isOutsideSafezone ? "OUTSIDE" : "INSIDE"} ${currentSafezoneName != null ? "($currentSafezoneName)" : ""}');
    } catch (e) {
      print('Error updating student safe zone status: $e');
      throw 'Failed to update safe zone status: $e';
    }
  }

  // Update safezone entry time (called when student enters a safezone)
  Future<void> updateSafezoneEntryTime({
    required String studentId,
    required String safezoneName,
  }) async {
    try {
      await _firestore.collection('Students').doc(studentId).update({
        'safezoneEntryTime': FieldValue.serverTimestamp(),
      });
      print('Updated safezone entry time for: $safezoneName');
    } catch (e) {
      print('Error updating safezone entry time: $e');
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

  Future<void> saveAdminNotification({
    required String notificationId,
    required String studentId,
    required String message,
    required String type,
  }) async {
    try {
      await _firestore.collection('AdminNotification').doc(notificationId).set({
        'NotificationID': notificationId,
        'StudentID': studentId,
        'Message': message,
        'Type': type, // 'PredefinedZoneEntry', 'PredefinedZoneExit'
        'Timestamp': FieldValue.serverTimestamp(),
        'createdAt': FieldValue.serverTimestamp(),
        'isRead': false,
      });
      print('Successfully saved admin notification: $message');
    } catch (e) {
      print('Error saving admin notification: $e');
      // Don't throw, just log, as it's secondary
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
  
  Future<Map<String, dynamic>?> getLastNotification(String parentGuardianId) async {
    try {
      final query = await _firestore
          .collection('Notification')
          .where('ParentGuardianID', isEqualTo: parentGuardianId)
          .orderBy('Timestamp', descending: true)
          .limit(1)
          .get();

      return query.docs.isNotEmpty ? query.docs.first.data() : null;
    } catch (e) {
      print('Error getting last notification: $e');
      return null;
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

  Future<void> deleteNotification(String notificationId) async {
    try {
      await _firestore.collection('Notification').doc(notificationId).delete();
      print('Successfully deleted notification: $notificationId');
    } catch (e) {
      print('Error deleting notification: $e');
      throw 'Failed to delete notification: $e';
    }
  }

  Future<void> deleteAllNotifications(String parentGuardianId) async {
    try {
      final query = await _firestore
          .collection('Notification')
          .where('ParentGuardianID', isEqualTo: parentGuardianId)
          .get();

      final batch = _firestore.batch();
      for (var doc in query.docs) {
        batch.delete(doc.reference);
      }
      await batch.commit();
      print('Successfully deleted all notifications for parent: $parentGuardianId');
    } catch (e) {
      print('Error deleting all notifications: $e');
      throw 'Failed to delete all notifications: $e';
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

  // ========== PREDEFINED SAFEZONES ==========
  // Get predefined University of Batangas safezones
  List<Map<String, dynamic>> getPredefinedSafezones() {
    return [
      {
        'SafezoneID': 'UB_ELEMENTARY_DEPT',
        'Zonename': 'University of Batangas - Elementary Department',
        'Address': 'University of Batangas, Batangas City',
        'Coordinates': '13.754693277111798, 121.05816575323965',
        'Radius': 40.0,
        'isPredefined': true,
      },
      {
        'SafezoneID': 'UB_MAIN',
        'Zonename': 'University Of Batangas',
        'Address': 'University of Batangas, Batangas City',
        'Coordinates': '13.763555046394824, 121.05986555221901',
        'Radius': 100.0,
        'isPredefined': true,
      },
      {
        'SafezoneID': 'UB_SENIOR_HIGH',
        'Zonename': 'University of Batangas - Senior High School',
        'Address': 'University of Batangas, Batangas City',
        'Coordinates': '13.763585329372402, 121.05737214653715',
        'Radius': 50.0,
        'isPredefined': true,
      },
    ];
  }

  // Check if a safezone is predefined based on coordinates
  // Normalizes coordinates for comparison (handles spacing differences)
  bool isPredefinedSafezone(String coordinates) {
    final predefinedZones = getPredefinedSafezones();
    // Normalize coordinates by removing extra spaces
    final normalizedInput = coordinates.replaceAll(RegExp(r'\s+'), ' ').trim();
    return predefinedZones.any((zone) {
      final zoneCoords = (zone['Coordinates'] as String).replaceAll(RegExp(r'\s+'), ' ').trim();
      return zoneCoords == normalizedInput;
    });
  }

  // Get predefined safezone by coordinates
  Map<String, dynamic>? getPredefinedSafezoneByCoordinates(String coordinates) {
    final predefinedZones = getPredefinedSafezones();
    try {
      return predefinedZones.firstWhere(
        (zone) => zone['Coordinates'] == coordinates,
      );
    } catch (e) {
      return null;
    }
  }

  // ========== PREDEFINED ZONES COLLECTION ==========
  // Save predefined zone entry with only: SafezoneID, Radius, TimeIn, TimeOut, duration
  Future<void> savePredefinedZoneEntry({
    required String studentId,
    required String safezoneID,
    required double radius,
    required String timeIn,
    String? timeOut,
    String? duration,
  }) async {
    try {
      final today = DateTime.now();
      final dateLog = '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';
      final entryId = '${studentId}_${safezoneID}_$dateLog';
      
      // Check if entry already exists for today
      final existingEntry = await _firestore.collection('PredefinedZones').doc(entryId).get();
      
      // Only include the required fields
      final entryData = <String, dynamic>{
        'SafezoneID': safezoneID,
        'Radius': radius,
        'TimeIn': timeIn,
      };

      if (timeOut != null && timeOut.isNotEmpty) {
        entryData['TimeOut'] = timeOut;
      } else {
        entryData['TimeOut'] = '';
      }

      if (duration != null && duration.isNotEmpty) {
        entryData['duration'] = duration;
      } else {
        entryData['duration'] = '';
      }

      if (existingEntry.exists) {
        // Update existing entry
        await _firestore.collection('PredefinedZones').doc(entryId).update(entryData);
        print('✅ [PREDEFINED ZONES] Updated entry for student: $studentId, safezone: $safezoneID');
      } else {
        // Create new entry
        await _firestore.collection('PredefinedZones').doc(entryId).set(entryData);
        print('✅ [PREDEFINED ZONES] Created new entry for student: $studentId, safezone: $safezoneID');
      }
    } catch (e) {
      print('❌ [PREDEFINED ZONES] Error saving entry: $e');
      throw 'Failed to save predefined zone entry: $e';
    }
  }

  // Get predefined zone entries for a student
  Future<List<Map<String, dynamic>>> getPredefinedZoneEntries(String studentId) async {
    try {
      final query = await _firestore
          .collection('PredefinedZones')
          .where('StudentID', isEqualTo: studentId)
          .orderBy('DateLog', descending: true)
          .orderBy('TimeIn', descending: true)
          .limit(50)
          .get();

      return query.docs.map((doc) => {
        'EntryID': doc.id,
        ...doc.data(),
      }).toList();
    } catch (e) {
      print('❌ [PREDEFINED ZONES] Error getting entries: $e');
      // If orderBy fails, try without it
      try {
        final query = await _firestore
            .collection('PredefinedZones')
            .where('StudentID', isEqualTo: studentId)
            .get();
        
        final entries = query.docs.map((doc) => {
          'EntryID': doc.id,
          ...doc.data(),
        }).toList();
        
        // Sort manually by DateLog and TimeIn
        entries.sort((a, b) {
          final dateA = a['DateLog'] ?? '';
          final dateB = b['DateLog'] ?? '';
          if (dateA != dateB) return dateB.compareTo(dateA);
          final timeA = a['TimeIn'] ?? '';
          final timeB = b['TimeIn'] ?? '';
          return timeB.compareTo(timeA);
        });
        
        return entries;
      } catch (e2) {
        print('❌ [PREDEFINED ZONES] Error in fallback query: $e2');
        return [];
      }
    }
  }

  // Get today's predefined zone entry for a student and safezone
  Future<Map<String, dynamic>?> getTodayPredefinedZoneEntry({
    required String studentId,
    required String safezoneID,
  }) async {
    try {
      final today = DateTime.now();
      final dateLog = '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';
      final entryId = '${studentId}_${safezoneID}_$dateLog';
      
      final doc = await _firestore.collection('PredefinedZones').doc(entryId).get();
      if (doc.exists) {
        return {
          'EntryID': doc.id,
          ...doc.data()!,
        };
      }
      return null;
    } catch (e) {
      print('❌ [PREDEFINED ZONES] Error getting today\'s entry: $e');
      return null;
    }
  }

  // Test method to manually create a predefined zone entry (for testing)
  // This writes directly to Firestore to ensure the collection is created
  Future<void> testCreatePredefinedZoneEntry({
    required String studentId,
    required String safezoneID,
    required double radius,
    String? timeIn,
    String? timeOut,
    String? duration,
  }) async {
    try {
      print('🧪 [TEST] Starting test entry creation...');
      print('🧪 [TEST] StudentID: $studentId');
      print('🧪 [TEST] SafezoneID: $safezoneID');
      print('🧪 [TEST] Radius: $radius');
      
      final now = DateTime.now();
      final timeInValue = timeIn ?? '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
      final dateLog = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
      final entryId = '${studentId}_${safezoneID}_$dateLog';
      
      print('🧪 [TEST] EntryID: $entryId');
      print('🧪 [TEST] TimeIn: $timeInValue');
      print('🧪 [TEST] DateLog: $dateLog');
      
      // Write directly to Firestore with only required fields
      final entryData = <String, dynamic>{
        'SafezoneID': safezoneID,
        'Radius': radius,
        'TimeIn': timeInValue,
        'TimeOut': timeOut ?? '',
        'duration': duration ?? '',
      };
      
      print('🧪 [TEST] Writing to Firestore collection: PredefinedZones');
      print('🧪 [TEST] Document ID: $entryId');
      print('🧪 [TEST] Data: $entryData');
      
      await _firestore.collection('PredefinedZones').doc(entryId).set(entryData);
      
      print('✅ [TEST] Successfully wrote to Firestore!');
      print('✅ [TEST] Collection "PredefinedZones" should now be visible in Firebase Console');
      
      // Verify it was written
      final verifyDoc = await _firestore.collection('PredefinedZones').doc(entryId).get();
      if (verifyDoc.exists) {
        print('✅ [TEST] Verification: Document exists in Firestore');
        print('✅ [TEST] Document data: ${verifyDoc.data()}');
      } else {
        print('⚠️ [TEST] Warning: Document not found after write');
      }
      
    } catch (e, stackTrace) {
      print('❌ [TEST] Error creating test entry: $e');
      print('❌ [TEST] Stack trace: $stackTrace');
      throw 'Failed to create test entry: $e';
    }
  }

  // Calculate duration between time-in and time-out
  String calculateDuration(String timeIn, String timeOut) {
    try {
      // Parse time strings (format: HH:mm)
      final inParts = timeIn.split(':');
      final outParts = timeOut.split(':');
      
      if (inParts.length != 2 || outParts.length != 2) {
        return 'N/A';
      }
      
      final inHour = int.parse(inParts[0]);
      final inMinute = int.parse(inParts[1]);
      final outHour = int.parse(outParts[0]);
      final outMinute = int.parse(outParts[1]);
      
      final inTotalMinutes = inHour * 60 + inMinute;
      final outTotalMinutes = outHour * 60 + outMinute;
      
      int diffMinutes = outTotalMinutes - inTotalMinutes;
      
      // Handle case where time-out is next day
      if (diffMinutes < 0) {
        diffMinutes += 24 * 60; // Add 24 hours
      }
      
      final hours = diffMinutes ~/ 60;
      final minutes = diffMinutes % 60;
      
      if (hours > 0) {
        return '${hours}h ${minutes}m';
      } else {
        return '${minutes}m';
      }
    } catch (e) {
      print('❌ [PREDEFINED ZONES] Error calculating duration: $e');
      return 'N/A';
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

  // Save time in/out for predefined zones (for admin web app)
  Future<void> savePredefinedZoneTimelog({
    required String studentId,
    required String zoneName,
    required String coordinates,
    required String timeIn,
    String? timeOut,
    required String eventType, // 'TimeIn' or 'TimeOut'
  }) async {
    try {
      final today = DateTime.now();
      final dateLog = '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';
      final logId = '${studentId}_${coordinates.replaceAll(',', '_').replaceAll(' ', '')}_$dateLog';
      
      // Check if log already exists for today
      final existingLog = await _firestore.collection('Timelogs').doc(logId).get();
      
      if (existingLog.exists) {
        // Update existing log
        final updateData = <String, dynamic>{
          'updatedAt': FieldValue.serverTimestamp(),
        };
        
        if (eventType == 'TimeIn') {
          updateData['TimeIn'] = timeIn;
        } else if (eventType == 'TimeOut' && timeOut != null) {
          updateData['TimeOut'] = timeOut;
        }
        
        await _firestore.collection('Timelogs').doc(logId).update(updateData);
        print('Updated timelog for student: $studentId, zone: $zoneName, event: $eventType');
      } else {
        // Create new log
        await _firestore.collection('Timelogs').doc(logId).set({
          'LogID': logId,
          'StudentID': studentId,
          'TimeIn': eventType == 'TimeIn' ? timeIn : '',
          'TimeOut': eventType == 'TimeOut' && timeOut != null ? timeOut : '',
          'Datelog': dateLog,
          'Location': zoneName,
          'Coordinates': coordinates,
          'isPredefinedZone': true,
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
        print('Created new timelog for student: $studentId, zone: $zoneName, event: $eventType');
      }
    } catch (e) {
      print('Error saving predefined zone timelog: $e');
      // Don't throw, just log, as it's for admin tracking
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

  Future<void> updateParentRelationship(String parentGuardianId, String relationship) async {
    try {
      await _firestore.collection('Parents_Guardian').doc(parentGuardianId).update({
        'relationship': relationship,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      print('Successfully updated parent relationship: $relationship');
    } catch (e) {
      print('Error updating parent relationship: $e');
      throw 'Failed to update parent relationship: $e';
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
