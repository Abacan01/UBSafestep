import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'main_navigation.dart';
import 'name_setup_screen.dart';
import '../services/firestore_service.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _isGoogleLoading = false;
  bool _showSignUp = false;

  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirestoreService _firestoreService = FirestoreService();
  final GoogleSignIn _googleSignIn = GoogleSignIn(
    scopes: ['email', 'profile'],
  );

  // Forgot Password Method
  Future<void> _handleForgotPassword() async {
    final email = _emailController.text.trim().toLowerCase();

    if (email.isEmpty || !_isValidUbStudentEmail(email)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter a valid UB student email address'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    try {
      await _auth.sendPasswordResetEmail(email: email);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Password reset email sent to $email'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } on FirebaseAuthException catch (e) {
      String errorMessage = 'Failed to send reset email. Please try again.';
      if (e.code == 'user-not-found') {
        errorMessage = 'No account found with this email address.';
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errorMessage),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // Account Linking Methods
  Future<void> _linkGoogleAccountToExistingUser({
    required GoogleSignInAuthentication googleAuth,
    required String userEmail,
  }) async {
    final shouldLink = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Account Found'),
        content: const Text(
          'An account already exists with this email using email/password. '
              'Would you like to link your Google account to this existing account? '
              'This will allow you to sign in with either method.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Link Accounts'),
          ),
        ],
      ),
    );

    if (shouldLink != true) {
      await _googleSignIn.signOut();
      return;
    }

    final password = await _showPasswordVerificationDialog();
    if (password == null) {
      await _googleSignIn.signOut();
      return;
    }

    try {
      final emailCredential = EmailAuthProvider.credential(
        email: userEmail,
        password: password,
      );

      final userCredential = await _auth.signInWithCredential(emailCredential);

      final googleCredential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      await userCredential.user!.linkWithCredential(googleCredential);

      await _continueToAppAfterAuth(userEmail);

    } on FirebaseAuthException catch (e) {
      if (e.code == 'wrong-password') {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Incorrect password. Please try again.'),
            backgroundColor: Colors.red,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to link accounts: ${e.message}'),
            backgroundColor: Colors.red,
          ),
        );
      }
      await _googleSignIn.signOut();
      await _auth.signOut();
    }
  }

  Future<String?> _showPasswordVerificationDialog() async {
    final passwordController = TextEditingController();

    return showDialog<String?>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Verify Your Account'),
        content: TextField(
          controller: passwordController,
          obscureText: true,
          decoration: const InputDecoration(
            labelText: 'Enter your password',
            hintText: 'Please enter your current password',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(null),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(passwordController.text),
            child: const Text('Verify'),
          ),
        ],
      ),
    );
  }

  Future<void> _proceedWithGoogleSignIn(
      GoogleSignInAuthentication googleAuth,
      String userEmail
      ) async {
    final credential = GoogleAuthProvider.credential(
      accessToken: googleAuth.accessToken,
      idToken: googleAuth.idToken,
    );

    final userCredential = await _auth.signInWithCredential(credential);

    if (userCredential.user != null && mounted) {
      await _continueToAppAfterAuth(userEmail);
    }
  }

  Future<void> _continueToAppAfterAuth(String userEmail) async {
    final existingParent = await _firestoreService.getParentGuardianByUBmail(userEmail);

    if (existingParent != null) {
      _navigateToMainNavigation(
        userData: existingParent,
        userId: existingParent['ParentGuardianID'],
      );
    } else {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => NameSetupScreen(
            userEmail: userEmail,
            studentInfo: _createStudentInfoFromEmail(userEmail),
          ),
        ),
      );
    }
  }

  // Google Sign-In with Account Linking
  void _handleGoogleSignIn() async {
    if (!mounted) return;

    setState(() {
      _isGoogleLoading = true;
    });

    try {
      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();

      if (googleUser == null) {
        setState(() {
          _isGoogleLoading = false;
        });
        return;
      }

      final GoogleSignInAuthentication googleAuth = await googleUser.authentication;
      final String userEmail = googleUser.email.toLowerCase();

      if (!_isValidUbStudentEmail(userEmail)) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Only UB student email accounts are allowed for parent access.'),
              backgroundColor: Colors.red,
              duration: Duration(seconds: 4),
            ),
          );
        }
        await _googleSignIn.signOut();
        return;
      }

      try {
        final list = await _auth.fetchSignInMethodsForEmail(userEmail);

        if (list.isNotEmpty && list.contains('password')) {
          await _linkGoogleAccountToExistingUser(
            googleAuth: googleAuth,
            userEmail: userEmail,
          );
        } else {
          await _proceedWithGoogleSignIn(googleAuth, userEmail);
        }
      } catch (error) {
        await _proceedWithGoogleSignIn(googleAuth, userEmail);
      }

    } catch (error) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Google Sign-In failed: ${error.toString()}'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isGoogleLoading = false;
        });
      }
    }
  }

  // Enhanced Password Validation Methods
  String? _validateUbStudentEmail(String? value) {
    if (value == null || value.isEmpty) {
      return 'Please enter student email';
    }

    final email = value.trim().toLowerCase();
    if (!email.contains('@') || !email.contains('.')) {
      return 'Please enter a valid email address';
    }

    if (!email.endsWith('@ub.edu.ph')) {
      return 'Only University of Batangas (@ub.edu.ph) emails are allowed';
    }

    if (!RegExp(r'^\d+@ub\.edu\.ph$').hasMatch(email)) {
      return 'Please use valid student ID email format (e.g., 202310001@ub.edu.ph)';
    }

    return null;
  }

  String? _validatePassword(String? value) {
    if (value == null || value.isEmpty) {
      return 'Please enter a password';
    }
    if (value.length < 6) {
      return 'Password must be at least 6 characters';
    }
    if (!_containsSpecialCharacter(value)) {
      return 'Password must include at least one special character (!@#\$%^&* etc.)';
    }
    return null;
  }

  String? _validateConfirmPassword(String? value) {
    if (value == null || value.isEmpty) {
      return 'Please confirm your password';
    }
    if (value != _passwordController.text) {
      return 'Passwords do not match';
    }
    return null;
  }

  bool _containsSpecialCharacter(String password) {
    final specialCharRegex = RegExp(r'[!@#$%^&*(),.?":{}|<>]');
    return specialCharRegex.hasMatch(password);
  }

  Map<String, dynamic> _createStudentInfoFromEmail(String email) {
    final studentId = email.split('@').first;
    return {
      'studentName': 'Student $studentId',
      'course': 'University of Batangas',
      'studentId': studentId,
    };
  }

  // Email/Password Sign Up
  void _handleSignUp() async {
    if (!mounted) return;

    final String email = _emailController.text.trim().toLowerCase();
    final String password = _passwordController.text;
    final String confirmPassword = _confirmPasswordController.text;

    final emailValidation = _validateUbStudentEmail(email);
    if (emailValidation != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(emailValidation),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final passwordValidation = _validatePassword(password);
    if (passwordValidation != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(passwordValidation),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    if (password != confirmPassword) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Passwords do not match'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final existingParent = await _firestoreService.getParentGuardianByUBmail(email);

      if (existingParent != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('An account with this email already exists. Please login instead.'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      final UserCredential userCredential = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );

      if (userCredential.user != null && mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => NameSetupScreen(
              userEmail: email,
              studentInfo: _createStudentInfoFromEmail(email),
            ),
          ),
        );
      }
    } on FirebaseAuthException catch (e) {
      String errorMessage = 'Sign up failed. Please try again.';
      if (e.code == 'email-already-in-use') {
        errorMessage = 'An account with this email already exists. Please login instead.';
      } else if (e.code == 'weak-password') {
        errorMessage = 'Password is too weak. Please use a stronger password.';
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(errorMessage),
          backgroundColor: Colors.red,
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Sign up failed: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  // Email/Password Login
  void _handleLogin() async {
    if (!mounted) return;

    final String email = _emailController.text.trim().toLowerCase();
    final String password = _passwordController.text;

    final emailValidation = _validateUbStudentEmail(email);
    if (emailValidation != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(emailValidation),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    if (password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter your password'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final UserCredential userCredential = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );

      if (userCredential.user != null && mounted) {
        final existingParent = await _firestoreService.getParentGuardianByUBmail(email);

        if (existingParent != null) {
          _navigateToMainNavigation(
            userData: existingParent,
            userId: existingParent['ParentGuardianID'],
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Account data not found. Please contact support.'),
              backgroundColor: Colors.red,
            ),
          );
          await _auth.signOut();
        }
      }
    } on FirebaseAuthException catch (e) {
      String errorMessage = 'Login failed. Please try again.';
      if (e.code == 'user-not-found' || e.code == 'wrong-password') {
        errorMessage = 'Invalid email or password.';
      } else if (e.code == 'too-many-requests') {
        errorMessage = 'Too many login attempts. Please try again later.';
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(errorMessage),
          backgroundColor: Colors.red,
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Login failed: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  // Navigation
  void _navigateToMainNavigation({
    required Map<String, dynamic> userData,
    required String userId,
  }) {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (context) => MainNavigation(
          userData: userData,
          userId: userId,
        ),
      ),
    );
  }

  bool _isValidUbStudentEmail(String email) {
    final String cleanEmail = email.trim().toLowerCase();
    return cleanEmail.endsWith('@ub.edu.ph') &&
        RegExp(r'^\d+@ub\.edu\.ph$').hasMatch(cleanEmail);
  }

  void _toggleSignUp() {
    setState(() {
      _showSignUp = !_showSignUp;
      _passwordController.clear();
      _confirmPasswordController.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Image.asset(
                'asset/New UBsafestep.png',
                width: 400,
                height: 300,
              ),
              Text(
                'UBSafestep',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: theme.colorScheme.primary,
                ),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFF862334).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  'Parental Monitoring System',
                  style: TextStyle(
                    fontSize: 12,
                    color: Color(0xFF862334),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              const SizedBox(height: 32),

              // Student Email Field
              TextFormField(
                controller: _emailController,
                decoration: InputDecoration(
                  labelText: 'Student UBmail',
                  prefixIcon: const Icon(Icons.school_outlined),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  hintText: '2000118@ub.edu.ph',
                ),
                keyboardType: TextInputType.emailAddress,
                autovalidateMode: AutovalidateMode.onUserInteraction,
                validator: _validateUbStudentEmail,
              ),
              const SizedBox(height: 16),

              // Password Field
              TextFormField(
                controller: _passwordController,
                obscureText: _obscurePassword,
                decoration: InputDecoration(
                  labelText: 'Password',
                  prefixIcon: const Icon(Icons.lock_outline),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscurePassword ? Icons.visibility_off : Icons.visibility,
                      color: Colors.grey,
                    ),
                    onPressed: () {
                      setState(() {
                        _obscurePassword = !_obscurePassword;
                      });
                    },
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  hintText: _showSignUp ? 'Create a password (min. 6 chars with special character)' : 'Enter your password',
                ),
                validator: _showSignUp ? _validatePassword : null,
              ),
              const SizedBox(height: 16),

              // Confirm Password Field (only for signup)
              if (_showSignUp) ...[
                TextFormField(
                  controller: _confirmPasswordController,
                  obscureText: _obscurePassword,
                  decoration: InputDecoration(
                    labelText: 'Confirm Password',
                    prefixIcon: const Icon(Icons.lock_outline),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    hintText: 'Confirm your password',
                  ),
                  validator: _showSignUp ? _validateConfirmPassword : null,
                ),
                const SizedBox(height: 16),
              ],

              // Forgot Password Button (only for login)
              if (!_showSignUp) ...[
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: _handleForgotPassword,
                    child: const Text(
                      'Forgot Password?',
                      style: TextStyle(
                        color: Color(0xFF862334),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
              ],

              // Login/Signup Button
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : (_showSignUp ? _handleSignUp : _handleLogin),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF862334),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: _isLoading
                      ? const CircularProgressIndicator(
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  )
                      : Text(
                    _showSignUp ? 'Create Account' : 'Login as Parent',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.2,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Toggle between Login and Signup
              TextButton(
                onPressed: _toggleSignUp,
                child: Text(
                  _showSignUp
                      ? 'Already have an account? Login here'
                      : 'Don\'t have an account? Sign up here',
                  style: const TextStyle(
                    color: Color(0xFF862334),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // Divider
              Row(
                children: [
                  Expanded(
                    child: Divider(
                      color: Colors.grey[400],
                      thickness: 1,
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Text(
                      'OR',
                      style: TextStyle(
                        color: Colors.grey[600],
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Divider(
                      color: Colors.grey[400],
                      thickness: 1,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Google Sign-In Button
              SizedBox(
                width: double.infinity,
                height: 50,
                child: OutlinedButton(
                  onPressed: _isGoogleLoading ? null : _handleGoogleSignIn,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.black87,
                    backgroundColor: Colors.white,
                    side: const BorderSide(color: Color(0xFF862334)),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 1,
                  ),
                  child: _isGoogleLoading
                      ? const CircularProgressIndicator(
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.blue),
                  )
                      : Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Image.asset(
                        'asset/GoogleLogo.png',
                        width: 60,
                        height: 60,
                        errorBuilder: (context, error, stackTrace) =>
                        const Icon(Icons.account_circle, color: Colors.blue),
                      ),
                      const SizedBox(width: 9),
                      const Text(
                        'Google Sign-In',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}