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

  Future<void> showForTrigger(
    String trigger, {
    Set<String> excludedIds = const {},
  }) async {
    try {
      final announcements = await _fetchAnnouncements();
      for (final announcement in announcements) {
        if (_triggerOf(announcement) == trigger &&
            !excludedIds.contains(_idOf(announcement))) {
          await _showIfDue(announcement);
        }
      }
    } catch (error) {
      commonPrint.log('show announcements failed: $error');
    }
  }

  Future<void> showOpenedAnnouncement(Map<String, dynamic> announcement) async {
    if (announcement['title'] is! String ||
        announcement['content'] is! String) {
      return;
    }
    final id = _idOf(announcement);
    if (_showingAnnouncements.contains(id)) return;
    _showingAnnouncements.add(id);
    try {
      await _present(announcement, id, asNotification: false);
    } catch (error) {
      commonPrint.log('show opened announcement failed: $error');
    } finally {
      _showingAnnouncements.remove(id);
    }
  }

  void startRepeating() {
    _repeatTimer ??= Timer.periodic(
      const Duration(minutes: 3),
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
        final hasDailyWindow = announcement['dailyStartTime'] is String &&
            (announcement['dailyStartTime'] as String).isNotEmpty &&
            announcement['dailyEndTime'] is String &&
            (announcement['dailyEndTime'] as String).isNotEmpty;
        final isScheduledStartup =
            hasDailyWindow && _triggerOf(announcement) == 'startup';
        if (_repeatIntervalOf(announcement) > 0) {
          await _showIfDue(
            announcement,
            onlyIfPreviouslyShown: !isScheduledStartup,
            asNotification: true,
          );
        } else if (isScheduledStartup) {
          await _showIfDue(
            announcement,
            onlyOnce: true,
            asNotification: true,
          );
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
    bool onlyOnce = false,
    bool asNotification = false,
  }) async {
    final id = _idOf(announcement);
    if (_showingAnnouncements.contains(id)) return;

    final repeatInterval = _repeatIntervalOf(announcement);
    final preferences = await SharedPreferences.getInstance();
    final lastShownAt = preferences.getInt(_lastShownKey(id)) ?? 0;
    if (onlyIfPreviouslyShown && lastShownAt == 0) return;
    if (onlyOnce && lastShownAt > 0) return;
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
      await _present(announcement, id, asNotification: asNotification);
    } catch (error) {
      commonPrint.log('present announcement failed: $error');
    } finally {
      _showingAnnouncements.remove(id);
    }
  }

  Future<void> _present(
    Map<String, dynamic> announcement,
    String id, {
    required bool asNotification,
  }) async {
    final title = announcement['title'] as String;
    final summary = announcement['summary'] is String
        ? announcement['summary'] as String
        : '';
    final content = announcement['content'] as String;
    final autoCloseSeconds = _autoCloseSecondsOf(announcement);

    if (system.isAndroid && asNotification) {
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
  Timer? _countdownTimer;
  late int _remainingSeconds;

  @override
  void initState() {
    super.initState();
    _remainingSeconds = widget.autoCloseSeconds;
    if (widget.autoCloseSeconds > 0) {
      _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (!mounted) {
          timer.cancel();
          return;
        }
        if (_remainingSeconds <= 1) {
          timer.cancel();
          Navigator.of(context).pop();
          return;
        }
        setState(() => _remainingSeconds--);
      });
    }
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final isAutoClosing = widget.autoCloseSeconds > 0;
    final locale = Localizations.localeOf(context).languageCode;
    final countdownLabel = switch (locale) {
      'zh' => '$_remainingSeconds 秒后自动关闭',
      'ja' => '$_remainingSeconds 秒後に自動で閉じます',
      'ru' => 'Закроется автоматически через $_remainingSeconds с',
      _ => 'Closes automatically in $_remainingSeconds sec',
    };

    return PopScope(
      canPop: !isAutoClosing,
      child: Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        clipBehavior: Clip.antiAlias,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: colors.primaryContainer,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      alignment: Alignment.center,
                      child: Icon(
                        Icons.campaign_outlined,
                        color: colors.onPrimaryContainer,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          widget.title,
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Divider(height: 1, color: colors.outlineVariant),
                const SizedBox(height: 18),
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.sizeOf(context).height * 0.42,
                  ),
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (widget.summary.isNotEmpty) ...[
                          Text(
                            widget.summary,
                            style: theme.textTheme.titleSmall?.copyWith(
                              color: colors.onSurfaceVariant,
                              height: 1.5,
                            ),
                          ),
                          const SizedBox(height: 12),
                        ],
                        Text(
                          widget.content,
                          style: theme.textTheme.bodyLarge?.copyWith(
                            height: 1.55,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                if (isAutoClosing) ...[
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: _remainingSeconds / widget.autoCloseSeconds,
                      minHeight: 4,
                      backgroundColor: colors.surfaceContainerHighest,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerRight,
                    child: Text(
                      countdownLabel,
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ),
                ] else
                  Align(
                    alignment: Alignment.centerRight,
                    child: FilledButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: Text(appLocalizations.confirm),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

final announcementService = AnnouncementService();
