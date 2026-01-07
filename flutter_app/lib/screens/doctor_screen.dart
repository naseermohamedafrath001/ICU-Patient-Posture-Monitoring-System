import 'package:flutter/material.dart';
import '../models/doctor.dart';
import '../widgets/fade_in_entry.dart';
import '../services/api_service.dart';
import 'package:url_launcher/url_launcher.dart';

class DoctorScreen extends StatefulWidget {
  const DoctorScreen({super.key});

  @override
  State<DoctorScreen> createState() => _DoctorScreenState();
}

class _DoctorScreenState extends State<DoctorScreen> {
  final _apiService = ApiService();
  List<Doctor> _doctors = [];
  List<Doctor> _filteredDoctors = [];
  bool _isLoading = true;
  String? _baseUrl;
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadData();
    _searchController.addListener(_filterDoctors);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _filterDoctors() {
    final query = _searchController.text.toLowerCase();
    setState(() {
      _filteredDoctors = _doctors.where((d) =>
          d.name.toLowerCase().contains(query) ||
          d.specialty.toLowerCase().contains(query)).toList();
    });
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final baseUrl = await _apiService.getBaseUrl();
      final doctors = await _apiService.getDoctors();
      if (mounted) {
        setState(() {
          _baseUrl = baseUrl;
          _doctors = doctors;
          _filteredDoctors = doctors;
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
            padding: const EdgeInsets.only(top: 20, left: 24, right: 24, bottom: 16),
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
                const Text(
                  'Medical Team',
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'Gilroy',
                    color: Color(0xFF1E293B),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Find your specialist doctor',
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
                      hintText: 'Search doctor or specialty...',
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
                : _filteredDoctors.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.person_off_outlined, size: 60, color: Colors.grey[300]),
                            const SizedBox(height: 16),
                            Text(
                              'No doctors found',
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
                        itemCount: _filteredDoctors.length,
                        itemBuilder: (context, index) {
                          final doctor = _filteredDoctors[index];
                          return _buildDoctorCard(doctor);
                        },
                      ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        heroTag: null,
        onPressed: _loadData,
        backgroundColor: Theme.of(context).colorScheme.primary,
        elevation: 4,
        child: const Icon(Icons.refresh, color: Colors.white),
      ),
    );
  }

  Widget _buildDoctorCard(Doctor doctor) {
    final photoUrl = doctor.photoUrl != null && _baseUrl != null
        ? '$_baseUrl${doctor.photoUrl}'
        : null;
    final isOnDuty = doctor.isOnDuty();

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
            onTap: () => _showDoctorDetails(doctor),
            borderRadius: BorderRadius.circular(24),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      // Profile Image
                      Stack(
                        children: [
                          Container(
                            width: 60, // Slightly smaller for list view
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
                          Positioned(
                            bottom: 0,
                            right: 0,
                            child: Container(
                              width: 12,
                              height: 12,
                              decoration: BoxDecoration(
                                color: isOnDuty ? Colors.green : Colors.grey,
                                shape: BoxShape.circle,
                                border: Border.all(color: Colors.white, width: 2),
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
                              doctor.name,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                fontFamily: 'Gilroy',
                                color: Color(0xFF1E293B),
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              doctor.specialty,
                              style: TextStyle(
                                fontSize: 13,
                                color: Theme.of(context).colorScheme.primary,
                                fontFamily: 'Gilroy',
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: isOnDuty ? Colors.green.withOpacity(0.1) : Colors.grey.withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    isOnDuty ? 'ON DUTY' : 'OFF DUTY',
                                    style: TextStyle(
                                      fontSize: 9,
                                      fontWeight: FontWeight.bold,
                                      color: isOnDuty ? Colors.green : Colors.grey,
                                      fontFamily: 'Gilroy',
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Icon(Icons.access_time_filled_rounded, size: 12, color: Colors.grey[400]),
                                const SizedBox(width: 4),
                                Text(
                                  doctor.dutyTime,
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
                      
                      // Action Button (Right Aligned)
                      const SizedBox(width: 12),
                      Container(
                        height: 48,
                        width: 48,
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
                          shape: BoxShape.circle,
                        ),
                        child: IconButton(
                          onPressed: () => _makePhoneCall(doctor.contact),
                          icon: Icon(Icons.call, color: Theme.of(context).colorScheme.primary, size: 24),
                          tooltip: 'Call Doctor',
                        ),
                      ),
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

  void _showDoctorDetails(Doctor doctor) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => DoctorDetailScreen(doctor: doctor, baseUrl: _baseUrl),
      ),
    );
  }

  Future<void> _makePhoneCall(String phoneNumber) async {
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

  Widget _buildDetailRow(IconData icon, String label, String value) {
    return Container(); 
  }
}

class DoctorDetailScreen extends StatelessWidget {
  final Doctor doctor;
  final String? baseUrl;

  const DoctorDetailScreen({super.key, required this.doctor, this.baseUrl});

  @override
  Widget build(BuildContext context) {
    final photoUrl = doctor.photoUrl != null && baseUrl != null
        ? '$baseUrl${doctor.photoUrl}'
        : null;

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: SingleChildScrollView(
        child: Column(
          children: [
            // HUGE Gradient Header
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
                    child: CircleAvatar(
                      backgroundColor: Colors.white,
                      child: const Icon(Icons.arrow_back, color: Colors.black),
                    ),
                  ),
                ),
                 Positioned(
                  top: 50,
                  right: 20,
                  child: CircleAvatar(
                    backgroundColor: Colors.white,
                    child: const Icon(Icons.call, color: Colors.black),
                  ),
                ),
                
                // Doctor Image & Info
                Positioned(
                  bottom: 0,
                  right: 20,
                  child: Hero(
                    tag: 'doctor_${doctor.id}',
                    child: Container(
                      height: 280,
                      width: 200, // Approximate width for cutout look
                      decoration: photoUrl != null ? BoxDecoration(
                        image: DecorationImage(
                          image: NetworkImage(photoUrl),
                          fit: BoxFit.cover,
                          alignment: Alignment.topCenter,
                        ),
                      ) : null,
                      child: photoUrl == null 
                          ? Icon(Icons.person, size: 100, color: Colors.grey.withOpacity(0.5)) 
                          : null,
                    ),
                  ),
                ),

                Positioned(
                  top: 100,
                  left: 24,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: const Color(0xFFDBEAFE),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          doctor.specialty,
                          style: const TextStyle(
                            color: Color(0xFF2563EB),
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                            fontFamily: 'Gilroy',
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: 180,
                        child: Text(
                          doctor.name,
                          style: const TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                            height: 1.1,
                            fontFamily: 'Gilroy',
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Icon(Icons.apartment, size: 16, color: Colors.grey[600]),
                          const SizedBox(width: 8),
                          Text(
                            'General Hospital',
                            style: TextStyle(
                              color: Colors.grey[600],
                              fontFamily: 'Gilroy',
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                       Text(
                        'Dr. Contact: ${doctor.contact}',
                        style: TextStyle(
                          color: Colors.grey[400],
                          fontSize: 12,
                          fontFamily: 'Gilroy',
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            const SizedBox(height: 24),
            
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Doctor Information',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'Gilroy',
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _buildInfoCard(context, Icons.work, '10 Years', 'Experience'),
                      _buildInfoCard(context, Icons.translate, 'English', 'Language'),
                      _buildInfoCard(context, Icons.access_time_filled, doctor.dutyTime.split('-')[0].trim(), 'Availability'),
                    ],
                  ),
                  
                  const SizedBox(height: 24),
                   const Text(
                    'Appointment',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'Gilroy',
                    ),
                  ),
                  const SizedBox(height: 16),
                  
                  // Date Scroll (Mock)
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: List.generate(5, (index) {
                        final date = DateTime.now().add(Duration(days: index));
                        final isSelected = index == 1; // Mock selection
                        return Container(
                          margin: const EdgeInsets.only(right: 12),
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          decoration: BoxDecoration(
                            color: isSelected ? Theme.of(context).colorScheme.primary : Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: Colors.grey.shade200),
                            boxShadow: [
                               if (isSelected) BoxShadow(
                                 color: Theme.of(context).colorScheme.primary.withOpacity(0.3),
                                 blurRadius: 8,
                                 offset: const Offset(0, 4),
                               ),
                            ]
                          ),
                          child: Column(
                            children: [
                              Text(
                                '${date.day}',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: isSelected ? Colors.white : Colors.black87,
                                  fontFamily: 'Gilroy',
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                _getWeekday(date.weekday),
                                style: TextStyle(
                                  fontSize: 12,
                                  color: isSelected ? Colors.white70 : Colors.grey,
                                  fontFamily: 'Gilroy',
                                ),
                              ),
                            ],
                          ),
                        );
                      }),
                    ),
                  ),

                  const SizedBox(height: 24),
                  
                  // Time Slots (Mock)
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      _buildTimeSlot(context, '08:00', false),
                      _buildTimeSlot(context, '09:40', false),
                      _buildTimeSlot(context, '10:00', true), // Selected
                      _buildTimeSlot(context, '11:50', false),
                      _buildTimeSlot(context, '12:30', false),
                      _buildTimeSlot(context, '17:40', false),
                    ],
                  ),

                  const SizedBox(height: 32),
                  
                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: ElevatedButton(
                      onPressed: () {},
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Theme.of(context).colorScheme.primary,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        elevation: 4,
                        shadowColor: Theme.of(context).colorScheme.primary.withOpacity(0.4),
                      ),
                      child: const Text(
                        'Contact',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                          fontFamily: 'Gilroy',
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 30),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoCard(BuildContext context, IconData icon, String value, String label) {
    return Container(
      width: (MediaQuery.of(context).size.width - 64) / 3,
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.grey.shade100),
        boxShadow: const [
          BoxShadow(
            color: Colors.black12,
            blurRadius: 10,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Icon(icon, color: Theme.of(context).colorScheme.primary),
          const SizedBox(height: 8),
          Text(
            value,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 14,
              fontFamily: 'Gilroy',
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(
              fontSize: 10,
              color: Colors.grey,
              fontFamily: 'Gilroy',
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildTimeSlot(BuildContext context, String time, bool isSelected) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      decoration: BoxDecoration(
        color: isSelected ? Theme.of(context).colorScheme.primary : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isSelected ? Theme.of(context).colorScheme.primary : Colors.grey.shade300,
        ),
      ),
      child: Text(
        time,
        style: TextStyle(
          color: isSelected ? Colors.white : Colors.grey[600],
          fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
          fontFamily: 'Gilroy',
        ),
      ),
    );
  }

  String _getWeekday(int weekday) {
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return days[weekday - 1];
  }
}
