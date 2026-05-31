import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../theme/app_theme.dart';

// ============================================================================
// FIREBASE DATA MODEL
// ============================================================================

class VolunteerUser {
  final String id;
  final String name;
  final int points;
  final String avatarUrl;
  final bool isCurrentUser;
  final int rank;

  VolunteerUser({
    required this.id,
    required this.name,
    required this.points,
    required this.avatarUrl,
    required this.isCurrentUser,
    required this.rank,
  });

  factory VolunteerUser.fromFirestore(
    DocumentSnapshot doc,
    int rank,
    String currentUserId,
  ) {
    final data = doc.data() as Map<String, dynamic>;
    return VolunteerUser(
      id: doc.id,
      name: data['name'] ?? 'Unknown User',
      points: data['points'] ?? 0,
      avatarUrl: data['avatarUrl'] ?? '👤',
      isCurrentUser: doc.id == currentUserId,
      rank: rank,
    );
  }
}

// ============================================================================
// UI SCREEN
// ============================================================================

class LeaderboardScreen extends StatefulWidget {
  const LeaderboardScreen({super.key});

  @override
  State<LeaderboardScreen> createState() => _LeaderboardScreenState();
}

class _LeaderboardScreenState extends State<LeaderboardScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  // Get current user's rank and data
  Future<VolunteerUser?> _getCurrentUserData() async {
    try {
      final currentUser = _auth.currentUser;
      if (currentUser == null) return null;

      final userDoc = await _firestore
          .collection('users')
          .doc(currentUser.uid)
          .get();
      if (!userDoc.exists) return null;

      // Get the rank of current user
      final allUsers = await _firestore
          .collection('users')
          .orderBy('points', descending: true)
          .get();

      int rank = 1;
      for (final doc in allUsers.docs) {
        if (doc.id == currentUser.uid) break;
        rank++;
      }

      return VolunteerUser.fromFirestore(userDoc, rank, currentUser.uid);
    } catch (e) {
      print('Error fetching current user: $e');
      return null;
    }
  }

  // Get leaderboard stream
  Stream<List<VolunteerUser>> _getLeaderboardStream() {
    return _firestore
        .collection('users')
        .orderBy('points', descending: true)
        .snapshots()
        .map((snapshot) {
          final currentUserId = _auth.currentUser?.uid ?? '';
          return snapshot.docs.asMap().entries.map((entry) {
            return VolunteerUser.fromFirestore(
              entry.value,
              entry.key + 1,
              currentUserId,
            );
          }).toList();
        });
  }

  // Filter for all-time (all users)
  Stream<List<VolunteerUser>> _getAllTimeLeaderboard() {
    return _getLeaderboardStream();
  }

  // Filter for monthly (users with recent activity)
  Stream<List<VolunteerUser>> _getMonthlyLeaderboard() {
    final thirtyDaysAgo = Timestamp.fromDate(
      DateTime.now().subtract(const Duration(days: 30)),
    );

    return _firestore
        .collection('users')
        .where('lastActivityAt', isGreaterThanOrEqualTo: thirtyDaysAgo)
        .orderBy('lastActivityAt', descending: true)
        .orderBy('points', descending: true)
        .snapshots()
        .map((snapshot) {
          final currentUserId = _auth.currentUser?.uid ?? '';
          return snapshot.docs.asMap().entries.map((entry) {
            return VolunteerUser.fromFirestore(
              entry.value,
              entry.key + 1,
              currentUserId,
            );
          }).toList();
        })
        .handleError((error) {
          // Handle case where monthly data is not available
          print('Monthly leaderboard error: $error');
          return _getLeaderboardStream();
        });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Leaderboard'), elevation: 0),
      body: SingleChildScrollView(
        child: Column(
          children: [
            // User's Own Card
            FutureBuilder<VolunteerUser?>(
              future: _getCurrentUserData(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: CircularProgressIndicator(color: AppTheme.primary),
                  );
                }

                if (snapshot.hasError || snapshot.data == null) {
                  return Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Text(
                      'Sign in to see your rank',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  );
                }

                final currentUser = snapshot.data!;
                return _buildUserCard(currentUser);
              },
            ),

            // Tab Controller for All-Time / Monthly
            TabBar(
              controller: _tabController,
              labelColor: AppTheme.primary,
              unselectedLabelColor: AppTheme.text.withOpacity(0.6),
              indicatorColor: AppTheme.primary,
              indicatorWeight: 3,
              labelStyle: Theme.of(context).textTheme.titleMedium,
              tabs: const [
                Tab(text: 'All-Time'),
                Tab(text: 'Monthly'),
              ],
            ),

            // Tab View for Leaderboard Lists
            SizedBox(
              height: MediaQuery.of(context).size.height * 0.6,
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildLeaderboardListFromStream(_getAllTimeLeaderboard()),
                  _buildLeaderboardListFromStream(_getMonthlyLeaderboard()),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // User's own card at the top
  Widget _buildUserCard(VolunteerUser user) {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [AppTheme.primary, AppTheme.secondary],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: AppTheme.primary.withOpacity(0.3),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          // Avatar
          Container(
            width: 70,
            height: 70,
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Center(
              child: Text(user.avatarUrl, style: const TextStyle(fontSize: 40)),
            ),
          ),
          const SizedBox(width: 20),
          // User Info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Your Rank',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Colors.white.withOpacity(0.9),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  user.name,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '#${user.rank}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      '${user.points} pts',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Leaderboard list view with StreamBuilder
  Widget _buildLeaderboardListFromStream(Stream<List<VolunteerUser>> stream) {
    return StreamBuilder<List<VolunteerUser>>(
      stream: stream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Center(
            child: CircularProgressIndicator(color: AppTheme.primary),
          );
        }

        if (snapshot.hasError) {
          return Center(
            child: Text(
              'Error loading leaderboard',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          );
        }

        final volunteers = snapshot.data ?? [];

        if (volunteers.isEmpty) {
          return Center(
            child: Text(
              'No users found',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: AppTheme.text.withOpacity(0.5),
              ),
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          itemCount: volunteers.length,
          itemBuilder: (context, index) {
            return _buildLeaderboardItem(volunteers[index], context);
          },
        );
      },
    );
  }

  // Individual leaderboard item
  Widget _buildLeaderboardItem(VolunteerUser volunteer, BuildContext context) {
    final isMedal = volunteer.rank <= 3;
    final medalColor = volunteer.rank == 1
        ? const Color(0xFFFFD700) // Gold
        : volunteer.rank == 2
        ? const Color(0xFFC0C0C0) // Silver
        : const Color(0xFFCD7F32); // Bronze

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: volunteer.isCurrentUser
            ? AppTheme.accent.withOpacity(0.15)
            : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: volunteer.isCurrentUser
            ? Border.all(color: AppTheme.accent, width: 1.5)
            : null,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            // Rank Badge / Medal
            if (isMedal)
              Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  color: medalColor,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: medalColor.withOpacity(0.4),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Center(
                  child: Text(
                    '${volunteer.rank}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              )
            else
              Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  color: AppTheme.background,
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Text(
                    '${volunteer.rank}',
                    style: TextStyle(
                      color: AppTheme.text,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            const SizedBox(width: 16),
            // Avatar & Name
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: AppTheme.secondary.withOpacity(0.2),
                          shape: BoxShape.circle,
                        ),
                        child: Center(
                          child: Text(
                            volunteer.avatarUrl,
                            style: const TextStyle(fontSize: 22),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          volunteer.name,
                          style: Theme.of(context).textTheme.titleMedium,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            // Points
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: AppTheme.primary.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '${volunteer.points} pts',
                style: TextStyle(
                  color: AppTheme.primary,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
