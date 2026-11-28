import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models.dart';
import '../services/core_services.dart';

typedef _DialerJsonMap = Map<String, dynamic>;

String normalizePhoneNumber(String input) {
  final buffer = StringBuffer();
  for (final code in input.runes) {
    if (code >= 0xFF10 && code <= 0xFF19) {
      buffer.writeCharCode(code - 0xFEE0);
    } else if (code == 0xFF0B) {
      buffer.write('+');
    } else if (code == 0xFF0A) {
      buffer.write('*');
    } else if (code == 0xFF03) {
      buffer.write('#');
    } else {
      final ch = String.fromCharCode(code);
      if (RegExp(r'[0-9+*#]').hasMatch(ch)) {
        buffer.write(ch);
      }
    }
  }
  return buffer.toString();
}

String _formatCallTime(DateTime dt) {
  final m = dt.month.toString().padLeft(2, '0');
  final d = dt.day.toString().padLeft(2, '0');
  final hh = dt.hour.toString().padLeft(2, '0');
  final mm = dt.minute.toString().padLeft(2, '0');
  return '$m/$d $hh:$mm';
}

class ExternalPhoneContact {
  const ExternalPhoneContact({
    required this.id,
    required this.name,
    required this.phoneNumber,
    this.category = '家族',
  });

  final String id;
  final String name;
  final String phoneNumber;
  final String category;

  _DialerJsonMap toJson() => <String, dynamic>{
        'id': id,
        'name': name,
        'phoneNumber': phoneNumber,
        'category': category,
      };

  factory ExternalPhoneContact.fromJson(_DialerJsonMap json) =>
      ExternalPhoneContact(
        id: (json['id'] as String?) ??
            DateTime.now().microsecondsSinceEpoch.toString(),
        name: (json['name'] as String?) ?? '未登録',
        phoneNumber: (json['phoneNumber'] as String?) ?? '',
        category: (json['category'] as String?) ?? '家族',
      );
}

class ExternalCallRecord {
  const ExternalCallRecord({
    required this.id,
    required this.name,
    required this.phoneNumber,
    required this.calledAt,
  });

  final String id;
  final String name;
  final String phoneNumber;
  final DateTime calledAt;

  _DialerJsonMap toJson() => <String, dynamic>{
        'id': id,
        'name': name,
        'phoneNumber': phoneNumber,
        'calledAt': calledAt.toIso8601String(),
      };

  factory ExternalCallRecord.fromJson(_DialerJsonMap json) =>
      ExternalCallRecord(
        id: (json['id'] as String?) ??
            DateTime.now().microsecondsSinceEpoch.toString(),
        name: (json['name'] as String?) ?? '',
        phoneNumber: (json['phoneNumber'] as String?) ?? '',
        calledAt:
            DateTime.tryParse((json['calledAt'] as String?) ?? '') ??
                DateTime.now(),
      );
}

class PhoneDialerHelper {
  static const String _contactsKey = 'trancefer_ext_contacts_v1';
  static const String _historyKey = 'trancefer_ext_history_v1';

  static Future<List<ExternalPhoneContact>> loadContacts() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_contactsKey);
      if (raw == null || raw.isEmpty) return <ExternalPhoneContact>[];
      final decoded = jsonDecode(raw) as List<dynamic>;
      return decoded
          .map(
            (dynamic e) => ExternalPhoneContact.fromJson(
              _DialerJsonMap.from(e as Map),
            ),
          )
          .toList();
    } catch (e, s) {
      ErrorGuard.record('外線電話帳の読込エラー: $e', s);
      return <ExternalPhoneContact>[];
    }
  }

  static Future<void> saveContacts(List<ExternalPhoneContact> items) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _contactsKey,
        jsonEncode(items.map((e) => e.toJson()).toList()),
      );
    } catch (e, s) {
      ErrorGuard.record('外線電話帳の保存エラー: $e', s);
    }
  }

  static Future<List<ExternalCallRecord>> loadHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_historyKey);
      if (raw == null || raw.isEmpty) return <ExternalCallRecord>[];
      final decoded = jsonDecode(raw) as List<dynamic>;
      return decoded
          .map(
            (dynamic e) => ExternalCallRecord.fromJson(
              _DialerJsonMap.from(e as Map),
            ),
          )
          .toList();
    } catch (e, s) {
      ErrorGuard.record('発信履歴の読込エラー: $e', s);
      return <ExternalCallRecord>[];
    }
  }

  static Future<void> saveHistory(List<ExternalCallRecord> items) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _historyKey,
        jsonEncode(items.map((e) => e.toJson()).toList()),
      );
    } catch (e, s) {
      ErrorGuard.record('発信履歴の保存エラー: $e', s);
    }
  }

  static Future<bool> dial(
    BuildContext context, {
    required String rawNumber,
    String? displayName,
  }) async {
    final cleaned = normalizePhoneNumber(rawNumber);
    if (cleaned.isEmpty) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('電話番号を入力してください')),
        );
      }
      return false;
    }

    try {
      final uri = Uri(scheme: 'tel', path: cleaned);
      final opened = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
      if (!opened) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('電話アプリを開けませんでした（SIM・通話対応端末か確認してください）'),
            ),
          );
        }
        return false;
      }

      final history = await loadHistory();
      history.insert(
        0,
        ExternalCallRecord(
          id: 'ext_${DateTime.now().microsecondsSinceEpoch}',
          name: (displayName ?? '').trim(),
          phoneNumber: rawNumber.trim().isEmpty ? cleaned : rawNumber.trim(),
          calledAt: DateTime.now(),
        ),
      );
      if (history.length > 50) {
        history.removeRange(50, history.length);
      }
      await saveHistory(history);
      return true;
    } catch (e, s) {
      ErrorGuard.record('外線発信エラー: $e', s);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('発信処理でエラーが発生しました')),
        );
      }
      return false;
    }
  }
}

class PhoneDialerScreen extends StatefulWidget {
  const PhoneDialerScreen({super.key, this.initialTab = 0});
  final int initialTab;

  @override
  State<PhoneDialerScreen> createState() => _PhoneDialerScreenState();
}

class _PhoneDialerScreenState extends State<PhoneDialerScreen> {
  final TextEditingController _numberCtrl = TextEditingController();
  final TextEditingController _searchCtrl = TextEditingController();
  List<ExternalPhoneContact> _contacts = <ExternalPhoneContact>[];
  List<ExternalCallRecord> _history = <ExternalCallRecord>[];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _reloadData();
  }

  @override
  void dispose() {
    _numberCtrl.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _reloadData() async {
    final contacts = await PhoneDialerHelper.loadContacts();
    final history = await PhoneDialerHelper.loadHistory();
    if (!mounted) return;
    setState(() {
      _contacts = contacts;
      _history = history;
      _loading = false;
    });
  }

  String _findNameForNumber(String rawNumber) {
    final target = normalizePhoneNumber(rawNumber);
    for (final c in _contacts) {
      if (normalizePhoneNumber(c.phoneNumber) == target) {
        return c.name;
      }
    }
    return '';
  }

  Future<void> _placeCall(String rawNumber, {String? name}) async {
    final resolvedName =
        (name != null && name.trim().isNotEmpty) ? name.trim() : _findNameForNumber(rawNumber);
    final ok = await PhoneDialerHelper.dial(
      context,
      rawNumber: rawNumber,
      displayName: resolvedName,
    );
    if (ok) {
      await _reloadData();
    }
  }

  void _appendKey(String key) {
    final next = '${_numberCtrl.text}$key';
    _numberCtrl.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: next.length),
    );
    setState(() {});
  }

  void _backspace() {
    final text = _numberCtrl.text;
    if (text.isEmpty) return;
    final next = text.substring(0, text.length - 1);
    _numberCtrl.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: next.length),
    );
    setState(() {});
  }

  Future<void> _openContactDialog({
    ExternalPhoneContact? existing,
    String? prefillNumber,
  }) async {
    final nameCtrl = TextEditingController(text: existing?.name ?? '');
    final phoneCtrl = TextEditingController(
      text: existing?.phoneNumber ?? prefillNumber ?? '',
    );
    var category = existing?.category ?? '家族';

    try {
      final ok = await showDialog<bool>(
        context: context,
        builder: (BuildContext dc) => StatefulBuilder(
          builder: (_, StateSetter setLocal) => AlertDialog(
            title: Text(existing == null ? '外線連絡先を登録' : '外線連絡先を編集'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  TextField(
                    controller: nameCtrl,
                    decoration: const InputDecoration(
                      labelText: '名前（例：実家の固定電話、お母さん携帯）',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: phoneCtrl,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(
                      labelText: '電話番号（ハイフンあり／なし可）',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 10),
                  const Text('分類'),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    children: const <String>['家族', '親戚', '仕事', 'その他']
                        .map(
                          (String cat) => ChoiceChip(
                            label: Text(cat),
                            selected: category == cat,
                            onSelected: (_) => setLocal(() => category = cat),
                          ),
                        )
                        .toList(),
                  ),
                ],
              ),
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(dc).pop(false),
                child: const Text('キャンセル'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(dc).pop(true),
                child: const Text('保存'),
              ),
            ],
          ),
        ),
      );

      if (ok != true) return;
      final name = nameCtrl.text.trim();
      final phone = phoneCtrl.text.trim();
      if (name.isEmpty || normalizePhoneNumber(phone).isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('名前と電話番号を入力してください')),
          );
        }
        return;
      }

      final next = List<ExternalPhoneContact>.from(_contacts);
      if (existing != null) {
        final idx = next.indexWhere((c) => c.id == existing.id);
        final updated = ExternalPhoneContact(
          id: existing.id,
          name: name,
          phoneNumber: phone,
          category: category,
        );
        if (idx >= 0) {
          next[idx] = updated;
        } else {
          next.add(updated);
        }
      } else {
        next.add(
          ExternalPhoneContact(
            id: 'c_${DateTime.now().microsecondsSinceEpoch}',
            name: name,
            phoneNumber: phone,
            category: category,
          ),
        );
      }
      await PhoneDialerHelper.saveContacts(next);
      await _reloadData();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('「$name」を電話帳に保存しました')),
        );
      }
    } finally {
      nameCtrl.dispose();
      phoneCtrl.dispose();
    }
  }

  Future<void> _deleteContact(ExternalPhoneContact contact) async {
    final next = _contacts.where((c) => c.id != contact.id).toList();
    await PhoneDialerHelper.saveContacts(next);
    await _reloadData();
  }

  Future<void> _clearHistory() async {
    await PhoneDialerHelper.saveHistory(<ExternalCallRecord>[]);
    await _reloadData();
  }

  Widget _buildKeyButton(String label, {String? sub}) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.all(5),
        child: SizedBox(
          height: 60,
          child: OutlinedButton(
            style: OutlinedButton.styleFrom(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            onPressed: () => _appendKey(label),
            onLongPress: label == '0' ? () => _appendKey('+') : null,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (sub != null)
                  Text(
                    sub,
                    style: const TextStyle(fontSize: 10, color: Colors.black54),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDialTab() {
    final matchedName = _findNameForNumber(_numberCtrl.text);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        Card(
          color: const Color(0xFFF3F6F4),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: <Widget>[
                TextField(
                  controller: _numberCtrl,
                  keyboardType: TextInputType.phone,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.2,
                  ),
                  decoration: InputDecoration(
                    hintText: '090-1234-5678 / 086-...',
                    border: InputBorder.none,
                    suffixIcon: _numberCtrl.text.isNotEmpty
                        ? IconButton(
                            tooltip: 'クリア',
                            icon: const Icon(Icons.clear),
                            onPressed: () {
                              _numberCtrl.clear();
                              setState(() {});
                            },
                          )
                        : null,
                  ),
                  onChanged: (_) => setState(() {}),
                ),
                if (matchedName.isNotEmpty)
                  Text(
                    '登録先: $matchedName',
                    style: const TextStyle(
                      color: Color(0xFF1B8A5A),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: <Widget>[
            _buildKeyButton('1'),
            _buildKeyButton('2', sub: 'ABC'),
            _buildKeyButton('3', sub: 'DEF'),
          ],
        ),
        Row(
          children: <Widget>[
            _buildKeyButton('4', sub: 'GHI'),
            _buildKeyButton('5', sub: 'JKL'),
            _buildKeyButton('6', sub: 'MNO'),
          ],
        ),
        Row(
          children: <Widget>[
            _buildKeyButton('7', sub: 'PQRS'),
            _buildKeyButton('8', sub: 'TUV'),
            _buildKeyButton('9', sub: 'WXYZ'),
          ],
        ),
        Row(
          children: <Widget>[
            _buildKeyButton('*'),
            _buildKeyButton('0', sub: '長押しで+'),
            _buildKeyButton('#'),
          ],
        ),
        const SizedBox(height: 14),
        Row(
          children: <Widget>[
            OutlinedButton.icon(
              onPressed: _numberCtrl.text.trim().isEmpty
                  ? null
                  : () => _openContactDialog(prefillNumber: _numberCtrl.text),
              icon: const Icon(Icons.person_add),
              label: const Text('登録'),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF1B8A5A),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                onPressed: () => _placeCall(_numberCtrl.text),
                icon: const Icon(Icons.call, size: 22),
                label: const Text(
                  '固定・携帯へ発信',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
            ),
            const SizedBox(width: 10),
            IconButton.outlined(
              tooltip: '1文字削除',
              onPressed: _numberCtrl.text.isEmpty ? null : _backspace,
              icon: const Icon(Icons.backspace_outlined),
            ),
          ],
        ),
        const SizedBox(height: 12),
        const Text(
          '※ スマホ標準の電話アプリを起動して通話回線で発信します（ご契約中の通話料金・かけ放題がそのまま適用されます）。',
          style: TextStyle(fontSize: 12, color: Colors.black54),
        ),
      ],
    );
  }

  Widget _buildContactsTab() {
    final q = _searchCtrl.text.trim().toLowerCase();
    final filtered = q.isEmpty
        ? _contacts
        : _contacts
            .where(
              (c) =>
                  c.name.toLowerCase().contains(q) ||
                  c.phoneNumber.toLowerCase().contains(q) ||
                  c.category.toLowerCase().contains(q),
            )
            .toList();

    return Column(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
          child: Row(
            children: <Widget>[
              Expanded(
                child: TextField(
                  controller: _searchCtrl,
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search),
                    hintText: '名前・電話番号で検索',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                onPressed: () => _openContactDialog(),
                icon: const Icon(Icons.add),
                label: const Text('登録'),
              ),
            ],
          ),
        ),
        Expanded(
          child: filtered.isEmpty
              ? const Center(
                  child: Text('登録された固定電話・携帯番号はまだありません。\n右上の「登録」ボタンから追加できます。',
                      textAlign: TextAlign.center),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: filtered.length,
                  itemBuilder: (_, int i) {
                    final c = filtered[i];
                    return Card(
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: const Color(0xFFE8F5E9),
                          foregroundColor: const Color(0xFF1B8A5A),
                          child: Text(initialLetter(c.name)),
                        ),
                        title: Text(
                          c.name,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        subtitle: Text('${c.phoneNumber}（${c.category}）'),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            IconButton.filled(
                              style: IconButton.styleFrom(
                                backgroundColor: const Color(0xFF1B8A5A),
                                foregroundColor: Colors.white,
                              ),
                              tooltip: '発信',
                              icon: const Icon(Icons.call),
                              onPressed: () =>
                                  _placeCall(c.phoneNumber, name: c.name),
                            ),
                            PopupMenuButton<String>(
                              onSelected: (String action) {
                                if (action == 'edit') {
                                  _openContactDialog(existing: c);
                                } else if (action == 'delete') {
                                  _deleteContact(c);
                                }
                              },
                              itemBuilder: (_) => const <PopupMenuEntry<String>>[
                                PopupMenuItem<String>(
                                  value: 'edit',
                                  child: Text('編集'),
                                ),
                                PopupMenuItem<String>(
                                  value: 'delete',
                                  child: Text('削除'),
                                ),
                              ],
                            ),
                          ],
                        ),
                        onTap: () => _placeCall(c.phoneNumber, name: c.name),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildHistoryTab() {
    if (_history.isEmpty) {
      return const Center(child: Text('外線発信の履歴はまだありません。'));
    }
    return Column(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: <Widget>[
              Text('最近の発信（${_history.length}件）',
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              TextButton.icon(
                onPressed: _clearHistory,
                icon: const Icon(Icons.delete_outline, size: 18),
                label: const Text('履歴を消去'),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: _history.length,
            itemBuilder: (_, int i) {
              final h = _history[i];
              final savedName =
                  h.name.isNotEmpty ? h.name : _findNameForNumber(h.phoneNumber);
              return Card(
                child: ListTile(
                  leading: const Icon(Icons.call_made, color: Color(0xFF1B8A5A)),
                  title: Text(
                    savedName.isNotEmpty ? savedName : h.phoneNumber,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: Text(
                    savedName.isNotEmpty
                        ? '${h.phoneNumber} ・ ${_formatCallTime(h.calledAt)}'
                        : _formatCallTime(h.calledAt),
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      if (savedName.isEmpty)
                        IconButton(
                          tooltip: '電話帳に登録',
                          icon: const Icon(Icons.person_add_alt_1),
                          onPressed: () =>
                              _openContactDialog(prefillNumber: h.phoneNumber),
                        ),
                      IconButton.filledTonal(
                        tooltip: 'リダイヤル',
                        icon: const Icon(Icons.call),
                        onPressed: () =>
                            _placeCall(h.phoneNumber, name: savedName),
                      ),
                    ],
                  ),
                  onTap: () => _placeCall(h.phoneNumber, name: savedName),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final safeTab = widget.initialTab.clamp(0, 2);
    return DefaultTabController(
      length: 3,
      initialIndex: safeTab,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('固定電話・携帯電話へ発信'),
          bottom: const TabBar(
            tabs: <Tab>[
              Tab(icon: Icon(Icons.dialpad), text: 'ダイヤル'),
              Tab(icon: Icon(Icons.contacts), text: '外線電話帳'),
              Tab(icon: Icon(Icons.history), text: '発信履歴'),
            ],
          ),
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : TabBarView(
                children: <Widget>[
                  _buildDialTab(),
                  _buildContactsTab(),
                  _buildHistoryTab(),
                ],
              ),
      ),
    );
  }
}
