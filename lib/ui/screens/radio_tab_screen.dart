import 'package:flutter/material.dart';

import 'plan333_screen.dart';
import 'radio_config_screen.dart';

/// Wraps RadioConfigScreen and Plan333Screen in a two-tab layout so that
/// the Plano 3-3-3 feature is accessible from the Rádio bottom-nav item
/// without occupying its own slot in the navigation bar.
class RadioTabScreen extends StatelessWidget {
  const RadioTabScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Column(
        children: [
          const TabBar(
            tabs: [
              Tab(
                icon: Icon(Icons.settings_input_antenna_outlined),
                text: 'Rádio',
              ),
              Tab(icon: Icon(Icons.crisis_alert_outlined), text: 'Plano 3-3-3'),
            ],
          ),
          const Expanded(
            child: TabBarView(children: [RadioConfigScreen(), Plan333Screen()]),
          ),
        ],
      ),
    );
  }
}
