import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'login_page.dart';
import '../../services/firestore_service.dart';

class SettingsScreen extends StatefulWidget {
  final Map<String, dynamic> userData;
  final String userId;

  const SettingsScreen({
    Key? key,
    required this.userData,
    required this.userId,
  }) : super(key: key);

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final GoogleSignIn _googleSignIn = GoogleSignIn();
  final FirestoreService _firestoreService = FirestoreService();
  bool _isLoading = false;
  final TextEditingController _parentNameController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _parentNameController.text = widget.userData['parentName'] ?? '';
  }

  @override
  void dispose() {
    _parentNameController.dispose();
    super.dispose();
  }

  Future<void> _logout() async {
    setState(() {
      _isLoading = true;
    });

    try {
      // Sign out from Firebase
      await _auth.signOut();

      // Sign out from Google if user used Google Sign-In
      if (await _googleSignIn.isSignedIn()) {
        await _googleSignIn.signOut();
      }

      // Navigate to login page
      if (mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (context) => const LoginPage()),
              (Route<dynamic> route) => false,
        );

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Successfully logged out!')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error during logout: $e')),
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

  void _showLogoutConfirmation() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Log Out'),
        content: const Text('Are you sure you want to log out?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF862334)),
            onPressed: () {
              Navigator.pop(context);
              _logout();
            },
            child: const Text('Log Out', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Future<void> _showAccountInfo() async {
    final studentData = await _firestoreService.getStudentData(widget.userData['StudentID']);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Account Information'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildInfoRow('Parent Name', widget.userData['parentName'] ?? 'Not set'),
              _buildInfoRow('Parent Email', widget.userData['UBMail'] ?? 'Not available'),
              _buildInfoRow('Parent ID', widget.userId),
              const SizedBox(height: 16),
              const Text(
                'Student Information',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              const SizedBox(height: 8),
              if (studentData != null) ...[
                _buildInfoRow('Student Name', '${studentData['FirstName']} ${studentData['LastName']}'),
                _buildInfoRow('Student ID', studentData['StudentID'] ?? 'Not available'),
                _buildInfoRow('Course', studentData['Course'] ?? 'Not available'),
                _buildInfoRow('Year Level', studentData['YearLevel']?.toString() ?? 'Not available'),
                _buildInfoRow('UB Mail', studentData['UBmail'] ?? 'Not available'),
              ] else ...[
                const Text('Student information not available', style: TextStyle(color: Colors.grey)),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Future<void> _showEditParentName() async {
    _parentNameController.text = widget.userData['parentName'] ?? '';

    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit Parent Name'),
        content: TextField(
          controller: _parentNameController,
          decoration: const InputDecoration(
            labelText: 'Parent Name',
            hintText: 'Enter your name',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF862334)),
            onPressed: () async {
              if (_parentNameController.text.trim().isNotEmpty) {
                await _updateParentName(_parentNameController.text.trim());
                Navigator.pop(context);
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Please enter a valid name')),
                );
              }
            },
            child: const Text('Save', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Future<void> _updateParentName(String newName) async {
    try {
      setState(() {
        _isLoading = true;
      });

      await _firestoreService.updateParentName(widget.userId, newName);

      // Update local user data
      widget.userData['parentName'] = newName;

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Parent name updated successfully!')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error updating name: $e')),
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

  void _showNotificationSettings() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Notification Settings'),
        content: const SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Configure your notification preferences:'),
              SizedBox(height: 16),
              Text('• Emergency Alerts'),
              Text('• Zone Entry/Exit Notifications'),
              Text('• Location Updates'),
              Text('• System Notifications'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  void _showPrivacySecurity() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Privacy & Security'),
        content: const SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Privacy and Security Settings:'),
              SizedBox(height: 16),
              Text('• Data Collection'),
              Text('• Location Sharing'),
              Text('• Account Security'),
              Text('• Privacy Controls'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  void _showHelpSupport() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Help & Support'),
        content: const SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Need help? Contact us:'),
              SizedBox(height: 16),
              Text('📧 Email: support@ubsafestep.com'),
              Text('📞 Phone: +1 (555) 123-4567'),
              Text('🕒 Hours: 9AM - 5PM Mon-Fri'),
              SizedBox(height: 16),
              Text('Common Issues:'),
              Text('• Location not updating'),
              Text('• Safezone alerts'),
              Text('• Account access'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  void _showReportIssue() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Report Issue'),
        content: const SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Report bugs or issues:'),
              SizedBox(height: 16),
              Text('Please describe the issue you\'re experiencing:'),
              SizedBox(height: 8),
              Text('• What were you doing when it happened?'),
              Text('• What did you expect to happen?'),
              Text('• What actually happened?'),
              SizedBox(height: 16),
              Text('You can email details to: support@ubsafestep.com'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              '$label:',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final primaryColor = const Color(0xFF862334);
    final accentColor = const Color(0xFFFFC553);

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
                  'Settings',
                  style: TextStyle(color: Colors.white),
                ),
              ),
            ),
            const SizedBox(width: 40),
          ],
        ),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // User Info Card
          Card(
            elevation: 2,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      CircleAvatar(
                        backgroundColor: primaryColor.withOpacity(0.1),
                        radius: 24,
                        child: Icon(Icons.person, color: primaryColor),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.userData['parentName'] ?? 'Parent Account',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              widget.userData['UBMail'] ?? 'Parent Account',
                              style: TextStyle(
                                color: Colors.grey[600],
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  ElevatedButton(
                    onPressed: _showAccountInfo,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.grey[100],
                      foregroundColor: Colors.black87,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: const Text('View Account Details'),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Settings Options
          Card(
            elevation: 2,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              children: [
                ListTile(
                  leading: Icon(Icons.person, color: primaryColor),
                  title: const Text('Account Settings'),
                  subtitle: const Text('Manage your account information'),
                  trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                  onTap: _showEditParentName,
                ),
                const Divider(height: 1),
                ListTile(
                  leading: Icon(Icons.notifications, color: accentColor),
                  title: const Text('Notifications'),
                  subtitle: const Text('Notification preferences and alerts'),
                  trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                  onTap: _showNotificationSettings,
                ),
                const Divider(height: 1),
                ListTile(
                  leading: Icon(Icons.security, color: Colors.blue),
                  title: const Text('Privacy & Security'),
                  subtitle: const Text('Manage privacy and security settings'),
                  trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                  onTap: _showPrivacySecurity,
                ),
                const Divider(height: 1),
                ListTile(
                  leading: Icon(Icons.help, color: Colors.orange),
                  title: const Text('Help & Support'),
                  subtitle: const Text('Get help and contact support'),
                  trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                  onTap: _showHelpSupport,
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // About Section
          Card(
            elevation: 2,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              children: [
                ListTile(
                  leading: Icon(Icons.info, color: primaryColor),
                  title: const Text('About UBSafestep'),
                  subtitle: const Text('App version and developer info'),
                  trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                  onTap: () {
                    showAboutDialog(
                      context: context,
                      applicationName: 'UBSafestep',
                      applicationVersion: '1.0.0',
                      applicationIcon: Icon(Icons.location_on, color: primaryColor),
                      children: [
                        const SizedBox(height: 16),
                        const Text(
                          'Parental Monitoring System\n\n'
                              'Features:\n'
                              '• Real-time student location tracking\n'
                              '• Safe zone monitoring\n'
                              '• Emergency alerts\n'
                              '• Location history\n\n'
                              'Developed for University of Batangas\n'
                              'For demonstration purposes',
                          textAlign: TextAlign.left,
                          style: TextStyle(fontSize: 14),
                        ),
                      ],
                    );
                  },
                ),
                const Divider(height: 1),
                ListTile(
                  leading: Icon(Icons.bug_report, color: Colors.red),
                  title: const Text('Report Issue'),
                  subtitle: const Text('Report bugs or issues'),
                  trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                  onTap: _showReportIssue,
                ),
              ],
            ),
          ),
          const SizedBox(height: 32),

          // Logout Button
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: ElevatedButton.icon(
              onPressed: _isLoading ? null : _showLogoutConfirmation,
              icon: _isLoading
                  ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              )
                  : const Icon(Icons.logout),
              label: Text(_isLoading ? 'LOGGING OUT...' : 'LOG OUT'),
              style: ElevatedButton.styleFrom(
                backgroundColor: primaryColor,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 2,
              ),
            ),
          ),
          const SizedBox(height: 16),

          // App Version
          const Center(
            child: Text(
              'UBSafestep v1.0.0',
              style: TextStyle(
                color: Colors.grey,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }
}