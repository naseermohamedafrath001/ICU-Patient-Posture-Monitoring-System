class ChatUser {
  final String username;
  final String name;
  final String role;
  final String? photoUrl;
  final String? lastMessage;
  final String? lastTimestamp;
  final String? phone;
  final String? nurseId;
  final String? joinedDate;
  final String? address;
  final bool isOnline;
  final int unreadCount;

  ChatUser({
    required this.username,
    required this.name,
    required this.role,
    this.photoUrl,
    this.lastMessage,
    this.lastTimestamp,
    this.phone,
    this.nurseId,
    this.joinedDate,
    this.address,
    this.isOnline = false,
    this.unreadCount = 0,
  });

  factory ChatUser.fromJson(Map<String, dynamic> json) {
    return ChatUser(
      username: json['username'],
      name: json['name'],
      role: json['role'],
      photoUrl: json['photo_url'],
      lastMessage: json['last_message'],
      lastTimestamp: json['last_timestamp'],
      phone: json['phone']?.toString(),
      nurseId: json['nurse_id']?.toString(),
      joinedDate: json['joined_date'],
      address: json['address'],
      isOnline: json['is_online'] == 1,
      unreadCount: json['unread_count'] ?? 0,
    );
  }
}
