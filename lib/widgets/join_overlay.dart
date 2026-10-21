import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:google_fonts/google_fonts.dart';
import 'dart:math' as math;
import 'dart:ui';
import '../services/auth_service.dart';
import '../services/signaling.dart';
import 'digital_prescription_pad.dart';

class JoinOverlay extends StatefulWidget {
  const JoinOverlay({super.key});

  @override
  State<JoinOverlay> createState() => _JoinOverlayState();
}

class _JoinOverlayState extends State<JoinOverlay> {
  final Signaling _signaling = Signaling();
  final AuthService _authService = AuthService();
  final RTCVideoRenderer _localRenderer = RTCVideoRenderer();
  final RTCVideoRenderer _remoteRenderer = RTCVideoRenderer();

  bool _isJoined = false;
  // CHANGED: Instead of a boolean, we track the specific room ID being processed
  String? _processingRoomId; 
  
  // Media & UI State
  bool _isMicOn = true;
  bool _isCameraOn = true;
  bool _showPrescriptionPad = false; // Controls prescription pad visibility
  
  String? _localMediaError;
  String? _joinError;
  bool _checkingAccess = true;
  String? _accessError; // null = allowed
  String _connectionStatus = "Ready"; 

  @override
  void initState() {
    super.initState();
    _initRenderers();
    _checkDoctorAccess();

    _signaling.onCallEnded = () {
      if (mounted && _isJoined) {
         ScaffoldMessenger.of(context).showSnackBar(
           const SnackBar(content: Text("Call ended by patient"), backgroundColor: Colors.red),
         );
         _signaling.hangUp(_localRenderer);
         Navigator.pop(context);
      }
    };
  }

  /// Client-side guard. (Real protection must ALSO live in Firestore rules.)
  Future<void> _checkDoctorAccess() async {
    final user = _authService.currentUser;
    String? error;
    if (user == null) {
      error = 'Please sign in with a doctor account to view waiting patients.';
    } else {
      final profile = await _authService.getUserProfile(user.uid);
      if (profile == null || profile['role'] != 'doctor') {
        error = 'This portal is for registered doctors only.';
      } else if (profile['isVerified'] == false) {
        error = 'Your doctor account is awaiting verification by an administrator.';
      }
    }
    if (!mounted) return;
    setState(() {
      _accessError = error;
      _checkingAccess = false;
    });
  }

  Future<void> _initRenderers() async {
    await _localRenderer.initialize();
    await _remoteRenderer.initialize();
    
    _signaling.onAddRemoteStream = (stream) {
      _remoteRenderer.srcObject = stream;
      if (mounted) setState(() {});
    };

    _signaling.onConnectionState = (state) {
      if (mounted) setState(() => _connectionStatus = state.toString().split('.').last);
    };
  }

  @override
  void dispose() {
    if (_isJoined) _signaling.hangUp(_localRenderer);
    _localRenderer.dispose();
    _remoteRenderer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
      child: Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: EdgeInsets.zero,
        child: Container(
          width: MediaQuery.of(context).size.width,
          height: MediaQuery.of(context).size.height,
          color: const Color(0xFF0F172A).withOpacity(0.9),
          child: Column(
            children: [
              _buildHeader(),
              Expanded(
                child: _isJoined
                    ? _buildCallUI()
                    : (_checkingAccess
                        ? const Center(child: CircularProgressIndicator(color: Color(0xFF2D7D46)))
                        : (_accessError != null ? _buildAccessDenied() : _buildQueueList())),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    final bool compact = MediaQuery.of(context).size.width < 600;
    return Padding(
      padding: EdgeInsets.all(compact ? 16 : 30),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text("DOCTOR PORTAL", style: GoogleFonts.plusJakartaSans(color: Colors.white, fontWeight: FontWeight.w800, letterSpacing: 2)),
              Text("Status: $_connectionStatus", style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 12)),
            ],
          ),
          // ONLY SHOW THE CLOSE BUTTON IF THE DOCTOR HAS NOT JOINED A CALL
          if (!_isJoined)
            IconButton(
              icon: const Icon(Icons.close, color: Colors.white, size: 30),
              onPressed: () => Navigator.pop(context),
            )
        ],
      ),
    );
  }

  Widget _buildAccessDenied() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 480),
          padding: const EdgeInsets.all(30),
          decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(30), border: Border.all(color: Colors.white12)),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.lock_outline, color: Color(0xFFF9A825), size: 50),
              const SizedBox(height: 15),
              Text(_accessError!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 16, height: 1.4)),
              if (_authService.currentUser == null) ...[
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: () {
                    Navigator.pop(context);
                    Navigator.pushNamed(context, '/auth');
                  },
                  child: const Text("SIGN IN"),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildQueueList() {
    return Center(
      child: Container(
        width: math.min(600.0, MediaQuery.of(context).size.width - 32),
        padding: const EdgeInsets.all(30),
        decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(30), border: Border.all(color: Colors.white12)),
        child: Column(
          children: [
            const Icon(Icons.medical_services, color: Color(0xFFF9A825), size: 50),
            const SizedBox(height: 15),
            Text("Waiting Patients", style: GoogleFonts.plusJakartaSans(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
            const SizedBox(height: 30),
            if (_joinError != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Text(_joinError!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.redAccent, fontWeight: FontWeight.w600)),
              ),
            Expanded(
              child: StreamBuilder<QuerySnapshot>(
                stream: _signaling.getRoomsStream(),
                builder: (context, snapshot) {
                  if (!snapshot.hasData) return const Center(child: CircularProgressIndicator(color: Color(0xFF2D7D46)));
                  var queue = snapshot.data!.docs.where((doc) {
                    var data = doc.data() as Map<String, dynamic>;
                    if (data['offer'] == null || data['answer'] != null) return false;
                    // hide ghost rooms left behind by patients who closed the tab
                    final ts = data['createdAt'];
                    if (ts is Timestamp && DateTime.now().difference(ts.toDate()) > const Duration(minutes: 15)) {
                      return false;
                    }
                    return true;
                  }).toList();
                  
                  if (queue.isEmpty) return const Center(child: Text("No patients waiting", style: TextStyle(color: Colors.white38)));

                  return ListView.builder(
                    itemCount: queue.length,
                    itemBuilder: (context, index) {
                      var room = queue[index];
                      return ListTile(
                        leading: const Icon(Icons.person, color: Colors.white),
                        title: Text("Patient #${index + 1}", style: const TextStyle(color: Colors.white)),
                        trailing: ElevatedButton(
                          // Disable button if ANY room is currently processing
                          onPressed: _processingRoomId != null ? null : () => _joinRoom(room.id),
                          // Only show the loading spinner if THIS specific room is the one being processed
                          child: _processingRoomId == room.id && !_isJoined 
                             ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) 
                             : const Text("ACCEPT"),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _joinRoom(String roomId) async {
    if (_processingRoomId != null) return; // PREVENT DOUBLE CLICK

    setState(() {
      _processingRoomId = roomId;
      _localMediaError = null;
      _joinError = null;
    });

    try {
      // Camera/mic problems are not fatal for a doctor: continue receive-only.
      try {
        await _signaling.openUserMedia(_localRenderer, _remoteRenderer);
      } catch (e) {
        _localMediaError = e.toString();
      }

      await _signaling.joinRoom(roomId, _remoteRenderer);
      if (mounted) setState(() => _isJoined = true);
    } on StateError catch (e) {
      // e.g. patient left / another doctor was faster
      _localRenderer.srcObject = null;
      if (mounted) setState(() { _joinError = e.message; _localMediaError = null; });
    } catch (e) {
      _localRenderer.srcObject = null;
      if (mounted) setState(() { _joinError = 'Could not join the call: $e'; _localMediaError = null; });
    } finally {
      if (mounted) setState(() => _processingRoomId = null);
    }
  }

  Widget _buildCallUI() {
    bool hasRemoteVideo = _remoteRenderer.srcObject != null && _remoteRenderer.srcObject!.getVideoTracks().isNotEmpty;
    final bool compact = MediaQuery.of(context).size.width < 600;
    final double previewW = compact ? 110.0 : 180.0;
    final double previewH = compact ? 160.0 : 260.0;
    final double gap = compact ? 14.0 : 25.0;

    return Stack(
      children: [
        RTCVideoView(_remoteRenderer, objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover),
        
        if (!hasRemoteVideo)
          Container(
            color: Colors.black87,
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.signal_wifi_off, color: Colors.orange, size: 50),
                  const SizedBox(height: 20),
                  Text("NO PATIENT VIDEO", style: GoogleFonts.plusJakartaSans(color: Colors.orange, fontWeight: FontWeight.bold, fontSize: 18)),
                  const SizedBox(height: 10),
                  Text("Connection: $_connectionStatus", style: const TextStyle(color: Colors.white70)),
                  if (_localMediaError != null)
                     Text("Your Cam: $_localMediaError", style: const TextStyle(color: Colors.redAccent, fontSize: 12)),
                ],
              ),
            ),
          ),
          
        // Digital Prescription Pad - Toggled by _showPrescriptionPad
        if (_showPrescriptionPad)
          Positioned(
            left: 20, 
            right: 20, // <-- ADDED: Prevents overflow on the right side
            top: 30,
            bottom: 120, // Leaves room for the bottom call control buttons
            child: Align( // <-- ADDED: Ensures the BoxConstraints work perfectly
              alignment: Alignment.topLeft,
              child: DigitalPrescriptionPad(roomId: _signaling.roomId ?? ''), 
            ),
          ),

        // Local Preview (Floating) - NOW HIDES WHEN CAMERA IS OFF
        if (_isCameraOn && !(compact && _showPrescriptionPad))
          Positioned(
            right: compact ? 12 : 30, top: compact ? 12 : 30,
            child: Container(
              width: previewW, height: previewH,
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(20), border: Border.all(color: Colors.white24, width: 2)),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(18),
                child: _localMediaError != null
                   ? Container(color: Colors.red.withOpacity(0.3), child: const Center(child: Icon(Icons.warning, color: Colors.red)))
                   : RTCVideoView(_localRenderer, mirror: true, objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover),
              ),
            ),
          ),
        
        Positioned(
          bottom: 40, left: 0, right: 0,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Prescription Pad Toggle Button
              _circleBtn(
                icon: Icons.edit_document, 
                bgColor: _showPrescriptionPad ? const Color(0xFF2D7D46) : Colors.white, 
                iconColor: _showPrescriptionPad ? Colors.white : Colors.black,
                onTap: () {
                  setState(() => _showPrescriptionPad = !_showPrescriptionPad);
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
                  _signaling.hangUp(_localRenderer);
                  Navigator.pop(context);
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
        ),
      ],
    );
  }

  Widget _circleBtn({required IconData icon, required Color bgColor, required Color iconColor, VoidCallback? onTap}) {
    final bool compact = MediaQuery.of(context).size.width < 600;
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