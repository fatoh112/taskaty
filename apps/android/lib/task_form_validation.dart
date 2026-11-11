String? validateTaskTitle(String? value, {bool arabic = true}) {
  final title = value?.trim() ?? '';
  if (title.isEmpty) return arabic ? 'اكتب عنوان المهمة' : 'Task title is required';
  if (title.length > 240) return arabic ? 'العنوان طويل جدًا' : 'Title is too long';
  return null;
}

int? parseDurationMinutes(String value) {
  final minutes = int.tryParse(value.trim());
  if (minutes == null || minutes < 1 || minutes > 525600) return null;
  return minutes;
}
