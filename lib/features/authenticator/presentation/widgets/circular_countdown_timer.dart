import 'dart:math' as math;
import 'package:flutter/material.dart';

class CircularCountdownTimer extends StatelessWidget {
  final int secondsRemaining;
  final double size;
  final Color progressColor;
  final Color backgroundColor;

  const CircularCountdownTimer({
    super.key,
    required this.secondsRemaining,
    this.size = 24.0, // Giữ kích thước nhỏ gọn
    this.progressColor = Colors.blue, // Màu mặc định, có thể lấy từ theme
    this.backgroundColor = Colors.grey, // Màu nền mặc định
  });

  @override
  Widget build(BuildContext context) {
    // Ưu tiên màu từ theme nếu màu mặc định không được chỉ định khác
    final Color effectiveProgressColor =
        progressColor == Colors.blue
            ? Theme.of(context).colorScheme.primary
            : progressColor;
    final Color effectiveBackgroundColor =
        backgroundColor == Colors.grey
            ? Theme.of(context).colorScheme.onSurface.withOpacity(0.1)
            : backgroundColor;

    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _SolidCountdownPainter(
          secondsRemaining: secondsRemaining,
          progressColor: effectiveProgressColor,
          backgroundColor: effectiveBackgroundColor,
        ),
      ),
    );
  }
}

class _SolidCountdownPainter extends CustomPainter {
  final int secondsRemaining;
  final Color progressColor;
  final Color backgroundColor;

  _SolidCountdownPainter({
    required this.secondsRemaining,
    required this.progressColor,
    required this.backgroundColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final Paint backgroundPaint =
        Paint()
          ..color = backgroundColor
          ..style = PaintingStyle.fill; // Tô đầy nền

    final Paint progressPaint =
        Paint()
          ..color = progressColor
          ..style = PaintingStyle.fill; // Tô đầy phần tiến trình

    final double radius = size.width / 2;
    final Offset center = Offset(radius, radius);

    // Vẽ nền tròn đầy đủ trước
    canvas.drawCircle(center, radius, backgroundPaint);

    // Tính toán góc cho phần thời gian CÒN LẠI, vẽ theo chiều kim đồng hồ
    final double remainingFraction = secondsRemaining / 30.0;
    final double elapsedFraction = 1.0 - remainingFraction;

    // Góc bắt đầu là vị trí 12h (-pi/2) cộng với góc đã trôi qua
    final double elapsedAngle = elapsedFraction * 2 * math.pi;
    final double startAngle = -math.pi / 2 + elapsedAngle;

    // Góc quét là phần còn lại
    final double sweepAngle = remainingFraction * 2 * math.pi;

    // Vẽ cung tròn được tô màu (giống miếng bánh pizza)
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      startAngle,
      sweepAngle,
      true, // useCenter: true để vẽ thành hình rẻ quạt
      progressPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _SolidCountdownPainter oldDelegate) {
    // Chỉ vẽ lại nếu giây thay đổi
    return oldDelegate.secondsRemaining != secondsRemaining ||
        oldDelegate.progressColor != progressColor ||
        oldDelegate.backgroundColor != backgroundColor;
  }
}
