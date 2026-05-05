import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';
import '../models/identity_record.dart';

/// 身份认证状态
class IdentityState {
  final List<IdentityRecord> records;

  const IdentityState({this.records = const []});

  IdentityState copyWith({List<IdentityRecord>? records}) {
    return IdentityState(records: records ?? this.records);
  }

  /// 根据指纹查找认证记录（不区分大小写）
  IdentityRecord? findByFingerprint(String fingerprint) {
    final upperFingerprint = fingerprint.toUpperCase();
    try {
      return records.firstWhere(
        (r) => r.fingerprintHex.toUpperCase() == upperFingerprint,
      );
    } catch (_) {
      return null;
    }
  }
}

/// 身份认证 Provider
class IdentityNotifier extends StateNotifier<IdentityState> {
  static const String _boxName = 'identity';
  static const String _recordsKey = 'records';
  Box<String>? _box;

  IdentityNotifier() : super(const IdentityState()) {
    _loadFromStorage();
  }

  /// 从本地存储加载
  Future<void> _loadFromStorage() async {
    try {
      _box = await Hive.openBox<String>(_boxName);
      final data = _box!.get(_recordsKey);
      if (data != null) {
        final List<dynamic> jsonList = jsonDecode(data);
        final records = jsonList
            .map((e) => IdentityRecord.fromJson(e as Map<String, dynamic>))
            .toList();
        state = IdentityState(records: records);
      }
    } catch (e) {
      // 加载失败时使用空列表
      state = const IdentityState();
    }
  }

  /// 保存到本地存储
  Future<void> _saveToStorage() async {
    if (_box == null) return;
    try {
      final jsonList = state.records.map((r) => r.toJson()).toList();
      await _box!.put(_recordsKey, jsonEncode(jsonList));
    } catch (e) {
      // 忽略保存错误
    }
  }

  /// 添加身份记录
  Future<void> addRecord(IdentityRecord record) async {
    // 检查是否已存在相同指纹的记录
    final existingIndex = state.records.indexWhere((r) => r.key == record.key);
    if (existingIndex >= 0) {
      // 更新已存在的记录
      final newRecords = List<IdentityRecord>.from(state.records);
      newRecords[existingIndex] = record;
      state = IdentityState(records: newRecords);
    } else {
      // 添加新记录
      state = IdentityState(records: [...state.records, record]);
    }
    await _saveToStorage();
  }

  /// 删除身份记录
  Future<void> removeRecord(String fingerprintHex) async {
    state = IdentityState(
      records: state.records.where((r) => r.key != fingerprintHex).toList(),
    );
    await _saveToStorage();
  }

  /// 批量删除身份记录
  Future<void> removeRecords(List<String> fingerprintHexList) async {
    final keySet = fingerprintHexList.toSet();
    state = IdentityState(
      records: state.records.where((r) => !keySet.contains(r.key)).toList(),
    );
    await _saveToStorage();
  }

  /// 更新身份记录
  Future<void> updateRecord(IdentityRecord record) async {
    final index = state.records.indexWhere((r) => r.key == record.key);
    if (index >= 0) {
      final newRecords = List<IdentityRecord>.from(state.records);
      newRecords[index] = record;
      state = IdentityState(records: newRecords);
      await _saveToStorage();
    }
  }

  /// 导出为 JSON 字符串
  String exportToJson() {
    final jsonList = state.records.map((r) => r.toJson()).toList();
    return const JsonEncoder.withIndent('  ').convert(jsonList);
  }

  /// 从 JSON 字符串导入
  Future<void> importFromJson(String jsonString) async {
    try {
      final List<dynamic> jsonList = jsonDecode(jsonString);
      final records = jsonList
          .map((e) => IdentityRecord.fromJson(e as Map<String, dynamic>))
          .toList();

      // 合并记录（已存在的会被覆盖）
      final Map<String, IdentityRecord> recordMap = {
        for (final r in state.records) r.key: r,
      };
      for (final r in records) {
        recordMap[r.key] = r;
      }

      state = IdentityState(records: recordMap.values.toList());
      await _saveToStorage();
    } catch (e) {
      rethrow;
    }
  }

  /// 清空所有记录
  Future<void> clearAll() async {
    state = const IdentityState();
    await _saveToStorage();
  }
}

/// Provider 实例
final identityProvider = StateNotifierProvider<IdentityNotifier, IdentityState>(
  (ref) => IdentityNotifier(),
);
