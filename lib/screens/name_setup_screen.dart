import 'package:flutter/material.dart';
import 'main_navigation.dart';
import '../services/firestore_service.dart';

class NameSetupScreen extends StatefulWidget {
  final String userEmail;
  final Map<String, dynamic>? studentInfo;

  const NameSetupScreen({
    super.key,
    required this.userEmail,
    required this.studentInfo,
  });

  @override
  State<NameSetupScreen> createState() => _NameSetupScreenState();
}

class _NameSetupScreenState extends State<NameSetupScreen> {
  final _parentNameController = TextEditingController();
  final _relationshipController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  final FirestoreService _firestoreService = FirestoreService();
  bool _isSaving = false;

  // Check if user already has saved names
  Future<Map<String, dynamic>?> _getUserData() async {
    try {
      return await _firestoreService.getParentGuardianByUBmail(widget.userEmail);
    } catch (e) {
      print('Error getting user data: $e');
      return null;
    }
  }

  // Helper method to extract student ID from email
  String _getStudentIdFromEmail(String email) {
    // Extract student ID from email (e.g., "2000118@ub.edu.ph" -> "2000118")
    final parts = email.split('@');
    if (parts.isNotEmpty) {
      return parts[0];
    }
    return _firestoreService.generateId(); // Fallback if extraction fails
  }

  @override
  void initState() {
    super.initState();
    _checkExistingUserData();
  }

  void _checkExistingUserData() async {
    final userData = await _getUserData();
    if (userData != null && mounted) {
      // User already has data, skip to main navigation
      _navigateToMain(
        parentName: userData['parentName'] ?? 'Parent/Guardian',
        relationship: userData['relationship'] ?? 'Parent',
        parentGuardianId: userData['ParentGuardianID'],
      );
    }
  }

  void _saveNames() async {
    if (_formKey.currentState!.validate()) {
      setState(() {
        _isSaving = true;
      });

      final parentName = _parentNameController.text.trim();
      final relationship = _relationshipController.text.trim();
      final childName = widget.studentInfo?['studentName'] ?? 'UB Student';

      try {
        final parentGuardianId = _firestoreService.generateId();
        await _firestoreService.saveParentGuardian(
          parentGuardianId: parentGuardianId,
          studentId: _getStudentIdFromEmail(widget.userEmail),
          ubmail: widget.userEmail,
          password: 'parent123', // Default password for parent accounts
        );

        if (mounted) {
          _navigateToMain(
            parentName: parentName,
            relationship: relationship,
            parentGuardianId: parentGuardianId,
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to save data: $e'),
              backgroundColor: Colors.red,
            ),
          );
          setState(() {
            _isSaving = false;
          });
        }
      }
    }
  }

  void _navigateToMain({
    required String parentName,
    required String relationship,
    required String parentGuardianId,
  }) {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (context) => MainNavigation(
          userData: {
            'parentName': parentName,
            'childName': widget.studentInfo?['studentName'] ?? 'UB Student',
            'userEmail': widget.userEmail,
            'userDisplayName': parentName,
            'isInSafeZone': false,
            'lastLocation': 'University of Batangas',
            'lastUpdateTime': '3:42 PM',
            'isParent': true,
            'relationship': relationship,
            'studentInfo': widget.studentInfo,
            'StudentID': _getStudentIdFromEmail(widget.userEmail),
            'UBMail': widget.userEmail,
            'ParentGuardianID': parentGuardianId,
          },
          userId: parentGuardianId,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final primaryColor = const Color(0xFF862334);

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                Center(
                  child: Column(
                    children: [
                      Image.asset(
                        'asset/New UBsafestep.png',
                        width: 300,
                        height: 200,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Parent Profile Setup',
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          color: primaryColor,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Set up your parent/guardian profile',
                        style: TextStyle(
                          fontSize: 16,
                          color: Colors.grey[700],
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 32),

                // Student Information Card
                Card(
                  elevation: 2,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.school, color: primaryColor),
                            const SizedBox(width: 8),
                            Text(
                              'Student Information',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: primaryColor,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Student: ${widget.studentInfo?['studentName'] ?? 'N/A'}',
                          style: const TextStyle(fontSize: 14),
                        ),
                        Text(
                          'Email: ${widget.userEmail}',
                          style: const TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                        if (widget.studentInfo?['course'] != null)
                          Text(
                            'Course: ${widget.studentInfo!['course']}',
                            style: const TextStyle(fontSize: 12, color: Colors.grey),
                          ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 24),

                // Parent/Guardian Name Field
                Text(
                  'Your Name (Parent/Guardian)',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey[800],
                  ),
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _parentNameController,
                  decoration: InputDecoration(
                    hintText: 'Enter your full name',
                    prefixIcon: const Icon(Icons.person_outline),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Please enter your name';
                    }
                    return null;
                  },
                ),

                const SizedBox(height: 16),

                // Relationship Field
                Text(
                  'Relationship to Student',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey[800],
                  ),
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _relationshipController,
                  decoration: InputDecoration(
                    hintText: 'e.g., Mother, Father, Guardian, etc.',
                    prefixIcon: const Icon(Icons.family_restroom_outlined),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Please enter your relationship';
                    }
                    return null;
                  },
                ),

                const SizedBox(height: 32),

                // Continue Button
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    onPressed: _isSaving ? null : _saveNames,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: primaryColor,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: _isSaving
                        ? const CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    )
                        : const Text(
                      'Save and Continue',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
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

  @override
  void dispose() {
    _parentNameController.dispose();
    _relationshipController.dispose();
    super.dispose();
  }
}