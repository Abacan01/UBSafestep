import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'map_screen.dart';
import 'dart:async';
import '../services/firestore_service.dart';

class DashboardScreen extends StatefulWidget {
  final Map<String, dynamic> userData;
  final String userId;

  const DashboardScreen({
    Key? key,
    required this.userData,
    required this.userId,
  }) : super(key: key);

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final FirestoreService _firestoreService = FirestoreService();
  Map<String, dynamic>? _studentData;
  bool _isLoading = true;
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _studentData = widget.userData;
    _isLoading = false;
    _loadStudentData();
    _refreshTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      _loadStudentData(isRefresh: true);
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadStudentData({bool isRefresh = false}) async {
    if (!mounted) return;

    if (!isRefresh) {
      setState(() {
        _isLoading = true;
      });
    }

    try {
      final studentData = await _firestoreService.getStudentData(widget.userData['StudentID']);
      if (mounted && studentData != null) {
        final safezones = await _firestoreService.getSafezonesByParent(widget.userId);
        studentData['safezonesExist'] = safezones.isNotEmpty;
        setState(() {
          _studentData = studentData;
        });
      }
    } catch (e) {
      print('Error loading student data: $e');
    } finally {
      if (mounted && !isRefresh) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  bool get _isInSafeZone {
    if (_studentData?['safezonesExist'] == false) {
      return false;
    }
    return _studentData?['isOutsideSafezone'] == false;
  }

  String get _lastLocation {
    // Always show the actual location address, not the safezone name
    return _studentData?['lastLocation'] ?? 'Unknown Location';
  }

  String? get _currentSafezoneName {
    if (_isInSafeZone) {
      final safezoneName = _studentData?['currentSafezoneName'];
      if (safezoneName != null && safezoneName.toString().isNotEmpty) {
        return safezoneName.toString();
      }
    }
    return null;
  }

  // Helper function to format time with AM/PM
  String _formatTimeWithAMPM(DateTime date) {
    int hour = date.hour;
    int minute = date.minute;
    String period = hour >= 12 ? 'PM' : 'AM';
    
    // Convert to 12-hour format
    if (hour == 0) {
      hour = 12; // 12 AM (midnight)
    } else if (hour > 12) {
      hour = hour - 12;
    }
    
    return '${hour}:${minute.toString().padLeft(2, '0')} $period';
  }

  String get _lastUpdateTime {
    final timestamp = _studentData?['lastLocationUpdate'];
    if (timestamp is Timestamp) {
      final date = timestamp.toDate();
      return _formatTimeWithAMPM(date);
    } else if (timestamp is String) {
      try {
        final date = DateTime.parse(timestamp);
        return _formatTimeWithAMPM(date);
      } catch (e) {
        print('[DASHBOARD] Error parsing last update time: $e');
      }
    }
    return 'Unknown';
  }

  String get _safezoneEntryTime {
    if (_isInSafeZone) {
      final timestamp = _studentData?['safezoneEntryTime'];
      if (timestamp is Timestamp) {
        final date = timestamp.toDate();
        return _formatTimeWithAMPM(date);
      } else if (timestamp is String) {
        try {
          final date = DateTime.parse(timestamp);
          return _formatTimeWithAMPM(date);
        } catch (e) {
          print('[DASHBOARD] Error parsing safezone entry time: $e');
        }
      }
    }
    return 'Unknown';
  }

  String get _safezoneExitTime {
    if (!_isInSafeZone) {
      final timestamp = _studentData?['safezoneExitTime'];
      if (timestamp is Timestamp) {
        final date = timestamp.toDate();
        return _formatTimeWithAMPM(date);
      } else if (timestamp is String) {
        try {
          final date = DateTime.parse(timestamp);
          return _formatTimeWithAMPM(date);
        } catch (e) {
          print('[DASHBOARD] Error parsing safezone exit time: $e');
        }
      }
    }
    return 'Unknown';
  }

  // Get the appropriate time to display based on safezone status
  String get _displayTime {
    if (_isInSafeZone) {
      // Show entry time if in safezone
      final entryTime = _safezoneEntryTime;
      if (entryTime != 'Unknown') {
        return entryTime;
      }
    } else {
      // Show exit time if outside safezone
      final exitTime = _safezoneExitTime;
      if (exitTime != 'Unknown') {
        return exitTime;
      }
    }
    // Fallback to last update time
    return _lastUpdateTime;
  }

  String get _studentName {
    if (_studentData != null) {
      final firstName = _studentData!['FirstName'] ?? '';
      final lastName = _studentData!['LastName'] ?? '';
      final fullName = '$firstName $lastName'.trim();
      if (fullName.isNotEmpty) {
        return fullName;
      }
    }
    return 'UB Student';
  }

  // Helper to map year level to category and grade
  Map<String, String> _getCategoryAndGradeFromYearLevel(int yearLevel) {
    if (yearLevel >= 0 && yearLevel <= 6) {
      return {'category': 'Elementary Level', 'grade': yearLevel == 0 ? 'Kindergarten' : 'Grade $yearLevel'};
    } else if (yearLevel >= 7 && yearLevel <= 10) {
      return {'category': 'Junior High School', 'grade': 'Grade $yearLevel'};
    } else if (yearLevel >= 11 && yearLevel <= 12) {
      return {'category': 'Senior High School', 'grade': 'Grade $yearLevel'};
    }
    return {'category': 'Unknown', 'grade': 'Unknown'};
  }

  String get _studentLevelCategory {
    if (_studentData?['YearLevel'] != null) {
      final yearLevel = _studentData!['YearLevel'] as int;
      final categoryAndGrade = _getCategoryAndGradeFromYearLevel(yearLevel);
      return '${categoryAndGrade['category']} - ${categoryAndGrade['grade']}';
    }
    return 'Unknown';
  }

  // Check if GPS is online based on last update timestamp
  bool get _isGPSOnline {
    if (_studentData?['lastLocationUpdate'] == null) {
      return false; // No GPS data available
    }

    final lastUpdate = _studentData!['lastLocationUpdate'];
    DateTime? lastUpdateTime;

    // Handle different timestamp formats
    if (lastUpdate is Timestamp) {
      lastUpdateTime = lastUpdate.toDate();
    } else if (lastUpdate is String) {
      try {
        lastUpdateTime = DateTime.parse(lastUpdate);
      } catch (e) {
        print('[DASHBOARD] Error parsing timestamp: $e');
        return false;
      }
    }

    if (lastUpdateTime != null) {
      final secondsSinceUpdate = DateTime.now().difference(lastUpdateTime).inSeconds;
      // If last update was within 3 seconds, GPS is online
      return secondsSinceUpdate <= 3;
    }

    return false;
  }

  @override
  Widget build(BuildContext context) {
    final primaryColor = const Color(0xFF862334);

    return Scaffold(
      backgroundColor: Colors.grey[50],
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
                child: const Text(
                  'UBSafestep',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                ),
              ),
            ),
            const SizedBox(width: 50),
          ],
        ),
        backgroundColor: primaryColor,
        foregroundColor: Colors.white,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: CircleAvatar(
              backgroundColor: Colors.white,
              radius: 18,
              child: Icon(Icons.person, size: 24, color: primaryColor),
            ),
          ),
        ],
        iconTheme: const IconThemeData(color: Colors.white),
      ),

      body: SafeArea(
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Welcome section with real parent name
                Container(
                  margin: const EdgeInsets.only(bottom: 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Welcome back,',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey[700],
                        ),
                      ),
                      Text(
                        widget.userData['parentName'] ?? 'Parent/Guardian',
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF222222),
                        ),
                      ),
                      Text(
                        'Relationship: ${widget.userData['relationship'] ?? 'Parent'}',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                ),

                // Alert notification - shows only when student is outside safezone
                if (!_isInSafeZone)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    margin: const EdgeInsets.only(bottom: 20),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.orange.withOpacity(0.3),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                      border: Border.all(
                        color: Colors.orange,
                        width: 1.5,
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.orange.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(
                            Icons.warning_rounded,
                            color: Colors.orange[800],
                            size: 28,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Zone Alert',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.orange[800],
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '$_studentName is outside a safezone!',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.grey[800],
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              Text(
                                'Last seen: $_lastLocation',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey[600],
                                ),
                                overflow: TextOverflow.ellipsis,
                                maxLines: 2,
                              ),
                              if (!_isInSafeZone && _safezoneExitTime != 'Unknown')
                                Text(
                                  'Left at: $_safezoneExitTime',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey[600],
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                // Child info card with real data
                Container(
                  margin: const EdgeInsets.only(bottom: 24),
                  child: Card(
                    elevation: 3,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(20.0),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              Container(
                                decoration: BoxDecoration(
                                  color: primaryColor.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                padding: const EdgeInsets.all(12),
                                child: CircleAvatar(
                                  radius: 30,
                                  backgroundColor: primaryColor,
                                  child: const Icon(
                                    Icons.person,
                                    size: 36,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 20),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      _studentName,
                                      style: const TextStyle(
                                        fontSize: 20,
                                        fontWeight: FontWeight.bold,
                                        color: Color(0xFF222222),
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 12,
                                        vertical: 6,
                                      ),
                                      decoration: BoxDecoration(
                                        color: _isInSafeZone
                                            ? Colors.green.withOpacity(0.1)
                                            : Colors.red.withOpacity(0.1),
                                        borderRadius: BorderRadius.circular(20),
                                      ),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(
                                                Icons.circle,
                                                size: 10,
                                                color: _isInSafeZone
                                                    ? Colors.green
                                                    : Colors.red,
                                              ),
                                              const SizedBox(width: 6),
                                              Text(
                                                _isInSafeZone
                                                    ? (_currentSafezoneName != null 
                                                        ? 'In: $_currentSafezoneName'
                                                        : 'In Safezone')
                                                    : 'Out of Safezone',
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.w600,
                                                  color: _isInSafeZone
                                                      ? Colors.green
                                                      : Colors.red,
                                                ),
                                              ),
                                            ],
                                          ),
                                          if (_isInSafeZone && _currentSafezoneName != null) ...[
                                            const SizedBox(height: 4),
                                            Text(
                                              'Entered at: ${_safezoneEntryTime != 'Unknown' ? _safezoneEntryTime : _lastUpdateTime}',
                                              style: TextStyle(
                                                fontSize: 10,
                                                color: Colors.grey[600],
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),
                                    if (_studentData?['YearLevel'] != null) ...[
                                      const SizedBox(height: 4),
                                      Text(
                                        _studentLevelCategory,
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.grey[600],
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 20),
                          Container(
                            decoration: BoxDecoration(
                              color: Colors.grey[100],
                              borderRadius: BorderRadius.circular(12),
                            ),
                            padding: const EdgeInsets.all(12),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.location_on,
                                  color: primaryColor,
                                  size: 20,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Text(
                                        'Last Known Location',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.grey,
                                        ),
                                      ),
                                      Text(
                                        _lastLocation,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w600,
                                          color: Color(0xFF222222),
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                        maxLines: 2,
                                      ),
                                    ],
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.grey[200],
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Text(
                                    _displayTime,
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: Colors.grey[700],
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

                // Refresh button
                Container(
                  margin: const EdgeInsets.only(bottom: 16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        "Student Status",
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF222222),
                        ),
                      ),
                      IconButton(
                        icon: Icon(
                          Icons.refresh,
                          color: primaryColor,
                        ),
                        onPressed: _isLoading ? null : () => _loadStudentData(),
                        tooltip: 'Refresh Status',
                      ),
                    ],
                  ),
                ),

                // Status indicators
                Card(
                  elevation: 2,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        _buildStatusIndicator(
                          'Safezone Status',
                          _isInSafeZone 
                              ? (_currentSafezoneName != null 
                                  ? _currentSafezoneName! 
                                  : 'Safe')
                              : 'Alert',
                          _isInSafeZone ? Icons.check_circle : Icons.warning,
                          _isInSafeZone ? Colors.green : Colors.orange,
                        ),
                        const SizedBox(width: 16),
                        _buildStatusIndicator(
                          'GPS Status',
                          _isGPSOnline ? 'Online' : 'Offline',
                          _isGPSOnline ? Icons.signal_cellular_alt : Icons.signal_cellular_off,
                          _isGPSOnline ? Colors.green : Colors.orange,
                        ),
                        const SizedBox(width: 16),
                        _buildStatusIndicator(
                          'Location',
                          _lastLocation,
                          Icons.location_pin,
                          Colors.purple,
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 24),

                // View on map button
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => MapScreen(
                            userData: widget.userData,
                            userId: widget.userId,
                          ),
                        ),
                      );
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: primaryColor,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 2,
                    ),
                    icon: const Icon(Icons.map, color: Colors.white),
                    label: const Text(
                      'VIEW ON MAP',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStatusIndicator(String title, String value, IconData icon, Color color) {
    return Expanded(
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(height: 8),
          Text(
            title,
            style: TextStyle(
              fontSize: 10,
              color: Colors.grey[600],
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: color,
            ),
            textAlign: TextAlign.center,
            overflow: TextOverflow.ellipsis,
            maxLines: 2,
          ),
        ],
      ),
    );
  }
}
