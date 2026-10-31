const webpush = require('web-push');

exports.handler = async (event) => {
  const headers = {
    'Content-Type': 'application/json',
    'Cache-Control': 'no-store',
    'Access-Control-Allow-Origin': 'https://yemektadinda.com',
    'Access-Control-Allow-Headers': 'Content-Type, Authorization',
    'Access-Control-Allow-Methods': 'POST, OPTIONS'
  };
  const reply = (statusCode, payload) => ({ statusCode, headers, body: JSON.stringify(payload) });
  if (event.httpMethod === 'OPTIONS') return { statusCode: 204, headers, body: '' };
  if (event.httpMethod !== 'POST') return reply(405, { error: 'Yalnızca POST desteklenir.' });

  const { SUPABASE_URL, SUPABASE_ANON_KEY, SUPABASE_SERVICE_ROLE_KEY,
    VAPID_PUBLIC_KEY, VAPID_PRIVATE_KEY, VAPID_SUBJECT } = process.env;
  if (![SUPABASE_URL, SUPABASE_ANON_KEY, SUPABASE_SERVICE_ROLE_KEY,
    VAPID_PUBLIC_KEY, VAPID_PRIVATE_KEY, VAPID_SUBJECT].every(Boolean)) {
    return reply(503, { error: 'Bildirim sunucusu ayarları tamamlanmamış. Netlify ortam değişkenlerini kontrol edin.' });
  }

  const token = (event.headers.authorization || event.headers.Authorization || '').replace(/^Bearer\s+/i, '');
  if (!token) return reply(401, { error: 'Yönetici oturumu gerekli.' });

  try {
    const authResponse = await fetch(SUPABASE_URL + '/rest/v1/rpc/is_admin', {
      method: 'POST',
      headers: { apikey: SUPABASE_ANON_KEY, Authorization: 'Bearer ' + token, 'Content-Type': 'application/json' },
      body: '{}'
    });
    if (!authResponse.ok || await authResponse.json() !== true) {
      return reply(403, { error: 'Bu işlem için yönetici yetkisi gerekli.' });
    }

    const input = JSON.parse(event.body || '{}');
    const title = String(input.title || '').trim().slice(0, 80);
    const body = String(input.body || '').trim().slice(0, 220);
    const image = typeof input.image === 'string' ? input.image : '';
    const url = typeof input.url === 'string' && input.url.startsWith('https://yemektadinda.com')
      ? input.url : 'https://yemektadinda.com/';
    if (!title || !body) return reply(400, { error: 'Bildirim başlığı ve mesajı zorunludur.' });

    const db = await fetch(SUPABASE_URL + '/rest/v1/push_subscriptions?select=id,subscription', {
      headers: { apikey: SUPABASE_SERVICE_ROLE_KEY, Authorization: 'Bearer ' + SUPABASE_SERVICE_ROLE_KEY }
    });
    if (!db.ok) throw new Error('Abonelik kayıtları okunamadı: ' + await db.text());
    const subscriptions = await db.json();

    webpush.setVapidDetails(VAPID_SUBJECT, VAPID_PUBLIC_KEY, VAPID_PRIVATE_KEY);
    let sent = 0, failed = 0;
    const expired = [];
    for (const row of subscriptions) {
      try {
        await webpush.sendNotification(row.subscription, JSON.stringify({ title, body, image, url, tag: 'yemek-tadinda-campaign' }), { TTL: 60 * 60 * 24 });
        sent++;
      } catch (err) {
        failed++;
        if (err.statusCode === 404 || err.statusCode === 410) expired.push(row.id);
      }
    }
    if (expired.length) {
      await fetch(SUPABASE_URL + '/rest/v1/push_subscriptions?id=in.(' + expired.join(',') + ')', {
        method: 'DELETE',
        headers: { apikey: SUPABASE_SERVICE_ROLE_KEY, Authorization: 'Bearer ' + SUPABASE_SERVICE_ROLE_KEY }
      });
    }
    return reply(200, { sent, failed, total: subscriptions.length });
  } catch (err) {
    console.error('Push notification error:', err);
    return reply(500, { error: err.message || 'Bildirim gönderimi başarısız.' });
  }
};
