import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'screens/auth/login_screen.dart';
import 'screens/auth/signup_screen.dart';
import 'screens/users_screen.dart';
import 'screens/chat_screen.dart';
import 'models/user_model.dart';

void main() async {
  // Ensure Flutter is initialized
  WidgetsFlutterBinding.ensureInitialized();

  // Run with error handling
  runZonedGuarded(() async {
    try {
      // Initialize Firebase
      await Firebase.initializeApp();
      print('Firebase initialized successfully');

      // Run the app
      runApp(MyApp());
    } catch (e, stackTrace) {
      print('Error starting app: $e');
      print(stackTrace);
      // Show an error screen instead of crashing
      runApp(ErrorApp(error: e.toString()));
    }
  }, (error, stackTrace) {
    // Handle any errors that occur during app execution
    print('Uncaught error: $error');
    print(stackTrace);
  });
}

// Error screen if Firebase fails to initialize
class ErrorApp extends StatelessWidget {
  final String error;
  const ErrorApp({Key? key, required this.error}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.error_outline, color: Colors.red, size: 60),
                SizedBox(height: 16),
                Text('Failed to start the app',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                SizedBox(height: 8),
                Text(error, textAlign: TextAlign.center),
                SizedBox(height: 16),
                ElevatedButton(
                  onPressed: () {
                    // Try to restart the app
                    main();
                  },
                  child: Text('Try Again'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Chat App',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primarySwatch: Colors.blue,
        useMaterial3: true,
        // Add consistent styling
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            padding: EdgeInsets.symmetric(vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
          ),
          contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        ),
      ),
      home: _getHomeScreen(),
      routes: {
        '/login': (context) => LoginScreen(),
        '/signup': (context) => SignupScreen(),
        '/home': (context) => UsersScreen(),
      },
      onGenerateRoute: (settings) {
        if (settings.name == '/chat') {
          final receiver = settings.arguments as UserModel;
          return MaterialPageRoute(
            builder: (_) => ChatScreen(receiver: receiver),
          );
        }
        return null;
      },
    );
  }

  Widget _getHomeScreen() {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        // If waiting for auth check
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Scaffold(body: Center(child: CircularProgressIndicator()));
        }

        // If user is authenticated
        if (snapshot.hasData && snapshot.data != null) {
          return UsersScreen();
        }

        // If not authenticated
        return LoginScreen();
      },
    );
  }
}