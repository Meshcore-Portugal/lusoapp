import 'package:flutter_test/flutter_test.dart';
import 'package:lusoapp/services/widget_service.dart';

void main() {
  group('WidgetAction.fromUri', () {
    test('parses all known schemes', () {
      expect(
        WidgetAction.fromUri(Uri.parse('meshcore-widget://open')),
        WidgetAction.open,
      );
      expect(
        WidgetAction.fromUri(Uri.parse('meshcore-widget://action/advert')),
        WidgetAction.sendAdvert,
      );
      expect(
        WidgetAction.fromUri(Uri.parse('meshcore-widget://action/sos')),
        WidgetAction.sendEmergency,
      );
      expect(
        WidgetAction.fromUri(Uri.parse('meshcore-widget://nav/channels')),
        WidgetAction.openChats,
      );
      expect(
        WidgetAction.fromUri(Uri.parse('meshcore-widget://nav/map')),
        WidgetAction.openMap,
      );
      expect(
        WidgetAction.fromUri(Uri.parse('meshcore-widget://nav/connect')),
        WidgetAction.openConnect,
      );
      expect(
        WidgetAction.fromUri(Uri.parse('meshcore-widget://nav/apps/plan333')),
        WidgetAction.openPlan333,
      );
      expect(
        WidgetAction.fromUri(
          Uri.parse('meshcore-widget://nav/apps/telemetry'),
        ),
        WidgetAction.openTelemetry,
      );
    });

    test('returns null on unknown scheme or path', () {
      expect(WidgetAction.fromUri(Uri.parse('https://x.test')), isNull);
      expect(
        WidgetAction.fromUri(Uri.parse('meshcore-widget://unknown')),
        isNull,
      );
    });
  });
}
