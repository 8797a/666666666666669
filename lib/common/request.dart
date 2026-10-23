import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/controller.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/state.dart';
import 'package:flutter/cupertino.dart';

class Request {
  late final Dio dio;
  late final Dio _directDio;
  String? userAgent;

  Request() {
    dio = Dio(
      BaseOptions(
        headers: {'User-Agent': browserUa},
        connectTimeout: httpTimeoutDuration,
        sendTimeout: httpTimeoutDuration,
        receiveTimeout: httpTimeoutDuration,
      ),
    );

    _directDio = Dio(
      BaseOptions(
        headers: {'User-Agent': browserUa},
        connectTimeout: const Duration(seconds: 15),
        sendTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 30),
      ),
    );
    _directDio.httpClientAdapter = IOHttpClientAdapter(
      createHttpClient: () {
        final client = HttpClient();
        client.userAgent = appController.ua;
        client.findProxy = (_) => 'DIRECT';
        client.badCertificateCallback = (_, _, _) => true;
        return client;
      },
    );
  }

  Future<Response<Uint8List>> getFileResponseForUrl(String url) async {
    try {
      final hwInfo = await hardwareInfo.getAllHardwareInfo();
      return await _directDio.get<Uint8List>(
        url,
        options: Options(
          responseType: ResponseType.bytes,
          headers: {
            clientMarkerHeader: clientMarkerValue,
            'X-Device-Platform': Platform.operatingSystem,
            'X-Device-CPU': hwInfo['cpu'],
            'X-Device-Board': hwInfo['board'],
            'X-Device-Disk': hwInfo['disk'],
            'X-Device-UUID': hwInfo['uuid'],
          },
        ),
      );
    } catch (e) {
      commonPrint.log('getFileResponseForUrl error ${e.toString()}');
      _throwNetworkException(e);
    }
  }

  Never _throwNetworkException(Object e) {
    if (e is DioException) {
      switch (e.type) {
        case DioExceptionType.connectionError:
          throw 'Connection error: unable to connect to the server. Check the network or subscription URL.';
        case DioExceptionType.connectionTimeout:
          throw 'Connection timeout: the server took too long to respond.';
        case DioExceptionType.receiveTimeout:
          throw 'Receive timeout: the server took too long to return data.';
        case DioExceptionType.sendTimeout:
          throw 'Send timeout: the request took too long to send.';
        case DioExceptionType.badCertificate:
          throw 'Certificate error: invalid server certificate.';
        case DioExceptionType.cancel:
          throw 'Request cancelled.';
        case DioExceptionType.unknown:
          final errorMsg = e.error?.toString() ?? '';
          if (errorMsg.contains('Failed host lookup') ||
              errorMsg.contains('SocketException')) {
            throw 'Network error: unable to resolve the host or connect. Check the network connection.';
          }
          if (errorMsg.contains('Connection closed') ||
              errorMsg.contains('Connection reset')) {
            throw 'Server error: the server is temporarily unavailable.';
          }
          throw appLocalizations.unknownNetworkError;
        case DioExceptionType.badResponse:
          final message = _parseBadResponseMessage(e.response);
          if (message.isNotEmpty) {
            throw message;
          }
          final statusCode = e.response?.statusCode;
          if (statusCode != null) {
            throw 'Server error: HTTP $statusCode';
          }
          throw appLocalizations.networkException;
      }
    }
    throw appLocalizations.unknownNetworkError;
  }

  String _parseBadResponseMessage(Response<dynamic>? response) {
    final responseData = response?.data;
    if (responseData == null) {
      return '';
    }
    try {
      if (responseData is String) {
        return _parseErrorText(responseData);
      }
      if (responseData is List<int>) {
        return _parseErrorText(utf8.decode(responseData, allowMalformed: true));
      }
      if (responseData is Map) {
        return _getErrorMessage(Map<String, dynamic>.from(responseData));
      }
    } catch (_) {}
    return '';
  }

  String _parseErrorText(String text) {
    try {
      final jsonData = json.decode(text);
      if (jsonData is Map) {
        final message = _getErrorMessage(Map<String, dynamic>.from(jsonData));
        if (message.isNotEmpty) {
          return message;
        }
      }
    } catch (_) {}
    return text;
  }

  String _getErrorMessage(Map<String, dynamic> errorData) {
    final errorCode = errorData['error_code'];
    switch (errorCode) {
      case 'CLIENT_MARKER_INVALID':
        return 'The current client version is not supported.';
      case 'DEVICE_MISMATCH':
        final bindTime = errorData['bind_time'] ?? '';
        return 'This subscription is bound to another device. Unbind it in the device management page. Bind time: $bindTime';
      case 'IP_MISMATCH':
        final boundIp = errorData['bound_ip'] ?? '';
        final currentIp = errorData['current_ip'] ?? '';
        return 'IP address mismatch. Unbind it in the device management page. Bound IP: $boundIp, current IP: $currentIp';
      default:
        return '';
    }
  }

  Future<Response<String>> getTextResponseForUrl(String url) async {
    return await _directDio.get<String>(
      url,
      options: Options(responseType: ResponseType.plain),
    );
  }

  Future<MemoryImage?> getImage(String url) async {
    if (url.isEmpty) return null;
    final response = await dio.get<Uint8List>(
      url,
      options: Options(responseType: ResponseType.bytes),
    );
    final data = response.data;
    if (data == null) return null;
    return MemoryImage(data);
  }

  Future<Map<String, dynamic>?> checkForUpdate() async {
    try {
      final response = await dio.get(
        'https://api.github.com/repos/$repository/releases/latest',
        options: Options(responseType: ResponseType.json),
      );
      if (response.statusCode != 200) return null;
      final data = response.data as Map<String, dynamic>;
      final remoteVersion = data['tag_name'];
      final version = globalState.packageInfo.version;
      final hasUpdate =
          utils.compareVersions(remoteVersion.replaceAll('v', ''), version) > 0;
      if (!hasUpdate) return null;
      return data;
    } catch (e) {
      commonPrint.log('checkForUpdate failed', logLevel: LogLevel.warning);
      return null;
    }
  }

  final Map<String, IpInfo Function(Map<String, dynamic>)> _ipInfoSources = {
    'https://ipwho.is': IpInfo.fromIpWhoIsJson,
    'https://api.myip.com': IpInfo.fromMyIpJson,
    'https://ipapi.co/json': IpInfo.fromIpApiCoJson,
    'https://ident.me/json': IpInfo.fromIdentMeJson,
    'http://ip-api.com/json': IpInfo.fromIpAPIJson,
    'https://api.ip.sb/geoip': IpInfo.fromIpSbJson,
    'https://ipinfo.io/json': IpInfo.fromIpInfoIoJson,
  };

  Future<Result<IpInfo?>> checkIp({CancelToken? cancelToken}) async {
    final token = cancelToken ?? CancelToken();
    final completer = Completer<Result<IpInfo?>>();
    var pendingCount = _ipInfoSources.length;

    void finish(Result<IpInfo?> result) {
      if (!completer.isCompleted) {
        completer.complete(result);
      }
    }

    void finishOne() {
      pendingCount--;
      if (pendingCount <= 0) {
        finish(Result.success(null));
      }
    }

    for (final source in _ipInfoSources.entries) {
      unawaited(() async {
        try {
          final res = await dio
              .get<Map<String, dynamic>>(
                source.key,
                cancelToken: token,
                options: Options(responseType: ResponseType.json),
              )
              .timeout(const Duration(seconds: 8));
          if (res.statusCode == HttpStatus.ok && res.data != null) {
            finish(Result.success(source.value(res.data!)));
            return;
          }
        } catch (e) {
          if (e is DioException && e.type == DioExceptionType.cancel) {
            finish(Result.error('cancelled'));
            return;
          }
        } finally {
          finishOne();
        }
      }());
    }

    final res = await completer.future.timeout(
      const Duration(seconds: 12),
      onTimeout: () => Result.success(null),
    );
    token.cancel();
    return res;
  }

  Future<bool> pingHelper() async {
    try {
      final response = await dio
          .get(
            'http://$localhost:$helperPort/ping',
            options: Options(responseType: ResponseType.plain),
          )
          .timeout(const Duration(milliseconds: 2000));
      if (response.statusCode != HttpStatus.ok) {
        return false;
      }
      return (response.data as String) == globalState.coreSHA256;
    } catch (_) {
      return false;
    }
  }

  Future<bool> startCoreByHelper(String arg) async {
    try {
      final response = await dio
          .post(
            'http://$localhost:$helperPort/start',
            data: json.encode({'path': appPath.corePath, 'arg': arg}),
            options: Options(responseType: ResponseType.plain),
          )
          .timeout(const Duration(milliseconds: 2000));
      if (response.statusCode != HttpStatus.ok) {
        return false;
      }
      final data = response.data as String;
      return data.isEmpty;
    } catch (_) {
      return false;
    }
  }

  Future<bool> stopCoreByHelper() async {
    try {
      final response = await dio
          .post(
            'http://$localhost:$helperPort/stop',
            options: Options(responseType: ResponseType.plain),
          )
          .timeout(const Duration(milliseconds: 2000));
      if (response.statusCode != HttpStatus.ok) {
        return false;
      }
      final data = response.data as String;
      return data.isEmpty;
    } catch (_) {
      return false;
    }
  }
}

final request = Request();
