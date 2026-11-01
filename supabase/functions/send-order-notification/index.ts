import webpush from "npm:web-push@3.6.7";

const headers = {
  "Access-Control-Allow-Origin": "https://yemektadinda.com",
  "Access-Control-Allow-Headers": "content-type, x-order-hook-secret",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Content-Type": "application/json",
};

const reply = (status: number, payload: Record<string, unknown>) =>
  new Response(JSON.stringify(payload), { status, headers });

function constantTimeEqual(aText: string, bText: string): boolean {
  const a = new TextEncoder().encode(aText);
  const b = new TextEncoder().encode(bText);
  let diff = a.length ^ b.length;
  for (let i = 0; i < Math.max(a.length, b.length); i++) {
    diff |= (a[i] ?? 0) ^ (b[i] ?? 0);
  }
  return diff === 0;
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers });
  if (req.method !== "POST") return reply(405, { error: "POST required." });

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  const hookSecret = Deno.env.get("ORDER_PUSH_HOOK_SECRET");
  const vapidPublicKey = Deno.env.get("VAPID_PUBLIC_KEY");
  const vapidPrivateKey = Deno.env.get("VAPID_PRIVATE_KEY");
  const vapidSubject = Deno.env.get("VAPID_SUBJECT");

  if (![supabaseUrl, serviceRoleKey, hookSecret, vapidPublicKey, vapidPrivateKey, vapidSubject].every(Boolean)) {
    return reply(503, { error: "Missing Edge Function secrets." });
  }

  const suppliedSecret = req.headers.get("x-order-hook-secret") || "";
  if (!constantTimeEqual(suppliedSecret, hookSecret!)) {
    return reply(401, { error: "Invalid order hook secret." });
  }

  try {
    const input = await req.json();
    if (input?.type !== "order" || !input?.record) {
      return reply(400, { error: "Invalid order event." });
    }

    const record = input.record;
    const orderNumber = String(record.order_number || "").trim().slice(0, 80);
    if (!orderNumber) return reply(400, { error: "Missing order number." });

    const customerName = String(record.customer_name || "Yeni müşteri").trim().slice(0, 60);
    const total = Number(record.total) || 0;
    const body = "#" + orderNumber + " · " + customerName + " · " +
      new Intl.NumberFormat("tr-TR", { maximumFractionDigits: 0 }).format(total) + " TL";

    const db = await fetch(
      supabaseUrl + "/rest/v1/push_subscriptions?select=id,subscription",
      { headers: { apikey: serviceRoleKey!, Authorization: "Bearer " + serviceRoleKey } },
    );
    if (!db.ok) throw new Error("Abonelikler okunamadı: " + await db.text());
    const subscriptions = await db.json();

    webpush.setVapidDetails(vapidSubject!, vapidPublicKey!, vapidPrivateKey!);
    let sent = 0;
    let failed = 0;
    const expired: number[] = [];

    for (const row of subscriptions) {
      try {
        await webpush.sendNotification(
          row.subscription,
          JSON.stringify({
            title: "YENİ SİPARİŞ ALINDI",
            body,
            url: "https://yemektadinda.com/",
            tag: "yemek-tadinda-order-" + orderNumber,
            orderNumber,
          }),
          { TTL: 86400 },
        );
        sent++;
      } catch (error) {
        failed++;
        const status = (error as { statusCode?: number }).statusCode;
        console.error("ORDER_PUSH_DELIVERY_ERROR", {
          statusCode: status,
          message: (error as Error).message,
          subscriptionId: row.id,
        });
        if (status === 404 || status === 410) expired.push(row.id);
      }
    }

    if (expired.length) {
      await fetch(
        supabaseUrl + "/rest/v1/push_subscriptions?id=in.(" + expired.join(",") + ")",
        {
          method: "DELETE",
          headers: { apikey: serviceRoleKey!, Authorization: "Bearer " + serviceRoleKey },
        },
      );
    }

    return reply(200, { success: failed === 0, sent, failed, total: subscriptions.length });
  } catch (error) {
    console.error("send-order-notification:", error);
    return reply(500, { error: (error as Error).message || "Push delivery failed." });
  }
});
