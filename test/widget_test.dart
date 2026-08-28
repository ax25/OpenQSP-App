import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openqsp_app/app/app.dart';
import 'package:openqsp_app/features/callsign/data/callsign_store.dart';

class FakeCallsignStore implements CallsignStore {
  FakeCallsignStore([this.value]);

  String? value;

  @override
  Future<String?> read() async => value;

  @override
  Future<void> write(String callsign) async => value = callsign;
}

void main() {
  final callsignField = find.byKey(const Key('callsignField'));
  final continueButton = find.byKey(const Key('continueButton'));

  Future<void> pumpApp(WidgetTester tester, FakeCallsignStore store) async {
    await tester.pumpWidget(OpenQspApp(callsignStore: store));
    await tester.pumpAndSettle();
  }

  testWidgets('first launch shows onboarding', (tester) async {
    await pumpApp(tester, FakeCallsignStore());
    expect(find.text('Insert your callsign'), findsOneWidget);
  });

  testWidgets('submitting normalizes, persists, and opens Home', (tester) async {
    final store = FakeCallsignStore();
    await pumpApp(tester, store);
    await tester.enterText(callsignField, ' ea3gnu-5 ');
    await tester.pump();
    await tester.tap(continueButton);
    await tester.pumpAndSettle();

    expect(store.value, 'EA3GNU-5');
    expect(find.byKey(const Key('homeCallsign')), findsOneWidget);
    expect(find.text('EA3GNU-5'), findsOneWidget);
  });

  testWidgets('stored callsign skips onboarding and populates Home', (
    tester,
  ) async {
    await pumpApp(tester, FakeCallsignStore('EA3GNU'));
    expect(find.text('Insert your callsign'), findsNothing);
    expect(find.text('EA3GNU'), findsOneWidget);
  });

  testWidgets('Home presents status, services, and all transports', (
    tester,
  ) async {
    await pumpApp(tester, FakeCallsignStore('EA3GNU'));
    expect(find.text('Internet'), findsOneWidget);
    expect(find.text('Server available'), findsOneWidget);
    expect(find.text('Messages'), findsOneWidget);
    expect(find.text('Bulletins'), findsOneWidget);

    await tester.tap(find.byKey(const Key('transportSelector')));
    await tester.pumpAndSettle();
    expect(find.text('Internet'), findsNWidgets(2));
    expect(find.text('APRS'), findsOneWidget);
    expect(find.text('Winlink'), findsOneWidget);
    final aprs = tester.widget<PopupMenuItem<String>>(
      find.ancestor(
        of: find.text('APRS'),
        matching: find.byType(PopupMenuItem<String>),
      ),
    );
    final winlink = tester.widget<PopupMenuItem<String>>(
      find.ancestor(
        of: find.text('Winlink'),
        matching: find.byType(PopupMenuItem<String>),
      ),
    );
    expect(aprs.enabled, isFalse);
    expect(winlink.enabled, isFalse);
  });

  testWidgets('changing callsign updates storage and Home', (tester) async {
    final store = FakeCallsignStore('EA3GNU');
    await pumpApp(tester, store);
    await tester.tap(find.byKey(const Key('editCallsignButton')));
    await tester.pumpAndSettle();

    expect(tester.widget<TextField>(callsignField).controller?.text, 'EA3GNU');
    await tester.enterText(callsignField, 'n0call');
    await tester.pump();
    await tester.tap(continueButton);
    await tester.pumpAndSettle();

    expect(store.value, 'N0CALL');
    expect(find.text('N0CALL'), findsOneWidget);
  });

  for (final size in [const Size(320, 480), const Size(1200, 800)]) {
    testWidgets('Home has no overflow at ${size.width}x${size.height}', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await pumpApp(tester, FakeCallsignStore('EA3GNU'));
      expect(tester.takeException(), isNull);
      final scrollable = tester.state<ScrollableState>(
        find.descendant(
          of: find.byKey(const Key('homeScrollView')),
          matching: find.byType(Scrollable),
        ),
      );
      expect(scrollable.position.maxScrollExtent, 0);
    });
  }

  testWidgets('empty callsign keeps Continue disabled', (tester) async {
    await pumpApp(tester, FakeCallsignStore());
    expect(tester.widget<ElevatedButton>(continueButton).onPressed, isNull);
  });

  testWidgets('uppercase normalization preserves a middle cursor position', (
    tester,
  ) async {
    await pumpApp(tester, FakeCallsignStore());
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
}
