import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openqsp_app/app/app.dart';
import 'package:openqsp_app/core/network/server_status_client.dart';
import 'package:openqsp_app/features/auth/data/auth_client.dart';
import 'package:openqsp_app/features/auth/data/auth_token_store.dart';
import 'package:openqsp_app/features/callsign/data/callsign_store.dart';

class FakeCallsignStore implements CallsignStore {
  FakeCallsignStore([this.value]);

  String? value;

  @override
  Future<String?> read() async => value;

  @override
  Future<void> write(String callsign) async => value = callsign;
}

class FakeServerStatusClient implements ServerStatusClient {
  FakeServerStatusClient({this.result = true, this.pending});

  bool result;
  Future<bool>? pending;
  int checks = 0;

  @override
  Future<bool> isAvailable() {
    checks++;
    return pending ?? Future.value(result);
  }

  @override
  void close() {}
}

class FakeAuthClient implements AuthClient {
  LoginResult loginResult = const LoginSuccess('new-token');
  AuthValidationResult validationResult = AuthValidationResult.valid;
  int validations = 0;

  @override
  Future<LoginResult> login({
    required String callsign,
    required String password,
  }) async => loginResult;

  @override
  Future<AuthValidationResult> validateToken({
    required String token,
    required String callsign,
  }) async {
    validations++;
    return validationResult;
  }
  @override
  void close() {}
}

class FakeAuthTokenStore implements AuthTokenStore {
  final Map<String, String> tokens = {};
  @override
  Future<String?> read(String callsign) async => tokens[callsign];
  @override
  Future<void> write(String callsign, String token) async {
    tokens[callsign] = token;
  }

  @override
  Future<void> delete(String callsign) async => tokens.remove(callsign);
}

void main() {
  final callsignField = find.byKey(const Key('callsignField'));
  final continueButton = find.byKey(const Key('continueButton'));

  Future<void> pumpApp(
    WidgetTester tester,
    FakeCallsignStore store, {
    FakeServerStatusClient? statusClient,
    bool settle = true,
    FakeAuthClient? authClient,
    FakeAuthTokenStore? tokenStore,
  }) async {
    await tester.pumpWidget(
      OpenQspApp(
        callsignStore: store,
        serverStatusClient: statusClient ?? FakeServerStatusClient(),
        authClient: authClient ?? FakeAuthClient(),
        authTokenStore: tokenStore ?? FakeAuthTokenStore(),
      ),
    );
    if (settle) {
      await tester.pumpAndSettle();
    }
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

  testWidgets('Home initially shows checking state', (tester) async {
    final pending = Completer<bool>();
    final client = FakeServerStatusClient(
      pending: pending.future,
    );
    await pumpApp(
      tester,
      FakeCallsignStore('EA3GNU'),
      statusClient: client,
      settle: false,
    );
    await tester.pump();

    expect(find.text('Checking server...'), findsOneWidget);
  });

  testWidgets('Home shows unavailable when status check fails', (tester) async {
    await pumpApp(
      tester,
      FakeCallsignStore('EA3GNU'),
      statusClient: FakeServerStatusClient(result: false),
    );
    expect(find.text('Server unavailable'), findsOneWidget);
  });

  testWidgets('tapping status retries the check', (tester) async {
    final client = FakeServerStatusClient(result: false);
    await pumpApp(
      tester,
      FakeCallsignStore('EA3GNU'),
      statusClient: client,
    );
    expect(client.checks, 1);

    client.result = true;
    await tester.tap(find.byKey(const Key('serverStatusRetry')));
    await tester.pumpAndSettle();

    expect(client.checks, 2);
    expect(find.text('Server available'), findsOneWidget);
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

  testWidgets(
    'Messages prompts for an obscured password and authenticates callsign',
    (tester) async {
      final tokens = FakeAuthTokenStore();
      await pumpApp(tester, FakeCallsignStore('EA3GNU'), tokenStore: tokens);
      await tester.tap(find.byKey(const Key('messagesTile')));
      await tester.pumpAndSettle();
      expect(find.text('Password for EA3GNU'), findsOneWidget);
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('serverPasswordField')))
            .obscureText,
        isTrue,
      );
      await tester.enterText(
        find.byKey(const Key('serverPasswordField')),
        'secret',
      );
      await tester.tap(find.byKey(const Key('connectButton')));
      await tester.pumpAndSettle();
      expect(tokens.tokens['EA3GNU'], 'new-token');
      expect(find.text('Unable to load conversations'), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('Connected to server'), findsOneWidget);
    },
  );

  testWidgets(
    'incorrect password stays available, clears field, and permits retry',
    (tester) async {
      final auth = FakeAuthClient()
        ..loginResult = const LoginError(LoginFailure.incorrectPassword);
      await pumpApp(tester, FakeCallsignStore('EA3GNU'), authClient: auth);
      await tester.tap(find.byKey(const Key('messagesTile')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('serverPasswordField')),
        'wrong',
      );
      await tester.tap(find.byKey(const Key('connectButton')));
      await tester.pumpAndSettle();
      expect(find.text('Incorrect password'), findsOneWidget);
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('serverPasswordField')))
            .controller!
            .text,
        isEmpty,
      );
      expect(find.text('Server available'), findsOneWidget);
      auth.loginResult = const LoginSuccess('retry-token');
      await tester.enterText(
        find.byKey(const Key('serverPasswordField')),
        'right',
      );
      await tester.tap(find.byKey(const Key('connectButton')));
      await tester.pumpAndSettle();
      expect(find.text('Unable to load conversations'), findsOneWidget);
    },
  );

  testWidgets(
    'valid scoped token skips prompt, while invalid token is cleared',
    (tester) async {
      final auth = FakeAuthClient();
      final tokens = FakeAuthTokenStore()..tokens['EA3GNU'] = 'stored';
      await pumpApp(
        tester,
        FakeCallsignStore('EA3GNU'),
        authClient: auth,
        tokenStore: tokens,
      );
      await tester.tap(find.byKey(const Key('messagesTile')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('serverPasswordField')), findsNothing);
      expect(find.text('Unable to load conversations'), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      auth.validationResult = AuthValidationResult.invalid;
      await tester.tap(find.byKey(const Key('messagesTile')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('serverPasswordField')), findsOneWidget);
      expect(tokens.tokens['EA3GNU'], isNull);
    },
  );

  testWidgets('unavailable server does not prompt for password', (tester) async {
    await pumpApp(
      tester,
      FakeCallsignStore('EA3GNU'),
      statusClient: FakeServerStatusClient(result: false),
    );
    await tester.tap(find.byKey(const Key('messagesTile')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('serverPasswordField')), findsNothing);
    expect(find.text('Server unavailable'), findsWidgets);
  });

  testWidgets('token for another callsign is not reused', (tester) async {
    final tokens = FakeAuthTokenStore()..tokens['EA3GNU'] = 'other-token';
    await pumpApp(tester, FakeCallsignStore('N0CALL'), tokenStore: tokens);
    await tester.tap(find.byKey(const Key('messagesTile')));
    await tester.pumpAndSettle();
    expect(find.text('Password for N0CALL'), findsOneWidget);
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
