import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/lexicon_record.dart';

/// 词库状态
class LexiconState {
  final List<LexiconRecord> records;
  final bool isLoading;

  LexiconState({
    this.records = const [],
    this.isLoading = false,
  });

  LexiconState copyWith({
    List<LexiconRecord>? records,
    bool? isLoading,
  }) {
    return LexiconState(
      records: records ?? this.records,
      isLoading: isLoading ?? this.isLoading,
    );
  }
}

/// 词库 Provider
class LexiconNotifier extends StateNotifier<LexiconState> {
  LexiconNotifier() : super(LexiconState()) {
    _loadRecords();
  }

  static const _storageKey = 'lexicon_records';

  Future<void> _loadRecords() async {
    state = state.copyWith(isLoading: true);
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonStr = prefs.getString(_storageKey);
      if (jsonStr != null) {
        final List<dynamic> jsonList = json.decode(jsonStr);
        final records = jsonList
            .map((item) => LexiconRecord.fromJson(item as Map<String, dynamic>))
            .toList();
        state = state.copyWith(records: records);
      }
    } catch (e) {
      // 错误处理
    } finally {
      state = state.copyWith(isLoading: false);
    }
  }

  Future<void> _saveRecords() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonList = state.records.map((r) => r.toJson()).toList();
      await prefs.setString(_storageKey, json.encode(jsonList));
    } catch (e) {
      // 错误处理
    }
  }

  Future<void> addRecord(LexiconRecord record) async {
    state = state.copyWith(records: [record, ...state.records]);
    await _saveRecords();
  }

  Future<void> updateRecord(LexiconRecord record) async {
    state = state.copyWith(
      records: state.records.map((r) => r.key == record.key ? record : r).toList(),
    );
    await _saveRecords();
  }

  Future<void> removeRecord(String key) async {
    state = state.copyWith(
      records: state.records.where((r) => r.key != key).toList(),
    );
    await _saveRecords();
  }

  Future<void> removeRecords(List<String> keys) async {
    state = state.copyWith(
      records: state.records.where((r) => !keys.contains(r.key)).toList(),
    );
    await _saveRecords();
  }

  Future<void> addItem(String lexiconKey, String content) async {
    state = state.copyWith(
      records: state.records.map((r) {
        if (r.key == lexiconKey) {
          return r.copyWith(
            items: [
              ...r.items,
              LexiconItem(content: content),
            ],
          );
        }
        return r;
      }).toList(),
    );
    await _saveRecords();
  }

  Future<void> updateItem(String lexiconKey, String itemKey, String content) async {
    state = state.copyWith(
      records: state.records.map((r) {
        if (r.key == lexiconKey) {
          return r.copyWith(
            items: r.items.map((i) => i.key == itemKey ? i.copyWith(content: content) : i).toList(),
          );
        }
        return r;
      }).toList(),
    );
    await _saveRecords();
  }

  Future<void> removeItem(String lexiconKey, String itemKey) async {
    state = state.copyWith(
      records: state.records.map((r) {
        if (r.key == lexiconKey) {
          return r.copyWith(items: r.items.where((i) => i.key != itemKey).toList());
        }
        return r;
      }).toList(),
    );
    await _saveRecords();
  }

  Future<void> removeItems(String lexiconKey, List<String> itemKeys) async {
    state = state.copyWith(
      records: state.records.map((r) {
        if (r.key == lexiconKey) {
          return r.copyWith(items: r.items.where((i) => !itemKeys.contains(i.key)).toList());
        }
        return r;
      }).toList(),
    );
    await _saveRecords();
  }

  String exportToJson() {
    return json.encode(state.records.map((r) => r.toJson()).toList());
  }
}

final lexiconProvider = StateNotifierProvider<LexiconNotifier, LexiconState>((ref) {
  return LexiconNotifier();
});
