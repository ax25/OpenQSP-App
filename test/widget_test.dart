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

    await tester.enterText(callsignField, '   ');
    await tester.pump();

    final whitespaceButton = tester.widget<ElevatedButton>(continueButton);
    expect(whitespaceButton.onPressed, isNull);
  });

  testWidgets('entering a callsign enables Continue', (tester) async {
    await tester.pumpWidget(const OpenQspApp());

    await tester.enterText(callsignField, 'ea3gnu');
    await tester.pump();

    final button = tester.widget<ElevatedButton>(continueButton);
    expect(button.onPressed, isNotNull);
  });

  testWidgets('editing in the middle preserves the cursor position', (
    tester,
  ) async {
    await tester.pumpWidget(const OpenQspApp());

    await tester.showKeyboard(callsignField);
    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: 'ea3gnu',
        selection: TextSelection.collapsed(offset: 2),
      ),
    );
    await tester.pump();

    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: 'eax3gnu',
        selection: TextSelection.collapsed(offset: 3),
      ),
    );
    await tester.pump();

    final field = tester.widget<TextField>(callsignField);
    expect(field.controller?.text, 'EAX3GNU');
    expect(
      field.controller?.selection,
      const TextSelection.collapsed(offset: 3),
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

  testWidgets('form stays fluid in a narrow viewport', (tester) async {
    tester.view.physicalSize = const Size(320, 480);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const OpenQspApp());

    expect(tester.getSize(callsignField).width, 272);
    expect(tester.getSize(continueButton).width, 272);
    expect(tester.takeException(), isNull);
  });

  testWidgets('form is centered and constrained in a wide viewport', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const OpenQspApp());

    expect(tester.getSize(callsignField).width, 420);
    expect(tester.getSize(continueButton).width, 420);
    expect(tester.getCenter(callsignField).dx, 600);
    expect(tester.takeException(), isNull);
  });
}
