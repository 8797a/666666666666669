import 'dart:convert';

import 'package:fl_clash/models/models.dart';

import 'preferences.dart';

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
    );
  }
}

class PlanLimitViolation {
  final String message;
  final bool expired;

  const PlanLimitViolation(this.message, {this.expired = false});
}

class PlanLimitController {
  Future<PlanLimitState> getState() async {
    final data = await preferences.getPlanLimitJson();
    if (data == null || data.isEmpty) {
      return const PlanLimitState();
    }
    try {
      return PlanLimitState.fromJson(json.decode(data) as Map<String, Object?>);
    } catch (_) {
      return const PlanLimitState();
    }
  }

  Future<void> saveFromSubscriptionInfo(SubscriptionInfo info) async {
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final state = await getState();
    final next = state.copyWith(
      name: info.planName,
      expire: info.expire,
      dailyTraffic: info.dailyTraffic,
      totalTraffic: info.total,
      serverTime: info.serverTime > 0 ? info.serverTime : now,
      receivedAt: now,
      dayKey: _currentDayKey(info.serverTime > 0 ? info.serverTime : now, now),
    );
    await _save(next);
  }

  Future<PlanLimitViolation?> check() async {
    final state = await _normalizeDay(await getState());
    final now = _estimatedNow(state);
    if (state.expire > 0 && now >= state.expire) {
      return const PlanLimitViolation(
        '套餐已到期，请更新配置或重新购买套餐',
        expired: true,
      );
    }
    if (state.dailyTraffic > 0 && state.dailyUsed >= state.dailyTraffic) {
      return const PlanLimitViolation('今日流量已用完，请明天再使用');
    }
    if (state.totalTraffic > 0 && state.totalUsed >= state.totalTraffic) {
      return const PlanLimitViolation('套餐流量已用完，请重新购买套餐');
    }
    return null;
  }

  Future<PlanLimitViolation?> addTraffic(num bytes) async {
    if (bytes <= 0) {
      return check();
    }
    final state = await _normalizeDay(await getState());
    final next = state.copyWith(
      dailyUsed: state.dailyUsed + bytes.round(),
      totalUsed: state.totalUsed + bytes.round(),
    );
    await _save(next);
    return check();
  }

  Future<void> _save(PlanLimitState state) async {
    await preferences.savePlanLimitJson(json.encode(state.toJson()));
  }

  Future<PlanLimitState> _normalizeDay(PlanLimitState state) async {
    final dayKey = _currentDayKey(state.serverTime, state.receivedAt);
    if (state.dayKey == dayKey) {
      return state;
    }
    final next = state.copyWith(dayKey: dayKey, dailyUsed: 0);
    await _save(next);
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
