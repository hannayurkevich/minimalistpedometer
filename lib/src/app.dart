import 'package:flutter/material.dart';

import 'controller/pedometer_controller.dart';
import 'theme/palette.dart';
import 'theme/typography.dart';
import 'ui/page_dots.dart';
import 'ui/swipe_pager.dart';
import 'ui/stats/statistics_page.dart';
import 'ui/today/today_page.dart';

class MinimalistPedometerApp extends StatelessWidget {
  const MinimalistPedometerApp({super.key, required this.controller});

  final PedometerController controller;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Minimalist Pedometer',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        fontFamily: AppType.sansFamily,
        scaffoldBackgroundColor: Palette.white,
        splashFactory: NoSplash.splashFactory,
        highlightColor: Colors.transparent,
      ),
      home: HomePager(controller: controller),
    );
  }
}

/// Exactly two pages, switched by a horizontal swipe. Each page owns its
/// own background, so the dark Statistics screen is revealed naturally as
/// it slides in — no shared background that changes abruptly.
class HomePager extends StatefulWidget {
  const HomePager({super.key, required this.controller});

  final PedometerController controller;

  @override
  State<HomePager> createState() => _HomePagerState();
}

class _HomePagerState extends State<HomePager> {
  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Palette.white,
      child: SwipePager(
        overlay: (context, position) => Stack(
          children: [BottomDots(dots: PageDots(position: position))],
        ),
        children: [
          TodayPage(controller: widget.controller),
          StatisticsPage(controller: widget.controller),
        ],
      ),
    );
  }
}
