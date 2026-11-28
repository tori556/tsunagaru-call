import 'package:flutter/services.dart';
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
 
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
 
import '../models.dart';
import '../services/cloud_sync_service.dart';
import '../services/core_services.dart';
 
class AppStore extends ChangeNotifier {
  static const String _storageKey = 'tsunagaru_full_step1_6_v2';
 
  final CloudSyncService cloud = CloudSyncService();
 
  String myName = '自分';
  String myInviteId = '';
  bool warnOnNonWifi = true;
  int defaultExpireHours = 0;
  bool showOnlineStatus = true;
  bool showLastSeen = true;
  bool shareTypingStatus = true;
  bool noiseCancellationEnabled = true;
  String liveKitUrl = '';
  String liveKitToken = '';
 
  bool lockEnabled = false;
  bool useBiometrics = true;
  int lockGraceSeconds = 30;
  bool isUnlocked = true;
  DateTime? lastBackgroundedAt;
 
  List<MemberProfile> contacts = <MemberProfile>[];
  List<ChatGroup> groups = <ChatGroup>[];
  UpdateInfo? pendingUpdate;
 
  double? uploadProgress;
  String? uploadingFileName;
  IncomingCallPayload? activeIncomingCall;
 
  Timer? _housekeepingTimer;
  Timer? _ringTimer;
  Timer? _saveDebounceTimer;
 
  String get myViewerKey => cloud.uid ?? myInviteId;

  String displayNameForGroup(String groupId) => myName;

  Future<void> updateMyDisplayName(String newName) async {
    final clean = newName.trim().isEmpty ? '自分' : newName.trim();
    final oldName = myName;
    myName = clean;
    for (final g in groups) {
      final idx = g.members.indexOf(oldName);
      if (idx >= 0) {
        g.members[idx] = clean;
      }
      if (cloud.isReady) {
        unawaited(cloud.syncGroupToCloud(g));
      }
    }
    await saveImmediate(syncProfile: true);
  }
 
  Future<void> init() async {
    await _load();
    if (lockEnabled) {
      isUnlocked = false;
    }
 
    cloud.onIncomingCall = (IncomingCallPayload payload) {
      activeIncomingCall = payload;
      _startRingingFeedback(payload);
      notifyListeners();
    };
    cloud.onCallCancelled = (String callId) {
      if (activeIncomingCall?.callId == callId) {
        activeIncomingCall = null;
        _stopRingingFeedback();
        notifyListeners();
      }
    };
 
    await cloud.init(inviteId: myInviteId, displayName: myName);
    if (cloud.isReady) {
      _startCloudListeners();
    }
    notifyListeners();
 
    _housekeepingTimer?.cancel();
    _housekeepingTimer = Timer.periodic(
      const Duration(seconds: 10),
      (_) => _runHousekeeping(),
    );
    _checkUpdatesSilently();
  }
 
  void _startCloudListeners() {
    for (final g in groups) {
      if (cloud.uid != null && !g.memberUids.contains(cloud.uid)) {
        g.memberUids.add(cloud.uid!);
      }
      cloud.listenGroupMessages(g.id, (List<ChatMessage> remoteMsgs) {
        _mergeRemoteMessages(g.id, remoteMsgs);
      });
    }
 
    cloud.listenMyGroups((List<ChatGroup> remoteGroups) {
      var changed = false;
      for (final rg in remoteGroups) {
        // AUTO_SYNC_DM_CONTACT: 1対1トーク同期時に未登録の相手を友だち一覧へ自動追加
        final myUid = cloud.uid;
        if (myUid != null &&
            (rg.id.startsWith('dm_') || rg.memberUids.length == 2)) {
          String? otherUid;
          for (final u in rg.memberUids) {
            if (u.isNotEmpty && u != myUid) {
              otherUid = u;
              break;
            }
          }
          if (otherUid != null) {
            String otherName = '';
            for (final m in rg.members) {
              if (m.trim().isNotEmpty && m != myName) {
                otherName = m.trim();
                break;
              }
            }
            if (otherName.isEmpty) {
              otherName = (rg.name.trim().isNotEmpty && rg.name != myName)
                  ? rg.name.trim()
                  : '相手';
            }
            final exists = contacts.any(
              (c) => c.uid == otherUid || (otherName != '相手' && c.name == otherName),
            );
            if (!exists) {
              contacts.add(
                MemberProfile(
                  inviteId: otherUid.length >= 6
                      ? otherUid.substring(0, 6).toUpperCase()
                      : otherUid,
                  name: otherName,
                  uid: otherUid,
                ),
              );
              changed = true;
            }
          }
        }
        final local = findGroup(rg.id);
        if (local == null) {
          groups.add(rg);
          cloud.listenGroupMessages(rg.id, (List<ChatMessage> remoteMsgs) {
            _mergeRemoteMessages(rg.id, remoteMsgs);
          });
          changed = true;
        } else {
          if (local.pinnedMessageId != rg.pinnedMessageId) {
            local.pinnedMessageId = rg.pinnedMessageId;
            changed = true;
          }
          for (final uid in rg.memberUids) {
            if (!local.memberUids.contains(uid)) {
              local.memberUids.add(uid);
              changed = true;
            }
          }
          for (final m in rg.members) {
            if (!local.members.contains(m)) {
              local.members.add(m);
              changed = true;
            }
          }
        }
      }
      if (changed) save();
    });
  }
 
  void _mergeRemoteMessages(String groupId, List<ChatMessage> remoteMsgs) {
    final g = findGroup(groupId);
    if (g == null) return;
    final now = DateTime.now();
    final byId = <String, ChatMessage>{for (final m in g.messages) m.id: m};
    for (final rm in remoteMsgs) {
      if (rm.isExpired(now)) continue;
      final existing = byId[rm.id];
      if (existing?.media?.localPath != null &&
          rm.media != null &&
          rm.media!.localPath == null) {
        rm.media = MediaAttachment(
          fileName: rm.media!.fileName,
          localPath: existing!.media!.localPath,
          remoteUrl: rm.media!.remoteUrl,
          storagePath: rm.media!.storagePath,
          fileSizeBytes: rm.media!.fileSizeBytes,
          durationSec: rm.media!.durationSec,
          isTemporaryCache: existing.media!.isTemporaryCache,
        );
      }
      byId[rm.id] = rm;
    }
    final merged = byId.values.where((m) => !m.isExpired(now)).toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    g.messages
      ..clear()
      ..addAll(merged);
    save();
  }
 
  String _generateInviteId() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final r = Random.secure();
    String part(int n) =>
        List<String>.generate(n, (_) => chars[r.nextInt(chars.length)]).join();
    return 'TSU-${part(4)}-${part(2)}';
  }
 
  Future<void> _checkUpdatesSilently() async {
    try {
      final info = await UpdateChecker.checkLatest();
      if (info != null) {
        pendingUpdate = info;
        notifyListeners();
      }
    } catch (e, s) {
      ErrorGuard.record('更新確認スキップ: $e', s);
    }
  }
 
  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_storageKey);
      if (raw != null && raw.isNotEmpty) {
        final d = jsonDecode(raw) as JsonMap;
        myName = (d['myName'] as String?) ?? '自分';
        myInviteId = (d['myInviteId'] as String?) ?? '';
        warnOnNonWifi = (d['warnOnNonWifi'] as bool?) ?? true;
        defaultExpireHours = (d['defaultExpireHours'] as int?) ?? 0;
        showOnlineStatus = (d['showOnlineStatus'] as bool?) ?? true;
        showLastSeen = (d['showLastSeen'] as bool?) ?? true;
        shareTypingStatus = (d['shareTypingStatus'] as bool?) ?? true;
        noiseCancellationEnabled =
            (d['noiseCancellationEnabled'] as bool?) ?? true;
        liveKitUrl = (d['liveKitUrl'] as String?) ?? '';
        liveKitToken = (d['liveKitToken'] as String?) ?? '';
        lockEnabled = (d['lockEnabled'] as bool?) ?? false;
        useBiometrics = (d['useBiometrics'] as bool?) ?? true;
        lockGraceSeconds = (d['lockGraceSeconds'] as int?) ?? 30;
        contacts = ((d['contacts'] as List<dynamic>?) ?? const <dynamic>[])
            .map((dynamic e) => MemberProfile.fromJson(JsonMap.from(e as Map)))
            .toList();
        groups = ((d['groups'] as List<dynamic>?) ?? const <dynamic>[])
            .map((dynamic e) => ChatGroup.fromJson(JsonMap.from(e as Map)))
            .toList();
      }
    } catch (e, s) {
      ErrorGuard.record('データ復元エラー: $e', s);
    }
 
    if (myInviteId.isEmpty) {
      myInviteId = _generateInviteId();
    }
    _runHousekeeping(notify: false);
    notifyListeners();
  }
 
 
  void save({bool syncProfile = false}) {
    notifyListeners();
    _saveDebounceTimer?.cancel();
    _saveDebounceTimer = Timer(const Duration(milliseconds: 350), () {
      _persistNow(syncProfile: syncProfile);
    });
  }
 
  void updateDraft(String groupId, String draftText) {
    final g = findGroup(groupId);
    if (g == null) return;
    g.draft = draftText;
    _saveDebounceTimer?.cancel();
    _saveDebounceTimer = Timer(const Duration(milliseconds: 450), () {
      _persistNow(syncProfile: false);
    });
  }
 
  Future<void> saveImmediate({bool syncProfile = false}) async {
    _saveDebounceTimer?.cancel();
    notifyListeners();
    await _persistNow(syncProfile: syncProfile);
  }
 
  Future<void> _persistNow({required bool syncProfile}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _storageKey,
        jsonEncode(<String, dynamic>{
          'myName': myName,
          'myInviteId': myInviteId,
          'warnOnNonWifi': warnOnNonWifi,
          'defaultExpireHours': defaultExpireHours,
          'showOnlineStatus': showOnlineStatus,
          'showLastSeen': showLastSeen,
          'shareTypingStatus': shareTypingStatus,
          'noiseCancellationEnabled': noiseCancellationEnabled,
          'liveKitUrl': liveKitUrl,
          'liveKitToken': liveKitToken,
          'lockEnabled': lockEnabled,
          'useBiometrics': useBiometrics,
          'lockGraceSeconds': lockGraceSeconds,
          'contacts': contacts.map((c) => c.toJson()).toList(),
          'groups': groups.map((g) => g.toJson()).toList(),
        }),
      );
      if (syncProfile) {
        unawaited(
          cloud.syncUserProfile(
            inviteId: myInviteId,
            displayName: myName,
            defaultExpireHours: defaultExpireHours,
            showOnline: showOnlineStatus,
            showLastSeen: showLastSeen,
            shareTyping: shareTypingStatus,
          ),
        );
      }
    } catch (e, s) {
      ErrorGuard.record('データ保存エラーを吸収: $e', s);
    }
  }
 
  void handleAppPaused() {
    lastBackgroundedAt = DateTime.now();
    unawaited(_persistNow(syncProfile: false));
  }
 
  void handleAppResumed() {
    if (!lockEnabled || lastBackgroundedAt == null) return;
    final elapsed = DateTime.now().difference(lastBackgroundedAt!).inSeconds;
    if (elapsed >= lockGraceSeconds) {
      isUnlocked = false;
      notifyListeners();
    }
  }
 
  void unlockApp() {
    isUnlocked = true;
    notifyListeners();
  }
 
  Future<void> resetLockEmergency() async {
    await AuthLockService.clearPin();
    lockEnabled = false;
    isUnlocked = true;
    await saveImmediate();
  }
 
  void _runHousekeeping({bool notify = true}) {
    final now = DateTime.now();
    var changed = false;
 
    for (final g in groups) {
      final before = g.messages.length;
      g.messages.removeWhere((m) => m.isExpired(now));
      if (g.messages.length != before) {
        changed = true;
        if (g.pinnedMessageId != null &&
            !g.messages.any((m) => m.id == g.pinnedMessageId)) {
          g.pinnedMessageId = null;
        }
      }
 
      if (!cloud.isReady) {
        final due = g.scheduledMessages
            .where((m) => m.scheduledFor != null && !now.isBefore(m.scheduledFor!))
            .toList();
        if (due.isNotEmpty) {
          for (final item in due) {
            g.scheduledMessages.remove(item);
            g.messages.add(
              ChatMessage(
                id: item.id,
                sender: item.sender,
                senderId: item.senderId,
                text: item.text,
                createdAt: now,
                kind: item.kind,
                silent: item.silent,
                media: item.media,
                viewOncePhoto: item.viewOncePhoto,
                expiresAt: item.expiresAt,
                readBy: <String>[item.sender],
              ),
            );
          }
          changed = true;
        }
      }
    }
 
    if (changed && notify) save();
  }
 
  ChatGroup? findGroup(String id) {
    for (final g in groups) {
      if (g.id == id) return g;
    }
    return null;
  }
 
  Future<void> addGroup(String name, String category, List<String> members) async {
    final clean = <String>{myName, ...members}.toList();
    final group = ChatGroup(
      id: 'grp_${DateTime.now().millisecondsSinceEpoch}',
      name: name.trim(),
      category: category,
      members: clean,
      memberUids: cloud.uid != null ? <String>[cloud.uid!] : <String>[],
    );
    groups.add(group);
    await saveImmediate();
    if (cloud.isReady) {
      await cloud.syncGroupToCloud(group);
      cloud.listenGroupMessages(group.id, (List<ChatMessage> remoteMsgs) {
        _mergeRemoteMessages(group.id, remoteMsgs);
      });
    }
  }
 
  Future<MemberProfile> addContactByIdOrQr({
    required String inviteId,
    String? fallbackName,
    String? targetGroupId,
  }) async {
    final normalized = inviteId.trim().toUpperCase();
    final remote = await cloud.lookupInviteId(normalized);
    final profile = remote ??
        MemberProfile(
          inviteId: normalized,
          name: (fallbackName != null && fallbackName.trim().isNotEmpty)
              ? fallbackName.trim()
              : '友だち($normalized)',
        );
 
    contacts.removeWhere((c) => c.inviteId == profile.inviteId);
    contacts.add(profile);
 
    if (targetGroupId != null) {
      final g = findGroup(targetGroupId);
      if (g != null) {
        if (!g.members.contains(profile.name)) {
          g.members.add(profile.name);
        }
        if (profile.uid != null && !g.memberUids.contains(profile.uid)) {
          g.memberUids.add(profile.uid!);
        }
        unawaited(cloud.syncGroupToCloud(g));
      }
    }
    await saveImmediate();
    return profile;
  }

  Future<void> removeContact(String inviteId) async {
    contacts.removeWhere((c) => c.inviteId == inviteId);
    await saveImmediate();
  }

  Future<void> addContactToGroup(String groupId, MemberProfile contact) async {
    final g = findGroup(groupId);
    if (g == null) return;
    if (!g.members.contains(contact.name)) {
      g.members.add(contact.name);
    }
    if (contact.uid != null && !g.memberUids.contains(contact.uid)) {
      g.memberUids.add(contact.uid!);
    }
    await saveImmediate();
    if (cloud.isReady) {
      unawaited(cloud.syncGroupToCloud(g));
    }
  }

  Future<void> removeMemberFromGroup(String groupId, String memberName) async {
    final g = findGroup(groupId);
    if (g == null) return;
    g.members.remove(memberName);
    for (final c in contacts) {
      if (c.name == memberName && c.uid != null) {
        g.memberUids.remove(c.uid);
      }
    }
    await saveImmediate();
    if (cloud.isReady) {
      unawaited(cloud.syncGroupToCloud(g));
    }
  }

  Future<ChatGroup> openOrCreateDirectChat(MemberProfile contact) async {
    for (final g in groups) {
      if (g.category == '個人' &&
          (g.name == contact.name ||
              (contact.uid != null && g.memberUids.contains(contact.uid)))) {
        return g;
      }
    }
    final memberUids = <String>[];
    if (cloud.uid != null) memberUids.add(cloud.uid!);
    if (contact.uid != null && !memberUids.contains(contact.uid)) {
      memberUids.add(contact.uid!);
    }
    final direct = ChatGroup(
      id: 'dm_${DateTime.now().millisecondsSinceEpoch}',
      name: contact.name,
      category: '個人',
      members: <String>{myName, contact.name}.toList(),
      memberUids: memberUids,
    );
    groups.insert(0, direct);
    await saveImmediate();
    if (cloud.isReady) {
      await cloud.syncGroupToCloud(direct);
      cloud.listenGroupMessages(direct.id, (List<ChatMessage> remoteMsgs) {
        _mergeRemoteMessages(direct.id, remoteMsgs);
      });
    }
    return direct;
  }

  Future<void> renameGroup(String groupId, String newName) async {
    final clean = newName.trim();
    if (clean.isEmpty) return;
    final g = findGroup(groupId);
    if (g == null) return;
    g.name = clean;
    await saveImmediate();
    if (cloud.isReady) {
      unawaited(cloud.syncGroupToCloud(g));
    }
  }

  Future<void> deleteGroup(String groupId) async {
    try {
      await FirebaseFirestore.instance.collection('groups').doc(groupId).delete();
    } catch (_) {}

    groups.removeWhere((g) => g.id == groupId);
    await saveImmediate();
  }

 
  Future<void> sendMessage(
    String groupId, {
    required String text,
    String kind = 'text',
    int? expireHoursOverride,
    bool silent = false,
    String? replyToId,
    String? replyPreview,
    MediaAttachment? media,
    bool viewOncePhoto = false,
    String? forwardedFrom,
    PollData? poll,
    Duration? scheduleDelay,
  }) async {
    final g = findGroup(groupId);
    if (g == null) return;
    final now = DateTime.now();
    final hours = expireHoursOverride ?? defaultExpireHours;
    final sendAt = scheduleDelay != null ? now.add(scheduleDelay) : now;
    final expiresAt = hours > 0 ? sendAt.add(Duration(hours: hours)) : null;
    final msgId = 'm_${now.microsecondsSinceEpoch}';
 
    MediaAttachment? finalMedia = media;
    if (media != null && media.localPath != null && cloud.isReady) {
      uploadingFileName = media.fileName;
      uploadProgress = 0.01;
      notifyListeners();
      try {
        final uploaded = await cloud.uploadFileStream(
          groupId: groupId,
          messageId: msgId,
          file: File(media.localPath!),
          fileName: media.fileName,
          fileSizeBytes: media.fileSizeBytes,
          durationSec: media.durationSec,
          onProgress: (double p) {
            uploadProgress = p.clamp(0.0, 1.0);
            notifyListeners();
          },
        );
        if (uploaded != null) finalMedia = uploaded;
      } finally {
        uploadProgress = null;
        uploadingFileName = null;
        notifyListeners();
      }
    }
 
    final msg = ChatMessage(
      id: msgId,
      sender: myName,
      senderId: cloud.uid,
      text: text,
      createdAt: sendAt,
      kind: kind,
      silent: silent,
      forwardedFrom: forwardedFrom,
      replyToId: replyToId,
      replyPreview: replyPreview,
      media: finalMedia,
      viewOncePhoto: viewOncePhoto,
      expiresAt: expiresAt,
      scheduledFor: scheduleDelay != null ? sendAt : null,
      readBy: <String>[myName],
      poll: poll,
    );
 
    if (scheduleDelay != null) {
      g.scheduledMessages.add(msg);
    } else {
      g.messages.add(msg);
      g.draft = '';
    }
    await saveImmediate();
    if (cloud.isReady) {
      unawaited(cloud.syncGroupToCloud(g));
      unawaited(cloud.pushMessageToCloud(groupId, msg));
    }
  }
 
  Future<void> markViewOncePhotoViewed(String groupId, String messageId) async {
    final g = findGroup(groupId);
    if (g == null) return;
    for (final m in g.messages) {
      if (m.id == messageId && m.viewOncePhoto) {
        if (!m.viewedOnceBy.contains(myViewerKey)) {
          m.viewedOnceBy.add(myViewerKey);
        }
        if (m.media?.isTemporaryCache == true && m.media?.localPath != null) {
          try {
            final f = File(m.media!.localPath!);
            if (f.existsSync()) await f.delete();
          } catch (_) {}
        }
        save();
        unawaited(
          cloud.updateMessageFieldsInCloud(groupId, messageId, <String, dynamic>{
            'viewedOnceBy': m.viewedOnceBy,
          }),
        );
        return;
      }
    }
  }
 
  void markAllRead(String groupId) {
    final g = findGroup(groupId);
    if (g == null) return;
    var changed = false;
    for (final m in g.messages) {
      if (!m.readBy.contains(myName)) {
        m.readBy.add(myName);
        changed = true;
        unawaited(
          cloud.updateMessageFieldsInCloud(groupId, m.id, <String, dynamic>{
            'readBy': m.readBy,
          }),
        );
      }
    }
    if (changed) save();
  }
 
  void editMessage(String groupId, ChatMessage msg, String newText) {
    msg.text = newText;
    msg.edited = true;
    save();
    unawaited(
      cloud.updateMessageFieldsInCloud(groupId, msg.id, <String, dynamic>{
        'text': newText,
        'edited': true,
      }),
    );
  }
 
  void deleteMessageForAll(String groupId, ChatMessage msg) {
    msg.deletedForAll = true;
    msg.text = 'このメッセージは送信取り消しされました';
    msg.media = null;
    save();
    unawaited(
      cloud.updateMessageFieldsInCloud(groupId, msg.id, <String, dynamic>{
        'deletedForAll': true,
        'text': msg.text,
        'media': null,
      }),
    );
  }
 
  void togglePin(ChatGroup group, String? messageId) {
    group.pinnedMessageId = messageId;
    save();
    unawaited(cloud.syncGroupToCloud(group));
  }
 
  void updateTalkSettings(ChatGroup group, {bool? muted, String? ringtone}) {
    if (muted != null) group.muted = muted;
    if (ringtone != null) group.ringtone = ringtone;
    save();
    unawaited(
      cloud.syncMemberSettingToCloud(
        group.id,
        muted: group.muted,
        ringtone: group.ringtone,
      ),
    );
  }
 
  void toggleReaction(String groupId, String messageId, String emoji) {
    final g = findGroup(groupId);
    if (g == null) return;
    for (final m in g.messages) {
      if (m.id == messageId) {
        final users = m.reactions.putIfAbsent(emoji, () => <String>[]);
        if (users.contains(myName)) {
          users.remove(myName);
          if (users.isEmpty) m.reactions.remove(emoji);
        } else {
          users.add(myName);
        }
        save();
        unawaited(
          cloud.updateMessageFieldsInCloud(groupId, messageId, <String, dynamic>{
            'reactions': m.reactions,
          }),
        );
        return;
      }
    }
  }
 
  void votePoll(String groupId, String messageId, int optionIndex) {
    final g = findGroup(groupId);
    if (g == null) return;
    for (final m in g.messages) {
      if (m.id == messageId && m.poll != null) {
        final key = optionIndex.toString();
        m.poll!.votes.forEach((_, List<String> voters) => voters.remove(myName));
        m.poll!.votes.putIfAbsent(key, () => <String>[]).add(myName);
        save();
        unawaited(
          cloud.updateMessageFieldsInCloud(groupId, messageId, <String, dynamic>{
            'poll': m.poll!.toJson(),
          }),
        );
        return;
      }
    }
  }
 
  void triggerTestIncomingCall() {
    final group = groups.isNotEmpty
        ? groups.first
        : ChatGroup(
            id: 'test_call',
            name: '着信テスト',
            category: '個人',
            members: <String>[myName],
          );
    final payload = IncomingCallPayload(
      callId: 'test_${DateTime.now().millisecondsSinceEpoch}',
      groupId: group.id,
      groupName: group.name,
      callerName: group.members.length > 1 ? group.members[1] : 'お母さん',
      isVideo: true,
      ringtone: group.ringtone,
      sentAtEpochMs: DateTime.now().millisecondsSinceEpoch,
    );
    activeIncomingCall = payload;
    unawaited(CloudSyncService.showIncomingCallNotification(payload));
    notifyListeners();
  }
 
  void _startRingingFeedback(IncomingCallPayload payload) {
    _stopRingingFeedback();
    unawaited(CloudSyncService.showIncomingCallNotification(payload));
    SystemSound.play(SystemSoundType.alert);
    HapticFeedback.vibrate();
    _ringTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (activeIncomingCall == null) {
        _stopRingingFeedback();
        return;
      }
      SystemSound.play(SystemSoundType.alert);
      HapticFeedback.vibrate();
    });
  }

  void _stopRingingFeedback() {
    _ringTimer?.cancel();
    _ringTimer = null;
  }

  void clearIncomingCall({required String status}) {
    _stopRingingFeedback();
    final call = activeIncomingCall;
    activeIncomingCall = null;
    if (call != null) {
      localNotificationsPlugin.cancel(call.callId.hashCode & 0x7fffffff);
      unawaited(cloud.updateCallStatus(call.callId, status));
    }
    notifyListeners();
  }
 
  @override
  void dispose() {
    _housekeepingTimer?.cancel();
    _saveDebounceTimer?.cancel();
    cloud.dispose();
    super.dispose();
  }
}
