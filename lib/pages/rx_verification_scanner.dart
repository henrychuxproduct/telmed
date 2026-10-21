import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../services/auth_service.dart';
import '../services/prescription_service.dart';

class RxVerificationScanner extends StatefulWidget {
  const RxVerificationScanner({super.key});

  @override
  State<RxVerificationScanner> createState() => _RxVerificationScannerState();
}

class _RxVerificationScannerState extends State<RxVerificationScanner> {
  final PrescriptionService _prescriptionService = PrescriptionService();
  final AuthService _authService = AuthService();
  final Color primaryGreen = const Color(0xFF2D7D46);
  
  String? _scannedRoomId;
  Map<String, dynamic>? _rxData;
  List<dynamic> _medications = [];
  
  // Tracks which medications the pharmacist has packed/checked off
  final Map<int, bool> _checkedItems = {};
  
  bool _isLoading = false;
  bool _isError = false;
  bool _isCompleting = false;
  String _errorMessage = "This prescription could not be found in the secure database.";
  DateTime? _lastInvalidToast;

  Future<void> _handleScan(BarcodeCapture capture) async {
    // Prevent multiple scans from firing simultaneously
    if (_scannedRoomId != null || _isLoading) return;

    final List<Barcode> barcodes = capture.barcodes;
    if (barcodes.isEmpty) return;
    final String rawValue = barcodes.first.rawValue ?? "";

    if (!rawValue.startsWith('VERIFY-RX-')) {
      // The camera reports the same frame many times a second: throttle.
      final now = DateTime.now();
      if (_lastInvalidToast == null || now.difference(_lastInvalidToast!) > const Duration(seconds: 3)) {
        _lastInvalidToast = now;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Invalid QR Code Format"), backgroundColor: Colors.red),
        );
      }
      return;
    }

    final String roomId = rawValue.replaceFirst('VERIFY-RX-', '');
    setState(() {
      _isLoading = true;
      _scannedRoomId = roomId;
    });

    final data = await _prescriptionService.getPrescription(roomId);
    if (!mounted) return;

    if (data == null) {
      setState(() {
        _isError = true;
        _isLoading = false;
        _errorMessage = "This prescription could not be found in the secure database.";
      });
      return;
    }

    final String? status = data['status'] as String?;
    if (status == 'dispensed') {
      setState(() {
        _isError = true;
        _isLoading = false;
        _errorMessage = "This prescription has ALREADY been dispensed. Do not issue the medication again.";
      });
    } else if (status != 'issued') {
      // drafts are still being typed by the doctor - they are not valid yet
      setState(() {
        _isError = true;
        _isLoading = false;
        _errorMessage = "This prescription has not been finalised by the doctor yet.";
      });
    } else {
      setState(() {
        _rxData = data;
        _medications = data['medications'] ?? [];
        for (int i = 0; i < _medications.length; i++) {
          _checkedItems[i] = false;
        }
        _isLoading = false;
      });
    }
  }

  /// Marks the prescription as dispensed so the QR can't be reused elsewhere.
  Future<void> _completeOrder() async {
    final user = _authService.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please sign in with a pharmacy account to complete orders."), backgroundColor: Colors.red),
      );
      return;
    }
    final String? role = await _authService.getUserRole(user.uid);
    if (!mounted) return;
    if (role != 'pharmacy') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Only pharmacy accounts can complete orders."), backgroundColor: Colors.red),
      );
      return;
    }

    setState(() => _isCompleting = true);
    final String? error = await _prescriptionService.markDispensed(
      roomId: _scannedRoomId!,
      dispensedBy: user.uid,
    );
    if (!mounted) return;
    setState(() => _isCompleting = false);

    if (error != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error), backgroundColor: Colors.red),
      );
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Order marked as dispensed."), backgroundColor: Color(0xFF2D7D46)),
    );
    _resetScanner();
  }

  void _resetScanner() {
    setState(() {
      _scannedRoomId = null;
      _rxData = null;
      _medications = [];
      _checkedItems.clear();
      _isError = false;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: Text("RX Verification", style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w800, fontSize: 18)),
        backgroundColor: Colors.white,
        foregroundColor: primaryGreen,
        elevation: 0.5,
        centerTitle: true,
        actions: [
          if (_scannedRoomId != null)
            IconButton(
              icon: const Icon(Icons.qr_code_scanner),
              onPressed: _resetScanner,
              tooltip: "Scan Another",
            )
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: primaryGreen),
            const SizedBox(height: 16),
            Text("Verifying Authenticity...", style: TextStyle(color: primaryGreen, fontWeight: FontWeight.bold)),
          ],
        ),
      );
    }

    if (_isError) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.gpp_bad_outlined, color: Colors.red, size: 60),
            const SizedBox(height: 16),
            Text("Verification Failed", style: GoogleFonts.plusJakartaSans(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Text(_errorMessage, textAlign: TextAlign.center),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: _resetScanner,
              style: ElevatedButton.styleFrom(backgroundColor: primaryGreen),
              child: const Text("TRY AGAIN", style: TextStyle(color: Colors.white)),
            )
          ],
        ),
      );
    }

    // If we have verified data, show the Checklist View
    if (_rxData != null) {
      return _buildChecklistView();
    }

    // Default View: The Live Camera Scanner
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(24),
          width: double.infinity,
          color: primaryGreen,
          child: Column(
            children: [
              const Icon(Icons.verified_user, color: Colors.white, size: 40),
              const SizedBox(height: 10),
              Text(
                "TELMED AUTHENTICATOR",
                style: GoogleFonts.plusJakartaSans(color: Colors.white, fontWeight: FontWeight.w900, letterSpacing: 1.5),
              ),
              const SizedBox(height: 5),
              const Text(
                "Scan patient QR code to verify and pack medications.",
                style: TextStyle(color: Colors.white70, fontSize: 13),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
        Expanded(
          child: Stack(
            alignment: Alignment.center,
            children: [
              MobileScanner(
                onDetect: _handleScan,
              ),
              // Optional: A visual targeting box
              Container(
                width: 250,
                height: 250,
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.white.withOpacity(0.5), width: 4),
                  borderRadius: BorderRadius.circular(20),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildChecklistView() {
    int checkedCount = _checkedItems.values.where((v) => v).length;
    bool allPacked = checkedCount == _medications.length;

    return Column(
      children: [
        // Verified Banner
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          color: const Color(0xFF1B4D2C),
          child: Row(
            children: [
              const Icon(Icons.verified, color: Colors.greenAccent, size: 30),
              const SizedBox(width: 15),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("VERIFIED PRESCRIPTION", style: GoogleFonts.plusJakartaSans(color: Colors.white, fontWeight: FontWeight.bold)),
                    Text("Doctor: ${_rxData!['doctorId']}", style: const TextStyle(color: Colors.white70, fontSize: 12)),
                  ],
                ),
              )
            ],
          ),
        ),
        
        // Progress Tracker
        Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text("PACKING CHECKLIST", style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w900, color: primaryGreen)),
              Text("$checkedCount / ${_medications.length} Packed", style: TextStyle(fontWeight: FontWeight.bold, color: allPacked ? primaryGreen : Colors.grey)),
            ],
          ),
        ),

        // Interactive Checklist
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: _medications.length,
            itemBuilder: (context, index) {
              var med = _medications[index];
              bool isChecked = _checkedItems[index] ?? false;

              return Card(
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: isChecked ? primaryGreen : Colors.grey.shade200, width: isChecked ? 2 : 1),
                ),
                color: isChecked ? primaryGreen.withOpacity(0.05) : Colors.white,
                margin: const EdgeInsets.only(bottom: 12),
                child: CheckboxListTile(
                  activeColor: primaryGreen,
                  checkColor: Colors.white,
                  title: Text(
                    med['medicine'], 
                    style: TextStyle(
                      fontWeight: FontWeight.bold, 
                      color: isChecked ? primaryGreen : Colors.black,
                      decoration: isChecked ? TextDecoration.lineThrough : null,
                    )
                  ),
                  subtitle: Text("${med['dosage']} • ${med['duration']}"),
                  value: isChecked,
                  onChanged: (bool? val) {
                    setState(() {
                      _checkedItems[index] = val ?? false;
                    });
                  },
                ),
              );
            },
          ),
        ),

        // Completion Action
        if (allPacked)
          Container(
            padding: const EdgeInsets.all(24),
            child: ElevatedButton(
              onPressed: _isCompleting ? null : _completeOrder,
              style: ElevatedButton.styleFrom(
                backgroundColor: primaryGreen,
                minimumSize: const Size(double.infinity, 60),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
              child: _isCompleting ? const SizedBox(height: 24, width: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 3)) : Text("ORDER PACKED & COMPLETE", style: GoogleFonts.plusJakartaSans(color: Colors.white, fontWeight: FontWeight.w900, letterSpacing: 1)),
            ),
          )
      ],
    );
  }
}