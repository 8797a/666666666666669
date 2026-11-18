import 'dart:async';
import 'dart:io';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/models/models.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class App {
  static App? _instance;
  late MethodChannel methodChannel;
  Function()? onExit;
  Future<void> Function(Map<String, dynamic>)? _onAnnouncementTapped;
  Map<String, dynamic>? _pendingAnnouncementTap;

  App._internal() {
    methodChannel = const MethodChannel('$packageName/app');
    methodChannel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'exit':
          if (onExit != null) {
            await onExit!();
          }
          return;
        case 'announcementTapped':
          final payload = _announcementMap(call.arguments);
          if (payload == null) return;
          final handler = _onAnnouncementTapped;
          if (handler == null) {
            _pendingAnnouncementTap = payload;
          } else {
            await _deliverAnnouncementTap(payload, handler);
          }
          return;
        default:
          throw MissingPluginException();
      }
    });
  }

  factory App() {
    _instance ??= App._internal();
    return _instance!;
  }

  set onAnnouncementTapped(
    Future<void> Function(Map<String, dynamic>)? handler,
  ) {
    _onAnnouncementTapped = handler;
    final pending = _pendingAnnouncementTap;
    if (handler != null && pending != null) {
      _pendingAnnouncementTap = null;
      unawaited(_deliverAnnouncementTap(pending, handler));
    }
  }

  Future<Map<String, dynamic>?> consumePendingAnnouncement() async {
    final result = await methodChannel.invokeMethod<Object?>(
      'consumePendingAnnouncement',
    );
    return _announcementMap(result);
  }

  Map<String, dynamic>? _announcementMap(Object? value) {
    if (value is! Map) return null;
    return value.map((key, item) => MapEntry(key.toString(), item));
  }

  Future<void> _deliverAnnouncementTap(
    Map<String, dynamic> payload,
    Future<void> Function(Map<String, dynamic>) handler,
  ) async {
    try {
      await handler(payload);
    } finally {
      try {
        await consumePendingAnnouncement();
      } catch (_) {}
    }
  }

  Future<bool?> moveTaskToBack() async {
    return await methodChannel.invokeMethod<bool>('moveTaskToBack');
  }

  Future<List<Package>> getPackages() async {
    final packagesString = await methodChannel.invokeMethod<String>(
      'getPackages',
    );
    List<dynamic> packagesRaw =
        (await packagesString?.commonToJSON<List<dynamic>>()) ?? [];
    return packagesRaw.map((e) => Package.fromJson(e)).toSet().toList();
  }

  Future<List<String>> getChinaPackageNames() async {
    final packageNamesString = await methodChannel.invokeMethod<String>(
      'getChinaPackageNames',
    );
    List<dynamic> packageNamesRaw =
        await packageNamesString?.commonToJSON<List<dynamic>>() ?? [];
    return packageNamesRaw.map((e) => e.toString()).toList();
  }

  Future<bool?> requestNotificationsPermission() async {
    return await methodChannel.invokeMethod<bool>(
      'requestNotificationsPermission',
    );
  }

  Future<bool> showAnnouncementNotification({
    required String id,
    required String title,
    required String summary,
    required String content,
    required int autoCloseSeconds,
  }) async {
    final hasPermission = await requestNotificationsPermission();
    if (hasPermission != true) return false;
    return await methodChannel.invokeMethod<bool>(
          'showAnnouncementNotification',
          {
            'id': id,
            'title': title,
            'summary': summary,
            'content': content,
            'autoCloseSeconds': autoCloseSeconds,
          },
        ) ??
        false;
  }

  Future<bool> openFile(String path) async {
    return await methodChannel.invokeMethod<bool>('openFile', {'path': path}) ??
        false;
  }

  Future<ImageProvider?> getPackageIcon(String packageName) async {
    final path = await methodChannel.invokeMethod<String>('getPackageIcon', {
      'packageName': packageName,
    });
    if (path == null) {
      return null;
    }
    return FileImage(File(path));
  }

  Future<bool?> tip(String? message) async {
    return await methodChannel.invokeMethod<bool>('tip', {
      'message': '$message',
    });
  }

  Future<bool?> initShortcuts() async {
    return await methodChannel.invokeMethod<bool>(
      'initShortcuts',
      appLocalizations.toggle,
    );
  }

  Future<bool?> updateExcludeFromRecents(bool value) async {
    return await methodChannel.invokeMethod<bool>('updateExcludeFromRecents', {
      'value': value,
    });
  }
}

final app = system.isAndroid ? App() : null;
