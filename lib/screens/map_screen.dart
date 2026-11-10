import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'dart:async';
import 'course_list_screen.dart';

class MapScreen extends StatefulWidget {
  // 문정욱 수정 - course 파라미터 optional로 변경 (코스추천/일반 산책 둘 다 지원)
  final CourseModel? course;

  const MapScreen({super.key, this.course});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  late GoogleMapController mapController;
  final LatLng _initialPosition = const LatLng(37.5665, 126.9780);

  bool _isWalking = false;
  List<LatLng> _routePoints = [];
  StreamSubscription<Position>? _positionStream;
  Set<Polyline> _polylines = {};
  Set<Marker> _markers = {};

  @override
  void initState() {
    super.initState();
    // 문정욱 수정 - 코스가 있으면 코스 폴리라인 그리기
    if (widget.course != null) {
      _drawCourse();
    }
  }

  void _onMapCreated(GoogleMapController controller) {
    mapController = controller;
    if (widget.course != null) {
      _fitCameraToCourse();
    }
  }

  // 팀원 코드 - 추천 코스 폴리라인 그리기
  void _drawCourse() {
    final points = widget.course!.points;
    setState(() {
      _polylines.add(
        Polyline(
          polylineId: const PolylineId('recommended_course'),
          points: points,
          color: const Color(0xFF4CAF50),
          width: 5,
          startCap: Cap.roundCap,
          endCap: Cap.roundCap,
          jointType: JointType.round,
        ),
      );
      _markers.add(
        Marker(
          markerId: const MarkerId('course_start'),
          position: points.first,
          infoWindow: const InfoWindow(title: '출발'),
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
        ),
      );
      _markers.add(
        Marker(
          markerId: const MarkerId('course_end'),
          position: points.last,
          infoWindow: const InfoWindow(title: '도착'),
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
        ),
      );
    });
  }

  // 팀원 코드 - 코스 전체 보이도록 카메라 조정
  void _fitCameraToCourse() {
    final points = widget.course!.points;
    double minLat = points.first.latitude;
    double maxLat = points.first.latitude;
    double minLng = points.first.longitude;
    double maxLng = points.first.longitude;

    for (final point in points) {
      if (point.latitude < minLat) minLat = point.latitude;
      if (point.latitude > maxLat) maxLat = point.latitude;
      if (point.longitude < minLng) minLng = point.longitude;
      if (point.longitude > maxLng) maxLng = point.longitude;
    }

    mapController.animateCamera(
      CameraUpdate.newLatLngBounds(
        LatLngBounds(
          southwest: LatLng(minLat, minLng),
          northeast: LatLng(maxLat, maxLng),
        ),
        80,
      ),
    );
  }

  // 문정욱 수정 - 현재 위치로 이동
  Future<void> _goToMyLocation() async {
    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) return;
      }
      if (permission == LocationPermission.deniedForever) return;

      Position position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
      );

      mapController.animateCamera(
        CameraUpdate.newLatLngZoom(LatLng(position.latitude, position.longitude), 16),
      );
    } catch (e) {
      debugPrint('위치 오류: $e');
    }
  }

  // 문정욱 수정 - 산책 시작 (GPS 추적 + 폴리라인)
  Future<void> _startWalking() async {
    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) return;
      }

      Position startPosition = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
      );
      final startPoint = LatLng(startPosition.latitude, startPosition.longitude);

      setState(() {
        _isWalking = true;
        _routePoints = [startPoint];
        _markers.add(
          Marker(
            markerId: const MarkerId('walk_start'),
            position: startPoint,
            icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
            infoWindow: const InfoWindow(title: '산책 시작'),
          ),
        );
      });

      mapController.animateCamera(CameraUpdate.newLatLngZoom(startPoint, 16));

      _positionStream = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 5,
        ),
      ).listen((Position position) {
        final newPoint = LatLng(position.latitude, position.longitude);

        setState(() {
          _routePoints.add(newPoint);
          _polylines.removeWhere((p) => p.polylineId.value == 'walk_route');
          _polylines.add(
            Polyline(
              polylineId: const PolylineId('walk_route'),
              points: List.from(_routePoints),
              color: Colors.blue,
              width: 4,
            ),
          );
        });

        mapController.animateCamera(CameraUpdate.newLatLng(newPoint));
      });
    } catch (e) {
      debugPrint('산책 시작 오류: $e');
    }
  }

  // 문정욱 수정 - 산책 종료
  void _stopWalking() {
    _positionStream?.cancel();

    if (_routePoints.isNotEmpty) {
      final endPoint = _routePoints.last;
      setState(() {
        _isWalking = false;
        _markers.add(
          Marker(
            markerId: const MarkerId('walk_end'),
            position: endPoint,
            icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueViolet),
            infoWindow: const InfoWindow(title: '산책 종료'),
          ),
        );
      });
    } else {
      setState(() => _isWalking = false);
    }
  }

  @override
  void dispose() {
    _positionStream?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.course?.name ?? '산책 지도'),
        backgroundColor: const Color(0xFF4CAF50),
        foregroundColor: Colors.white,
      ),
      body: Stack(
        children: [
          GoogleMap(
            onMapCreated: _onMapCreated,
            initialCameraPosition: CameraPosition(
              target: widget.course?.points.first ?? _initialPosition,
              zoom: 14,
            ),
            myLocationEnabled: true,
            myLocationButtonEnabled: false,
            polylines: _polylines,
            markers: _markers,
          ),

          // 현재 위치 버튼
          Positioned(
            bottom: 100,
            right: 70,
            child: FloatingActionButton(
              backgroundColor: Colors.white,
              onPressed: _goToMyLocation,
              child: const Icon(Icons.my_location, color: Color(0xFF4CAF50)),
            ),
          ),

          // 코스 정보 카드 (코스가 있을 때만)
          if (widget.course != null)
            Positioned(
              bottom: 90,
              left: 16,
              right: 16,
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.1),
                      blurRadius: 10,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _buildInfoItem(Icons.straighten, '${widget.course!.distanceKm}km', '거리'),
                    _buildInfoItem(Icons.access_time, '${widget.course!.estimatedMinutes}분', '예상 시간'),
                    _buildInfoItem(
                      Icons.auto_awesome,
                      widget.course!.type == 'cf' ? 'AI 추천' : '기본 추천',
                      '추천 방식',
                    ),
                  ],
                ),
              ),
            ),

          // 산책 시작/종료 버튼
          Positioned(
            bottom: 24,
            left: 0,
            right: 0,
            child: Center(
              child: ElevatedButton.icon(
                onPressed: _isWalking ? _stopWalking : _startWalking,
                icon: Icon(_isWalking ? Icons.stop : Icons.directions_walk),
                label: Text(_isWalking ? '산책 종료' : '산책 시작'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _isWalking ? Colors.red : const Color(0xFF4CAF50),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                  textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoItem(IconData icon, String value, String label) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: const Color(0xFF4CAF50), size: 20),
        const SizedBox(height: 4),
        Text(value, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.black87)),
        Text(label, style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
      ],
    );
  }
}