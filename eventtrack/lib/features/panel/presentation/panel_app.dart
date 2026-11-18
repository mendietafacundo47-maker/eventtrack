import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_theme.dart';
import '../../../data/remote/panel_api.dart';
import '../../auth/presentation/auth_controller.dart';
import '../application/panel_selection.dart';
import 'panel_router.dart';

/// Mismo tema que la app móvil, pero en escritorio los botones principales
/// no ocupan todo el ancho (se mantiene el alto táctil de 48, RNF-12).
ThemeData _panelTheme() {
  final base = AppTheme.light();
  return base.copyWith(
    filledButtonTheme: FilledButtonThemeData(
      style: base.filledButtonTheme.style!.copyWith(
        minimumSize: const WidgetStatePropertyAll(Size(64, 48)),
      ),
    ),
  );
}

/// Panel web administrativo (§3.2.2, §4.1.4).
class PanelApp extends StatefulWidget {
  const PanelApp({super.key, required this.auth, required this.api});

  final AuthController auth;
  final PanelApi api;

  @override
  State<PanelApp> createState() => _PanelAppState();
}

class _PanelAppState extends State<PanelApp> {
  late final GoRouter _router = buildPanelRouter(widget.auth);
  late final PanelSelection _selection = PanelSelection(widget.api);
  String? _userId;

  @override
  void initState() {
    super.initState();
    widget.auth.addListener(_onAuth);
    _onAuth();
  }

  /// Los eventos visibles dependen del usuario: se recargan al cambiar de sesión.
  void _onAuth() {
    final id = widget.auth.user?.id;
    if (id == _userId) return;
    _userId = id;
    _selection.clear();
    if (id != null) _selection.load();
  }

  @override
  void dispose() {
    widget.auth.removeListener(_onAuth);
    _router.dispose();
    _selection.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: widget.auth),
        ChangeNotifierProvider.value(value: _selection),
        Provider.value(value: widget.api),
      ],
      child: MaterialApp.router(
        title: 'EventTrack · Panel administrativo',
        debugShowCheckedModeBanner: false,
        theme: _panelTheme(),
        routerConfig: _router,
      ),
    );
  }
}
