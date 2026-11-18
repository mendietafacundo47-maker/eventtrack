// Panel web administrativo: navegación por rol, revisión de evidencias y
// diseño adaptable (escritorio 1366×768, §3.2.2, y pantallas angostas).
import 'package:eventtrack/domain/entities/panel.dart';
import 'package:eventtrack/domain/entities/user.dart';
import 'package:eventtrack/features/auth/presentation/auth_controller.dart';
import 'package:eventtrack/features/panel/presentation/panel_app.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/fake_panel_api.dart';
import 'helpers/real_fonts.dart';

const desktop = Size(1366, 768);
const phone = Size(390, 844);

void main() {
  late FakePanelApi api;

  setUpAll(() async {
    await loadRealFonts();
    WidgetController.hitTestWarningShouldBeFatal = true;
  });

  setUp(() => api = FakePanelApi());

  Future<void> pumpPanel(
    WidgetTester tester,
    User user, {
    Size size = desktop,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final auth = AuthController(FakeAuthRepository(user));
    await tester.pumpWidget(PanelApp(auth: auth, api: api));
    await auth.restore();
    await tester.pumpAndSettle();
  }

  /// Las tablas anchas se desplazan: primero se lleva el botón a la vista.
  Future<void> tapVisible(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  Future<void> goTo(WidgetTester tester, String section) async {
    final menu = find.byTooltip('Open navigation menu');
    if (menu.evaluate().isNotEmpty) {
      // Pantalla angosta: las secciones están en el menú lateral.
      await tester.tap(menu);
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(of: find.byType(Drawer), matching: find.text(section)),
      );
    } else {
      await tester.tap(
        find.descendant(of: find.byType(AppBar), matching: find.text(section)),
      );
    }
    await tester.pumpAndSettle();
  }

  testWidgets('CAP-02: resumen del evento activo con indicadores y bandeja', (
    tester,
  ) async {
    await pumpPanel(tester, supervisor);

    expect(find.text('Resumen del evento'), findsOneWidget);
    expect(find.text('TOTAL ACTIVIDADES'), findsOneWidget);
    expect(find.text('PENDIENTES'), findsOneWidget);
    expect(find.text('COMPLETADAS'), findsOneWidget);
    expect(find.text('Acreditación Zona A'), findsOneWidget);
    expect(find.text('Sin evidencia aún'), findsWidgets);
    expect(find.text('Sin asignar'), findsOneWidget);
    // Supervisor: puede aprobar o rechazar la evidencia pendiente.
    expect(find.widgetWithText(OutlinedButton, 'Aprobar'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'Rechazar'), findsOneWidget);
  });

  testWidgets('TC-20: rechazar desde el panel exige motivo', (tester) async {
    await pumpPanel(tester, supervisor);

    await tapVisible(tester, find.widgetWithText(OutlinedButton, 'Rechazar'));
    await tester.tap(find.widgetWithText(FilledButton, 'Rechazar'));
    await tester.pumpAndSettle();
    expect(find.text('Indica el motivo del rechazo.'), findsOneWidget);
    expect(api.reviews, isEmpty);

    await tester.enterText(
      find.byType(TextFormField),
      'La foto está desenfocada.',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Rechazar'));
    await tester.pumpAndSettle();
    expect(api.reviews.single, (
      'ev-1',
      ReviewStatus.rejected,
      'La foto está desenfocada.',
    ));
  });

  testWidgets('TC-19: aprobar desde el detalle de la evidencia', (
    tester,
  ) async {
    await pumpPanel(tester, supervisor);
    await goTo(tester, 'Evidencias');

    expect(find.text('Permiso de ubicación denegado'), findsOneWidget);
    await tapVisible(tester, find.text('Revisar').first);

    expect(find.text('Capturada (dispositivo)'.toUpperCase()), findsOneWidget);
    expect(find.text('Recibida (servidor)'.toUpperCase()), findsOneWidget);
    expect(
      find.textContaining('indicador, no prueba de presencia'),
      findsOneWidget,
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Aprobar'));
    await tester.pumpAndSettle();
    expect(api.reviews.single.$2, ReviewStatus.approved);
  });

  testWidgets('el organizador gestiona eventos pero no revisa', (tester) async {
    await pumpPanel(tester, organizer);

    expect(find.widgetWithText(OutlinedButton, 'Aprobar'), findsNothing);
    expect(find.text('Usuarios'), findsNothing);

    await goTo(tester, 'Eventos');
    expect(find.text('Nuevo evento'), findsOneWidget);
    expect(find.text('Congreso Universitario de Informática'), findsOneWidget);

    await tester.tap(find.text('Nuevo evento'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();
    // TC-05: validación en el formulario antes de llamar al backend.
    expect(find.text('Ingresa al menos 3 caracteres.'), findsOneWidget);
    expect(find.text('Indica la fecha de inicio y de fin.'), findsOneWidget);
  });

  testWidgets('el supervisor no ve acciones de gestión', (tester) async {
    await pumpPanel(tester, supervisor);
    await goTo(tester, 'Eventos');
    expect(find.text('Nuevo evento'), findsNothing);
    await goTo(tester, 'Actividades');
    expect(find.text('Nueva actividad'), findsNothing);
    expect(find.text('Asignar'), findsNothing);
  });

  testWidgets('solo el administrador ve Usuarios', (tester) async {
    await pumpPanel(tester, admin);
    await goTo(tester, 'Usuarios');
    expect(find.text('Nuevo usuario'), findsOneWidget);
    expect(find.text('Ana Admin (tú)'), findsOneWidget);
    expect(find.text('Inactivo'.toUpperCase()), findsOneWidget);
  });

  testWidgets('el responsable no usa el panel web', (tester) async {
    await pumpPanel(tester, responsible);
    expect(
      find.textContaining('aplicación EventTrack para Android'),
      findsOneWidget,
    );
    expect(find.text('Resumen del evento'), findsNothing);
  });

  for (final size in [desktop, phone]) {
    final label = size == desktop ? 'escritorio' : 'celular';
    testWidgets('sin desbordes en todas las secciones ($label)', (
      tester,
    ) async {
      await pumpPanel(tester, admin, size: size);
      for (final section in [
        'Eventos',
        'Actividades',
        'Evidencias',
        'Usuarios',
        'Reportes',
        'Resumen',
      ]) {
        await goTo(tester, section);
        expect(tester.takeException(), isNull, reason: section);
      }
      expect(find.text('Resumen del evento'), findsOneWidget);
    });
  }
}
