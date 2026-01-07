import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'analysis_screen.dart';
import 'history_screen.dart';
import 'guidance_screen.dart';
import 'nurse_screen.dart';
import 'settings_screen.dart';
import '../services/auth_service.dart';
import '../services/api_service.dart';
import '../widgets/alert_popup.dart';
import '../models/history_record.dart';
import 'package:audioplayers/audioplayers.dart';
import 'doctor_screen.dart';
import 'chat_screen.dart';
import 'patient_list_screen.dart';
import '../widgets/side_drawer.dart';
import '../widgets/chat_notification.dart';
import '../models/chat_user.dart';
import 'chat_detail_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentIndex = 0;
  final _authService = AuthService();
  final _apiService = ApiService();
  Timer? _alertTimer;
  final AudioPlayer _audioPlayer = AudioPlayer();
  final Set<String> _shownAlertIds = {};
  bool _isShowingAlert = false;
  bool _isNavBarVisible = false;
  Timer? _navBarHideTimer;
  Timer? _messagePollingTimer;
  Map<String, int> _lastUnreadCounts = {};
  OverlayEntry? _currentNotification;
  Timer? _notificationTimeout;

  @override
  void initState() {
    super.initState();
    _startAlertPolling();
    _startMessagePolling();
    // Show Nav Bar on initial load
    WidgetsBinding.instance.addPostFrameCallback((_) => _showNavBar());
  }

  @override
  void dispose() {
    _alertTimer?.cancel();
    _navBarHideTimer?.cancel();
    _messagePollingTimer?.cancel();
    _notificationTimeout?.cancel();
    _hideNotification();
    _audioPlayer.dispose();
    super.dispose();
  }

  void _startAlertPolling() {
    _alertTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
      _checkPendingAlerts();
    });
  }

  void _startMessagePolling() {
    _messagePollingTimer = Timer.periodic(const Duration(seconds: 4), (timer) {
      _checkNewMessages();
    });
  }

  Future<void> _checkNewMessages() async {
    final user = await _authService.getCurrentUser();
    if (user == null) return;

    // Send heartbeat during polling to keep status "online"
    _apiService.sendHeartbeat(user.username);

    final chatUsers = await _apiService.getChatUsers(user.username);
    for (var chatUser in chatUsers) {
      final lastCount = _lastUnreadCounts[chatUser.username] ?? 0;
      if (chatUser.unreadCount > lastCount) {
        // New message detected!
        _showNewMessageNotification(chatUser);
      }
      _lastUnreadCounts[chatUser.username] = chatUser.unreadCount;
    }
  }

  void _showNewMessageNotification(ChatUser user) async {
    if (!mounted) return;

    final baseUrl = await _apiService.getBaseUrl();
    _hideNotification();
    _playNotificationSound();

    _currentNotification = OverlayEntry(
      builder: (context) => Positioned(
        top: 0,
        left: 0,
        right: 0,
        child: ChatNotification(
          senderName: user.name,
          messageSnippet: user.lastMessage ?? 'Sent a message',
          photoUrl: user.photoUrl != null 
              ? '$baseUrl${user.photoUrl}' 
              : null,
          onTap: () {
            _hideNotification();
            _navigateToChat(user);
          },
          onDismiss: () {
            _hideNotification();
          },
        ),
      ),
    );

    Overlay.of(context).insert(_currentNotification!);

    // Auto-hide after 10 seconds if not swiped
    _notificationTimeout = Timer(const Duration(seconds: 10), () {
      _hideNotification();
    });
  }

  void _playNotificationSound() async {
    try {
      await _audioPlayer.setVolume(1.0);
      await _audioPlayer.play(AssetSource('sound/piggyback.mp3'));
    } catch (e) {
      print('Error playing notification sound: $e');
    }
  }

  void _hideNotification() {
    _notificationTimeout?.cancel();
    _currentNotification?.remove();
    _currentNotification = null;
  }

  void _navigateToChat(ChatUser recipient) async {
    final currentUser = await _authService.getCurrentUser();
    if (currentUser != null && mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => ChatDetailScreen(
            currentUser: currentUser,
            recipient: recipient,
          ),
        ),
      );
    }
  }

  Future<void> _checkPendingAlerts() async {
    if (_isShowingAlert) return;

    final pendingAlerts = await _apiService.getPendingAlerts();
    if (pendingAlerts.isNotEmpty) {
      final newAlert = pendingAlerts.firstWhere(
        (a) => !ApiService.shownAlertIds.contains(a.id),
        orElse: () => HistoryRecord(
          id: '',
          timestamp: '',
          prediction: '',
          confidence: 0,
        ),
      );

      if (newAlert.id.isNotEmpty && mounted) {
        _showAlert(newAlert);
      }
    }
  }

  void _playAlertSound() async {
    try {
      await _audioPlayer.setVolume(1.0);
      await _audioPlayer.play(AssetSource('sound/alert.mp3'));
    } catch (e) {
      print('Error playing sound: $e');
    }
  }

  void _stopAlertSound() {
    _audioPlayer.stop();
  }

  Future<void> _showAlert(HistoryRecord alert) async {
    setState(() {
      _isShowingAlert = true;
      _apiService.markAlertAsShown(alert.id);
    });

    _playAlertSound();

    bool locallyAcknowledged = false;
    Timer? remoteCheckTimer;

    if (mounted) {
      // Start polling for remote acknowledgement
      remoteCheckTimer = Timer.periodic(const Duration(seconds: 2), (timer) async {
        final status = await _apiService.getAlertStatus(alert.id);
        if (status == 'acknowledged' && !locallyAcknowledged && mounted) {
          timer.cancel();
          if (Navigator.of(context).canPop()) {
            Navigator.of(context).pop(); // Close dialog remotely
          }
        }
      });

      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertPopup(
          patientName: alert.patientName ?? 'Unknown Patient',
          position: alert.prediction ?? 'Unknown',
          duration: alert.duration ?? 'unknown',
          onAcknowledge: () async {
            locallyAcknowledged = true;
            remoteCheckTimer?.cancel();
            _stopAlertSound();
            final user = await _authService.getCurrentUser();
            await _apiService.acknowledgeAlert(alert.id, user?.name ?? 'Nurse');
            if (mounted) Navigator.of(context).pop();
          },
        ),
      );
      
      remoteCheckTimer?.cancel();
      _stopAlertSound();
    }

    setState(() => _isShowingAlert = false);
  }

  final List<Widget> _screens = [
    const AnalysisScreen(),
    const HistoryScreen(),
    const ChatScreen(),
    const DoctorScreen(), // Index 3: Now in Bottom Bar
    const GuidanceScreen(), // Index 4: In Drawer
    const NurseScreen(), // Index 5: In Drawer
    const SettingsScreen(), // Index 6: Profile in Drawer
    const PatientListScreen(), // Index 7: Patient Management in Drawer
  ];

  void _logout() async {
    await _authService.logout();
    if (mounted) {
      Navigator.of(context).pushNamedAndRemoveUntil('/splash', (route) => false);
    }
  }

  void _showNavBar() {
    if (!_isNavBarVisible) {
      setState(() => _isNavBarVisible = true);
    }
    _navBarHideTimer?.cancel();
    _navBarHideTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) {
        setState(() => _isNavBarVisible = false);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text(_getPageTitle()),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16.0),
            child: CircleAvatar(
              radius: 18,
              backgroundColor: Colors.white,
              child: Padding(
                padding: const EdgeInsets.all(4.0),
                child: Image.asset('assets/icon/app_icon.png'),
              ),
            ),
          ),
        ],
      ),
      drawer: SideDrawer(
        onNavigate: (index) {
          setState(() {
            _currentIndex = index;
            _showNavBar();
          });
        },
      ),
      body: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTapDown: (_) => _showNavBar(),
        child: Stack(
          children: [
            NotificationListener<ScrollNotification>(
              onNotification: (notification) {
                if (notification is ScrollUpdateNotification) {
                  _showNavBar();
                }
                return false;
              },
              child: IndexedStack(
                index: _currentIndex,
                children: _screens,
              ),
            ),
            AnimatedPositioned(
              duration: const Duration(milliseconds: 400),
              curve: Curves.easeInOutCubic,
              left: MediaQuery.of(context).size.width * 0.15,
              right: MediaQuery.of(context).size.width * 0.15,
              bottom: _isNavBarVisible ? 20 : -100,
              child: _buildFloatingBottomBar(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFloatingBottomBar() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(40),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primary.withOpacity(0.7),
            borderRadius: BorderRadius.circular(40),
            border: Border.all(color: Colors.white.withOpacity(0.2)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildNavItem(0, Icons.home_outlined, Icons.home),
              _buildNavItem(1, Icons.calendar_month_outlined, Icons.calendar_month),
              _buildNavItem(2, Icons.chat_bubble_outline_rounded, Icons.chat_bubble_rounded),
              _buildNavItem(3, Icons.hexagon_outlined, Icons.hexagon),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem(int index, IconData icon, IconData activeIcon) {
    bool isSelected = _currentIndex == index;
    return GestureDetector(
      onTap: () => setState(() => _currentIndex = index),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isSelected ? Colors.white : Colors.transparent,
          shape: BoxShape.circle,
          boxShadow: isSelected 
            ? [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 4)]
            : null,
        ),
        child: Icon(
          isSelected ? activeIcon : icon,
          color: isSelected ? Theme.of(context).colorScheme.primary : Colors.white,
          size: 26,
        ),
      ),
    );
  }

  String _getPageTitle() {
    switch (_currentIndex) {
      case 0: return 'Analysis Dashboard';
      case 1: return 'History';
      case 2: return 'Nurse Chat';
      case 3: return 'Doctors on Duty';
      case 4: return 'Guidelines';
      case 5: return 'Nurse Contacts';
      case 6: return 'Profile Settings';
      case 7: return 'Patient Management';
      default: return 'ThermalVision AI';
    }
  }
}

