#!/usr/bin/env node
// Uploads screenshots + app preview to App Store Connect for the current
// editable iOS version. Run AFTER push-asc-metadata.js has attached the
// build — it reads the version ID from ASC dynamically.
//
// File → display-type mapping:
//   iphone_*.png  → APP_IPHONE_69       (1320×2868)
//   ipad_*.png    → APP_IPAD_PRO_3GEN_13 (2064×2752)
//   iphone_preview.mp4 → appPreviewSet, APP_IPHONE_69
//
// Uses: fetch, crypto (for MD5 + ES256 JWT). No external deps.

const fs = require('fs');
const path = require('path');
const crypto = require('crypto');

const KEY_ID = '8BTRQ6P2YQ';
const ISSUER_ID = process.env.ASC_ISSUER_ID || 'd543c968-1d53-4a5c-b447-7470b4c36505';
const APP_ID = '6761740179';
const VERSION_STRING = '2.16';
const LOCALE = 'en-US';
const SHOTS_DIR = path.join(__dirname, '..', 'screenshots', '2.16');
const KEY_PATH = `${process.env.HOME}/.appstoreconnect/private_keys/AuthKey_${KEY_ID}.p8`;

function signJwt() {
  const header = { alg: 'ES256', kid: KEY_ID, typ: 'JWT' };
  const payload = {
    iss: ISSUER_ID,
    iat: Math.floor(Date.now() / 1000),
    exp: Math.floor(Date.now() / 1000) + 20 * 60,
    aud: 'appstoreconnect-v1',
  };
  const enc = (o) => Buffer.from(JSON.stringify(o)).toString('base64url');
  const signing = `${enc(header)}.${enc(payload)}`;
  const key = fs.readFileSync(KEY_PATH, 'utf8');
  const sig = crypto.createSign('SHA256').update(signing)
    .sign({ key, dsaEncoding: 'ieee-p1363' }).toString('base64url');
  return `${signing}.${sig}`;
}

const TOKEN = signJwt();
const BASE = 'https://api.appstoreconnect.apple.com/v1';

async function asc(method, path, body) {
  const res = await fetch(`${BASE}${path}`, {
    method,
    headers: { 'Authorization': `Bearer ${TOKEN}`, 'Content-Type': 'application/json' },
    body: body ? JSON.stringify(body) : undefined,
  });
  const text = await res.text();
  const json = text ? JSON.parse(text) : null;
  if (!res.ok) {
    console.error(`[ASC ${method} ${path}] ${res.status}\n${JSON.stringify(json, null, 2).slice(0, 1500)}`);
    throw new Error(`ASC ${method} ${path} → ${res.status}`);
  }
  return json;
}

async function uploadAsset(operations, fileBuffer) {
  // `operations` is what ASC returns for uploadOperations.
  for (const op of operations) {
    const headers = {};
    for (const h of op.requestHeaders ?? []) headers[h.name] = h.value;
    const chunk = fileBuffer.subarray(op.offset, op.offset + op.length);
    const res = await fetch(op.url, { method: op.method, headers, body: chunk });
    if (!res.ok) {
      const body = await res.text();
      throw new Error(`PUT ${op.url} → ${res.status}: ${body.slice(0, 200)}`);
    }
  }
}

async function findVersionId() {
  const res = await asc('GET', `/apps/${APP_ID}/appStoreVersions?filter[platform]=IOS&filter[versionString]=${VERSION_STRING}&limit=3`);
  const v = res.data[0];
  if (!v) throw new Error(`No ${VERSION_STRING} version on app ${APP_ID} — run push-asc-metadata.js first.`);
  return v.id;
}

async function findLocalizationId(versionId) {
  const res = await asc('GET', `/appStoreVersions/${versionId}/appStoreVersionLocalizations?limit=50`);
  const loc = res.data.find((l) => l.attributes.locale === LOCALE);
  if (!loc) throw new Error(`No ${LOCALE} localization on version ${versionId}`);
  return loc.id;
}

async function findOrCreateScreenshotSet(locId, displayType) {
  const res = await asc('GET', `/appStoreVersionLocalizations/${locId}/appScreenshotSets?limit=50`);
  const existing = res.data.find((s) => s.attributes.screenshotDisplayType === displayType);
  if (existing) return existing.id;
  const created = await asc('POST', '/appScreenshotSets', {
    data: {
      type: 'appScreenshotSets',
      attributes: { screenshotDisplayType: displayType },
      relationships: { appStoreVersionLocalization: { data: { type: 'appStoreVersionLocalizations', id: locId } } },
    },
  });
  return created.data.id;
}

async function findOrCreatePreviewSet(locId, displayType) {
  const res = await asc('GET', `/appStoreVersionLocalizations/${locId}/appPreviewSets?limit=50`);
  const existing = res.data.find((s) => s.attributes.previewType === displayType);
  if (existing) return existing.id;
  const created = await asc('POST', '/appPreviewSets', {
    data: {
      type: 'appPreviewSets',
      attributes: { previewType: displayType },
      relationships: { appStoreVersionLocalization: { data: { type: 'appStoreVersionLocalizations', id: locId } } },
    },
  });
  return created.data.id;
}

async function uploadScreenshot(setId, filePath) {
  const fileBuf = fs.readFileSync(filePath);
  const fileName = path.basename(filePath);
  const fileSize = fileBuf.length;

  // 1. Reserve
  const reserveRes = await asc('POST', '/appScreenshots', {
    data: {
      type: 'appScreenshots',
      attributes: { fileSize, fileName },
      relationships: { appScreenshotSet: { data: { type: 'appScreenshotSets', id: setId } } },
    },
  });
  const scr = reserveRes.data;
  // 2. Upload chunks
  await uploadAsset(scr.attributes.uploadOperations, fileBuf);
  // 3. Commit
  const md5 = crypto.createHash('md5').update(fileBuf).digest('hex');
  await asc('PATCH', `/appScreenshots/${scr.id}`, {
    data: {
      type: 'appScreenshots',
      id: scr.id,
      attributes: { uploaded: true, sourceFileChecksum: md5 },
    },
  });
  console.log(`  ✅ ${fileName} (${(fileSize / 1024).toFixed(0)}KB)`);
}

async function uploadPreview(setId, filePath, previewFrameTimeCode) {
  const fileBuf = fs.readFileSync(filePath);
  const fileName = path.basename(filePath);
  const fileSize = fileBuf.length;
  const mimeType = 'video/mp4';

  const reserveRes = await asc('POST', '/appPreviews', {
    data: {
      type: 'appPreviews',
      attributes: { fileSize, fileName, mimeType, previewFrameTimeCode },
      relationships: { appPreviewSet: { data: { type: 'appPreviewSets', id: setId } } },
    },
  });
  const prev = reserveRes.data;
  await uploadAsset(prev.attributes.uploadOperations, fileBuf);
  const md5 = crypto.createHash('md5').update(fileBuf).digest('hex');
  await asc('PATCH', `/appPreviews/${prev.id}`, {
    data: {
      type: 'appPreviews',
      id: prev.id,
      attributes: { uploaded: true, sourceFileChecksum: md5 },
    },
  });
  console.log(`  ✅ ${fileName} (${(fileSize / 1024).toFixed(0)}KB, preview poster @ ${previewFrameTimeCode})`);
}

async function wipeExistingAssets(setId, kind) {
  const setType = kind === 'preview' ? 'appPreviewSets' : 'appScreenshotSets';
  const childType = kind === 'preview' ? 'appPreviews' : 'appScreenshots';
  const res = await asc('GET', `/${setType}/${setId}/${childType}?limit=50`);
  for (const asset of res.data) {
    await asc('DELETE', `/${childType}/${asset.id}`);
    console.log(`  🗑  removed ${kind} ${asset.id}`);
  }
}

async function main() {
  console.log(`Uploading to App Store Connect for ${VERSION_STRING} (${LOCALE})…`);

  const versionId = await findVersionId();
  const locId = await findLocalizationId(versionId);
  console.log(`  version=${versionId}  localization=${locId}`);

  // iPhone screenshots (6.7"/6.9" category — ASC accepts 1320×2868 as APP_IPHONE_67)
  const iphoneSetId = await findOrCreateScreenshotSet(locId, 'APP_IPHONE_67');
  const iphoneShots = fs.readdirSync(SHOTS_DIR)
    .filter((f) => f.startsWith('iphone_') && f.endsWith('.png'))
    .sort();
  console.log(`\niPhone 6.9" set (${iphoneSetId}): replacing ${iphoneShots.length} screenshots`);
  await wipeExistingAssets(iphoneSetId, 'screenshot');
  for (const f of iphoneShots) {
    await uploadScreenshot(iphoneSetId, path.join(SHOTS_DIR, f));
  }

  // iPad Pro 12.9"/13" category — ASC accepts 2064×2752 as APP_IPAD_PRO_3GEN_129
  const ipadSetId = await findOrCreateScreenshotSet(locId, 'APP_IPAD_PRO_3GEN_129');
  const ipadShots = fs.readdirSync(SHOTS_DIR)
    .filter((f) => f.startsWith('ipad_') && f.endsWith('.png'))
    .sort();
  console.log(`\niPad Pro 13" set (${ipadSetId}): replacing ${ipadShots.length} screenshots`);
  await wipeExistingAssets(ipadSetId, 'screenshot');
  for (const f of ipadShots) {
    await uploadScreenshot(ipadSetId, path.join(SHOTS_DIR, f));
  }

  // iPhone app preview (6.9" — 886×1920 or 1320×2868)
  const previewPath = path.join(SHOTS_DIR, 'iphone_preview.mp4');
  if (fs.existsSync(previewPath)) {
    const previewSetId = await findOrCreatePreviewSet(locId, 'IPHONE_67');
    console.log(`\niPhone 6.9" preview set (${previewSetId}): replacing`);
    await wipeExistingAssets(previewSetId, 'preview');
    await uploadPreview(previewSetId, previewPath, '00:00:03:00');  // poster frame at t=3s
  }

  console.log('\n✅ All assets uploaded. Visit App Store Connect to verify & submit.');
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
