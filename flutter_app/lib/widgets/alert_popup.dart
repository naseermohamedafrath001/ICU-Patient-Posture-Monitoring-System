import 'package:flutter/material.dart';

class AlertPopup extends StatefulWidget {
  final String patientName;
  final String position;
  final String duration;
  final VoidCallback onAcknowledge;

  const AlertPopup({
    super.key,
    required this.patientName,
    required this.position,
    required this.duration,
    required this.onAcknowledge,
  });

  @override
  State<AlertPopup> createState() => _AlertPopupState();
}

class _AlertPopupState extends State<AlertPopup> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<Color?> _colorAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    )..repeat(reverse: true);

    _colorAnimation = ColorTween(
      begin: Colors.red,
      end: Colors.transparent,
    ).animate(_controller);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _colorAnimation,
      builder: (context, child) {
        return Dialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: _colorAnimation.value ?? Colors.red, width: 4),
          ),
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: _colorAnimation.value ?? Colors.red,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.warning_amber_rounded, color: Colors.white, size: 40),
                ),
                const SizedBox(height: 16),
                Text(
                  'CRITICAL ALERT',
                  style: TextStyle(
                    color: _colorAnimation.value ?? Colors.red,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Prolonged Static Position Detected!',
                  style: TextStyle(color: Colors.black87, fontSize: 16),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                _buildDetailRow('Patient:', widget.patientName),
                _buildDetailRow('Position:', widget.position),
                _buildDetailRow('Duration:', widget.duration),
                const SizedBox(height: 32),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: widget.onAcknowledge,
                    icon: const Icon(Icons.check_circle),
                    label: const Text('Acknowledge & Log'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.grey)),
          Text(
            value,
            style: const TextStyle(color: Colors.black87, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }
}
