import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ganj/core/net/api_client.dart';
import 'package:ganj/features/translate/translator.dart';

import '../support/fake_adapter.dart';

void main() {
  test('beyts asked for together go to Google in one request, answers come back in order', () async {
    final adapter = FakeAdapter({
      '/translate_a/t': jsonEncode(['one\ntwo', 'three\nfour']),
    });
    final t = GoogleWebTranslator(dio: createDio(adapter: adapter));
    final results = await Future.wait([t.translate('یک\nدو', 'en'), t.translate('سه\nچهار', 'en')]);
    expect(results, ['one\ntwo', 'three\nfour']);
    expect(adapter.requests, hasLength(1));
    final u = adapter.requests.single;
    expect(u.host, 'clients5.google.com');
    expect(u.queryParametersAll['q'], ['یک\nدو', 'سه\nچهار']);
    expect(u.queryParameters['sl'], 'fa');
    expect(u.queryParameters['tl'], 'en');
  });

  test('the same beyt is not asked twice', () async {
    final adapter = FakeAdapter({
      '/translate_a/t': jsonEncode(['hello']),
    });
    final t = GoogleWebTranslator(dio: createDio(adapter: adapter));
    expect(await t.translate('سلام', 'en'), 'hello');
    expect(await t.translate('سلام', 'en'), 'hello');
    expect(adapter.requests, hasLength(1));
  });

  test('if the first address is blocked, the second one is tried', () async {
    final adapter = FakeAdapter({
      '/translate_a/single': jsonEncode([
        [
          ['hello ', 'سلام'],
          ['world', 'دنیا'],
        ],
        null,
        'fa',
      ]),
    });
    final t = GoogleWebTranslator(dio: createDio(adapter: adapter));
    expect(await t.translate('سلام دنیا', 'en'), 'hello world');
    expect(adapter.requests.map((u) => u.host), ['clients5.google.com', 'translate.googleapis.com']);
  });

  test('with no answer at all it fails, so the reader is offered the browser', () async {
    final t = GoogleWebTranslator(dio: createDio(adapter: FakeAdapter({})..offline = true));
    expect(t.translate('سلام', 'en'), throwsA(anything));
  });

  test('it translates inside the app and needs no model download', () {
    final t = GoogleWebTranslator(dio: createDio(adapter: FakeAdapter({})));
    expect(t.inApp, isTrue);
    expect(t.needsModel, isFalse);
  });
}
