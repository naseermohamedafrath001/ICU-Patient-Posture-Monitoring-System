class User {
  final String username;
  final String role;
  final String name;
  final String? photoUrl;
  final String? phone;
  final String? nurseId;
  final String? joinedDate;
  final String? address;

  User({
    required this.username,
    required this.role,
    required this.name,
    this.photoUrl,
    this.phone,
    this.nurseId,
    this.joinedDate,
    this.address,
  });

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      username: json['username'],
      role: json['role'],
      name: json['name'],
      photoUrl: json['photo_url'] ?? json['photoUrl'],
      phone: json['phone'],
      nurseId: json['nurse_id'] ?? json['nurseId'],
      joinedDate: json['joined_date'] ?? json['joinedDate'],
      address: json['address'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'username': username,
      'role': role,
      'name': name,
      'photo_url': photoUrl,
      'phone': phone,
      'nurse_id': nurseId,
      'joined_date': joinedDate,
      'address': address,
    };
  }
}
