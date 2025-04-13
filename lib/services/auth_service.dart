//auth_service.dart
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/user_model.dart';
import 'notification_service.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final GoogleSignIn _googleSignIn = GoogleSignIn();

  Future<UserModel?> signInWithEmail(String email, String password) async {
    try {
      final UserCredential result = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
      return _userFromFirebase(result.user);
    } on FirebaseAuthException catch (e) {
      throw _handleAuthException(e);
    }
  }

  Future<UserModel?> signUpWithEmail(
      String email, String password, String name) async {
    try {
      // Create auth user
      final UserCredential result = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
      
      // Update display name
      await result.user?.updateDisplayName(name);
      await result.user?.reload();  // Reload user data to get updated displayName
      
      // Create user model
      final user = _userFromFirebase(result.user);
      if (user != null) {
        // Create user document with retry mechanism
        int retries = 3;
        while (retries > 0) {
          try {
            await _createUserDocument(user, name);
            // Verify document creation
            final docSnapshot = await FirebaseFirestore.instance
                .collection('users')
                .doc(user.uid)
                .get();
            
            if (docSnapshot.exists) {
              return user;
            }
            retries--;
          } catch (e) {
            if (retries <= 1) throw Exception('Failed to create user profile after multiple attempts');
            retries--;
          }
        }
      }
      
      // If we get here without returning, something went wrong
      throw Exception('Failed to complete user registration');
    } on FirebaseAuthException catch (e) {
      throw _handleAuthException(e);
    }
  }

  Future<UserModel?> signInWithGoogle() async {
    try {
      // First, try to sign out to clear any previous session
      await _googleSignIn.signOut();

      // Start Google sign in process
      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();
      if (googleUser == null) {
        // User canceled sign-in
        return null;
      }

      // Get auth details from Google Sign In
      final GoogleSignInAuthentication googleAuth = await googleUser.authentication;

      // Create credential for Firebase
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      // Sign in to Firebase
      final UserCredential result = await _auth.signInWithCredential(credential);
      final User? firebaseUser = result.user;

      if (firebaseUser == null) {
        throw Exception('Failed to sign in with Google');
      }

      // Create user model
      final user = UserModel(
        uid: firebaseUser.uid,
        email: firebaseUser.email ?? '',
        name: firebaseUser.displayName ?? googleUser.displayName ?? 'User',
        photoUrl: firebaseUser.photoURL ?? googleUser.photoUrl ?? '',
      );

      // Create/update user document with retry mechanism
      int retries = 3;
      while (retries > 0) {
        try {
          await _createUserDocument(
            user,
            user.name,
            photoUrl: user.photoUrl
          );

          // Verify document creation
          final docSnapshot = await FirebaseFirestore.instance
              .collection('users')
              .doc(user.uid)
              .get();

          if (docSnapshot.exists) {
            return user;
          }
          retries--;
        } catch (e) {
          print('Error creating user document (attempt ${3-retries}/3): $e');
          if (retries <= 1) throw Exception('Failed to create user profile after multiple attempts');
          retries--;
        }
      }

      return user;
    } catch (e) {
      print('Google sign in error: $e');
      throw Exception('Failed to sign in with Google: $e');
    }
  }

  Future<void> signOut() async {
    try {
      final user = _auth.currentUser;
      if (user != null) {
        // Update user's presence data on logout
        await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .update({
          'isOnline': false,
          'lastSeen': FieldValue.serverTimestamp(),
          'presence.lastActivity': FieldValue.serverTimestamp(),
        });
      }
      
      await _googleSignIn.signOut();
      await _auth.signOut();
    } catch (e) {
      print('Error during sign out: $e');
      throw Exception('Failed to sign out');
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
      final userDoc = FirebaseFirestore.instance.collection('users').doc(user.uid);
      
      // Check if document already exists
      final docSnapshot = await userDoc.get();
      if (docSnapshot.exists) {
        await userDoc.update({
          'name': name,
          'photoUrl': photoUrl,
          'lastSeen': FieldValue.serverTimestamp(),
          'isOnline': true,
        });
      } else {
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
    } catch (e) {
      print('Error creating/updating user document: $e');
      throw Exception('Failed to create user profile');
    }
  }

  String _handleAuthException(FirebaseAuthException e) {
    switch (e.code) {
      case 'user-not-found':
        return 'No user found with this email.';
      case 'wrong-password':
        return 'Wrong password provided.';
      case 'email-already-in-use':
        return 'Email is already in use.';
      case 'weak-password':
        return 'The password provided is too weak.';
      default:
        return 'An error occurred. Please try again.';
    }
  }
}

