import 'package:flutter/material.dart';

void showSnack(BuildContext context, String text, {bool error = false}) {
  final messenger = ScaffoldMessenger.of(context);
  messenger.hideCurrentSnackBar();
  messenger.showSnackBar(SnackBar(
    content: Text(text),
    backgroundColor: error ? Theme.of(context).colorScheme.error : null,
    duration: Duration(seconds: error ? 6 : 3),
  ));
}

void showError(BuildContext context, Object e) =>
    showSnack(context, e.toString(), error: true);

/// A "esfera" da Consart (avatar), com brilho quando está ativa.
class ConsartOrb extends StatelessWidget {
  final double size;
  final bool glow;
  const ConsartOrb({super.key, this.size = 40, this.glow = false});

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const RadialGradient(
          center: Alignment(-0.3, -0.3),
          colors: [Color(0xFFB8ECFF), Color(0xFF2B8CFF), Color(0xFF5B2BD9)],
          stops: [0.0, 0.55, 1.0],
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF5FB8FF).withValues(alpha: glow ? 0.8 : 0.45),
            blurRadius: glow ? size * 0.35 : size * 0.15,
            spreadRadius: glow ? size * 0.05 : 0,
          ),
        ],
      ),
    );
  }
}
