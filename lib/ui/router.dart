import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../config/feature_toggles.dart';

import 'screens/apps_screen.dart';
import 'screens/connect_screen.dart';
import 'screens/home_screen.dart';
import 'screens/channels_list_screen.dart';
import 'screens/channel_chat_screen.dart';
import 'screens/map_screen.dart';
import 'apps/plan333/plan333_screen.dart';
import 'screens/private_chat_screen.dart';
import 'screens/radio_settings_screen.dart';
import 'screens/contacts_screen.dart';
import 'screens/room_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/event_program_screen.dart';
import 'apps/telemetry/telemetry_screen.dart';
import 'screens/discover_contacts_screen.dart';
import 'apps/noise_floor/noise_floor_screen.dart';
import 'apps/rx_log/rx_log_screen.dart';
import 'apps/topology/topology_screen.dart';
import 'apps/data_export/data_export_screen.dart';
import 'screens/repeater_screen.dart';

final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/connect',
    // Widget click intents arrive as `meshcore-widget://...` URIs and would
    // otherwise hit GoRouter's "no route" page. The actual action is handled
    // by `WidgetService.registerClickHandlers()` listening on the
    // `HomeWidget.widgetClicked` stream, so we only need to neutralise the
    // navigation side-effect here.
    redirect: (context, state) {
      final loc = state.matchedLocation;
      if (loc.startsWith('meshcore-widget') ||
          state.uri.scheme == 'meshcore-widget') {
        // Land on the channels list \u2014 a stable, always-available shell
        // route. The widget action handler in main.dart will then re-route
        // to the right destination (chats / map / connect / etc.).
        return '/channels';
      }
      return null;
    },
    routes: [
      GoRoute(
        path: '/connect',
        builder: (context, state) => const ConnectScreen(),
      ),
      ShellRoute(
        builder: (context, state, child) => HomeScreen(child: child),
        routes: [
          GoRoute(
            path: '/channels',
            builder: (context, state) => const ChannelsListScreen(),
          ),
          GoRoute(
            path: '/channels/:index',
            builder: (context, state) {
              final index = int.parse(state.pathParameters['index']!);
              return ChannelChatScreen(channelIndex: index);
            },
          ),
          GoRoute(
            path: '/contacts',
            builder: (context, state) => const ContactsScreen(),
          ),
          GoRoute(
            path: '/discover',
            builder: (context, state) => const DiscoverContactsScreen(),
          ),
          GoRoute(path: '/map', builder: (context, state) => const MapScreen()),
          GoRoute(
            path: '/apps',
            builder: (context, state) => const AppsScreen(),
          ),
          if (FeatureToggles.appPlan333)
            GoRoute(
              path: '/apps/plan333',
              builder: (context, state) => const Plan333Screen(),
            ),
          if (FeatureToggles.appTelemetry)
            GoRoute(
              path: '/apps/telemetry',
              builder: (context, state) => const TelemetryScreen(),
            ),
          if (FeatureToggles.appRxLog)
            GoRoute(
              path: '/apps/rxlog',
              builder: (context, state) => const RxLogScreen(),
            ),
          if (FeatureToggles.appNoiseFloor)
            GoRoute(
              path: '/apps/noisefloor',
              builder: (context, state) => const NoiseFloorScreen(),
            ),
          if (FeatureToggles.appTopology)
            GoRoute(
              path: '/apps/topology',
              builder: (context, state) => const TopologyScreen(),
            ),
          if (FeatureToggles.appDataExport)
            GoRoute(
              path: '/apps/dataexport',
              builder: (context, state) => const DataExportScreen(),
            ),
          if (FeatureToggles.appEvent)
            GoRoute(
              path: '/apps/event',
              builder: (context, state) => const EventProgramScreen(),
            ),
          GoRoute(
            path: '/chat/:keyHex',
            builder: (context, state) {
              final keyHex = state.pathParameters['keyHex']!;
              return PrivateChatScreen(contactKeyHex: keyHex);
            },
          ),
          GoRoute(
            path: '/room/:keyHex',
            builder: (context, state) {
              final keyHex = state.pathParameters['keyHex']!;
              return RoomScreen(contactKeyHex: keyHex);
            },
          ),
          GoRoute(
            path: '/repeater/:keyHex',
            builder: (context, state) {
              final keyHex = state.pathParameters['keyHex']!;
              return RepeaterScreen(contactKeyHex: keyHex);
            },
          ),
          GoRoute(
            path: '/settings',
            builder: (context, state) => const SettingsScreen(),
          ),
          GoRoute(
            path: '/settings/radio',
            builder: (context, state) => const RadioSettingsScreen(),
          ),
        ],
      ),
    ],
  );
});
