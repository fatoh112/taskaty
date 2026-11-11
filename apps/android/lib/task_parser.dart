class ParsedTaskCommand {
  const ParsedTaskCommand({
    required this.title,
    required this.durationMinutes,
    required this.priority,
    required this.assignedTo,
    required this.assigneeName,
    required this.assignmentNeedsReview,
    required this.intent,
    this.dueAt,
  });

  final String title;
  final int durationMinutes;
  final String priority;
  final String? assignedTo;
  final String? assigneeName;
  final bool assignmentNeedsReview;
  final String intent;
  final DateTime? dueAt;
}

class TeamName {
  const TeamName({required this.id, required this.name});
  final String id;
  final String name;
}

class TaskParser {
  static const _digits = <String, String>{
    '٠': '0', '١': '1', '٢': '2', '٣': '3', '٤': '4', '٥': '5', '٦': '6', '٧': '7', '٨': '8', '٩': '9',
    '۰': '0', '۱': '1', '۲': '2', '۳': '3', '۴': '4', '۵': '5', '۶': '6', '۷': '7', '۸': '8', '۹': '9',
  };
  static const _words = <String, int>{
    'واحد': 1, 'واحده': 1, 'اتنين': 2, 'اثنين': 2, 'اثنتين': 2,
    'تلاته': 3, 'ثلاثه': 3, 'اربع': 4, 'اربعه': 4, 'خمسه': 5, 'سته': 6, 'سبعه': 7, 'تمانيه': 8, 'ثمانيه': 8,
    'تسعه': 9, 'عشره': 10, 'حداشر': 11, 'اتناشر': 12, 'تلتاشر': 13, 'اربعتاشر': 14, 'خمستاشر': 15,
    'ستاشر': 16, 'سبعتاشر': 17, 'تمنتاشر': 18, 'تسعتاشر': 19, 'عشرين': 20, 'ثلاثين': 30, 'اربعين': 40,
  };

  static ParsedTaskCommand parse(String input, List<TeamName> members, {DateTime? now}) {
    final current = now ?? DateTime.now();
    var text = _normalize(input).replaceAll(RegExp(r'\s+'), ' ').trim();
    var duration = 240;
    DateTime? dueAt;
    var intent = 'create';
    final command = RegExp(r'^(?:انا\s+)?(خلصت|خلص|انجزت|انهيت|تم|ابدأ تنفيذ|ابدا تنفيذ|ابدأ|ابدا|شغل|الغى|الغاء|الغ)\s+(?:(?:المهمة|المهمه|مهمة|مهمه)\s+)?').firstMatch(text);
    if (command != null) {
      final verb = command.group(1)!;
      intent = switch (verb) {
        'خلصت' || 'خلص' || 'انجزت' || 'انهيت' || 'تم' => 'completed',
        'ابدأ' || 'ابدا' || 'ابدأ تنفيذ' || 'ابدا تنفيذ' || 'شغل' => 'in_progress',
        _ => 'cancelled',
      };
      text = text.substring(command.end).trim();
    }

    final tomorrow = RegExp(r'(?:بكرة|بكره|غدا|غداً)\s*(?:الساعة|الساعه)?\s*(\d{1,2}|[\u0600-\u06FF]+)(?::(\d{2}))?').firstMatch(text);
    if (tomorrow != null) {
      final hourToken = tomorrow.group(1)!;
      final hourRaw = int.tryParse(hourToken) ?? _wordNumber(hourToken)?.round();
      if (hourRaw != null && hourRaw >= 0 && hourRaw <= 23) {
        final minute = int.tryParse(tomorrow.group(2) ?? '0') ?? 0;
        final hour = _to24Hour(hourRaw, text);
        var day = DateTime(current.year, current.month, current.day + 1, hour, minute);
        if (!day.isAfter(current)) day = day.add(const Duration(days: 1));
        dueAt = day;
        duration = day.difference(current).inMinutes.clamp(1, 525600);
        text = text.replaceFirst(tomorrow.group(0)!, ' ');
      }
    }
    if (dueAt == null) {
      final durationMatch = RegExp(r'(?:(?:خلال|بعد|في|لمده)\s*)?(?:(نص ساعه|نصف ساعه|ربع ساعه|تلت ساعه|ثلث ساعه|ساعه ونص|ساعتين|يومين|يومان)|([0-9]+|[\u0600-\u06FF]+)\s*(دقيقه|دقايق|دقائق|ساعه|ساعات|يوم|ايام))').firstMatch(text);
      if (durationMatch != null) {
        final special = durationMatch.group(1);
        if (special != null) {
          duration = switch (special) {
            'نص ساعه' || 'نصف ساعه' => 30,
            'ربع ساعه' => 15,
            'تلت ساعه' || 'ثلث ساعه' => 20,
            'ساعه ونص' => 90,
            'ساعتين' => 120,
            _ => 2880,
          };
        } else {
          final count = _wordNumber(durationMatch.group(2) ?? '') ?? 4;
          final unit = durationMatch.group(3) ?? 'ساعه';
          final multiplier = unit.startsWith('دق') ? 1 : unit.startsWith('ي') ? 1440 : 60;
          duration = (count * multiplier).round().clamp(1, 525600);
        }
        text = text.replaceFirst(durationMatch.group(0)!, ' ');
      }
    }

    final urgent = RegExp(r'(مهمة جدا|مهمه جدا|مهمه قوي|مهمة قوي|ضروري جدا|عاجل|عاجلة|مستعجل)').hasMatch(text);
    final high = RegExp(r'(مهمة مهمة|مهم جدا|مهمه|أولوية عالية|اولوية عالية)').hasMatch(text);
    final low = RegExp(r'(أولوية منخفضة|اولوية منخفضة|مش مستعجل|عادي خالص)').hasMatch(text);
    final priority = urgent ? 'urgent' : high ? 'high' : low ? 'low' : 'normal';
    text = text.replaceAll(RegExp(r'(مهمة جدا|مهمه جدا|مهمه قوي|مهمة قوي|ضروري جدا|عاجل|عاجلة|مستعجل|مهمة مهمة|مهم جدا|مهمه|أولوية عالية|اولوية عالية|أولوية منخفضة|اولوية منخفضة|مش مستعجل|عادي خالص)'), ' ');

    String? assignee;
    String? assigneeName;
    var review = false;
    final candidates = members.where((m) => _containsName(text, m.name)).toList();
    if (candidates.length == 1) {
      assignee = candidates.single.id;
      assigneeName = candidates.single.name;
      text = _replaceName(text, candidates.single.name);
    } else if (candidates.length > 1) {
      review = true;
      assigneeName = candidates.first.name;
      assignee = null;
      text = _replaceName(text, candidates.first.name);
    }

    text = text
        .replaceAll(RegExp(r'^(?:اعمل|اعملي|سجل|سجلي|ضيف|أضف|اضف)\s+(?:تاسك|مهمة|مهمه|مهمة جديدة|تاسك جديد)?\s*'), '')
        .replaceAll(RegExp(r'^(?:ل|على)\s+'), '')
        .replaceAll(RegExp(r'(?:خلال|بعد|في)\s*$'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .replaceAll(RegExp(r'^[،,.:؛\s]+|[،,.:؛\s]+$'), '')
        .trim();
    if (text.isEmpty) text = _normalize(input).trim();
    return ParsedTaskCommand(
      title: text,
      durationMinutes: duration,
      priority: priority,
      assignedTo: assignee,
      assigneeName: assigneeName,
      assignmentNeedsReview: review,
      intent: intent,
      dueAt: dueAt,
    );
  }

  static String _normalize(String value) => value.replaceAllMapped(RegExp(r'[٠-٩۰-۹]'), (m) => _digits[m[0]] ?? m[0]!).replaceAll(RegExp(r'[\u064B-\u065F\u0670\u0640]'), '').replaceAll('أ', 'ا').replaceAll('إ', 'ا').replaceAll('آ', 'ا').replaceAll('ة', 'ه');
  static String normalizeForMatch(String value) => _normalize(value).toLowerCase().replaceAll(RegExp(r'[^\u0600-\u06FFa-z0-9 ]'), '').replaceAll(RegExp(r'\s+'), ' ').trim();
  static double? _wordNumber(String amount) {
    if (amount.isEmpty) return 1;
    final numeric = double.tryParse(amount);
    if (numeric != null) return numeric;
    return _words[amount]?.toDouble();
  }
  static bool _containsName(String text, String name) {
    final normalized = _normalize(text).toLowerCase();
    final candidate = _normalize(name).toLowerCase().trim();
    return candidate.isNotEmpty && RegExp(r'(^|[\\s،,])(?:ل|على)?' + RegExp.escape(candidate) + r'(?=$|[\\s،,])').hasMatch(normalized);
  }
  static String _replaceName(String text, String name) => text.replaceAll(RegExp(r'(?:^|[\s،,])(?:ل|على)?' + RegExp.escape(_normalize(name)) + r'(?=$|[\s،,])', caseSensitive: false), ' ');
  static int _to24Hour(int hour, String text) {
    final afternoon = RegExp(r'(مساء|بالليل|مسا)').hasMatch(text);
    if (afternoon && hour < 12) return hour + 12;
    return hour == 12 && !afternoon ? 0 : hour.clamp(0, 23);
  }
}
