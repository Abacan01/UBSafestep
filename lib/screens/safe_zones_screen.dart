import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'map_screen.dart';
import '../../services/firestore_service.dart';

class SafeZonesScreen extends StatefulWidget {
  final Map<String, dynamic> userData;
  final String userId;

  const SafeZonesScreen({
    Key? key,
    required this.userData,
    required this.userId,
  }) : super(key: key);

  @override
  State<SafeZonesScreen> createState() => _SafeZonesScreenState();
}

class _SafeZonesScreenState extends State<SafeZonesScreen> {
  final FirestoreService _firestoreService = FirestoreService();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _addressController = TextEditingController();
  final TextEditingController _latitudeController = TextEditingController();
  final TextEditingController _longitudeController = TextEditingController();

  List<Map<String, dynamic>> _safeZones = [];
  bool _isLoading = true;
  double _radius = 150.0;
  Map<String, dynamic>? _editingZone;

  // Predefined UB Safezone
  final Map<String, dynamic> _ubSafezone = {
    'Zonename': 'University of Batangas',
    'Address': 'University of Batangas, Batangas City',
    'Coordinates': '13.7565,121.0583',
    'Radius': 200.0,
    'isPredefined': true,
    'email': 'ub@ub.edu.ph',
  };

  @override
  void initState() {
    super.initState();
    print('🚀 [SAFEZONES] Screen initialized for user: ${widget.userId}');
    print('📋 [SAFEZONES] User data: ${widget.userData}');
    _loadSafeZones();

    // Remove the test call - comment this out:
    // WidgetsBinding.instance.addPostFrameCallback((_) {
    //   _firestoreService.testSafezoneFlow(widget.userId);
    // });
  }

  @override
  void dispose() {
    _nameController.dispose();
    _addressController.dispose();
    _latitudeController.dispose();
    _longitudeController.dispose();
    super.dispose();
  }

  Future<void> _loadSafeZones() async {
    print('🔄 [SAFEZONES] Starting to load safe zones for user: ${widget.userId}');

    setState(() {
      _isLoading = true;
    });

    try {
      final safeZones = await _firestoreService.getSafezonesByParent(widget.userId);

      print('📊 [SAFEZONES] Load complete:');
      print('   - User ID: ${widget.userId}');
      print('   - Number of safezones received: ${safeZones.length}');

      if (safeZones.isEmpty) {
        print('   ⚠️ No safezones found for this user');
      } else {
        for (var zone in safeZones) {
          print('   - Safezone: ${zone['Zonename']}');
          print('     ID: ${zone['SafezoneID']}');
          print('     ParentID: ${zone['ParentGuardianID']}');
          print('     Coordinates: ${zone['Coordinates']}');
        }
      }

      setState(() {
        _safeZones = safeZones;
        _isLoading = false;
      });

      print('✅ [SAFEZONES] UI state updated with ${_safeZones.length} safezones');

    } catch (e) {
      print('❌ [SAFEZONES] Error loading safe zones: $e');
      setState(() {
        _isLoading = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading safe zones: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _openMapForLocationPicking() async {
    final pickedLocation = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => MapScreen(
          userData: widget.userData,
          userId: widget.userId,
        ),
      ),
    );

    if (pickedLocation != null && pickedLocation is LatLng) {
      setState(() {
        _latitudeController.text = pickedLocation.latitude.toStringAsFixed(6);
        _longitudeController.text = pickedLocation.longitude.toStringAsFixed(6);
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('📍 Location set: ${pickedLocation.latitude.toStringAsFixed(6)}, ${pickedLocation.longitude.toStringAsFixed(6)}'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  // ADD THIS METHOD BACK - This is the main save method that was missing
  Future<void> _saveSafeZone() async {
    final zoneName = _nameController.text.trim();
    final address = _addressController.text.trim();

    if (zoneName.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter a zone name'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    if (address.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter an address'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final double latitude = double.tryParse(_latitudeController.text) ?? 0.0;
    final double longitude = double.tryParse(_longitudeController.text) ?? 0.0;

    if (latitude == 0.0 || longitude == 0.0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please set valid coordinates'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    print('💾 [SAFEZONES] Starting to save safezone: $zoneName');
    print('📍 [SAFEZONES] Coordinates: $latitude, $longitude');

    setState(() {
      _isLoading = true;
    });

    try {
      final safezoneId = _editingZone?['SafezoneID'] ?? _firestoreService.generateId();

      await _firestoreService.saveSafezone(
        safezoneId: safezoneId,
        parentGuardianId: widget.userId,
        zoneName: zoneName,
        address: address,
        coordinates: '$latitude,$longitude',
        radius: _radius,
      );

      print('✅ [SAFEZONES] Safezone saved successfully, reloading...');

      // Close the dialog
      if (mounted) {
        Navigator.pop(context);
      }

      // Wait a moment for Firestore to process
      await Future.delayed(const Duration(milliseconds: 500));

      // Reload the safezones
      await _loadSafeZones();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ ${_editingZone != null ? 'Updated' : 'Added'} "$zoneName" safezone successfully!'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 3),
          ),
        );
      }

      // Reset form
      _nameController.clear();
      _addressController.clear();
      _latitudeController.clear();
      _longitudeController.clear();
      _radius = 150.0;
      _editingZone = null;

    } catch (e) {
      print('❌ [SAFEZONES] Error saving safezone: $e');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error saving safezone: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _deleteSafeZone(String safezoneId, String zoneName) async {
    try {
      await _firestoreService.deleteSafezone(safezoneId);
      await _loadSafeZones();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('🗑️ "$zoneName" safezone deleted'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error deleting safezone: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _showDeleteConfirmation(String safezoneId, String zoneName) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Safezone'),
        content: Text('Are you sure you want to delete "$zoneName"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () {
              Navigator.pop(context);
              _deleteSafeZone(safezoneId, zoneName);
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  void _showEditSafeZoneDialog(Map<String, dynamic> zone) {
    _editingZone = zone;
    _nameController.text = zone['Zonename'] ?? '';
    _addressController.text = zone['Address'] ?? '';

    final coordinates = zone['Coordinates']?.toString() ?? '';
    if (coordinates.isNotEmpty) {
      final parts = coordinates.split(',');
      if (parts.length == 2) {
        _latitudeController.text = parts[0].trim();
        _longitudeController.text = parts[1].trim();
      }
    }

    _radius = (zone['Radius'] as num?)?.toDouble() ?? 150.0;

    _showSafeZoneDialog(isEditing: true);
  }

  void _showAddSafeZoneDialog() {
    _editingZone = null;
    _nameController.clear();
    _addressController.clear();
    _latitudeController.clear();
    _longitudeController.clear();
    _radius = 150.0;

    _showSafeZoneDialog(isEditing: false);
  }

  void _showSafeZoneDialog({bool isEditing = false}) {
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            title: Text(isEditing ? 'Edit Safezone' : 'Add New Safezone'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: _nameController,
                    decoration: const InputDecoration(
                      labelText: 'Zone Name',
                      border: OutlineInputBorder(),
                      hintText: 'Home, School, etc.',
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _addressController,
                    decoration: const InputDecoration(
                      labelText: 'Address',
                      border: OutlineInputBorder(),
                      hintText: 'Full address for reference',
                    ),
                  ),
                  const SizedBox(height: 16),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Location Coordinates',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: _latitudeController,
                                  decoration: const InputDecoration(
                                    labelText: 'Latitude',
                                    border: OutlineInputBorder(),
                                    hintText: '13.7565',
                                  ),
                                  keyboardType: TextInputType.number,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: TextField(
                                  controller: _longitudeController,
                                  decoration: const InputDecoration(
                                    labelText: 'Longitude',
                                    border: OutlineInputBorder(),
                                    hintText: '121.0583',
                                  ),
                                  keyboardType: TextInputType.number,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          ElevatedButton.icon(
                            onPressed: _openMapForLocationPicking,
                            icon: const Icon(Icons.map),
                            label: const Text('Pick Location on Map'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.blue,
                              foregroundColor: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Zone Radius',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 8),
                          Slider(
                            value: _radius,
                            min: 50,
                            max: 1000,
                            divisions: 19,
                            label: '${_radius.round()}m',
                            onChanged: (value) {
                              setState(() {
                                _radius = value;
                              });
                            },
                          ),
                          Text(
                            'Radius: ${_radius.round()} meters',
                            style: TextStyle(
                              color: Colors.grey[600],
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () {
                  _editingZone = null;
                  Navigator.pop(context);
                },
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF862334),
                ),
                onPressed: _saveSafeZone,
                child: Text(
                    isEditing ? 'Update Safezone' : 'Save Safezone',
                    style: const TextStyle(color: Colors.white)
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildSafezoneCard(Map<String, dynamic> zone, {bool isPredefined = false}) {
    final zoneName = zone['Zonename'] ?? 'Unnamed Zone';
    final address = zone['Address'] ?? 'No address provided';
    final radius = zone['Radius']?.toString() ?? '150';
    final email = zone['email'] ?? '';

    print('🎨 [UI] Building card for: $zoneName');

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      child: Card(
        elevation: 3,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  color: _getZoneColor(zoneName).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(25),
                ),
                child: Icon(
                  _getZoneIcon(zoneName),
                  color: _getZoneColor(zoneName),
                  size: 24,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      zoneName,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      address,
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey[600],
                      ),
                    ),
                    if (email.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        'e-mail: $email',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[500],
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ],
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Icon(
                          Icons.radio_button_checked,
                          size: 14,
                          color: _getZoneColor(zoneName),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'Radius: ${radius}m',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[500],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              if (!isPredefined) ...[
                IconButton(
                  icon: const Icon(Icons.edit, color: Colors.blue),
                  onPressed: () => _showEditSafeZoneDialog(zone),
                  tooltip: 'Edit Safezone',
                ),
                IconButton(
                  icon: const Icon(Icons.delete, color: Colors.red),
                  onPressed: () => _showDeleteConfirmation(
                    zone['SafezoneID'],
                    zoneName,
                  ),
                  tooltip: 'Delete Safezone',
                ),
              ] else ...[
                const Icon(
                  Icons.lock,
                  color: Colors.grey,
                  size: 20,
                ),
                const SizedBox(width: 8),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Container(
      margin: const EdgeInsets.only(top: 20),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[300]!),
      ),
      child: Column(
        children: [
          Icon(
            Icons.add_location_alt,
            size: 48,
            color: Colors.grey[400],
          ),
          const SizedBox(height: 12),
          const Text(
            'No Custom Safezones',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Colors.grey,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Add your first safezone to get started',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  IconData _getZoneIcon(String zoneName) {
    final name = zoneName.toLowerCase();
    if (name.contains('home') || name.contains('house')) {
      return Icons.home;
    } else if (name.contains('school') || name.contains('university') || name.contains('college')) {
      return Icons.school;
    } else if (name.contains('work') || name.contains('office')) {
      return Icons.work;
    } else {
      return Icons.location_on;
    }
  }

  Color _getZoneColor(String zoneName) {
    final name = zoneName.toLowerCase();
    if (name.contains('home') || name.contains('house')) {
      return Colors.blue;
    } else if (name.contains('school') || name.contains('university') || name.contains('college')) {
      return Colors.green;
    } else if (name.contains('work') || name.contains('office')) {
      return Colors.orange;
    } else {
      return Colors.purple;
    }
  }

  @override
  Widget build(BuildContext context) {
    final primaryColor = const Color(0xFF862334);

    print('🏗️ [UI] Building SafeZonesScreen with ${_safeZones.length} safezones');
    print('🏗️ [UI] Loading state: $_isLoading');

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text(
          'Safe Zones',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        backgroundColor: const Color(0xFF862334),
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadSafeZones,
            tooltip: 'Refresh',
          ),
          IconButton(
            icon: const Icon(Icons.add_location_alt),
            onPressed: _showAddSafeZoneDialog,
            tooltip: 'Add Safezone',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Loading safe zones...'),
          ],
        ),
      )
          : Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              'Your Safe Zones',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.grey[800],
              ),
            ),
          ),

          // Safezones List
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                // Predefined UB Safezone (always shown)
                _buildSafezoneCard(_ubSafezone, isPredefined: true),

                // User's custom safezones
                if (_safeZones.isNotEmpty)
                  ..._safeZones.map((zone) => _buildSafezoneCard(zone)),

                // Empty state for custom safezones
                if (_safeZones.isEmpty)
                  _buildEmptyState(),
              ],
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddSafeZoneDialog,
        backgroundColor: primaryColor,
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }
}