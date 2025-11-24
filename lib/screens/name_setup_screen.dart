import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'main_navigation.dart';
import '../services/firestore_service.dart';

class NameSetupScreen extends StatefulWidget {
  final String userEmail;
  final String? userDisplayName;
  final Map<String, dynamic>? studentInfo;

  const NameSetupScreen({
    super.key,
    required this.userEmail,
    this.userDisplayName,
    required this.studentInfo,
  });

  @override
  State<NameSetupScreen> createState() => _NameSetupScreenState();
}

class _NameSetupScreenState extends State<NameSetupScreen> {
  final _parentNameController = TextEditingController();
  final _firstNameController = TextEditingController(); // For student first name
  final _lastNameController = TextEditingController();  // For student last name
  final _relationshipController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  final FirestoreService _firestoreService = FirestoreService();
  final FirebaseAuth _auth = FirebaseAuth.instance;
  bool _isSaving = false;
  bool _isVerified = false;

  // New variables for category and grade selection
  String? _selectedCategory;
  String? _selectedGrade;
  Map<String, List<String>> _gradeOptions = {
    'Elementary Level': ['Kindergarten', 'Grade 1', 'Grade 2', 'Grade 3', 'Grade 4', 'Grade 5', 'Grade 6'],
    'Junior High School': ['Grade 7', 'Grade 8', 'Grade 9', 'Grade 10'],
    'Senior High School': ['Grade 11', 'Grade 12'],
  };

  // Mapping grades to year level integers
  int _getYearLevelFromGrade(String category, String grade) {
    final Map<String, int> gradeToLevel = {
      'Kindergarten': 0,
      'Grade 1': 1,
      'Grade 2': 2,
      'Grade 3': 3,
      'Grade 4': 4,
      'Grade 5': 5,
      'Grade 6': 6,
      'Grade 7': 7,
      'Grade 8': 8,
      'Grade 9': 9,
      'Grade 10': 10,
      'Grade 11': 11,
      'Grade 12': 12,
    };
    return gradeToLevel[grade] ?? 0;
  }

  @override
  void initState() {
    super.initState();
    // Pre-fill student name fields if display name is available from Google Sign-In
    if (widget.userDisplayName != null && widget.userDisplayName!.isNotEmpty) {
      final nameParts = widget.userDisplayName!.split(' ');
      _firstNameController.text = nameParts.first;
      if (nameParts.length > 1) {
        _lastNameController.text = nameParts.sublist(1).join(' ');
      }
    }
    _checkEmailVerification();
    _checkExistingUserData();
  }

  Future<void> _checkEmailVerification() async {
    final user = _auth.currentUser;
    if (user != null) {
      await user.reload(); // Refresh user data
      if (mounted) {
        setState(() {
          _isVerified = user.emailVerified;
        });
      }
    }
  }

  Future<void> _resendVerificationEmail() async {
    final user = _auth.currentUser;
    if (user != null && !user.emailVerified) {
      await user.sendEmailVerification();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Verification email sent! Please check your inbox.'),
            backgroundColor: Colors.green,
          ),
        );
      }
    }
  }

  Future<void> _checkExistingUserData() async {
    final userData = await _firestoreService.getParentGuardianByUBmail(widget.userEmail);
    if (userData != null && mounted) {
      _navigateToMain(
        parentName: userData['parentName'] ?? 'Parent/Guardian',
        relationship: userData['relationship'] ?? 'Parent',
        parentGuardianId: userData['ParentGuardianID'],
      );
    }
  }

  String _getStudentIdFromEmail(String email) {
    final parts = email.split('@');
    return parts.isNotEmpty ? parts[0] : _firestoreService.generateId();
  }

  void _saveNames() async {
    if (!_isVerified) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please verify your email before proceeding.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    if (_formKey.currentState!.validate()) {
      setState(() {
        _isSaving = true;
      });

      final parentName = _parentNameController.text.trim();
      final relationship = _relationshipController.text.trim();
      final firstName = _firstNameController.text.trim();
      final lastName = _lastNameController.text.trim();
      final studentId = _getStudentIdFromEmail(widget.userEmail);
      final yearLevel = _getYearLevelFromGrade(_selectedCategory!, _selectedGrade!);

      try {
        await _firestoreService.saveStudentData(
          studentId: studentId,
          firstName: firstName,
          lastName: lastName,
          yearLevel: yearLevel,
          ubmail: widget.userEmail,
          password: "", // Not needed for student record in this context
        );

        final parentGuardianId = _firestoreService.generateId();
        await _firestoreService.saveParentGuardian(
          parentGuardianId: parentGuardianId,
          studentId: studentId,
          ubmail: widget.userEmail,
          password: 'parent123', // Default password, consider security implications
          parentName: parentName,
          relationship: relationship,
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
            SnackBar(content: Text('Failed to save data: $e'), backgroundColor: Colors.red),
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
            'relationship': relationship,
            'userEmail': widget.userEmail,
            'StudentID': _getStudentIdFromEmail(widget.userEmail),
            'ParentGuardianID': parentGuardianId,
            ...widget.studentInfo ?? {},
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
                Center(
                  child: Column(
                    children: [
                      Image.asset('asset/New UBsafestep.png', width: 300, height: 200),
                      const SizedBox(height: 16),
                      Text('Profile Setup', style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: primaryColor)),
                      const SizedBox(height: 8),
                      Text('Complete your profile to continue', style: TextStyle(fontSize: 16, color: Colors.grey[700])),
                    ],
                  ),
                ),
                const SizedBox(height: 32),
                // Email Verification Section
                if (!_isVerified) ...[
                  const Text(
                    'Verify Your Email',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'A verification email has been sent to ${widget.userEmail}. Please check your inbox and verify your email before proceeding.',
                    style: const TextStyle(fontSize: 16),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      const Icon(Icons.error, color: Colors.red),
                      const SizedBox(width: 8),
                      const Text(
                        'Email Not Verified',
                        style: TextStyle(
                          color: Colors.red,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: _resendVerificationEmail,
                    child: const Text('Resend Verification Email'),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: _checkEmailVerification,
                    child: const Text('I have verified my email'),
                  ),
                  const SizedBox(height: 32),
                ],
                // Student Information Section
                const Text(
                  "Student's Information",
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),
                Text("Student's First Name", style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.grey[800])),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _firstNameController,
                  decoration: InputDecoration(
                    hintText: "Enter the student's first name",
                    prefixIcon: const Icon(Icons.school_outlined),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  validator: (value) => (value == null || value.isEmpty) ? "Please enter the student's first name" : null,
                ),
                const SizedBox(height: 16),
                Text("Student's Last Name", style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.grey[800])),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _lastNameController,
                  decoration: InputDecoration(
                    hintText: "Enter the student's last name",
                    prefixIcon: const Icon(Icons.school_outlined),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  validator: (value) => (value == null || value.isEmpty) ? "Please enter the student's last name" : null,
                ),
                const SizedBox(height: 16),
                Text("Student's Level", style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.grey[800])),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  value: _selectedCategory,
                  decoration: InputDecoration(
                    hintText: 'Select level category',
                    prefixIcon: const Icon(Icons.category),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  items: _gradeOptions.keys.map((category) {
                    return DropdownMenuItem<String>(
                      value: category,
                      child: Text(category),
                    );
                  }).toList(),
                  onChanged: (value) {
                    setState(() {
                      _selectedCategory = value;
                      _selectedGrade = null; // Reset grade when category changes
                    });
                  },
                  validator: (value) {
                    if (value == null || value.isEmpty) return 'Please select a level category';
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                if (_selectedCategory != null) ...[
                  Text("Student's Grade", style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.grey[800])),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    value: _selectedGrade,
                    decoration: InputDecoration(
                      hintText: 'Select grade',
                      prefixIcon: const Icon(Icons.format_list_numbered),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    items: _gradeOptions[_selectedCategory]!.map((grade) {
                      return DropdownMenuItem<String>(
                        value: grade,
                        child: Text(grade),
                      );
                    }).toList(),
                    onChanged: (value) {
                      setState(() {
                        _selectedGrade = value;
                      });
                    },
                    validator: (value) {
                      if (value == null || value.isEmpty) return 'Please select a grade';
                      return null;
                    },
                  ),
                ],
                const SizedBox(height: 24),
                // Parent Information Section
                const Text(
                  'Your Information (Parent/Guardian)',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),
                Text('Your Name (Parent/Guardian)', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.grey[800])),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _parentNameController,
                  decoration: InputDecoration(
                    hintText: 'Enter your full name',
                    prefixIcon: const Icon(Icons.person_outline),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  validator: (value) => (value == null || value.isEmpty) ? 'Please enter your name' : null,
                ),
                const SizedBox(height: 16),
                Text('Relationship to Student', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.grey[800])),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _relationshipController,
                  decoration: InputDecoration(
                    hintText: 'e.g., Mother, Father, Guardian, etc.',
                    prefixIcon: const Icon(Icons.family_restroom_outlined),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  validator: (value) => (value == null || value.isEmpty) ? 'Please enter your relationship' : null,
                ),
                const SizedBox(height: 32),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    onPressed: _isSaving ? null : _saveNames,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: primaryColor,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: _isSaving
                        ? const CircularProgressIndicator(valueColor: AlwaysStoppedAnimation<Color>(Colors.white))
                        : const Text('Save and Continue', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
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
    _firstNameController.dispose();
    _lastNameController.dispose();
    _relationshipController.dispose();
    super.dispose();
  }
}