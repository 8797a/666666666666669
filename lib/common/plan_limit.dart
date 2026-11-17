import 'dart:convert';

import 'package:fl_clash/models/models.dart';

import 'preferences.dart';

const int limitedPlanTrafficMultiplier = 3;

class PlanLimitState {
  final String name;
  final int expire;
  final int dailyTraffic;
  final int totalTraffic;
  final int serverTime;
  final int receivedAt;
  final int dailyUsed;
  final int totalUsed;
  final String dayKey;
  final bool tampered;

  const PlanLimitState({
    this.name = '',
    this.expire = 0,
    this.dailyTraffic = 0,
    this.totalTraffic = 0,
    this.serverTime = 0,
    this.receivedAt = 0,
    this.dailyUsed = 0,
    this.totalUsed = 0,
    this.dayKey = '',
    this.tampered = false,
  });

  factory PlanLimitState.fromJson(Map<String, Object?> json) {
    return PlanLimitState(
      name: json['name'] as String? ?? '',
      expire: (json['expire'] as num?)?.toInt() ?? 0,
      dailyTraffic: (json['dailyTraffic'] as num?)?.toInt() ?? 0,
      totalTraffic: (json['totalTraffic'] as num?)?.toInt() ?? 0,
      serverTime: (json['serverTime'] as num?)?.toInt() ?? 0,
      receivedAt: (json['receivedAt'] as num?)?.toInt() ?? 0,
      dailyUsed: (json['dailyUsed'] as num?)?.toInt() ?? 0,
      totalUsed: (json['totalUsed'] as num?)?.toInt() ?? 0,
      dayKey: json['dayKey'] as String? ?? '',
      tampered: false,
    );
  }

  Map<String, Object?> toJson() {
    return {
      'name': name,
      'expire': expire,
      'dailyTraffic': dailyTraffic,
      'totalTraffic': totalTraffic,
      'serverTime': serverTime,
      'receivedAt': receivedAt,
      'dailyUsed': dailyUsed,
      'totalUsed': totalUsed,
      'dayKey': dayKey,
    };
  }

  PlanLimitState copyWith({
    String? name,
    int? expire,
    int? dailyTraffic,
    int? totalTraffic,
    int? serverTime,
    int? receivedAt,
    int? dailyUsed,
    int? totalUsed,
    String? dayKey,
    bool? tampered,
  }) {
    return PlanLimitState(
      name: name ?? this.name,
      expire: expire ?? this.expire,
      dailyTraffic: dailyTraffic ?? this.dailyTraffic,
      totalTraffic: totalTraffic ?? this.totalTraffic,
      serverTime: serverTime ?? this.serverTime,
      receivedAt: receivedAt ?? this.receivedAt,
      dailyUsed: dailyUsed ?? this.dailyUsed,
      totalUsed: totalUsed ?? this.totalUsed,
      dayKey: dayKey ?? this.dayKey,
      tampered: tampered ?? this.tampered,
    );
  }
}

class PlanLimitViolation {
  final String message;
  final bool expired;

  const PlanLimitViolation(this.message, {this.expired = false});
}

class PlanLimitController {
  Future<PlanLimitState> getState(
    int profileId, {
    SubscriptionInfo? subscriptionInfo,
  }) async {
    final data = await preferences.getPlanLimitJson(profileId: profileId);
    if (data != null && data.isNotEmpty) {
      return _decodeState(data) ?? const PlanLimitState(tampered: true);
    }

    final legacyData = await preferences.getPlanLimitJson();
    if (legacyData == invalidPlanLimitData) {
      await preferences.removePlanLimitJson();
      return _stateFromSubscriptionInfo(subscriptionInfo);
    }
    if (legacyData != null && legacyData.isNotEmpty) {
      final legacyState = _decodeState(legacyData);
      if (legacyState == null) {
        await preferences.removePlanLimitJson();
      } else if (_matchesSubscription(legacyState, subscriptionInfo)) {
        await _save(legacyState, profileId);
        await preferences.removePlanLimitJson();
        return legacyState;
      }
    }

    return _stateFromSubscriptionInfo(subscriptionInfo);
  }

  Future<void> saveFromSubscriptionInfo(
    SubscriptionInfo info, {
    required int profileId,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    var state = await getState(profileId, subscriptionInfo: info);
    if (state.tampered) {
      state = _stateFromSubscriptionInfo(info);
    }
    final serverTime = info.serverTime > 0 ? info.serverTime : now;
    final dayKey = _currentDayKey(serverTime, now);
    final next = state.copyWith(
      name: info.planName,
      expire: info.expire,
      dailyTraffic: info.dailyTraffic,
      totalTraffic: info.total,
      serverTime: serverTime,
      receivedAt: now,
      dailyUsed: state.dayKey == dayKey ? state.dailyUsed : 0,
      dayKey: dayKey,
    );
    await _save(next, profileId);
  }

  Future<PlanLimitViolation?> check(
    int profileId, {
    SubscriptionInfo? subscriptionInfo,
  }) async {
    final state = await getState(
      profileId,
      subscriptionInfo: subscriptionInfo,
    );
    if (state.tampered) {
      return const PlanLimitViolation(
        '本地套餐数据异常，请重新导入连接配置',
      );
    }
    final normalized = await _normalizeDay(state, profileId);
    final now = _estimatedNow(normalized);
    if (normalized.expire > 0 && now >= normalized.expire) {
      return const PlanLimitViolation(
        '套餐已到期，请更新配置或重新购买套餐',
        expired: true,
      );
    }
    if (normalized.dailyTraffic > 0 &&
        normalized.dailyUsed >= normalized.dailyTraffic) {
      return const PlanLimitViolation('今日流量已用完，请明天再使用');
    }
    if (normalized.totalTraffic > 0 &&
        normalized.totalUsed >= normalized.totalTraffic) {
      return const PlanLimitViolation('套餐流量已用完，请重新购买套餐');
    }
    return null;
  }

  Future<PlanLimitViolation?> addTraffic(
    int profileId,
    num bytes, {
    SubscriptionInfo? subscriptionInfo,
  }) async {
    if (bytes <= 0) {
      return check(profileId, subscriptionInfo: subscriptionInfo);
    }
    final state = await _normalizeDay(
      await getState(profileId, subscriptionInfo: subscriptionInfo),
      profileId,
    );
    if (state.tampered) {
      return const PlanLimitViolation(
        '本地套餐数据异常，请重新导入连接配置',
      );
    }
    final chargedBytes = _chargedTrafficBytes(state, bytes);
    final next = state.copyWith(
      dailyUsed: state.dailyUsed + chargedBytes,
      totalUsed: state.totalUsed + chargedBytes,
    );
    await _save(next, profileId);
    return check(profileId, subscriptionInfo: subscriptionInfo);
  }

  int _chargedTrafficBytes(PlanLimitState state, num bytes) {
    final rawBytes = bytes.round();
    final hasTrafficLimit = state.dailyTraffic > 0 || state.totalTraffic > 0;
    if (!hasTrafficLimit) {
      return rawBytes;
    }
    return rawBytes * limitedPlanTrafficMultiplier;
  }

  Future<void> clearProfile(int profileId) async {
    await preferences.removePlanLimitJson(profileId: profileId);
  }

  PlanLimitState _stateFromSubscriptionInfo(SubscriptionInfo? info) {
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final serverTime = (info?.serverTime ?? 0) > 0 ? info!.serverTime : now;
    return PlanLimitState(
      name: info?.planName ?? '',
      expire: info?.expire ?? 0,
      dailyTraffic: info?.dailyTraffic ?? 0,
      totalTraffic: info?.total ?? 0,
      serverTime: serverTime,
      receivedAt: now,
      dayKey: _currentDayKey(serverTime, now),
    );
  }

  bool _matchesSubscription(
    PlanLimitState state,
    SubscriptionInfo? info,
  ) {
    if (info == null || state.tampered) return false;
    final hasLimits = info.expire > 0 ||
        info.dailyTraffic > 0 ||
        info.total > 0 ||
        info.planName.isNotEmpty;
    return hasLimits &&
        state.name == info.planName &&
        state.expire == info.expire &&
        state.dailyTraffic == info.dailyTraffic &&
        state.totalTraffic == info.total;
  }

  PlanLimitState? _decodeState(String data) {
    if (data == invalidPlanLimitData) return null;
    try {
      return PlanLimitState.fromJson(json.decode(data) as Map<String, Object?>);
    } catch (_) {
      return null;
    }
  }

  Future<void> _save(PlanLimitState state, int profileId) async {
    await preferences.savePlanLimitJson(
      json.encode(state.toJson()),
      profileId: profileId,
    );
  }

  Future<PlanLimitState> _normalizeDay(
    PlanLimitState state,
    int profileId,
  ) async {
    if (state.tampered) return state;
    final dayKey = _currentDayKey(state.serverTime, state.receivedAt);
    if (state.dayKey == dayKey) {
      return state;
    }
    final next = state.copyWith(dayKey: dayKey, dailyUsed: 0);
    await _save(next, profileId);
    return next;
  }

  int _estimatedNow(PlanLimitState state) {
    if (state.serverTime <= 0 || state.receivedAt <= 0) {
      return DateTime.now().millisecondsSinceEpoch ~/ 1000;
    }
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    return state.serverTime + (now - state.receivedAt);
  }

  String _currentDayKey(int serverTime, int receivedAt) {
    final timestamp = serverTime > 0 && receivedAt > 0
        ? serverTime +
              ((DateTime.now().millisecondsSinceEpoch ~/ 1000) - receivedAt)
        : DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final date = DateTime.fromMillisecondsSinceEpoch(timestamp * 1000);
    return '${date.year}-${date.month}-${date.day}';
  }
}

final planLimitController = PlanLimitController();
