/// Pure-Dart stub implementation of [GeolocatorPlatform] for Windows.
///
/// The real [geolocator_windows] package requires downloading the NuGet
/// package Microsoft.Windows.CppWinRT via CMake, which fails in offline or
/// restricted environments.  Since the map screen only calls Geolocator
/// inside a [defaultTargetPlatform == TargetPlatform.android] (or iOS) guard,
/// this stub is never invoked at runtime.  It satisfies the Dart/Flutter
/// plugin registration without any native code.
library;

import 'dart:async';

import 'package:geolocator_platform_interface/geolocator_platform_interface.dart';

class GeolocatorWindows extends GeolocatorPlatform {
  /// Registers this class as the default platform implementation on Windows.
  static void registerWith() {
    GeolocatorPlatform.instance = GeolocatorWindows();
  }

  @override
  Future<LocationPermission> checkPermission() async =>
      LocationPermission.denied;

  @override
  Future<LocationPermission> requestPermission() async =>
      LocationPermission.denied;

  @override
  Future<bool> isLocationServiceEnabled() async => false;

  @override
  Future<Position?> getLastKnownPosition({
    bool forceLocationManager = false,
  }) async => null;

  @override
  Future<Position> getCurrentPosition({LocationSettings? locationSettings}) =>
      Future.error(
        'Geolocator is not supported on Windows in this build.',
        StackTrace.current,
      );

  @override
  Stream<Position> getPositionStream({LocationSettings? locationSettings}) =>
      Stream.error(
        'Geolocator is not supported on Windows in this build.',
        StackTrace.current,
      );

  @override
  Stream<ServiceStatus> getServiceStatusStream() =>
      Stream.value(ServiceStatus.disabled);

  @override
  Future<bool> openAppSettings() async => false;

  @override
  Future<bool> openLocationSettings() async => false;
}
