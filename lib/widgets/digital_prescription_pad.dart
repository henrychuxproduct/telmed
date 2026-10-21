import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/prescription_service.dart'; 

class DigitalPrescriptionPad extends StatefulWidget {
  final String roomId;

  const DigitalPrescriptionPad({super.key, required this.roomId});

  @override
  State<DigitalPrescriptionPad> createState() => _DigitalPrescriptionPadState();
}

class _DigitalPrescriptionPadState extends State<DigitalPrescriptionPad> {
  final PrescriptionService _prescriptionService = PrescriptionService();

  // The real signed-in doctor (was hard-coded to "Dr. Doctor" before).
  String get _doctorName {
    final String n = FirebaseAuth.instance.currentUser?.displayName?.trim() ?? '';
    if (n.isEmpty) return 'Doctor';
    return n.toLowerCase().startsWith('dr') ? n : 'Dr. $n';
  }

  String? get _doctorUid => FirebaseAuth.instance.currentUser?.uid;

  // --- CONTROLLERS ---
  final TextEditingController _patientAgeController = TextEditingController(); 
  final TextEditingController _medicineController = TextEditingController();
  final TextEditingController _notesController = TextEditingController(); 
  
  String _selectedQty = "Select Quantity";
  String _selectedFrequency = "Select Frequency";
  String _selectedDuration = "Select Duration";

  final List<Map<String, dynamic>> _prescribedItems = [];
  bool _isIssuing = false;
  bool _isListConfirmed = false; // NEW: Tracks if doctor is done adding meds

  final List<String> _quantities = ["Select Quantity", "1 Tablet", "2 Tablets", "5ml (1 tsp)", "10ml", "1 Capsule", "1 Injection", "Apply Thinly"];
  final List<String> _frequencies = [
    "Select Frequency", "Once a day (OD)", "Twice a day (BD)", "3 times a day (TDS)", "4 times a day (QDS)", "Before Bed (ON)", "When needed (PRN)"
  ];
  final List<String> _durations = ["Select Duration", "1 Day", "3 Days", "5 Days", "7 Days", "14 Days", "30 Days"];

  bool get _isInputValid {
    return _medicineController.text.trim().isNotEmpty &&
           _selectedQty != "Select Quantity" &&
           _selectedFrequency != "Select Frequency" &&
           _selectedDuration != "Select Duration";
  }

  // --- NEW: SILENT BACKGROUND SYNC ---
  Future<void> _syncLiveDraft() async {
    if (widget.roomId.isEmpty) return;
    
    await _prescriptionService.savePrescription(
      roomId: widget.roomId,
      doctorId: _doctorName,
        doctorUid: _doctorUid,
      patientAge: _patientAgeController.text.trim(), 
      medications: _prescribedItems,
      doctorNotes: _notesController.text.trim(),
      status: 'draft', 
    );
  }

  void _addMedication() {
    if (!_isInputValid) return;

    setState(() {
      _prescribedItems.add({
        'medicine': _medicineController.text.trim().toUpperCase(),
        'dosage': "$_selectedQty, $_selectedFrequency",
        'duration': _selectedDuration,
      });
      
      _medicineController.clear();
      _selectedQty = "Select Quantity";
      _selectedFrequency = "Select Frequency";
      _selectedDuration = "Select Duration";
    });

    _syncLiveDraft();
  }

  void _removeMedication(int index) {
    setState(() {
      _prescribedItems.removeAt(index);
      // Reset confirmation if the list becomes empty
      if (_prescribedItems.isEmpty) {
        _isListConfirmed = false;
      }
    });
    
    _syncLiveDraft();
  }

  void _showPopup(String title, String message, {bool isError = false}) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(isError ? Icons.error_outline : Icons.check_circle, color: isError ? Colors.red : Colors.green),
            const SizedBox(width: 10),
            Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("OK", style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Future<void> _issuePrescription() async {
    if (_prescribedItems.isEmpty) return;
    
    if (_patientAgeController.text.trim().isEmpty) {
      _showPopup("Missing Info", "Please enter the Patient's Age.", isError: true);
      return;
    }

    if (widget.roomId.isEmpty) {
      _showPopup("Connection Error", "Room ID is missing. Please wait for the call to connect fully.", isError: true);
      return;
    }

    setState(() => _isIssuing = true);

    try {
      bool success = await _prescriptionService.savePrescription(
        roomId: widget.roomId,
        doctorId: _doctorName,
        doctorUid: _doctorUid,
        patientAge: _patientAgeController.text.trim(), 
        medications: _prescribedItems,
        doctorNotes: _notesController.text.trim(),
        status: 'issued', 
      );

      if (success && mounted) {
        _showPopup("Success", "Prescription finalized and locked for the patient!");
        setState(() {
          _prescribedItems.clear();
          _notesController.clear(); 
          _patientAgeController.clear();
          _isListConfirmed = false; // Reset view for next patient
        });
      } else if (!success && mounted) {
        _showPopup("Failed", "Failed to save prescription. Check internet or Firebase rules.", isError: true);
      }
    } catch (e) {
      debugPrint("Fulfillment Error: $e");
      if (mounted) _showPopup("Error", "An unexpected error occurred: $e", isError: true);
    } finally {
      if (mounted) setState(() => _isIssuing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity, // <-- CHANGED: Allows it to shrink on small screens
      constraints: const BoxConstraints(maxWidth: 420), // <-- CHANGED: Max width for large screens
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 40, offset: const Offset(0, 15))],
      ),
      child: Column(
        children: [
          _buildSafetyHeader(),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _sectionLabel("PATIENT DETAILS (PRIVATE)"),
                  _buildTextInput(
                    _patientAgeController, 
                    "Patient Age (Years)", 
                    Icons.cake_outlined, 
                    isNumber: true,
                  ),
                  const SizedBox(height: 20),

                  // Hide input fields if list is confirmed to keep UI clean
                  if (!_isListConfirmed) ...[
                    _sectionLabel("PHARMACEUTICAL ITEM"),
                    _buildTextInput(_medicineController, "Enter Generic or Brand Name", Icons.medication_liquid),
                    const SizedBox(height: 20),
                    
                    _sectionLabel("REGIMEN (DOSAGE & FREQUENCY)"),
                    _buildDosagePickers(),
                    const SizedBox(height: 20),
                    
                    _sectionLabel("COURSE DURATION"),
                    _buildDurationPicker(),
                    const SizedBox(height: 25),
                    
                    _buildAddButton(),
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 25),
                      child: Divider(color: Color(0xFFE2E8F0), thickness: 1),
                    ),
                  ],
                  
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _sectionLabel("ACTIVE PRESCRIPTION LIST"),
                      if (_isListConfirmed)
                        TextButton(
                          onPressed: () => setState(() => _isListConfirmed = false),
                          style: TextButton.styleFrom(
                            padding: EdgeInsets.zero,
                            minimumSize: const Size(50, 20),
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          child: const Text("Edit List", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                        ),
                    ],
                  ),
                  _buildMedicationList(),

                  // NEW: Confirmation Button
                  if (_prescribedItems.isNotEmpty && !_isListConfirmed)
                    Padding(
                      padding: const EdgeInsets.only(top: 20),
                      child: _buildConfirmListButton(),
                    ),

                  // Only show notes if the list is confirmed
                  if (_isListConfirmed) ...[
                    const SizedBox(height: 25),
                    _sectionLabel("DOCTOR'S NOTES / INSTRUCTIONS"),
                    Focus(
                      onFocusChange: (hasFocus) {
                        if (!hasFocus) _syncLiveDraft();
                      },
                      child: _buildDoctorNotesInput(),
                    ),
                  ],
                ],
              ),
            ),
          ),
          // Only show the finalize button if the list is confirmed
          if (_isListConfirmed) _buildFinalActionArea(),
        ],
      ),
    );
  }

  Widget _buildSafetyHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
      decoration: const BoxDecoration(
        color: Color(0xFF1E293B), 
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Row(
        children: [
          const Icon(Icons.verified_user, color: Color(0xFFF9A825), size: 22),
          const SizedBox(width: 12),
          Text(
            "DIGITAL RX TERMINAL", 
            style: GoogleFonts.plusJakartaSans(
              color: Colors.white, 
              fontWeight: FontWeight.w800, 
              fontSize: 15,
              letterSpacing: 1.1
            )
          ),
        ],
      ),
    );
  }

  Widget _sectionLabel(String label) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10, left: 2),
      child: Text(
        label, 
        style: GoogleFonts.plusJakartaSans(
          fontSize: 11, 
          fontWeight: FontWeight.w900, 
          color: const Color(0xFF64748B), 
          letterSpacing: 1.5
        )
      ),
    );
  }

  Widget _buildTextInput(TextEditingController controller, String hint, IconData icon, {bool isNumber = false}) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: TextField(
        controller: controller,
        keyboardType: isNumber ? TextInputType.number : TextInputType.text,
        onChanged: (_) => setState(() {}),
        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(color: Colors.grey.shade400, fontWeight: FontWeight.normal, fontSize: 13),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          border: InputBorder.none,
          suffixIcon: Icon(icon, color: const Color(0xFF94A3B8), size: 20),
        ),
      ),
    );
  }

  Widget _buildDoctorNotesInput() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: TextField(
        controller: _notesController,
        maxLines: 3, 
        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
        decoration: InputDecoration(
          hintText: "Add dietary restrictions, advice, or follow-up instructions...",
          hintStyle: TextStyle(color: Colors.grey.shade400, fontWeight: FontWeight.normal),
          contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          border: InputBorder.none,
        ),
      ),
    );
  }

  Widget _buildDosagePickers() {
    return Row(
      children: [
        Expanded(child: _safetyDropdown(_quantities, _selectedQty, (v) => setState(() => _selectedQty = v!))),
        const SizedBox(width: 12),
        Expanded(child: _safetyDropdown(_frequencies, _selectedFrequency, (v) => setState(() => _selectedFrequency = v!))),
      ],
    );
  }

  Widget _buildDurationPicker() {
    return _safetyDropdown(_durations, _selectedDuration, (v) => setState(() => _selectedDuration = v!));
  }

  Widget _safetyDropdown(List<String> items, String value, ValueChanged<String?> onChanged) {
    bool isDefault = value.contains("Select");
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white, 
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: isDefault ? Colors.orange.shade200 : const Color(0xFFE2E8F0), width: 1.5),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          isExpanded: true,
          icon: Icon(Icons.keyboard_arrow_down, color: isDefault ? Colors.orange : Colors.blueGrey),
          style: GoogleFonts.plusJakartaSans(
            color: isDefault ? Colors.grey : const Color(0xFF1E293B), 
            fontSize: 13, 
            fontWeight: isDefault ? FontWeight.normal : FontWeight.w700
          ),
          items: items.map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
          onChanged: onChanged,
        ),
      ),
    );
  }

  Widget _buildAddButton() {
    return SizedBox(
      width: double.infinity,
      height: 55,
      child: ElevatedButton(
        onPressed: _isInputValid ? _addMedication : null,
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF2D7D46),
          disabledBackgroundColor: Colors.grey.shade200,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          elevation: 0,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.add_task, color: _isInputValid ? Colors.white : Colors.grey),
            const SizedBox(width: 10),
            Text(
              "VALIDATE & ADD ITEM", 
              style: TextStyle(
                color: _isInputValid ? Colors.white : Colors.grey, 
                fontWeight: FontWeight.w800
              )
            ),
          ],
        ),
      ),
    );
  }

  // NEW: Confirm List Button
  Widget _buildConfirmListButton() {
    return SizedBox(
      width: double.infinity,
      height: 55,
      child: ElevatedButton(
        onPressed: () => setState(() => _isListConfirmed = true),
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF0F172A), // Dark slate to match header
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          elevation: 0,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: const [
            Icon(Icons.checklist_rtl, color: Colors.white),
            SizedBox(width: 10),
            Text(
              "CONFIRM MEDICATION LIST", 
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800)
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMedicationList() {
    if (_prescribedItems.isEmpty) {
      return Container(
        height: 120,
        width: double.infinity,
        decoration: BoxDecoration(
          color: Colors.white, 
          borderRadius: BorderRadius.circular(16), 
          border: Border.all(color: const Color(0xFFF1F5F9), width: 2)
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.inventory_2_outlined, color: Colors.grey.shade300, size: 30),
            const SizedBox(height: 10),
            Text("List is currently empty", style: TextStyle(color: Colors.grey.shade400, fontSize: 13)),
          ],
        ),
      );
    }
    return Column(
      children: _prescribedItems.asMap().entries.map((entry) {
        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: Colors.white, 
            borderRadius: BorderRadius.circular(16), 
            border: Border.all(color: const Color(0xFFE2E8F0)),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 10)]
          ),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
            title: Text(entry.value['medicine']!, style: const TextStyle(fontWeight: FontWeight.w900, color: Color(0xFF0F172A), fontSize: 14)),
            subtitle: Text("${entry.value['dosage']} • ${entry.value['duration']}", style: const TextStyle(fontSize: 12, color: Color(0xFF64748B))),
            trailing: IconButton(
              icon: const Icon(Icons.cancel_outlined, color: Colors.redAccent, size: 22), 
              onPressed: () => _removeMedication(entry.key)
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildFinalActionArea() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: const BoxDecoration(
        color: Colors.white, 
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(24)),
        border: Border(top: BorderSide(color: Color(0xFFF1F5F9)))
      ),
      child: Column(
        children: [
          if (_prescribedItems.isEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 15),
              child: Text(
                "Add at least one item to proceed", 
                style: TextStyle(color: Colors.orange.shade800, fontSize: 12, fontWeight: FontWeight.bold)
              ),
            ),
          ElevatedButton(
            onPressed: _prescribedItems.isEmpty || _isIssuing ? null : _issuePrescription,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFF9A825),
              disabledBackgroundColor: Colors.grey.shade100,
              minimumSize: const Size(double.infinity, 60),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              elevation: 0,
            ),
            child: _isIssuing
                ? const CircularProgressIndicator(color: Colors.white)
                : Text(
                    "FINALIZE & ISSUE RX", 
                    style: GoogleFonts.plusJakartaSans(
                      color: _prescribedItems.isEmpty ? Colors.grey : Colors.white, 
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1
                    )
                  ),
          ),
        ],
      ),
    );
  }
}