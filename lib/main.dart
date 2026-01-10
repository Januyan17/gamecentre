import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:provider/provider.dart';
import 'core/providers/session_provider.dart';
import 'core/providers/connectivity_provider.dart';
import 'core/screens/main_navigation.dart';
import 'core/screens/no_internet_screen.dart';
import 'core/services/notification_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();

  // Initialize notification service
  await NotificationService().initialize();

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => SessionProvider()),
        ChangeNotifierProvider(create: (_) => ConnectivityProvider()),
      ],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'Gaming Center Staff',
        theme: ThemeData(
          primarySwatch: Colors.deepPurple,
          primaryColor: Colors.purple.shade700,
          colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.purple.shade700,
            primary: Colors.purple.shade700,
          ),
          appBarTheme: AppBarTheme(
            backgroundColor: Colors.purple.shade700,
            foregroundColor: Colors.white,
            elevation: 0,
          ),
        ),
        home: const ConnectivityWrapper(),
      ),
    );
  }
}

/// Wrapper widget that shows NoInternetScreen when offline, MainNavigation when online
class ConnectivityWrapper extends StatelessWidget {
  const ConnectivityWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<ConnectivityProvider>(
      builder: (context, connectivityProvider, child) {
        // Show no internet screen when offline
        if (!connectivityProvider.isConnected) {
          return const NoInternetScreen();
        }
        // Show main app when online
        return const MainNavigation();
      },
    );
  }
}
