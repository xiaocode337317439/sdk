// Copyright (c) 2017, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:convert' show utf8;

import 'package:http/http.dart';
import 'package:http/testing.dart';
import 'package:telemetry/crash_reporting.dart';
import 'package:test/test.dart';
import 'package:usage/usage.dart';

void main() {
  group('crash_reporting', () {
    MockClient mockClient;

    Request request;

    setUp(() {
      mockClient = new MockClient((Request r) async {
        request = r;
        return new Response('crash-report-001', 200);
      });
    });

    test('CrashReportSender', () async {
      EnablementCallback shouldSend = () {
        return true;
      };

      AnalyticsMock analytics = new AnalyticsMock()..enabled = true;
      CrashReportSender sender = new CrashReportSender(
          analytics.trackingId, shouldSend,
          httpClient: mockClient);

      await sender.sendReport('test-error', stackTrace: StackTrace.current);

      String body = utf8.decode(request.bodyBytes);
      expect(body, contains('String')); // error.runtimeType
      expect(body, contains('test-error'));
    });
  });
}