import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

/// One-shot check used by AuthProvider / MealPlanProvider / UserProfileProvider /
/// BmiProvider before they attempt a network call. This lets those calls fail
/// instantly with a clear message instead of sitting through a slow timeout
/// when the device is offline.
Future<bool> hasInternetConnection() async {
  try {
    final result = await Connectivity().checkConnectivity();
    return result.any((r) => r != ConnectivityResult.none);
  } catch (e) {
    // If the connectivity check itself fails for some reason, don't block
    // the user — let the actual network call be the source of truth.
    debugPrint('Connectivity check failed: $e');
    return true;
  }
}

/// App-wide online/offline status, used to drive the persistent offline
/// banner in main.dart. Note this reflects whether the device has a network
/// interface up (Wi-Fi/mobile data), not true internet reachability — but
/// it's an instant signal that's good enough to warn the user before a
/// Firestore/API call is even attempted.
class ConnectivityProvider extends ChangeNotifier {
  final Connectivity _connectivity = Connectivity();
  StreamSubscription<List<ConnectivityResult>>? _subscription;

  bool _isOnline = true;
  bool get isOnline => _isOnline;

  Future<void> initialize() async {
    try {
      final result = await _connectivity.checkConnectivity();
      _isOnline = _hasConnection(result);
    } catch (e) {
      debugPrint('ConnectivityProvider init failed: $e');
    }
    notifyListeners();

    _subscription = _connectivity.onConnectivityChanged.listen((result) {
      final wasOnline = _isOnline;
      _isOnline = _hasConnection(result);
      if (wasOnline != _isOnline) notifyListeners();
    });
  }

  bool _hasConnection(List<ConnectivityResult> results) {
    return results.any((r) => r != ConnectivityResult.none);
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}