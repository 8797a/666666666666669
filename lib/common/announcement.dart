import 'dart:async';

import 'package:dio/dio.dart';
import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/plugins/app.dart';
import 'package:fl_clash/state.dart';
import 'package:fl_clash/widgets/dialog.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';

const announcementApiKey =
    'dc96b35d35d8a1cb9831b44db09da9b733a806dba8e53b173d10f8ea16298ccb';

class AnnouncementService {
  Timer? _repeatTimer;
  bool _isCheckingRepeats = false;
  final Set<String> _showingAnnouncements = {};

  Future<void> showForTrigger(String trigger) async {
    try {
      final announcements = await _fetchAnnouncements();
      for (final announcement in announcements) {
        if (_triggerOf(announcement) == trigger) {
          await _showIfDue(announcement);
        }
      }
    } catch (error) {
      commonPrint.log('show announcements failed: $error');
    }
  }

  void startRepeating() {
    _repeatTimer ??= Timer.periodic(
      const Duration(minutes: 1),
      (_) => _checkRepeats(),
    );
  }

  void dispose() {
    _repeatTimer?.cancel();
    _repeatTimer = null;
  }

  Future<List<Map<String, dynamic>>> _fetchAnnouncements() async {
    try {
      final response = await request.dio
          .get<Map<String, dynamic>>(
          'https://announcement-center-production.up.railway.app/api.php',
          queryParameters: {'appId': 'flclash'},
          options: Options(
            responseType: ResponseType.json,
            headers: {'X-API-Key': announcementApiKey},
          ),
        )
          .timeout(const Duration(seconds: 10));
      final rawAnnouncements = response.data?['announcements'];
      if (rawAnnouncements is! List) return [];
      return rawAnnouncements.whereType<Map>().map((item) {
        return item.map((key, value) => MapEntry(key.toString(), value));
      }).where((item) {
        return item['title'] is String && item['content'] is String;
      }).toList();
    } catch (error) {
      commonPrint.log('load announcements failed: $error');
      return [];
    }
  }

  Future<void> _checkRepeats() async {
    if (_isCheckingRepeats) return;
    _isCheckingRepeats = true;
    try {
      final announcements = await _fetchAnnouncements();
      for (final announcement in announcements) {
        if (_repeatIntervalOf(announcement) > 0) {
          await _showIfDue(announcement, onlyIfPreviouslyShown: true);
        }
      }
    } catch (error) {
      commonPrint.log('repeat announcements failed: $error');
    } finally {
      _isCheckingRepeats = false;
    }
  }

  Future<void> _showIfDue(
    Map<String, dynamic> announcement, {
    bool onlyIfPreviouslyShown = false,
  }) async {
    final id = _idOf(announcement);
    if (_showingAnnouncements.contains(id)) return;

    final repeatInterval = _repeatIntervalOf(announcement);
    final preferences = await SharedPreferences.getInstance();
    final lastShownAt = preferences.getInt(_lastShownKey(id)) ?? 0;
    if (onlyIfPreviouslyShown && lastShownAt == 0) return;
    if (repeatInterval > 0 && lastShownAt > 0) {
      final elapsed = DateTime.now().millisecondsSinceEpoch - lastShownAt;
      if (elapsed < Duration(minutes: repeatInterval).inMilliseconds) return;
    }

    _showingAnnouncements.add(id);
    try {
      await preferences.setInt(
        _lastShownKey(id),
        DateTime.now().millisecondsSinceEpoch,
      );
      await _present(announcement, id);
    } catch (error) {
      commonPrint.log('present announcement failed: $error');
    } finally {
      _showingAnnouncements.remove(id);
    }
  }

  Future<void> _present(
    Map<String, dynamic> announcement,
    String id,
  ) async {
    final title = announcement['title'] as String;
    final summary = announcement['summary'] is String
        ? announcement['summary'] as String
        : '';
    final content = announcement['content'] as String;
    final autoCloseSeconds = _autoCloseSecondsOf(announcement);

    if (system.isAndroid) {
      await app?.showAnnouncementNotification(
        id: id,
        title: title,
        summary: summary,
        content: content,
        autoCloseSeconds: autoCloseSeconds,
      );
      return;
    }

    var restoreAlwaysOnTop = false;
    if (system.isWindows) {
      final wasAlwaysOnTop = await windowManager.isAlwaysOnTop();
      await window?.show();
      if (!wasAlwaysOnTop) {
        await windowManager.setAlwaysOnTop(true);
        restoreAlwaysOnTop = true;
      }
      await windowManager.focus();
    }

    try {
      await globalState.showCommonDialog<void>(
        dismissible: autoCloseSeconds == 0,
        child: _AnnouncementDialog(
          title: title,
          summary: summary,
          content: content,
          autoCloseSeconds: autoCloseSeconds,
        ),
      );
    } finally {
      if (restoreAlwaysOnTop) {
        await windowManager.setAlwaysOnTop(false);
      }
    }
  }

  String _triggerOf(Map<String, dynamic> item) =>
      (item['displayTrigger'] ?? 'startup') == 'connect' ? 'connect' : 'startup';

  int _repeatIntervalOf(Map<String, dynamic> item) {
    final value = item['repeatIntervalMinutes'];
    return value is num ? value.toInt().clamp(0, 10080).toInt() : 0;
  }

  int _autoCloseSecondsOf(Map<String, dynamic> item) {
    final value = item['autoCloseSeconds'];
    return value is num ? value.toInt().clamp(0, 3600).toInt() : 0;
  }

  String _idOf(Map<String, dynamic> item) {
    final id = item['id'];
    return id is String && id.isNotEmpty ? id : (item['title'] as String);
  }

  String _lastShownKey(String id) => 'announcement_last_shown_$id';
}

class _AnnouncementDialog extends StatefulWidget {
  final String title;
  final String summary;
  final String content;
  final int autoCloseSeconds;

  const _AnnouncementDialog({
    required this.title,
    required this.summary,
    required this.content,
    required this.autoCloseSeconds,
  });

  @override
  State<_AnnouncementDialog> createState() => _AnnouncementDialogState();
}

class _AnnouncementDialogState extends State<_AnnouncementDialog> {
  Timer? _autoCloseTimer;

  @override
  void initState() {
    super.initState();
    if (widget.autoCloseSeconds > 0) {
      _autoCloseTimer = Timer(Duration(seconds: widget.autoCloseSeconds), () {
        if (mounted) Navigator.of(context).pop();
      });
    }
  }

  @override
  void dispose() {
    _autoCloseTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: widget.autoCloseSeconds == 0,
      child: CommonDialog(
        title: widget.title,
        actions: widget.autoCloseSeconds == 0
            ? [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(appLocalizations.confirm),
                ),
              ]
            : null,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (widget.summary.isNotEmpty) ...[
              Text(
                widget.summary,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 8),
            ],
            Text(widget.content),
          ],
        ),
      ),
    );
  }
}

final announcementService = AnnouncementService();
