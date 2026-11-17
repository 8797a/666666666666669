import 'dart:async';
import 'dart:convert';

import 'package:fl_clash/models/models.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'constant.dart';
import 'profile_crypto.dart';

const invalidPlanLimitData = '__INVALID_PLAN_LIMIT_DATA__';

class Preferences {
  static Preferences? _instance;
  Completer<SharedPreferences?> sharedPreferencesCompleter = Completer();

  Future<bool> get isInit async =>
      await sharedPreferencesCompleter.future != null;

  Preferences._internal() {
    SharedPreferences.getInstance()
        .then((value) => sharedPreferencesCompleter.complete(value))
        .onError((_, _) => sharedPreferencesCompleter.complete(null));
  }

  factory Preferences() {
    _instance ??= Preferences._internal();
    return _instance!;
  }

  Future<int> getVersion() async {
    final preferences = await sharedPreferencesCompleter.future;
    return preferences?.getInt('version') ?? 0;
  }

  Future<void> setVersion(int version) async {
    final preferences = await sharedPreferencesCompleter.future;
    await preferences?.setInt('version', version);
  }

  Future<void> saveShareState(SharedState shareState) async {
    final preferences = await sharedPreferencesCompleter.future;
    await preferences?.setString('sharedState', json.encode(shareState));
  }

  Future<void> saveShareStateJson(String shareState) async {
    final preferences = await sharedPreferencesCompleter.future;
    await preferences?.setString('sharedState', shareState);
  }

  Future<Map<String, Object?>?> getConfigMap() async {
    try {
      final preferences = await sharedPreferencesCompleter.future;
      final configString = preferences?.getString(configKey);
      if (configString == null) return null;
      final Map<String, Object?>? configMap = json.decode(configString);
      return configMap;
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, Object?>?> getClashConfigMap() async {
    try {
      final preferences = await sharedPreferencesCompleter.future;
      final clashConfigString = preferences?.getString(clashConfigKey);
      if (clashConfigString == null) return null;
      return json.decode(clashConfigString);
    } catch (_) {
      return null;
    }
  }

  Future<void> clearClashConfig() async {
    try {
      final preferences = await sharedPreferencesCompleter.future;
      await preferences?.remove(clashConfigKey);
      return;
    } catch (_) {
      return;
    }
  }

  Future<Config?> getConfig() async {
    final configMap = await getConfigMap();
    if (configMap == null) {
      return null;
    }
    return Config.fromJson(configMap);
  }

  Future<bool> saveConfig(Config config) async {
    final preferences = await sharedPreferencesCompleter.future;
    return preferences?.setString(configKey, json.encode(config)) ?? false;
  }

  Future<String?> getPlanLimitJson({int? profileId}) async {
    final preferences = await sharedPreferencesCompleter.future;
    final key = profileId == null ? 'planLimit' : 'planLimit_$profileId';
    final data = preferences?.getString(key);
    if (data == null || data.isEmpty) {
      return data;
    }
    try {
      return await decryptSecureDataString(data);
    } catch (_) {
      return invalidPlanLimitData;
    }
  }

  Future<void> savePlanLimitJson(String data, {int? profileId}) async {
    final preferences = await sharedPreferencesCompleter.future;
    final key = profileId == null ? 'planLimit' : 'planLimit_$profileId';
    await preferences?.setString(key, await encryptSecureDataString(data));
  }

  Future<void> removePlanLimitJson({int? profileId}) async {
    final preferences = await sharedPreferencesCompleter.future;
    final key = profileId == null ? 'planLimit' : 'planLimit_$profileId';
    await preferences?.remove(key);
  }

  Future<bool> getLoginState() async {
    final preferences = await sharedPreferencesCompleter.future;
    return preferences?.getBool('isLoggedIn') ?? false;
  }

  Future<void> setLoginState(bool isLoggedIn) async {
    final preferences = await sharedPreferencesCompleter.future;
    await preferences?.setBool('isLoggedIn', isLoggedIn);
  }

  Future<void> clearPreferences() async {
    final sharedPreferencesIns = await sharedPreferencesCompleter.future;
    await sharedPreferencesIns?.clear();
  }
}

final preferences = Preferences();
