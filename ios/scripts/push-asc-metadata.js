#!/usr/bin/env node
// Pushes wAIpoint 2.16 metadata to App Store Connect:
//   1. Creates (or finds) iOS version 2.16 on app 6761740179.
//   2. Updates English localization's `whatsNew`, `promotionalText`, `description`,
//      `keywords`, `supportUrl`, `marketingUrl`.
//   3. Attaches the just-uploaded build to the version (by version string +
//      build number match against preReleaseVersions → builds).
//
// We do NOT submit for review from the script — export compliance + content
// rights attestations should be clicked by a human in App Store Connect.
//
// Usage:
//   node ios/scripts/push-asc-metadata.js [--build=29]
//
// Requires:
//   - Node 18+ (global fetch)
//   - `npm i jsonwebtoken` in backend/ (we shell out to it)
//   - API key at ~/.appstoreconnect/private_keys/AuthKey_8BTRQ6P2YQ.p8
//   - Env: ASC_ISSUER_ID (from ~/.keys.sh)

const fs = require('fs');
const path = require('path');
const crypto = require('crypto');

const KEY_ID = '8BTRQ6P2YQ';
const ISSUER_ID = process.env.ASC_ISSUER_ID || 'd543c968-1d53-4a5c-b447-7470b4c36505';
const APP_ID = '6761740179';  // wAIpoint — from altool logs
const KEY_PATH = `${process.env.HOME}/.appstoreconnect/private_keys/AuthKey_${KEY_ID}.p8`;
const VERSION_STRING = '2.16';
const BUILD_NUMBER = process.argv.find((a) => a.startsWith('--build='))?.split('=')[1] || '29';

// ── Minimal ES256 JWT for ASC API ────────────────────────────────────────────
function signJwt() {
  const header = { alg: 'ES256', kid: KEY_ID, typ: 'JWT' };
  const payload = {
    iss: ISSUER_ID,
    iat: Math.floor(Date.now() / 1000),
    exp: Math.floor(Date.now() / 1000) + 20 * 60,
    aud: 'appstoreconnect-v1',
  };
  const enc = (o) => Buffer.from(JSON.stringify(o)).toString('base64url');
  const headerB64 = enc(header);
  const payloadB64 = enc(payload);
  const signingInput = `${headerB64}.${payloadB64}`;

  const keyPem = fs.readFileSync(KEY_PATH, 'utf8');
  const signer = crypto.createSign('SHA256');
  signer.update(signingInput);
  // Apple wants a raw (r|s) 64-byte signature, not DER. Node's sign() returns
  // DER by default — we pass `dsaEncoding: 'ieee-p1363'` to get raw.
  const sig = signer.sign({ key: keyPem, dsaEncoding: 'ieee-p1363' });
  return `${signingInput}.${sig.toString('base64url')}`;
}

const TOKEN = signJwt();
const BASE = 'https://api.appstoreconnect.apple.com/v1';

async function asc(method, path, body) {
  const res = await fetch(`${BASE}${path}`, {
    method,
    headers: {
      'Authorization': `Bearer ${TOKEN}`,
      'Content-Type': 'application/json',
    },
    body: body ? JSON.stringify(body) : undefined,
  });
  const text = await res.text();
  const json = text ? JSON.parse(text) : null;
  if (!res.ok) {
    console.error(`[ASC ${method} ${path}] ${res.status}`, JSON.stringify(json, null, 2));
    throw new Error(`ASC API ${method} ${path} → ${res.status}`);
  }
  return json;
}

// ── Metadata drafts ──────────────────────────────────────────────────────────
const WHATS_NEW = `Location-aware driving tours are here.

• Start a tour from anywhere — when you're far from the first stop, wAIpoint now plays a dynamically generated "drive-to" narration and then seamlessly hands off to the pre-written tour narration the moment you arrive. A status banner shows live distance and ETA.

• Adaptive follow-ups — on long drives we space 2-3 mini bridges across the ride so you never sit in silence. Each one uses a different device: a fact, a sensory hook, a pop-culture tie.

• Accurate ETAs powered by Google Directions — real road-based time, not straight-line estimates.

• Featured tours — hand-curated showcase tours you can play for free. Miami's Golden Hour (2-hour drive) and Miami's Canvas (4-hour walk) are live now. More cities coming.

• Gold-standard visual treatment — featured tours carry a gold border + sparkle pill so you can tell them apart from user-shared tours.

• Instant playback for featured tours — pre-generated audio, no "Preparing your tour" delay.

• Make it your own — one tap clones any featured or community tour into your library so you can edit stops and narration.

• Segment list during navigation — a new menu in the player shows every segment with progress. Tap any to skip to it.

• Small UX fixes: community visibility toggle now sticks on first tap; community tours load reliably; Start/End toggles in Advanced search fit cleanly in portrait.`;

const PROMOTIONAL_TEXT = `Location-aware audio tours that know when you're still on the road and when you've arrived. Featured tours of Miami are free. Make any tour your own.`;

const DESCRIPTION = `wAIpoint is your private AI tour guide. Open the app, pick a city or featured tour, and drive or walk — the narration follows you.

FEATURED TOURS (free)
• Hand-curated showcase tours with professionally-written narration, premium voice, and photos of every stop.
• Miami's Golden Hour — a 2-hour driving tour across the causeways, Wynwood, and Vizcaya at golden hour.
• Miami's Canvas — a 4-hour walking tour through South Beach's Art Deco district and Wynwood's murals.
• Gold badge on every featured tour so you know you're getting the full experience.

LOCATION-AWARE NARRATION
• Start a tour from anywhere — we know the difference between "at your house" and "at the first stop."
• If you're still driving, wAIpoint plays a live introduction while you travel, then seamlessly switches to the pre-written tour the moment you arrive.
• Follow-up mini bridges keep long drives entertaining without ever repeating the same opening.

CUSTOM TOURS (subscription)
• Type any city, set a duration, pick themes (history, food, scenic, hidden gems, architecture…) and we'll generate a bespoke tour in minutes.
• Works by car, on foot, by bike, or even by boat.
• Save unlimited tours to your library and re-play any time.

MAKE ANY TOUR YOUR OWN
• Tap a featured or community tour, then "Make it your own" — we clone it into your library so you can edit stops, tweak narration, and re-share.

BUILT FOR THE DRIVE
• Accurate arrival detection via turn-by-turn navigation.
• Segment list with tap-to-skip.
• Offline download so tours play without a signal.
• Premium Google TTS voice — warm, natural, not robotic.
• Passenger Mode for the back seat.

SHARE WITH FRIENDS
• Every tour gets a shareable link. If your friends have the app, they open right in it; if not, they can preview on the web.
• Community tab surfaces the highest-rated public tours, sorted by Top / Recent / Trending.

Subscription unlocks unlimited custom tour generation, voice picker, offline downloads. Featured tours remain free forever.`;

const KEYWORDS = 'audio tour,city tour,travel,road trip,AI,driving,miami,walking tour,podcast,narration,gps';
const SUPPORT_URL = 'https://waipoint.o11r.com/support';
const MARKETING_URL = 'https://waipoint.o11r.com';
const PROMOTIONAL_SUBTITLE = 'AI audio tours for the road';  // 27 chars (≤30)

// ── Flow ─────────────────────────────────────────────────────────────────────
async function main() {
  console.log(`Using ASC API with key ${KEY_ID}, issuer ${ISSUER_ID.slice(0, 8)}…`);

  // 1. Find the editable version. If one exists in PREPARE_FOR_SUBMISSION /
  //    DEVELOPER_REJECTED / REJECTED, reuse & rename it; if not, create fresh.
  //    ASC only allows one editable version at a time, so creating 2.16 when
  //    2.13 is still editable returns 409.
  const EDITABLE_STATES = new Set([
    'PREPARE_FOR_SUBMISSION', 'DEVELOPER_REJECTED', 'REJECTED',
    'METADATA_REJECTED', 'INVALID_BINARY',
  ]);
  const versionsRes = await asc('GET', `/apps/${APP_ID}/appStoreVersions?filter[platform]=IOS&limit=50`);
  let version = versionsRes.data.find((v) => v.attributes.versionString === VERSION_STRING);
  const editable = versionsRes.data.find((v) => EDITABLE_STATES.has(v.attributes.appStoreState));
  if (!version && editable) {
    console.log(`Reusing editable version ${editable.attributes.versionString} → renaming to ${VERSION_STRING}…`);
    const patched = await asc('PATCH', `/appStoreVersions/${editable.id}`, {
      data: {
        type: 'appStoreVersions',
        id: editable.id,
        attributes: { versionString: VERSION_STRING },
      },
    });
    version = patched.data;
  } else if (!version) {
    console.log(`Creating new version ${VERSION_STRING}…`);
    const created = await asc('POST', '/appStoreVersions', {
      data: {
        type: 'appStoreVersions',
        attributes: { platform: 'IOS', versionString: VERSION_STRING, releaseType: 'MANUAL' },
        relationships: { app: { data: { type: 'apps', id: APP_ID } } },
      },
    });
    version = created.data;
  }
  console.log(`  version.id = ${version.id} (state: ${version.attributes.appStoreState})`);

  // 2. Find build by pre-release version + build number.
  const buildsRes = await asc('GET',
    `/builds?filter[app]=${APP_ID}&filter[version]=${BUILD_NUMBER}&filter[preReleaseVersion.platform]=IOS&filter[preReleaseVersion.version]=${VERSION_STRING}&limit=5`);
  const build = buildsRes.data[0];
  if (!build) {
    console.error(`No build ${BUILD_NUMBER} for ${VERSION_STRING} yet. Upload may still be processing — try again in 5 minutes.`);
    process.exit(2);
  }
  console.log(`  build.id = ${build.id} (processed: ${build.attributes.processingState})`);

  // 3. Attach build to version (idempotent).
  console.log('Attaching build to version…');
  await asc('PATCH', `/appStoreVersions/${version.id}/relationships/build`, {
    data: { type: 'builds', id: build.id },
  });

  // 4. Patch the version's attributes.
  await asc('PATCH', `/appStoreVersions/${version.id}`, {
    data: {
      type: 'appStoreVersions',
      id: version.id,
      attributes: { releaseType: 'MANUAL' },
    },
  });

  // 5. Update the en-US localization (create if missing).
  const locsRes = await asc('GET', `/appStoreVersions/${version.id}/appStoreVersionLocalizations?limit=50`);
  let enLoc = locsRes.data.find((l) => l.attributes.locale === 'en-US');
  const locAttrs = {
    whatsNew: WHATS_NEW,
    promotionalText: PROMOTIONAL_TEXT,
    description: DESCRIPTION,
    keywords: KEYWORDS,
    supportUrl: SUPPORT_URL,
    marketingUrl: MARKETING_URL,
  };
  if (!enLoc) {
    console.log('Creating en-US localization…');
    const created = await asc('POST', '/appStoreVersionLocalizations', {
      data: {
        type: 'appStoreVersionLocalizations',
        attributes: { locale: 'en-US', ...locAttrs },
        relationships: { appStoreVersion: { data: { type: 'appStoreVersions', id: version.id } } },
      },
    });
    enLoc = created.data;
  } else {
    console.log('Patching en-US localization…');
    await asc('PATCH', `/appStoreVersionLocalizations/${enLoc.id}`, {
      data: { type: 'appStoreVersionLocalizations', id: enLoc.id, attributes: locAttrs },
    });
  }
  console.log(`  localization.id = ${enLoc.id}`);

  // 6. Update the app's global promotional subtitle (appInfoLocalizations).
  // Subtitle lives on appInfo, not the version — it rolls into the next submission.
  const appInfoRes = await asc('GET', `/apps/${APP_ID}/appInfos?limit=5`);
  const editableAppInfo = appInfoRes.data.find(
    (i) => i.attributes.appStoreState === 'PREPARE_FOR_SUBMISSION'
      || i.attributes.appStoreState === 'DEVELOPER_REJECTED'
      || i.attributes.appStoreState === 'REJECTED'
  ) || appInfoRes.data[0];
  if (editableAppInfo) {
    const infoLocsRes = await asc('GET', `/appInfos/${editableAppInfo.id}/appInfoLocalizations?limit=50`);
    const enInfoLoc = infoLocsRes.data.find((l) => l.attributes.locale === 'en-US');
    if (enInfoLoc) {
      console.log('Patching en-US subtitle…');
      await asc('PATCH', `/appInfoLocalizations/${enInfoLoc.id}`, {
        data: {
          type: 'appInfoLocalizations',
          id: enInfoLoc.id,
          attributes: { subtitle: PROMOTIONAL_SUBTITLE },
        },
      });
    }
  }

  console.log('\n✅ Metadata push complete.');
  console.log(`   Review in App Store Connect:`);
  console.log(`   https://appstoreconnect.apple.com/apps/${APP_ID}/appstore/ios/version/${version.id}`);
  console.log('\n   Remaining manual steps:');
  console.log('   1. Upload/verify screenshots (6.7", 6.5", 5.5" iPhone + 12.9", 11" iPad).');
  console.log('   2. Attest Export Compliance + Content Rights + IDFA.');
  console.log('   3. Click "Add for Review" → "Submit to App Review".');
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
