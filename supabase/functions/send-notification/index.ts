import webpush from "npm:web-push@3.6.7";

const corsHeaders = {
  "Access-Control-Allow-Origin": "https://yemektadinda.com",
  "Access-Control-Allow-Headers": "authorization, apikey, content-type, x-client-info",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Content-Type": "application/json",
};

const json = (status: number, body: Record<string, unknown>) =>
  new Response(JSON.stringify(body), { status, headers: corsHeaders });

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json(405, { error: "Yalnızca POST desteklenir." });

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  const vapidPublicKey = Deno.env.get("VAPID_PUBLIC_KEY");
  const vapidPrivateKey = Deno.env.get("VAPID_PRIVATE_KEY");
  const vapidSubject = Deno.env.get("VAPID_SUBJECT");

  if (![supabaseUrl, anonKey, serviceRoleKey, vapidPublicKey, vapidPrivateKey, vapidSubject].every(Boolean)) {
    return json(503, { error: "Bildirim sunucusunun gizli ayarları tamamlanmamış." });
  }

  const auth = req.headers.get("Authorization") || "";
  if (!auth.startsWith("Bearer ")) return json(401, { error: "Yönetici oturumu gerekli." });
  const token = auth.slice(7);

  try {
    const adminCheck = await fetch(`${supabaseUrl}/rest/v1/rpc/is_admin`, {
      method: "POST",
      headers: { apikey: anonKey!, Authorization: `Bearer ${token}`, "Content-Type": "application/json" },
      body: "{}",
    });
    if (!adminCheck.ok || await adminCheck.json() !== true) {
      return json(403, { error: "Bu işlem için yönetici yetkisi gerekli." });
    }

    const input = await req.json();
    const title = String(input.title || "").trim().slice(0, 80);
    const body = String(input.body || "").trim().slice(0, 220);
    const image = typeof input.image === "string" ? input.image : "";
    const targetUrl = typeof input.url === "string" && input.url.startsWith("https://yemektadinda.com")
      ? input.url : "https://yemektadinda.com/";

    if (!title || !body) return json(400, { error: "Bildirim başlığı ve mesajı zorunludur." });

    const rowsResponse = await fetch(`${supabaseUrl}/rest/v1/push_subscriptions?select=id,subscription`, {
      headers: { apikey: serviceRoleKey!, Authorization: `Bearer ${serviceRoleKey}` },
    });
    if (!rowsResponse.ok) throw new Error("Bildirim abonelikleri okunamadı.");
    const rows = await rowsResponse.json();

    webpush.setVapidDetails(vapidSubject!, vapidPublicKey!, vapidPrivateKey!);
    let sent = 0;
    let failed = 0;
    const expired: number[] = [];

    for (const row of rows) {
      try {
        await webpush.sendNotification(
          row.subscription,
          JSON.stringify({ title, body, image, url: targetUrl, tag: "yemek-tadinda-campaign" }),
          { TTL: 86400 },
        );
        sent++;
      } catch (error) {
        failed++;
        const status = (error as { statusCode?: number }).statusCode;
        if (status === 404 || status === 410) expired.push(row.id);
      }
    }

    if (expired.length) {
      await fetch(`${supabaseUrl}/rest/v1/push_subscriptions?id=in.(${expired.join(",")})`, {
        method: "DELETE",
        headers: { apikey: serviceRoleKey!, Authorization: `Bearer ${serviceRoleKey}` },
      });
    }

    return json(200, { sent, failed, total: rows.length });
  } catch (error) {
    console.error("send-notification:", error);
    return json(500, { error: (error as Error).message || "Bildirim gönderimi başarısız." });
  }
});
