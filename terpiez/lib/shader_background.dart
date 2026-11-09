import 'dart:ui';
import 'package:flutter/material.dart';

class ShaderBackground extends StatefulWidget {
  const ShaderBackground({super.key});

  @override
  State<ShaderBackground> createState() => _ShaderBackgroundState();
}

class _ShaderBackgroundState extends State<ShaderBackground>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  FragmentProgram? _program;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1), // not sure why this is needed
    )..repeat();
    
    _loadShader();
  }

  Future<void> _loadShader() async {
    final program = await FragmentProgram.fromAsset('shaders/sliding_bars.frag');
    if (mounted) {
      setState(() {
        _program = program;
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_program == null) return const SizedBox.shrink();

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return SizedBox.expand( 
          child: CustomPaint(
            painter: _BarsPainter(
              shader: _program!.fragmentShader(),
              time: _controller.lastElapsedDuration?.inMilliseconds.toDouble() ?? 0.0,
            ),
          ),
        );
      },
    );
  }
}

class _BarsPainter extends CustomPainter {
  final FragmentShader shader;
  final double time;
  _BarsPainter({required this.shader, required this.time});

  @override
  void paint(Canvas canvas, Size size) {
    shader.setFloat(0, size.width); 
    shader.setFloat(1, size.height); 
    shader.setFloat(2, time / 1000.0);

    canvas.drawRect(Offset.zero & size, Paint()..shader = shader);
  }

  @override
  bool shouldRepaint(_BarsPainter old) => old.time != time;
}