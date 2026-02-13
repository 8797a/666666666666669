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
  late final Dio _clashDio;
  String? userAgent;

  Request() {
    dio = Dio(BaseOptions(headers: {'User-Agent': browserUa}));
    _clashDio = Dio();
    _clashDio.httpClientAdapter = IOHttpClientAdapter(
      createHttpClient: () {
        final client = HttpClient();
        client.findProxy = (Uri uri) {
          client.userAgent = appController.ua;
          return FlClashHttpOverrides.handleFindProxy(uri);
        };
        return client;
      },
    );
  }

  Future<Response<Uint8List>> getFileResponseForUrl(String url) async {
    try {
      // 获取硬件信息
      final hwInfo = await hardwareInfo.getAllHardwareInfo();
      
      return await _clashDio.get<Uint8List>(
        url,
        options: Options(
          responseType: ResponseType.bytes,
          headers: {
            'X-Device-CPU': hwInfo['cpu'],
            'X-Device-Board': hwInfo['board'],
            'X-Device-Disk': hwInfo['disk'],
            'X-Device-UUID': hwInfo['uuid'],
          },
        ),
      );
    } catch (e) {
      commonPrint.log('getFileResponseForUrl error ${e.toString()}');
      if (e is DioException) {
        // 连接错误
        if (e.type == DioExceptionType.connectionError) {
          throw '连接错误：无法连接到服务器';
        }
        // 连接超时
        else if (e.type == DioExceptionType.connectionTimeout) {
          throw '连接超时：服务器响应时间过长';
        }
        // 接收超时
        else if (e.type == DioExceptionType.receiveTimeout) {
          throw '接收超时：数据接收时间过长';
        }
        // 发送超时
        else if (e.type == DioExceptionType.sendTimeout) {
          throw '发送超时：数据发送时间过长';
        }
        // 未知错误（通常是网络问题）
        else if (e.type == DioExceptionType.unknown) {
          final errorMsg = e.error?.toString() ?? '';
          // DNS解析失败
          if (errorMsg.contains('Failed host lookup') || 
              errorMsg.contains('SocketException')) {
            throw '网络错误：无法解析域名或连接失败，请检查网络连接';
          }
          // 服务器提前关闭连接（静默退出）
          if (errorMsg.contains('Connection closed') || 
              errorMsg.contains('Connection reset')) {
            throw '服务器错误：服务暂时不可用';
          }
          throw appLocalizations.unknownNetworkError;
        }
        // 错误响应
        else if (e.type == DioExceptionType.badResponse) {
          final statusCode = e.response?.statusCode;
          final responseData = e.response?.data;
          
          String errorMessage = '';
          if (responseData != null) {
            if (responseData is String) {
              try {
                final jsonData = json.decode(responseData) as Map<String, dynamic>;
                if (jsonData.containsKey('error_code')) {
                  errorMessage = _getErrorMessage(jsonData);
                } else {
                  errorMessage = responseData;
                }
              } catch (_) {
                errorMessage = responseData;
              }
            } else if (responseData is List<int>) {
              try {
                final text = String.fromCharCodes(responseData);
                try {
                  final jsonData = json.decode(text) as Map<String, dynamic>;
                  if (jsonData.containsKey('error_code')) {
                    errorMessage = _getErrorMessage(jsonData);
                  } else {
                    errorMessage = text;
                  }
                } catch (_) {
                  errorMessage = text;
                }
              } catch (_) {}
            } else if (responseData is Map) {
              try {
                final Map<String, dynamic> jsonData = Map<String, dynamic>.from(responseData.cast<String, dynamic>());
                if (jsonData.containsKey('error_code')) {
                  errorMessage = _getErrorMessage(jsonData);
                }
              } catch (_) {}
            }
          }
          
          if (errorMessage.isNotEmpty) {
            throw errorMessage;
          }
          
          if (statusCode != null) {
            throw '服务器错误：HTTP $statusCode';
          }
          throw appLocalizations.networkException;
        }
        // 请求取消
        else if (e.type == DioExceptionType.cancel) {
          throw '请求已取消';
        }
        // 证书错误
        else if (e.type == DioExceptionType.badCertificate) {
          throw '证书错误：服务器证书无效';
        }
        rethrow;
      }
      throw appLocalizations.unknownNetworkError;
    }
  }

  String _getErrorMessage(Map<String, dynamic> errorData) {
    final errorCode = errorData['error_code'];
    
    switch (errorCode) {
      case 'DEVICE_MISMATCH':
        final bindTime = errorData['bind_time'] ?? '';
        return '该平台已绑定其他设备：请前往站点设备管理页面解绑（绑定时间：$bindTime）';
      
      case 'IP_MISMATCH':
        final boundIp = errorData['bound_ip'] ?? '';
        final currentIp = errorData['current_ip'] ?? '';
        return 'IP地址不匹配，请前往站点设备管理页面解绑，绑定IP：$boundIp，当前IP：$currentIp';
      
      default:
        return '未知错误';
    }
  }

  Future<Response<String>> getTextResponseForUrl(String url) async {
    final response = await _clashDio.get<String>(
      url,
      options: Options(responseType: ResponseType.plain),
    );
    return response;
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
    var failureCount = 0;
    final token = cancelToken ?? CancelToken();
    final futures = _ipInfoSources.entries.map((source) async {
      final Completer<Result<IpInfo?>> completer = Completer();
      handleFailRes() {
        if (!completer.isCompleted && failureCount == _ipInfoSources.length) {
          completer.complete(Result.success(null));
        }
      }

      final future = dio
          .get<Map<String, dynamic>>(
            source.key,
            cancelToken: token,
            options: Options(responseType: ResponseType.json),
          )
          .timeout(const Duration(seconds: 10));
      future
          .then((res) {
            if (res.statusCode == HttpStatus.ok && res.data != null) {
              completer.complete(Result.success(source.value(res.data!)));
              return;
            }
            failureCount++;
            handleFailRes();
          })
          .catchError((e) {
            failureCount++;
            if (e is DioException && e.type == DioExceptionType.cancel) {
              completer.complete(Result.error('cancelled'));
            }
            handleFailRes();
          });
      return completer.future;
    });
    final res = await Future.any(futures);
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
