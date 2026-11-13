import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import 'config.dart';
import 'models.dart';

final httpClientProvider = Provider<http.Client>((ref) => http.Client());
final apiProvider = Provider<TaskApi>((ref) => TaskApi(ref.watch(httpClientProvider)));

class TaskApi {
  TaskApi(this._client);
  final http.Client _client;
  final Map<String, String> _etags = {};
  final Map<String, List<TaskItem>> _taskPages = {};
  final Map<String, Map<String, dynamic>> _dashboardPages = {};
  String get _base => AppConfig.apiBaseUrl.replaceFirst(RegExp(r'/+$'), '');

  void _remember<T>(Map<String, T> cache, String key, T value, String? etag) {
    cache.remove(key);
    cache[key] = value;
    if (etag != null) {
      _etags[key] = etag;
    } else {
      _etags.remove(key);
    }
    while (cache.length > 20) {
      final oldest = cache.keys.first;
      cache.remove(oldest);
      _etags.remove(oldest);
    }
  }

  Future<Map<String, dynamic>> _request(String path, {String method = 'GET', Object? body, Map<String, String>? headers, bool allowNotModified = false, bool retriedVerifiedToken = false}) async {
    if (!AppConfig.apiConfigured) throw const ApiException('Backend is not configured. Add TASKPULSE_API_URL.', code: 'CONFIG_MISSING');
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw const ApiException('Sign in to continue.', code: 'AUTH_REQUIRED');
    final token = await user.getIdToken();
    final uri = Uri.parse('$_base$path');
    final request = http.Request(method, uri)
      ..headers.addAll({'Authorization': 'Bearer $token', 'Accept': 'application/json', if (body != null) 'Content-Type': 'application/json', ...?headers})
      ..body = body == null ? '' : jsonEncode(body);
    final streamed = await _client.send(request).timeout(const Duration(seconds: 20));
    final response = await http.Response.fromStream(streamed);
    if (allowNotModified && response.statusCode == 304) return {'_notModified': true, 'etag': response.headers['etag']};
    Map<String, dynamic> payload = {};
    if (response.body.isNotEmpty) {
      try { payload = jsonDecode(response.body) as Map<String, dynamic>; } catch (_) { throw const ApiException('The server returned an invalid response.'); }
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final error = payload['error'] as Map<String, dynamic>?;
      if (response.statusCode == 403 && error?['code'] == 'EMAIL_NOT_VERIFIED' && user.emailVerified && !retriedVerifiedToken) {
        await user.getIdToken(true);
        return _request(path, method: method, body: body, headers: headers, allowNotModified: allowNotModified, retriedVerifiedToken: true);
      }
      throw ApiException((error?['message'] as String?) ?? 'Request failed (${response.statusCode}).', code: (error?['code'] as String?) ?? 'HTTP_${response.statusCode}');
    }
    final etag = response.headers['etag'];
    return {...payload, if (etag != null) '_etag': etag};
  }

  Future<Map<String, dynamic>> getMe() => _request('/v1/me');
  Future<List<Team>> listTeams() async => ((await _request('/v1/teams'))['items'] as List).cast<Map<String, dynamic>>().map(Team.fromJson).toList();
  Future<Team> createTeam(String name) async => Team.fromJson((await _request('/v1/teams', method: 'POST', body: {'name': name}))['team'] as Map<String, dynamic>);
  Future<String> createInvitation(String teamId) async => (await _request('/v1/teams/$teamId/invitations', method: 'POST', body: const {}))['code'] as String;
  Future<void> joinTeam(String code) async => _request('/v1/teams/join', method: 'POST', body: {'code': code});
  Future<void> leaveTeam(String teamId) async => _request('/v1/teams/$teamId/leave', method: 'POST', body: const {});
  Future<List<Member>> listMembers(String teamId) async => ((await _request('/v1/teams/$teamId/members'))['items'] as List).cast<Map<String, dynamic>>().map(Member.fromJson).toList();

  Future<List<TaskItem>> listTasks(String teamId, {String status = '', String search = '', bool onlyMine = false, String? etag}) async {
    final params = <String, String>{'limit': '50', if (status.isNotEmpty) 'status': status, if (search.isNotEmpty) 'q': search, if (onlyMine) 'assignedTo': 'me'};
    final path = '/v1/teams/$teamId/tasks?${Uri(queryParameters: params).query}';
    final cachedEtag = etag ?? _etags[path];
    var result = await _request(path, headers: {if (cachedEtag != null) 'If-None-Match': cachedEtag}, allowNotModified: true);
    if (result['_notModified'] == true && !_taskPages.containsKey(path)) result = await _request(path);
    if (result['_notModified'] == true) return _taskPages[path] ?? const [];
    final items = (result['items'] as List).cast<Map<String, dynamic>>().map(TaskItem.fromJson).toList();
    _remember(_taskPages, path, items, result['_etag'] as String?);
    return items;
  }

  Future<Map<String, dynamic>> dashboard(String teamId, {String? etag}) async {
    final path = '/v1/teams/$teamId/dashboard';
    final cachedEtag = etag ?? _etags[path];
    var result = await _request(path, headers: {if (cachedEtag != null) 'If-None-Match': cachedEtag}, allowNotModified: true);
    if (result['_notModified'] == true && !_dashboardPages.containsKey(path)) result = await _request(path);
    if (result['_notModified'] == true) return _dashboardPages[path] ?? const {};
    final responseEtag = result.remove('_etag') as String?;
    _remember(_dashboardPages, path, result, responseEtag);
    return result;
  }
  Future<TaskItem> getTask(String taskId) async => TaskItem.fromJson((await _request('/v1/tasks/$taskId'))['task'] as Map<String, dynamic>);
  Future<List<Map<String, dynamic>>> taskActivity(String taskId) async => (await _request('/v1/tasks/$taskId/activity'))['items'].cast<Map<String, dynamic>>();

  Future<TaskItem> createTask({required String teamId, required String title, required String description, required int durationMinutes, required String priority, required String idempotencyKey, String? assignedTo, DateTime? dueAt}) async {
    final result = await _request('/v1/teams/$teamId/tasks', method: 'POST', headers: {'Idempotency-Key': idempotencyKey}, body: {
      'title': title, 'description': description, 'durationMinutes': durationMinutes, 'priority': priority,
      'assignedTo': assignedTo, if (dueAt != null) 'dueAt': dueAt.toUtc().toIso8601String(),
    });
    return TaskItem.fromJson(result['task'] as Map<String, dynamic>);
  }

  Future<TaskItem> updateTask(String id, {required int version, String? title, String? description, int? durationMinutes, String? status, String? priority, String? assignedTo, bool clearAssignee = false}) async {
    final data = await _request('/v1/tasks/$id', method: 'PATCH', body: {
      'expectedVersion': version, if (title != null) 'title': title, if (description != null) 'description': description,
      if (durationMinutes != null) 'durationMinutes': durationMinutes,
      if (status != null) 'status': status, if (priority != null) 'priority': priority,
      if (assignedTo != null || clearAssignee) 'assignedTo': clearAssignee ? null : assignedTo,
    });
    return TaskItem.fromJson(data['task'] as Map<String, dynamic>);
  }

  Future<NotificationPage> listNotifications() async {
    final result = await _request('/v1/notifications?limit=50');
    return NotificationPage(items: (result['items'] as List).cast<Map<String, dynamic>>().map(AppNotification.fromJson).toList(), unreadCount: (result['unreadCount'] as num?)?.toInt() ?? 0, nextCursor: result['nextCursor'] as String?);
  }
  Future<void> markRead(String id) async { await _request('/v1/notifications/$id/read', method: 'POST', body: const {}); }
  Future<void> registerFcmToken(String token) async { await _request('/v1/devices/register', method: 'POST', body: {'token': token, 'platform': 'android'}); }
  Future<void> unregisterFcmToken(String token) async { await _request('/v1/devices/unregister', method: 'POST', body: {'token': token}); }
  Future<Map<String, dynamic>> health() async {
    if (!AppConfig.apiConfigured) throw const ApiException('Backend is not configured.', code: 'CONFIG_MISSING');
    final response = await _client.get(Uri.parse('$_base/health')).timeout(const Duration(seconds: 10));
    return jsonDecode(response.body) as Map<String, dynamic>;
  }
}
