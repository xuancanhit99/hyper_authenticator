import 'package:flutter/material.dart';

/// Giữ nội dung đọc/form ở độ rộng hợp lý trên desktop nhưng vẫn dùng toàn bộ
/// chiều rộng khả dụng trên màn hình nhỏ.
class MaxWidthContent extends StatelessWidget {
  const MaxWidthContent({
    required this.child,
    this.maxWidth = 760,
    this.alignment = Alignment.topCenter,
    super.key,
  });

  final Widget child;
  final double maxWidth;
  final AlignmentGeometry alignment;

  @override
  Widget build(BuildContext context) => Align(
    alignment: alignment,
    child: ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: SizedBox(width: double.infinity, child: child),
    ),
  );
}

/// Scrollable body responsive dành cho form cần căn giữa theo cả hai trục.
class ResponsiveScrollableContent extends StatelessWidget {
  const ResponsiveScrollableContent({
    required this.child,
    this.maxWidth = 480,
    this.padding = const EdgeInsets.all(24),
    super.key,
  });

  final Widget child;
  final double maxWidth;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final minHeight = (constraints.maxHeight - padding.vertical).clamp(
        0.0,
        double.infinity,
      );
      return SingleChildScrollView(
        padding: padding,
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: maxWidth,
              minHeight: minHeight,
            ),
            child: SizedBox(width: double.infinity, child: child),
          ),
        ),
      );
    },
  );
}
