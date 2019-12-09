// Copyright (c) 2014, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http_multi_server/http_multi_server.dart';
import 'package:http_multi_server/src/utils.dart';
import 'package:test/test.dart';

void main() {
  group('with multiple HttpServers', () {
    var multiServer;
    HttpServer subServer1;
    HttpServer subServer2;
    HttpServer subServer3;
    setUp(() {
      return Future.wait([
        HttpServer.bind('localhost', 0).then((server) => subServer1 = server),
        HttpServer.bind('localhost', 0).then((server) => subServer2 = server),
        HttpServer.bind('localhost', 0).then((server) => subServer3 = server)
      ]).then((servers) => multiServer = HttpMultiServer(servers));
    });

    tearDown(() => multiServer.close());

    test('listen listens to all servers', () {
      multiServer.listen((request) {
        request.response.write('got request');
        request.response.close();
      });

      expect(_read(subServer1), completion(equals('got request')));
      expect(_read(subServer2), completion(equals('got request')));
      expect(_read(subServer3), completion(equals('got request')));
    });

    test('serverHeader= sets the value for all servers', () {
      multiServer.serverHeader = 'http_multi_server test';

      multiServer.listen((request) {
        request.response.write('got request');
        request.response.close();
      });

      expect(
          _get(subServer1).then((response) {
            expect(
                response.headers['server'], equals('http_multi_server test'));
          }),
          completes);

      expect(
          _get(subServer2).then((response) {
            expect(
                response.headers['server'], equals('http_multi_server test'));
          }),
          completes);

      expect(
          _get(subServer3).then((response) {
            expect(
                response.headers['server'], equals('http_multi_server test'));
          }),
          completes);
    });

    test('autoCompress= sets the value for all servers', () {
      multiServer.autoCompress = true;

      multiServer.listen((request) {
        request.response.write('got request');
        request.response.close();
      });

      expect(
          _get(subServer1).then((response) {
            expect(response.headers['content-encoding'], equals('gzip'));
          }),
          completes);

      expect(
          _get(subServer2).then((response) {
            expect(response.headers['content-encoding'], equals('gzip'));
          }),
          completes);

      expect(
          _get(subServer3).then((response) {
            expect(response.headers['content-encoding'], equals('gzip'));
          }),
          completes);
    });

    test('headers.set sets the value for all servers', () {
      multiServer.defaultResponseHeaders
          .set('server', 'http_multi_server test');

      multiServer.listen((request) {
        request.response.write('got request');
        request.response.close();
      });

      expect(
          _get(subServer1).then((response) {
            expect(
                response.headers['server'], equals('http_multi_server test'));
          }),
          completes);

      expect(
          _get(subServer2).then((response) {
            expect(
                response.headers['server'], equals('http_multi_server test'));
          }),
          completes);

      expect(
          _get(subServer3).then((response) {
            expect(
                response.headers['server'], equals('http_multi_server test'));
          }),
          completes);
    });

    test('connectionsInfo sums the values for all servers', () {
      var pendingRequests = 0;
      var awaitingResponseCompleter = Completer();
      var sendResponseCompleter = Completer();
      multiServer.listen((request) {
        sendResponseCompleter.future.then((_) {
          request.response.write('got request');
          request.response.close();
        });

        pendingRequests++;
        if (pendingRequests == 2) awaitingResponseCompleter.complete();
      });

      // Queue up some requests, then wait on [awaitingResponseCompleter] to
      // make sure they're in-flight before we check [connectionsInfo].
      expect(_get(subServer1), completes);
      expect(_get(subServer2), completes);

      return awaitingResponseCompleter.future.then((_) {
        var info = multiServer.connectionsInfo();
        expect(info.total, equals(2));
        expect(info.active, equals(2));
        expect(info.idle, equals(0));
        expect(info.closing, equals(0));

        sendResponseCompleter.complete();
      });
    });
  });

  group('HttpMultiServer.loopback', () {
    var server;
    setUp(() {
      return HttpMultiServer.loopback(0).then((s) => server = s);
    });

    tearDown(() => server.close());

    test('listens on all localhost interfaces', () async {
      server.listen((request) {
        request.response.write('got request');
        request.response.close();
      });

      if (await supportsIPv4) {
        expect(http.read('http://127.0.0.1:${server.port}/'),
            completion(equals('got request')));
      }

      if (await supportsIPv6) {
        expect(http.read('http://[::1]:${server.port}/'),
            completion(equals('got request')));
      }
    });
  });

  group('HttpMultiServer.bind', () {
    test("listens on all localhost interfaces for 'localhost'", () async {
      final server = await HttpMultiServer.bind('localhost', 0);
      server.listen((request) {
        request.response.write('got request');
        request.response.close();
      });

      if (await supportsIPv4) {
        expect(http.read('http://127.0.0.1:${server.port}/'),
            completion(equals('got request')));
      }

      if (await supportsIPv6) {
        expect(http.read('http://[::1]:${server.port}/'),
            completion(equals('got request')));
      }
    });

    test("listens on all localhost interfaces for 'any'", () async {
      final server = await HttpMultiServer.bind('any', 0);
      server.listen((request) {
        request.response.write('got request');
        request.response.close();
      });

      if (await supportsIPv4) {
        expect(http.read('http://127.0.0.1:${server.port}/'),
            completion(equals('got request')));
      }

      if (await supportsIPv6) {
        expect(http.read('http://[::1]:${server.port}/'),
            completion(equals('got request')));
      }
    });

    test('listens on specified hostname', () async {
      final server = await HttpMultiServer.bind(InternetAddress.anyIPv4, 0);
      server.listen((request) {
        request.response.write('got request');
        request.response.close();
      });

      if (await supportsIPv4) {
        expect(http.read('http://127.0.0.1:${server.port}/'),
            completion(equals('got request')));
      }

      if (await supportsIPv6) {
        expect(http.read('http://[::1]:${server.port}/'),
            throwsA(isA<SocketException>()));
      }
    });
  });
}

/// Makes a GET request to the root of [server] and returns the response.
Future<http.Response> _get(HttpServer server) => http.get(_urlFor(server));

/// Makes a GET request to the root of [server] and returns the response body.
Future<String> _read(HttpServer server) => http.read(_urlFor(server));

/// Returns the URL for the root of [server].
String _urlFor(HttpServer server) =>
    'http://${server.address.host}:${server.port}/';
