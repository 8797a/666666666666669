import 'dart:convert';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/controller.dart';
import 'package:fl_clash/core/core.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/plugins/app.dart';
import 'package:fl_clash/plugins/service.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class AndroidManager extends ConsumerStatefulWidget {
  final Widget child;

  const AndroidManager({super.key, required this.child});

  @override
  ConsumerState<AndroidManager> createState() => _AndroidContainerState();
}

class _AndroidContainerState extends ConsumerState<AndroidManager>
    with ServiceListener {
  @override
  void initState() {
    super.initState();
    ref.listenManual(appSettingProvider.select((state) => state.hidden), (
      prev,
      next,
    ) {
      app?.updateExcludeFromRecents(next);
    }, fireImmediately: true);
    ref.listenManual(sharedStateProvider, (prev, next) async {
      if (prev != next) {
        debouncer.call(FunctionTag.saveSharedFile, () async {
          preferences.saveShareState(next.needSyncSharedState);
        }, duration: Duration(seconds: 1));
        if (prev?.needSyncSharedState != next.needSyncSharedState) {
          service?.syncStateData(await _buildSharedStateJson(next));
        }
      }
    });
    service?.addListener(this);
  }

  Future<String> _buildSharedStateJson(SharedState state) async {
    final stateJson = state.toJson();
    final profile = ref.read(currentProfileProvider);
    if (profile == null || state.setupParams == null) {
      stateJson['setupParams'] = null;
      return json.encode(stateJson);
    }
    try {
      final setupState = await ref.read(setupStateProvider(profile.id).future);
      final patchConfig = ref.read(patchClashConfigProvider);
      final config = await appController.getProfile(
        setupState: setupState,
        patchConfig: patchConfig,
      );
      final yamlString = await encodeYamlTask(config);
      stateJson['setupParams'] = state.setupParams!.toJson()
        ..['config'] = yamlString;
    } catch (_) {
      stateJson['setupParams'] = null;
    }
    return json.encode(stateJson);
  }

  @override
  Future<void> dispose() async {
    service?.removeListener(this);
    super.dispose();
  }

  @override
  void onServiceEvent(CoreEvent event) {
    coreEventManager.sendEvent(event);
    super.onServiceEvent(event);
  }

  @override
  void onServiceCrash(String message) {
    coreEventManager.sendEvent(
      CoreEvent(type: CoreEventType.crash, data: message),
    );
    super.onServiceCrash(message);
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}
