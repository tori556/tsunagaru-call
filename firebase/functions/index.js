const crypto = require('crypto');
const http2 = require('http2');
const { onDocumentCreated, onDocumentUpdated } = require('firebase-functions/v2/firestore');
const { onRequest } = require('firebase-functions/v2/https');
const admin = require('firebase-admin');

admin.initializeApp();
const db = admin.firestore();

function base64Url(input) {
  return Buffer.from(input)
    .toString('base64')
    .replace(/=/g, '')
    .replace(/\+/g, '-')
    .replace(/\//g, '_');
}

function createLiveKitJwt({ apiKey, apiSecret, identity, name, roomName, ttlSec = 3600 }) {
  const now = Math.floor(Date.now() / 1000);
  const header = { alg: 'HS256', typ: 'JWT' };
  const payload = {
    iss: apiKey,
    sub: identity,
    name: name || identity,
    nbf: now - 10,
    exp: now + ttlSec,
    video: {
      room: roomName,
      roomJoin: true,
      canPublish: true,
      canSubscribe: true,
      canPublishData: true,
    },
  };
  const body = `${base64Url(JSON.stringify(header))}.${base64Url(JSON.stringify(payload))}`;
  const sig = crypto
    .createHmac('sha256', apiSecret)
    .update(body)
    .digest('base64')
    .replace(/=/g, '')
    .replace(/\+/g, '-')
    .replace(/\//g, '_');
  return `${body}.${sig}`;
}

function createApnsJwt({ keyId, teamId, privateKeyPem }) {
  const header = { alg: 'ES256', kid: keyId };
  const payload = { iss: teamId, iat: Math.floor(Date.now() / 1000) };
  const signingInput = `${base64Url(JSON.stringify(header))}.${base64Url(JSON.stringify(payload))}`;
  const signer = crypto.createSign('SHA256');
  signer.update(signingInput);
  signer.end();
  const sig = signer.sign({
    key: privateKeyPem,
    dsaEncoding: 'ieee-p1363',
  });
  return `${signingInput}.${base64Url(sig)}`;
}

function sendApnsVoipPush({ voipToken, bundleId, keyId, teamId, privateKeyPem, sandbox, payload }) {
  return new Promise((resolve, reject) => {
    const host = sandbox
      ? 'https://api.sandbox.push.apple.com'
      : 'https://api.push.apple.com';
    const jwt = createApnsJwt({ keyId, teamId, privateKeyPem });
    const client = http2.connect(host);
    client.on('error', (err) => {
      client.close();
      reject(err);
    });

    const req = client.request({
      ':method': 'POST',
      ':path': `/3/device/${voipToken}`,
      authorization: `bearer ${jwt}`,
      'apns-topic': `${bundleId}.voip`,
      'apns-push-type': 'voip',
      'apns-priority': '10',
      'apns-expiration': '0',
      'content-type': 'application/json',
    });

    let statusCode = 0;
    let respData = '';
    req.on('response', (headers) => {
      statusCode = Number(headers[':status'] || 0);
    });
    req.on('data', (chunk) => {
      respData += chunk;
    });
    req.on('end', () => {
      client.close();
      if (statusCode >= 200 && statusCode < 300) {
        resolve({ ok: true, statusCode });
      } else {
        reject(new Error(`APNs VoIP error ${statusCode}: ${respData}`));
      }
    });
    req.on('error', (err) => {
      client.close();
      reject(err);
    });
    req.write(JSON.stringify(payload));
    req.end();
  });
}

// 1) 1対1 着信トリガー（iOSは完全VoIP Push優先、Androidは高優先度FCM Data）
exports.onCallCreated = onDocumentCreated(
  { document: 'calls/{callId}', region: 'asia-northeast1' },
  async (event) => {
    const data = event.data?.data();
    if (!data || data.status !== 'ringing') return;

    const calleeSnap = await db.collection('users').doc(data.calleeUid).get();
    const userData = calleeSnap.data() || {};
    const fcmToken = userData.fcmToken;
    const voipToken = userData.voipToken;
    const callId = String(event.params.callId);
    const isVideo = data.isVideo === true;

    const callPayload = {
      type: 'incoming_call',
      callId,
      callerUid: String(data.callerUid || ''),
      callerName: String(data.callerName || '着信相手'),
      callerEmoji: String(data.callerEmoji || '📞'),
      category: String(data.category || 'other'),
      isVideo: isVideo ? '1' : '0',
    };

    const apnsKeyId = process.env.APNS_KEY_ID;
    const apnsTeamId = process.env.APNS_TEAM_ID;
    const apnsBundleId = process.env.APNS_BUNDLE_ID || 'jp.tsunagarucall.app';
    const apnsKeyRaw = process.env.APNS_PRIVATE_KEY;
    const apnsSandbox = process.env.APNS_SANDBOX === 'true';

    if (voipToken && apnsKeyId && apnsTeamId && apnsKeyRaw) {
      try {
        const privateKeyPem = apnsKeyRaw.replace(/\\n/g, '\n');
        await sendApnsVoipPush({
          voipToken,
          bundleId: apnsBundleId,
          keyId: apnsKeyId,
          teamId: apnsTeamId,
          privateKeyPem,
          sandbox: apnsSandbox,
          payload: {
            aps: { 'content-available': 1 },
            ...callPayload,
          },
        });
        return;
      } catch (err) {
        console.error('APNs VoIP Push failed, fallback to FCM:', err.message);
      }
    }

    if (!fcmToken) return;
    await admin.messaging().send({
      token: fcmToken,
      data: callPayload,
      android: { priority: 'high', ttl: 30000 },
      apns: {
        headers: { 'apns-priority': '10' },
        payload: {
          aps: {
            alert: {
              title: `📞 ${data.callerName || '着信'}`,
              body: isVideo ? 'ビデオ通話がかかっています' : '音声通話がかかっています',
            },
            sound: 'default',
            'content-available': 1,
            'interruption-level': 'time-sensitive',
          },
        },
      },
    });
  }
);

// 2) 1対1トーク新着通知
exports.onChatMessageCreated = onDocumentCreated(
  { document: 'chats/{chatId}/messages/{msgId}', region: 'asia-northeast1' },
  async (event) => {
    const data = event.data?.data();
    if (!data || !data.receiverUid) return;

    const receiverSnap = await db.collection('users').doc(data.receiverUid).get();
    const fcmToken = receiverSnap.data()?.fcmToken;
    if (!fcmToken) return;

    const bodyText = data.imageUrl
      ? '📷 写真を送信しました'
      : (data.isStamp ? `【スタンプ】${data.text || ''}` : String(data.text || '新着メッセージ'));

    await admin.messaging().send({
      token: fcmToken,
      notification: {
        title: `💬 ${data.senderName || '新着メッセージ'}`,
        body: bodyText,
      },
      data: {
        type: 'chat_message',
        chatId: String(event.params.chatId),
      },
      android: { priority: 'high' },
      apns: { payload: { aps: { sound: 'default' } } },
    });
  }
);

// 3) グループトーク新着通知
exports.onGroupMessageCreated = onDocumentCreated(
  { document: 'groups/{groupId}/messages/{msgId}', region: 'asia-northeast1' },
  async (event) => {
    const data = event.data?.data();
    if (!data) return;

    const groupSnap = await db.collection('groups').doc(event.params.groupId).get();
    const groupData = groupSnap.data();
    if (!groupData || !Array.isArray(groupData.memberUids)) return;

    const targetUids = groupData.memberUids.filter((u) => u !== data.senderUid);
    if (!targetUids.length) return;

    const userDocs = await Promise.all(
      targetUids.map((uid) => db.collection('users').doc(uid).get())
    );
    const tokens = userDocs
      .map((s) => s.data()?.fcmToken)
      .filter((t) => typeof t === 'string' && t.length > 0);
    if (!tokens.length) return;

    const bodyText = data.imageUrl
      ? `${data.senderName || 'メンバー'}: 📷 写真を送信しました`
      : `${data.senderName || 'メンバー'}: ${data.isStamp ? '【スタンプ】' : ''}${data.text || ''}`;

    await admin.messaging().sendEachForMulticast({
      tokens,
      notification: {
        title: `👥 ${groupData.name || 'グループトーク'}`,
        body: bodyText,
      },
      data: {
        type: 'group_message',
        groupId: String(event.params.groupId),
      },
      android: { priority: 'high' },
      apns: { payload: { aps: { sound: 'default' } } },
    });
  }
);

// 4) グループ通話開始通知
exports.onGroupCallStarted = onDocumentUpdated(
  { document: 'groups/{groupId}', region: 'asia-northeast1' },
  async (event) => {
    const beforeCall = event.data?.before?.data()?.activeCall;
    const afterData = event.data?.after?.data();
    const afterCall = afterData?.activeCall;

    if (beforeCall || !afterCall) return;
    if (!Array.isArray(afterData.memberUids)) return;

    const starterUids = afterCall.activeParticipantUids || [];
    const targetUids = afterData.memberUids.filter((u) => !starterUids.includes(u));
    if (!targetUids.length) return;

    const userDocs = await Promise.all(
      targetUids.map((uid) => db.collection('users').doc(uid).get())
    );
    const tokens = userDocs
      .map((s) => s.data()?.fcmToken)
      .filter((t) => typeof t === 'string' && t.length > 0);
    if (!tokens.length) return;

    const kind = afterCall.isVideo ? 'グループビデオ通話' : 'グループ音声通話';
    await admin.messaging().sendEachForMulticast({
      tokens,
      notification: {
        title: `📞 ${afterData.name || 'グループ'}で通話開始`,
        body: `${afterCall.startedByName || 'メンバー'}が${kind}を開始しました。タップして参加できます。`,
      },
      data: {
        type: 'group_call_started',
        groupId: String(event.params.groupId),
        roomName: String(afterCall.roomName || ''),
        isVideo: afterCall.isVideo ? '1' : '0',
      },
      android: { priority: 'high' },
      apns: {
        headers: { 'apns-priority': '10' },
        payload: { aps: { sound: 'default', 'interruption-level': 'time-sensitive' } },
      },
    });
  }
);

// 5) LiveKit SFU アクセスJWTトークン発行
exports.issueLiveKitToken = onRequest(
  { cors: true, region: 'asia-northeast1' },
  async (req, res) => {
    if (req.method !== 'POST') {
      res.status(405).send({ error: 'Method Not Allowed' });
      return;
    }
    const apiKey = process.env.LIVEKIT_API_KEY;
    const apiSecret = process.env.LIVEKIT_API_SECRET;
    if (!apiKey || !apiSecret) {
      res.status(500).send({ error: 'LIVEKIT_API_KEY / LIVEKIT_API_SECRET が未設定です' });
      return;
    }
    const { roomName, identity, name } = req.body || {};
    if (!roomName || !identity) {
      res.status(400).send({ error: 'roomName and identity are required' });
      return;
    }
    const token = createLiveKitJwt({
      apiKey,
      apiSecret,
      identity: String(identity),
      name: String(name || identity),
      roomName: String(roomName),
    });
    res.status(200).send({ token });
  }
);

// 6) Phase 4 追加: TURN サーバー一時クレデンシャル自動発行
exports.issueTurnCredentials = onRequest(
  { cors: true, region: 'asia-northeast1' },
  async (req, res) => {
    const rawUrls = (process.env.TURN_URLS || '')
      .split(',')
      .map((s) => s.trim())
      .filter(Boolean);
    if (!rawUrls.length) {
      res.status(200).send({ iceServers: [] });
      return;
    }

    const authSecret = process.env.TURN_AUTH_SECRET;
    if (authSecret) {
      const uid = String(req.body?.uid || 'user').replace(/[^a-zA-Z0-9_-]/g, '');
      const expiry = Math.floor(Date.now() / 1000) + 12 * 3600;
      const username = `${expiry}:${uid}`;
      const credential = crypto
        .createHmac('sha1', authSecret)
        .update(username)
        .digest('base64');
      res.status(200).send({
        iceServers: [{ urls: rawUrls, username, credential }],
      });
      return;
    }

    res.status(200).send({
      iceServers: [
        {
          urls: rawUrls,
          username: process.env.TURN_USERNAME || '',
          credential: process.env.TURN_CREDENTIAL || '',
        },
      ],
    });
  }
);
