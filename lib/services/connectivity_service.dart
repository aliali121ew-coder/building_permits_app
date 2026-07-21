import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';

class ConnectivityService {
  ConnectivityService._();
  static final ConnectivityService instance = ConnectivityService._();

  final Connectivity _connectivity = Connectivity();
  final StreamController<bool> _onlineController = StreamController<bool>.broadcast();

  Stream<bool> get onlineStream => _onlineController.stream;
  bool _isOnline = true;
  bool get isOnline => _isOnline;

  Future<void> init() async {
    final initial = await _connectivity.checkConnectivity();
    _isOnline = _hasConnection(initial);
    _onlineController.add(_isOnline);

    _connectivity.onConnectivityChanged.listen((results) {
      final online = _hasConnection(results);
      if (online != _isOnline) {
        _isOnline = online;
        _onlineController.add(online);
      }
    });
  }

  bool _hasConnection(List<ConnectivityResult> results) {
    return results.any((r) => r != ConnectivityResult.none);
  }

  void dispose() => _onlineController.close();
}
