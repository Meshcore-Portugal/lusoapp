import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'screens/apps_screen.dart';
import 'screens/connect_screen.dart';
import 'screens/home_screen.dart';
import 'screens/channels_list_screen.dart';
import 'screens/channel_chat_screen.dart';
import 'screens/map_screen.dart';
import 'screens/plan333_screen.dart';
import 'screens/private_chat_screen.dart';
import 'screens/radio_settings_screen.dart';
import 'screens/contacts_screen.dart';
import 'screens/room_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/telemetry_screen.dart';

final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/connect',
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
          GoRoute(path: '/map', builder: (context, state) => const MapScreen()),
          GoRoute(
            path: '/apps',
            builder: (context, state) => const AppsScreen(),
          ),
          GoRoute(
            path: '/apps/plan333',
            builder: (context, state) => const Plan333Screen(),
          ),
          GoRoute(
            path: '/apps/telemetry',
            builder: (context, state) => const TelemetryScreen(),
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
