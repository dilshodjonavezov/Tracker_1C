import 'dart:ui';

import 'package:flutter/widgets.dart';
import 'package:workmanager/workmanager.dart';

import 'services/location_diagnostic_service.dart';
import 'services/server_service.dart';

const locationDiagnosticTaskName = 'location_diagnostic_task';
const locationDiagnosticUniqueName = 'location_diagnostic_unique_task';

@pragma('vm:entry-point')
void diagnosticCallbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    WidgetsFlutterBinding.ensureInitialized();
    DartPluginRegistrant.ensureInitialized();

    await ServerService().flushPendingLocations(force: true);
    await LocationDiagnosticService().checkAndReport();
    return true;
  });
}
