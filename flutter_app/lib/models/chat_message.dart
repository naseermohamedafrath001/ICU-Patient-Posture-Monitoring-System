class ChatMessage {
  final int? id;
  final String sender;
  final String recipient;
  final String text;
  final DateTime timestamp;
  final bool isRead;
  final String type; // 'text' or 'voice'
  final String? mediaUrl;

  ChatMessage({
    this.id,
    required this.sender,
    required this.recipient,
    required this.text,
    required this.timestamp,
    this.isRead = false,
    this.type = 'text',
    this.mediaUrl,
  });

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    return ChatMessage(
      id: json['id'],
      sender: json['sender_username'],
      recipient: json['recipient_username'],
      text: json['text'] ?? '',
      timestamp: DateTime.parse(json['timestamp']),
      isRead: json['is_read'] == 1,
      type: json['type'] ?? 'text',
      mediaUrl: json['media_url'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'sender': sender,
      'recipient': recipient,
      'text': text,
      'type': type,
      'media_url': mediaUrl,
    };
  }
}
