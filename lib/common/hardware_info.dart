import 'dart:io';
import 'package:fl_clash/common/common.dart';
import 'package:flutter/services.dart';

class HardwareInfo {
  static HardwareInfo? _instance;
  static const platform = MethodChannel('com.follow/hardware');
  
  String? _cpuId;
  String? _boardSerial;
  String? _diskSerial;
  String? _biosUuid;
  
  HardwareInfo._internal();
  
  factory HardwareInfo() {
    _instance ??= HardwareInfo._internal();
    return _instance!;
  }
  
  /// 获取CPU ID
  Future<String> getCpuId() async {
    if (_cpuId != null) return _cpuId!;
    
    try {
      if (Platform.isAndroid) {
        try {
          final String result = await platform.invokeMethod('getCpuId');
          _cpuId = result.isNotEmpty ? result : '';
          return _cpuId!;
        } catch (e) {
          commonPrint.log('Android获取CPU ID失败: $e', logLevel: LogLevel.warning);
        }
      } else if (Platform.isWindows) {
        final result = await Process.run('wmic', ['cpu', 'get', 'ProcessorId']);
        final output = result.stdout.toString();
        final lines = output.split('\n').where((line) => line.trim().isNotEmpty).toList();
        if (lines.length > 1) {
          _cpuId = lines[1].trim();
          return _cpuId!;
        }
      } else if (Platform.isLinux) {
        final result = await Process.run('cat', ['/proc/cpuinfo']);
        final output = result.stdout.toString();
        final serialLine = output.split('\n').firstWhere(
          (line) => line.contains('Serial'),
          orElse: () => '',
        );
        if (serialLine.isNotEmpty) {
          _cpuId = serialLine.split(':').last.trim();
          return _cpuId!;
        }
      } else if (Platform.isMacOS) {
        final result = await Process.run('sysctl', ['-n', 'machdep.cpu.brand_string']);
        _cpuId = result.stdout.toString().trim();
        return _cpuId!;
      }
    } catch (e) {
      commonPrint.log('获取CPU ID失败: $e', logLevel: LogLevel.warning);
    }
    
    _cpuId = '';
    return _cpuId!;
  }
  
  /// 获取主板序列号
  Future<String> getBoardSerial() async {
    if (_boardSerial != null) return _boardSerial!;
    
    try {
      if (Platform.isAndroid) {
        try {
          final String result = await platform.invokeMethod('getBoardSerial');
          _boardSerial = result.isNotEmpty ? result : '';
          return _boardSerial!;
        } catch (e) {
          commonPrint.log('Android获取主板序列号失败: $e', logLevel: LogLevel.warning);
        }
      } else if (Platform.isWindows) {
        final result = await Process.run('wmic', ['baseboard', 'get', 'SerialNumber']);
        final output = result.stdout.toString();
        final lines = output.split('\n').where((line) => line.trim().isNotEmpty).toList();
        if (lines.length > 1) {
          _boardSerial = lines[1].trim();
          return _boardSerial!;
        }
      } else if (Platform.isLinux) {
        final result = await Process.run('sudo', ['dmidecode', '-s', 'baseboard-serial-number']);
        _boardSerial = result.stdout.toString().trim();
        return _boardSerial!;
      } else if (Platform.isMacOS) {
        final result = await Process.run('system_profiler', ['SPHardwareDataType']);
        final output = result.stdout.toString();
        final serialLine = output.split('\n').firstWhere(
          (line) => line.contains('Serial Number'),
          orElse: () => '',
        );
        if (serialLine.isNotEmpty) {
          _boardSerial = serialLine.split(':').last.trim();
          return _boardSerial!;
        }
      }
    } catch (e) {
      commonPrint.log('获取主板序列号失败: $e', logLevel: LogLevel.warning);
    }
    
    _boardSerial = '';
    return _boardSerial!;
  }
  
  /// 获取硬盘序列号
  Future<String> getDiskSerial() async {
    if (_diskSerial != null) return _diskSerial!;
    
    try {
      if (Platform.isAndroid) {
        try {
          final String result = await platform.invokeMethod('getDiskSerial');
          _diskSerial = result.isNotEmpty ? result : '';
          return _diskSerial!;
        } catch (e) {
          commonPrint.log('Android获取硬盘序列号失败: $e', logLevel: LogLevel.warning);
        }
      } else if (Platform.isWindows) {
        final result = await Process.run('wmic', ['diskdrive', 'get', 'SerialNumber']);
        final output = result.stdout.toString();
        final lines = output.split('\n').where((line) => line.trim().isNotEmpty).toList();
        if (lines.length > 1) {
          _diskSerial = lines[1].trim();
          return _diskSerial!;
        }
      } else if (Platform.isLinux) {
        final result = await Process.run('lsblk', ['-o', 'SERIAL', '-n']);
        final output = result.stdout.toString();
        final lines = output.split('\n').where((line) => line.trim().isNotEmpty).toList();
        if (lines.isNotEmpty) {
          _diskSerial = lines.first.trim();
          return _diskSerial!;
        }
      } else if (Platform.isMacOS) {
        final result = await Process.run('system_profiler', ['SPSerialATADataType']);
        final output = result.stdout.toString();
        final serialLine = output.split('\n').firstWhere(
          (line) => line.contains('Serial Number'),
          orElse: () => '',
        );
        if (serialLine.isNotEmpty) {
          _diskSerial = serialLine.split(':').last.trim();
          return _diskSerial!;
        }
      }
    } catch (e) {
      commonPrint.log('获取硬盘序列号失败: $e', logLevel: LogLevel.warning);
    }
    
    _diskSerial = '';
    return _diskSerial!;
  }
  
  /// 获取BIOS UUID
  Future<String> getBiosUuid() async {
    if (_biosUuid != null) return _biosUuid!;
    
    try {
      if (Platform.isAndroid) {
        try {
          final String result = await platform.invokeMethod('getAndroidId');
          _biosUuid = result.isNotEmpty ? result : '';
          return _biosUuid!;
        } catch (e) {
          commonPrint.log('Android获取设备ID失败: $e', logLevel: LogLevel.warning);
        }
      } else if (Platform.isWindows) {
        final result = await Process.run('wmic', ['csproduct', 'get', 'UUID']);
        final output = result.stdout.toString();
        final lines = output.split('\n').where((line) => line.trim().isNotEmpty).toList();
        if (lines.length > 1) {
          _biosUuid = lines[1].trim();
          return _biosUuid!;
        }
      } else if (Platform.isLinux) {
        final result = await Process.run('sudo', ['dmidecode', '-s', 'system-uuid']);
        _biosUuid = result.stdout.toString().trim();
        return _biosUuid!;
      } else if (Platform.isMacOS) {
        final result = await Process.run('system_profiler', ['SPHardwareDataType']);
        final output = result.stdout.toString();
        final uuidLine = output.split('\n').firstWhere(
          (line) => line.contains('Hardware UUID'),
          orElse: () => '',
        );
        if (uuidLine.isNotEmpty) {
          _biosUuid = uuidLine.split(':').last.trim();
          return _biosUuid!;
        }
      }
    } catch (e) {
      commonPrint.log('获取BIOS UUID失败: $e', logLevel: LogLevel.warning);
    }
    
    _biosUuid = '';
    return _biosUuid!;
  }
  
  /// 获取所有硬件信息
  Future<Map<String, String>> getAllHardwareInfo() async {
    return {
      'cpu': await getCpuId(),
      'board': await getBoardSerial(),
      'disk': await getDiskSerial(),
      'uuid': await getBiosUuid(),
    };
  }
  
  /// 清除缓存（用于测试）
  void clearCache() {
    _cpuId = null;
    _boardSerial = null;
    _diskSerial = null;
    _biosUuid = null;
  }
}

final hardwareInfo = HardwareInfo();
