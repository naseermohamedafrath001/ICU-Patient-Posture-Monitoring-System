import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../models/chat_user.dart';
import '../models/user.dart';
import 'chat_detail_screen.dart';
import '../widgets/fade_in_entry.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _apiService = ApiService();
  final _authService = AuthService();
  final _searchController = TextEditingController();
  
  List<ChatUser> _users = [];
  List<ChatUser> _filteredUsers = [];
  bool _isLoading = true;
  User? _currentUser;
  String? _baseUrl;
  String _selectedTab = 'All';
  Timer? _pollingTimer;

  @override
  void initState() {
    super.initState();
    _loadData();
    _searchController.addListener(_onSearchChanged);
    _pollingTimer = Timer.periodic(const Duration(seconds: 10), (_) => _loadData(silent: true));
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    _filterUsers();
  }

  Future<void> _loadData({bool silent = false}) async {
    if (_currentUser == null && !silent) {
       setState(() => _isLoading = true);
    }
    
    final user = await _authService.getCurrentUser();
    final baseUrl = await _apiService.getBaseUrl();
    
    if (user != null) {
      final chatUsers = await _apiService.getChatUsers(user.username);
      if (mounted) {
        setState(() {
          _currentUser = user;
          _users = chatUsers;
          _baseUrl = baseUrl;
          _isLoading = false;
          _filterUsers();
        });
      }
    }
  }

  void _filterUsers() {
    final query = _searchController.text.toLowerCase();
    setState(() {
      _filteredUsers = _users.where((user) {
        final matchesSearch = user.name.toLowerCase().contains(query) || 
                             user.role.toLowerCase().contains(query);
        
        bool matchesTab = true;
        if (_selectedTab == 'Active') {
          matchesTab = user.isOnline;
        } else if (_selectedTab == 'Unread') {
          matchesTab = user.unreadCount > 0;
        }
        
        return matchesSearch && matchesTab;
      }).toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            _buildTabs(),
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _filteredUsers.isEmpty
                      ? _buildEmptyState()
                      : ListView.builder(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          itemCount: _filteredUsers.length,
                          itemBuilder: (context, index) {
                            return FadeInEntry(
                              delay: Duration(milliseconds: 100 * index),
                              child: _buildChatTile(_filteredUsers[index]),
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 7),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Messages',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'Gilroy',
                  color: Color(0xFF1E293B),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.refresh, color: Color(0xFF64748B)),
                onPressed: _loadData,
              ),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(15),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.04),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: TextField(
              controller: _searchController,
              decoration: const InputDecoration(
                isDense: true,
                contentPadding: EdgeInsets.symmetric(vertical: 8),
                icon: Icon(Icons.search, color: Color(0xFF94A3B8)),
                hintText: 'Search contacts...',
                hintStyle: TextStyle(color: Color(0xFF94A3B8), fontFamily: 'Gilroy'),
                border: InputBorder.none,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabs() {
    final tabs = ['All', 'Active', 'Unread'];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      child: Row(
        children: tabs.map((tab) {
          final isSelected = _selectedTab == tab;
          return GestureDetector(
            onTap: () {
              setState(() {
                _selectedTab = tab;
                _filterUsers();
              });
            },
            child: Container(
              margin: const EdgeInsets.only(right: 12),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              decoration: BoxDecoration(
                color: isSelected ? Theme.of(context).colorScheme.primary : Colors.white,
                borderRadius: BorderRadius.circular(25),
                boxShadow: isSelected ? [
                  BoxShadow(
                    color: Theme.of(context).colorScheme.primary.withOpacity(0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 4),
                  )
                ] : null,
              ),
              child: Text(
                tab,
                style: TextStyle(
                  color: isSelected ? Colors.white : const Color(0xFF64748B),
                  fontWeight: FontWeight.bold,
                  fontFamily: 'Gilroy',
                  fontSize: 13,
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildChatTile(ChatUser user) {
    final photoUrl = user.photoUrl != null && _baseUrl != null
        ? '$_baseUrl${user.photoUrl}'
        : null;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          if (_currentUser == null) return;
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => ChatDetailScreen(
                currentUser: _currentUser!,
                recipient: user,
              ),
            ),
          ).then((_) => _loadData());
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          child: Row(
            children: [
              Stack(
                children: [
                  CircleAvatar(
                    radius: 30,
                    backgroundColor: Theme.of(context).colorScheme.primary.withOpacity(0.1),
                    backgroundImage: photoUrl != null ? NetworkImage(photoUrl) : null,
                    child: photoUrl == null
                        ? Icon(Icons.person, color: Theme.of(context).colorScheme.primary, size: 30)
                        : null,
                  ),
                  if (user.isOnline)
                    Positioned(
                      right: 2,
                      bottom: 2,
                      child: Container(
                        width: 14,
                        height: 14,
                        decoration: BoxDecoration(
                          color: Colors.green,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Text(
                              user.name,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                fontFamily: 'Gilroy',
                                color: Color(0xFF1E293B),
                              ),
                            ),
                            if (user.unreadCount > 0) ...[
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.all(6),
                                decoration: const BoxDecoration(
                                  color: Color(0xFF4ADE80),
                                  shape: BoxShape.circle,
                                ),
                                child: Text(
                                  '${user.unreadCount}',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 8,
                                    fontWeight: FontWeight.bold,
                                    fontFamily: 'Gilroy',
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        if (user.lastTimestamp != null)
                          Text(
                            _formatTimestamp(DateTime.parse(user.lastTimestamp!)),
                            style: const TextStyle(
                              fontSize: 11,
                              color: Color(0xFF94A3B8),
                              fontFamily: 'Gilroy',
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      user.lastMessage ?? user.role.toUpperCase(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        color: user.lastMessage != null ? const Color(0xFF64748B) : Theme.of(context).colorScheme.primary.withOpacity(0.7),
                        fontFamily: 'Gilroy',
                        fontWeight: user.lastMessage != null ? FontWeight.normal : FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatTimestamp(DateTime timestamp) {
    final now = DateTime.now();
    if (timestamp.day == now.day && timestamp.month == now.month && timestamp.year == now.year) {
      return DateFormat('HH:mm').format(timestamp);
    }
    return DateFormat('dd/MM').format(timestamp);
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.chat_bubble_outline, size: 60, color: Colors.grey[300]),
          const SizedBox(height: 16),
          Text(
            'No messages yet',
            style: TextStyle(
              fontSize: 18,
              color: Colors.grey[500],
              fontFamily: 'Gilroy',
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Start a conversation with your team.',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[400],
              fontFamily: 'Gilroy',
            ),
          ),
        ],
      ),
    );
  }
}
