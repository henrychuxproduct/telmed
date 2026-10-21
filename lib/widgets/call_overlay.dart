import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:ui';
import '../services/signaling.dart';
import '../services/prescription_service.dart';
import 'package:telmed/pages/home_page.dart';
import 'package:telmed/pages/patient_prescription_dashboard.dart'; 

class CallOverlay extends StatefulWidget {
  /// True only when the M-Pesa payment was confirmed (see TelmedHomePage).
  /// Without it the overlay refuses to start a call.
  final bool paymentVerified;

  /// The M-Pesa checkoutRequestID, stored on the room for reconciliation.
  final String? paymentId;

  const CallOverlay({super.key, this.paymentVerified = false, this.paymentId});

  @override
  State<CallOverlay> createState() => _CallOverlayState();
}

class _CallOverlayState extends State<CallOverlay> {
  final Signaling _signaling = Signaling();
  final PrescriptionService _prescriptionService = PrescriptionService();
  
  final RTCVideoRenderer _localRenderer = RTCVideoRenderer();
  final RTCVideoRenderer _remoteRenderer = RTCVideoRenderer();

  // Logic State
  bool _isPaying = false;
  bool _paymentConfirmed = false;
  bool _callConnecting = false;
  bool _hasPermissions = false;
  bool _isCallActive = false;
  
  // Media & UI State
  bool _isMicOn = true;
  bool _isCameraOn = true;
  bool _showPrescription = false; // Toggles the prescription view

  // DEBUGGING STATES
  String? _localMediaError; 
  String _connectionStatus = "Initializing"; 
  String? _roomId;
  bool _leaving = false;

  @override
  void initState() {
    super.initState();
    _initRenderers();

    // --- LISTEN FOR HANGUP ---
    _signaling.onCallEnded = () async {
      if (!mounted || _leaving) return;
      _leaving = true;

      final String? rid = _roomId;
      Map<String, dynamic>? rx;
      if (rid != null) rx = await _prescriptionService.getPrescription(rid);
      if (!mounted) return;

      _signaling.hangUp(_localRenderer, roomId: rid);

      // If the doctor already issued a prescription, don't throw the patient
      // back to the home page and lose it - take them straight to it.
      final bool hasRx = rid != null && rx != null && rx['status'] == 'issued';

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(hasRx ? "The call has ended. Your prescription is ready." : "The call has ended"),
          backgroundColor: hasRx ? const Color(0xFF2D7D46) : Colors.red,
        ),
      );
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(
          builder: (context) => hasRx
              ? PatientPrescriptionDashboard(roomId: rid)
              : const TelmedHomePage(),
        ),
        (Route<dynamic> route) => false,
      );
    };
  }

  Future<void> _initRenderers() async {
    await _localRenderer.initialize();
    await _remoteRenderer.initialize();

    _signaling.onCallAccepted = () {
      if (mounted) {
        setState(() {
          _isCallActive = true; 
        });
      }
    };

    _signaling.onAddRemoteStream = (stream) {
      if (mounted) {
        setState(() {
          _remoteRenderer.srcObject = stream;
          _isCallActive = true;
        });
      }
    };

    _signaling.onConnectionState = (state) {
      if (mounted) {
        setState(() {
          _connectionStatus = state.toString().split('.').last;
          
          if (_connectionStatus == 'connected' || _connectionStatus == 'completed') {
            _isCallActive = true;
          } else if (_connectionStatus == 'disconnected' || _connectionStatus == 'failed' || _connectionStatus == 'closed') {
            _isCallActive = false;
          }
        });
      }
    };
  }

  @override
  void dispose() {
    _signaling.hangUp(_localRenderer, roomId: _roomId);
    _localRenderer.dispose();
    _remoteRenderer.dispose();
    super.dispose();
  }

  /// Called from the button on the card. Payment was ALREADY verified on the
  /// home page (M-Pesa), so this only asks for camera/mic and starts the call.
  Future<void> _startConsultation() async {
    if (!widget.paymentVerified) return; // never start a call without payment

    setState(() {
      _isPaying = true;
      _localMediaError = null;
    });

    try {
      await _signaling.openUserMedia(_localRenderer, _remoteRenderer);
      if (!mounted) return;

      setState(() {
        _hasPermissions = true;
        _isPaying = false;
        _paymentConfirmed = true;
      });
      _startWebRTCCall();
    } catch (e) {
      debugPrint("Permission Error: $e");
      if (mounted) {
        setState(() {
          _isPaying = false;
          final String errorStr = e.toString();
          if (errorStr.contains('NotFoundError')) {
            _localMediaError = "Hardware Missing: No Camera/Mic found.";
          } else if (errorStr.contains('NotAllowedError') || errorStr.contains('PermissionDeniedError')) {
            _localMediaError = "Permission Denied: Click lock icon 🔒 to allow.";
          } else {
            _localMediaError = "Media Error: $e";
          }
        });
      }
    }
  }

  Future<void> _startWebRTCCall() async {
    setState(() => _callConnecting = true);
    try {
      _roomId = await _signaling.createRoom(_remoteRenderer, paymentId: widget.paymentId);
      if (mounted) setState(() => _callConnecting = false);
    } catch (e) {
      debugPrint("Call failed: $e");
      if (mounted) {
        setState(() {
          _callConnecting = false;
          _connectionStatus = "Room Creation Failed: $e";
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black.withOpacity(0.95),
      body: Stack(
        children: [
          // 1. Remote Video Layer
          if (_paymentConfirmed && !_callConnecting)
            Positioned.fill(
              child: _buildRemoteView(),
            ),

          // 2. Payment UI
          if (!_paymentConfirmed) _buildPaymentUI(),

          // 3. Loader
          if (_callConnecting)
            const Center(child: CircularProgressIndicator(color: Colors.greenAccent)),

          // 4. Local Preview (Floating) - NOW HIDES WHEN CAMERA IS OFF
          if (_isCameraOn && (_hasPermissions || _localMediaError != null)) 
            _buildLocalThumbnail(),

          // 5. Prescription Viewer Overlay
          if (_showPrescription && _roomId != null)
            Positioned(
              left: 20, 
              right: 20, 
              top: 100, 
              bottom: 140,
              child: Align(
                alignment: Alignment.topLeft,
                child: _buildPrescriptionView(),
              ),
            ),

          // 6. Controls
          if (_paymentConfirmed && !_callConnecting) ...[
            _buildActionControls(),
            if (!_isCallActive) _buildRoomIdDisplay(),
          ],

          // 7. Close Button
          if (!_paymentConfirmed || _callConnecting)
            Positioned(
              top: 40, right: 30,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white, size: 30),
                onPressed: () {
                   _signaling.hangUp(_localRenderer, roomId: _roomId);
                   Navigator.pushAndRemoveUntil(
                     context,
                     MaterialPageRoute(builder: (context) => const TelmedHomePage()),
                     (Route<dynamic> route) => false,
                   );
                },
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildRemoteView() {
    bool hasRemoteVideo = _remoteRenderer.srcObject != null && _remoteRenderer.srcObject!.getVideoTracks().isNotEmpty;
    bool isFullyConnected = _connectionStatus == 'connected' || _connectionStatus == 'completed';

    return Stack(
      children: [
        RTCVideoView(_remoteRenderer, objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover),
        
        if (!_isCallActive)
          _buildWaitingRoomUI(),
          
        if (_isCallActive && !hasRemoteVideo && !isFullyConnected)
          Container(
            color: const Color(0xFF1E293B),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(color: Colors.greenAccent),
                  const SizedBox(height: 25),
                  Text("Doctor Joined!", style: GoogleFonts.plusJakartaSans(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 10),
                  Text("Connecting video stream...", style: GoogleFonts.plusJakartaSans(color: Colors.white70, fontSize: 16)),
                ],
              ),
            ),
          ),

        if (_isCallActive && (hasRemoteVideo || isFullyConnected))
          Positioned(
            top: 40, left: 30,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFF2D7D46).withOpacity(0.9),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.greenAccent, width: 1)
              ),
              child: Row(
                children: [
                  Container(width: 10, height: 10, decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle)),
                  const SizedBox(width: 8),
                  Text("ACTIVE CALL", style: GoogleFonts.plusJakartaSans(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12, letterSpacing: 1)),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildPrescriptionView() {
    return Container(
      width: double.infinity, 
      constraints: const BoxConstraints(maxWidth: 380), 
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 20)],
      ),
      child: StreamBuilder<DocumentSnapshot>(
        stream: _prescriptionService.getPrescriptionStream(_roomId!),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(color: Color(0xFF2D7D46)));
          }
          
          if (!snapshot.hasData || !snapshot.data!.exists) {
            return _buildEmptyPrescriptionState();
          }

          var data = snapshot.data!.data() as Map<String, dynamic>;
          List<dynamic> medications = data['medications'] ?? [];
          String status = data['status'] ?? 'draft'; 
          
          return Column(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
                decoration: const BoxDecoration(
                  color: Color(0xFF1E293B),
                  borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.receipt_long, color: Color(0xFFF9A825), size: 22),
                    const SizedBox(width: 12),
                    Text("YOUR PRESCRIPTION", style: GoogleFonts.plusJakartaSans(color: Colors.white, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.all(24),
                  children: [
                    Text("Patient Age: ${data['patientAge']} yrs", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    Text("Doctor: ${data['doctorId']}", style: const TextStyle(color: Colors.grey, fontSize: 14)),
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 16),
                      child: Divider(),
                    ),
                    Text("MEDICATIONS", style: GoogleFonts.plusJakartaSans(color: Colors.grey.shade600, fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 1)),
                    const SizedBox(height: 10),
                    ...medications.map((med) => Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade50,
                        border: Border.all(color: Colors.grey.shade200),
                        borderRadius: BorderRadius.circular(12)
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(med['medicine'], style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                          const SizedBox(height: 4),
                          Text("${med['dosage']} • ${med['duration']}", style: TextStyle(color: Colors.grey.shade700, fontSize: 13)),
                        ],
                      ),
                    )),
                    if (data['doctorNotes'] != null && data['doctorNotes'].toString().isNotEmpty) ...[
                      const SizedBox(height: 20),
                      Text("DOCTOR'S NOTES", style: GoogleFonts.plusJakartaSans(color: Colors.grey.shade600, fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 1)),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(12)),
                        child: Text(data['doctorNotes'], style: TextStyle(color: Colors.blue.shade900, fontSize: 14)),
                      )
                    ],
                    
                    if (status == 'issued') ...[
                      const SizedBox(height: 30),
                      ElevatedButton(
                        onPressed: () {
                          try {
                            _signaling.hangUp(_localRenderer, roomId: _roomId);
                          } catch (e) {
                            debugPrint("WebRTC Hangup bypassed: $e");
                          }

                          if (!mounted) return;

                          Navigator.pushReplacement(
                            context,
                            MaterialPageRoute(
                              builder: (context) => PatientPrescriptionDashboard(roomId: _roomId!),
                            ),
                          );
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFF9A825), 
                          minimumSize: const Size(double.infinity, 60),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          elevation: 0,
                        ),
                        child: Text(
                          "PROCEED TO DASHBOARD",
                          style: GoogleFonts.plusJakartaSans(
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1,
                          ),
                        ),
                      ),
                    ]
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildEmptyPrescriptionState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(30),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.hourglass_empty, color: Colors.grey.shade300, size: 60),
            const SizedBox(height: 20),
            Text("No Prescription Yet", style: GoogleFonts.plusJakartaSans(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.grey.shade800)),
            const SizedBox(height: 10),
            Text("The doctor hasn't finalized your prescription yet. Check back here during or after the consultation.", textAlign: TextAlign.center, style: TextStyle(color: Colors.grey.shade600)),
          ],
        ),
      ),
    );
  }

  Widget _buildWaitingRoomUI() {
    return Container(
      color: const Color(0xFF1E293B),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(color: Color(0xFFF9A825), strokeWidth: 3),
            const SizedBox(height: 35),
            const Icon(Icons.health_and_safety, color: Color(0xFF2D7D46), size: 70), 
            const SizedBox(height: 25),
            Text("VIRTUAL WAITING ROOM", style: GoogleFonts.plusJakartaSans(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w900, letterSpacing: 1.5)),
            const SizedBox(height: 12),
            Text("Please wait patiently.", style: GoogleFonts.plusJakartaSans(color: Colors.white70, fontSize: 16)),
            const SizedBox(height: 6),
            Text("An available doctor will join shortly.", style: GoogleFonts.plusJakartaSans(color: Colors.white70, fontSize: 16)),
          ],
        ),
      ),
    );
  }

  Widget _buildRoomIdDisplay() {
    return Positioned(
      top: 40, left: 30,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SelectableText("Room ID: ${_roomId ?? 'Generating...'}", style: const TextStyle(color: Colors.white54, fontSize: 12)),
          Text("Conn: $_connectionStatus", style: const TextStyle(color: Colors.orange, fontSize: 10)),
        ],
      ),
    );
  }

  Widget _buildPaymentUI() {
    final bool verified = widget.paymentVerified;
    final bool compact = MediaQuery.of(context).size.width < 420;

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 380),
          child: Container(
            padding: EdgeInsets.all(compact ? 24 : 40),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(30)),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(verified ? Icons.verified_rounded : Icons.lock_outline, size: 60, color: const Color(0xFF2D7D46)),
                const SizedBox(height: 20),
                Text("KSH 54", style: GoogleFonts.plusJakartaSans(fontSize: compact ? 40 : 48, fontWeight: FontWeight.w900, color: const Color(0xFF1B4D2C))),
                const SizedBox(height: 8),
                Text(
                  verified ? "Payment received" : "Payment required",
                  style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700, color: verified ? const Color(0xFF2D7D46) : Colors.black54),
                ),
                if (!verified) ...[
                  const SizedBox(height: 12),
                  const Text(
                    "Please start from 'Call Telmed' on the home page so your M-Pesa payment can be verified.",
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.black54, height: 1.4),
                  ),
                ],
                const SizedBox(height: 30),
                if (_localMediaError != null)
                  Container(
                    margin: const EdgeInsets.only(bottom: 20),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.red.shade200)),
                    child: Row(
                      children: [
                        const Icon(Icons.error_outline, color: Colors.red),
                        const SizedBox(width: 10),
                        Expanded(child: Text(_localMediaError!, style: const TextStyle(color: Colors.red, fontSize: 13))),
                      ],
                    ),
                  ),
                ElevatedButton(
                  onPressed: (_isPaying || !verified) ? null : _startConsultation,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _localMediaError != null ? Colors.redAccent : const Color(0xFFF9A825),
                    minimumSize: const Size(double.infinity, 65),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                  ),
                  child: _isPaying
                      ? const CircularProgressIndicator(color: Colors.white)
                      : Text(_localMediaError != null ? "RETRY ACCESS" : "START CONSULTATION", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLocalThumbnail() {
    final bool compact = MediaQuery.of(context).size.width < 420;
    return Positioned(
      bottom: compact ? 120 : 140, right: compact ? 12 : 25,
      child: Container(
        width: compact ? 96 : 120, height: compact ? 144 : 180,
        decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(20), border: Border.all(color: Colors.white38, width: 2)),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: _localMediaError != null
              ? Container(color: Colors.red.withOpacity(0.2), child: const Center(child: Icon(Icons.no_photography, color: Colors.red, size: 30)))
              : RTCVideoView(_localRenderer, mirror: true, objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover),
        ),
      ),
    );
  }

  Widget _buildActionControls() {
    final double gap = MediaQuery.of(context).size.width < 420 ? 14 : 25;
    return Positioned(
      bottom: 40, left: 0, right: 0,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _circleBtn(
            icon: Icons.receipt_long, 
            bgColor: _showPrescription ? const Color(0xFF2D7D46) : Colors.white, 
            iconColor: _showPrescription ? Colors.white : Colors.black,
            onTap: () {
              setState(() => _showPrescription = !_showPrescription);
            }
          ),
          SizedBox(width: gap),
          _circleBtn(
            icon: _isMicOn ? Icons.mic : Icons.mic_off, 
            bgColor: _isMicOn ? Colors.white10 : Colors.white, 
            iconColor: _isMicOn ? Colors.white : Colors.black,
            onTap: () {
              _signaling.toggleMic();
              setState(() => _isMicOn = !_isMicOn);
            }
          ),
          SizedBox(width: gap),
          _circleBtn(
            icon: Icons.call_end, bgColor: Colors.red, iconColor: Colors.white,
            onTap: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text("You have ended the call"), backgroundColor: Colors.red),
              );
              _signaling.hangUp(_localRenderer, roomId: _roomId);
              Navigator.pushAndRemoveUntil(
                context,
                MaterialPageRoute(builder: (context) => const TelmedHomePage()),
                (Route<dynamic> route) => false,
              );
            }
          ),
          SizedBox(width: gap),
          _circleBtn(
            icon: _isCameraOn ? Icons.videocam : Icons.videocam_off, 
            bgColor: _isCameraOn ? Colors.white10 : Colors.white, 
            iconColor: _isCameraOn ? Colors.white : Colors.black,
            onTap: () {
              _signaling.toggleCamera();
              setState(() => _isCameraOn = !_isCameraOn);
            }
          ),
        ],
      ),
    );
  }

  Widget _circleBtn({required IconData icon, required Color bgColor, required Color iconColor, VoidCallback? onTap}) {
    final bool compact = MediaQuery.of(context).size.width < 420;
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.all(compact ? 14 : 18),
        decoration: BoxDecoration(color: bgColor, shape: BoxShape.circle),
        child: Icon(icon, color: iconColor, size: compact ? 26 : 30),
      ),
    );
  }
}