import 'package:flutter/material.dart';

enum CommandCategory {
  navigation,
  action,
}

class CommandItem {
  final String id;
  final String title;
  final String subtitle;
  final List<String> keywords;
  final IconData icon;
  final CommandCategory category;
  final bool adminOnly;
  final VoidCallback onSelect;

  const CommandItem({
    required this.id,
    required this.title,
    required this.subtitle,
    this.keywords = const [],
    required this.icon,
    required this.category,
    this.adminOnly = false,
    required this.onSelect,
  });

  bool matches(String query) {
    if (query.isEmpty) return true;
    final q = query.toLowerCase().trim();
    if (title.toLowerCase().contains(q)) return true;
    if (subtitle.toLowerCase().contains(q)) return true;
    for (final kw in keywords) {
      if (kw.toLowerCase().contains(q)) return true;
    }
    return false;
  }
}
