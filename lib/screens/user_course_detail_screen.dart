import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

// 문정욱 수정 2026-05-19
// 유저가 공유한 산책 코스 상세 화면
// - 지도에 폴리라인 표시
// - 좋아요 / 댓글 기능

class UserCourseDetailScreen extends StatefulWidget {
  final String courseId;
  final Map<String, dynamic> data;

  const UserCourseDetailScreen({
    super.key,
    required this.courseId,
    required this.data,
  });

  @override
  State<UserCourseDetailScreen> createState() => _UserCourseDetailScreenState();
}

class _UserCourseDetailScreenState extends State<UserCourseDetailScreen> {
  GoogleMapController? _mapController;
  final _commentController = TextEditingController();
  final _uid = FirebaseAuth.instance.currentUser?.uid ?? '';
  final _displayName = FirebaseAuth.instance.currentUser?.displayName ?? '익명';

  bool _isLiked = false;
  int _likeCount = 0;
  bool _isSubmitting = false;

  Set<Polyline> _polylines = {};
  Set<Marker> _markers = {};
  List<LatLng> _routePoints = [];

  @override
  void initState() {
    super.initState();
    _likeCount = (widget.data['like_count'] as num?)?.toInt() ?? 0;
    _buildRoute();
    _checkIfLiked();
  }

  @override
  void dispose() {
    _commentController.dispose();
    _mapController?.dispose();
    super.dispose();
  }

  void _buildRoute() {
    final rawPoints = widget.data['route_points'] as List<dynamic>? ?? [];
    final points = rawPoints.map((p) {
      return LatLng((p['lat'] as num).toDouble(), (p['lng'] as num).toDouble());
    }).toList();

    if (points.isEmpty) return;

    final newMarkers = <Marker>{
      Marker(
        markerId: const MarkerId('start'),
        position: points.first,
        infoWindow: const InfoWindow(title: '시작'),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
      ),
      Marker(
        markerId: const MarkerId('end'),
        position: points.last,
        infoWindow: const InfoWindow(title: '종료'),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
      ),
    };

    final newPolylines = <Polyline>{
      Polyline(
        polylineId: const PolylineId('route'),
        points: points,
        color: Colors.blue,
        width: 5,
        startCap: Cap.roundCap,
        endCap: Cap.roundCap,
      ),
    };

    setState(() {
      _routePoints = points;
      _markers = newMarkers;
      _polylines = newPolylines;
    });
  }

  Future<void> _checkIfLiked() async {
    if (_uid.isEmpty) return;
    final doc = await FirebaseFirestore.instance
        .collection('walk_courses')
        .doc(widget.courseId)
        .collection('likes')
        .doc(_uid)
        .get();
    if (mounted) setState(() => _isLiked = doc.exists);
  }

  Future<void> _toggleLike() async {
    if (_uid.isEmpty) return;
    final likeRef = FirebaseFirestore.instance
        .collection('walk_courses')
        .doc(widget.courseId)
        .collection('likes')
        .doc(_uid);
    final courseRef = FirebaseFirestore.instance
        .collection('walk_courses')
        .doc(widget.courseId);

    // 좋아요 문서와 카운트를 한 번에(batch) 반영하고,
    // 카운트는 화면 값(_likeCount)이 아닌 서버 값 기준으로 증감(FieldValue.increment)
    // → 여러 명이 동시에 눌러도 누락되지 않음
    final batch = FirebaseFirestore.instance.batch();
    if (_isLiked) {
      batch.delete(likeRef);
      batch.update(courseRef, {'like_count': FieldValue.increment(-1)});
    } else {
      batch.set(likeRef, {'uid': _uid, 'liked_at': FieldValue.serverTimestamp()});
      batch.update(courseRef, {'like_count': FieldValue.increment(1)});
    }
    await batch.commit();

    if (!mounted) return;
    setState(() {
      _isLiked = !_isLiked;
      _likeCount += _isLiked ? 1 : -1;
    });
  }

  Future<void> _submitComment() async {
    final text = _commentController.text.trim();
    if (text.isEmpty || _isSubmitting) return;

    setState(() => _isSubmitting = true);

    await FirebaseFirestore.instance
        .collection('walk_courses')
        .doc(widget.courseId)
        .collection('comments')
        .add({
      'uid': _uid,
      'name': _displayName,
      'text': text,
      'created_at': FieldValue.serverTimestamp(),
    });

    await FirebaseFirestore.instance
        .collection('walk_courses')
        .doc(widget.courseId)
        .update({'comment_count': FieldValue.increment(1)});

    _commentController.clear();
    setState(() => _isSubmitting = false);
  }

  @override
  Widget build(BuildContext context) {
    final distanceKm = (widget.data['distance_km'] as num?)?.toDouble() ?? 0.0;
    final durationMin = (widget.data['duration_min'] as num?)?.toInt() ?? 0;
    final sharedBy = widget.data['shared_by_name'] ?? '익명';
    final petName = widget.data['pet_name'] ?? '';
    final initialPos = _routePoints.isNotEmpty
        ? _routePoints.first
        : const LatLng(37.5665, 126.9780);

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: Colors.black87),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          '코스 상세',
          style: TextStyle(color: Colors.black87, fontWeight: FontWeight.w600),
        ),
        centerTitle: true,
      ),
      body: Column(
        children: [
          // 지도
          SizedBox(
            height: 280,
            child: GoogleMap(
              initialCameraPosition: CameraPosition(target: initialPos, zoom: 15),
              markers: _markers,
              polylines: _polylines,
              myLocationEnabled: false,
              myLocationButtonEnabled: false,
              onMapCreated: (controller) {
                _mapController = controller;
                if (_routePoints.isNotEmpty) {
                  _mapController?.animateCamera(
                    CameraUpdate.newLatLng(_routePoints.first),
                  );
                }
              },
            ),
          ),

          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 공유자 정보
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 20,
                        backgroundColor: const Color(0xFF4CAF50).withOpacity(0.1),
                        child: const Icon(Icons.person, color: Color(0xFF4CAF50)),
                      ),
                      const SizedBox(width: 10),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(sharedBy,
                              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                          if (petName.isNotEmpty)
                            Text('🐾 $petName',
                                style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
                        ],
                      ),
                      const Spacer(),
                      // 좋아요 버튼
                      GestureDetector(
                        onTap: _toggleLike,
                        child: Row(
                          children: [
                            Icon(
                              _isLiked ? Icons.favorite : Icons.favorite_border,
                              color: _isLiked ? Colors.red : Colors.grey.shade400,
                              size: 22,
                            ),
                            const SizedBox(width: 4),
                            Text('$_likeCount',
                                style: TextStyle(fontSize: 14, color: Colors.grey.shade600)),
                          ],
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 16),
                  const Divider(),
                  const SizedBox(height: 12),

                  // 통계
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _statItem(Icons.straighten, '${distanceKm.toStringAsFixed(2)}km', '이동 거리'),
                      Container(width: 1, height: 30, color: Colors.grey.shade200),
                      _statItem(Icons.timer_outlined, '${durationMin}분', '소요 시간'),
                    ],
                  ),

                  const SizedBox(height: 16),
                  const Divider(),
                  const SizedBox(height: 12),

                  // 댓글 목록
                  const Text('댓글',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 10),

                  StreamBuilder<QuerySnapshot>(
                    stream: FirebaseFirestore.instance
                        .collection('walk_courses')
                        .doc(widget.courseId)
                        .collection('comments')
                        .orderBy('created_at', descending: false)
                        .snapshots(),
                    builder: (context, snapshot) {
                      final comments = snapshot.data?.docs ?? [];
                      if (comments.isEmpty) {
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          child: Center(
                            child: Text('첫 댓글을 남겨보세요!',
                                style: TextStyle(fontSize: 13, color: Colors.grey.shade400)),
                          ),
                        );
                      }
                      return Column(
                        children: comments.map((doc) {
                          final d = doc.data() as Map<String, dynamic>;
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                CircleAvatar(
                                  radius: 14,
                                  backgroundColor: const Color(0xFF4CAF50).withOpacity(0.1),
                                  child: const Icon(Icons.person, size: 14, color: Color(0xFF4CAF50)),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(d['name'] ?? '익명',
                                          style: const TextStyle(
                                              fontSize: 13, fontWeight: FontWeight.w600)),
                                      const SizedBox(height: 2),
                                      Text(d['text'] ?? '',
                                          style: TextStyle(
                                              fontSize: 13, color: Colors.grey.shade700)),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          );
                        }).toList(),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),

          // 댓글 입력창
          Container(
            padding: EdgeInsets.only(
              left: 16,
              right: 16,
              top: 10,
              bottom: MediaQuery.of(context).padding.bottom + 10,
            ),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 4,
                  offset: const Offset(0, -2),
                ),
              ],
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _commentController,
                    decoration: InputDecoration(
                      hintText: '댓글을 입력하세요...',
                      hintStyle: TextStyle(fontSize: 13, color: Colors.grey.shade400),
                      contentPadding:
                          const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(20),
                        borderSide: BorderSide(color: Colors.grey.shade200),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(20),
                        borderSide: BorderSide(color: Colors.grey.shade200),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(20),
                        borderSide: const BorderSide(color: Color(0xFF4CAF50)),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: _submitComment,
                  child: Container(
                    width: 40,
                    height: 40,
                    decoration: const BoxDecoration(
                      color: Color(0xFF4CAF50),
                      shape: BoxShape.circle,
                    ),
                    child: _isSubmitting
                        ? const Padding(
                            padding: EdgeInsets.all(10),
                            child: CircularProgressIndicator(
                                color: Colors.white, strokeWidth: 2),
                          )
                        : const Icon(Icons.send, color: Colors.white, size: 18),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _statItem(IconData icon, String value, String label) {
    return Column(
      children: [
        Icon(icon, color: const Color(0xFF4CAF50), size: 20),
        const SizedBox(height: 4),
        Text(value, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
        const SizedBox(height: 2),
        Text(label, style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
      ],
    );
  }
}