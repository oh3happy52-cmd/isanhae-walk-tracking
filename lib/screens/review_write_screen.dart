import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class ReviewWriteScreen extends StatefulWidget {
  final String roomId;
  final String walkerId;
  final String petName;

  const ReviewWriteScreen({
    super.key,
    required this.roomId,
    required this.walkerId,
    required this.petName,
  });

  @override
  State<ReviewWriteScreen> createState() => _ReviewWriteScreenState();
}

class _ReviewWriteScreenState extends State<ReviewWriteScreen> {
  final _contentController = TextEditingController();
  bool _isSaving = false;

  // 세부 항목별 별점
  final Map<String, double> _ratings = {
    '시간 준수': 5.0,
    '산책 태도': 5.0,
    '반려동물 케어': 5.0,
    '의사소통': 5.0,
    '재이용 의사': 5.0,
  };

  final Map<String, IconData> _ratingIcons = {
    '시간 준수': Icons.access_time,
    '산책 태도': Icons.directions_walk,
    '반려동물 케어': Icons.pets,
    '의사소통': Icons.chat_bubble_outline,
    '재이용 의사': Icons.repeat,
  };

  double get _averageRating {
    final total = _ratings.values.reduce((a, b) => a + b);
    return total / _ratings.length;
  }

  @override
  void dispose() {
    _contentController.dispose();
    super.dispose();
  }

  Future<void> _submitReview() async {
    if (_contentController.text.trim().length < 10) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('리뷰는 10자 이상 작성해주세요.'), backgroundColor: Colors.orange),
      );
      return;
    }

    setState(() => _isSaving = true);

    try {
      final uid = FirebaseAuth.instance.currentUser!.uid;

      await FirebaseFirestore.instance.collection('reviews').add({
        'room_id': widget.roomId,
        'owner_id': uid,
        'walker_id': widget.walkerId,
        'rating': double.parse(_averageRating.toStringAsFixed(1)),
        'rating_detail': _ratings.map((key, value) => MapEntry(key, double.parse(value.toStringAsFixed(1)))),
        'content': _contentController.text.trim(),
        'is_deleted': false,
        'created_at': FieldValue.serverTimestamp(),
        'updated_at': FieldValue.serverTimestamp(),
      });

      // Walker 평점 갱신
      final reviewsSnapshot = await FirebaseFirestore.instance
          .collection('reviews')
          .where('walker_id', isEqualTo: widget.walkerId)
          .where('is_deleted', isEqualTo: false)
          .get();

      double totalRating = 0;
      for (var doc in reviewsSnapshot.docs) {
        totalRating += (doc.data()['rating'] ?? 0).toDouble();
      }
      final avgRating = reviewsSnapshot.docs.isNotEmpty ? totalRating / reviewsSnapshot.docs.length : 0.0;

      await FirebaseFirestore.instance.collection('walkers').doc(widget.walkerId).update({
        'rating_avg': double.parse(avgRating.toStringAsFixed(1)),
      });

      // 채팅방에 리뷰 완료 표시 저장
      await FirebaseFirestore.instance.collection('chatting_rooms').doc(widget.roomId).update({
        'review_submitted': true,
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('리뷰가 등록되었습니다!'), backgroundColor: Color(0xFF4CAF50)),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      setState(() => _isSaving = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('리뷰 등록 실패: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white, elevation: 0,
        leading: IconButton(icon: const Icon(Icons.arrow_back_ios, color: Colors.black87), onPressed: () => Navigator.pop(context, false)),
        title: const Text('리뷰 작성', style: TextStyle(color: Colors.black87, fontWeight: FontWeight.w600)),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 산책 정보
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: const Color(0xFF4CAF50).withOpacity(0.05), borderRadius: BorderRadius.circular(16)),
              child: Row(children: [
                const Icon(Icons.pets, color: Color(0xFF4CAF50), size: 24),
                const SizedBox(width: 12),
                Text('${widget.petName} 산책에 대한 리뷰', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
              ]),
            ),

            const SizedBox(height: 24),

            // 평균 점수 표시
            Center(
              child: Column(
                children: [
                  Text(_averageRating.toStringAsFixed(1), style: const TextStyle(fontSize: 40, fontWeight: FontWeight.bold, color: Color(0xFF2E7D32))),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(5, (i) {
                      final starValue = i + 1.0;
                      return Icon(
                        _averageRating >= starValue ? Icons.star : (_averageRating >= starValue - 0.5 ? Icons.star_half : Icons.star_border),
                        color: Colors.amber, size: 24,
                      );
                    }),
                  ),
                  const SizedBox(height: 4),
                  Text('평균 별점', style: TextStyle(fontSize: 13, color: Colors.grey.shade500)),
                ],
              ),
            ),

            const SizedBox(height: 28),

            // 세부 항목별 별점
            const Text('세부 평가', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            const SizedBox(height: 16),

            ..._ratings.keys.map((category) => _buildRatingItem(category)),

            const SizedBox(height: 28),

            // 리뷰 내용
            const Text('리뷰 내용', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text('10자 이상 작성해주세요.', style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
            const SizedBox(height: 12),
            TextField(
              controller: _contentController,
              maxLines: 5,
              maxLength: 500,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: '산책 서비스에 대한 솔직한 리뷰를 남겨주세요.',
                hintStyle: TextStyle(color: Colors.grey.shade400),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFF4CAF50), width: 2)),
                filled: true, fillColor: Colors.grey.shade50,
                counterText: '${_contentController.text.length}/500',
                counterStyle: TextStyle(
                  color: _contentController.text.length < 10 ? Colors.red : Colors.grey.shade500,
                ),
              ),
            ),
            if (_contentController.text.isNotEmpty && _contentController.text.length < 10)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text('${10 - _contentController.text.length}자 더 작성해주세요.', style: const TextStyle(fontSize: 12, color: Colors.red)),
              ),

            const SizedBox(height: 32),

            SizedBox(
              width: double.infinity, height: 52,
              child: ElevatedButton(
                onPressed: _isSaving ? null : _submitReview,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF4CAF50), foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)), elevation: 0,
                ),
                child: _isSaving
                    ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5))
                    : const Text('리뷰 등록', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRatingItem(String category) {
    final rating = _ratings[category]!;
    final icon = _ratingIcons[category] ?? Icons.star;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Icon(icon, size: 20, color: const Color(0xFF4CAF50)),
              const SizedBox(width: 10),
              Expanded(
                child: Text(category, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
              ),
              Text(rating.toStringAsFixed(0), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF2E7D32))),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(5, (i) {
              final starValue = i + 1.0;
              return GestureDetector(
                onTap: () => setState(() => _ratings[category] = starValue),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Icon(
                    rating >= starValue ? Icons.star : Icons.star_border,
                    color: Colors.amber, size: 32,
                  ),
                ),
              );
            }),
          ),
        ],
      ),
    );
  }
}