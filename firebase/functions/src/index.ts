import * as admin from "firebase-admin";
import {
  onDocumentCreated,
  onDocumentDeleted,
  onDocumentUpdated,
} from "firebase-functions/v2/firestore";
import { onCall, HttpsError } from "firebase-functions/v2/https";
import { onSchedule } from "firebase-functions/v2/scheduler";
import { AccessToken } from "livekit-server-sdk";

admin.initializeApp();
const db = admin.firestore();

// 1. Send high-priority background incoming call push when a call starts
export const onCallCreated = onDocumentCreated("calls/{callId}", async (event) => {
  const data = event.data?.data();
  if (!data) return;

  const callId = event.params.callId;
  const groupId = String(data.groupId ?? "");
  const callerId = String(data.callerId ?? "");
  const groupDoc = await db.collection("groups").doc(groupId).get();
  const memberIds: string[] = (groupDoc.data()?.memberIds as string[]) ?? [];

  for (const uid of memberIds) {
    if (uid === callerId) continue;

    const settingDoc = await db
      .collection("groups")
      .doc(groupId)
      .collection("memberSettings")
      .doc(uid)
      .get();
    if (settingDoc.data()?.muted === true) continue;

    const userDoc = await db.collection("users").doc(uid).get();
    const tokens: string[] = (userDoc.data()?.fcmTokens as string[]) ?? [];
    if (tokens.length === 0) continue;

    const ringtone = String(settingDoc.data()?.ringtone ?? data.ringtone ?? "家族ベル");

    await admin.messaging().sendEachForMulticast({
      tokens,
      android: { priority: "high", ttl: 45000 },
      data: {
        type: "incoming_call",
        callId,
        groupId,
        groupName: String(data.groupName ?? "グループ通話"),
        callerName: String(data.callerName ?? "着信"),
        isVideo: String(Boolean(data.isVideo)),
        ringtone,
        roomName: String(data.roomName ?? ""),
        sentAtEpochMs: String(Date.now()),
      },
    });
  }
});

// 2. Cancel ringing on receiver devices if caller hangs up early
export const onCallUpdated = onDocumentUpdated("calls/{callId}", async (event) => {
  const after = event.data?.after.data();
  if (!after || after.status !== "ended") return;

  const groupId = String(after.groupId ?? "");
  const groupDoc = await db.collection("groups").doc(groupId).get();
  const memberIds: string[] = (groupDoc.data()?.memberIds as string[]) ?? [];

  for (const uid of memberIds) {
    const userDoc = await db.collection("users").doc(uid).get();
    const tokens: string[] = (userDoc.data()?.fcmTokens as string[]) ?? [];
    if (tokens.length === 0) continue;

    await admin.messaging().sendEachForMulticast({
      tokens,
      android: { priority: "high" },
      data: {
        type: "cancel_call",
        callId: event.params.callId,
      },
    });
  }
});

// 3. Dispatch scheduled messages every minute
export const dispatchScheduledMessages = onSchedule("every 1 minutes", async () => {
  const now = admin.firestore.Timestamp.now();
  const snap = await db
    .collection("scheduledMessages")
    .where("sendAt", "<=", now)
    .limit(50)
    .get();

  for (const doc of snap.docs) {
    const { groupId, payload } = doc.data();
    if (groupId && payload) {
      await db
        .collection("groups")
        .doc(String(groupId))
        .collection("messages")
        .doc(doc.id)
        .set({ ...payload, scheduledFor: null, createdAt: now }, { merge: true });
    }
    await doc.ref.delete();
  }
});

// 4. Automatically delete Storage files when TTL or users delete a message
export const cleanupDeletedMedia = onDocumentDeleted(
  "groups/{groupId}/messages/{messageId}",
  async (event) => {
    const data = event.data?.data();
    const storagePath = data?.media?.storagePath as string | undefined;
    if (!storagePath) return;
    try {
      await admin.storage().bucket().file(storagePath).delete();
    } catch (_) {
      // Ignore already-deleted files
    }
  }
);

// 5. Issue short-lived LiveKit room token for verified group members
export const issueLiveKitToken = onCall(async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Login required.");
  }
  const groupId = String(request.data?.groupId ?? "");
  const roomName = String(request.data?.roomName ?? `room_${groupId}`);
  const groupDoc = await db.collection("groups").doc(groupId).get();
  const members: string[] = (groupDoc.data()?.memberIds as string[]) ?? [];
  if (!members.includes(request.auth.uid)) {
    throw new HttpsError("permission-denied", "Not a group member.");
  }

  const apiKey = process.env.LIVEKIT_API_KEY ?? "";
  const apiSecret = process.env.LIVEKIT_API_SECRET ?? "";
  const at = new AccessToken(apiKey, apiSecret, {
    identity: request.auth.uid,
    ttl: "2h",
  });
  at.addGrant({ roomJoin: true, room: roomName, canPublish: true, canSubscribe: true });
  return { token: await at.toJwt(), roomName };
});
