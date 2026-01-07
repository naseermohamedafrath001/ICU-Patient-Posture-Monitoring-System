import 'package:flutter/material.dart';

import '../models/analysis_result.dart';

class ResultCard extends StatelessWidget {
  final AnalysisResult result;

  const ResultCard({super.key, required this.result});

  @override
  Widget build(BuildContext context) {
    return Card(
      // Card color comes from Theme (white)
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.bar_chart, color: Color(0xFF1E88E5)),
                SizedBox(width: 8),
                Text(
                  'Analysis Results',
                  style: TextStyle(
                    color: Color(0xFF37474F),
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const Divider(color: Colors.grey),
            const SizedBox(height: 16),
            _buildPredictionInfo(),
            const SizedBox(height: 24),

            if (result.framePredictions != null) _buildFrameAnalysis(),
          ],
        ),
      ),
    );
  }

  Widget _buildPredictionInfo() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Detected Body Position:', style: TextStyle(color: Colors.grey)),
        const SizedBox(height: 4),
        Text(
          result.prediction ?? 'Unknown',
          style: const TextStyle(
            color: Color(0xFF1E88E5),
            fontSize: 24,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: const Color(0xFF1E88E5).withOpacity(0.1),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFF1E88E5)),
          ),
          child: Text(
            'Confidence: ${(result.confidence != null ? (result.confidence! * 100).toStringAsFixed(1) : "0.0")}%',
            style: const TextStyle(color: Color(0xFF1E88E5), fontWeight: FontWeight.bold),
          ),
        ),
      ],
    );
  }



  Widget _buildFrameAnalysis() {
    // 1. Filter for transitions
    List<FramePrediction> transitions = [];
    if (result.framePredictions != null && result.framePredictions!.isNotEmpty) {
      // Always add the first one
      transitions.add(result.framePredictions!.first);
      
      for (int i = 1; i < result.framePredictions!.length; i++) {
        if (result.framePredictions![i].prediction != result.framePredictions![i-1].prediction) {
          transitions.add(result.framePredictions![i]);
        }
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 24),
        const Text(
          'Timeline of Movements',
          style: TextStyle(
            color: Color(0xFF37474F),
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        const Text(
           'Shows when the patient changed positions during the video.',
           style: TextStyle(color: Colors.grey, fontSize: 13),
        ),
        const SizedBox(height: 20),
        
        ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: transitions.length,
          itemBuilder: (context, index) {
            final frame = transitions[index];
            final isSupine = frame.prediction.toLowerCase().contains('supine');
            final isLeft = frame.prediction.toLowerCase().contains('left');
            
            IconData icon;
            Color color;
            String label;

            if (isSupine) {
              icon = Icons.bed;
              color = Colors.blue;
              label = 'Supine';
            } else if (isLeft) {
              icon = Icons.airline_seat_flat;
              color = Colors.orange;
              label = 'Left Lateral';
            } else {
              icon = Icons.airline_seat_flat_angled;
              color = Colors.green;
              label = 'Right Lateral';
            }

            final isLast = index == transitions.length - 1;

            return IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Timeline Line & Dot
                  SizedBox(
                    width: 40,
                    child: Column(
                      children: [
                        Container(
                          width: 12,
                          height: 12,
                          decoration: BoxDecoration(
                            color: color,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 2),
                            boxShadow: [
                              BoxShadow(
                                color: color.withOpacity(0.4),
                                blurRadius: 4,
                                spreadRadius: 1,
                              ),
                            ],
                          ),
                        ),
                        if (!isLast)
                          Expanded(
                            child: Container(
                              width: 2,
                              color: Colors.grey.withOpacity(0.2),
                            ),
                          ),
                      ],
                    ),
                  ),
                  
                  // Content
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(8, 0, 0, 24),
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.grey.withOpacity(0.1)),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF64748B).withOpacity(0.05),
                              blurRadius: 8,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: color.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Icon(icon, color: color, size: 20),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    label,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFF1E293B),
                                      fontSize: 16,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    index == 0 ? 'Initial Position' : 'Changed to $label',
                                    style: TextStyle(
                                      color: Colors.grey[600],
                                      fontSize: 13,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF1F5F9),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Row(
                                children: [
                                  const Icon(Icons.access_time, size: 14, color: Color(0xFF64748B)),
                                  const SizedBox(width: 4),
                                  Text(
                                    frame.timestampFormatted.isNotEmpty ? frame.timestampFormatted : '00:00', 
                                    style: const TextStyle(
                                      color: Color(0xFF475569),
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ],
    );
  }
}
