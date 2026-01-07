import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:record/record.dart';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:cross_file/cross_file.dart'; // Ensure XFile is available if not already via record
import 'package:audioplayers/audioplayers.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:io';
import '../services/api_service.dart';
import '../models/chat_message.dart';
import '../models/chat_user.dart';
import '../models/user.dart';

class ChatDetailScreen extends StatefulWidget {
  final User currentUser;
  final ChatUser recipient;

  const ChatDetailScreen({
    super.key,
    required this.currentUser,
    required this.recipient,
  });

  @override
  State<ChatDetailScreen> createState() => _ChatDetailScreenState();
}

class _ChatDetailScreenState extends State<ChatDetailScreen> {
  final _apiService = ApiService();
  final _messageController = TextEditingController();
  final _scrollController = ScrollController();
  final _audioRecorder = AudioRecorder();
  final _audioPlayer = AudioPlayer();
  
  List<ChatMessage> _messages = [];
  Timer? _pollingTimer;
  bool _isLoading = true;
  bool _isRecording = false;
  bool _isRecorderInitializing = false;
  String? _recordingPath;
  String? _currentlyPlayingUrl;
  DateTime? _recordingStartTime;
  String? _baseUrl;
  late bool _isRecipientOnline;

  @override
  void initState() {
    super.initState();
    _isRecipientOnline = widget.recipient.isOnline;
    _fetchMessages();
    // Start polling every 3 seconds
    _pollingTimer = Timer.periodic(const Duration(seconds: 3), (_) => _fetchMessages(silent: true));
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
    _messageController.dispose();
    _scrollController.dispose();
    _audioRecorder.dispose();
    _audioPlayer.dispose();
    super.dispose();
  }

  Future<void> _startRecording() async {
    try {
      if (await _audioRecorder.hasPermission()) {
        print('DEBUG: Microphone permission granted');
        
        final config = const RecordConfig();
        
        // --- WEB SPECIFIC LOGIC ---
        if (kIsWeb) {
           // On Web, we stream to memory/blob, so we don't provide a path.
           // The record package handles this when path is null/undefined on web.
           await _audioRecorder.start(config, path: ''); 
        } else {
           // --- MOBILE/DESKTOP SPECIFIC ---
           final directory = Directory.systemTemp;
           _recordingPath = '${directory.path}/voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
           await _audioRecorder.start(config, path: _recordingPath!);
        }
        
        setState(() => _isRecorderInitializing = true);
        
        if (mounted) {
          setState(() {
            _isRecording = true;
            _isRecorderInitializing = false;
            _recordingStartTime = DateTime.now();
          });
        }
        print('DEBUG: Recording started');
      } else {
        print('DEBUG: Microphone permission denied');
        if (mounted) {
           ScaffoldMessenger.of(context).showSnackBar(
             const SnackBar(content: Text('Microphone permission denied')),
           );
        }
      }
    } catch (e) {
      print('Error starting recording: $e');
       if (mounted) {
           ScaffoldMessenger.of(context).showSnackBar(
             SnackBar(content: Text('Error starting recording: $e')),
           );
        }
    }
  }

  Future<void> _stopAndSendRecording() async {
    print('DEBUG: Attempting to stop recording...');
    
    while (_isRecorderInitializing) {
      await Future.delayed(const Duration(milliseconds: 100));
    }

    if (!_isRecording) {
      return;
    }

    try {
      final path = await _audioRecorder.stop();
      final duration = _recordingStartTime != null 
          ? DateTime.now().difference(_recordingStartTime!) 
          : Duration.zero;
          
      print('DEBUG: Recording stopped, path: $path, duration: ${duration.inMilliseconds}ms');
      
      setState(() {
        _isRecording = false;
        _recordingStartTime = null;
      });
      
      if (path != null && duration.inMilliseconds > 200) {
        if (mounted) {
           ScaffoldMessenger.of(context).showSnackBar(
             const SnackBar(content: Text('Sending voice message...'), duration: Duration(milliseconds: 500)),
           );
        }

        // --- CROSS PLATFORM UPLOAD ---
        // Create an XFile from the path (works for local file path AND web blob URLs)
        final file = XFile(path);
        
        final mediaUrl = await _apiService.uploadChatAudio(file);
        
        if (mediaUrl != null) {
          await _apiService.sendMessage(
            widget.currentUser.username,
            widget.recipient.username,
            '', 
            type: 'voice',
            mediaUrl: mediaUrl,
          );
          _playSentSound();
          _fetchMessages(silent: true);
        } else {
            if (mounted) {
               ScaffoldMessenger.of(context).showSnackBar(
                 const SnackBar(content: Text('Failed to upload audio.')),
               );
            }
        }
      } else if (duration.inMilliseconds <= 200) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Hold longer to record'), duration: Duration(seconds: 1)),
          );
        }
      }
    } catch (e) {
      print('DEBUG ERROR: Error stopping/sending recording: $e');
      if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error: $e')),
          );
      }
      setState(() {
        _isRecording = false;
        _isRecorderInitializing = false;
      });
    }
  }

  Future<void> _cancelRecording() async {
    await _audioRecorder.stop();
    setState(() => _isRecording = false);
  }

  Future<void> _fetchMessages({bool silent = false}) async {
    final baseUrl = await _apiService.getBaseUrl();
    try {
      // Also refresh recipient status periodically (every 2nd poll)
      if (DateTime.now().second % 6 < 3) {
        final users = await _apiService.getChatUsers(widget.currentUser.username);
        final currentRecipient = users.where((u) => u.username == widget.recipient.username).firstOrNull;
        if (currentRecipient != null && mounted) {
           if (_isRecipientOnline != currentRecipient.isOnline) {
             setState(() => _isRecipientOnline = currentRecipient.isOnline);
           }
        }
      }

      final history = await _apiService.getChatHistory(
        widget.currentUser.username,
        widget.recipient.username,
      );
      
      if (history.length != _messages.length) {
        if (mounted) {
          setState(() {
            _messages = history;
            _baseUrl = baseUrl;
            _isLoading = false;
          });
          _scrollToBottom();
        }
      } else if (!silent && mounted) {
        setState(() {
          _baseUrl = baseUrl;
          _isLoading = false;
        });
      }
    } catch (e) {
      print('Error fetching chat history: $e');
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;

    _messageController.clear();
    
    final success = await _apiService.sendMessage(
      widget.currentUser.username,
      widget.recipient.username,
      text,
    );

    if (success) {
      _playSentSound();
      _fetchMessages(silent: true);
    }
  }

  Future<void> _playSentSound() async {
    try {
      await _audioPlayer.stop();
      await _audioPlayer.setVolume(0.5); // Slightly lower volume for chat sound
      await _audioPlayer.play(AssetSource('sound/tick.mp3'));
    } catch (e) {
      print('Error playing sent sound: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            _buildCustomHeader(),
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
                ),
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator(color: Colors.white70))
                    : ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
                        itemCount: _messages.length,
                        itemBuilder: (context, index) {
                          final msg = _messages[index];
                          final isMe = msg.sender == widget.currentUser.username;
                          return _buildMessageBubble(msg, isMe);
                        },
                      ),
              ),
            ),
            Container(
              color: Theme.of(context).colorScheme.primary,
              child: _buildInputArea(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCustomHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Colors.grey.withOpacity(0.1))),
      ),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back, color: Color(0xFF1E293B)),
            onPressed: () => Navigator.pop(context),
          ),
          _buildProfileWithStatus(),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  widget.recipient.name,
                  style: const TextStyle(
                    color: Color(0xFF1E293B),
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'Gilroy',
                  ),
                ),
                Text(
                  _isRecipientOnline ? 'Online' : 'Offline',
                  style: TextStyle(
                    color: _isRecipientOnline ? const Color(0xFF4ADE80) : const Color(0xFF94A3B8),
                    fontSize: 13,
                    fontFamily: 'Gilroy',
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          _buildCircularAction(
            Icons.phone_rounded, 
            'Call', 
            () => _makePhoneCall(widget.recipient.phone ?? ''),
          ),
          const SizedBox(width: 8),
          _buildCircularAction(
            Icons.videocam_rounded, 
            'Video Call', 
            () => _showComingSoon('Video Calling'),
          ),
        ],
      ),
    );
  }

  Widget _buildCircularAction(IconData icon, String tooltip, VoidCallback onTap) {
    return Container(
      height: 40,
      width: 40,
      decoration: const BoxDecoration(
        color: Color(0xFFF8FAFC),
        shape: BoxShape.circle,
      ),
      child: IconButton(
        icon: Icon(icon, color: const Color(0xFF1E293B), size: 18),
        onPressed: onTap,
        padding: EdgeInsets.zero,
        tooltip: tooltip,
        splashRadius: 20,
      ),
    );
  }

  void _showComingSoon(String feature) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$feature coming soon!'),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Widget _buildProfileWithStatus() {
    final photoUrl = widget.recipient.photoUrl != null && _baseUrl != null
        ? '$_baseUrl${widget.recipient.photoUrl}'
        : null;

    return Stack(
      children: [
        CircleAvatar(
          radius: 22,
          backgroundColor: const Color(0xFFF1F5F9),
          backgroundImage: photoUrl != null ? NetworkImage(photoUrl) : null,
          child: photoUrl == null ? const Icon(Icons.person, color: Color(0xFF94A3B8)) : null,
        ),
        if (_isRecipientOnline)
          Positioned(
            right: 0,
            bottom: 0,
            child: Container(
              width: 14,
              height: 14,
              decoration: BoxDecoration(
                color: const Color(0xFF4ADE80),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2.5),
              ),
            ),
          ),
      ],
    );
  }

  Future<void> _makePhoneCall(String phoneNumber) async {
    if (phoneNumber.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Phone number not available for this staff'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    
    final Uri launchUri = Uri(scheme: 'tel', path: phoneNumber);
    try {
      if (await canLaunchUrl(launchUri)) {
        await launchUrl(launchUri);
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not launch phone dialer')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  Widget _buildMessageBubble(ChatMessage msg, bool isMe) {
    if (msg.type == 'image' || msg.type == 'video') {
       return Align(
        alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          margin: const EdgeInsets.only(bottom: 8),
          constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.7),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 5,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: FutureBuilder<String>(
              future: _apiService.getBaseUrl(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) return const SizedBox(height: 150, width: 200, child: Center(child: CircularProgressIndicator()));
                
                String baseUrl = snapshot.data ?? '';
                if (baseUrl.endsWith('/')) baseUrl = baseUrl.substring(0, baseUrl.length - 1);
                String cleanMediaUrl = msg.mediaUrl ?? '';
                if (!cleanMediaUrl.startsWith('/')) cleanMediaUrl = '/$cleanMediaUrl';
                final fullUrl = '$baseUrl$cleanMediaUrl';
                
                if (msg.type == 'image') {
                  return Image.network(
                    fullUrl,
                    fit: BoxFit.cover,
                    loadingBuilder: (context, child, loadingProgress) {
                      if (loadingProgress == null) return child;
                      return SizedBox(
                        height: 150,
                        width: 200,
                        child: Center(child: CircularProgressIndicator(value: loadingProgress.expectedTotalBytes != null ? loadingProgress.cumulativeBytesLoaded / loadingProgress.expectedTotalBytes! : null)),
                      );
                    },
                    errorBuilder: (context, error, stackTrace) => Container(
                      height: 150, 
                      width: 200, 
                      color: Colors.grey[200], 
                      child: const Column(
                        mainAxisAlignment: MainAxisAlignment.center, 
                        children: [Icon(Icons.broken_image, color: Colors.grey), SizedBox(height: 4), Text('Image Error', style: TextStyle(fontSize: 10, color: Colors.grey))],
                      ),
                    ),
                  );
                } else {
                  return GestureDetector(
                    onTap: () async {
                      if (await canLaunchUrl(Uri.parse(fullUrl))) {
                        await launchUrl(Uri.parse(fullUrl));
                      } else {
                         // Fallback or handle inline video play if implementing more complex player
                      }
                    },
                    child: Container(
                      width: 200,
                      height: 150,
                      color: Colors.black12,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          const Icon(Icons.play_circle_outline, size: 50, color: Color(0xFF4ADE80)),
                          Positioned(
                              bottom: 8,
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(4)),
                                child: const Text("Tap to Play", style: TextStyle(color: Colors.white, fontSize: 10)),
                              )
                          )
                        ],
                      ),
                    ),
                  );
                }
              },
            ),
          ),
        ),
      );
    }

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
        decoration: BoxDecoration(
          color: isMe ? Colors.white : Colors.white.withOpacity(0.2),
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(isMe ? 24 : 4),
            topRight: Radius.circular(isMe ? 4 : 24),
            bottomLeft: const Radius.circular(24),
            bottomRight: const Radius.circular(24),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            if (msg.type == 'voice')
              _buildVoicePlayer(msg.mediaUrl, isMe)
            else if (msg.type == 'file')
              _buildFileBubble(msg, isMe)
            else
              Text(
                msg.text,
                style: TextStyle(
                  color: isMe ? const Color(0xFF1E293B) : Colors.white,
                  fontSize: 15,
                  height: 1.4,
                  fontFamily: 'Gilroy',
                  fontWeight: isMe ? FontWeight.w500 : FontWeight.w400,
                ),
              ),
            const SizedBox(height: 6),
            Text(
              DateFormat('HH:mm').format(msg.timestamp),
              style: TextStyle(
                fontSize: 10,
                color: isMe ? Colors.grey[500] : Colors.white70,
                fontFamily: 'Gilroy',
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFileBubble(ChatMessage msg, bool isMe) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isMe ? const Color(0xFFF1F5F9) : Colors.white.withOpacity(0.1),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: isMe ? Colors.white : Colors.white.withOpacity(0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              Icons.insert_drive_file_rounded,
              color: isMe ? Theme.of(context).colorScheme.primary : Colors.white,
              size: 24,
            ),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  msg.text.isNotEmpty ? msg.text : "Document.docx",
                  style: TextStyle(
                    color: isMe ? const Color(0xFF1E293B) : Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    fontFamily: 'Gilroy',
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  "269.18 KB", // Mock size as in image
                  style: TextStyle(
                    color: isMe ? Colors.grey[600] : Colors.white70,
                    fontSize: 11,
                    fontFamily: 'Gilroy',
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
           // Download Button
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: isMe ? Theme.of(context).colorScheme.primary.withOpacity(0.1) : Colors.white.withOpacity(0.2),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.download_rounded,
              color: isMe ? Theme.of(context).colorScheme.primary : Colors.white,
              size: 20,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVoicePlayer(String? mediaUrl, bool isMe) {
    if (mediaUrl == null) return const Icon(Icons.error_outline, color: Colors.red);
    
    // Construct full URL
    final isPlaying = _currentlyPlayingUrl == mediaUrl;

    return FutureBuilder<String>(
      future: _apiService.getBaseUrl(),
      builder: (context, snapshot) {
        String baseUrl = snapshot.data ?? '';
        if (baseUrl.endsWith('/')) {
          baseUrl = baseUrl.substring(0, baseUrl.length - 1);
        }
        String cleanMediaUrl = mediaUrl;
        if (!cleanMediaUrl.startsWith('/')) {
          cleanMediaUrl = '/$cleanMediaUrl';
        }
        final fullUrl = '$baseUrl$cleanMediaUrl';

        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: Icon(
                isPlaying ? Icons.pause_circle_filled : Icons.play_circle_fill,
                color: isMe ? const Color(0xFF4ADE80) : Colors.white,
                size: 32,
              ),
              onPressed: () async {
                if (isPlaying) {
                  await _audioPlayer.pause();
                  setState(() => _currentlyPlayingUrl = null);
                } else {
                  await _audioPlayer.play(UrlSource(fullUrl));
                  setState(() => _currentlyPlayingUrl = mediaUrl);
                  
                  StreamSubscription<void>? sub;
                  sub = _audioPlayer.onPlayerComplete.listen((_) {
                    if (mounted) setState(() => _currentlyPlayingUrl = null);
                    sub?.cancel();
                  });
                }
              },
            ),
            Expanded(
              child: Container(
                height: 2,
                decoration: BoxDecoration(
                  color: isMe ? Colors.grey[300] : Colors.white24,
                  borderRadius: BorderRadius.circular(1),
                ),
                child: Stack(
                  children: [
                     // Simple mock waveform visualization
                     Row(
                       mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                       children: List.generate(12, (i) => Container(
                         width: 2,
                         height: (i % 3 + 2) * 2.0,
                         color: isMe ? const Color(0xFF1E293B) : Colors.white,
                       )),
                     ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 10),
            Icon(Icons.mic, size: 16, color: isMe ? Colors.grey[500] : Colors.white70),
          ],
        );
      }
    );
  }

  Future<void> _pickImageOrVideo() async {
    final picker = ImagePicker();
    
    // Show modal bottom sheet to choose between Camera (Photo), Camera (Video), Gallery (Photo), Gallery (Video)
    // For simplicity, we can do nice options.
    
    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt, color: Colors.blue),
              title: const Text('Take Photo', style: TextStyle(fontFamily: 'Gilroy')),
              onTap: () {
                Navigator.pop(context);
                _processMediaPick(picker.pickImage(source: ImageSource.camera), isVideo: false);
              },
            ),
             ListTile(
              leading: const Icon(Icons.videocam, color: Colors.red),
              title: const Text('Record Video', style: TextStyle(fontFamily: 'Gilroy')),
              onTap: () {
                Navigator.pop(context);
                _processMediaPick(picker.pickVideo(source: ImageSource.camera), isVideo: true);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library, color: Colors.green),
              title: const Text('Photo Gallery', style: TextStyle(fontFamily: 'Gilroy')),
              onTap: () {
                Navigator.pop(context);
                _processMediaPick(picker.pickImage(source: ImageSource.gallery), isVideo: false);
              },
            ),
             ListTile(
              leading: const Icon(Icons.video_library, color: Colors.purple),
              title: const Text('Video Gallery', style: TextStyle(fontFamily: 'Gilroy')),
              onTap: () {
                Navigator.pop(context);
                _processMediaPick(picker.pickVideo(source: ImageSource.gallery), isVideo: true);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _processMediaPick(Future<XFile?> pickFuture, {required bool isVideo}) async {
    try {
      final file = await pickFuture;
      if (file != null) {
        if (mounted) {
           ScaffoldMessenger.of(context).showSnackBar(
             const SnackBar(content: Text('Uploading media...'), duration: Duration(seconds: 1)),
           );
        }
        
        final mediaUrl = await _apiService.uploadChatMedia(file, isVideo: isVideo);
        
        if (mediaUrl != null && mounted) {
           await _apiService.sendMessage(
            widget.currentUser.username,
            widget.recipient.username,
            '', 
            type: isVideo ? 'video' : 'image', // 'image' or 'video'
            mediaUrl: mediaUrl,
          );
          _playSentSound();
          _fetchMessages(silent: true);
        } else if (mounted) {
           ScaffoldMessenger.of(context).showSnackBar(
             const SnackBar(content: Text('Failed to upload media')),
           );
        }
      }
    } catch (e) {
      print('Error picking media: $e');
    }
  }

  Widget _buildInputArea() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
      child: SafeArea(
        child: Row(
          children: [
            // Floating Pill
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(35),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.1),
                      blurRadius: 10,
                      offset: const Offset(0, 5),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                     // Voice/Mic Icon
                    GestureDetector(
                      onTapDown: (_) => _startRecording(),
                      onTapUp: (_) => _stopAndSendRecording(),
                      onTapCancel: () => _cancelRecording(),
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        child: Icon(
                          _isRecording ? Icons.mic : Icons.mic_none_outlined,
                          color: _isRecording ? Colors.redAccent : const Color(0xFF94A3B8),
                          size: 24,
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: TextField(
                        controller: _messageController,
                        style: const TextStyle(
                          fontFamily: 'Gilroy',
                          fontSize: 15,
                          color: Color(0xFF1E293B),
                        ),
                        decoration: const InputDecoration(
                          hintText: 'Ok. Let me check',
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          errorBorder: InputBorder.none,
                          disabledBorder: InputBorder.none,
                          hintStyle: TextStyle(color: Color(0xFF94A3B8)),
                          contentPadding: EdgeInsets.symmetric(vertical: 12),
                        ),
                        onChanged: (_) => setState(() {}),
                        onSubmitted: (_) => _sendMessage(),
                      ),
                    ),
                    const SizedBox(width: 4),
                    // Attachment Icon
                    _buildInputIcon(Icons.attachment_rounded, _pickImageOrVideo),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 12),
            // Send Button
            GestureDetector(
              onTap: _sendMessage,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                height: 50,
                width: 50,
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.1),
                      blurRadius: 10,
                      offset: const Offset(0, 5),
                    ),
                  ],
                ),
                child: Center(
                  child: Icon(
                    Icons.send_rounded,
                    color: _messageController.text.isNotEmpty 
                        ? Theme.of(context).colorScheme.primary 
                        : const Color(0xFF94A3B8), 
                    size: 24
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInputIcon(IconData icon, VoidCallback onTap) {
    return IconButton(
      icon: Icon(icon, color: const Color(0xFF94A3B8), size: 22),
      onPressed: onTap,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(),
    );
  }
}

class ChatBackgroundPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFFE2E8F0).withOpacity(0.2)
      ..strokeWidth = 1.0;

    const spacing = 40.0;
    for (double i = -size.height; i < size.width; i += spacing) {
      canvas.drawLine(
        Offset(i, 0),
        Offset(i + size.height, size.height),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
