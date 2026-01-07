import 'package:flutter/material.dart';
import '../models/chat_user.dart';
import '../widgets/fade_in_entry.dart';
import '../services/api_service.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/auth_service.dart';
import 'chat_detail_screen.dart';

class NurseScreen extends StatefulWidget {
  const NurseScreen({super.key});

  @override
  State<NurseScreen> createState() => _NurseScreenState();
}

class _NurseScreenState extends State<NurseScreen> {
  final _apiService = ApiService();
  final _authService = AuthService();
  List<ChatUser> _nurses = [];
  List<ChatUser> _filteredNurses = [];
  bool _isLoading = true;
  String? _baseUrl;
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadData();
    _searchController.addListener(_filterNurses);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _filterNurses() {
    final query = _searchController.text.toLowerCase();
    setState(() {
      _filteredNurses = _nurses.where((n) =>
          n.name.toLowerCase().contains(query) ||
          n.username.toLowerCase().contains(query)).toList();
    });
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final baseUrl = await _apiService.getBaseUrl();
      final currentUser = await _authService.getCurrentUser();
      final nurses = await _apiService.getChatUsers(currentUser?.username ?? '');
      if (mounted) {
        setState(() {
          _baseUrl = baseUrl;
          _nurses = nurses;
          _filteredNurses = nurses;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: Column(
        children: [
          // Header & Search
          Container(
            padding: const EdgeInsets.only(top: 20, left: 24, right: 24, bottom: 24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: const BorderRadius.vertical(bottom: Radius.circular(32)),
              boxShadow: [
                BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 20, offset: const Offset(0, 10)),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Nursing Staff',
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        fontFamily: 'Gilroy',
                        color: Color(0xFF1E293B),
                      ),
                    ),
                    IconButton(
                      onPressed: _loadData,
                      icon: Icon(Icons.refresh, color: Theme.of(context).colorScheme.primary),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Connected and care for better future',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey[500],
                    fontFamily: 'Gilroy',
                  ),
                ),
                const SizedBox(height: 16),
                // Search Bar
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: TextField(
                    controller: _searchController,
                    decoration: const InputDecoration(
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(vertical: 12),
                      border: InputBorder.none,
                      hintText: 'Search staff by name...',
                      icon: Icon(Icons.search, color: Color(0xFF94A3B8)),
                      hintStyle: TextStyle(color: Color(0xFF94A3B8), fontFamily: 'Gilroy'),
                    ),
                    style: const TextStyle(
                      fontFamily: 'Gilroy',
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF1E293B),
                    ),
                  ),
                ),
              ],
            ),
          ),
          
          // List
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _filteredNurses.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.person_off_outlined, size: 60, color: Colors.grey[300]),
                            const SizedBox(height: 16),
                            Text(
                              'No staff found',
                              style: TextStyle(
                                  color: Colors.grey[400],
                                  fontSize: 16,
                                  fontFamily: 'Gilroy'),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.all(24),
                        itemCount: _filteredNurses.length,
                        itemBuilder: (context, index) {
                          final nurse = _filteredNurses[index];
                          return _buildNurseCard(nurse);
                        },
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildNurseCard(ChatUser nurse) {
    // Determine image URL
    String? photoUrl;
    if (nurse.photoUrl != null && _baseUrl != null) {
      if (nurse.photoUrl!.startsWith('http')) {
        photoUrl = nurse.photoUrl;
      } else {
        photoUrl = '$_baseUrl${nurse.photoUrl}';
      }
    }

    return FadeInEntry(
      child: Container(
        margin: const EdgeInsets.only(bottom: 20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Colors.grey.withOpacity(0.05)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 24,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => _showNurseDetails(nurse),
            borderRadius: BorderRadius.circular(24),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // Profile Image
                  Stack(
                    children: [
                      Container(
                        width: 60,
                        height: 60,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                          color: Theme.of(context).colorScheme.primary.withOpacity(0.05),
                          image: photoUrl != null
                              ? DecorationImage(
                                  image: NetworkImage(photoUrl),
                                  fit: BoxFit.cover,
                                )
                              : null,
                        ),
                        child: photoUrl == null
                            ? Icon(Icons.person, size: 28, color: Theme.of(context).colorScheme.primary)
                            : null,
                      ),
                      // Online/Offline Status Indicator
                      Positioned(
                        right: -2,
                        bottom: -2,
                        child: Container(
                          width: 16,
                          height: 16,
                          decoration: BoxDecoration(
                            color: nurse.isOnline ? Colors.green : Colors.grey[400],
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 2.5),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(width: 16),
                  
                  // Info
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          nurse.name,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            fontFamily: 'Gilroy',
                            color: Color(0xFF1E293B),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          nurse.role == 'user' ? 'Registered Nurse' : nurse.role.toUpperCase(),
                          style: TextStyle(
                            fontSize: 13,
                            color: Theme.of(context).colorScheme.primary,
                            fontFamily: 'Gilroy',
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Icon(Icons.badge_outlined, size: 12, color: Colors.grey[400]),
                            const SizedBox(width: 4),
                            Text(
                              nurse.nurseId ?? nurse.username,
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.grey[500],
                                fontFamily: 'Gilroy',
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  
                  // Action Buttons
                  const SizedBox(width: 12),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _buildActionCircle(Icons.chat_bubble_rounded, () => _openChat(nurse)),
                      const SizedBox(width: 8),
                      _buildActionCircle(Icons.call, () => _makePhoneCall(nurse.phone ?? '')),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildActionCircle(IconData icon, VoidCallback onTap) {
    return Container(
      height: 40,
      width: 40,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
        shape: BoxShape.circle,
      ),
      child: IconButton(
        onPressed: onTap,
        padding: EdgeInsets.zero,
        icon: Icon(icon, color: Theme.of(context).colorScheme.primary, size: 20),
      ),
    );
  }

  void _showNurseDetails(ChatUser nurse) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => NurseDetailScreen(nurse: nurse, baseUrl: _baseUrl),
      ),
    );
  }

  void _openChat(ChatUser nurse) async {
    final currentFullUser = await _authService.getCurrentUser();
    if (mounted && currentFullUser != null) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => ChatDetailScreen(
            currentUser: currentFullUser,
            recipient: nurse,
          ),
        ),
      );
    }
  }

  Future<void> _makePhoneCall(String phoneNumber) async {
    if (phoneNumber.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Phone number not available')),
        );
        return;
    }
    final Uri launchUri = Uri(
      scheme: 'tel',
      path: phoneNumber,
    );
    if (await canLaunchUrl(launchUri)) {
      await launchUrl(launchUri);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not launch phone dialer')),
        );
      }
    }
  }
}

class NurseDetailScreen extends StatelessWidget {
  final ChatUser nurse;
  final String? baseUrl;

  const NurseDetailScreen({super.key, required this.nurse, this.baseUrl});

  @override
  Widget build(BuildContext context) {
    String? photoUrl;
    if (nurse.photoUrl != null && baseUrl != null) {
      if (nurse.photoUrl!.startsWith('http')) {
        photoUrl = nurse.photoUrl;
      } else {
        photoUrl = '$baseUrl${nurse.photoUrl}';
      }
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: SingleChildScrollView(
        child: Column(
          children: [
            // Premium Header
            Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  height: 300,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        const Color(0xFFE0F2FE),
                        const Color(0xFFEFF6FF),
                        Theme.of(context).colorScheme.primary.withOpacity(0.1),
                      ],
                    ),
                    borderRadius: const BorderRadius.only(
                      bottomLeft: Radius.circular(40),
                      bottomRight: Radius.circular(40),
                    ),
                  ),
                ),
                Positioned(
                  top: 50,
                  left: 20,
                  child: GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: const CircleAvatar(
                      backgroundColor: Colors.white,
                      child: Icon(Icons.arrow_back, color: Colors.black),
                    ),
                  ),
                ),
                
                // Nurse Image/Avatar
                Positioned(
                  bottom: -20,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: Container(
                      height: 140,
                      width: 140,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white,
                        border: Border.all(color: Colors.white, width: 4),
                        boxShadow: [
                          BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 20, offset: const Offset(0, 10)),
                        ],
                        image: photoUrl != null
                            ? DecorationImage(
                                image: NetworkImage(photoUrl),
                                fit: BoxFit.cover,
                              )
                            : null,
                      ),
                      child: photoUrl == null
                          ? Icon(Icons.person, size: 60, color: Theme.of(context).colorScheme.primary.withOpacity(0.5))
                          : null,
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 40),
            
            Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                children: [
                  Text(
                    nurse.name,
                    style: const TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'Gilroy',
                      color: Color(0xFF1E293B),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    nurse.role == 'user' ? 'Senior Registered Nurse' : nurse.role.toUpperCase(),
                    style: TextStyle(
                      fontSize: 16,
                      color: Theme.of(context).colorScheme.primary,
                      fontFamily: 'Gilroy',
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 32),
                  
                  // Stats / Info Row (Like Doc page)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _buildDetailItem(context, Icons.badge_outlined, 'ID', nurse.nurseId ?? 'N/A'),
                      _buildDetailItem(context, Icons.history, 'Joined', nurse.joinedDate ?? 'Recently'),
                      _buildDetailItem(context, Icons.verified_user_outlined, 'Verified', 'Yes'),
                    ],
                  ),
                  
                  const SizedBox(height: 32),
                  
                  // Contact Info Section
                  _buildSectionTitle('Personal Information'),
                  _buildInfoTile(Icons.phone_android, 'Phone Number', nurse.phone ?? 'Not provided'),
                  _buildInfoTile(Icons.location_on_outlined, 'Address', nurse.address ?? 'Hospital Residence'),
                  _buildInfoTile(Icons.alternate_email, 'Username', '@${nurse.username}'),

                  const SizedBox(height: 32),
                  
                  // Big Message Button
                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: ElevatedButton.icon(
                      onPressed: () {
                         // Navigation logic to chat handled in NurseScreen parent, but could pass it here
                         Navigator.pop(context); // Simple for now
                      },
                      icon: const Icon(Icons.chat_bubble_rounded, color: Colors.white),
                      label: const Text(
                        'Send Message',
                        style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                            fontFamily: 'Gilroy'),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Theme.of(context).colorScheme.primary,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        elevation: 4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 16.0),
        child: Text(
          title,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            fontFamily: 'Gilroy',
            color: Color(0xFF1E293B),
          ),
        ),
      ),
    );
  }

  Widget _buildDetailItem(BuildContext context, IconData icon, String label, String value) {
    return Column(
      children: [
        Icon(icon, color: Theme.of(context).colorScheme.primary.withOpacity(0.6), size: 24),
        const SizedBox(height: 8),
        Text(
          value,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            fontFamily: 'Gilroy',
            color: Color(0xFF1E293B),
          ),
        ),
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            color: Colors.grey,
            fontFamily: 'Gilroy',
          ),
        ),
      ],
    );
  }

  Widget _buildInfoTile(IconData icon, String title, String value) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.withOpacity(0.1)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 20, color: const Color(0xFF64748B)),
          ),
          const SizedBox(width: 16),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 12,
                  color: Colors.grey,
                  fontFamily: 'Gilroy',
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'Gilroy',
                  color: Color(0xFF1E293B),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
