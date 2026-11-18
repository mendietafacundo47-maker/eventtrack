// Pantalla B: tarjetas legibles en teléfono con texto ampliado (RNF-12).
import 'package:eventtrack/core/theme/app_theme.dart';
import 'package:eventtrack/domain/entities/assignment.dart';
import 'package:eventtrack/features/activities/presentation/my_activities_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Assignment sample(ActivityStatus status) => Assignment(
  id: 'asg-${status.code}',
  activityId: 'act',
  activityTitle: 'Registro de asistencia de expositores',
  activityDescription: '',
  activityStatus: status,
  dueAt: DateTime.utc(2026, 11, 12),
  eventId: 'evt',
  eventName: 'Congreso universitario de informática',
);

void main() {
  for (final scale in [1.0, 1.3]) {
    testWidgets('sin desbordes a 360 dp con texto ×$scale', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: MediaQuery(
            data: MediaQueryData(
              size: const Size(360, 800),
              textScaler: TextScaler.linear(scale),
            ),
            child: Scaffold(
              // Column (no ListView) para construir todas las tarjetas.
              body: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    for (final s in ActivityStatus.values)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: ActivityCard(
                          assignment: sample(s),
                          unsyncedCount: 2,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );

      expect(tester.takeException(), isNull);
      // Cada estado se identifica por texto, no solo por color.
      for (final s in ActivityStatus.values) {
        expect(find.text(s.label.toUpperCase()), findsOneWidget);
      }
      expect(find.text('2 evidencias sin sincronizar'), findsNWidgets(5));
    });
  }
}
