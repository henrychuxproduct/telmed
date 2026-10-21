import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

/// Prescription lifecycle:  draft  ->  issued  ->  dispensed
///  - draft     : doctor is still typing during the call (live-synced)
///  - issued    : doctor finalised it; patient can see/print it, QR is valid
///  - dispensed : a pharmacy packed it; the QR can no longer be reused
class PrescriptionService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  /// Saves or updates a prescription linked to the unique [roomId].
  /// Returns false if the save was refused or failed.
  Future<bool> savePrescription({
    required String roomId,
    required String patientAge,
    required List<dynamic> medications,
    required String doctorNotes,
    required String doctorId, // display name, e.g. "Dr. Jane Doe"
    String? doctorUid,
    String status = 'issued',
  }) async {
    try {
      final DocumentReference ref = _db.collection('prescriptions').doc(roomId);

      return await _db.runTransaction<bool>((tx) async {
        final snap = await tx.get(ref);
        final String? existing = snap.exists
            ? (snap.data() as Map<String, dynamic>)['status'] as String?
            : null;

        // A dispensed prescription is final.
        if (existing == 'dispensed') {
          debugPrint('PrescriptionService: $roomId already dispensed - refused.');
          return false;
        }
        // A late "live draft" sync must never downgrade an issued prescription
        // (this used to silently revert it to draft on the patient's screen).
        if (existing == 'issued' && status == 'draft') {
          debugPrint('PrescriptionService: ignoring draft sync for issued $roomId.');
          return false;
        }

        final Map<String, dynamic> data = {
          'roomId': roomId,
          'doctorId': doctorId,
          if (doctorUid != null) 'doctorUid': doctorUid,
          'patientAge': patientAge,
          'medications': medications,
          'doctorNotes': doctorNotes,
          'status': status,
          // issuedAt only means something once it is actually issued
          if (status == 'issued')
            'issuedAt': FieldValue.serverTimestamp()
          else
            'updatedAt': FieldValue.serverTimestamp(),
        };

        tx.set(ref, data, SetOptions(merge: true));
        return true;
      });
    } catch (e) {
      debugPrint('PrescriptionService: Error saving prescription: $e');
      return false;
    }
  }

  /// Marks an issued prescription as dispensed.
  /// Returns null on success, or a user-friendly error message.
  Future<String?> markDispensed({
    required String roomId,
    required String dispensedBy,
  }) async {
    try {
      final ref = _db.collection('prescriptions').doc(roomId);

      return await _db.runTransaction<String?>((tx) async {
        final snap = await tx.get(ref);
        if (!snap.exists) return 'Prescription not found.';

        final status = (snap.data() as Map<String, dynamic>)['status'];
        if (status == 'dispensed') {
          return 'This prescription has already been dispensed.';
        }
        if (status != 'issued') {
          return 'This prescription has not been finalised by the doctor.';
        }

        tx.update(ref, {
          'status': 'dispensed',
          'dispensedAt': FieldValue.serverTimestamp(),
          'dispensedBy': dispensedBy,
        });
        return null;
      });
    } catch (e) {
      debugPrint('PrescriptionService: Error marking dispensed: $e');
      return 'Could not update the prescription. Check your connection.';
    }
  }

  Stream<DocumentSnapshot> getPrescriptionStream(String roomId) {
    return _db.collection('prescriptions').doc(roomId).snapshots();
  }

  Future<Map<String, dynamic>?> getPrescription(String roomId) async {
    try {
      final DocumentSnapshot doc =
          await _db.collection('prescriptions').doc(roomId).get();
      if (doc.exists) {
        return doc.data() as Map<String, dynamic>;
      }
      return null;
    } catch (e) {
      debugPrint('PrescriptionService: Error fetching prescription: $e');
      return null;
    }
  }
}