"use strict";

// ============ READ-ONLY AUDIT: DEAD STORAGE REFERENCES ============
//
// Walks EVERY Firestore collection (recursively, subcollections included),
// finds every string value that points at a Cloud Storage object, and checks
// whether that object still exists in the bucket. Written after the default
// bucket (libsk-b68f5.firebasestorage.app) was deleted and recreated empty on
// 2026-09-16.
//
// Detection is by VALUE, not by field name, so it also catches fields nobody
// remembered. Recognised shapes:
//   https://firebasestorage.googleapis.com/v0/b/<bucket>/o/<path>?alt=media&token=<t>
//   https://storage.googleapis.com/<bucket>/<path>
//   https://<bucket>.storage.googleapis.com/<path>
//   gs://<bucket>/<path>
//   bare "<folder>/..." paths under the app's upload folders (StorageService)
//
// Known fields at time of writing (for orientation — the scan does not rely
// on this list):
//   boutiques/{b}                  logoPath, bannerPath                  SOURCE
//   boutiques/{b}/products/{p}     imageUrl, imageUrls[], sizeGuideUrl   SOURCE
//   promo_bookings/{id}            bannerImageUrl                        SOURCE
//   hero_banners/{id}              imageUrl (editorial = SOURCE,
//                                  promo-published = COPY of the booking)
//   users/{u}/saved_items          imageUrl, imageUrls[]                 COPY
//   users/{u}/saved_boutiques      imageUrl                              COPY
//   users/{u}/carts/{b}            boutiqueLogoUrl                       COPY
//   users/{u}/carts/{b}/items      imageUrl                              COPY
//   users/{u}/orders, boutiques/{b}/orders, global_orders
//                                  items[].imageUrl                      COPY
// SOURCE = what the boutique/admin re-uploads through the app. COPY = a
// denormalised snapshot that is NOT refreshed by a re-upload; it stays broken
// until the bucket is restored or the copy is backfilled.
//
// Per reference the status is one of:
//   OK              object exists and (for download URLs) the URL's token is
//                   still one of the object's download tokens
//   MISSING         object is not in the bucket
//   TOKEN_MISMATCH  object exists but the URL's token is not one of its
//                   download tokens (e.g. file re-uploaded at same path). The
//                   URL then only works while storage.rules allows public read
//                   on that path — every current upload folder does.
//   NO_BUCKET       the referenced bucket does not exist
//   CHECK_FAILED    the existence check itself errored (see detail)
//
// SAFETY:
//   * READ-ONLY. Firestore: listCollections / listDocuments / getAll only.
//     Storage: bucket.exists / file.getMetadata only. Nothing is written,
//     updated, nulled or deleted — in Firestore or in Storage.
//   * The only writes are the local report files in OUT_DIR.
//   * Runs against LIVE Firestore + Storage via Application Default
//     Credentials:
//       gcloud auth application-default login
//       gcloud config set project libsk-b68f5
//
// USAGE (from functions/):
//   node scripts/audit-storage-refs.js
//   OUT_DIR=/some/dir node scripts/audit-storage-refs.js
//   SKIP_COLLECTIONS=rate_limits,promo_click_events node scripts/audit-storage-refs.js
//
// OUTPUT (OUT_DIR, default <repo>/build/storage-audit/<timestamp>/ — gitignored):
//   report.txt   the console report (grouped by boutique)
//   broken.csv   one row per non-OK reference
//   report.json  every reference found (OK ones included) + scan stats

const admin = require("firebase-admin");
const fs = require("fs");
const path = require("path");

const PROJECT = process.env.GCLOUD_PROJECT || "libsk-b68f5";
const DEFAULT_BUCKET = process.env.STORAGE_BUCKET || `${PROJECT}.firebasestorage.app`;
const SKIP_COLLECTIONS = new Set(
  String(process.env.SKIP_COLLECTIONS || "").split(",").map((s) => s.trim()).filter(Boolean),
);
const OUT_DIR = process.env.OUT_DIR || path.join(
  __dirname, "..", "..", "build", "storage-audit",
  new Date().toISOString().replace(/[:.]/g, "-"),
);
const GET_ALL_CHUNK = 100;
const CHECK_CONCURRENCY = 16;

// Folders StorageService uploads into. The first four plus promo_banners are
// "<folder>/<boutiqueId>/<file>"; hero_banners is "<folder>/<file>".
const UPLOAD_FOLDERS = [
  "product_images", "size_guides", "boutique_logos",
  "boutique_banners", "promo_banners", "hero_banners",
];
const BOUTIQUE_SCOPED_FOLDERS = new Set(UPLOAD_FOLDERS.filter((f) => f !== "hero_banners"));

if (process.env.FIRESTORE_EMULATOR_HOST || process.env.FIREBASE_STORAGE_EMULATOR_HOST) {
  console.error(
    "Refusing to run: an emulator host env var is set. This audit targets live " +
    "Firestore + Storage. Unset FIRESTORE_EMULATOR_HOST / FIREBASE_STORAGE_EMULATOR_HOST.",
  );
  process.exit(1);
}

admin.initializeApp({ projectId: PROJECT });
const db = admin.firestore();
const storage = admin.storage();

// ─────────────────────────── reference parsing ───────────────────────────

function safeDecode(s) {
  try {
    return decodeURIComponent(s);
  } catch (_) {
    return s;
  }
}

function parseStorageRef(value) {
  if (typeof value !== "string") return null;
  const s = value.trim();
  let m;
  m = s.match(/^https?:\/\/firebasestorage\.googleapis\.com\/v0\/b\/([^/]+)\/o\/([^?#]+)(?:\?([^#]*))?/i);
  if (m) {
    const token = new URLSearchParams(m[3] || "").get("token");
    return { kind: "download_url", bucket: m[1], objectPath: safeDecode(m[2]), token };
  }
  m = s.match(/^https?:\/\/storage\.googleapis\.com\/([^/]+)\/([^?#]+)/i);
  if (m) return { kind: "gcs_url", bucket: m[1], objectPath: safeDecode(m[2]), token: null };
  m = s.match(/^https?:\/\/([^/]+)\.storage\.googleapis\.com\/([^?#]+)/i);
  if (m) return { kind: "gcs_url", bucket: m[1], objectPath: safeDecode(m[2]), token: null };
  m = s.match(/^gs:\/\/([^/]+)\/(.+)$/i);
  if (m) return { kind: "gs_uri", bucket: m[1], objectPath: m[2], token: null };
  m = s.match(new RegExp(`^/?((?:${UPLOAD_FOLDERS.join("|")})/[^?#\\s]+)$`));
  if (m) return { kind: "bare_path", bucket: DEFAULT_BUCKET, objectPath: m[1], token: null };
  return null;
}

// ─────────────────────────── Firestore walk ───────────────────────────

function isPlainMap(v) {
  return v !== null && typeof v === "object" && Object.getPrototypeOf(v) === Object.prototype;
}

// Yields every string leaf with its field path and the nearest enclosing
// `boutiqueId` (order line items carry their own).
function* stringLeaves(value, fieldPath, nearestBoutiqueId) {
  if (typeof value === "string") {
    yield { fieldPath, value, nearestBoutiqueId };
  } else if (Array.isArray(value)) {
    for (let i = 0; i < value.length; i++) {
      yield* stringLeaves(value[i], `${fieldPath}[${i}]`, nearestBoutiqueId);
    }
  } else if (isPlainMap(value)) {
    const bid = typeof value.boutiqueId === "string" && value.boutiqueId
      ? value.boutiqueId : nearestBoutiqueId;
    for (const [k, v] of Object.entries(value)) {
      yield* stringLeaves(v, fieldPath ? `${fieldPath}.${k}` : k, bid);
    }
  }
  // Timestamp, GeoPoint, DocumentReference, Bytes, etc. hold no URLs.
}

// "boutiques/abc/products/xyz" → "boutiques/*/products"
function collectionPattern(docPath) {
  const segs = docPath.split("/");
  return segs.slice(0, -1).map((s, i) => (i % 2 === 1 ? "*" : s)).join("/");
}

function classifyRole(docPath, data) {
  const segs = docPath.split("/");
  const top = segs[0];
  if (top === "boutiques" && segs.length === 2) return "SOURCE";
  if (top === "boutiques" && segs[2] === "products" && segs.length === 4) return "SOURCE";
  if (top === "promo_bookings" && segs.length === 2) return "SOURCE";
  if (top === "hero_banners" && segs.length === 2) return data.promoBookingId ? "COPY" : "SOURCE";
  if (top === "users" || top === "global_orders") return "COPY";
  if (top === "boutiques" && segs[2] === "orders") return "COPY";
  return "OTHER";
}

function resolveBoutique(docPath, data, nearestBoutiqueId, ref) {
  const segs = docPath.split("/");
  if (segs[0] === "boutiques") return segs[1];
  if (nearestBoutiqueId) return nearestBoutiqueId;
  const pathSegs = ref.objectPath.split("/");
  if (BOUTIQUE_SCOPED_FOLDERS.has(pathSegs[0]) && pathSegs.length >= 3) return pathSegs[1];
  if (segs[0] === "hero_banners") return "_platform";
  return "_unattributed";
}

const stats = { collections: {}, docsScanned: 0, missingParentDocs: 0 };
const refs = [];

async function scanCollection(collRef) {
  const docRefs = await collRef.listDocuments(); // includes "missing" parent docs
  for (let i = 0; i < docRefs.length; i += GET_ALL_CHUNK) {
    const chunk = docRefs.slice(i, i + GET_ALL_CHUNK);
    const snaps = await db.getAll(...chunk);
    for (const snap of snaps) {
      const pattern = collectionPattern(snap.ref.path);
      stats.collections[pattern] = (stats.collections[pattern] || 0) + 1;
      if (!snap.exists) {
        stats.missingParentDocs += 1;
        continue;
      }
      stats.docsScanned += 1;
      const data = snap.data() || {};
      const docBoutiqueId = typeof data.boutiqueId === "string" ? data.boutiqueId : null;
      for (const leaf of stringLeaves(data, "", docBoutiqueId)) {
        const ref = parseStorageRef(leaf.value);
        if (!ref) continue;
        refs.push({
          boutiqueId: resolveBoutique(snap.ref.path, data, leaf.nearestBoutiqueId, ref),
          role: classifyRole(snap.ref.path, data),
          collection: pattern,
          docPath: snap.ref.path,
          docId: snap.id,
          field: leaf.fieldPath,
          url: leaf.value,
          ...ref,
        });
      }
    }
    for (const docRef of chunk) {
      for (const sub of await docRef.listCollections()) {
        if (!SKIP_COLLECTIONS.has(sub.id)) await scanCollection(sub);
      }
    }
  }
}

// ─────────────────────────── Storage checks ───────────────────────────

const bucketExistsCache = new Map();
async function bucketExists(name) {
  if (!bucketExistsCache.has(name)) {
    bucketExistsCache.set(name, storage.bucket(name).exists().then(([e]) => e));
  }
  return bucketExistsCache.get(name);
}

const objectCache = new Map();
function objectInfo(bucket, objectPath) {
  const key = `${bucket}/${objectPath}`;
  if (!objectCache.has(key)) {
    objectCache.set(key, (async () => {
      if (!(await bucketExists(bucket))) return { state: "NO_BUCKET" };
      try {
        const [meta] = await storage.bucket(bucket).file(objectPath).getMetadata();
        const tokens = String((meta.metadata || {}).firebaseStorageDownloadTokens || "")
          .split(",").map((t) => t.trim()).filter(Boolean);
        return { state: "EXISTS", tokens };
      } catch (e) {
        if (e.code === 404) return { state: "MISSING" };
        return { state: "CHECK_FAILED", detail: `${e.code || ""} ${e.message}`.trim() };
      }
    })());
  }
  return objectCache.get(key);
}

async function checkAll() {
  let next = 0;
  async function worker() {
    while (next < refs.length) {
      const r = refs[next++];
      const info = await objectInfo(r.bucket, r.objectPath);
      if (info.state === "EXISTS") {
        r.status = r.kind === "download_url" && r.token && !info.tokens.includes(r.token)
          ? "TOKEN_MISMATCH" : "OK";
      } else {
        r.status = info.state;
        if (info.detail) r.detail = info.detail;
      }
    }
  }
  await Promise.all(Array.from({ length: CHECK_CONCURRENCY }, worker));
}

// ─────────────────────────── report ───────────────────────────

function csvCell(v) {
  const s = v === undefined || v === null ? "" : String(v);
  return /[",\n]/.test(s) ? `"${s.replace(/"/g, '""')}"` : s;
}

async function main() {
  const startedAt = new Date().toISOString();
  const lines = [];
  const out = (s = "") => {
    console.log(s);
    lines.push(s);
  };

  out(`Storage reference audit — READ-ONLY — project ${PROJECT}`);
  out(`Default bucket: gs://${DEFAULT_BUCKET}   started ${startedAt}`);
  if (SKIP_COLLECTIONS.size) out(`Skipping collections: ${[...SKIP_COLLECTIONS].join(", ")}`);
  out();

  const boutiqueNames = {};
  (await db.collection("boutiques").get()).forEach((d) => {
    boutiqueNames[d.id] = (d.data() || {}).name || "";
  });

  for (const coll of await db.listCollections()) {
    if (!SKIP_COLLECTIONS.has(coll.id)) await scanCollection(coll);
  }
  await checkAll();

  const byStatus = {};
  for (const r of refs) byStatus[r.status] = (byStatus[r.status] || 0) + 1;
  const broken = refs.filter((r) => r.status !== "OK");
  const bucketsSeen = [...new Set(refs.map((r) => r.bucket))];

  out(`Scanned ${stats.docsScanned} docs across ${Object.keys(stats.collections).length} collection paths` +
      ` (${stats.missingParentDocs} phantom parent docs skipped).`);
  out(`Storage references found: ${refs.length}  (unique objects: ${objectCache.size})`);
  out(`By status: ${Object.entries(byStatus).map(([k, v]) => `${k}=${v}`).join("  ") || "none"}`);
  out(`Buckets referenced: ${bucketsSeen.map((b) => `gs://${b}`).join(", ") || "none"}`);
  out();

  const groups = {};
  for (const r of broken) (groups[r.boutiqueId] ||= []).push(r);
  const order = Object.keys(groups).sort((a, b) =>
    (a.startsWith("_") - b.startsWith("_")) || a.localeCompare(b));

  for (const bid of order) {
    const rows = groups[bid];
    const label = bid.startsWith("_") ? bid : `${boutiqueNames[bid] || "(unknown boutique)"} [${bid}]`;
    out("════════════════════════════════════════════════════════════════════");
    out(`${label} — ${rows.length} broken reference(s)`);
    for (const role of ["SOURCE", "COPY", "OTHER"]) {
      const rr = rows.filter((r) => r.role === role);
      if (!rr.length) continue;
      const heading = {
        SOURCE: "SOURCE — needs re-upload through the app (or bucket restore)",
        COPY: "COPY — denormalised snapshot; not fixed by a re-upload",
        OTHER: "OTHER — unclassified location, review manually",
      }[role];
      out(`  ${heading}`);
      rr.sort((a, b) => a.docPath.localeCompare(b.docPath) || a.field.localeCompare(b.field));
      for (const r of rr) {
        out(`    [${r.status}] ${r.collection}  doc=${r.docId}  field=${r.field}`);
        out(`        path: ${r.objectPath}${r.bucket !== DEFAULT_BUCKET ? `  (bucket ${r.bucket})` : ""}`);
        out(`        url:  ${r.url}`);
        if (r.detail) out(`        detail: ${r.detail}`);
      }
    }
    const files = [...new Set(rows.filter((r) => r.role === "SOURCE").map((r) => r.objectPath))];
    if (files.length) out(`  → ${files.length} distinct file(s) to request from this boutique`);
    out();
  }
  if (!broken.length) out("No broken references. ✔");

  out("Docs scanned per collection path:");
  for (const [k, v] of Object.entries(stats.collections).sort()) out(`  ${k}: ${v}`);

  fs.mkdirSync(OUT_DIR, { recursive: true });
  fs.writeFileSync(path.join(OUT_DIR, "report.txt"), lines.join("\n") + "\n");
  const cols = ["boutiqueId", "boutiqueName", "role", "status", "collection", "docPath",
    "docId", "field", "bucket", "objectPath", "url", "detail"];
  const csv = [cols.join(",")].concat(broken.map((r) =>
    cols.map((c) => csvCell(c === "boutiqueName" ? boutiqueNames[r.boutiqueId] : r[c])).join(",")));
  fs.writeFileSync(path.join(OUT_DIR, "broken.csv"), csv.join("\n") + "\n");
  fs.writeFileSync(path.join(OUT_DIR, "report.json"), JSON.stringify({
    project: PROJECT, defaultBucket: DEFAULT_BUCKET, startedAt,
    finishedAt: new Date().toISOString(), stats, byStatus, boutiqueNames, refs,
  }, null, 2));
  console.log(`\nReport files written to ${OUT_DIR}`);
}

main().catch((e) => {
  console.error("Audit failed:", e);
  process.exit(1);
});
