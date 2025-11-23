import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../services/firestore_service.dart';

class NotificationsScreen extends StatefulWidget {
  final Map<String, dynamic> userData;
  final String userId;

  const NotificationsScreen({
    Key? key,
    required this.userData,
    required this.userId,
  }) : super(key: key);

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  final FirestoreService _firestoreService = FirestoreService();
  List<Map<String, dynamic>> _notifications = [];
  List<Map<String, dynamic>> _filteredNotifications = [];
  bool _isLoading = true;
  String _currentFilter = 'All';

  @override
  void initState() {
    super.initState();
    _loadNotifications();
  }

  Future<void> _loadNotifications() async {
    try {
      final notifications = await _firestoreService.getParentNotifications(widget.userId);
      setState(() {
        _notifications = notifications;
        _filteredNotifications = notifications;
        _isLoading = false;
      });
    } catch (e) {
      print('Error loading notifications: $e');
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _filterNotifications(String filter) {
    setState(() {
      _currentFilter = filter;
      if (filter == 'All') {
        _filteredNotifications = _notifications;
      } else if (filter == 'Emergency') {
        _filteredNotifications = _notifications
            .where((notification) => notification['EmergencySOS'] == true)
            .toList();
      } else if (filter == 'Zone Alerts') {
        _filteredNotifications = _notifications
            .where((notification) =>
        notification['EmergencySOS'] == false &&
            notification['Message']?.toString().toLowerCase().contains('zone') == true)
            .toList();
      } else if (filter == 'Movement') {
        _filteredNotifications = _notifications
            .where((notification) =>
        notification['EmergencySOS'] == false &&
            notification['Message']?.toString().toLowerCase().contains('left') == true ||
            notification['Message']?.toString().toLowerCase().contains('entered') == true)
            .toList();
      }
    });
  }

  Future<void> _markAllAsRead() async {
    try {
      for (final notification in _notifications) {
        if (notification['isRead'] != true) {
          await _firestoreService.markNotificationAsRead(notification['NotificationID']);
        }
      }

      // Reload notifications to reflect changes
      await _loadNotifications();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('All notifications marked as read')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error marking notifications as read: $e')),
        );
      }
    }
  }

  Future<void> _markAsRead(String notificationId) async {
    try {
      await _firestoreService.markNotificationAsRead(notificationId);

      // Update local state
      setState(() {
        final index = _notifications.indexWhere((n) => n['NotificationID'] == notificationId);
        if (index != -1) {
          _notifications[index]['isRead'] = true;
        }

        final filteredIndex = _filteredNotifications.indexWhere((n) => n['NotificationID'] == notificationId);
        if (filteredIndex != -1) {
          _filteredNotifications[filteredIndex]['isRead'] = true;
        }
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Notification marked as read')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error marking notification as read: $e')),
        );
      }
    }
  }

  Future<void> _refreshNotifications() async {
    setState(() {
      _isLoading = true;
    });
    await _loadNotifications();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Notifications refreshed')),
      );
    }
  }

  String _getNotificationType(Map<String, dynamic> notification) {
    if (notification['EmergencySOS'] == true) {
      return 'Emergency';
    }

    final message = notification['Message']?.toString().toLowerCase() ?? '';
    if (message.contains('zone')) {
      return 'Zone Alerts';
    } else if (message.contains('left') || message.contains('entered')) {
      return 'Movement';
    }

    return 'General';
  }

  Color _getNotificationColor(String type, Map<String, dynamic> notification) {
    if (type == 'Emergency') {
      return Colors.red;
    }
    
    final message = notification['Message']?.toString().toLowerCase() ?? '';
    
    if (message.contains('entered')) {
      return Colors.green; // Entering safezone is green
    } else if (message.contains('outside') || message.contains('left')) {
      return Colors.orange; // Leaving or outside is orange
    } else if (type == 'Zone Alerts') {
      return Colors.orange;
    } else if (type == 'Movement') {
      return Colors.blue;
    }
    
    return Colors.grey;
  }

  IconData _getNotificationIcon(String type, Map<String, dynamic> notification) {
    if (type == 'Emergency') {
      return Icons.warning_rounded;
    }
    
    final message = notification['Message']?.toString().toLowerCase() ?? '';
    
    if (message.contains('entered')) {
      return Icons.location_on; // Safe inside
    } else if (message.contains('outside') || message.contains('left')) {
      return Icons.wrong_location; // Outside/Left
    }
    
    switch (type) {
      case 'Zone Alerts':
        return Icons.location_on;
      case 'Movement':
        return Icons.directions_walk;
      default:
        return Icons.notifications;
    }
  }

  String _formatTimestamp(dynamic timestamp) {
    if (timestamp == null) return 'Unknown time';

    if (timestamp is Timestamp) {
      final date = timestamp.toDate();
      return '${date.hour}:${date.minute.toString().padLeft(2, '0')} - ${date.day}/${date.month}/${date.year}';
    }

    return timestamp.toString();
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
                  'Notifications',
                  style: TextStyle(color: Colors.white),
                ),
              ),
            ),
            const SizedBox(width: 40),
          ],
        ),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: IconButton(
              icon: const Icon(Icons.done_all),
              onPressed: _markAllAsRead,
              tooltip: 'Mark all as read',
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          // Filter chips
          Container(
            height: 60,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                _buildFilterChip('All', _currentFilter == 'All', primaryColor),
                const SizedBox(width: 8),
                _buildFilterChip('Emergency', _currentFilter == 'Emergency', Colors.red),
                const SizedBox(width: 8),
                _buildFilterChip('Zone Alerts', _currentFilter == 'Zone Alerts', Colors.orange),
                const SizedBox(width: 8),
                _buildFilterChip('Movement', _currentFilter == 'Movement', Colors.blue),
              ],
            ),
          ),

          // Notifications list
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _filteredNotifications.isEmpty
                ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.notifications_off, size: 64, color: Colors.grey),
                  SizedBox(height: 16),
                  Text(
                    'No notifications',
                    style: TextStyle(
                      fontSize: 18,
                      color: Colors.grey,
                    ),
                  ),
                ],
              ),
            )
                : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _filteredNotifications.length,
              itemBuilder: (context, index) {
                final notification = _filteredNotifications[index];
                final notificationType = _getNotificationType(notification);
                final notifColor = _getNotificationColor(notificationType, notification);
                final notifIcon = _getNotificationIcon(notificationType, notification);
                final isRead = notification['isRead'] == true;

                return Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.05),
                        blurRadius: 10,
                        offset: const Offset(0, 2),
                      ),
                    ],
                    border: isRead
                        ? null
                        : Border.all(color: notifColor.withOpacity(0.5)),
                  ),
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    leading: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: notifColor.withOpacity(0.1),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(notifIcon, color: notifColor),
                    ),
                    title: Text(
                      notification['Message'] ?? 'Notification',
                      style: TextStyle(
                        fontWeight: isRead
                            ? FontWeight.normal
                            : FontWeight.bold,
                        color: const Color(0xFF222222),
                      ),
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 4),
                        Text(
                          notificationType,
                          style: TextStyle(
                            fontSize: 12,
                            color: notifColor,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _formatTimestamp(notification['Timestamp']),
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                    trailing: IconButton(
                      icon: Icon(
                        isRead
                            ? Icons.more_vert
                            : Icons.check_circle_outline,
                        color: isRead
                            ? Colors.grey
                            : primaryColor,
                      ),
                      onPressed: () {
                        if (!isRead) {
                          _markAsRead(notification['NotificationID']);
                        } else {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Notification options'),
                            ),
                          );
                        }
                      },
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _refreshNotifications,
        backgroundColor: accentColor,
        child: const Icon(Icons.refresh, color: Colors.black87),
        tooltip: 'Refresh notifications',
      ),
    );
  }

  Widget _buildFilterChip(String label, bool isSelected, Color color) {
    return FilterChip(
      label: Text(
        label,
        style: TextStyle(
          color: isSelected ? Colors.white : Colors.black87,
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
        ),
      ),
      selected: isSelected,
      selectedColor: color,
      backgroundColor: Colors.white,
      checkmarkColor: Colors.white,
      elevation: 1,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      onSelected: (bool selected) {
        if (selected) {
          _filterNotifications(label);
        }
      },
    );
  }
}
