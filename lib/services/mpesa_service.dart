import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:http/http.dart' as http;
import 'package:cloud_firestore/cloud_firestore.dart';

/// Thrown with a message that is safe to show to the user.
class MpesaException implements Exception {
  final String message;
  const MpesaException(this.message);

  @override
  String toString() => message;
}

class MpesaService {
  static const String _vercelUrl =
      'https://telmed-backend.vercel.app/api/initiate_mpesa';

  final FirebaseFirestore _db = FirebaseFirestore.instance;

  /// Returns a strict Daraja number "2547XXXXXXXX" / "2541XXXXXXXX",
  /// or throws [MpesaException] if the input can't be a Safaricom number.
  String _formatPhoneNumber(String phone) {
    String cleaned = phone.replaceAll(RegExp(r'\D'), '');

    if (cleaned.startsWith('254')) {
      // already international
    } else if (cleaned.startsWith('0')) {
      cleaned = '254${cleaned.substring(1)}';
    } else if (cleaned.length == 9 &&
        (cleaned.startsWith('7') || cleaned.startsWith('1'))) {
      cleaned = '254$cleaned';
    }

    if (!RegExp(r'^254[17]\d{8}$').hasMatch(cleaned)) {
      throw const MpesaException(
        'Enter a valid Safaricom number, e.g. 712345678.',
      );
    }
    return cleaned;
  }

  /// Triggers the STK push. Returns the checkoutRequestID, or throws a
  /// [MpesaException] explaining what went wrong.
  Future<String> initiatePayment({
    required String phoneNumber,
    required int amount,
  }) async {
    final String formattedPhone = _formatPhoneNumber(phoneNumber);
    debugPrint('M-Pesa: POST $_vercelUrl phone=$formattedPhone amount=$amount');

    final http.Response response;
    try {
      response = await http
          .post(
            Uri.parse(_vercelUrl),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'phone': formattedPhone, 'amount': amount}),
          )
          .timeout(const Duration(seconds: 30));
    } on TimeoutException {
      throw const MpesaException(
        'The payment server took too long to respond. Please try again.',
      );
    } catch (e) {
      debugPrint('M-Pesa network error: $e');
      // On Flutter web a blocked CORS request shows up here as
      // "ClientException: Failed to fetch" with no status code.
      throw MpesaException(
        kIsWeb
            ? 'Could not reach the payment server (network or CORS). Details: $e'
            : 'Could not reach the payment server. Check your connection.',
      );
    }

    debugPrint('M-Pesa: status=${response.statusCode} body=${response.body}');

    Map<String, dynamic> data = {};
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) data = decoded;
    } catch (_) {
      // body wasn't JSON (e.g. a Vercel HTML error page)
    }

    if (response.statusCode != 200) {
      final String serverMsg = (data['error'] ??
              data['errorMessage'] ??
              data['message'] ??
              data['ResponseDescription'] ??
              '')
          .toString();
      throw MpesaException(
        'Payment request failed (${response.statusCode})'
        '${serverMsg.isNotEmpty ? ': $serverMsg' : '.'}',
      );
    }

    // Accept any casing the backend might use (Daraja itself returns
    // "CheckoutRequestID").
    final dynamic id = data['checkoutRequestID'] ??
        data['CheckoutRequestID'] ??
        data['checkoutRequestId'];

    if (id == null || id.toString().isEmpty) {
      throw MpesaException(
        'Server replied OK but without a checkout ID. Response: ${response.body}',
      );
    }
    return id.toString();
  }

  /// Listens to the payment document the webhook updates.
  Stream<DocumentSnapshot> listenToPaymentStatus(String checkoutRequestId) {
    return _db.collection('payments').doc(checkoutRequestId).snapshots();
  }
}