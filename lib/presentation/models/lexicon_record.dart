import 'package:uuid/uuid.dart';

/// 词条模型
class LexiconItem {
  final String key;
  final String content;

  LexiconItem({String? key, required this.content})
    : key = key ?? const Uuid().v4();

  LexiconItem copyWith({String? content}) {
    return LexiconItem(key: key, content: content ?? this.content);
  }

  Map<String, dynamic> toJson() {
    return {'key': key, 'content': content};
  }

  factory LexiconItem.fromJson(Map<String, dynamic> json) {
    return LexiconItem(
      key: json['key'] as String,
      content: json['content'] as String,
    );
  }
}

/// 词库记录模型
class LexiconRecord {
  final String key;
  final String name;
  final String description;
  final List<LexiconItem> items;
  final DateTime createdAt;

  LexiconRecord({
    String? key,
    required this.name,
    this.description = '',
    this.items = const <LexiconItem>[],
    DateTime? createdAt,
  }) : key = key ?? const Uuid().v4(),
       createdAt = createdAt ?? DateTime.now();

  LexiconRecord copyWith({
    String? name,
    String? description,
    List<LexiconItem>? items,
  }) {
    return LexiconRecord(
      key: key,
      name: name ?? this.name,
      description: description ?? this.description,
      items: items ?? this.items,
      createdAt: createdAt,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'key': key,
      'name': name,
      'description': description,
      'items': items.map((i) => i.toJson()).toList(),
      'createdAt': createdAt.toIso8601String(),
    };
  }

  factory LexiconRecord.fromJson(Map<String, dynamic> json) {
    return LexiconRecord(
      key: json['key'] as String,
      name: json['name'] as String,
      description: json['description'] as String? ?? '',
      items:
          (json['items'] as List<dynamic>?)
              ?.map((i) => LexiconItem.fromJson(i as Map<String, dynamic>))
              .toList()
              .cast<LexiconItem>() ??
          <LexiconItem>[],
      createdAt: DateTime.parse(json['createdAt'] as String),
    );
  }
}
