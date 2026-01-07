import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../models/user.dart';
import '../screens/settings_screen.dart';

class SideDrawer extends StatefulWidget {
  final Function(int) onNavigate;

  const SideDrawer({super.key, required this.onNavigate});

  @override
  State<SideDrawer> createState() => _SideDrawerState();
}

class _SideDrawerState extends State<SideDrawer> {
  final _authService = AuthService();
  User? _currentUser;

  @override
  void initState() {
    super.initState();
    _loadUser();
  }

  Future<void> _loadUser() async {
    final user = await _authService.getCurrentUser();
    if (mounted) setState(() => _currentUser = user);
  }

  @override
  Widget build(BuildContext context) {
    return Drawer(
      child: Column(
        children: [
          _buildHeader(),
          Expanded(
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                _buildDrawerItem(
                  icon: Icons.menu_book_outlined,
                  title: 'Guidance Library',
                  onTap: () => _handleNavigation(4),
                ),
                _buildDrawerItem(
                  icon: Icons.medical_services_outlined,
                  title: 'Nursing Staff',
                  onTap: () => _handleNavigation(5),
                ),
                _buildDrawerItem(
                  icon: Icons.person_outline,
                  title: 'My Profile',
                  onTap: () => _handleNavigation(6),
                ),
                _buildDrawerItem(
                  icon: Icons.people_outline,
                  title: 'Patient Management',
                  onTap: () => _handleNavigation(7),
                ),
              ],
            ),
          ),
          _buildLogoutButton(),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.only(top: 60, left: 24, bottom: 24, right: 24),
      width: double.infinity,
      color: Theme.of(context).colorScheme.primary.withOpacity(0.05),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 35,
            backgroundColor: Theme.of(context).colorScheme.primary,
            child: Text(
              _currentUser?.name.substring(0, 1).toUpperCase() ?? 'N',
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            _currentUser?.name ?? 'Nurse',
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Color(0xFF1E293B),
              fontFamily: 'Gilroy',
            ),
          ),
          Text(
            _currentUser?.role.toUpperCase() ?? 'STAFF',
            style: TextStyle(
              fontSize: 12,
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.2,
              fontFamily: 'Gilroy',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDrawerItem({
    required IconData icon,
    required String title,
    required VoidCallback onTap,
  }) {
    return ListTile(
      leading: Icon(icon, color: const Color(0xFF64748B)),
      title: Text(
        title,
        style: const TextStyle(
          fontSize: 15,
          color: Color(0xFF1E293B),
          fontWeight: FontWeight.w500,
          fontFamily: 'Gilroy',
        ),
      ),
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 24),
    );
  }

  Widget _buildLogoutButton() {
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: ListTile(
        leading: const Icon(Icons.logout_rounded, color: Colors.redAccent),
        title: const Text(
          'Logout',
          style: TextStyle(
            color: Colors.redAccent,
            fontWeight: FontWeight.bold,
            fontFamily: 'Gilroy',
          ),
        ),
        onTap: () async {
          await _authService.logout();
          if (mounted) {
            Navigator.of(context).pushNamedAndRemoveUntil('/splash', (route) => false);
          }
        },
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: Colors.redAccent, width: 1),
        ),
      ),
    );
  }

  void _handleNavigation(int index) {
    Navigator.pop(context);
    widget.onNavigate(index);
  }
}
