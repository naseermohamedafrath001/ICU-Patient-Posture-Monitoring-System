import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/patient.dart';

class StorageService {
  static const String _patientsKey = 'thermalvision_patients';

  Future<List<Patient>> getPatients() async {
    final prefs = await SharedPreferences.getInstance();
    final String? patientsJson = prefs.getString(_patientsKey);
    if (patientsJson != null) {
      final List<dynamic> decoded = jsonDecode(patientsJson);
      return decoded.map((e) => Patient.fromJson(e)).toList();
    }
    return [];
  }

  Future<void> savePatient(Patient patient) async {
    final prefs = await SharedPreferences.getInstance();
    final List<Patient> patients = await getPatients();
    
    final index = patients.indexWhere((p) => p.id == patient.id);
    if (index != -1) {
      patients[index] = patient;
    } else {
      patients.add(patient);
    }

    await prefs.setString(_patientsKey, jsonEncode(patients.map((e) => e.toJson()).toList()));
  }
}
