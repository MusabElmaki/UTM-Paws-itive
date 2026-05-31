import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../theme/app_theme.dart';

// ============================================================================
// FIREBASE DATA MODEL
// ============================================================================

enum NotificationType {
  straySighting,
  reportUpdate,
  pointsEarned,
  animalRescued,
  friendRequest,
  achievement,
}

class FirestoreNotification {
  final String id;
  final String title;
  final String description;
  final NotificationType type;
  final DateTime timestamp;
  final bool isRead;
  final String? relatedReportId;

  FirestoreNotification({
    required this.id,
    required this.title,
    required this.description,
    required this.type,
    required this.timestamp,
    this.isRead = false,
    this.relatedReportId,
  });

  factory FirestoreNotification.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return FirestoreNotification(
      id: doc.id,
      title: data['title'] ?? 'Notification',
      description: data['description'] ?? '',
      type: _parseNotificationType(data['type'] ?? 'straySighting'),
      timestamp: (data['timestamp'] as Timestamp?)?.toDate() ?? DateTime.now(),
      isRead: data['isRead'] ?? false,
      relatedReportId: data['relatedReportId'],
    );
  }

  static NotificationType _parseNotificationType(String typeString) {
    switch (typeString) {
      case 'straySighting':
        return NotificationType.straySighting;
      case 'reportUpdate':
        return NotificationType.reportUpdate;
      case 'pointsEarned':
        return NotificationType.pointsEarned;
      case 'animalRescued':
        return NotificationType.animalRescued;
      case 'friendRequest':
        return NotificationType.friendRequest;
      case 'achievement':
        return NotificationType.achievement;
      default:
        return NotificationType.straySighting;
    }
  }
}

// Helper function to group notifications by date
Map<String, List<FirestoreNotification>> groupNotificationsByDate(
  List<FirestoreNotification> notifications,
) {
  final Map<String, List<FirestoreNotification>> grouped = {};
  final now = DateTime.now();

  for (var notification in notifications) {
    final date = notification.timestamp;
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = DateTime(now.year, now.month, now.day - 1);
    final twoDaysAgo = DateTime(now.year, now.month, now.day - 2);
    final threeDaysAgo = DateTime(now.year, now.month, now.day - 3);

    final notifDate = DateTime(date.year, date.month, date.day);

    String groupKey;
    if (notifDate == today) {
      groupKey = 'Today';
    } else if (notifDate == yesterday) {
      groupKey = 'Yesterday';
    } else if (notifDate == twoDaysAgo) {
      groupKey = '2 Days Ago';
    } else if (notifDate == threeDaysAgo) {
      groupKey = '3 Days Ago';
    } else {
      groupKey = '${date.month}/${date.day}/${date.year}';
    }

    if (!grouped.containsKey(groupKey)) {
      grouped[groupKey] = [];
    }
    grouped[groupKey]!.add(notification);
  }

  return grouped;
}

// ============================================================================
// UI SCREEN
// ============================================================================

class NotificationCenterScreen extends StatefulWidget {
  const NotificationCenterScreen({super.key});

  @override
  State<NotificationCenterScreen> createState() =>
      _NotificationCenterScreenState();
}

class _NotificationCenterScreenState extends State<NotificationCenterScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // Mark all notifications as read
  Future<void> _markAllAsRead() async {
    try {
      final notifications = await _firestore
          .collection('notifications')
          .where('isRead', isEqualTo: false)
          .get();

      for (var doc in notifications.docs) {
        await doc.reference.update({'isRead': true});
      }
    } catch (e) {
      print('Error marking all as read: $e');
    }
  }

  // Mark single notification as read
  Future<void> _markNotificationAsRead(String notificationId) async {
    try {
      await _firestore.collection('notifications').doc(notificationId).update({
        'isRead': true,
      });
    } catch (e) {
      print('Error marking notification as read: $e');
    }
  }

  // Delete notification
  Future<void> _deleteNotification(String notificationId) async {
    try {
      await _firestore.collection('notifications').doc(notificationId).delete();
    } catch (e) {
      print('Error deleting notification: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16.0),
            child: Center(
              child: Tooltip(
                message: 'Mark all as read',
                child: InkWell(
                  onTap: _markAllAsRead,
                  child: const Icon(Icons.done_all),
                ),
              ),
            ),
          ),
        ],
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: _firestore
            .collection('notifications')
            .where('userId', isEqualTo: _auth.currentUser?.uid ?? '')
            .orderBy('timestamp', descending: true)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return Center(
              child: CircularProgressIndicator(color: AppTheme.primary),
            );
          }

          if (snapshot.hasError) {
            return Center(
              child: Text(
                'Error loading notifications',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            );
          }

          final docs = snapshot.data?.docs ?? [];
          final notifications = docs
              .map((doc) => FirestoreNotification.fromFirestore(doc))
              .toList();

          if (notifications.isEmpty) {
            return _buildEmptyState(context);
          }

          final groupedNotifications = groupNotificationsByDate(notifications);
          final sortedKeys = groupedNotifications.keys.toList();

          return ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: sortedKeys.length,
            itemBuilder: (context, groupIndex) {
              final groupKey = sortedKeys[groupIndex];
              final groupNotifications = groupedNotifications[groupKey]!;

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Date Header
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    child: Text(
                      groupKey,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: AppTheme.text.withOpacity(0.7),
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                  // Notifications in group
                  ...groupNotifications.map(
                    (notif) => _buildNotificationItem(notif, context),
                  ),
                  const SizedBox(height: 8),
                ],
              );
            },
          );
        },
      ),
    );
  }

  // Empty state
  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.notifications_none,
            size: 64,
            color: AppTheme.text.withOpacity(0.3),
          ),
          const SizedBox(height: 16),
          Text(
            'No notifications yet',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: AppTheme.text.withOpacity(0.5),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'You\'re all caught up!',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: AppTheme.text.withOpacity(0.4),
            ),
          ),
        ],
      ),
    );
  }

  // Individual notification item
  Widget _buildNotificationItem(
    FirestoreNotification notification,
    BuildContext context,
  ) {
    return GestureDetector(
      onTap: () {
        if (!notification.isRead) {
          _markNotificationAsRead(notification.id);
        }
        // TODO: Navigate to specific report if relatedReportId exists
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Opening ${notification.relatedReportId ?? 'notification'}...',
            ),
            duration: const Duration(milliseconds: 800),
          ),
        );
      },
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: notification.isRead
              ? Colors.white
              : AppTheme.primary.withOpacity(0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: notification.isRead
                ? AppTheme.border
                : AppTheme.primary.withOpacity(0.3),
            width: notification.isRead ? 0.5 : 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.03),
              blurRadius: 4,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Notification Icon
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: _getNotificationIconBackgroundColor(notification.type),
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Icon(
                  _getNotificationIcon(notification.type),
                  color: Colors.white,
                  size: 24,
                ),
              ),
            ),
            const SizedBox(width: 12),
            // Notification Content
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          notification.title,
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(
                                fontWeight: notification.isRead
                                    ? FontWeight.w600
                                    : FontWeight.w800,
                                fontSize: notification.isRead ? 14 : 15,
                              ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (!notification.isRead)
                        Container(
                          width: 10,
                          height: 10,
                          margin: const EdgeInsets.only(left: 8),
                          decoration: const BoxDecoration(
                            color: AppTheme.primary,
                            shape: BoxShape.circle,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    notification.description,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: AppTheme.text.withOpacity(0.7),
                      height: 1.4,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _formatTime(notification.timestamp),
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: AppTheme.text.withOpacity(0.5),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            // More Action
            PopupMenuButton<String>(
              onSelected: (String result) {
                if (result == 'mark_read') {
                  _markNotificationAsRead(notification.id);
                } else if (result == 'delete') {
                  _deleteNotification(notification.id);
                }
              },
              itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
                const PopupMenuItem<String>(
                  value: 'mark_read',
                  child: Text('Mark as read'),
                ),
                const PopupMenuItem<String>(
                  value: 'delete',
                  child: Text('Delete'),
                ),
              ],
              child: Icon(
                Icons.more_vert,
                color: AppTheme.text.withOpacity(0.5),
                size: 20,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Get icon for notification type
  IconData _getNotificationIcon(NotificationType type) {
    switch (type) {
      case NotificationType.straySighting:
        return Icons.location_on;
      case NotificationType.reportUpdate:
        return Icons.info;
      case NotificationType.pointsEarned:
        return Icons.star;
      case NotificationType.animalRescued:
        return Icons.check_circle;
      case NotificationType.friendRequest:
        return Icons.person_add;
      case NotificationType.achievement:
        return Icons.emoji_events;
    }
  }

  // Get background color for notification icon
  Color _getNotificationIconBackgroundColor(NotificationType type) {
    switch (type) {
      case NotificationType.straySighting:
        return const Color(0xFF6B4226); // Brown
      case NotificationType.reportUpdate:
        return const Color(0xFF1565C0); // Blue
      case NotificationType.pointsEarned:
        return const Color(0xFFF57C00); // Orange
      case NotificationType.animalRescued:
        return AppTheme.success;
      case NotificationType.friendRequest:
        return const Color(0xFFD81B60); // Pink
      case NotificationType.achievement:
        return const Color(0xFF7B1FA2); // Purple
    }
  }

  // Format time to human readable
  String _formatTime(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);

    if (difference.inMinutes < 1) {
      return 'now';
    } else if (difference.inMinutes < 60) {
      return '${difference.inMinutes}m ago';
    } else if (difference.inHours < 24) {
      return '${difference.inHours}h ago';
    } else if (difference.inDays < 7) {
      return '${difference.inDays}d ago';
    } else {
      return '${dateTime.month}/${dateTime.day}';
    }
  }
}
