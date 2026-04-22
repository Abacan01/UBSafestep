import 'package:flutter/material.dart';
import 'package:audioplayers/audioplayers.dart';
import 'dart:async';

class SOSAlertService {
  static final SOSAlertService _instance = SOSAlertService._internal();
  factory SOSAlertService() => _instance;
  SOSAlertService._internal();

  AudioPlayer? _audioPlayer;
  OverlayEntry? _overlayEntry;
  bool _isShowing = false;
  bool _isPlayingSound = false;
  Timer? _soundTimer;

  // Show SOS alert overlay on any screen
  void showSOSAlert(BuildContext context) {
    if (_isShowing) {
      print('🚨 [SOS] Alert already showing');
      return;
    }

    print('🚨 [SOS] Showing emergency alert');
    _isShowing = true;

    // Create overlay entry
    _overlayEntry = OverlayEntry(
      builder: (context) => _SOSAlertOverlay(
        onDismiss: () => dismissSOSAlert(),
      ),
    );

    // Insert overlay
    Overlay.of(context).insert(_overlayEntry!);

    // Start playing emergency sound
    _playEmergencySound();
  }

  // Dismiss SOS alert
  void dismissSOSAlert() {
    if (!_isShowing) return;

    print('🚨 [SOS] Dismissing emergency alert');
    _isShowing = false;
    _stopEmergencySound();
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  // Play emergency sound repeatedly
  Future<void> _playEmergencySound() async {
    if (_isPlayingSound) return;

    _isPlayingSound = true;
    
    try {
      _audioPlayer ??= AudioPlayer();
      await _audioPlayer!.setReleaseMode(ReleaseMode.loop);
      
      // Try to play custom emergency sound if available
      // To add a custom sound:
      // 1. Create assets/sounds/ directory
      // 2. Add emergency.mp3 or emergency.wav file
      // 3. Update pubspec.yaml assets section to include: - assets/sounds/
      try {
        await _audioPlayer!.play(AssetSource('sounds/emergency.mp3'), volume: 1.0);
        print('🔊 [SOS] Playing custom emergency sound');
      } catch (e) {
        // If custom sound doesn't exist, try alternative formats or use system sound
        try {
          await _audioPlayer!.play(AssetSource('sounds/emergency.wav'), volume: 1.0);
          print('🔊 [SOS] Playing emergency sound (wav)');
        } catch (e2) {
          print('⚠️ [SOS] Custom sound file not found. Add emergency.mp3 to assets/sounds/ for audio alert.');
          print('⚠️ [SOS] Visual alert is active. Sound will be added when audio file is provided.');
        }
      }
    } catch (e) {
      print('❌ [SOS] Error initializing audio player: $e');
      print('⚠️ [SOS] Visual alert is active. Sound requires audio file setup.');
    }
  }

  // Stop emergency sound
  void _stopEmergencySound() {
    _isPlayingSound = false;
    _soundTimer?.cancel();
    _audioPlayer?.stop();
  }

  // Check if alert is currently showing
  bool get isShowing => _isShowing;
}

// SOS Alert Overlay Widget
class _SOSAlertOverlay extends StatefulWidget {
  final VoidCallback onDismiss;

  const _SOSAlertOverlay({required this.onDismiss});

  @override
  State<_SOSAlertOverlay> createState() => _SOSAlertOverlayState();
}

class _SOSAlertOverlayState extends State<_SOSAlertOverlay>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.1).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: Curves.easeInOut,
      ),
    );
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withOpacity(0.7),
      child: GestureDetector(
        onTap: widget.onDismiss,
        child: Container(
          width: double.infinity,
          height: double.infinity,
          color: Colors.red.withOpacity(0.3),
          child: Center(
            child: GestureDetector(
              onTap: () {}, // Prevent dismissing when tapping the alert itself
              child: AnimatedBuilder(
                animation: _pulseAnimation,
                builder: (context, child) {
                  return Transform.scale(
                    scale: _pulseAnimation.value,
                    child: Container(
                      margin: const EdgeInsets.all(32),
                      padding: const EdgeInsets.all(32),
                      decoration: BoxDecoration(
                        color: Colors.red,
                        borderRadius: BorderRadius.circular(24),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.red.withOpacity(0.5),
                            blurRadius: 30,
                            spreadRadius: 10,
                          ),
                        ],
                      ),
                      child: Stack(
                        children: [
                          Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // SOS Icon
                              Container(
                                padding: const EdgeInsets.all(20),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.warning_rounded,
                                  size: 64,
                                  color: Colors.red,
                                ),
                              ),
                              const SizedBox(height: 24),
                              // Emergency Message
                              const Text(
                                '🚨 EMERGENCY ALERT 🚨',
                                style: TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                  letterSpacing: 2,
                                ),
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 16),
                              const Text(
                                'Student needs immediate assistance!',
                                style: TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white,
                                ),
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 32),
                              // Dismiss Button
                              ElevatedButton(
                                onPressed: widget.onDismiss,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.white,
                                  foregroundColor: Colors.red,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 32,
                                    vertical: 16,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                                child: const Text(
                                  'ACKNOWLEDGE',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          // X Button in top-right corner
                          Positioned(
                            top: 0,
                            right: 0,
                            child: IconButton(
                              onPressed: widget.onDismiss,
                              icon: const Icon(
                                Icons.close,
                                color: Colors.white,
                                size: 28,
                              ),
                              style: IconButton.styleFrom(
                                backgroundColor: Colors.white.withOpacity(0.2),
                                padding: const EdgeInsets.all(8),
                              ),
                              tooltip: 'Close',
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}

