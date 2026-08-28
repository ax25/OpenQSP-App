import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:openqsp_app/features/auth/data/auth_client.dart';

void main() {
  final baseUri = Uri.parse('http://server.test:8000');

  test('successful login parses token and sends expected body', () async {
    final client = InternetAuthClient(
      baseUri: baseUri,
      httpClient: MockClient((request) async {
        expect(request.url.path, '/api/v1/auth/login');
        expect(request.body, '{"callsign":"EA3GNU","password":"secret"}');
        return http.Response(
          '{"access_token":"abc","token_type":"bearer",'
          '"user":{"callsign":"EA3GNU"}}',
          200,
        );
      }),
    );
    final result = await client.login(callsign: 'EA3GNU', password: 'secret');
    expect((result as LoginSuccess).accessToken, 'abc');
  });

  test('401 maps to incorrect password', () async {
    final client = InternetAuthClient(
      baseUri: baseUri,
      httpClient: MockClient(
        (_) async => http.Response('{"code":"invalid_credentials"}', 401),
      ),
    );
    final result = await client.login(callsign: 'EA3GNU', password: 'bad');
    expect(
      (result as LoginError).failure,
      LoginFailure.incorrectPassword,
    );
  });

  test('network exception maps to network failure', () async {
    final client = InternetAuthClient(
      baseUri: baseUri,
      httpClient: MockClient(
        (_) async => throw http.ClientException('offline'),
      ),
    );
    final result = await client.login(callsign: 'EA3GNU', password: 'secret');
    expect((result as LoginError).failure, LoginFailure.network);
  });

  test('malformed successful response is a failure', () async {
    final client = InternetAuthClient(
      baseUri: baseUri,
      httpClient: MockClient((_) async => http.Response('{}', 200)),
    );
    final result = await client.login(callsign: 'EA3GNU', password: 'secret');
    expect((result as LoginError).failure, LoginFailure.malformedResponse);
  });

  test('/me 200 with matching callsign validates token', () async {
    var status = 200;
    final client = InternetAuthClient(
      baseUri: baseUri,
      httpClient: MockClient((request) async {
        expect(request.url.path, '/api/v1/me');
        expect(request.headers['authorization'], 'Bearer abc');
        return http.Response('{"user":{"callsign":" ea3gnu "}}', status);
      }),
    );
    expect(
      await client.validateToken(token: 'abc', callsign: 'EA3GNU'),
      AuthValidationResult.valid,
    );
    status = 401;
    expect(
      await client.validateToken(token: 'abc', callsign: 'EA3GNU'),
      AuthValidationResult.invalid,
    );
  });

  test('/me 200 with different callsign invalidates token', () async {
    final client = InternetAuthClient(
      baseUri: baseUri,
      httpClient: MockClient(
        (_) async => http.Response('{"user":{"callsign":"N0CALL"}}', 200),
      ),
    );

    expect(
      await client.validateToken(token: 'abc', callsign: 'EA3GNU'),
      AuthValidationResult.invalid,
    );
  });
}
