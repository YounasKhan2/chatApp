import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/user_model.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final GoogleSignIn _googleSignIn = GoogleSignIn();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Sign in with email and password
  Future<UserModel?> signInWithEmail(String email, String password) async {
    try {
      print('Attempting to sign in with email: $email');
      final UserCredential result = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );

      print('Email sign-in successful for ${result.user?.email}');
      final user = _userFromFirebase(result.user);

      if (user != null) {
        // Update user's online status
        await _firestore.collection('users').doc(user.uid).update({
          'isOnline': true,
          'lastSeen': FieldValue.serverTimestamp(),
        });
      }

      return user;
    } on FirebaseAuthException catch (e) {
      print('Email sign-in error: ${e.code} - ${e.message}');
      throw _handleAuthException(e);
    } catch (e) {
      print('Unexpected sign-in error: $e');
      throw Exception('An error occurred during sign in: $e');
    }
  }

  // Sign up with email, password, and name
  Future<UserModel?> signUpWithEmail(
      String email, String password, String name) async {
    try {
      print('Attempting to create account for: $email with name: $name');

      // Create auth user
      final UserCredential result = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );

      print('Firebase Auth account created successfully');

      // Update display name
      await result.user?.updateDisplayName(name);
      await result.user?.reload();

      print('Profile updated with name: $name');

      // Create user model
      final user = _userFromFirebase(_auth.currentUser);
      if (user != null) {
        // Create user document
        await _createUserDocument(user, name);
        print('User document created in Firestore');
        return user;
      } else {
        throw Exception('Failed to create user profile: User is null after authentication');
      }
    } on FirebaseAuthException catch (e) {
      print('Account creation error: ${e.code} - ${e.message}');
      throw _handleAuthException(e);
    } catch (e) {
      print('Unexpected signup error: $e');
      throw Exception('Failed to create account: $e');
    }
  }

  // Sign in with Google
  Future<UserModel?> signInWithGoogle() async {
    try {
      // Clear previous sessions
      await _googleSignIn.signOut();

      // Step 1: Google sign in
      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();
      if (googleUser == null) return null; // User canceled

      // Step 2: Get authentication tokens
      final GoogleSignInAuthentication googleAuth = await googleUser.authentication;

      // Step 3: Create credential
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      // Step 4: Sign into Firebase (THIS IS WHERE USERS ARE CREATED)
      final userCredential = await FirebaseAuth.instance.signInWithCredential(credential);
      final user = userCredential.user;

      if (user == null) return null;

      // Step 5: Create a custom UserModel instead of relying on automatic conversion
      final userModel = UserModel(
        uid: user.uid,
        email: user.email ?? '',
        name: user.displayName ?? 'User',
        photoUrl: user.photoURL ?? '',
      );

      // Step 6: Update Firestore document for the user
      try {
        await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
          'uid': user.uid,
          'email': user.email,
          'name': user.displayName ?? 'User',
          'photoUrl': user.photoURL ?? '',
          'lastSeen': FieldValue.serverTimestamp(),
          'isOnline': true,
        }, SetOptions(merge: true));
      } catch (e) {
        print('Firestore update error: $e');
        // Continue anyway - user is authenticated
      }

      return userModel;
    } catch (e) {
      print('Google sign-in error: $e');
      // Rethrow with clearer message
      throw Exception('Google sign-in failed: ${e.toString()}');
    }
  }

  Future<void> signOut() async {
    try {
      final user = _auth.currentUser;
      if (user != null) {
        // Update user's presence data on logout
        await _firestore.collection('users').doc(user.uid).update({
          'isOnline': false,
          'lastSeen': FieldValue.serverTimestamp(),
        });
      }

      await _googleSignIn.signOut();
      await _auth.signOut();
      print('User signed out successfully');
    } catch (e) {
      print('Error during sign out: $e');
      throw Exception('Failed to sign out: $e');
    }
  }

  UserModel? _userFromFirebase(User? user) {
    if (user == null) return null;
    return UserModel(
      uid: user.uid,
      email: user.email ?? '',
      name: user.displayName ?? '',
      photoUrl: user.photoURL ?? '',
    );
  }

  Future<void> _createUserDocument(UserModel user, String name, {String photoUrl = ''}) async {
    try {
      final userDoc = _firestore.collection('users').doc(user.uid);

      // Check if document already exists
      final docSnapshot = await userDoc.get();

      if (docSnapshot.exists) {
        print('Updating existing user document');
        await userDoc.update({
          'name': name,
          'photoUrl': photoUrl,
          'lastSeen': FieldValue.serverTimestamp(),
          'isOnline': true,
          'fcmToken': '', // This will be updated later by the notification service
        });
      } else {
        print('Creating new user document');
        // Create new document with updated schema
        final userData = {
          'uid': user.uid,
          'email': user.email,
          'name': name,
          'photoUrl': photoUrl,
          'createdAt': FieldValue.serverTimestamp(),
          'lastSeen': FieldValue.serverTimestamp(),
          'isOnline': true,
          'fcmToken': '',
          'settings': {
            'notifications': true,
            'emailNotifications': true,
          }
        };

        await userDoc.set(userData);
      }
      print('User document operation completed successfully');
    } catch (e) {
      print('Error creating/updating user document: $e');
      throw Exception('Failed to create user profile: $e');
    }
  }

  String _handleAuthException(FirebaseAuthException e) {
    print('Handling Firebase Auth Exception: ${e.code}');
    switch (e.code) {
      case 'user-not-found':
        return 'No user found with this email.';
      case 'wrong-password':
        return 'Wrong password provided.';
      case 'email-already-in-use':
        return 'Email is already in use by another account.';
      case 'weak-password':
        return 'The password provided is too weak. Please use a stronger password.';
      case 'invalid-email':
        return 'The email address is not valid.';
      case 'operation-not-allowed':
        return 'Email/password accounts are not enabled. Please contact support.';
      case 'account-exists-with-different-credential':
        return 'An account already exists with the same email but different sign-in credentials.';
      case 'invalid-credential':
        return 'The credential is malformed or has expired.';
      case 'network-request-failed':
        return 'Network error occurred. Please check your internet connection.';
      default:
        return 'An error occurred: ${e.message}';
    }
  }
}