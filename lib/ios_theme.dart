// Hệ thiết kế iOS — giống AppTheme.swift của app ChamCongHieuIT:
// indigo #4554D9, blue #1F7AF5, teal #0DC4A8, gradient thương hiệu
// indigo → blue → teal theo đường chéo, nền trang xám nhạt #F2F2F7,
// thẻ trắng bo 20 + bóng đen 5% + viền đen 7%.
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

const iosIndigo = Color(0xFF4554D9);
const iosBlue = Color(0xFF1F7AF5);
const iosTeal = Color(0xFF0DC4A8);
const iosTealDark = Color(0xFF0A9C86);
const iosPageBg = Color(0xFFF2F2F7);
const iosLabel = Color(0xFF1C1C1E);
const iosSecondary = Color(0xFF6E6E73);
const iosBorder = Color(0x12000000); // đen 7%
const iosRed = Color(0xFFFF3B30);
const iosOrange = Color(0xFFFF9500);
const iosPink = Color(0xFFFF2D55);

const iosBrandGradient = LinearGradient(
  colors: [iosIndigo, iosBlue, iosTeal],
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
);

const iosSoftBrandGradient = LinearGradient(
  colors: [Color(0x244554D9), Color(0x140DC4A8)], // indigo 14% → teal 8%
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
);

// Màu trạng thái ca — giống WorkStatus.tintColor bên iOS.
Color statusTint(String status) {
  switch (status) {
    case 'work':
      return iosTeal;
    case 'paidLeave':
      return iosBlue;
    case 'unpaidLeave':
      return iosOrange;
    case 'holiday':
      return iosPink;
    default:
      return iosTeal;
  }
}

/// Thẻ trắng kiểu iOS (appCard): bo góc 20, bóng đen 5% (blur 12, y 5),
/// viền 1px đen 7%.
class AppCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  const AppCard(
      {super.key,
      required this.child,
      this.padding = const EdgeInsets.all(16)});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: iosBorder),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 12,
              offset: const Offset(0, 5)),
        ],
      ),
      child: child,
    );
  }
}

/// Tiêu đề mục (AppSectionHeader): icon + chữ semibold màu xám phụ.
class AppSectionHeader extends StatelessWidget {
  final IconData icon;
  final String title;
  const AppSectionHeader({super.key, required this.icon, required this.title});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 15, color: iosSecondary),
        const SizedBox(width: 6),
        Text(title,
            style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: iosSecondary)),
      ],
    );
  }
}

/// Ô icon vuông bo góc (IconTile): nền màu tint 12%, icon màu tint.
class IconTile extends StatelessWidget {
  final IconData icon;
  final Color tint;
  const IconTile({super.key, required this.icon, required this.tint});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: tint.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(11),
      ),
      child: Icon(icon, size: 16, color: tint),
    );
  }
}

/// 1 chỉ số trong thẻ tổng quan gradient (MetricItem): icon + số đậm + nhãn.
class MetricData {
  final IconData icon;
  final String value;
  final String title;
  const MetricData({required this.icon, required this.value, required this.title});
}

class GradientSummaryCard extends StatelessWidget {
  final List<MetricData> metrics;
  const GradientSummaryCard({super.key, required this.metrics});

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[];
    for (var i = 0; i < metrics.length; i++) {
      if (i > 0) {
        children.add(const SizedBox(width: 12));
        children.add(Container(
          width: 1,
          height: 52,
          color: Colors.white.withValues(alpha: 0.24),
        ));
        children.add(const SizedBox(width: 12));
      }
      final m = metrics[i];
      children.add(Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(m.icon,
                size: 15,
                color: Colors.white.withValues(alpha: 0.82)),
            const SizedBox(height: 8),
            Text(m.value,
                maxLines: 1,
                style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.white)),
            const SizedBox(height: 2),
            Text(m.title,
                maxLines: 1,
                style: TextStyle(
                    fontSize: 12,
                    color: Colors.white.withValues(alpha: 0.78))),
          ],
        ),
      ));
    }
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: iosBrandGradient,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
              color: iosIndigo.withValues(alpha: 0.2),
              blurRadius: 14,
              offset: const Offset(0, 8)),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: children,
      ),
    );
  }
}

/// Nút chính (PrimaryActionButtonStyle): nền gradient thương hiệu,
/// chữ trắng, bo góc 14, cao ~48.
class PrimaryButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final IconData? icon;
  final String label;
  const PrimaryButton(
      {super.key, required this.label, this.icon, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: onPressed == null ? 0.45 : 1,
      child: Container(
        decoration: BoxDecoration(
          gradient: iosBrandGradient,
          borderRadius: BorderRadius.circular(14),
        ),
        child: CupertinoButton(
          padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 16),
          onPressed: onPressed,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (icon != null) ...[
                Icon(icon, color: Colors.white, size: 18),
                const SizedBox(width: 6),
              ],
              Text(label,
                  style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                      color: Colors.white)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Nút phụ (TintedActionButtonStyle): nền màu tint 11%, chữ màu tint.
class TintedButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final IconData? icon;
  final String label;
  final Color tint;
  const TintedButton(
      {super.key,
      required this.label,
      required this.tint,
      this.icon,
      required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: onPressed == null ? 0.45 : 1,
      child: Container(
        decoration: BoxDecoration(
          color: tint.withValues(alpha: 0.11),
          borderRadius: BorderRadius.circular(13),
        ),
        child: CupertinoButton(
          padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 14),
          onPressed: onPressed,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (icon != null) ...[
                Icon(icon, color: tint, size: 17),
                const SizedBox(width: 6),
              ],
              Text(label,
                  style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: tint)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Chuyển tháng (MonthSwitcher): thẻ trắng, 2 nút tròn chevron nền
/// indigo 10%, giữa là "BẢNG CÔNG" nhỏ in hoa + tên tháng đậm.
class MonthSwitcher extends StatelessWidget {
  final String monthLabel;
  final VoidCallback onPrev;
  final VoidCallback onNext;
  const MonthSwitcher(
      {super.key,
      required this.monthLabel,
      required this.onPrev,
      required this.onNext});

  Widget _chevron(IconData icon, VoidCallback onPressed) {
    return CupertinoButton(
      padding: EdgeInsets.zero,
      minimumSize: Size.zero,
      onPressed: onPressed,
      child: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: iosIndigo.withValues(alpha: 0.1),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, size: 16, color: iosIndigo),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          _chevron(Icons.chevron_left, onPrev),
          Expanded(
            child: Column(
              children: [
                const Text('BẢNG CÔNG',
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.1,
                        color: iosSecondary)),
                const SizedBox(height: 3),
                Text(monthLabel,
                    style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                        color: iosLabel)),
              ],
            ),
          ),
          _chevron(Icons.chevron_right, onNext),
        ],
      ),
    );
  }
}
