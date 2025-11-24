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
  IconData _selectedIcon = Icons.location_on;

  // Predefined UB Safezones
  List<Map<String, dynamic>> get _predefinedSafezones {
    return [
      {
        'Zonename': 'University of Batangas - Elementary Department',
        'Address': 'University of Batangas, Batangas City',
        'Coordinates': '13.754693277111798, 121.05816575323965',
        'Radius': 40.0,
        'isPredefined': true,
        'SafezoneID': 'UB_ELEMENTARY_DEPT',
      },
      {
        'Zonename': 'University Of Batangas',
        'Address': 'University of Batangas, Batangas City',
        'Coordinates': '13.763555046394824, 121.05986555221901',
        'Radius': 100.0,
        'isPredefined': true,
        'SafezoneID': 'UB_MAIN',
      },
      {
        'Zonename': 'University of Batangas - Senior High School',
        'Address': 'University of Batangas, Batangas City',
        'Coordinates': '13.763809309801465, 121.05748439205635',
        'Radius': 50.0,
        'isPredefined': true,
        'SafezoneID': 'UB_SENIOR_HIGH',
      },
    ];
  }

  @override
  void initState() {
    super.initState();
    print('🚀 [SAFEZONES] Screen initialized for user: ${widget.userId}');
    print('📋 [SAFEZONES] User data: ${widget.userData}');
    _loadSafeZones();
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
          isPickingMode: true,
          previewRadius: _radius,
        ),
      ),
    );

    if (pickedLocation != null && pickedLocation is Map) {
      final location = pickedLocation['location'] as LatLng?;
      final radius = pickedLocation['radius'] as double?;
      
      if (location != null) {
        setState(() {
          _latitudeController.text = location.latitude.toStringAsFixed(6);
          _longitudeController.text = location.longitude.toStringAsFixed(6);
          if (radius != null) {
            _radius = radius;
          }
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('📍 Location set: ${location.latitude.toStringAsFixed(6)}, ${location.longitude.toStringAsFixed(6)}\nRadius: ${_radius.round()}m'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }

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
          content: Text('Please pick a location on the map'),
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
        iconCodePoint: _selectedIcon.codePoint,
      );

      print('✅ [SAFEZONES] Safezone saved successfully, reloading...');

      if (mounted) {
        Navigator.pop(context);
      }

      await Future.delayed(const Duration(milliseconds: 500));
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
    
    // Load icon from zone data or use default based on name
    final iconCodePoint = zone['IconCodePoint'];
    if (iconCodePoint != null && iconCodePoint is int) {
      _selectedIcon = IconData(iconCodePoint, fontFamily: 'MaterialIcons');
    } else {
      _selectedIcon = _getZoneIcon(zone['Zonename'] ?? '');
    }

    _showSafeZoneDialog(isEditing: true);
  }

  void _showAddSafeZoneDialog() {
    _editingZone = null;
    _nameController.clear();
    _addressController.clear();
    _latitudeController.clear();
    _longitudeController.clear();
    _radius = 150.0;
    _selectedIcon = Icons.location_on;

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
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text(
                                'Location',
                                style: TextStyle(fontWeight: FontWeight.bold),
                              ),
                              if (_latitudeController.text.isNotEmpty)
                                const Icon(Icons.check_circle, color: Colors.green, size: 16),
                            ],
                          ),
                          if (_latitudeController.text.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 4.0),
                              child: Text(
                                'Selected: ${_latitudeController.text}, ${_longitudeController.text}',
                                style: TextStyle(fontSize: 12, color: Colors.grey[700]),
                              ),
                            ),
                          const SizedBox(height: 8),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              onPressed: _openMapForLocationPicking,
                              icon: const Icon(Icons.map),
                              label: Text(
                                _latitudeController.text.isNotEmpty 
                                  ? 'Change Location on Map' 
                                  : 'Pick Location on Map'
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.blue,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(vertical: 12),
                              ),
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
                            'Zone Icon',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 12,
                            runSpacing: 12,
                            children: [
                              _buildIconOption(Icons.home, 'Home', setState),
                              _buildIconOption(Icons.school, 'School', setState),
                              _buildIconOption(Icons.business, 'Business', setState),
                              _buildIconOption(Icons.park, 'Park', setState),
                              _buildIconOption(Icons.restaurant, 'Restaurant', setState),
                              _buildIconOption(Icons.local_gas_station, 'Gas Station', setState),
                              _buildIconOption(Icons.shopping_cart, 'Shopping', setState),
                              _buildIconOption(Icons.local_hospital, 'Hospital', setState),
                              _buildIconOption(Icons.church, 'Church', setState),
                              _buildIconOption(Icons.sports_soccer, 'Sports', setState),
                              _buildIconOption(Icons.beach_access, 'Beach', setState),
                              _buildIconOption(Icons.location_on, 'Location', setState),
                            ],
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
    
    // Get icon from stored data or use default
    final iconCodePoint = zone['IconCodePoint'];
    IconData icon;
    if (iconCodePoint != null && iconCodePoint is int) {
      icon = IconData(iconCodePoint, fontFamily: 'MaterialIcons');
    } else {
      icon = _getZoneIcon(zoneName);
    }

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
                  icon,
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
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Icon(Icons.radar, size: 16, color: Colors.grey[500]),
                        const SizedBox(width: 4),
                        Text(
                          'Radius: ${radius}m',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[600],
                          ),
                        ),
                        if (isPredefined && email.isNotEmpty) ...[
                          const SizedBox(width: 12),
                          Icon(Icons.email, size: 16, color: Colors.grey[500]),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              email,
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey[600],
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              if (!isPredefined)
                Column(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.edit, color: Colors.blue),
                      onPressed: () => _showEditSafeZoneDialog(zone),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete, color: Colors.red),
                      onPressed: () => _showDeleteConfirmation(
                        zone['SafezoneID'],
                        zoneName,
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }

  IconData _getZoneIcon(String name) {
    final lowerName = name.toLowerCase();
    if (lowerName.contains('home')) return Icons.home;
    if (lowerName.contains('school') || lowerName.contains('university')) return Icons.school;
    if (lowerName.contains('park')) return Icons.park;
    return Icons.location_on;
  }

  Widget _buildIconOption(IconData icon, String label, StateSetter dialogSetState) {
    final isSelected = _selectedIcon.codePoint == icon.codePoint;
    return GestureDetector(
      onTap: () {
        dialogSetState(() {
          _selectedIcon = icon;
        });
      },
      child: Container(
        width: 70,
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF862334).withOpacity(0.1) : Colors.grey[100],
          border: Border.all(
            color: isSelected ? const Color(0xFF862334) : Colors.grey[300]!,
            width: isSelected ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              color: isSelected ? const Color(0xFF862334) : Colors.grey[700],
              size: 28,
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                color: isSelected ? const Color(0xFF862334) : Colors.grey[700],
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Color _getZoneColor(String name) {
    final lowerName = name.toLowerCase();
    if (lowerName.contains('home')) return Colors.blue;
    if (lowerName.contains('school') || lowerName.contains('university')) return const Color(0xFF862334);
    if (lowerName.contains('park')) return Colors.green;
    return Colors.orange;
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
                child: const Text(
                  'Manage Safe Zones',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                ),
              ),
            ),
            const SizedBox(width: 50),
          ],
        ),
        backgroundColor: primaryColor,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddSafeZoneDialog,
        backgroundColor: primaryColor,
        child: const Icon(Icons.add, color: Colors.white),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (_predefinedSafezones.isNotEmpty) ...[
                  const Padding(
                    padding: EdgeInsets.only(bottom: 8.0),
                    child: Text(
                      'System Safe Zones',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Colors.grey,
                      ),
                    ),
                  ),
                  ..._predefinedSafezones.map((zone) => _buildSafezoneCard(zone, isPredefined: true)).toList(),
                  if (_safeZones.isNotEmpty) const SizedBox(height: 16),
                ],
                if (_safeZones.isNotEmpty) ...[
                  const Padding(
                    padding: EdgeInsets.only(bottom: 8.0),
                    child: Text(
                      'My Safe Zones',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Colors.grey,
                      ),
                    ),
                  ),
                  ..._safeZones.map((zone) => _buildSafezoneCard(zone)).toList(),
                ],
                if (_safeZones.isEmpty && _predefinedSafezones.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Center(
                    child: Column(
                      children: [
                        Icon(Icons.add_circle_outline, size: 48, color: Colors.grey[400]),
                        const SizedBox(height: 8),
                        Text(
                          'Add your own safe zones',
                          style: TextStyle(fontSize: 14, color: Colors.grey[500]),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 60), // Space for FAB
              ],
            ),
    );
  }
}
