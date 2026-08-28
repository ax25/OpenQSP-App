import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openqsp_app/app/app.dart';

void main() {
  final callsignField = find.byKey(const Key('callsignField'));
  final continueButton = find.byKey(const Key('continueButton'));

  testWidgets('renders the callsign onboarding screen', (tester) async {
    await tester.pumpWidget(const OpenQspApp());

    expect(find.text('OpenQSP'), findsOneWidget);
    expect(find.text('Insert your callsign'), findsOneWidget);
    expect(find.text('Callsign'), findsOneWidget);
    expect(find.text('Continue'), findsOneWidget);
  });

  testWidgets('Continue is disabled while the callsign is empty', (
    tester,
  ) async {
    await tester.pumpWidget(const OpenQspApp());

    final button = tester.widget<ElevatedButton>(continueButton);
    expect(button.onPressed, isNull);
  });

  testWidgets('entering a callsign enables Continue', (tester) async {
    await tester.pumpWidget(const OpenQspApp());

    await tester.enterText(callsignField, 'ea3gnu');
    await tester.pump();

    final button = tester.widget<ElevatedButton>(continueButton);
    expect(button.onPressed, isNotNull);
  });

  testWidgets('callsign input is normalized without moving the selection', (
    tester,
  ) async {
    await tester.pumpWidget(const OpenQspApp());

    await tester.showKeyboard(callsignField);
    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: 'ea3gnu',
        selection: TextSelection(baseOffset: 2, extentOffset: 4),
      ),
    );
    await tester.pump();

    final field = tester.widget<TextField>(callsignField);
    expect(field.controller?.text, 'EA3GNU');
    expect(
      field.controller?.selection,
      const TextSelection(baseOffset: 2, extentOffset: 4),
    );
  });

  testWidgets('surrounding whitespace is trimmed on Continue', (tester) async {
    await tester.pumpWidget(const OpenQspApp());

    await tester.enterText(callsignField, ' ea3gnu-5 ');
    await tester.pump();

    var field = tester.widget<TextField>(callsignField);
    expect(field.controller?.text, ' EA3GNU-5 ');

    await tester.tap(continueButton);
    await tester.pump();

    field = tester.widget<TextField>(callsignField);
    expect(field.controller?.text, 'EA3GNU-5');
  });
}
