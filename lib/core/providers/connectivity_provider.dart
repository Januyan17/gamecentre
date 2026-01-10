import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

/// Provider to monitor internet connectivity status
class ConnectivityProvider extends ChangeNotifier {
  final Connectivity _connectivity = Connectivity();
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  
  bool _isConnected = true;
  bool get isConnected => _isConnected;

  ConnectivityProvider() {
    _initConnectivity();
    _connectivitySubscription = _connectivity.onConnectivityChanged.listen(
      _updateConnectionStatus,
      onError: (error) {
        debugPrint('Connectivity error: $error');
        _isConnected = false;
        notifyListeners();
      },
    );
  }

  /// Initialize connectivity status
  Future<void> _initConnectivity() async {
    try {
      final results = await _connectivity.checkConnectivity();
      _updateConnectionStatus(results);
    } catch (e) {
      debugPrint('Error checking connectivity: $e');
      _isConnected = false;
      notifyListeners();
    }
  }

  /// Update connection status based on connectivity results
  void _updateConnectionStatus(List<ConnectivityResult> results) {
    // Check if any of the connectivity results indicate internet access
    // None means no connection, others (wifi, mobile, ethernet, etc.) mean connected
    final wasConnected = _isConnected;
    _isConnected = results.isNotEmpty && 
                   !results.contains(ConnectivityResult.none) &&
                   results.any((result) => 
                     result == ConnectivityResult.wifi ||
                     result == ConnectivityResult.mobile ||
                     result == ConnectivityResult.ethernet ||
                     result == ConnectivityResult.vpn ||
                     result == ConnectivityResult.bluetooth ||
                     result == ConnectivityResult.other
                   );
    
    // Only notify if status changed
    if (wasConnected != _isConnected) {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _connectivitySubscription?.cancel();
    super.dispose();
  }
}
