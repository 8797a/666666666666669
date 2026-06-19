import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';

const _profileMagic = 'FLCLASH_PROFILE_V1:';
const _hardwareChannel = MethodChannel('com.follow/hardware');
final _profileMagicBytes = ascii.encode(_profileMagic);
List<int>? _profileKey;

bool isEncryptedProfileBytes(List<int> bytes) {
  if (bytes.length < _profileMagicBytes.length) {
    return false;
  }
  for (var i = 0; i < _profileMagicBytes.length; i++) {
    if (bytes[i] != _profileMagicBytes[i]) {
      return false;
    }
  }
  return true;
}

Future<Uint8List> encryptProfileBytes(Uint8List plainBytes) async {
  final nonce = _randomBytes(16);
  final key = await _getProfileKey();
  final cipherBytes = _xorWithStream(plainBytes, nonce, key);
  final mac = _hmac([...nonce, ...cipherBytes], key);
  final payload = json.encode({
    'v': 1,
    'n': base64.encode(nonce),
    'd': base64.encode(cipherBytes),
    'm': base64.encode(mac),
  });
  return Uint8List.fromList([
    ..._profileMagicBytes,
    ...utf8.encode(base64.encode(utf8.encode(payload))),
  ]);
}

Future<Uint8List> decryptProfileBytes(Uint8List bytes) async {
  if (!isEncryptedProfileBytes(bytes)) {
    throw 'Profile data is not encrypted';
  }
  final payloadBase64 = utf8.decode(bytes.sublist(_profileMagicBytes.length));
  final payload = json.decode(utf8.decode(base64.decode(payloadBase64)));
  if (payload is! Map || payload['v'] != 1) {
    throw 'Invalid profile data';
  }
  final nonce = base64.decode(payload['n'] as String);
  final cipherBytes = base64.decode(payload['d'] as String);
  final mac = base64.decode(payload['m'] as String);
  final key = await _getProfileKey();
  final expectedMac = _hmac([...nonce, ...cipherBytes], key);
  if (!_constantTimeEqual(mac, expectedMac)) {
    throw 'Invalid profile data';
  }
  return _xorWithStream(Uint8List.fromList(cipherBytes), nonce, key);
}

Future<void> writeEncryptedProfileFile(File file, Uint8List plainBytes) async {
  if (!await file.exists()) {
    await file.create(recursive: true);
  }
  await file.writeAsBytes(await encryptProfileBytes(plainBytes), flush: true);
}

Future<Uint8List> readProfilePlainBytes(File file) async {
  final bytes = await file.readAsBytes();
  return decryptProfileBytes(Uint8List.fromList(bytes));
}

Future<String> readProfilePlainString(File file) async {
  final bytes = await readProfilePlainBytes(file);
  return utf8.decode(bytes);
}

List<int> _randomBytes(int length) {
  final random = Random.secure();
  return List<int>.generate(length, (_) => random.nextInt(256));
}

Future<List<int>> _getProfileKey() async {
  if (_profileKey != null) {
    return _profileKey!;
  }
  final hardware = await _getHardwareInfo();
  final material = [
    'fl_clash_profile_storage_v2',
    Platform.operatingSystem,
    hardware['cpu'] ?? '',
    hardware['board'] ?? '',
    hardware['disk'] ?? '',
    hardware['uuid'] ?? '',
  ].join('|');
  _profileKey = sha256.convert(utf8.encode(material)).bytes;
  return _profileKey!;
}

Future<Map<String, String>> _getHardwareInfo() async {
  if (Platform.isAndroid) {
    return {
      'cpu': await _invokeHardware('getCpuId'),
      'board': await _invokeHardware('getBoardSerial'),
      'disk': await _invokeHardware('getDiskSerial'),
      'uuid': await _invokeHardware('getAndroidId'),
    };
  }
  if (Platform.isWindows) {
    return {
      'cpu': await _wmic(['cpu', 'get', 'ProcessorId']),
      'board': await _wmic(['baseboard', 'get', 'SerialNumber']),
      'disk': await _wmic(['diskdrive', 'get', 'SerialNumber']),
      'uuid': await _wmic(['csproduct', 'get', 'UUID']),
    };
  }
  return {
    'cpu': Platform.localHostname,
    'board': Platform.operatingSystem,
    'disk': Platform.resolvedExecutable,
    'uuid': Platform.environment['USERNAME'] ?? Platform.environment['USER'] ?? '',
  };
}

Future<String> _invokeHardware(String method) async {
  try {
    return await _hardwareChannel.invokeMethod<String>(method) ?? '';
  } catch (_) {
    return '';
  }
}

Future<String> _wmic(List<String> arguments) async {
  try {
    final result = await Process.run('wmic', arguments);
    final lines = result.stdout
        .toString()
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();
    if (lines.length > 1) {
      return lines[1];
    }
  } catch (_) {}
  return '';
}

List<int> _hmac(List<int> bytes, List<int> key) {
  return Hmac(sha256, key).convert(bytes).bytes;
}

Uint8List _xorWithStream(Uint8List input, List<int> nonce, List<int> key) {
  final output = Uint8List(input.length);
  var offset = 0;
  var counter = 0;
  while (offset < input.length) {
    final counterBytes = ByteData(8)..setUint64(0, counter);
    final streamBlock = _hmac([
      ...nonce,
      ...counterBytes.buffer.asUint8List(),
    ], key);
    for (var i = 0; i < streamBlock.length && offset < input.length; i++) {
      output[offset] = input[offset] ^ streamBlock[i];
      offset++;
    }
    counter++;
  }
  return output;
}

bool _constantTimeEqual(List<int> a, List<int> b) {
  if (a.length != b.length) {
    return false;
  }
  var diff = 0;
  for (var i = 0; i < a.length; i++) {
    diff |= a[i] ^ b[i];
  }
  return diff == 0;
}
