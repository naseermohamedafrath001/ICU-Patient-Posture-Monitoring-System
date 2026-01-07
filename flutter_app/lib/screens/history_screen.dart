import 'package:flutter/material.dart';
import '../models/history_record.dart';
import '../widgets/fade_in_entry.dart';
import '../services/api_service.dart';
import 'package:intl/intl.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  final _apiService = ApiService();
  List<HistoryRecord> _allRecords = [];
  List<HistoryRecord> _filteredRecords = [];
  bool _isLoading = true;
  String _searchQuery = '';
  String _filterType = 'all'; // all, critical, warning

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    setState(() => _isLoading = true);
    try {
      final records = await _apiService.getHistory();
      setState(() {
        _allRecords = records;
        _applyFilters();
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load history: $e')),
        );
      }
    }
  }

  void _applyFilters() {
    setState(() {
      _filteredRecords = _allRecords.where((record) {
        // Search filter
        final searchLower = _searchQuery.toLowerCase();
        final matchesSearch = (record.patientName?.toLowerCase().contains(searchLower) ?? false) ||
            (record.patientId?.toLowerCase().contains(searchLower) ?? false) ||
            (record.prediction?.toLowerCase().contains(searchLower) ?? false);

        // Type filter
        bool matchesType = true;
        if (_filterType == 'critical') {
          matchesType = record.type == 'critical' || record.isAlert;
        } else if (_filterType == 'warning') {
          matchesType = !record.isAlert && (record.confidence != null && record.confidence! < 0.7);
        }

        return matchesSearch && matchesType;
      }).toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: CustomScrollView(
        slivers: [
          // Professional Header
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.only(left: 24, right: 24, top: 40, bottom: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Alert History',
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF1E293B),
                          fontFamily: 'Gilroy',
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 4)),
                          ],
                        ),
                        child: IconButton(
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          icon: const Icon(Icons.refresh_rounded, color: Color(0xFF64748B)),
                          onPressed: _loadHistory,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  // Search Bar
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 10, offset: const Offset(0, 4)),
                      ],
                    ),
                    child: TextField(
                      style: const TextStyle(color: Color(0xFF1E293B), fontWeight: FontWeight.bold, fontFamily: 'Gilroy'),
                      decoration: const InputDecoration(
                        hintText: 'Search alerts...',
                        hintStyle: TextStyle(color: Color(0xFF94A3B8), fontFamily: 'Gilroy'),
                        prefixIcon: Icon(Icons.search, color: Color(0xFF64748B)),
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.symmetric(vertical: 16),
                      ),
                      onChanged: (value) {
                        _searchQuery = value;
                        _applyFilters();
                      },
                    ),
                  ),
                  const SizedBox(height: 16),
                  // Filters
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        _buildFilterChip('All Alerts', 'all'),
                        const SizedBox(width: 8),
                        _buildFilterChip('Critical', 'critical'),
                        const SizedBox(width: 8),
                        _buildFilterChip('Warnings', 'warning'),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          // History List
          _isLoading
              ? const SliverFillRemaining(child: Center(child: CircularProgressIndicator()))
              : _filteredRecords.isEmpty
                  ? const SliverFillRemaining(
                      child: Center(
                        child: Text(
                          'No history available',
                          style: TextStyle(color: Colors.grey, fontFamily: 'Gilroy'),
                        ),
                      ),
                    )
                  : SliverPadding(
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                      sliver: SliverList(
                        delegate: SliverChildBuilderDelegate(
                          (context, index) {
                            return _buildHistoryCard(_filteredRecords[index]);
                          },
                          childCount: _filteredRecords.length,
                        ),
                      ),
                    ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String label, String value) {
    final isSelected = _filterType == value;
    return GestureDetector(
      onTap: () {
        setState(() {
          _filterType = value;
          _applyFilters();
        });
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF1E88E5) : Colors.white,
          borderRadius: BorderRadius.circular(30),
          boxShadow: [
            if (isSelected)
              BoxShadow(
                color: const Color(0xFF1E88E5).withOpacity(0.3),
                blurRadius: 8,
                offset: const Offset(0, 4),
              ),
            if (!isSelected)
              BoxShadow(
                color: Colors.black.withOpacity(0.02),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
          ],
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.white : const Color(0xFF64748B),
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
            fontFamily: 'Gilroy',
            fontSize: 13,
          ),
        ),
      ),
    );
  }

  Widget _buildHistoryCard(HistoryRecord record) {
    final isAlert = record.isAlert || record.type == 'critical';
    final date = DateTime.tryParse(record.timestamp) ?? DateTime.now();
    final formattedDate = DateFormat('MMM d, h:mm:ss a').format(date);

    return FadeInEntry(
      delay: Duration(milliseconds: 30), // Small fixed delay or pass index if available
      child: Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: LiveInteractionWrapper(
          onTap: () {},
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 15, offset: const Offset(0, 6)),
              ],
              border: Border.all(
                color: isAlert ? Colors.red.withOpacity(0.1) : Colors.transparent,
                width: 1,
              ),
            ),
            child: Column(
              children: [
                // Top status bar
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: isAlert ? Colors.red.withOpacity(0.05) : const Color(0xFFF1F5F9).withOpacity(0.5),
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Icon(
                            isAlert ? Icons.warning_rounded : Icons.info_outline_rounded,
                            size: 14,
                            color: isAlert ? Colors.red : const Color(0xFF64748B),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            isAlert ? 'CRITICAL ALERT' : 'ROUTINE LOG',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: isAlert ? Colors.red : const Color(0xFF64748B),
                              letterSpacing: 0.5,
                              fontFamily: 'Gilroy',
                            ),
                          ),
                        ],
                      ),
                      Text(
                        formattedDate,
                        style: const TextStyle(fontSize: 10, color: Color(0xFF94A3B8), fontFamily: 'Gilroy'),
                      ),
                    ],
                  ),
                ),
                // Main content
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: (isAlert ? Colors.red : const Color(0xFF1E88E5)).withOpacity(0.1),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              Icons.person_rounded,
                              size: 20,
                              color: isAlert ? Colors.red : const Color(0xFF1E88E5),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  record.patientName ?? 'Unknown Patient',
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF1E293B),
                                    fontFamily: 'Gilroy',
                                  ),
                                ),
                                Text(
                                  'Patient ID: ${record.patientId ?? 'N/A'}',
                                  style: const TextStyle(fontSize: 12, color: Color(0xFF94A3B8), fontFamily: 'Gilroy'),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          _buildStat('Position', record.prediction ?? record.position ?? 'Unknown', Icons.accessibility_new),
                          if (record.confidence != null)
                            _buildStat(
                              'Confidence',
                              '${(record.confidence! * 100).toStringAsFixed(1)}%',
                              Icons.bolt,
                              valColor: (record.confidence! < 0.7) ? Colors.orange : Colors.green,
                            ),
                          if (record.duration != null)
                            _buildStat('Duration', record.duration!, Icons.timer_outlined),
                        ],
                      ),
                      if (record.acknowledgedBy != null) ...[
                        const SizedBox(height: 16),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.green.withOpacity(0.05),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.verified_user_rounded, size: 16, color: Colors.green),
                              const SizedBox(width: 8),
                              Text(
                                'Handled by ${record.acknowledgedBy}',
                                style: const TextStyle(
                                  color: Colors.green,
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  fontFamily: 'Gilroy',
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStat(String label, String value, IconData icon, {Color? valColor}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 12, color: const Color(0xFF94A3B8)),
            const SizedBox(width: 4),
            Text(label, style: const TextStyle(fontSize: 11, color: Color(0xFF94A3B8), fontFamily: 'Gilroy')),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.bold,
            color: valColor ?? const Color(0xFF334155),
            fontFamily: 'Gilroy',
          ),
        ),
      ],
    );
  }
}

// Reuse the Living UI Wrapper
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
        scale: _isPressed ? 0.98 : 1.0,
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOutCubic,
        child: widget.child,
      ),
    );
  }
}


