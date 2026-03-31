import 'package:flutter/material.dart';

import 'plan333_screen.dart';

/// Radio tab — hosts MeshCore apps.
///
/// Currently shows Plan 3-3-3 directly. As more apps are added this will
/// become a launcher list/grid.
class RadioTabScreen extends StatelessWidget {
  const RadioTabScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Plan333Screen();
  }
}
