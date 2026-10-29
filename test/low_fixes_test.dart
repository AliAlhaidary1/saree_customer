import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sareemart_customer/core/image_prefetch.dart';
import 'package:sareemart_customer/core/json_util.dart';

class _TestPrefetch extends ImagePrefetch {
  _TestPrefetch(this.dir);

  final Directory dir;

  @override
  Future<Directory?> thumbsDir() async => dir;
}

void main() {
  group('L-05 product routes', () {
    test('empty slug falls back to id', () {
      expect(J.productPath({'slug': '', 'id': 7}), '/product/7');
      expect(J.productPath({'slug': '   ', 'id': 7}), '/product/7');
      expect(J.productPath({'slug': null, 'product_id': 8}), '/product/8');
    });

    test('valid slug wins and missing identity uses product list', () {
      expect(
        J.productPath({'slug': 'blue-shirt', 'id': 7}),
        '/product/blue-shirt',
      );
      expect(J.productPath({'slug': '', 'id': 0}), '/products');
    });
  });

  group('L-03 image prefetch', () {
    test('SVG sources are skipped without a network request', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      var requests = 0;
      server.listen((req) async {
        requests++;
        req.response.headers.contentType = ContentType('image', 'svg+xml');
        req.response.write('<svg></svg>');
        await req.response.close();
      });
      final dir = await Directory.systemTemp.createTemp('low_l03');
      addTearDown(() async {
        try {
          await dir.delete(recursive: true);
        } catch (_) {}
      });

      final stored = await _TestPrefetch(dir).prefetch([
        'http://127.0.0.1:${server.port}/icon.svg',
      ], timeout: const Duration(seconds: 2));

      expect(stored, 0);
      expect(requests, 0);
    });
  });
}
