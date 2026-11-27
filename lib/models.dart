const String appBuildNumberStr = String.fromEnvironment(
  'APP_BUILD_NUMBER',
  defaultValue: '1',
);
const String githubRepo = String.fromEnvironment(
  'GITHUB_REPO',
  defaultValue: '',
);

const List<String> ringtoneOptions = <String>[
  '標準チャイム',
  '家族ベル',
  'やさしい木琴',
  '親戚メロディ',
  '仕事用トーン',
];

const List<int> expireChoices = <int>[0, 1, 3, 12, 24];
const List<String> reactionEmojis = <String>['👍', '❤️', '😂', '🙏', '👀'];

const List> stampCatalog = >[
  <String, String>{'emoji': '👌', 'label': 'りょうかい！'},
  <String, String>{'emoji': '🙏', 'label': 'ありがとう！'},
  <String, String>{'emoji': '🏠', 'label': 'いま帰るよ'},
  <String, String>{'emoji': '📞', 'label': 'あとで電話するね'},
  <String, String>{'emoji': '🍱', 'label': 'ごはんできたよ'},
  <String, String>{'emoji': '🚗', 'label': 'もうすぐ着くよ'},
  <String, String>{'emoji': '☀️', 'label': 'おはよう！'},
  <String, String>{'emoji': '🌙', 'label': 'おやすみ'},
];

/// Safely extracts the first Unicode code point (prevents crashes on empty/emoji strings).
String initialLetter(String text) {
  final trimmed = text.trim();
  if (trimmed.isEmpty) return '?';
  return String.fromCharCode(trimmed.runes.first);
}

String formatExpireLabel(int hours) => hours <= 0 ? '消えない' : '$hours時間';

String formatBytes(int? bytes) {
  if (bytes == null || bytes <= 0) return '';
  if (bytes < 1024) return '${bytes}B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)}KB';
  if (bytes < 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)}MB';
  }
  return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)}GB';
}

DateTime? parseFlexibleDateTime(dynamic value) {
  if (value == null) return null;
  if (value is DateTime) return value;
  if (value is String) return DateTime.tryParse(value);
  if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
  try {
    final dynamic d = (value as dynamic).toDate();
    if (d is DateTime) return d;
  } catch (_) {}
  return null;
}

class UpdateInfo {
  const UpdateInfo({
    required this.buildNumber,
    required this.versionName,
    required this.notes,
    required this.apkUrl,
  });

  final int buildNumber;
  final String versionName;
  final String notes;
  final String apkUrl;
}

class MemberProfile {
  const MemberProfile({
    required this.inviteId,
    required this.name,
    this.uid,
  });

  final String inviteId;
  final String name;
  final String? uid;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'inviteId': inviteId,
        'name': name,
        'uid': uid,
      };

  factory MemberProfile.fromJson(Map<String, dynamic> json) => MemberProfile(
        inviteId: (json['inviteId'] as String?) ?? '',
        name: (json['name'] as String?) ?? 'メンバー',
        uid: json['uid'] as String?,
      );
}

class PollData {
  PollData({
    required this.question,
    required this.options,
    required this.votes,
  });

  final String question;
  final List<String> options;
  final Map<String, List<String>> votes;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'question': question,
        'options': options,
        'votes': votes,
      };

  factory PollData.fromJson(Map<String, dynamic> json) {
    final raw = (json['votes'] as Map<String, dynamic>?) ?? <String, dynamic>{};
    final parsed = <String, List<String>>{};
    raw.forEach((String k, dynamic v) {
      parsed[k] = ((v as List<dynamic>?) ?? const <dynamic>[])
          .map((dynamic e) => e.toString())
          .toList();
    });
    return PollData(
      question: (json['question'] as String?) ?? '',
      options: ((json['options'] as List<dynamic>?) ?? const <dynamic>[])
          .map((dynamic e) => e.toString())
          .toList(),
      votes: parsed,
    );
  }
}

class MediaAttachment {
  const MediaAttachment({
    required this.fileName,
    this.localPath,
    this.remoteUrl,
    this.storagePath,
    this.fileSizeBytes,
    this.durationSec,
    this.isTemporaryCache = false,
  });

  final String fileName;
  final String? localPath;
  final String? remoteUrl;
  final String? storagePath;
  final int? fileSizeBytes;
  final int? durationSec;
  final bool isTemporaryCache;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'fileName': fileName,
        'localPath': localPath,
        'remoteUrl': remoteUrl,
        'storagePath': storagePath,
        'fileSizeBytes': fileSizeBytes,
        'durationSec': durationSec,
        'isTemporaryCache': isTemporaryCache,
      };

  factory MediaAttachment.fromJson(Map<String, dynamic> json) =>
      MediaAttachment(
        fileName: (json['fileName'] as String?) ?? 'file',
        localPath: json['localPath'] as String?,
        remoteUrl: json['remoteUrl'] as String?,
        storagePath: json['storagePath'] as String?,
        fileSizeBytes: (json['fileSizeBytes'] as num?)?.toInt(),
        durationSec: (json['durationSec'] as num?)?.toInt(),
        isTemporaryCache: (json['isTemporaryCache'] as bool?) ?? false,
      );
}

class ChatMessage {
  ChatMessage({
    required this.id,
    required this.sender,
    this.senderId,
    required this.text,
    required this.createdAt,
    this.kind = 'text',
    this.edited = false,
    this.deletedForAll = false,
    this.silent = false,
    this.forwardedFrom,
    this.replyToId,
    this.replyPreview,
    this.media,
    this.viewOncePhoto = false,
    List<String>? viewedOnceBy,
    this.expiresAt,
    this.scheduledFor,
    List<String>? readBy,
    Map<String, List<String>>? reactions,
    this.poll,
  })  : viewedOnceBy = viewedOnceBy ?? <String>[],
        readBy = readBy ?? <String>[],
        reactions = reactions ?? <String, List<String>>{};

  final String id;
  final String sender;
  final String? senderId;
  String text;
  final DateTime createdAt;
  final String kind; // text | stamp | voice | video | photo | file
  bool edited;
  bool deletedForAll;
  final bool silent;
  final String? forwardedFrom;
  final String? replyToId;
  final String? replyPreview;
  MediaAttachment? media;
  final bool viewOncePhoto;
  final List<String> viewedOnceBy;
  final DateTime? expiresAt;
  final DateTime? scheduledFor;
  final List<String> readBy;
  final Map<String, List<String>> reactions;
  final PollData? poll;

  bool isExpired(DateTime now) => expiresAt != null && now.isAfter(expiresAt!);

  bool isViewedOnceBy(String viewerKey) => viewedOnceBy.contains(viewerKey);

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'sender': sender,
        'senderId': senderId,
        'text': text,
        'createdAt': createdAt.toIso8601String(),
        'kind': kind,
        'edited': edited,
        'deletedForAll': deletedForAll,
        'silent': silent,
        'forwardedFrom': forwardedFrom,
        'replyToId': replyToId,
        'replyPreview': replyPreview,
        'media': media?.toJson(),
        'viewOncePhoto': viewOncePhoto,
        'viewedOnceBy': viewedOnceBy,
        'expiresAt': expiresAt?.toIso8601String(),
        'scheduledFor': scheduledFor?.toIso8601String(),
        'readBy': readBy,
        'reactions': reactions,
        'poll': poll?.toJson(),
      };

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    final rawReacts =
        (json['reactions'] as Map<String, dynamic>?) ?? <String, dynamic>{};
    final parsedReacts = <String, List<String>>{};
    rawReacts.forEach((String k, dynamic v) {
      parsedReacts[k] = ((v as List<dynamic>?) ?? const <dynamic>[])
          .map((dynamic e) => e.toString())
          .toList();
    });

    final viewedList =
        ((json['viewedOnceBy'] as List<dynamic>?) ?? const <dynamic>[])
            .map((dynamic e) => e.toString())
            .toList();
    // Legacy compatibility
    if (viewedList.isEmpty && (json['viewedOnce'] as bool?) == true) {
      viewedList.add('legacy_viewed');
    }

    return ChatMessage(
      id: (json['id'] as String?) ??
          DateTime.now().microsecondsSinceEpoch.toString(),
      sender: (json['sender'] as String?) ??
          (json['senderName'] as String?) ??
          'メンバー',
      senderId: json['senderId'] as String?,
      text: (json['text'] as String?) ?? '',
      createdAt: parseFlexibleDateTime(json['createdAt']) ?? DateTime.now(),
      kind: (json['kind'] as String?) ?? 'text',
      edited: (json['edited'] as bool?) ?? false,
      deletedForAll: (json['deletedForAll'] as bool?) ?? false,
      silent: (json['silent'] as bool?) ?? false,
      forwardedFrom: json['forwardedFrom'] as String?,
      replyToId: json['replyToId'] as String?,
      replyPreview: json['replyPreview'] as String?,
      media: json['media'] != null
          ? MediaAttachment.fromJson(
              Map<String, dynamic>.from(json['media'] as Map),
            )
          : null,
      viewOncePhoto: (json['viewOncePhoto'] as bool?) ?? false,
      viewedOnceBy: viewedList,
      expiresAt: parseFlexibleDateTime(json['expiresAt']),
      scheduledFor: parseFlexibleDateTime(json['scheduledFor']),
      readBy: ((json['readBy'] as List<dynamic>?) ?? const <dynamic>[])
          .map((dynamic e) => e.toString())
          .toList(),
      reactions: parsedReacts,
      poll: json['poll'] != null
          ? PollData.fromJson(Map<String, dynamic>.from(json['poll'] as Map))
          : null,
    );
  }
}

class ChatGroup {
  ChatGroup({
    required this.id,
    required this.name,
    required this.category,
    required this.members,
    List<String>? memberUids,
    this.muted = false,
    this.ringtone = '標準チャイム',
    this.pinnedMessageId,
    this.draft = '',
    List<ChatMessage>? messages,
    List<ChatMessage>? scheduledMessages,
  })  : memberUids = memberUids ?? <String>[],
        messages = messages ?? <ChatMessage>[],
        scheduledMessages = scheduledMessages ?? <ChatMessage>[];

  final String id;
  final String name;
  final String category;
  final List<String> members;
  final List<String> memberUids;
  bool muted;
  String ringtone;
  String? pinnedMessageId;
  String draft;
  final List<ChatMessage> messages;
  final List<ChatMessage> scheduledMessages;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'name': name,
        'category': category,
        'members': members,
        'memberUids': memberUids,
        'muted': muted,
        'ringtone': ringtone,
        'pinnedMessageId': pinnedMessageId,
        'draft': draft,
        'messages': messages.map((m) => m.toJson()).toList(),
        'scheduledMessages': scheduledMessages.map((m) => m.toJson()).toList(),
      };

  factory ChatGroup.fromJson(Map<String, dynamic> json) => ChatGroup(
        id: (json['id'] as String?) ?? 'group',
        name: (json['name'] as String?) ?? 'グループ',
        category: (json['category'] as String?) ?? '家族',
        members: ((json['members'] as List<dynamic>?) ?? const <dynamic>[])
            .map((dynamic e) => e.toString())
            .toList(),
        memberUids:
            ((json['memberUids'] as List<dynamic>?) ??
                    (json['memberIds'] as List<dynamic>?) ??
                    const <dynamic>[])
                .map((dynamic e) => e.toString())
                .toList(),
        muted: (json['muted'] as bool?) ?? false,
        ringtone: (json['ringtone'] as String?) ?? '標準チャイム',
        pinnedMessageId: json['pinnedMessageId'] as String?,
        draft: (json['draft'] as String?) ?? '',
        messages: ((json['messages'] as List<dynamic>?) ?? const <dynamic>[])
            .map((dynamic e) =>
                ChatMessage.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
        scheduledMessages: ((json['scheduledMessages'] as List<dynamic>?) ??
                const <dynamic>[])
            .map((dynamic e) =>
                ChatMessage.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
      );
}

class IncomingCallPayload {
  const IncomingCallPayload({
    required this.callId,
    required this.groupId,
    required this.groupName,
    required this.callerName,
    required this.isVideo,
    required this.ringtone,
    required this.sentAtEpochMs,
    this.roomName,
  });

  final String callId;
  final String groupId;
  final String groupName;
  final String callerName;
  final bool isVideo;
  final String ringtone;
  final int sentAtEpochMs;
  final String? roomName;

  bool get isStale =>
      DateTime.now().millisecondsSinceEpoch - sentAtEpochMs > 45000;

  Map<String, dynamic> toMap() => <String, dynamic>{
        'callId': callId,
        'groupId': groupId,
        'groupName': groupName,
        'callerName': callerName,
        'isVideo': isVideo.toString(),
        'ringtone': ringtone,
        'sentAtEpochMs': sentAtEpochMs.toString(),
        'roomName': roomName ?? '',
      };

  factory IncomingCallPayload.fromMap(Map<String, dynamic> map) =>
      IncomingCallPayload(
        callId: (map['callId'] ?? '').toString(),
        groupId: (map['groupId'] ?? 'family').toString(),
        groupName: (map['groupName'] ?? '家族ルーム').toString(),
        callerName: (map['callerName'] ?? '着信').toString(),
        isVideo: (map['isVideo'] ?? 'false').toString() == 'true',
        ringtone: (map['ringtone'] ?? '家族ベル').toString(),
        sentAtEpochMs: int.tryParse((map['sentAtEpochMs'] ?? '').toString()) ??
            DateTime.now().millisecondsSinceEpoch,
        roomName: (map['roomName'] ?? '').toString().isEmpty
            ? null
            : map['roomName'].toString(),
      );
}
