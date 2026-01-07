import 'package:flutter/material.dart';
import '../models/patient.dart';
import '../services/api_service.dart';

class PatientModal extends StatefulWidget {
  final Function(Patient) onSave;

  const PatientModal({super.key, required this.onSave});

  @override
  State<PatientModal> createState() => _PatientModalState();
}

class _PatientModalState extends State<PatientModal> {
  final _formKey = GlobalKey<FormState>();
  final _idController = TextEditingController();
  final _nameController = TextEditingController();
  final _ageController = TextEditingController();
  final _roomController = TextEditingController();
  final _conditionController = TextEditingController();
  
  final _apiService = ApiService();
  
  List<Patient> _existingPatients = [];
  bool _isLoadingExisting = true;
  bool _showNewPatientForm = false;

  @override
  void initState() {
    super.initState();
    _loadExistingPatients();
  }

  Future<void> _loadExistingPatients() async {
    setState(() => _isLoadingExisting = true);
    final patients = await _apiService.getPatients();
    if (mounted) {
      setState(() {
        _existingPatients = patients;
        _isLoadingExisting = false;
        if (patients.isEmpty) {
          _showNewPatientForm = true;
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.white,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 40),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 500),
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  _showNewPatientForm ? 'Add New Patient' : 'Select Patient',
                  style: const TextStyle(
                    color: Color(0xFF1E293B),
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'Gilroy',
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.grey),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (!_showNewPatientForm) ...[
              _buildExistingPatientsList(),
              const SizedBox(height: 16),
              Center(
                child: TextButton.icon(
                  onPressed: () => setState(() => _showNewPatientForm = true),
                  icon: const Icon(Icons.add_circle_outline, color: Color(0xFF5E8DE4)),
                  label: const Text('Add New Patient', 
                    style: TextStyle(color: Color(0xFF5E8DE4), fontWeight: FontWeight.bold)),
                ),
              ),
            ] else ...[
              _buildNewPatientForm(),
              const SizedBox(height: 12),
              if (_existingPatients.isNotEmpty)
                Center(
                  child: TextButton.icon(
                    onPressed: () => setState(() => _showNewPatientForm = false),
                    icon: const Icon(Icons.list_alt_rounded, color: Color(0xFF64748B)),
                    label: const Text('Back to List', 
                      style: TextStyle(color: Color(0xFF64748B), fontWeight: FontWeight.w600)),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildExistingPatientsList() {
    if (_isLoadingExisting) {
      return const Center(child: Padding(
        padding: EdgeInsets.all(30.0),
        child: CircularProgressIndicator(),
      ));
    }

    return Flexible(
      child: ListView.builder(
        shrinkWrap: true,
        itemCount: _existingPatients.length,
        itemBuilder: (context, index) {
          final p = _existingPatients[index];
          return Container(
            margin: const EdgeInsets.only(bottom: 8),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor: const Color(0xFF5E8DE4).withOpacity(0.1),
                child: Text(p.name[0].toUpperCase(), 
                  style: const TextStyle(color: Color(0xFF5E8DE4), fontWeight: FontWeight.bold)),
              ),
              title: Text(p.name, style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF1E293B))),
              subtitle: Text('ID: ${p.id} • Room: ${p.room ?? "N/A"}', 
                style: const TextStyle(fontSize: 12)),
              onTap: () => widget.onSave(p),
            ),
          );
        },
      ),
    );
  }

  Widget _buildNewPatientForm() {
    return Flexible(
      child: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildTextField(_idController, 'Patient ID *', Icons.badge, required: true),
              const SizedBox(height: 12),
              _buildTextField(_nameController, 'Full Name *', Icons.person, required: true),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(child: _buildTextField(_ageController, 'Age *', Icons.calendar_today, isNumber: true, required: true)),
                  const SizedBox(width: 12),
                  Expanded(child: _buildTextField(_roomController, 'Room/Bed', Icons.meeting_room)),
                ],
              ),
              const SizedBox(height: 12),
              _buildTextField(_conditionController, 'Medical Condition', Icons.medical_services, maxLines: 2),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _savePatient,
                  child: const Text('Save & Select Patient'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTextField(
    TextEditingController controller,
    String label,
    IconData icon, {
    bool isNumber = false,
    bool required = false,
    int maxLines = 1,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: isNumber ? TextInputType.number : TextInputType.text,
      maxLines: maxLines,
      style: const TextStyle(color: Color(0xFF1E293B), fontSize: 14),
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, color: const Color(0xFF5E8DE4), size: 18),
        filled: true,
        fillColor: const Color(0xFFF8FAFC),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      ),
      validator: required ? (value) => value!.isEmpty ? 'Required' : null : null,
    );
  }

  void _savePatient() async {
    if (_formKey.currentState!.validate()) {
      final patient = Patient(
        id: _idController.text,
        name: _nameController.text,
        age: _ageController.text,
        room: _roomController.text,
        condition: _conditionController.text,
        timestamp: DateTime.now().toIso8601String(),
      );

      final success = await _apiService.savePatient(patient);
      if (success) {
        widget.onSave(patient);
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Failed to save patient to backend.')),
          );
        }
      }
    }
  }
}
