class Patient {
  final String id;
  final String name;
  final String age;
  final String? room;
  final String? condition;
  final String? timestamp;

  Patient({
    required this.id,
    required this.name,
    required this.age,
    this.room,
    this.condition,
    this.timestamp,
  });

  factory Patient.fromJson(Map<String, dynamic> json) {
    return Patient(
      id: json['id'],
      name: json['name'],
      age: json['age'].toString(),
      room: json['room'],
      condition: json['condition'],
      timestamp: json['timestamp'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'age': age,
      'room': room,
      'condition': condition,
      'timestamp': timestamp,
    };
  }
}
