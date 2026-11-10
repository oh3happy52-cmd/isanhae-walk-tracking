import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

class GpsService {
  // 문정욱 수정 - 싱글톤으로 산책 상태 전역 유지
  static final GpsService _instance = GpsService._internal();
  factory GpsService() => _instance;
  GpsService._internal();

  bool isWalking = false;
  int elapsedSeconds = 0;
  double distance = 0.0;
  double speed = 0.0;
  String lastUpdate = '';
  List<LatLng> routePoints = [];

  DateTime? walkStartTime; //0518 산책 시작 시각 기록용 변수 추가 


  void resetWalk() {
    isWalking = false;
    elapsedSeconds = 0;
    distance = 0.0;
    speed = 0.0;
    lastUpdate = '';
    routePoints = [];
    walkStartTime = null; //0518 초기화 시 시작 시각도 함께 삭제
  }

  Future<bool> requestPermission() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return false;
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) return false;
    }
    if (permission == LocationPermission.deniedForever) return false;
    return true;
  }

  Future<Position?> getCurrentPosition() async {
    final hasPermission = await requestPermission();
    if (!hasPermission) return null;
    return await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.high,
    );
  }

  Stream<Position> startTracking() {
    const LocationSettings settings = LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 5,
    );
    return Geolocator.getPositionStream(locationSettings: settings);
  }
}