import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

const appName = 'Tempuh';
const appCredit = 'Created by KangAIs';

class AppColors {
  static const navy = Color(0xFF0B1220);
  static const charcoal = Color(0xFF172033);
  static const card = Color(0xFF172033);
  static const raised = Color(0xFF243049);
  static const lime = Color(0xFFA3E635);
  static const route = Color(0xFFA3E635);
  static const text = Color(0xFFF1F5F9);
  static const soft = Color(0xFFCBD5E1);
  static const muted = Color(0xFF94A3B8);
  static const danger = Color(0xFFEF4444);
  static const amber = Color(0xFFFBBF24);
}

ThemeData buildTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: AppColors.lime,
    brightness: Brightness.dark,
  ).copyWith(
    primary: AppColors.lime,
    onPrimary: AppColors.navy,
    surface: AppColors.charcoal,
    onSurface: AppColors.text,
  );
  final base = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: scheme,
  );
  return base.copyWith(
    scaffoldBackgroundColor: AppColors.navy,
    textTheme: GoogleFonts.plusJakartaSansTextTheme(base.textTheme)
        .apply(bodyColor: AppColors.text, displayColor: AppColors.text),
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.navy,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
    ),
    cardTheme: const CardThemeData(
      color: AppColors.card,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(18))),
    ),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
  );
}

/// Logo Tempuh (T-Rute) digambar dengan CustomPainter, sama dengan ikon app.
class TempuhLogo extends StatelessWidget {
  final double size;
  final Color background;
  const TempuhLogo({super.key, this.size = 36, this.background = AppColors.charcoal});

  @override
  Widget build(BuildContext context) => SizedBox(
        width: size,
        height: size,
        child: CustomPaint(painter: _LogoPainter(background)),
      );
}

class _LogoPainter extends CustomPainter {
  final Color bg;
  _LogoPainter(this.bg);

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 108;
    canvas.scale(s);
    canvas.drawRRect(
        RRect.fromRectAndRadius(
            const Rect.fromLTWH(0, 0, 108, 108), const Radius.circular(26)),
        Paint()..color = bg);
    final stroke = Paint()
      ..color = AppColors.lime
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    final route = Path()
      ..moveTo(54, 32)
      ..cubicTo(54, 48, 38, 50, 40, 63)
      ..cubicTo(42, 76, 60, 74, 52, 86);
    canvas.drawPath(route, stroke..strokeWidth = 10);
    canvas.drawLine(const Offset(28, 30), const Offset(80, 30), stroke..strokeWidth = 11);
    canvas.drawCircle(const Offset(52, 86), 7, Paint()..color = AppColors.text);
  }

  @override
  bool shouldRepaint(covariant _LogoPainter old) => old.bg != bg;
}
