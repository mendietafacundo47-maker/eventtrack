import 'package:connectivity_plus/connectivity_plus.dart';

/// Detecta si el dispositivo tiene alguna red. Tener red no garantiza llegar
/// al backend: los errores de envío se manejan igualmente en la cola.
abstract interface class NetworkMonitor {
  Future<bool> isOnline();

  Stream<bool> get onStatusChange;
}

class ConnectivityNetworkMonitor implements NetworkMonitor {
  ConnectivityNetworkMonitor([Connectivity? connectivity])
    : _connectivity = connectivity ?? Connectivity();

  final Connectivity _connectivity;

  static bool _hasNetwork(List<ConnectivityResult> results) =>
      results.any((r) => r != ConnectivityResult.none);

  @override
  Future<bool> isOnline() async =>
      _hasNetwork(await _connectivity.checkConnectivity());

  @override
  Stream<bool> get onStatusChange =>
      _connectivity.onConnectivityChanged.map(_hasNetwork).distinct();
}
