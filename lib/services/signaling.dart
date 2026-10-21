import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_webrtc/flutter_webrtc.dart';

typedef StreamHandler = void Function(MediaStream stream);
typedef ConnectionHandler = void Function(RTCPeerConnectionState state);
// NOTE: the old `typedef VoidCallback` was removed. It clashed with Flutter's
// own VoidCallback in every file that imported both (ambiguous import).

class Signaling {
  // Optional TURN server, passed at build time:
  //   --dart-define=TURN_URL=turn:your.server:3478
  //   --dart-define=TURN_USER=xxx --dart-define=TURN_PASS=yyy
  // STUN alone cannot connect many mobile-data / corporate networks (CGNAT /
  // symmetric NAT). Those calls show "connected" signalling but NO video.
  static const String _turnUrl = String.fromEnvironment('TURN_URL');
  static const String _turnUser = String.fromEnvironment('TURN_USER');
  static const String _turnPass = String.fromEnvironment('TURN_PASS');

  Map<String, dynamic> get configuration => {
        'iceServers': [
          {
            'urls': [
              'stun:stun1.l.google.com:19302',
              'stun:stun2.l.google.com:19302',
            ]
          },
          if (_turnUrl.isNotEmpty)
            {
              'urls': [_turnUrl],
              'username': _turnUser,
              'credential': _turnPass,
            },
        ]
      };

  RTCPeerConnection? peerConnection;
  MediaStream? localStream;
  MediaStream? remoteStream;
  String? roomId;

  StreamHandler? onAddRemoteStream;
  ConnectionHandler? onConnectionState;
  void Function()? onCallEnded;
  void Function()? onCallAccepted;

  final List<RTCIceCandidate> _candidateQueue = [];
  final List<StreamSubscription<dynamic>> _subs = [];
  bool _isRemoteDescriptionSet = false;
  bool _answerApplied = false;
  bool _endedNotified = false;

  Stream<QuerySnapshot> getRoomsStream() {
    return FirebaseFirestore.instance.collection('rooms').snapshots();
  }

  void _cancelSubs() {
    for (final s in _subs) {
      s.cancel();
    }
    _subs.clear();
  }

  void _notifyEnded() {
    if (_endedNotified) return; // fire once, not on every snapshot
    _endedNotified = true;
    onCallEnded?.call();
  }

  // --- 1. CALLER (Patient) ---
  Future<String> createRoom(
    RTCVideoRenderer remoteRenderer, {
    String? paymentId,
  }) async {
    final FirebaseFirestore db = FirebaseFirestore.instance;
    final DocumentReference roomRef = db.collection('rooms').doc();

    _endedNotified = false;
    _answerApplied = false;

    peerConnection = await createPeerConnection(configuration);
    registerPeerConnectionListeners();

    if (localStream != null) {
      for (final track in localStream!.getTracks()) {
        peerConnection?.addTrack(track, localStream!);
      }
    }

    final callerCandidates = roomRef.collection('callerCandidates');
    peerConnection?.onIceCandidate = (RTCIceCandidate candidate) {
      callerCandidates.add(candidate.toMap());
    };

    final RTCSessionDescription offer = await peerConnection!.createOffer();
    await peerConnection!.setLocalDescription(offer);

    await roomRef.set({
      'offer': offer.toMap(),
      'createdAt': FieldValue.serverTimestamp(),
      if (paymentId != null) 'paymentId': paymentId,
    });

    roomId = roomRef.id;

    _subs.add(roomRef.snapshots().listen((snapshot) async {
      if (!snapshot.exists) {
        _notifyEnded();
        return;
      }

      final data = snapshot.data() as Map<String, dynamic>?;
      final bool isWaitingForAnswer = peerConnection?.signalingState ==
          RTCSignalingState.RTCSignalingStateHaveLocalOffer;

      if (isWaitingForAnswer &&
          !_answerApplied &&
          data != null &&
          data['answer'] != null) {
        _answerApplied = true; // snapshots can fire again while we await
        onCallAccepted?.call();

        final answer = RTCSessionDescription(
          data['answer']['sdp'],
          data['answer']['type'],
        );
        await peerConnection?.setRemoteDescription(answer);
        _isRemoteDescriptionSet = true;
        _processCandidateQueue();
      }
    }));

    _subs.add(roomRef.collection('calleeCandidates').snapshots().listen((snapshot) {
      for (final change in snapshot.docChanges) {
        if (change.type == DocumentChangeType.added) {
          final data = change.doc.data() as Map<String, dynamic>;
          _addCandidate(RTCIceCandidate(
            data['candidate'],
            data['sdpMid'],
            data['sdpMLineIndex'],
          ));
        }
      }
    }));

    return roomId!;
  }

  // --- 2. JOINER (Doctor) ---
  /// Throws a [StateError] with a user-friendly message if the patient is gone
  /// or another doctor already accepted. Nothing is deleted in that case.
  Future<void> joinRoom(String incomingRoomId, RTCVideoRenderer remoteVideo) async {
    final FirebaseFirestore db = FirebaseFirestore.instance;
    final DocumentReference roomRef = db.collection('rooms').doc(incomingRoomId);

    final roomSnapshot = await roomRef.get();
    if (!roomSnapshot.exists) {
      throw StateError('This patient is no longer waiting.');
    }
    final roomData = roomSnapshot.data() as Map<String, dynamic>;
    if (roomData['answer'] != null) {
      throw StateError('Another doctor has already accepted this patient.');
    }

    _endedNotified = false;
    _answerApplied = false;

    try {
      peerConnection = await createPeerConnection(configuration);
      registerPeerConnectionListeners();

      if (localStream != null) {
        for (final track in localStream!.getTracks()) {
          peerConnection?.addTrack(track, localStream!);
        }
      }

      final calleeCandidates = roomRef.collection('calleeCandidates');
      peerConnection?.onIceCandidate = (RTCIceCandidate candidate) {
        calleeCandidates.add(candidate.toMap());
      };

      final offer = roomData['offer'];
      await peerConnection!.setRemoteDescription(
        RTCSessionDescription(offer['sdp'], offer['type']),
      );
      _isRemoteDescriptionSet = true;

      final answer = await peerConnection!.createAnswer();
      await peerConnection!.setLocalDescription(answer);

      // Atomic claim: if two doctors tap ACCEPT together, only one wins.
      await db.runTransaction((tx) async {
        final snap = await tx.get(roomRef);
        if (!snap.exists) {
          throw StateError('This patient is no longer waiting.');
        }
        final d = snap.data() as Map<String, dynamic>?;
        if (d != null && d['answer'] != null) {
          throw StateError('Another doctor has already accepted this patient.');
        }
        tx.update(roomRef, {
          'answer': {'type': answer.type, 'sdp': answer.sdp},
          'answeredAt': FieldValue.serverTimestamp(),
        });
      });

      // Only now do we "own" the room (so hangUp may delete it).
      roomId = incomingRoomId;

      _subs.add(roomRef.snapshots().listen((snapshot) {
        if (!snapshot.exists) _notifyEnded();
      }));

      _subs.add(roomRef.collection('callerCandidates').snapshots().listen((snapshot) {
        for (final change in snapshot.docChanges) {
          // ignore 'removed' events fired when the patient cleans up
          if (change.type != DocumentChangeType.added) continue;
          final data = change.doc.data() as Map<String, dynamic>;
          _addCandidate(RTCIceCandidate(
            data['candidate'],
            data['sdpMid'],
            data['sdpMLineIndex'],
          ));
        }
      }));

      _processCandidateQueue();
    } catch (e) {
      // Roll back locally WITHOUT touching the room document.
      roomId = null;
      await _stopMediaAndPeer(null);
      rethrow;
    }
  }

  void _addCandidate(RTCIceCandidate candidate) {
    if (_isRemoteDescriptionSet && peerConnection != null) {
      peerConnection!.addCandidate(candidate);
    } else {
      _candidateQueue.add(candidate);
    }
  }

  void _processCandidateQueue() {
    for (final candidate in _candidateQueue) {
      peerConnection?.addCandidate(candidate);
    }
    _candidateQueue.clear();
  }

  /// Throws if the camera/mic can't be opened (permission denied, no device…)
  /// so the UI can show a real message. Previously the error was swallowed,
  /// which is why "Permission denied" never appeared in the UI.
  Future<void> openUserMedia(
    RTCVideoRenderer localVideo,
    RTCVideoRenderer remoteVideo,
  ) async {
    final Map<String, dynamic> mediaConstraints = {
      'audio': true,
      'video': {'facingMode': 'user', 'width': 1280, 'height': 720},
    };

    try {
      final stream = await navigator.mediaDevices.getUserMedia(mediaConstraints);
      localVideo.srcObject = stream;
      localStream = stream;
    } catch (e) {
      debugPrint('Signaling: Error opening user media: $e');
      rethrow;
    }
  }

  void toggleMic() {
    if (localStream != null && localStream!.getAudioTracks().isNotEmpty) {
      final track = localStream!.getAudioTracks()[0];
      track.enabled = !track.enabled;
    }
  }

  void toggleCamera() {
    if (localStream != null && localStream!.getVideoTracks().isNotEmpty) {
      final track = localStream!.getVideoTracks()[0];
      track.enabled = !track.enabled;
    }
  }

  Future<void> _stopMediaAndPeer(RTCVideoRenderer? localVideo) async {
    _cancelSubs();

    try {
      localVideo?.srcObject?.getTracks().forEach((t) => t.stop());
    } catch (e) {
      debugPrint('Error stopping renderer tracks: $e');
    }
    try {
      localStream?.getTracks().forEach((t) => t.stop());
    } catch (e) {
      debugPrint('Error stopping local tracks: $e');
    }
    try {
      remoteStream?.getTracks().forEach((t) => t.stop());
    } catch (e) {
      debugPrint('Error stopping remote tracks: $e');
    }

    try {
      await peerConnection?.close();
    } catch (e) {
      debugPrint('Error closing peer connection: $e');
    }

    try {
      await localStream?.dispose();
      await remoteStream?.dispose();
    } catch (e) {
      debugPrint('Error disposing streams: $e');
    }

    localStream = null;
    remoteStream = null;
    peerConnection = null;
    _isRemoteDescriptionSet = false;
    _answerApplied = false;
    _candidateQueue.clear();
  }

  Future<void> hangUp(RTCVideoRenderer localVideo, {String? roomId}) async {
    final String? targetRoomId = roomId ?? this.roomId;
    this.roomId = null;

    // 1. Hardware + listeners first. Cancelling listeners BEFORE we delete the
    //    room stops our own deletion from firing "call ended" back at us.
    await _stopMediaAndPeer(localVideo);

    // 2. Database cleanup (ghost rooms would otherwise stay in the queue).
    if (targetRoomId != null) {
      try {
        final roomRef =
            FirebaseFirestore.instance.collection('rooms').doc(targetRoomId);

        for (final sub in ['callerCandidates', 'calleeCandidates']) {
          final snap = await roomRef.collection(sub).get();
          for (final doc in snap.docs) {
            await doc.reference.delete();
          }
        }
        await roomRef.delete();
        debugPrint('Signaling: Room $targetRoomId deleted.');
      } catch (e) {
        debugPrint('Signaling: Error deleting room: $e');
      }
    }
  }

  void registerPeerConnectionListeners() {
    peerConnection?.onConnectionState = (RTCPeerConnectionState state) {
      debugPrint('Signaling: Connection state change: $state');
      onConnectionState?.call(state);
    };

    peerConnection?.onTrack = (RTCTrackEvent event) {
      debugPrint('Signaling: Track received: ${event.streams.length} streams');
      if (event.streams.isNotEmpty) {
        remoteStream = event.streams[0];
        onAddRemoteStream?.call(remoteStream!);
      }
    };
  }
}