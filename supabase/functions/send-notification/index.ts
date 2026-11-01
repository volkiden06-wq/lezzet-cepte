import webpush from "npm:web-push@3.6.7";

const corsHeaders = {
  "Access-Control-Allow-Origin": "https://yemektadinda.com",
  "Access-Control-Allow-Headers": "authorization, apikey, content-type, x-client-info",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Content-Type": "application/json",
};

const json = (status: number, body: Record<string, unknown>) =>
  new Response(JSON.stringify(body), { status, headers: corsHeaders });

function constantTimeEqual(left: string, right: string): boolean {
  const a = new TextEncoder().encode(left);
  const b = new TextEncoder().encode(right);
  let difference = a.length ^ b.length;
  const length = Math.max(a.length, b.length);
  for (let i = 0; i < length; i++) {
    difference |= (a[i] ?? 0) ^ (b[i] ?? 0);
  }
  return difference === 0;
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json(405, { error: "Yalnızca POST desteklenir." });

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  const vapidPublicKey = Deno.env.get("VAPID_PUBLIC_KEY");
  const vapidPrivateKey = Deno.env.get("VAPID_PRIVATE_KEY");
  const vapidSubject = Deno.env.get("VAPID_SUBJECT");
  const orderHookSecret = Deno.env.get("ORDER_PUSH_HOOK_SECRET");

  if (![supabaseUrl, anonKey, serviceRoleKey, vapidPublicKey, vapidPrivateKey, vapidSubject, orderHookSecret].every(Boolean)) {
    return json(503, { error: "Bildirim sunucusu ayarları eksik. Function Secrets bölümünü kontrol edin." });
  }

  try {
    const input = await req.json();
    let title = "";
    let body = "";
    let image = "";
    let targetUrl = "https://yemektadinda.com/";
    let tag = "yemek-tadinda-campaign";

    if (input?.type === "order") {
      const suppliedSecret = req.headers.get("x-order-hook-secret") || "";
      if (!constantTimeEqual(suppliedSecret, orderHookSecret!)) {
        return json(401, { error: "Sipariş bildirimi doğrulanamadı." });
      }

      const record = input.record || {};
      const orderNumber = String(record.order_number || "").trim().slice(0, 80);
      const customerName = String(record.customer_name || "Yeni müşteri").trim().slice(0, 60);
      const total = Number(record.total) || 0;
      if (!orderNumber) return json(400, { error: "Sipariş numarası eksik." });

      title = "YENİ SİPARİŞ ALINDI";
      body = "#" + orderNumber + " · " + customerName + " · " +
        new Intl.NumberFormat("tr-TR", { maximumFractionDigits: 0 }).format(total) + " TL";
      tag = "yemek-tadinda-order-" + orderNumber;
    } else {
      const auth = req.headers.get("Authorization") || "";
      if (!auth.startsWith("Bearer ")) return json(401, { error: "Yönetici oturumu gerekli." });
      const token = auth.slice(7);
      const adminCheck = await fetch(`${supabaseUrl}/rest/v1/rpc/is_admin`, {
        method: "POST",
        headers: { apikey: anonKey!, Authorization: `Bearer ${token}`, "Content-Type": "application/json" },
        body: "{}",
      });
      if (!adminCheck.ok || await adminCheck.json() !== true) {
        return json(403, { error: "Bu işlem için yönetici yetkisi gerekli." });
      }

      title = String(input.title || "").trim().slice(0, 80);
      body = String(input.body || "").trim().slice(0, 220);
      image = typeof input.image === "string" ? input.image : "";
      targetUrl = typeof input.url === "string" && input.url.startsWith("https://yemektadinda.com")
        ? input.url : "https://yemektadinda.com/";
      if (!title || !body) return json(400, { error: "Bildirim başlığı ve mesajı zorunludur." });
    }

    const rowsResponse = await fetch(
      `${supabaseUrl}/rest/v1/push_subscriptions?select=id,subscription`,
      { headers: { apikey: serviceRoleKey!, Authorization: `Bearer ${serviceRoleKey}` } },
    );
    if (!rowsResponse.ok) throw new Error("Bildirim abonelikleri okunamadı: " + await rowsResponse.text());
    const rows = await rowsResponse.json();

    webpush.setVapidDetails(vapidSubject!, vapidPublicKey!, vapidPrivateKey!);
    let sent = 0;
    let failed = 0;
    const expired: number[] = [];

    for (const row of rows) {
      try {
        await webpush.sendNotification(
          row.subscription,
          JSON.stringify({ title, body, image, url: targetUrl, tag, orderNumber: input?.record?.order_number || null }),
          { TTL: 86400 },
        );
        sent++;
      } catch (error) {
        failed++;
        const status = (error as { statusCode?: number }).statusCode;
        console.error("PUSH_DELIVERY_ERROR", {
          statusCode: status,
          message: (error as Error).message,
          subscriptionId: row.id,
        });
        if (status === 404 || status === 410) expired.push(row.id);
      }
    }

    if (expired.length) {
      await fetch(`${supabaseUrl}/rest/v1/push_subscriptions?id=in.(${expired.join(",")})`, {
        method: "DELETE",
        headers: { apikey: serviceRoleKey!, Authorization: `Bearer ${serviceRoleKey}` },
      });
    }

    return json(200, { success: failed === 0, sent, failed, total: rows.length });
  } catch (error) {
    console.error("send-notification:", error);
    return json(500, { error: (error as Error).message || "Bildirim gönderimi başarısız." });
  }
});
