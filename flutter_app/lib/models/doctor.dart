class Doctor {
  final String id;
  final String name;
  final String position;
  final String specialty;
  final String dutyTime;
  final String joinedDate;
  final String contact;
  final String? photoUrl;

  Doctor({
    required this.id,
    required this.name,
    required this.position,
    required this.specialty,
    required this.dutyTime,
    required this.joinedDate,
    required this.contact,
    this.photoUrl,
  });

  factory Doctor.fromJson(Map<String, dynamic> json) {
    return Doctor(
      id: json['id'],
      name: json['name'],
      position: json['position'],
      specialty: json['specialty'],
      dutyTime: json['duty_time'] ?? json['dutyTime'] ?? '',
      joinedDate: json['joined_date'] ?? json['joinedDate'] ?? '',
      contact: json['contact'] ?? '',
      photoUrl: json['photo_url'] ?? json['photoUrl'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'position': position,
      'specialty': specialty,
      'duty_time': dutyTime,
      'joined_date': joinedDate,
      'contact': contact,
      'photo_url': photoUrl,
    };
  }

  bool isOnDuty() {
    if (dutyTime.isEmpty) return false;
    try {
      // Expected format: "14:00 - 16:30 PM" or "10:00 - 14:00 PM"
      final parts = dutyTime.split('-');
      if (parts.length != 2) return false;

      String startStr = parts[0].trim();
      String endWithPeriod = parts[1].trim();

      // Determine period (AM/PM) - usually the entire range is either AM or PM or spans them.
      // Based on provided strings like "14:00 - 16:30 PM", we assume 24h format but with a period suffix.
      bool isPM = endWithPeriod.toUpperCase().contains('PM');
      
      String cleanStart = startStr.replaceAll(RegExp(r'[^0-9:]'), '');
      String cleanEnd = endWithPeriod.replaceAll(RegExp(r'[^0-9:]'), '');

      final startParts = cleanStart.split(':');
      final endParts = cleanEnd.split(':');

      int startHour = int.parse(startParts[0]);
      int startMin = int.parse(startParts[1]);
      int endHour = int.parse(endParts[0]);
      int endMin = int.parse(endParts[1]);

      // If it's a 12h format or something similar, it might need more logic
      // But given "14:00", "16:00", etc., it's 24h format. 
      // If startHour < 12 and it's PM, should we add 12?
      // Usually "14:00" is already PM. Let's assume 24h format as the primary source.

      final now = DateTime.now();
      final startTime = DateTime(now.year, now.month, now.day, startHour, startMin);
      final endTime = DateTime(now.year, now.month, now.day, endHour, endMin);

      return now.isAfter(startTime) && now.isBefore(endTime);
    } catch (e) {
      print('Error parsing duty time for $name: $e');
      return false;
    }
  }
}
