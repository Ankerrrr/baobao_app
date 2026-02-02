import 'dart:math';
import 'package:flutter/material.dart';

class ArcMenuItem {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? textColor;

  ArcMenuItem({
    required this.icon,
    required this.label,
    required this.onTap,
    this.textColor,
  });
}

class RainbowArcMenuOverlay extends StatefulWidget {
  final Offset anchor; // 寶寶中心點（global）
  final List<ArcMenuItem> items;
  final VoidCallback onClose;

  const RainbowArcMenuOverlay({
    super.key,
    required this.anchor,
    required this.items,
    required this.onClose,
  });

  @override
  State<RainbowArcMenuOverlay> createState() => _RainbowArcMenuOverlayState();
}

class _RainbowArcMenuOverlayState extends State<RainbowArcMenuOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    )..forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 弧形參數（你可以調）
    final radius = 180.0; // 弧形半徑
    final startAngle = -pi * 5 / 6; // 左上
    final endAngle = -pi * 1 / 6; // 右上

    return Material(
      color: const Color.fromARGB(0, 232, 14, 14),
      child: Stack(
        children: [
          // 點背景關掉
          Positioned.fill(
            child: GestureDetector(
              onTap: widget.onClose,
              behavior: HitTestBehavior.opaque,
              child: const SizedBox.expand(),
            ),
          ),

          // 彩虹弧線（畫在寶寶上方）
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(
                painter: _RainbowArcPainter(
                  anchor: widget.anchor,
                  radius: radius,
                  startAngle: startAngle,
                  endAngle: endAngle,
                ),
              ),
            ),
          ),

          // 弧形按鈕
          ..._buildArcButtons(
            context,
            anchor: widget.anchor,
            items: widget.items,
            radius: radius,
            startAngle: startAngle,
            endAngle: endAngle,
          ),
        ],
      ),
    );
  }

  List<Widget> _buildArcButtons(
    BuildContext context, {
    required Offset anchor,
    required List<ArcMenuItem> items,
    required double radius,
    required double startAngle,
    required double endAngle,
  }) {
    final n = items.length;
    if (n == 0) return [];

    return List.generate(n, (i) {
      const edgePadding = 0.12; // 靠邊一點
      final t = (n == 1)
          ? 0.5
          : edgePadding + (1 - 2 * edgePadding) * (i / (n - 1));
      final angle = startAngle + (endAngle - startAngle) * t;

      final dx = cos(angle) * radius;
      final dy = sin(angle) * radius;

      // global -> Positioned 的 left/top
      final left = anchor.dx + dx - 28; // 56px 按鈕半徑
      final top = anchor.dy + dy - 70;

      return Positioned(
        left: left,
        top: top,
        child: FadeTransition(
          opacity: _ctrl,
          child: ScaleTransition(
            scale: Tween<double>(
              begin: 0.8,
              end: 1.0,
            ).chain(CurveTween(curve: Curves.easeOutBack)).animate(_ctrl),
            child: _ArcButton(item: items[i]),
          ),
        ),
      );
    });
  }
}

class _ArcButton extends StatelessWidget {
  final ArcMenuItem item;
  const _ArcButton({required this.item});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Material(
          color: Colors.orange,
          elevation: 6,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: item.onTap,
            child: const SizedBox(
              width: 56,
              height: 56,
              child: Center(child: Icon(Icons.circle)), // 先放占位
            ),
          ),
        ),

        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.9),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            item.label,
            style: TextStyle(
              fontSize: 17,
              color: item.textColor ?? Colors.white,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}

class _RainbowArcPainter extends CustomPainter {
  final Offset anchor;
  final double radius;
  final double startAngle;
  final double endAngle;

  _RainbowArcPainter({
    required this.anchor,
    required this.radius,
    required this.startAngle,
    required this.endAngle,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromCircle(center: anchor, radius: radius);

    // 簡單的彩虹（多條不同粗細弧線）
    final colors = [
      Colors.red,
      Colors.orange,
      Colors.yellow,
      Colors.green,
      Colors.blue,
      Colors.purple,
    ];

    for (int i = 0; i < colors.length; i++) {
      final paint = Paint()
        ..color = colors[i].withOpacity(0.9)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 10
        ..strokeCap = StrokeCap.round;

      final r = Rect.fromCircle(
        center: anchor.translate(0, -70),
        radius: radius - i * 8,
      );
      canvas.drawArc(r, startAngle, endAngle - startAngle, false, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _RainbowArcPainter oldDelegate) {
    return oldDelegate.anchor != anchor ||
        oldDelegate.radius != radius ||
        oldDelegate.startAngle != startAngle ||
        oldDelegate.endAngle != endAngle;
  }
}
