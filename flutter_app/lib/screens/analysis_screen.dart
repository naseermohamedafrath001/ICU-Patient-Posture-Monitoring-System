import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_player/video_player.dart';
import 'package:chewie/chewie.dart';
import 'package:audioplayers/audioplayers.dart';
import '../models/patient.dart';
import '../models/analysis_result.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../widgets/patient_modal.dart';
import '../widgets/alert_popup.dart';
import '../widgets/result_card.dart';
import '../models/user.dart';
import '../widgets/horizontal_calendar.dart';
import '../models/doctor.dart';
import '../models/history_record.dart';
import 'package:fl_chart/fl_chart.dart';
import '../widgets/fade_in_entry.dart';

class AnalysisScreen extends StatefulWidget {
  const AnalysisScreen({super.key});

  @override
  State<AnalysisScreen> createState() => _AnalysisScreenState();
}

class _AnalysisScreenState extends State<AnalysisScreen> {
  XFile? _selectedFile;
  bool _isVideo = false;
  bool _isRtsp = false;
  String? _rtspUrl;
  Patient? _currentPatient;
  AnalysisResult? _analysisResult;
  bool _isLoading = false;
  DateTime _selectedDate = DateTime.now();
  List<Doctor> _doctors = [];
  String? _baseUrl;
  bool _isAnalysisComplete = false;
  bool _showCompletionPopup = false;
  
  // Search State
  bool _isSearching = false;
  String _searchFilter = 'All'; // All, Patient, Nurse, Doctor
  final TextEditingController _searchController = TextEditingController();
  List<User> _nurses = [];
  List<Patient> _patients = [];
  List<dynamic> _searchResults = [];
  bool _isSearchingData = false;
  List<HistoryRecord> _history = [];
  Map<String, double> _positionStats = {};
  double _avgResponseTime = 0;
  int _totalAnalyses = 0;
  final PageController _analyticsPageController = PageController(viewportFraction: 0.9);
  int _currentAnalyticsPage = 0;
  
  VideoPlayerController? _videoPlayerController;
  ChewieController? _chewieController;
  final AudioPlayer _audioPlayer = AudioPlayer();
  Timer? _dutyPollingTimer;
  bool _showDutyNotification = false;
  String _currentDutyMessage = '';
  final Set<String> _shownDutyBroadcastIds = {};

  final _apiService = ApiService();
  final _authService = AuthService();
  User? _currentUser;

  @override
  void initState() {
    super.initState();
    _loadCurrentUser();
    _loadAllData(); // Load doctors, nurses, and patients
    _startDutyPolling();
  }

  @override
  void dispose() {
    _dutyPollingTimer?.cancel();
    _videoPlayerController?.dispose();
    _chewieController?.dispose();
    _audioPlayer.dispose();
    _searchController.dispose();
    _analyticsPageController.dispose();
    super.dispose();
  }

  void _startDutyPolling() {
    _dutyPollingTimer = Timer.periodic(const Duration(seconds: 3), (timer) async {
      final broadcasts = await _apiService.getDutyBroadcasts();
      if (broadcasts.isNotEmpty && mounted) {
        for (final b in broadcasts) {
          final id = b['id'] as String;
          if (!_shownDutyBroadcastIds.contains(id)) {
            _shownDutyBroadcastIds.add(id);
            _triggerDutyNotification(b['message'] as String);
            // Only show the most recent one if multiple arrive at same time
            break; 
          }
        }
      }
    });
  }

  void _triggerDutyNotification(String message) {
    if (!mounted) return;
    setState(() {
      _currentDutyMessage = message;
      _showDutyNotification = true;
    });
    
    Timer(const Duration(seconds: 3), () {
      if (mounted) {
        setState(() {
          _showDutyNotification = false;
        });
      }
    });
  }

  Future<void> _broadcastMyDuty() async {
    // Play sound immediately on click
    _playBubbleSound();
    
    if (_currentUser != null) {
      await _apiService.broadcastDutyStatus(_currentUser!.name);
      
      if (mounted) {
         _triggerDutyNotification('Duty status broadcasted');
      }
    }
  }

  Future<void> _playBubbleSound() async {
    try {
      await _audioPlayer.stop(); // Stop any previous sound
      await _audioPlayer.setVolume(1.0);
      await _audioPlayer.play(AssetSource('sound/bubble.mp3'));
    } catch (e) {
      print('Error playing bubble sound: $e');
    }
  }

  Future<void> _loadAllData() async {
    setState(() => _isSearchingData = true);
    try {
      final futures = await Future.wait([
        _apiService.getDoctors(),
        _apiService.getNurses(),
        _apiService.getPatients(),
        _apiService.getBaseUrl(),
        _apiService.getHistory(),
      ]);

      if (mounted) {
        setState(() {
          _doctors = futures[0] as List<Doctor>;
          _nurses = futures[1] as List<User>;
          _patients = futures[2] as List<Patient>;
          _baseUrl = futures[3] as String;
          _history = futures[4] as List<HistoryRecord>;
          _calculateAnalytics();
          _isSearchingData = false;
        });
      }
    } catch (e) {
      print('Error loading search data: $e');
      if (mounted) {
        setState(() => _isSearchingData = false);
      }
    }
  }

  void _triggerCompletionPopup() {
    setState(() => _showCompletionPopup = true);
    Timer(const Duration(seconds: 3), () {
      if (mounted) {
        setState(() => _showCompletionPopup = false);
      }
    });
  }

  Future<void> _loadDoctors() async {
    final doctors = await _apiService.getDoctors();
    final baseUrl = await _apiService.getBaseUrl();
    if (mounted) {
      setState(() {
        _doctors = doctors;
        _baseUrl = baseUrl;
      });
    }
  }

  void _toggleSearch() {
    setState(() {
      _isSearching = !_isSearching;
      if (!_isSearching) {
        _searchController.clear();
        _searchResults.clear();
      }
    });
  }

  void _performSearch(String query) {
    if (query.isEmpty) {
      setState(() => _searchResults = []);
      return;
    }

    final lowerQuery = query.toLowerCase();
    List<dynamic> results = [];

    // Filter Patients
    if (_searchFilter == 'All' || _searchFilter == 'Patient') {
      results.addAll(_patients.where((p) =>
          p.name.toLowerCase().contains(lowerQuery) ||
          p.id.toLowerCase().contains(lowerQuery)));
    }

    // Filter Nurses
    if (_searchFilter == 'All' || _searchFilter == 'Nurse') {
      results.addAll(_nurses.where((n) =>
          n.name.toLowerCase().contains(lowerQuery) ||
          n.username.toLowerCase().contains(lowerQuery)));
    }

    // Filter Doctors
    if (_searchFilter == 'All' || _searchFilter == 'Doctor') {
      results.addAll(_doctors.where((d) =>
          d.name.toLowerCase().contains(lowerQuery) ||
          d.specialty.toLowerCase().contains(lowerQuery)));
    }

    setState(() {
      _searchResults = results;
    });
  }

  void _showFilterOptions() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => Container(
        padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Search Categories',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                fontFamily: 'Gilroy',
                color: Color(0xFF1E293B),
              ),
            ),
            const SizedBox(height: 16),
            _buildFilterOption('All', Icons.all_inclusive),
            _buildFilterOption('Patient', Icons.person),
            _buildFilterOption('Nurse', Icons.badge),
            _buildFilterOption('Doctor', Icons.medical_services),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterOption(String label, IconData icon) {
    final isSelected = _searchFilter == label;
    return ListTile(
      leading: Icon(icon, color: isSelected ? Theme.of(context).colorScheme.primary : Colors.grey),
      title: Text(
        label,
        style: TextStyle(
          fontFamily: 'Gilroy',
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          color: isSelected ? Theme.of(context).colorScheme.primary : const Color(0xFF334155),
        ),
      ),
      trailing: isSelected ? Icon(Icons.check_circle, color: Theme.of(context).colorScheme.primary) : null,
      onTap: () {
        setState(() {
          _searchFilter = label;
          _performSearch(_searchController.text);
        });
        Navigator.pop(context);
      },
    );
  }

  void _showQuickView(dynamic item) {
    String name = '';
    String subTitle = '';
    String? photoUrl;
    IconData icon = Icons.person;
    Map<String, String> details = {};

    if (item is Patient) {
      name = item.name;
      subTitle = 'Patient | ID: ${item.id}';
      icon = Icons.person;
      details = {
        'Room': item.room ?? 'N/A',
        'Age': '${item.age} Yrs',
        'Condition': item.condition ?? 'N/A',
      };
    } else if (item is User) {
      name = item.name;
      subTitle = 'Nurse | ${item.role}';
      photoUrl = item.photoUrl;
      icon = Icons.badge;
      details = {
        'Username': item.username,
        'Phone': item.phone ?? 'Not provided',
        'Nurse ID': item.nurseId ?? 'N/A',
      };
    } else if (item is Doctor) {
      name = item.name;
      subTitle = 'Doctor | ${item.specialty}';
      photoUrl = item.photoUrl != null && _baseUrl != null ? '$_baseUrl${item.photoUrl}' : null;
      icon = Icons.medical_services;
      details = {
        'Duty Time': item.dutyTime,
        'Contact': item.contact ?? 'Not provided',
        'Position': item.position,
      };
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.7,
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
        ),
        child: Column(
          children: [
            const SizedBox(height: 12),
            Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 24),
            CircleAvatar(radius: 40, backgroundColor: Theme.of(context).colorScheme.primary.withOpacity(0.1), backgroundImage: photoUrl != null ? NetworkImage(photoUrl) : null, child: photoUrl == null ? Icon(icon, color: Theme.of(context).colorScheme.primary, size: 32) : null),
            const SizedBox(height: 16),
            Text(name, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, fontFamily: 'Gilroy')),
            Text(subTitle, style: TextStyle(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.bold, fontFamily: 'Gilroy')),
            const SizedBox(height: 32),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                children: [
                  ...details.entries.map((e) => FadeInEntry(
                        child: Padding(
                          padding: const EdgeInsets.only(bottom: 20),
                          child: Row(
                            children: [
                              Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: const Color(0xFFF1F5F9), borderRadius: BorderRadius.circular(12)), child: Icon(_getDetailIcon(e.key), size: 20, color: const Color(0xFF64748B))),
                              const SizedBox(width: 16),
                              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(e.key, style: const TextStyle(fontSize: 12, color: Colors.grey, fontFamily: 'Gilroy')), Text(e.value, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF1E293B), fontFamily: 'Gilroy'))]),
                            ],
                          ),
                        ),
                      )),
                  const SizedBox(height: 24),
                  FadeInEntry(
                    delay: const Duration(milliseconds: 100),
                    child: Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: () {},
                            icon: const Icon(Icons.call, size: 20),
                            label: const Text('Call'),
                            style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 16), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: () {},
                            icon: const Icon(Icons.message, size: 20),
                            label: const Text('Message'),
                            style: ElevatedButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.primary, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 16), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
                          ),
                        ),
                      ],
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

  IconData _getDetailIcon(String key) {
    switch (key.toLowerCase()) {
      case 'phone': case 'contact': return Icons.phone;
      case 'room': return Icons.door_front_door;
      case 'age': return Icons.cake;
      case 'condition': return Icons.description;
      case 'duty time': return Icons.access_time;
      case 'nurse id': return Icons.badge;
      case 'username': return Icons.account_circle;
      case 'position': return Icons.work;
      default: return Icons.info;
    }
  }

  int _touchedPieIndex = -1;

  void _calculateAnalytics() {
    if (_history.isEmpty) return;

    // Position Stats
    Map<String, int> counts = {};
    List<double> responseTimes = [];

    for (var record in _history) {
      final pos = record.prediction ?? record.position;
      if (pos != null) {
        counts[pos] = (counts[pos] ?? 0) + 1;
      }
      
      // Response time calculation (if duration exists and is parseable)
      if (record.duration != null) {
        final durationVal = double.tryParse(record.duration!.split(' ').first);
        if (durationVal != null) responseTimes.add(durationVal);
      }
    }

    setState(() {
      _totalAnalyses = _history.length;
      _positionStats = counts.map((k, v) => MapEntry(k, v.toDouble()));
      if (responseTimes.isNotEmpty) {
        _avgResponseTime = responseTimes.reduce((a, b) => a + b) / responseTimes.length;
      }
    });
  }

  Widget _buildAnalyticsDashboard() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'System Insights',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Color(0xFF1E293B),
                fontFamily: 'Gilroy',
              ),
            ),
            GestureDetector(
              onTap: () {
                _playBubbleSound();
                _loadAllData();
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  'Live',
                  style: TextStyle(
                    fontSize: 10, 
                    fontWeight: FontWeight.bold, 
                    color: Theme.of(context).colorScheme.primary,
                    fontFamily: 'Gilroy',
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        
        // KPI Cards Row
        Row(
          children: [
            _buildKPICard('Patients', _patients.length.toString(), Icons.people_alt),
            const SizedBox(width: 12),
            _buildKPICard('Analyses', _totalAnalyses.toString(), Icons.analytics),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            _buildKPICard('Avg. Response', '${_avgResponseTime.toStringAsFixed(1)}s', Icons.timer),
            const SizedBox(width: 12),
            _buildKPICard('Stability', '94%', Icons.verified_user),
          ],
        ),
        const SizedBox(height: 16),
        // Horizontal Swipable Infographics (PageView)
        SizedBox(
          height: 220,
          child: PageView(
            controller: _analyticsPageController,
            onPageChanged: (index) => setState(() => _currentAnalyticsPage = index),
            physics: const BouncingScrollPhysics(),
            children: [
              _buildPositionChartCard(),
              _buildStaffReadinessCard(),
              _buildMovementSummaryCard(),
              _buildAlertTrendCard(),
            ],
          ),
        ),
        const SizedBox(height: 12),
        // Page Indicators (Dots)
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(4, (index) {
            return AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              margin: const EdgeInsets.symmetric(horizontal: 4),
              height: 8,
              width: _currentAnalyticsPage == index ? 24 : 8,
              decoration: BoxDecoration(
                color: _currentAnalyticsPage == index 
                    ? Theme.of(context).colorScheme.primary 
                    : Theme.of(context).colorScheme.primary.withOpacity(0.2),
                borderRadius: BorderRadius.circular(4),
              ),
            );
          }),
        ),
      ],
    );
  }

  Widget _buildPositionChartCard() {
     final primary = Theme.of(context).colorScheme.primary;
     return Container(
          margin: const EdgeInsets.only(right: 12),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 10, offset: const Offset(0, 4)),
            ],
            border: Border.all(color: Colors.grey.withOpacity(0.05)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Position Distribution',
                    style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF64748B), fontFamily: 'Gilroy'),
                  ),
                  Icon(Icons.pie_chart_rounded, size: 16, color: primary.withOpacity(0.5)),
                ],
              ),
              const SizedBox(height: 16),
              Expanded(
                child: Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: SizedBox(
                        height: 120,
                        child: _positionStats.isEmpty 
                          ? const Center(child: Text('Empty', style: TextStyle(color: Colors.grey, fontSize: 10)))
                          : PieChart(
                              PieChartData(
                                pieTouchData: PieTouchData(
                                  touchCallback: (FlTouchEvent event, pieTouchResponse) {
                                    setState(() {
                                      if (!event.isInterestedForInteractions ||
                                          pieTouchResponse == null ||
                                          pieTouchResponse.touchedSection == null) {
                                        _touchedPieIndex = -1;
                                        return;
                                      }
                                      _touchedPieIndex = pieTouchResponse.touchedSection!.touchedSectionIndex;
                                    });
                                  },
                                ),
                                sectionsSpace: 2,
                                centerSpaceRadius: 30,
                                sections: _positionStats.entries.map((e) {
                                  // Monochromatic Palette
                                  final shades = [
                                    primary,
                                    primary.withOpacity(0.7),
                                    primary.withOpacity(0.5),
                                    primary.withOpacity(0.3),
                                    const Color(0xFF1E293B), // Dark slate for contrast fallback
                                  ];
                                  final keyList = _positionStats.keys.toList();
                                  final index = keyList.indexOf(e.key);
                                  final colorIndex = index % shades.length;
                                  final isTouched = index == _touchedPieIndex;
                                  return PieChartSectionData(
                                    color: shades[colorIndex],
                                    value: e.value,
                                    title: '${((e.value / _totalAnalyses) * 100).toStringAsFixed(0)}%',
                                    radius: isTouched ? 30 : 25,
                                    titleStyle: TextStyle(fontSize: isTouched ? 12 : 9, fontWeight: FontWeight.bold, color: Colors.white, fontFamily: 'Gilroy'),
                                  );
                                }).toList(),
                              ),
                            ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: _positionStats.keys.take(4).map((k) {
                           final shades = [
                                primary,
                                primary.withOpacity(0.7),
                                primary.withOpacity(0.5),
                                primary.withOpacity(0.3),
                                const Color(0xFF1E293B),
                              ];
                           final index = _positionStats.keys.toList().indexOf(k) % shades.length;
                           return Padding(
                             padding: const EdgeInsets.only(bottom: 6),
                             child: Row(
                               children: [
                                 Container(width: 8, height: 8, decoration: BoxDecoration(color: shades[index], borderRadius: BorderRadius.circular(2))),
                                 const SizedBox(width: 8),
                                 Expanded(child: Text(k, style: const TextStyle(fontSize: 10, color: Color(0xFF64748B), fontFamily: 'Gilroy'), overflow: TextOverflow.ellipsis)),
                               ],
                             ),
                           );
                        }).toList(),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
  }

  Widget _buildStaffReadinessCard() {
    final primary = Theme.of(context).colorScheme.primary;
    return Container(
      margin: const EdgeInsets.only(right: 12),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 10, offset: const Offset(0, 4)),
        ],
        border: Border.all(color: Colors.grey.withOpacity(0.05)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Staff Readiness Index',
            style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF64748B), fontFamily: 'Gilroy'),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 120,
                    child: PieChart(
                      PieChartData(
                        startDegreeOffset: 270,
                        sectionsSpace: 0,
                        centerSpaceRadius: 40,
                        sections: [
                          // Primary color for valid part
                          PieChartSectionData(color: primary, value: 85, showTitle: false, radius: 12),
                          // Lighter primary for empty part
                          PieChartSectionData(color: primary.withOpacity(0.1), value: 15, showTitle: false, radius: 12),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('85%', style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: primary, fontFamily: 'Gilroy')),
                    const Text('Operational', style: TextStyle(fontSize: 12, color: Colors.grey, fontFamily: 'Gilroy')),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMovementSummaryCard() {
    final primary = Theme.of(context).colorScheme.primary;
    return Container(
      margin: const EdgeInsets.only(right: 12),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 10, offset: const Offset(0, 4)),
        ],
        border: Border.all(color: Colors.grey.withOpacity(0.05)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Movement Summary',
            style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF64748B), fontFamily: 'Gilroy'),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: SizedBox(
              height: 120,
              child: BarChart(
                BarChartData(
                  gridData: FlGridData(show: false),
                  titlesData: FlTitlesData(show: false),
                  borderData: FlBorderData(show: false),
                  barGroups: [
                    // Monochromatic Bars with varied opacity
                    BarChartGroupData(x: 0, barRods: [BarChartRodData(toY: 8, color: primary.withOpacity(0.4), width: 12, borderRadius: BorderRadius.circular(4))]),
                    BarChartGroupData(x: 1, barRods: [BarChartRodData(toY: 10, color: primary.withOpacity(0.6), width: 12, borderRadius: BorderRadius.circular(4))]),
                    BarChartGroupData(x: 2, barRods: [BarChartRodData(toY: 5, color: primary.withOpacity(0.3), width: 12, borderRadius: BorderRadius.circular(4))]),
                    BarChartGroupData(x: 3, barRods: [BarChartRodData(toY: 12, color: primary, width: 12, borderRadius: BorderRadius.circular(4))]),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAlertTrendCard() {
    final primary = Theme.of(context).colorScheme.primary;
    return Container(
      margin: const EdgeInsets.only(right: 12),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 10, offset: const Offset(0, 4)),
        ],
        border: Border.all(color: Colors.grey.withOpacity(0.05)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Alert Trend',
            style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF64748B), fontFamily: 'Gilroy'),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: SizedBox(
              height: 120,
              child: LineChart(
                LineChartData(
                  gridData: FlGridData(show: false),
                  titlesData: FlTitlesData(show: false),
                  borderData: FlBorderData(show: false),
                  lineBarsData: [
                    LineChartBarData(
                      spots: [
                        const FlSpot(0, 3),
                        const FlSpot(1, 1.5),
                        const FlSpot(2, 4),
                        const FlSpot(3, 2.5),
                        const FlSpot(4, 5),
                        const FlSpot(5, 3.5),
                      ],
                      isCurved: true,
                      color: primary,
                      barWidth: 3,
                      isStrokeCapRound: true,
                      dotData: FlDotData(show: false),
                      belowBarData: BarAreaData(show: true, color: primary.withOpacity(0.05)),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildKPICard(String label, String value, IconData icon) {
    // Use Primary Color for all cards for consistency
    final color = Theme.of(context).colorScheme.primary;
    
    return Expanded(
      child: LiveInteractionWrapper(
        onTap: () {},
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: color.withOpacity(0.03),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: color.withOpacity(0.05)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: color, size: 18),
              ),
              const SizedBox(height: 12),
              Text(value, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, fontFamily: 'Gilroy', color: Color(0xFF1E293B))),
              Text(label, style: const TextStyle(fontSize: 12, color: Color(0xFF64748B), fontFamily: 'Gilroy')),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _loadCurrentUser() async {
    final user = await _authService.getCurrentUser();
    setState(() {
      _currentUser = user;
    });
  }

  String _getProfileImage(String? username) {
    if (username == null || username.isEmpty) return 'assets/nurse_profile/nurse_u.png';
    
    final lowerUser = username.toLowerCase().trim();
    // Try explicit mapping for common usernames if direct match fails
    if (lowerUser.contains('afra') || lowerUser == 'nurse1') return 'assets/nurse_profile/nurse_afra.png';
    if (lowerUser.contains('sarah') || lowerUser == 'nurse3') return 'assets/nurse_profile/nurse_sarah.png';
    if (lowerUser.contains('anshaf') || lowerUser == 'nurse5') return 'assets/nurse_profile/nurse_anshaf.png';
    if (lowerUser.contains('asiyan') || lowerUser == 'nurse4') return 'assets/nurse_profile/nurse_asiyan.png';
    
    // Direct match as per user's "same name" request
    // Map 'nurse2' to 'nurse_u.png' explicitly if it doesn't exist, or use a default
    if (lowerUser == 'nurse2') return 'assets/nurse_profile/nurse_u.png';

    // Direct match as per user's "same name" request
    // IMPORTANT: If this file doesn't exist, it will crash. 
    // Since we can't check file existence synchronously easily in asset bundle without context,
    // we should rely on known users or fallback to 'nurse_u.png' if unknown.
    // For now, let's default safe known users and fallback others.
    return 'assets/nurse_profile/nurse_u.png';
  }

  String _getGreeting() {
    final hour = DateTime.now().hour;
    if (hour >= 5 && hour < 12) {
      return 'Good Morning';
    } else if (hour >= 12 && hour < 17) {
      return 'Good Afternoon';
    } else if (hour >= 17 && hour < 21) {
      return 'Good Evening';
    } else {
      return 'Good Night';
    }
  }

  Future<void> _pickFile(ImageSource source, {bool isVideo = false}) async {
    final picker = ImagePicker();
    final XFile? file = isVideo
        ? await picker.pickVideo(source: source)
        : await picker.pickImage(source: source);

    if (file != null) {
      setState(() {
        _selectedFile = file;
        _isVideo = isVideo;
        _analysisResult = null;
      });

      if (_isVideo) {
        await _initializeVideoPlayer();
      }

      if (_currentPatient == null) {
        _showPatientModal();
      }
    }
  }

  Future<void> _initializeVideoPlayer() async {
    _videoPlayerController?.dispose();
    _chewieController?.dispose();

    if (kIsWeb) {
      _videoPlayerController = VideoPlayerController.networkUrl(Uri.parse(_selectedFile!.path));
    } else {
      _videoPlayerController = VideoPlayerController.file(File(_selectedFile!.path));
    }
    
    await _videoPlayerController!.initialize();

    _chewieController = ChewieController(
      videoPlayerController: _videoPlayerController!,
      autoPlay: false,
      looping: true,
      aspectRatio: _videoPlayerController!.value.aspectRatio,
    );

    setState(() {
      _isAnalysisComplete = false;
    });
  }

  void _resetAnalysis() {
    _videoPlayerController?.pause();
    setState(() {
      _selectedFile = null;
      _isVideo = false;
      _isRtsp = false;
      _rtspUrl = null;
      _currentPatient = null;
      _analysisResult = null;
      _isAnalysisComplete = false;
      _isLoading = false;
    });
  }

  void _showPatientModal() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => PatientModal(
        onSave: (patient) {
          setState(() => _currentPatient = patient);
          Navigator.of(context).pop();
        },
      ),
    );
  }

  Future<void> _analyze() async {
    if (_selectedFile == null && !_isRtsp) return;
    if (_currentPatient == null) {
      _showPatientModal();
      return;
    }

    setState(() => _isLoading = true);

    try {
      if (_isVideo) {
        await _analyzeVideoStream();
      } else {
        // Standard image analysis
        final result = await _apiService.predict(_selectedFile!, false);
        setState(() {
          _analysisResult = result;
          _isLoading = false;
        });
        _saveToHistory(result);
        setState(() => _isAnalysisComplete = true);
        _triggerCompletionPopup();
      }
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Analysis failed: $e')),
        );
      }
    }
  }

  Future<void> _analyzeVideoStream() async {
    if (!_isRtsp && (_videoPlayerController == null || !_videoPlayerController!.value.isInitialized)) {
      await _initializeVideoPlayer();
    }
    _chewieController?.play();
    
    setState(() => _isLoading = true);

    List<FramePrediction> allFramePredictions = [];
    
    try {
      final Stream<String> stream;
      if (_isRtsp) {
        stream = await _apiService.streamRtspAnalysis(
          _rtspUrl!, 
          _currentPatient!.id,
          _currentPatient!.name
        );
      } else {
        stream = await _apiService.streamVideoAnalysis(
          _selectedFile!, 
          _currentPatient!.id,
          _currentPatient!.name
        );
      }

      // Listen to the stream
      await for (final line in stream) {
        if (!mounted) break;
        
        try {
          final data = jsonDecode(line);
          final type = data['type'];
          
          if (type == 'metadata') {
             // Handle metadata if needed
          } else if (type == 'frame') {
             // Update live results
             final pred = FramePrediction.fromJson(data);
             allFramePredictions.add(pred);
             
             // UPDATE UI LIVE
             if (allFramePredictions.length % 5 == 0 || allFramePredictions.length == 1) {
                  final liveResult = AnalysisResult(
                    prediction: pred.prediction,
                    confidence: pred.confidence,
                    probabilities: {}, 
                    framePredictions: List.from(allFramePredictions),
                    videoMetadata: VideoMetadata(
                      duration: (_videoPlayerController?.value.duration.inSeconds.toDouble() ?? 0),
                      totalFrames: allFramePredictions.length,
                      fps: 30,
                    ),
                  );
                  setState(() {
                    _analysisResult = liveResult;
                  });
             }
          } else if (type == 'alert') {
             // CRITICAL: Immediate Alert Trigger
             _chewieController?.pause();
             
             if (mounted) {
               await _triggerAlert(
                 data['position'], 
                 (data['duration'] as num).toDouble().toStringAsFixed(1),
                 data['alert_id'] ?? 'unknown_id'
               );
             }
          } else if (type == 'error') {
             throw Exception(data['message']); // Will be caught by outer try/catch
          }
        } catch (e) {
             print("Error parsing stream line: $e");
        }
      }

    } catch (e) {
        print("Stream error: $e");
        if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Streaming failed: $e')),
            );
        }
    } finally {
        if (mounted) {
            setState(() => _isLoading = false);
            
            // STOP VIDEO playback when analysis is finished
            _chewieController?.pause();
            _videoPlayerController?.seekTo(Duration.zero);
            
            // Build final result object
            if (allFramePredictions.isNotEmpty) {
                 final finalResult = AnalysisResult(
                  prediction: allFramePredictions.last.prediction,
                  confidence: 0.9, 
                  probabilities: {}, 
                  framePredictions: allFramePredictions,
                  videoMetadata: VideoMetadata(
                    duration: (_videoPlayerController?.value.duration.inSeconds.toDouble() ?? 0),
                    totalFrames: allFramePredictions.length,
                    fps: 30,
                  ),
                );
                setState(() {
                  _analysisResult = finalResult;
                  _isAnalysisComplete = true;
                });
                _saveToHistory(finalResult);
                _triggerCompletionPopup();
            }
        }
    }
  }

  void _saveToHistory(AnalysisResult result, {List<Map<String, dynamic>>? intervalResults, int? labelChanges, int? totalIntervals}) async {
    final user = await _authService.getCurrentUser();
    
    String movementSummary = '';
    if (intervalResults != null) {
      movementSummary = (labelChanges != null && labelChanges > 0) 
          ? 'Movement detected in $labelChanges out of $totalIntervals intervals'
          : 'No movement detected throughout video';
    }

    final historyData = {
      'filename': (_selectedFile?.name ?? 'unknown'),
      'file_type': _isVideo ? 'video' : 'image',
      'id': DateTime.now().millisecondsSinceEpoch.toString(),
      'patientId': _currentPatient!.id,
      'patientName': _currentPatient!.name,
      'prediction': result.prediction,
      'confidence': result.confidence,
      'probabilities': result.probabilities,
      'timestamp': DateTime.now().toIso8601String(),
      'analyzedBy': user?.name,
      'analysisType': 'standard',
      'movementSummary': movementSummary,
      'totalIntervals': totalIntervals,
      'intervalsWithMovement': labelChanges,
      'analysis_result': intervalResults != null ? {'allIntervals': intervalResults} : null,
    };

    final success = await _apiService.saveHistory(historyData);
    if (!success && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to save history to backend')),
      );
    }
  }

  void _checkAlerts(AnalysisResult result) {
    if (result.framePredictions != null && result.framePredictions!.isNotEmpty) {
      // Group consecutive frames with same prediction
      String currentPosition = '';
      int consecutiveCount = 0;
      double startTime = 0;

      for (var frame in result.framePredictions!) {
        if (frame.prediction == currentPosition) {
          consecutiveCount++;
        } else {
          // Check previous segment
          if (consecutiveCount > 0) {
            double duration = frame.timestamp - startTime;
            if (duration >= 5.0) {
              _triggerAlert(currentPosition, duration.toStringAsFixed(1), 'legacy_alert');
              return; // Trigger only one alert per analysis for now
            }
          }
          // Reset
          currentPosition = frame.prediction;
          consecutiveCount = 1;
          startTime = frame.timestamp;
        }
      }
      
      // Check last segment
      if (consecutiveCount > 0) {
        double duration = result.framePredictions!.last.timestamp - startTime;
        if (duration >= 5.0) {
          _triggerAlert(currentPosition, duration.toStringAsFixed(1), 'legacy_alert');
        }
      }
    }
  }

  Future<void> _triggerAlert(String position, String duration, String alertId) async {
    // 1. Prevent showing the same alert twice (shared with HomeScreen polling)
    if (ApiService.shownAlertIds.contains(alertId)) return;
    _apiService.markAlertAsShown(alertId);

    _playAlertSound();
    
    bool locallyAcknowledged = false;
    Timer? remoteCheckTimer;

    // 2. Show Dialog
    if (mounted) {
      // Start polling for remote acknowledgement
      remoteCheckTimer = Timer.periodic(const Duration(seconds: 2), (timer) async {
        final status = await _apiService.getAlertStatus(alertId);
        if (status == 'acknowledged' && !locallyAcknowledged && mounted) {
          timer.cancel();
          Navigator.of(context).pop(); // Close dialog remotely
        }
      });

      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertPopup(
          patientName: _currentPatient!.name,
          position: position,
          duration: '$duration seconds',
          onAcknowledge: () async {
            locallyAcknowledged = true;
            remoteCheckTimer?.cancel();
            _stopAlertSound();
            Navigator.of(context).pop();
            // 3. Acknowledge on server
            await _acknowledgeAlert(alertId);
          },
        ),
      );
      
      remoteCheckTimer?.cancel();
      _stopAlertSound();

      // 4. RESUME VIDEO after alert is handled
      if (_chewieController != null && _chewieController!.videoPlayerController.value.isInitialized) {
          _chewieController!.play();
      }
    }
  }

  void _playAlertSound() async {
    // Play the local alert sound asset
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

  Future<String?> _createPendingAlert(String position, String duration) async {
    final user = await _authService.getCurrentUser();
    final alertId = 'alert_${DateTime.now().millisecondsSinceEpoch}';
    
    final alertData = {
      'id': alertId,
      'patientId': _currentPatient!.id,
      'patientName': _currentPatient!.name,
      'position': position,
      'duration': duration,
      'type': 'No Movement Detected',
      'alertType': 'No Movement Detected',
      'timestamp': DateTime.now().toIso8601String(),
      'acknowledgedBy': null,
      'status': 'pending', // Initially pending
      'isAlert': true,
    };
    
    final success = await _apiService.saveAlert(alertData); 
    if (!success && mounted) {
      print('Failed to create pending alert');
    }
    return success ? alertId : null;
  }

  Future<void> _acknowledgeAlert(String alertId) async {
    final user = await _authService.getCurrentUser();
    final success = await _apiService.acknowledgeAlert(alertId, user?.name ?? 'Unknown');
    
    if (success) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Alert acknowledged')),
        );
      }
    } else {
      print('Failed to acknowledge alert');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Stack(
        children: [
          // Background Gradient
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(0xFFE0E7FF), // Light Lavender/Blue
                  Colors.white,
                ],
                stops: [0.0, 0.4],
              ),
            ),
          ),
          
          // Main Content
          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 20), // Added top spacing
                  // Redesigned Header
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    if (!_isSearching)
                      CircleAvatar(
                        radius: 28,
                        backgroundColor: Colors.white,
                        backgroundImage: AssetImage(_getProfileImage(_currentUser?.username)),
                      )
                    else
                      IconButton(
                        icon: const Icon(Icons.arrow_back, color: Color(0xFF64748B)),
                        onPressed: _toggleSearch,
                      ),
                    Expanded(
                      child: _isSearching
                          ? Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 12),
                              child: TextField(
                                controller: _searchController,
                                autofocus: true,
                                decoration: InputDecoration(
                                  hintText: 'Search $_searchFilter...',
                                  border: InputBorder.none,
                                  hintStyle: const TextStyle(color: Color(0xFF94A3B8), fontFamily: 'Gilroy'),
                                ),
                                style: const TextStyle(color: Color(0xFF1E293B), fontWeight: FontWeight.bold, fontFamily: 'Gilroy'),
                                onChanged: _performSearch,
                              ),
                            )
                          : const SizedBox.shrink(),
                    ),
                    Row(
                      children: [
                        if (_isSearching)
                          GestureDetector(
                            onTap: _showFilterOptions,
                            child: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: Theme.of(context).colorScheme.primary, // Blue rounded
                                shape: BoxShape.circle,
                                border: Border.all(color: Colors.white, width: 2), // White border/bg effect
                                boxShadow: [
                                  BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 8, offset: const Offset(0, 4)),
                                ],
                              ),
                              child: const Icon(Icons.tune, color: Colors.white, size: 20),
                            ),
                          )
                        else
                          _buildHeaderAction(Icons.notifications_none, _broadcastMyDuty),
                        const SizedBox(width: 12),
                        _buildHeaderAction(_isSearching ? Icons.close : Icons.search, _toggleSearch),
                      ],
                    ),
                  ],
                ),
                if (!_isSearching) ...[
                  const SizedBox(height: 10),
                  Text(
                    _getGreeting(),
                    style: const TextStyle(
                      fontSize: 24,
                      color: Color(0xFF475569),
                      fontFamily: 'Gilroy',
                      height: 1.5,
                    ),
                  ),
                  Text(
                    _currentUser?.name ?? 'Nurse',
                    style: const TextStyle(
                      fontSize: 30,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF1E293B),
                      fontFamily: 'Gilroy',
                      height: 1.1,
                    ),
                  ),
                ],
            const SizedBox(height: 40),

            // New Promotional Card (Connect for Better Care)
            FadeInEntry(
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 32),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary, // Soft Blue Theme
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: Theme.of(context).colorScheme.primary.withOpacity(0.3),
                      blurRadius: 15,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Stack(
                  children: [
                    Column(
                      children: [
                        const Text(
                          'Connect for Better Care',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            fontFamily: 'Gilroy',
                          ),
                        ),
                        const SizedBox(height: 20),
                        Center(
                          child: ElevatedButton(
                            onPressed: _showPickerOptions,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF1E293B), // Dark Button
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(30),
                              ),
                            ),
                            child: const Text(
                              'Stream',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontFamily: 'Gilroy',
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),

            if (_selectedFile != null || _isRtsp) ...[
              const SizedBox(height: 8),
              _buildPreview(),
            ],
            
            const SizedBox(height: 16),

            // Analyze Button
            FadeInEntry(
              delay: const Duration(milliseconds: 100),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: ((_selectedFile != null || _isRtsp) && !_isLoading) ? _analyze : null,
                  icon: const Icon(Icons.analytics_rounded),
                  label: _isLoading
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                        )
                      : const Text('Start Analysis'),
                ),
              ),
            ),

            const SizedBox(height: 50),

            // Results (Moved Above Dashboard)
            if (_analysisResult != null) ...[
              const FadeInEntry(
                 child: Text(
                  'Analysis Results',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1E293B),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              FadeInEntry(child: ResultCard(result: _analysisResult!)),
              const SizedBox(height: 24),
              FadeInEntry(child: _buildAgentSuggestion()),
            ],

            if (_isAnalysisComplete) ...[
              const SizedBox(height: 16),
              FadeInEntry(child: _buildPostAnalysisActions()),
              const SizedBox(height: 32), // Add spacing before dashboard
            ],
            
            FadeInEntry(
              delay: const Duration(milliseconds: 200),
              child: _buildAnalyticsDashboard(),
            ),
            const SizedBox(height: 16),

            const SizedBox(height: 16),
            FadeInEntry(
              delay: const Duration(milliseconds: 300),
              child: _buildDoctorDutySection(),
            ),

            const SizedBox(height: 24),

            // Horizontal Calendar Widget
            FadeInEntry(
              delay: const Duration(milliseconds: 400),
              child: HorizontalCalendar(
                initialDate: _selectedDate,
                onDateSelected: (date) {
                  setState(() {
                    _selectedDate = date;
                  });
                },
              ),
            ),


            ],
          ),
        ),
      ),

    // Search Results Overlay
        if (_isSearching && _searchResults.isNotEmpty)
          Positioned(
            top: 100,
            left: 20,
            right: 20,
            bottom: 100,
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(color: Colors.black.withOpacity(0.15), blurRadius: 30, offset: const Offset(0, 10)),
                ],
              ),
              child: ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: _searchResults.length,
                separatorBuilder: (context, index) => const Divider(),
                itemBuilder: (context, index) {
                  final item = _searchResults[index];
                  String name = '';
                  String sub = '';
                  IconData icon = Icons.person;
                  String? photo;

                  if (item is Patient) {
                    name = item.name;
                    sub = 'Patient | Room: ${item.room ?? 'N/A'}';
                  } else if (item is User) {
                    name = item.name;
                    sub = 'Nurse | ${item.role}';
                    photo = item.photoUrl;
                  } else if (item is Doctor) {
                    name = item.name;
                    sub = 'Doctor | ${item.specialty}';
                    photo = item.photoUrl != null && _baseUrl != null ? '$_baseUrl/uploads/${item.photoUrl!.split('/').last}' : null; 
                  }

                  return ListTile(
                    leading: CircleAvatar(
                      backgroundColor: Theme.of(context).colorScheme.primary.withOpacity(0.1),
                      backgroundImage: photo != null ? NetworkImage(photo) : null,
                      child: photo == null ? Icon(icon, color: Theme.of(context).colorScheme.primary) : null,
                    ),
                    title: Text(name, style: const TextStyle(fontWeight: FontWeight.bold, fontFamily: 'Gilroy')),
                    subtitle: Text(sub, style: const TextStyle(color: Colors.grey, fontSize: 12, fontFamily: 'Gilroy')),
                    trailing: const Icon(Icons.chevron_right, color: Colors.grey),
                    onTap: () => _showQuickView(item),
                  );
                },
              ),
            ),
          ),

        // Duty Notification Overlay
        if (_showDutyNotification)
          Positioned(
            top: 50,
            left: 20,
            right: 20,
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0.0, end: 1.0),
              duration: const Duration(milliseconds: 500),
              builder: (context, value, child) {
                return Transform.translate(
                  offset: Offset(0, (1 - value) * -20),
                  child: Opacity(
                    opacity: value,
                    child: child,
                  ),
                );
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.9),
                  borderRadius: BorderRadius.circular(30),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.1),
                      blurRadius: 20,
                      offset: const Offset(0, 10),
                    ),
                  ],
                  border: Border.all(color: Colors.white.withOpacity(0.5)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.handshake_rounded,
                        color: Theme.of(context).colorScheme.primary,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _currentDutyMessage,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF1E293B),
                          fontFamily: 'Gilroy',
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          
          _buildCompletionPopup(),
      ],
    ),
  );
}

  Widget _buildCompletionPopup() {
    if (!_showCompletionPopup) return const SizedBox.shrink();

    return Positioned.fill(
      child: Container(
        color: Colors.black.withOpacity(0.3),
        child: Center(
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0.0, end: 1.0),
            duration: const Duration(milliseconds: 500),
            curve: Curves.elasticOut,
            builder: (context, value, child) {
              return Transform.scale(
                scale: value,
                child: Opacity(
                  opacity: value,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 30),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: [
                        BoxShadow(
                          color: Theme.of(context).colorScheme.primary.withOpacity(0.3),
                          blurRadius: 20,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.green.withOpacity(0.1),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.check_rounded, color: Colors.green, size: 48),
                        ),
                        const SizedBox(height: 20),
                        const Text(
                          'analysed finish',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF1E293B),
                            fontFamily: 'Gilroy',
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildPreview() {
    if (_isRtsp) {
      return Container(
        height: 200,
        width: double.infinity,
        decoration: BoxDecoration(
          color: Colors.black87,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.red.withOpacity(0.5), width: 2),
        ),
        child: Stack(
          children: [
            Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.sensors, color: Colors.white70, size: 48),
                  const SizedBox(height: 12),
                  const Text(
                    'LIVE MONITORING ACTIVE',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, letterSpacing: 1.2),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _rtspUrl ?? '',
                    style: const TextStyle(color: Colors.white54, fontSize: 10, fontFamily: 'monospace'),
                  ),
                ],
              ),
            ),
            Positioned(
              top: 16,
              right: 16,
              child: Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 8),
                  const Text('LIVE', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 12)),
                ],
              ),
            ),
          ],
        ),
      );
    }
    
    if (_isVideo) {
      return _chewieController != null && _chewieController!.videoPlayerController.value.isInitialized
          ? AspectRatio(
              aspectRatio: _videoPlayerController!.value.aspectRatio,
              child: ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: Chewie(controller: _chewieController!),
              ),
            )
          : const Center(
              child: Padding(
                padding: EdgeInsets.all(20.0),
                child: CircularProgressIndicator(),
              ),
            );
    } else {
      return ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: kIsWeb 
            ? Image.network(_selectedFile!.path, fit: BoxFit.cover)
            : Image.file(File(_selectedFile!.path), fit: BoxFit.cover),
      );
    }
  }

  Widget _buildAgentSuggestion() {
    final prediction = _analysisResult?.prediction?.toLowerCase() ?? '';
    String title = 'General Assessment';
    String desc = 'Monitor patient position and skin integrity.';
    IconData icon = Icons.medical_services;
    Color color = const Color(0xFF5E8DE4);

    if (prediction.contains('supine')) {
      title = 'Supine Position Care';
      desc = 'Check sacrum, heels, and elbows. Reposition within 2 hours.';
      icon = Icons.bed;
      color = Colors.orange;
    } else if (prediction.contains('left')) {
      title = 'Left Lateral Care';
      desc = 'Monitor left shoulder, hip, and ankle. Use pillow support.';
      icon = Icons.airline_seat_flat;
      color = Colors.orange;
    } else if (prediction.contains('right')) {
      title = 'Right Lateral Care';
      desc = 'Monitor right shoulder, hip, and ankle. Ensure alignment.';
      icon = Icons.airline_seat_flat_angled;
      color = Colors.orange;
    }

    return Card(
      // Card color comes from Theme (white)
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, color: color, size: 32),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          color: Color(0xFF37474F),
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        desc,
                        style: const TextStyle(color: Colors.grey),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _showPickerOptions() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      builder: (context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: Icon(Icons.image, color: Theme.of(context).colorScheme.primary),
            title: const Text('Pick Image from Gallery', style: TextStyle(color: Color(0xFF37474F))),
            onTap: () {
              Navigator.pop(context);
              _pickFile(ImageSource.gallery, isVideo: false);
            },
          ),
          ListTile(
            leading: const Icon(Icons.video_library, color: Color(0xFF1E88E5)),
            title: const Text('Pick Video from Gallery', style: TextStyle(color: Color(0xFF37474F))),
            onTap: () {
              Navigator.pop(context);
              _pickFile(ImageSource.gallery, isVideo: true);
            },
          ),
          ListTile(
            leading: const Icon(Icons.camera_alt, color: Color(0xFF1E88E5)),
            title: const Text('Take Photo', style: TextStyle(color: Color(0xFF37474F))),
            onTap: () {
              Navigator.pop(context);
              _pickFile(ImageSource.camera, isVideo: false);
            },
          ),
          ListTile(
            leading: const Icon(Icons.leak_add, color: Color(0xFF1E88E5)),
            title: const Text('Analyze RTSP Stream', style: TextStyle(color: Color(0xFF37474F))),
            onTap: () {
              Navigator.pop(context);
              _showRtspInputDialog();
            },
          ),
        ],
      ),
    );
  }

  void _showRtspInputDialog() {
    final controller = TextEditingController(text: 'rtsp://');
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Enter RTSP URL', style: TextStyle(fontFamily: 'Gilroy', fontWeight: FontWeight.bold)),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            hintText: 'rtsp://192.168.1.100:554/live',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              if (controller.text.isNotEmpty) {
                setState(() {
                  _rtspUrl = controller.text;
                  _isRtsp = true;
                  _isVideo = true; 
                  _selectedFile = null;
                  _analysisResult = null;
                });
                Navigator.pop(context);
                if (_currentPatient == null) {
                  _showPatientModal();
                }
              }
            },
            child: const Text('Connect'),
          ),
        ],
      ),
    );
  }



  Widget _buildDoctorDutySection() {
    final onDutyDoctors = _doctors.where((d) => d.isOnDuty()).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Doctors on Duty',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Color(0xFF1E293B),
                fontFamily: 'Gilroy',
              ),
            ),
          
          ],
        ),
        const SizedBox(height: 16),
        if (onDutyDoctors.isEmpty)
          Container(
            padding: const EdgeInsets.all(20),
            width: double.infinity,
            decoration: BoxDecoration(
              color: Colors.grey.withOpacity(0.05),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Center(
              child: Text(
                'No doctors currently on duty.',
                style: TextStyle(color: Colors.grey, fontFamily: 'Gilroy'),
              ),
            ),
          )
        else
          SizedBox(
            height: 120,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: onDutyDoctors.length,
              itemBuilder: (context, index) {
                final doctor = onDutyDoctors[index];
                final photoUrl = doctor.photoUrl != null && _baseUrl != null
                    ? '$_baseUrl${doctor.photoUrl}'
                    : null;

                return Container(
                  width: 250,
                  margin: const EdgeInsets.only(right: 16),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.grey.withOpacity(0.1)),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.02),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 30,
                        backgroundColor: Theme.of(context).colorScheme.primary.withOpacity(0.1),
                        backgroundImage: photoUrl != null ? NetworkImage(photoUrl) : null,
                        child: photoUrl == null
                            ? Icon(Icons.person, color: Theme.of(context).colorScheme.primary)
                            : null,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              doctor.name,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                                fontFamily: 'Gilroy',
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(
                              doctor.specialty,
                              style: TextStyle(
                                fontSize: 12,
                                color: Theme.of(context).colorScheme.primary,
                                fontFamily: 'Gilroy',
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                const Icon(Icons.access_time, size: 12, color: Colors.grey),
                                const SizedBox(width: 4),
                                Text(
                                  doctor.dutyTime,
                                  style: const TextStyle(fontSize: 10, color: Colors.grey),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
      ],
    );
  }

  Widget _buildHeaderAction(IconData icon, VoidCallback onTap) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: IconButton(
        icon: Icon(icon, color: const Color(0xFF64748B)),
        onPressed: onTap,
      ),
    );
  }

  Widget _buildPostAnalysisActions() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Theme.of(context).colorScheme.primary.withOpacity(0.2)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 15,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: [
          const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.check_circle, color: Colors.green, size: 28),
              SizedBox(width: 12),
              Text(
                'Analysis Complete',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1E293B),
                  fontFamily: 'Gilroy',
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'What would you like to do next?',
            style: TextStyle(
              fontSize: 14,
              color: Color(0xFF64748B),
              fontFamily: 'Gilroy',
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _analyze,
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Analyze Again'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    side: BorderSide(color: Theme.of(context).colorScheme.primary),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _resetAnalysis,
                  icon: const Icon(Icons.add_to_photos_rounded),
                  label: const Text('New Analysis'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    backgroundColor: Theme.of(context).colorScheme.primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class LiveInteractionWrapper extends StatefulWidget {
  final Widget child;
  final VoidCallback onTap;

  const LiveInteractionWrapper({super.key, required this.child, required this.onTap});

  @override
  State<LiveInteractionWrapper> createState() => _LiveInteractionWrapperState();
}

class _LiveInteractionWrapperState extends State<LiveInteractionWrapper> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _isPressed = true),
      onTapUp: (_) => setState(() => _isPressed = false),
      onTapCancel: () => setState(() => _isPressed = false),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _isPressed ? 0.98 : 1.0, // Subtle 2% scale
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOutCubic,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            boxShadow: _isPressed
                ? []
                : [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.02),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
          ),
          child: widget.child,
        ),
      ),
    );
  }
}
