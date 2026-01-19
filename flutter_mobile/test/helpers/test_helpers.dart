import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Wraps a widget with MaterialApp and ProviderScope for widget testing
Widget createWidgetUnderTest(Widget child, {List<Override>? overrides}) {
  return ProviderScope(
    overrides: overrides ?? [],
    child: MaterialApp(
      home: Scaffold(body: child),
    ),
  );
}

/// Wraps a widget with MaterialApp and ProviderScope, plus a Navigator for route testing
Widget createNavigableWidgetUnderTest(Widget child, {List<Override>? overrides}) {
  return ProviderScope(
    overrides: overrides ?? [],
    child: MaterialApp(
      home: child,
    ),
  );
}
