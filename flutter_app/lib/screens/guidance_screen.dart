import 'package:flutter/material.dart';

class GuidanceScreen extends StatelessWidget {
  const GuidanceScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: ListView(
        padding: const EdgeInsets.all(16.0),
        children: const [
          GuidanceCard(
            title: 'Optimal Positioning',
            icon: Icons.bed,
            items: [
              'Reposition every 2 hours for bedridden patients',
              'Use 30-degree lateral tilt for side-lying positions',
              'Keep heels floating with pillow support',
              'Maintain natural body alignment',
              'Use pressure-relieving devices when indicated',
            ],
          ),
          SizedBox(height: 16),
          GuidanceCard(
            title: 'Risk Assessment',
            icon: Icons.shield,
            items: [
              'Use Braden Scale for pressure injury risk',
              'Assess skin integrity during position changes',
              'Monitor moisture and nutrition status',
              'Document all skin assessments',
              'Consider mobility and sensory perception',
            ],
          ),
          SizedBox(height: 16),
          GuidanceCard(
            title: 'Skin Inspection',
            icon: Icons.medical_services,
            items: [
              'Check bony prominences daily',
              'Look for redness that doesn\'t blanch',
              'Monitor temperature changes',
              'Assess for skin breakdown or blisters',
              'Document any changes immediately',
            ],
          ),
        ],
      ),
    );
  }
}

class GuidanceCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final List<String> items;

  const GuidanceCard({
    super.key,
    required this.title,
    required this.icon,
    required this.items,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      // Card color comes from Theme (white)
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: const Color(0xFF1E88E5), size: 24),
                const SizedBox(width: 12),
                Text(
                  title,
                  style: const TextStyle(
                    color: Color(0xFF37474F),
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const Divider(color: Colors.grey),
            const SizedBox(height: 8),
            ...items.map((item) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4.0),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.check_circle, color: Colors.green, size: 16),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          item,
                          style: const TextStyle(color: Colors.black87),
                        ),
                      ),
                    ],
                  ),
                )),
          ],
        ),
      ),
    );
  }
}
