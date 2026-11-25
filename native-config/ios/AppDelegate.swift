import UIKit
import Flutter
import PushKit
import flutter_callkit_incoming

/**
 * Phase 4: iOS PushKit 完全VoIP着信対応 AppDelegate
 * ios/Runner/AppDelegate.swift をこの内容で置き換えると、
 * iPhoneがロック画面・タスクキル状態でも APNs VoIP Push 受信と同時に CallKit 着信画面が起動します。
 */
@main
@objc class AppDelegate: FlutterAppDelegate, PKPushRegistryDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)

    let mainQueue = DispatchQueue.main
    let voipRegistry = PKPushRegistry(queue: mainQueue)
    voipRegistry.delegate = self
    voipRegistry.desiredPushTypes = [PKPushType.voIP]

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func pushRegistry(
    _ registry: PKPushRegistry,
    didUpdate credentials: PKPushCredentials,
    for type: PKPushType
  ) {
    let deviceToken = credentials.token.map { String(format: "%02x", $0) }.joined()
    SwiftFlutterCallkitIncomingPlugin.sharedInstance?.setDevicePushTokenVoIP(deviceToken)
  }

  func pushRegistry(
    _ registry: PKPushRegistry,
    didInvalidatePushTokenFor type: PKPushType
  ) {
    SwiftFlutterCallkitIncomingPlugin.sharedInstance?.setDevicePushTokenVoIP("")
  }

  func pushRegistry(
    _ registry: PKPushRegistry,
    didReceiveIncomingPushWith payload: PKPushPayload,
    for type: PKPushType,
    completion: @escaping () -> Void
  ) {
    guard type == .voIP else {
      completion()
      return
    }

    let dict = payload.dictionaryPayload
    let callId = (dict["callId"] as? String) ?? UUID().uuidString
    let callerName = (dict["callerName"] as? String) ?? "着信相手"
    let callerEmoji = (dict["callerEmoji"] as? String) ?? "📞"
    let callerUid = (dict["callerUid"] as? String) ?? ""
    let category = (dict["category"] as? String) ?? "other"
    let isVideo = (dict["isVideo"] as? String) == "1"

    let catLabelMap: [String: (String, String)] = [
      "family": ("🏠", "家族"),
      "friends": ("💛", "友達"),
      "work": ("💼", "仕事関係"),
      "relatives": ("🌸", "親戚"),
      "other": ("✨", "その他"),
    ]
    let (catEmoji, catLabel) = catLabelMap[category] ?? ("✨", "その他")

    let ringtoneMap: [String: String] = [
      "family": "ring_family.wav",
      "friends": "ring_friends.wav",
      "work": "ring_work.wav",
      "relatives": "ring_relatives.wav",
      "other": "ring_other.wav",
    ]

    let data = flutter_callkit_incoming.Data(
      id: callId,
      nameCaller: "\(catEmoji)【\(catLabel)】\(callerName)",
      handle: isVideo ? "ビデオ通話の着信" : "音声通話の着信",
      type: isVideo ? 1 : 0
    )
    data.extra = [
      "callId": callId,
      "callerUid": callerUid,
      "callerName": callerName,
      "callerEmoji": callerEmoji,
      "category": category,
      "isVideo": isVideo ? "1" : "0",
    ]
    data.ringtonePath = ringtoneMap[category] ?? "system_ringtone_default"

    SwiftFlutterCallkitIncomingPlugin.sharedInstance?.showCallkitIncoming(
      data,
      fromPushKit: true
    ) {
      completion()
    }
  }
}
