import { gzipSync, strToU8 } from "npm:fflate@0.8.2";

const BUCKET_ID = "yemektadinda-backups";
const TABLES = [
  "site_catalog",
  "orders",
  "order_history_archive",
  "admin_users",
  "loyalty_accounts",
  "loyalty_transactions",
  "product_reviews",
  "push_subscriptions",
  "admin_push_subscriptions",
  "customer_order_push_links",
  "site_daily_visitors",
  "catalog_sync_events",
  "personnel",
  "personnel_months",
  "personnel_attendance",
];
const ALLOWED_ORIGINS = new Set([
  "https://yemektadinda.com",
  "https://www.yemektadinda.com",
]);

function headers(origin: string | null) {
  return {
    "Access-Control-Allow-Origin": origin && ALLOWED_ORIGINS.has(origin) ? origin : "https://yemektadinda.com",
    "Access-Control-Allow-Headers": "authorization, apikey, content-type, x-backup-token",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
    "Access-Control-Max-Age": "86400",
    "Vary": "Origin",
    "Content-Type": "application/json",
  };
}
function reply(status: number, payload: Record<string, unknown>, origin: string | null) {
  return new Response(JSON.stringify(payload), { status, headers: headers(origin) });
}
function pathUrl(path: string) {
  return path.split("/").map(encodeURIComponent).join("/");
}
async function readTable(url: string, serviceKey: string, table: string) {
  const rows: unknown[] = [];
  const pageSize = 500;
  for (let offset = 0; offset < 100000; offset += pageSize) {
    const response = await fetch(url + "/rest/v1/" + table + "?select=*", {
      headers: {
        apikey: serviceKey,
        Authorization: "Bearer " + serviceKey,
        "Range-Unit": "items",
        Range: offset + "-" + (offset + pageSize - 1),
        Prefer: "count=exact",
      },
    });
    if (!response.ok) {
      throw new Error("Tablo yedeklenemedi (" + table + "): " + response.status + " " + (await response.text()).slice(0, 300));
    }
    const page = await response.json();
    if (!Array.isArray(page)) throw new Error("Beklenmeyen tablo yanıtı: " + table);
    rows.push(...page);
    if (page.length < pageSize) break;
  }
  return rows;
}
async function listObjects(
  url: string,
  serviceKey: string,
  bucket: string,
  prefix = "",
  depth = 0,
): Promise<Array<{ bucket: string; path: string; content_type: string; bytes: number }>> {
  if (depth > 12) throw new Error("Görsel klasör yapısı çok derin.");
  const output: Array<{ bucket: string; path: string; content_type: string; bytes: number }> = [];
  let offset = 0;
  const limit = 100;
  while (true) {
    const response = await fetch(url + "/storage/v1/object/list/" + encodeURIComponent(bucket), {
      method: "POST",
      headers: {
        apikey: serviceKey,
        Authorization: "Bearer " + serviceKey,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        prefix, limit, offset,
        sortBy: { column: "name", order: "asc" },
      }),
    });
    if (!response.ok) throw new Error("Görsel deposu listelenemedi (" + bucket + "): " + response.status);
    const items = await response.json();
    if (!Array.isArray(items)) throw new Error("Görsel deposu listesi hatalı.");
    for (const item of items) {
      const name = String(item.name || "");
      if (!name || name === "." || name === "..") continue;
      const objectPath = prefix ? prefix.replace(/\/$/, "") + "/" + name : name;
      const folder = (item.id == null && item.metadata == null) || item.type === "folder";
      if (folder) {
        output.push(...await listObjects(url, serviceKey, bucket, objectPath, depth + 1));
      } else {
        output.push({
          bucket,
          path: objectPath,
          content_type: String(item.metadata?.mimetype || item.metadata?.contentType || "application/octet-stream"),
          bytes: Number(item.metadata?.size || 0),
        });
      }
    }
    if (items.length < limit) break;
    offset += items.length;
  }
  return output;
}
async function uploadPrivate(
  url: string,
  serviceKey: string,
  path: string,
  body: BodyInit,
  contentType: string,
  upsert: boolean,
) {
  const response = await fetch(url + "/storage/v1/object/" + BUCKET_ID + "/" + pathUrl(path), {
    method: "POST",
    headers: {
      apikey: serviceKey,
      Authorization: "Bearer " + serviceKey,
      "Content-Type": contentType,
      "x-upsert": upsert ? "true" : "false",
      "cache-control": "31536000",
    },
    body,
  });
  if (!response.ok) {
    throw new Error("Özel yedek alanına yazılamadı: " + response.status + " " + (await response.text()).slice(0, 300));
  }
}
async function logRun(url: string, serviceKey: string, record: Record<string, unknown>) {
  const response = await fetch(url + "/rest/v1/site_backup_runs", {
    method: "POST",
    headers: {
      apikey: serviceKey,
      Authorization: "Bearer " + serviceKey,
      "Content-Type": "application/json",
      Prefer: "return=minimal",
    },
    body: JSON.stringify(record),
  });
  if (!response.ok) console.error("BACKUP_RUN_LOG_FAILED", response.status, await response.text());
}
async function pruneOldDatabaseArchives(url: string, serviceKey: string) {
  const response = await fetch(
    url + "/rest/v1/site_backup_runs?status=eq.success&select=archive_path,database_path&order=created_at.desc&offset=30&limit=100",
    { headers: { apikey: serviceKey, Authorization: "Bearer " + serviceKey } },
  );
  if (!response.ok) {
    console.warn("BACKUP_RETENTION_LIST_FAILED", response.status);
    return;
  }
  const oldRuns = await response.json();
  if (!Array.isArray(oldRuns) || oldRuns.length === 0) return;
  const paths = oldRuns.flatMap((run: { archive_path?: string; database_path?: string }) =>
    [run.archive_path, run.database_path].filter((path): path is string => typeof path === "string" && path.length > 0)
  );
  if (!paths.length) return;
  const deleted = await fetch(url + "/storage/v1/object/" + BUCKET_ID, {
    method: "DELETE",
    headers: {
      apikey: serviceKey,
      Authorization: "Bearer " + serviceKey,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({ prefixes: paths }),
  });
  if (!deleted.ok) console.warn("BACKUP_RETENTION_DELETE_FAILED", deleted.status, await deleted.text());
}

Deno.serve(async (req: Request) => {
  const origin = req.headers.get("Origin");
  if (req.method === "OPTIONS") return new Response("ok", { headers: headers(origin) });
  if (req.method !== "POST") return reply(405, { error: "POST gerekli." }, origin);
  if (origin && !ALLOWED_ORIGINS.has(origin)) return reply(403, { error: "Bu alandan erişime izin verilmiyor." }, origin);

  const url = Deno.env.get("SUPABASE_URL") || "";
  const anon = Deno.env.get("SUPABASE_ANON_KEY") || "";
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") || "";
  if (![url, anon, serviceKey].every(Boolean)) return reply(503, { error: "Yedekleme sunucusu ayarları eksik." }, origin);

  const bearer = (req.headers.get("Authorization") || "").replace(/^Bearer\s+/i, "");
  const scheduledSecret = req.headers.get("x-backup-token") || "";
  let authorized = false;
  if (scheduledSecret) {
    const check = await fetch(url + "/rest/v1/rpc/verify_yemektadinda_backup_token", {
      method: "POST",
      headers: { apikey: serviceKey, Authorization: "Bearer " + serviceKey, "Content-Type": "application/json" },
      body: JSON.stringify({ p_token: scheduledSecret }),
    });
    authorized = check.ok && (await check.json()) === true;
  } else if (bearer) {
    const check = await fetch(url + "/rest/v1/rpc/is_admin", {
      method: "POST",
      headers: { apikey: anon, Authorization: "Bearer " + bearer, "Content-Type": "application/json" },
      body: "{}",
    });
    authorized = check.ok && (await check.json()) === true;
  }
  if (!authorized) return reply(401, { error: "Bulut yedeği için yönetici girişi gerekli." }, origin);

  const started = Date.now();
  let manifestPath = "";
  let databasePath = "";
  let tableCount = 0;
  let rowCount = 0;
  let storageFileCount = 0;
  let storageBytes = 0;
  try {
    const now = new Date();
    const stamp = now.toISOString().replace(/[:.]/g, "-");
    const day = now.toISOString().slice(0, 10);
    const prefix = "daily/" + day + "/";
    const database: Record<string, unknown[]> = {};
    for (const table of TABLES) {
      const rows = await readTable(url, serviceKey, table);
      database[table] = rows;
      tableCount++;
      rowCount += rows.length;
    }

    const databaseCompressed = gzipSync(strToU8(JSON.stringify({
      format: "YEMEK_TADINDA_DATABASE_BACKUP",
      version: 1,
      created_at: now.toISOString(),
      project_ref: "jlpqdjhxdpmighnpebkj",
      tables: database,
      counts: { table_count: tableCount, row_count: rowCount },
    })), { level: 6 });
    databasePath = prefix + "YEMEK-TADINDA-DATABASE-" + stamp + ".json.gz";
    await uploadPrivate(url, serviceKey, databasePath, databaseCompressed, "application/gzip", false);

    const bucketResponse = await fetch(url + "/storage/v1/bucket", {
      headers: { apikey: serviceKey, Authorization: "Bearer " + serviceKey },
    });
    if (!bucketResponse.ok) throw new Error("Görsel alanları okunamadı: " + bucketResponse.status);
    const buckets = await bucketResponse.json();
    if (!Array.isArray(buckets)) throw new Error("Görsel alanı listesi hatalı.");

    const backupBuckets = buckets.filter((bucket: { id?: string }) => bucket.id && bucket.id !== BUCKET_ID);
    const assetEntries: Array<{ source_bucket: string; source_path: string; backup_path: string; bytes: number; content_type: string }> = [];

    // Copy assets one at a time so large image collections never sit in memory together.
    for (const bucket of backupBuckets) {
      const bucketName = String(bucket.id);
      const objects = await listObjects(url, serviceKey, bucketName);
      for (const object of objects) {
        const download = await fetch(
          url + "/storage/v1/object/authenticated/" + encodeURIComponent(bucketName) + "/" + pathUrl(object.path),
          { headers: { apikey: serviceKey, Authorization: "Bearer " + serviceKey } },
        );
        if (!download.ok) throw new Error("Görsel okunamadı (" + bucketName + "/" + object.path + "): " + download.status);
        const asset = await download.arrayBuffer();
        const backupPath = "assets/" + bucketName + "/" + object.path;
        await uploadPrivate(url, serviceKey, backupPath, asset, object.content_type, true);
        const bytes = asset.byteLength;
        storageBytes += bytes;
        storageFileCount++;
        assetEntries.push({
          source_bucket: bucketName,
          source_path: object.path,
          backup_path: backupPath,
          bytes,
          content_type: object.content_type,
        });
      }
    }

    manifestPath = prefix + "YEMEK-TADINDA-MANIFEST-" + stamp + ".json";
    const manifest = {
      format: "YEMEK_TADINDA_BACKUP_MANIFEST",
      version: 1,
      created_at: now.toISOString(),
      project_ref: "jlpqdjhxdpmighnpebkj",
      database_path: databasePath,
      asset_mirror_path: "assets/",
      asset_files: assetEntries,
      counts: { table_count: tableCount, row_count: rowCount, storage_file_count: storageFileCount, storage_bytes: storageBytes },
      note: "Database snapshot is time-stamped. Asset mirror keeps the latest copy of each stored image in the private backup bucket.",
    };
    const manifestText = JSON.stringify(manifest, null, 2);
    await uploadPrivate(url, serviceKey, manifestPath, strToU8(manifestText), "application/json", false);

    const archiveBytes = databaseCompressed.byteLength + new TextEncoder().encode(manifestText).byteLength;
    await logRun(url, serviceKey, {
      status: "success",
      archive_path: manifestPath,
      database_path: databasePath,
      table_count: tableCount,
      row_count: rowCount,
      storage_file_count: storageFileCount,
      archive_bytes: archiveBytes,
      error_message: null,
    });
    await pruneOldDatabaseArchives(url, serviceKey);

    return reply(200, {
      success: true,
      message: "Bulut yedeği başarıyla oluşturuldu.",
      manifest_path: manifestPath,
      database_path: databasePath,
      table_count: tableCount,
      row_count: rowCount,
      storage_file_count: storageFileCount,
      storage_bytes: storageBytes,
      database_bytes: databaseCompressed.byteLength,
      duration_ms: Date.now() - started,
    }, origin);
  } catch (error) {
    const message = error instanceof Error ? error.message : "Bilinmeyen yedekleme hatası.";
    await logRun(url, serviceKey, {
      status: "failed",
      archive_path: manifestPath || null,
      database_path: databasePath || null,
      table_count: tableCount,
      row_count: rowCount,
      storage_file_count: storageFileCount,
      archive_bytes: 0,
      error_message: message.slice(0, 1000),
    });
    console.error("YEMEKTADINDA_CLOUD_BACKUP_FAILED", message);
    return reply(500, { success: false, error: message }, origin);
  }
});
