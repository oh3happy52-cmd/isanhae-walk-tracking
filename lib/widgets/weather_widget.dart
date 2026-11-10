import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:geolocator/geolocator.dart';
import 'dart:convert';

// 문정욱 작성 - 현재 위치 기반 날씨 위젯 (보호자 홈 AppBar)
// 원본은 팀 레포 owner_home_screen.dart 안에 있던 코드를 분리한 것
// API 키는 코드에 두지 않고 실행 시 주입: flutter run --dart-define=OPENWEATHER_API_KEY=키
class WeatherWidget extends StatefulWidget {
  const WeatherWidget({super.key});

  @override
  State<WeatherWidget> createState() => _WeatherWidgetState();
}

class _WeatherWidgetState extends State<WeatherWidget> {
  String _temp = '';
  String _weatherDesc = '';
  String _weatherIcon = '';
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchWeather();
  }

  Future<void> _fetchWeather() async {
    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) return;
      }

      Position position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.low,
        ),
      );

      const apiKey = String.fromEnvironment('OPENWEATHER_API_KEY');
      if (apiKey.isEmpty) {
        if (mounted) setState(() => _isLoading = false);
        return;
      }
      final url = Uri.parse(
        'https://api.openweathermap.org/data/2.5/weather?lat=${position.latitude}&lon=${position.longitude}&appid=$apiKey&units=metric&lang=kr',
      );

      final response = await http.get(url);

      if (!mounted) return; // 0518 추가 - 위젯이 이미 dispose된 경우 setState 방지 

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        setState(() {
          _temp = '${data['main']['temp'].toStringAsFixed(1)}°C';
          _weatherDesc = data['weather'][0]['description'];
          _weatherIcon = data['weather'][0]['icon'];
          _isLoading = false;
        });
      }
    } catch (e) {
      if (!mounted) return; // 0518 추가 - 위젯이 이미 dispose된 경우 setState 방지 
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading || _temp.isEmpty) return const SizedBox();
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: const BoxDecoration(), // 배경, 테두리 제거
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Image.network(
            'https://openweathermap.org/img/wn/$_weatherIcon.png',
            width: 28,
            height: 28,
          ),
          const SizedBox(width: 2),
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _temp,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                _weatherDesc,
                style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

