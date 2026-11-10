import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:geolocator/geolocator.dart';
import 'dart:math';
import 'user_course_detail_screen.dart';

// 문정욱 수정 2026-05-19
class CourseModel {
  final String id;
  final String name;
  final String description;
  final double distanceKm;
  final int estimatedMinutes;
  final String type;
  final List<LatLng> points;

  CourseModel({
    required this.id,
    required this.name,
    required this.description,
    required this.distanceKm,
    required this.estimatedMinutes,
    required this.type,
    required this.points,
  });
}

class CourseListScreen extends StatefulWidget {
  const CourseListScreen({super.key});

  @override
  State<CourseListScreen> createState() => _CourseListScreenState();
}

class _CourseListScreenState extends State<CourseListScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _uid = FirebaseAuth.instance.currentUser?.uid ?? '';

  String _sortType = 'recent';

  double? _myLat;
  double? _myLng;
  bool _locationLoading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _getMyLocation();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _getMyLocation() async {
    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          setState(() => _locationLoading = false);
          return;
        }
      }
      if (permission == LocationPermission.deniedForever) {
        setState(() => _locationLoading = false);
        return;
      }
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.low),
      );
      setState(() {
        _myLat = pos.latitude;
        _myLng = pos.longitude;
        _locationLoading = false;
      });
    } catch (e) {
      setState(() => _locationLoading = false);
    }
  }

  double _calcDistance(double lat1, double lng1, double lat2, double lng2) {
    const R = 6371.0;
    final dLat = (lat2 - lat1) * pi / 180;
    final dLng = (lng2 - lng1) * pi / 180;
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(lat1 * pi / 180) * cos(lat2 * pi / 180) *
            sin(dLng / 2) * sin(dLng / 2);
    return R * 2 * atan2(sqrt(a), sqrt(1 - a));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: const Text(
          '코스 추천',
          style: TextStyle(color: Colors.black87, fontWeight: FontWeight.w600, fontSize: 18),
        ),
        centerTitle: true,
        bottom: TabBar(
          controller: _tabController,
          labelColor: const Color(0xFF4CAF50),
          unselectedLabelColor: Colors.grey,
          indicatorColor: const Color(0xFF4CAF50),
          labelStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
          tabs: const [
            Tab(text: '유저 공유'),
            Tab(text: '내 코스'),
          ],
        ),
      ),
      backgroundColor: const Color(0xFFF5F5F5),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildUserSharedTab(),
          _buildMyCourseTab(),
        ],
      ),
    );
  }

  // ── 유저 공유 탭 ──────────────────────────────────────────
  Widget _buildUserSharedTab() {
    if (_locationLoading) {
      return const Center(child: CircularProgressIndicator(color: Color(0xFF4CAF50)));
    }

    String orderField;
    if (_sortType == 'likes') orderField = 'like_count';
    else if (_sortType == 'views') orderField = 'view_count';
    else orderField = 'shared_at';

    return Column(
      children: [
        Container(
          color: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              if (_myLat != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFF4CAF50).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.location_on, size: 13, color: Color(0xFF4CAF50)),
                      SizedBox(width: 4),
                      Text('5km 내', style: TextStyle(fontSize: 12, color: Color(0xFF2E7D32), fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
              const Spacer(),
              _sortButton('최신순', 'recent'),
              const SizedBox(width: 6),
              _sortButton('좋아요순', 'likes'),
              const SizedBox(width: 6),
              _sortButton('조회수순', 'views'),
            ],
          ),
        ),
        Expanded(
          child: StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('walk_courses')
                .orderBy(orderField, descending: true)
                .snapshots(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator(color: Color(0xFF4CAF50)));
              }

              var docs = snapshot.data?.docs ?? [];

              // is_public 필터 (없는 문서는 공개로 간주)
              docs = docs.where((doc) {
                final data = doc.data() as Map<String, dynamic>;
                return data['is_public'] == null || data['is_public'] == true;
              }).toList();

              // 5km 필터
              if (_myLat != null && _myLng != null) {
                docs = docs.where((doc) {
                  final data = doc.data() as Map<String, dynamic>;
                  final startLat = (data['start_lat'] as num?)?.toDouble();
                  final startLng = (data['start_lng'] as num?)?.toDouble();
                  if (startLat == null || startLng == null) return true;
                  final dist = _calcDistance(_myLat!, _myLng!, startLat, startLng);
                  return dist <= 5.0;
                }).toList();
              }

              if (docs.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.map_outlined, size: 64, color: Colors.grey.shade300),
                      const SizedBox(height: 16),
                      Text(
                        _myLat != null
                            ? '5km 내에 공유된 코스가 없습니다\n산책 완료 후 코스를 공유해보세요!'
                            : '공유된 코스가 없습니다\n산책 완료 후 코스를 공유해보세요!',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 14, color: Colors.grey.shade500),
                      ),
                    ],
                  ),
                );
              }

              return ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: docs.length,
                itemBuilder: (context, index) {
                  final data = docs[index].data() as Map<String, dynamic>;
                  final docId = docs[index].id;
                  return _buildSharedCourseCard(context, data, docId);
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _sortButton(String label, String type) {
    final isSelected = _sortType == type;
    return GestureDetector(
      onTap: () => setState(() => _sortType = type),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF4CAF50) : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: isSelected ? Colors.white : Colors.grey.shade600,
          ),
        ),
      ),
    );
  }

  Widget _buildSharedCourseCard(BuildContext context, Map<String, dynamic> data, String docId) {
    final distanceKm = (data['distance_km'] as num?)?.toDouble() ?? 0.0;
    final durationMin = (data['duration_min'] as num?)?.toInt() ?? 0;
    final sharedBy = data['shared_by_name'] ?? '익명';
    final petName = data['pet_name'] ?? '';
    final likeCount = (data['like_count'] as num?)?.toInt() ?? 0;
    final viewCount = (data['view_count'] as num?)?.toInt() ?? 0;
    final commentCount = (data['comment_count'] as num?)?.toInt() ?? 0;

    String? distanceStr;
    final startLat = (data['start_lat'] as num?)?.toDouble();
    final startLng = (data['start_lng'] as num?)?.toDouble();
    if (_myLat != null && _myLng != null && startLat != null && startLng != null) {
      final d = _calcDistance(_myLat!, _myLng!, startLat, startLng);
      distanceStr = '${d.toStringAsFixed(1)}km 거리';
    }

    return GestureDetector(
      onTap: () async {
        FirebaseFirestore.instance
            .collection('walk_courses')
            .doc(docId)
            .update({'view_count': FieldValue.increment(1)});
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => UserCourseDetailScreen(courseId: docId, data: data),
          ),
        );
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 2))],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 18,
                  backgroundColor: const Color(0xFF4CAF50).withOpacity(0.1),
                  child: const Icon(Icons.person, size: 18, color: Color(0xFF4CAF50)),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(sharedBy, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                      if (petName.isNotEmpty)
                        Text('🐾 $petName', style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
                    ],
                  ),
                ),
                if (distanceStr != null)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.blue.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(distanceStr, style: const TextStyle(fontSize: 11, color: Colors.blue, fontWeight: FontWeight.w500)),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Icon(Icons.straighten, size: 14, color: Colors.grey.shade400),
                const SizedBox(width: 4),
                Text('${distanceKm.toStringAsFixed(2)}km',
                    style: TextStyle(fontSize: 13, color: Colors.grey.shade600, fontWeight: FontWeight.w500)),
                const SizedBox(width: 12),
                Icon(Icons.access_time, size: 14, color: Colors.grey.shade400),
                const SizedBox(width: 4),
                Text('${durationMin}분',
                    style: TextStyle(fontSize: 13, color: Colors.grey.shade600, fontWeight: FontWeight.w500)),
                const Spacer(),
                Icon(Icons.favorite_border, size: 14, color: Colors.red.shade300),
                const SizedBox(width: 3),
                Text('$likeCount', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                const SizedBox(width: 8),
                Icon(Icons.visibility_outlined, size: 14, color: Colors.grey.shade400),
                const SizedBox(width: 3),
                Text('$viewCount', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                const SizedBox(width: 8),
                Icon(Icons.chat_bubble_outline, size: 14, color: Colors.blue.shade300),
                const SizedBox(width: 3),
                Text('$commentCount', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ── 내 코스 탭 ──────────────────────────────────────────
  Widget _buildMyCourseTab() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('walk_courses')
          .orderBy('shared_at', descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator(color: Color(0xFF4CAF50)));
        }

        var docs = snapshot.data?.docs ?? [];

        // 내 코스만 필터링 (비공개만, 공개한 건 유저공유 탭에서 표시)
        docs = docs.where((doc) {
          final data = doc.data() as Map<String, dynamic>;
          return data['shared_by_uid'] == _uid && data['is_public'] != true;
        }).toList();

        if (docs.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.directions_walk, size: 64, color: Colors.grey.shade300),
                const SizedBox(height: 16),
                Text(
                  '아직 산책 기록이 없습니다\n산책을 완료하면 여기에 코스가 저장됩니다!',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 14, color: Colors.grey.shade500),
                ),
              ],
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: docs.length,
          itemBuilder: (context, index) {
            final data = docs[index].data() as Map<String, dynamic>;
            final docId = docs[index].id;
            return _buildMyCourseCard(context, data, docId);
          },
        );
      },
    );
  }

  Widget _buildMyCourseCard(BuildContext context, Map<String, dynamic> data, String docId) {
    final distanceKm = (data['distance_km'] as num?)?.toDouble() ?? 0.0;
    final durationMin = (data['duration_min'] as num?)?.toInt() ?? 0;
    final petName = data['pet_name'] ?? '반려동물';
    final isPublic = data['is_public'] ?? false;
    final sharedAt = (data['shared_at'] as Timestamp?)?.toDate();
    final dateStr = sharedAt != null
        ? '${sharedAt.month}/${sharedAt.day} ${sharedAt.hour.toString().padLeft(2, '0')}:${sharedAt.minute.toString().padLeft(2, '0')}'
        : '';

    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => UserCourseDetailScreen(courseId: docId, data: data),
          ),
        );
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 2))],
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: isPublic
                    ? const Color(0xFF4CAF50).withOpacity(0.1)
                    : Colors.grey.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Icon(
                  isPublic ? Icons.public : Icons.lock_outline,
                  size: 20,
                  color: isPublic ? const Color(0xFF4CAF50) : Colors.grey,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text('🐾 $petName',
                          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                      const Spacer(),
                      Text(dateStr, style: TextStyle(fontSize: 11, color: Colors.grey.shade400)),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Icon(Icons.straighten, size: 14, color: Colors.grey.shade400),
                      const SizedBox(width: 4),
                      Text('${distanceKm.toStringAsFixed(2)}km',
                          style: TextStyle(fontSize: 13, color: Colors.grey.shade600, fontWeight: FontWeight.w500)),
                      const SizedBox(width: 12),
                      Icon(Icons.timer_outlined, size: 14, color: Colors.grey.shade400),
                      const SizedBox(width: 4),
                      Text('${durationMin}분',
                          style: TextStyle(fontSize: 13, color: Colors.grey.shade600, fontWeight: FontWeight.w500)),
                    ],
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: Colors.grey.shade400),
          ],
        ),
      ),
    );
  }
}