import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

// 문정욱 수정 2026-05-19
// 내 산책 코스 상세 화면
// - walk_reports 기반으로 지도에 폴리라인 표시
// - 산책 통계 (거리, 시간, 속도, 등급)
// - 커뮤니티 공유 버튼
class MyCourseDetailScreen extends StatefulWidget {
  final String reportId;
  final Map<String, dynamic> data;

  const MyCourseDetailScreen({
    super.key,
    required this.reportId,
    required this.data,
  });

  @override
  State<MyCourseDetailScreen> createState() => _MyCourseDetailScreenState();
}

class _MyCourseDetailScreenState extends State<MyCourseDetailScreen> {
  GoogleMapController? _mapController;
  final _uid = FirebaseAuth.instance.currentUser?.uid ?? '';

  Set<Polyline> _polylines = {};
  Set<Marker> _markers = {};
  List<LatLng> _routePoints = [];
  bool _isSharing = false;
  bool _alreadyShared = false;

  @override
  void initState() {
    super.initState();
    _buildRoute();
    _checkAlreadyShared();
  }

  @override
  void dispose() {
    _mapController?.dispose();
    super.dispose();
  }

  void _buildRoute() {
    final rawPoints = widget.data['walk_route'] as List<dynamic>? ?? [];
    final points = rawPoints.map((p) {
      return LatLng(
        (p['lat'] as num).toDouble(),
        (p['lng'] as num).toDouble(),
      );
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

  Future<void> _checkAlreadyShared() async {
    final snap = await FirebaseFirestore.instance
        .collection('walk_courses')
        .where('room_id', isEqualTo: widget.data['room_id'] ?? '')
        .where('shared_by_uid', isEqualTo: _uid)
        .get();
    if (mounted) setState(() => _alreadyShared = snap.docs.isNotEmpty);
  }

  Future<void> _shareToCommunity() async {
    if (_alreadyShared) return;
    setState(() => _isSharing = true);

    try {
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(_uid)
          .get();
      final userName = userDoc.data()?['username'] ?? '익명';

      final rawPoints = widget.data['walk_route'] as List<dynamic>? ?? [];
      final routePoints = rawPoints
          .map((p) => {'lat': p['lat'], 'lng': p['lng']})
          .toList();

      final distanceKm = (widget.data['distance_km'] as num?)?.toDouble() ?? 0.0;
      final durationMin = (widget.data['duration_min'] as num?)?.toInt() ?? 0;
      final startLat = routePoints.isNotEmpty ? (routePoints.first['lat'] as num?)?.toDouble() : null;
      final startLng = routePoints.isNotEmpty ? (routePoints.first['lng'] as num?)?.toDouble() : null;

      await FirebaseFirestore.instance.collection('walk_courses').add({
        'room_id': widget.data['room_id'] ?? '',
        'shared_by_uid': _uid,
        'shared_by_name': userName,
        'pet_name': widget.data['pet_name'] ?? '',
        'route_points': routePoints,
        'start_lat': startLat ?? 0.0,
        'start_lng': startLng ?? 0.0,
        'distance_km': distanceKm,
        'duration_seconds': durationMin * 60,
        'like_count': 0,
        'comment_count': 0,
        'view_count': 0,
        'shared_at': FieldValue.serverTimestamp(),
      });

      setState(() {
        _isSharing = false;
        _alreadyShared = true;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('커뮤니티에 공유되었습니다! 🗺️'),
            backgroundColor: Color(0xFF4CAF50),
          ),
        );
      }
    } catch (e) {
      setState(() => _isSharing = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('공유 실패: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final distanceKm = (widget.data['distance_km'] as num?)?.toDouble() ?? 0.0;
    final durationMin = (widget.data['duration_min'] as num?)?.toInt() ?? 0;
    final avgSpeed = (widget.data['avg_speed_kmh'] as num?)?.toDouble() ?? 0.0;
    final grade = widget.data['activity_grade'] ?? '-';
    final petName = widget.data['pet_name'] ?? '반려동물';
    final startTime = widget.data['start_time'] ?? '';
    final endTime = widget.data['end_time'] ?? '';

    final gradeColor = grade == 'A'
        ? Colors.green
        : grade == 'B'
        ? Colors.orange
        : Colors.blue;

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
          '내 산책 코스',
          style: TextStyle(color: Colors.black87, fontWeight: FontWeight.w600),
        ),
        centerTitle: true,
        actions: [
          // 커뮤니티 공유 버튼
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: _alreadyShared
                ? Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.check_circle, size: 14, color: Colors.grey.shade500),
                        const SizedBox(width: 4),
                        Text('공유됨', style: TextStyle(fontSize: 12, color: Colors.grey.shade500, fontWeight: FontWeight.w600)),
                      ],
                    ),
                  )
                : GestureDetector(
                    onTap: _isSharing ? null : _shareToCommunity,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: const Color(0xFF4CAF50).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: _isSharing
                          ? const SizedBox(
                              width: 14, height: 14,
                              child: CircularProgressIndicator(color: Color(0xFF4CAF50), strokeWidth: 2),
                            )
                          : const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.share, size: 14, color: Color(0xFF4CAF50)),
                                SizedBox(width: 4),
                                Text('공유', style: TextStyle(fontSize: 12, color: Color(0xFF4CAF50), fontWeight: FontWeight.w600)),
                              ],
                            ),
                    ),
                  ),
          ),
        ],
      ),
      body: Column(
        children: [
          // 지도
          SizedBox(
            height: 300,
            child: _routePoints.isEmpty
                ? Container(
                    color: Colors.grey.shade100,
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.map_outlined, size: 48, color: Colors.grey.shade300),
                          const SizedBox(height: 8),
                          Text('경로 데이터가 없습니다', style: TextStyle(color: Colors.grey.shade400)),
                        ],
                      ),
                    ),
                  )
                : GoogleMap(
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
                  // 반려동물 & 시간 정보
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: const Color(0xFF4CAF50).withOpacity(0.1),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.pets, size: 14, color: Color(0xFF4CAF50)),
                            const SizedBox(width: 6),
                            Text(petName, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF2E7D32))),
                          ],
                        ),
                      ),
                      const Spacer(),
                      if (startTime.isNotEmpty && endTime.isNotEmpty)
                        Text('$startTime ~ $endTime',
                            style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
                    ],
                  ),

                  const SizedBox(height: 16),
                  const Divider(),
                  const SizedBox(height: 12),

                  // 활동 등급
                  Row(
                    children: [
                      const Text('활동 등급', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                      const SizedBox(width: 12),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                        decoration: BoxDecoration(
                          color: gradeColor.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: gradeColor.withOpacity(0.3)),
                        ),
                        child: Text(
                          grade,
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: gradeColor),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 16),

                  // 통계 4개
                  Row(
                    children: [
                      Expanded(child: _statCard(Icons.straighten, '${distanceKm.toStringAsFixed(2)}km', '이동 거리', Colors.blue)),
                      const SizedBox(width: 10),
                      Expanded(child: _statCard(Icons.timer_outlined, '${durationMin}분', '소요 시간', Colors.orange)),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(child: _statCard(Icons.speed, '${avgSpeed.toStringAsFixed(1)}km/h', '평균 속도', Colors.green)),
                      const SizedBox(width: 10),
                      Expanded(child: _statCard(Icons.route, '${_routePoints.length}개', 'GPS 포인트', Colors.purple)),
                    ],
                  ),

                  const SizedBox(height: 16),
                  const Divider(),
                  const SizedBox(height: 12),

                  // AI 요약
                  if ((widget.data['ai_summary'] ?? '').isNotEmpty) ...[
                    const Text('AI 분석', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF4CAF50).withOpacity(0.05),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFF4CAF50).withOpacity(0.15)),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.auto_awesome, size: 16, color: Color(0xFF4CAF50)),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              widget.data['ai_summary'],
                              style: TextStyle(fontSize: 13, color: Colors.grey.shade700, height: 1.5),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _statCard(IconData icon, String value, String label, Color color) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withOpacity(0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withOpacity(0.15)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(value, style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: color)),
              Text(label, style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
            ],
          ),
        ],
      ),
    );
  }
}