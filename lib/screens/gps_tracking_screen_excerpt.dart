// ─────────────────────────────────────────────────────────────
// 보호자용 실시간 GPS 추적 화면 — 본인 작성 부분 발췌
//
// 원본 gps_tracking_screen.dart는 여러 팀원이 함께 수정한 파일이라
// 본인이 작성한 로직만 옮겼습니다. (마커 아이콘·반려동물 GPS 등은 팀원 담당)
//
//  - _listenToRoom()            : 산책 상태·시작/종료 시각을 Firestore에서 실시간 수신
//  - _updateElapsed()           : 경과 시간을 서버 시작 시각 기준으로 계산
//                                 → 화면을 나갔다 들어와도 시간이 이어짐
//  - _listenToWalkerPositions() : 산책자 좌표 스트림 수신 → 경로·거리·평균 속도 계산
//  - _haversine()               : 두 좌표 사이 거리(km)
//
// 문정욱 수정 2026-05-19
// ─────────────────────────────────────────────────────────────
import 'dart:async';
import 'dart:math';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

// (State 클래스 내부)
//   StreamSubscription<QuerySnapshot>? _positionsSub;
//   StreamSubscription<DocumentSnapshot>? _roomSub;
//   Timer? _uiTimer;                 // 1초마다 _updateElapsed() 호출
//   DateTime? _walkStartedAt, _walkEndedAt;
//   bool _walkCompleted = false;
//   List<LatLng> _walkerRoutePoints = [];
//   double _walkerDistance = 0.0, _speed = 0.0;
//   int _elapsedSeconds = 0;

  void _updateElapsed() {
    if (_walkStartedAt == null) return;
    setState(() {
      if (_walkCompleted && _walkEndedAt != null) {
        _elapsedSeconds = _walkEndedAt!.difference(_walkStartedAt!).inSeconds;
      } else {
        _elapsedSeconds = DateTime.now().difference(_walkStartedAt!).inSeconds;
      }
    });
  }

  // ── 채팅방 상태 감시 (기존 유지) ──
  void _listenToRoom() {
    _roomSub = FirebaseFirestore.instance
        .collection('chatting_rooms')
        .doc(widget.roomId)
        .snapshots()
        .listen((doc) {
      if (!doc.exists || !mounted) return;
      final data = doc.data()!;
      final walkStatus = data['walk_status'] ?? 'pending';
      final startedAtRaw = data['walk_started_at'];
      final endedAtRaw = data['walk_ended_at'];

      setState(() {
        _walkCompleted = walkStatus == 'completed';
        if (startedAtRaw != null) {
          _walkStartedAt = (startedAtRaw as Timestamp).toDate();
        }
        if (endedAtRaw != null) {
          _walkEndedAt = (endedAtRaw as Timestamp).toDate();
        }
      });
      _updateElapsed();
    });
  }

  // ── 산책자 GPS 위치 감시 (기존 유지) ──
  void _listenToWalkerPositions() {
    _positionsSub = FirebaseFirestore.instance
        .collection('chatting_rooms')
        .doc(widget.roomId)
        .collection('gps_positions')
        .orderBy('recorded_at')
        .snapshots()
        .listen((snapshot) {
      if (!mounted) return;

      final positions = snapshot.docs.map((doc) {
        final d = doc.data();
        return LatLng((d['lat'] as num).toDouble(), (d['lng'] as num).toDouble());
      }).toList();

      if (positions.isEmpty) return;

      double totalDistance = 0;
      for (int i = 1; i < positions.length; i++) {
        totalDistance += _haversine(
          positions[i - 1].latitude, positions[i - 1].longitude,
          positions[i].latitude, positions[i].longitude,
        );
      }

      final speed = _elapsedSeconds > 0
          ? totalDistance / (_elapsedSeconds / 3600)
          : 0.0;

      setState(() {
        _walkerRoutePoints = positions;
        _walkerDistance = totalDistance;
        _speed = speed;
        _rebuildMapOverlays();
      });

      if (!_walkCompleted && positions.isNotEmpty) {
        _mapController?.animateCamera(CameraUpdate.newLatLng(positions.last));
      }
    });

  double _haversine(double lat1, double lng1, double lat2, double lng2) {
    const R = 6371.0;
    final dLat = (lat2 - lat1) * pi / 180;
    final dLng = (lng2 - lng1) * pi / 180;
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(lat1 * pi / 180) * cos(lat2 * pi / 180) *
            sin(dLng / 2) * sin(dLng / 2);
    return R * 2 * atan2(sqrt(a), sqrt(1 - a));
  }
