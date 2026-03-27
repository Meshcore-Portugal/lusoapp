/// Pure-Dart stub implementation of [PermissionHandlerPlatform] for Windows.
///
/// The real [permission_handler_windows] package requires downloading the
/// NuGet package Microsoft.Windows.CppWinRT via CMake, which fails in offline
/// or restricted environments.  Since this app only requests Bluetooth
/// permissions inside [Platform.isAndroid] guards, the Windows implementation
/// is never called at runtime.  This stub satisfies the Dart/Flutter plugin
/// registration without any native code.
library permission_handler_windows;

import 'package:permission_handler_platform_interface/permission_handler_platform_interface.dart';

class PermissionHandlerWindows extends PermissionHandlerPlatform {
  /// Registers this class as the default platform implementation on Windows.
  static void registerWith() {
    PermissionHandlerPlatform.instance = PermissionHandlerWindows();
  }

  @override
  Future<PermissionStatus> checkPermissionStatus(Permission permission) async =>
      PermissionStatus.granted;

  @override
  Future<ServiceStatus> checkServiceStatus(Permission permission) async =>
      ServiceStatus.enabled;

  @override
  Future<Map<Permission, PermissionStatus>> requestPermissions(
    List<Permission> permissions,
  ) async => {for (final p in permissions) p: PermissionStatus.granted};

  @override
  Future<bool> shouldShowRequestPermissionRationale(
    Permission permission,
  ) async => false;

  @override
  Future<bool> openAppSettings() async => true;
}
