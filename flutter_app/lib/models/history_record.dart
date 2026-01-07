class HistoryRecord {
  final String id;
  final String? patientId;
  final String? patientName;
  final String? prediction;
  final double? confidence;
  final String timestamp;
  final String? type; // 'critical', 'warning', 'info'
  final bool isAlert;
  final String? position; // For alerts
  final String? duration; // For alerts
  final String? acknowledgedBy; // For alerts

  HistoryRecord({
    required this.id,
    this.patientId,
    this.patientName,
    this.prediction,
    this.confidence,
    required this.timestamp,
    this.type,
    this.isAlert = false,
    this.position,
    this.duration,
    this.acknowledgedBy,
  });

  factory HistoryRecord.fromJson(Map<String, dynamic> json) {
    return HistoryRecord(
      id: json['id'] ?? '',
      patientId: json['patientId'],
      patientName: json['patientName'],
      prediction: json['prediction'],
      confidence: json['confidence'] != null ? (json['confidence'] as num).toDouble() : null,
      timestamp: json['timestamp'] ?? '',
      type: json['type'],
      isAlert: json['isAlert'] ?? false,
      position: json['position'],
      duration: json['duration'],
      acknowledgedBy: json['acknowledged_by'] ?? json['acknowledgedBy'],
    );
  }
}
