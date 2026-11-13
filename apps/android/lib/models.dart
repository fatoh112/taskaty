class Team {
  const Team({required this.id, required this.name, this.role = 'member'});
  final String id;
  final String name;
  final String role;
  factory Team.fromJson(Map<String, dynamic> j) => Team(
    id: j['id'] as String,
    name: j['name'] as String,
    role: (j['role'] as String?) ?? 'member',
  );
}

/// Removes invalid and duplicate team identifiers while preserving server order.
/// A team ID is the stable identity used for selection across API refreshes.
List<Team> uniqueTeamsById(Iterable<Team> teams) {
  final seen = <String>{};
  return [
    for (final team in teams)
      if (team.id.trim().isNotEmpty && seen.add(team.id)) team,
  ];
}

/// Resolves the current selection to an instance from [teams].
/// If the old selection disappeared, choose the first available team.
Team? resolveActiveTeam(Iterable<Team> teams, Team? current) {
  final options = uniqueTeamsById(teams);
  if (options.isEmpty) return null;
  for (final team in options) {
    if (team.id == current?.id) return team;
  }
  return options.first;
}

List<Member> uniqueMembersById(Iterable<Member> members) {
  final seen = <String>{};
  return [
    for (final member in members)
      if (member.id.trim().isNotEmpty && seen.add(member.id)) member,
  ];
}

class Member {
  const Member({
    required this.id,
    required this.name,
    required this.email,
    required this.role,
  });
  final String id;
  final String name;
  final String email;
  final String role;
  factory Member.fromJson(Map<String, dynamic> j) => Member(
    id: j['id'] as String,
    name: (j['displayName'] as String?) ?? '',
    email: (j['email'] as String?) ?? '',
    role: (j['role'] as String?) ?? 'member',
  );
}

class TaskItem {
  const TaskItem({
    required this.id,
    required this.teamId,
    required this.title,
    required this.description,
    required this.createdBy,
    required this.createdAt,
    required this.updatedAt,
    required this.durationMinutes,
    required this.dueAt,
    required this.priority,
    required this.status,
    required this.version,
    this.assignedTo,
    this.completedAt,
    this.isOverdue = false,
  });
  final String id, teamId, title, description, createdBy, priority, status;
  final String? assignedTo, completedAt;
  final DateTime createdAt, updatedAt, dueAt;
  final int durationMinutes, version;
  final bool isOverdue;
  bool get active => status == 'pending' || status == 'in_progress';
  factory TaskItem.fromJson(Map<String, dynamic> j) => TaskItem(
    id: j['id'] as String,
    teamId: j['teamId'] as String,
    title: j['title'] as String,
    description: (j['description'] as String?) ?? '',
    createdBy: j['createdBy'] as String,
    assignedTo: j['assignedTo'] as String?,
    createdAt: DateTime.parse(j['createdAt'] as String).toLocal(),
    updatedAt: DateTime.parse(j['updatedAt'] as String).toLocal(),
    durationMinutes: (j['durationMinutes'] as num).toInt(),
    dueAt: DateTime.parse(j['dueAt'] as String).toLocal(),
    priority: (j['priority'] as String?) ?? 'normal',
    status: j['status'] as String,
    version: (j['version'] as num).toInt(),
    completedAt: j['completedAt'] as String?,
    isOverdue: j['isOverdue'] == true,
  );
}

class AppNotification {
  const AppNotification({
    required this.id,
    required this.title,
    required this.body,
    required this.type,
    required this.createdAt,
    this.taskId,
    this.readAt,
  });
  final String id, title, body, type;
  final String? taskId, readAt;
  final DateTime createdAt;
  factory AppNotification.fromJson(Map<String, dynamic> j) => AppNotification(
    id: j['id'] as String,
    title: j['title'] as String,
    body: j['body'] as String,
    type: j['type'] as String,
    createdAt: DateTime.parse(j['createdAt'] as String).toLocal(),
    taskId: j['taskId'] as String?,
    readAt: j['readAt'] as String?,
  );
}

class NotificationPage {
  const NotificationPage({
    required this.items,
    required this.unreadCount,
    this.nextCursor,
  });
  final List<AppNotification> items;
  final int unreadCount;
  final String? nextCursor;
}

class ApiException implements Exception {
  const ApiException(this.message, {this.code = 'API_ERROR'});
  final String message;
  final String code;
  @override
  String toString() => message;
}
