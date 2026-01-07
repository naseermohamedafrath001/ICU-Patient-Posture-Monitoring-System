import 'package:flutter/material.dart';

class ChatNotification extends StatelessWidget {
  final String senderName;
  final String messageSnippet;
  final String? photoUrl;
  final VoidCallback onTap;
  final VoidCallback onDismiss;

  const ChatNotification({
    super.key,
    required this.senderName,
    required this.messageSnippet,
    this.photoUrl,
    required this.onTap,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Dismissible(
          key: UniqueKey(),
          direction: DismissDirection.horizontal,
          onDismissed: (_) => onDismiss(),
          child: GestureDetector(
            onTap: onTap,
            child: Material(
              color: Colors.transparent,
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: Theme.of(context).colorScheme.primary.withOpacity(0.08),
                      blurRadius: 20,
                      offset: const Offset(0, 10),
                    ),
                  ],
                  border: Border.all(
                    color: Theme.of(context).colorScheme.primary.withOpacity(0.05),
                    width: 1,
                  ),
                ),
                child: Row(
                  children: [
                    // App Icon / Indicator
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.mark_chat_unread_rounded,
                        color: Theme.of(context).colorScheme.primary,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 16),
                    
                    // Text Info
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                senderName,
                                style: const TextStyle(
                                  color: Color(0xFF1E293B),
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                  fontFamily: 'Gilroy',
                                ),
                              ),
                              Text(
                                'just now',
                                style: TextStyle(
                                  color: const Color(0xFF94A3B8).withOpacity(0.8),
                                  fontSize: 11,
                                  fontWeight: FontWeight.w500,
                                  fontFamily: 'Gilroy',
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(
                            messageSnippet.length > 50 
                                ? '${messageSnippet.substring(0, 47)}...' 
                                : messageSnippet,
                            style: const TextStyle(
                              color: Color(0xFF64748B),
                              fontSize: 14,
                              fontFamily: 'Gilroy',
                              fontWeight: FontWeight.w400,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 16),
                    
                    // Avatar
                    Container(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
                          width: 2,
                        ),
                      ),
                      child: CircleAvatar(
                        radius: 20,
                        backgroundColor: const Color(0xFFF1F5F9),
                        backgroundImage: photoUrl != null ? NetworkImage(photoUrl!) : null,
                        child: photoUrl == null 
                            ? const Icon(Icons.person, color: Color(0xFF94A3B8)) 
                            : null,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
