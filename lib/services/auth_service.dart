import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart'; 

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  /// THE FIX: Intercept the Auth Stream
  /// This prevents the race condition by guaranteeing the user's Firestore 
  /// document exists before the app is allowed to route them to a dashboard.
  Stream<User?> get authStateChanges {
    return _auth.authStateChanges().asyncMap((User? user) async {
      if (user == null) return null;

      // Loop to wait for the Firestore document to catch up to the Auth event
      int retries = 0;
      while (retries < 6) {
        try {
          DocumentSnapshot doc = await _db.collection('users').doc(user.uid).get();
          if (doc.exists) {
            debugPrint("AuthService: Auth & Firestore sync confirmed for ${user.uid}");
            return user;
          }
        } catch (e) {
          debugPrint("AuthService: Sync check failed: $e");
        }
        
        // Wait 500ms before checking again (Max 3 seconds total)
        await Future.delayed(const Duration(milliseconds: 500));
        retries++;
      }
      
      debugPrint("AuthService: Warning - User document not found after retries.");
      return user; // Return anyway to prevent infinite hanging, UI handles the null role
    });
  }

  // Get current user immediately
  User? get currentUser => _auth.currentUser;

  /// SIGN UP: Create Auth Credentials and Sync Role to Firestore
  Future<String?> signUp({
    required String email,
    required String password,
    required String name,
    required String role,
  }) async {
    try {
      debugPrint("AuthService: Attempting to sign up $role: $email");
      
      UserCredential userCredential = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );

      User? user = userCredential.user;

      if (user != null) {
        // 1. Update core Firebase profile
        await user.updateDisplayName(name);
        
        // 2. Build the user payload
        Map<String, dynamic> userData = {
          'uid': user.uid,
          'email': email,
          'name': name,
          'role': role, // 'patient', 'doctor', or 'pharmacy'
          'createdAt': FieldValue.serverTimestamp(),
          'isActive': true,
          // Doctors / pharmacies must be approved by an admin before they can
          // use the doctor portal. (Set isVerified: true in the Firestore console.)
          'isVerified': role == 'patient',
        };

        // 3. Sync to Firestore using merge to prevent destructive overwrites
        await _db.collection('users').doc(user.uid).set(userData, SetOptions(merge: true));
        
        debugPrint("AuthService: Successfully registered and synced user ${user.uid}");
        return null; // Success
      }
      return "An unknown error occurred during sign up.";
    } on FirebaseAuthException catch (e) {
      debugPrint("AuthService: FirebaseAuthException during sign up - ${e.code}");
      return _handleFirebaseAuthError(e);
    } catch (e) {
      debugPrint("AuthService: Error during sign up: $e");
      return "An unexpected error occurred. Please try again.";
    }
  }

  /// SIGN IN: Authenticate Existing Users
  Future<String?> signIn({
    required String email,
    required String password,
  }) async {
    try {
      debugPrint("AuthService: Attempting to sign in user: $email");
      
      await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
      
      debugPrint("AuthService: Successfully signed in.");
      return null; // Success
    } on FirebaseAuthException catch (e) {
      debugPrint("AuthService: FirebaseAuthException during sign in - ${e.code}");
      return _handleFirebaseAuthError(e);
    } catch (e) {
      debugPrint("AuthService: Error during sign in: $e");
      return "An unexpected error occurred. Please try again.";
    }
  }

  /// SIGN OUT: Clear Session
  Future<void> signOut() async {
    try {
      await _auth.signOut();
      debugPrint("AuthService: User successfully signed out.");
    } catch (e) {
      debugPrint("AuthService: Error during sign out: $e");
    }
  }

  /// FETCH USER ROLE: Safely extract the role for routing logic
  Future<String?> getUserRole(String uid) async {
    try {
      DocumentSnapshot doc = await _db.collection('users').doc(uid).get();
      
      if (doc.exists) {
        // Cast to Map to prevent StateError if fields are unexpectedly missing
        final data = doc.data() as Map<String, dynamic>?;
        
        if (data != null && data.containsKey('role')) {
          debugPrint("AuthService: Fetched role for user $uid");
          return data['role'] as String?;
        }
      }
      debugPrint("AuthService: No user document or role found for uid: $uid");
      return null;
    } catch (e) {
      debugPrint("AuthService: Error fetching user role: $e");
      return null;
    }
  }

  /// FETCH FULL PROFILE: role, isVerified, name...
  Future<Map<String, dynamic>?> getUserProfile(String uid) async {
    try {
      final DocumentSnapshot doc = await _db.collection('users').doc(uid).get();
      if (doc.exists) return doc.data() as Map<String, dynamic>?;
      return null;
    } catch (e) {
      debugPrint("AuthService: Error fetching profile: $e");
      return null;
    }
  }

  /// PASSWORD RESET: returns null on success (also when the email is unknown,
  /// so we don't reveal which emails have accounts).
  Future<String?> sendPasswordReset(String email) async {
    try {
      await _auth.sendPasswordResetEmail(email: email);
      return null;
    } on FirebaseAuthException catch (e) {
      if (e.code == 'user-not-found') return null;
      if (e.code == 'invalid-email') return 'The email address is not valid.';
      return _handleFirebaseAuthError(e);
    } catch (e) {
      debugPrint("AuthService: Error sending reset email: $e");
      return "An unexpected error occurred. Please try again.";
    }
  }

  /// HELPER: UI-Friendly Error Translation
  String _handleFirebaseAuthError(FirebaseAuthException e) {
    switch (e.code) {
      case 'user-not-found':
      case 'wrong-password':
      case 'invalid-credential':
        return 'Invalid email or password. Please try again.';
      case 'email-already-in-use':
        return 'An account already exists for that email.';
      case 'invalid-email':
        return 'The email address is not valid.';
      case 'weak-password':
        return 'The password provided is too weak. Please use at least 6 characters.';
      case 'user-disabled':
        return 'This account has been disabled. Please contact support.';
      case 'network-request-failed':
        return 'Network error. Please check your internet connection.';
      default:
        return e.message ?? 'An authentication error occurred.';
    }
  }
}