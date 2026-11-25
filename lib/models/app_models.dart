import 'package:flutter/material.dart';

/// 5つの関係カテゴリ（家族・友達・仕事関係・親戚・その他）
enum ContactCategory {
  family('family', '家族', '🏠', Color(0xFFFFEDD5), Color(0xFFC2410C)),
  friends('friends', '友達', '💛', Color(0xFFCCFBF1), Color(0xFF0F766E)),
  work('work', '仕事関係', '💼', Color(0xFFDBEAFE), Color(0xFF1D4ED8)),
  relatives('relatives', '親戚', '🌸', Color(0xFFFCE7F3), Color(0xFFBE185D)),
  other('other', 'その他', '✨', Color(0xFFEDE9FE), Color(0xFF6D28D9));

  const ContactCategory(
    this.id,
    this.label,
    this.emoji,
    this.bgColor,
    this.fgColor,
  );

  final String id;
  final String label;
  final String emoji;
  final Color bgColor;
  final Color fgColor;

  static ContactCategory fromId(String? id) {
    return ContactCategory.values.firstWhere(
      (e) => e.id == id,
      orElse: () => ContactCategory.other,
    );
  }
}

class AppUser {
  final String uid;
  final String myId;
  final String displayName;
  final String emoji;
  final String statusMessage;
  final String? email;
  final String? fcmToken;
  final String? voipToken;
  final bool isOnline;

  const AppUser({
    required this.uid,
    required this.myId,
    required this.displayName,
    required this.emoji,
    this.statusMessage = '電話OK',
    this.email,
    this.fcmToken,
    this.voipToken,
    this.isOnline = true,
  });

  AppUser copyWith({
    String? displayName,
    String? emoji,
    String? statusMessage,
    String? email,
    String? fcmToken,
    String? voipToken,
    bool? isOnline,
  }) {
    return AppUser(
      uid: uid,
      myId: myId,
      displayName: displayName ?? this.displayName,
      emoji: emoji ?? this.emoji,
      statusMessage: statusMessage ?? this.statusMessage,
      email: email ?? this.email,
      fcmToken: fcmToken ?? this.fcmToken,
      voipToken: voipToken ?? this.voipToken,
      isOnline: isOnline ?? this.isOnline,
    );
  }

  Map<String, dynamic> toMap() => {
        'uid': uid,
        'myId': myId,
        'displayName': displayName,
        'emoji': emoji,
        'statusMessage': statusMessage,
        'email': email ?? '',
        'fcmToken': fcmToken ?? '',
        'voipToken': voipToken ?? '',
        'isOnline': isOnline,
      };

  factory AppUser.fromMap(Map<String, dynamic> map) {
    return AppUser(
      uid: (map['uid'] ?? '').toString(),
      myId: (map['myId'] ?? '').toString(),
      displayName: (map['displayName'] ?? 'ユーザー').toString(),
      emoji: (map['emoji'] ?? '😊').toString(),
      statusMessage: (map['statusMessage'] ?? '電話OK').toString(),
      email: map['email']?.toString(),
      fcmToken: map['fcmToken']?.toString(),
      voipToken: map['voipToken']?.toString(),
      isOnline: map['isOnline'] == true,
    );
  }
}

class ContactItem {
  final String id;
  final String targetUid;
  final String targetMyId;
  final String name;
  final String emoji;
  final ContactCategory category;
  final String memo;
  final bool pinned;
  final bool isOnline;
  final String statusText;
  final String? lastMessage;
  final DateTime? lastMessageAt;
  final int unreadCount;

  const ContactItem({
    required this.id,
    required this.targetUid,
    required this.targetMyId,
    required this.name,
    required this.emoji,
    required this.category,
    this.memo = '',
    this.pinned = false,
    this.isOnline = false,
    this.statusText = '待機中',
    this.lastMessage,
    this.lastMessageAt,
    this.unreadCount = 0,
  });

  ContactItem copyWith({
    String? name,
    String? emoji,
    ContactCategory? category,
    String? memo,
    bool? pinned,
    bool? isOnline,
    String? statusText,
    String? lastMessage,
    DateTime? lastMessageAt,
    int? unreadCount,
  }) {
    return ContactItem(
      id: id,
      targetUid: targetUid,
      targetMyId: targetMyId,
      name: name ?? this.name,
      emoji: emoji ?? this.emoji,
      category: category ?? this.category,
      memo: memo ?? this.memo,
      pinned: pinned ?? this.pinned,
      isOnline: isOnline ?? this.isOnline,
      statusText: statusText ?? this.statusText,
      lastMessage: lastMessage ?? this.lastMessage,
      lastMessageAt: lastMessageAt ?? this.lastMessageAt,
      unreadCount: unreadCount ?? this.unreadCount,
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'targetUid': targetUid,
        'targetMyId': targetMyId,
        'name': name,
        'emoji': emoji,
        'category': category.id,
        'memo': memo,
        'pinned': pinned,
      };

  factory ContactItem.fromMap(Map<String, dynamic> map) {
    return ContactItem(
      id: (map['id'] ?? '').toString(),
      targetUid: (map['targetUid'] ?? '').toString(),
      targetMyId: (map['targetMyId'] ?? '').toString(),
      name: (map['name'] ?? '連絡先').toString(),
      emoji: (map['emoji'] ?? '😊').toString(),
      category: ContactCategory.fromId(map['category']?.toString()),
      memo: (map['memo'] ?? '').toString(),
      pinned: map['pinned'] == true,
      isOnline: map['isOnline'] == true,
      statusText: (map['statusText'] ?? '待機中').toString(),
      lastMessage: map['lastMessage']?.toString(),
      lastMessageAt: map['lastMessageAt'] is int
          ? DateTime.fromMillisecondsSinceEpoch(map['lastMessageAt'] as int)
          : null,
      unreadCount: (map['unreadCount'] as num?)?.toInt() ?? 0,
    );
  }
}

/// Phase 3 追加: グループ内で進行中の通話セッション情報
class GroupCallSession {
  final String roomName;
  final bool isVideo;
  final String startedByName;
  final List<String> activeParticipantUids;
  final DateTime startedAt;

  const GroupCallSession({
    required this.roomName,
    required this.isVideo,
    required this.startedByName,
    required this.activeParticipantUids,
    required this.startedAt,
  });

  Map<String, dynamic> toMap() => {
        'roomName': roomName,
        'isVideo': isVideo,
        'startedByName': startedByName,
        'activeParticipantUids': activeParticipantUids,
        'startedAtMs': startedAt.millisecondsSinceEpoch,
      };

  factory GroupCallSession.fromMap(Map<String, dynamic> map) {
    final raw = (map['activeParticipantUids'] as List?) ?? const [];
    return GroupCallSession(
      roomName: (map['roomName'] ?? '').toString(),
      isVideo: map['isVideo'] == true,
      startedByName: (map['startedByName'] ?? 'メンバー').toString(),
      activeParticipantUids: raw.map((e) => e.toString()).toList(),
      startedAt: DateTime.fromMillisecondsSinceEpoch(
        (map['startedAtMs'] as num?)?.toInt() ??
            DateTime.now().millisecondsSinceEpoch,
      ),
    );
  }
}

class GroupChatRoom {
  final String id;
  final String name;
  final String emoji;
  final ContactCategory category;
  final List<String> memberUids;
  final Map<String, String> memberNames;
  final String? lastMessage;
  final DateTime? lastMessageAt;
  final int unreadCount;
  final GroupCallSession? activeCall;

  const GroupChatRoom({
    required this.id,
    required this.name,
    required this.emoji,
    required this.category,
    required this.memberUids,
    required this.memberNames,
    this.lastMessage,
    this.lastMessageAt,
    this.unreadCount = 0,
    this.activeCall,
  });

  bool get hasActiveCall =>
      activeCall != null && activeCall!.activeParticipantUids.isNotEmpty;

  GroupChatRoom copyWith({
    String? name,
    String? emoji,
    ContactCategory? category,
    List<String>? memberUids,
    Map<String, String>? memberNames,
    String? lastMessage,
    DateTime? lastMessageAt,
    int? unreadCount,
    GroupCallSession? activeCall,
    bool clearActiveCall = false,
  }) {
    return GroupChatRoom(
      id: id,
      name: name ?? this.name,
      emoji: emoji ?? this.emoji,
      category: category ?? this.category,
      memberUids: memberUids ?? this.memberUids,
      memberNames: memberNames ?? this.memberNames,
      lastMessage: lastMessage ?? this.lastMessage,
      lastMessageAt: lastMessageAt ?? this.lastMessageAt,
      unreadCount: unreadCount ?? this.unreadCount,
      activeCall: clearActiveCall ? null : (activeCall ?? this.activeCall),
    );
  }

  factory GroupChatRoom.fromMap(String id, Map<String, dynamic> map) {
    final rawUids = (map['memberUids'] as List?) ?? const [];
    final rawNames = Map<String, dynamic>.from(
      (map['memberNames'] as Map?) ?? const {},
    );
    final rawCall = map['activeCall'];
    return GroupChatRoom(
      id: id,
      name: (map['name'] ?? 'グループ').toString(),
      emoji: (map['emoji'] ?? '👥').toString(),
      category: ContactCategory.fromId(map['category']?.toString()),
      memberUids: rawUids.map((e) => e.toString()).toList(),
      memberNames: rawNames.map((k, v) => MapEntry(k, v.toString())),
      lastMessage: map['lastMessage']?.toString(),
      lastMessageAt: map['lastMessageAtMs'] is num
          ? DateTime.fromMillisecondsSinceEpoch(
              (map['lastMessageAtMs'] as num).toInt(),
            )
          : null,
      unreadCount: (map['unreadCount'] as num?)?.toInt() ?? 0,
      activeCall: rawCall is Map
          ? GroupCallSession.fromMap(Map<String, dynamic>.from(rawCall))
          : null,
    );
  }
}

class ChatMessage {
  final String id;
  final String senderUid;
  final String senderName;
  final String senderEmoji;
  final String text;
  final String? imageUrl;
  final String? localImagePath;
  final bool isStamp;
  final String? stampId;
  final DateTime createdAt;
  final bool isRead;
  final List<String> readBy;

  const ChatMessage({
    required this.id,
    required this.senderUid,
    this.senderName = '',
    this.senderEmoji = '😊',
    required this.text,
    this.imageUrl,
    this.localImagePath,
    this.isStamp = false,
    this.stampId,
    required this.createdAt,
    this.isRead = false,
    this.readBy = const [],
  });

  bool get hasImage =>
      (imageUrl != null && imageUrl!.isNotEmpty) ||
      (localImagePath != null && localImagePath!.isNotEmpty);

  int get readCount => readBy.isNotEmpty ? readBy.length : (isRead ? 1 : 0);

  factory ChatMessage.fromMap(String id, Map<String, dynamic> map) {
    final rawReadBy = (map['readBy'] as List?) ?? const [];
    return ChatMessage(
      id: id,
      senderUid: (map['senderUid'] ?? '').toString(),
      senderName: (map['senderName'] ?? '').toString(),
      senderEmoji: (map['senderEmoji'] ?? '😊').toString(),
      text: (map['text'] ?? '').toString(),
      imageUrl: map['imageUrl']?.toString(),
      localImagePath: map['localImagePath']?.toString(),
      isStamp: map['isStamp'] == true,
      stampId: map['stampId']?.toString(),
      createdAt: DateTime.fromMillisecondsSinceEpoch(
        (map['createdAtMs'] as num?)?.toInt() ??
            DateTime.now().millisecondsSinceEpoch,
      ),
      isRead: map['isRead'] == true,
      readBy: rawReadBy.map((e) => e.toString()).toList(),
    );
  }
}

class CallHistoryItem {
  final String id;
  final String peerName;
  final String peerEmoji;
  final String targetUid;
  final ContactCategory category;
  final bool isVideo;
  final bool isOutgoing;
  final bool isMissed;
  final int durationSec;
  final DateTime createdAt;

  const CallHistoryItem({
    required this.id,
    required this.peerName,
    required this.peerEmoji,
    required this.targetUid,
    required this.category,
    required this.isVideo,
    required this.isOutgoing,
    this.isMissed = false,
    this.durationSec = 0,
    required this.createdAt,
  });
}

class IncomingCallPayload {
  final String callId;
  final String callerUid;
  final String callerName;
  final String callerEmoji;
  final ContactCategory category;
  final bool isVideo;
  final bool isDemo;

  const IncomingCallPayload({
    required this.callId,
    required this.callerUid,
    required this.callerName,
    required this.callerEmoji,
    required this.category,
    required this.isVideo,
    this.isDemo = false,
  });
}
