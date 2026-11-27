/* Yemek Tadinda - server-verified daily wheel (branch prototype) */
(()=>{'use strict';
const prizes=['%5 İNDİRİM','ÜCRETSİZ İÇECEK','%10 İNDİRİM','ÜCRETSİZ TATLI','%15 İNDİRİM','ŞANS YOK'];
function launch(){if(document.getElementById('yt-spin-launch'))return;
const b=document.createElement('button');b.id='yt-spin-launch';b.textContent='🎡 ŞANSINI DENE';b.style.cssText='position:fixed;z-index:9998;right:18px;bottom:86px;border:2px solid #f3c65a;border-radius:999px;padding:14px 20px;background:linear-gradient(135deg,#111,#850b16);color:#fff;font-weight:900;box-shadow:0 8px 28px #0005;cursor:pointer';document.body.appendChild(b);b.onclick=open;}
function open(){if(document.getElementById('yt-spin-modal'))return;
const x=document.createElement('div');x.id='yt-spin-modal';x.style.cssText='position:fixed;inset:0;z-index:9999;background:#000b;display:flex;align-items:center;justify-content:center;padding:10px;font-family:inherit;overflow:auto';
x.innerHTML='<section style="max-width:360px;width:min(360px,100%);max-height:90vh;overflow-y:auto;padding:14px 16px;border-radius:18px;background:#161616;color:white;border:2px solid #e6b94d;text-align:center;box-sizing:border-box"><button id="swclose" style="float:right">✕</button><h2>🎡 ŞANS ÇARKI</h2><p>Telefon numaranı yaz, günlük şansını dene.</p><input id="swphone" placeholder="Telefon numarası" inputmode="tel" style="width:100%;padding:10px;margin:5px 0;border-radius:10px"><div id="swwheel" style="width:min(210px,65vw);height:min(210px,65vw);margin:10px auto;border-radius:50%;border:6px solid #e6b94d;background:conic-gradient(#df1824 0 60deg,#171717 60deg 120deg,#df1824 120deg 180deg,#171717 180deg 240deg,#df1824 240deg 300deg,#171717 300deg 360deg);display:grid;place-items:center;transition:transform 4s cubic-bezier(.12,.75,.12,1);"><div style="background:#111;border:3px solid #e6b94d;border-radius:50%;padding:16px;font-weight:900">ÇEVİR</div></div><button id="swspin" style="width:100%;padding:11px;background:#e6b94d;border:0;border-radius:12px;font-weight:900">ÇARKI ÇEVİR</button><p id="swresult" style="color:#f4cc62;font-weight:900;min-height:42px"></p><small>Günlük hakkınız telefon numarası üzerinden sunucuda kontrol edilir.</small></section>';
document.body.appendChild(x);x.querySelector('#swclose').onclick=()=>x.remove();const result=x.querySelector('#swresult'),btn=x.querySelector('#swspin');
btn.onclick=async()=>{btn.disabled=true;result.textContent='Doğrulanıyor…';
try{if(!window.supabase?.createClient)throw Error('Bağlantı kitaplığı yüklenmedi.');
const sb=window.supabase.createClient('https://jlpqdjhxdpmighnpebkj.supabase.co','sb_publishable_0jwHKXSBerbH6swoXYCRog_j3g8j5z6',{auth:{persistSession:false,autoRefreshToken:false}});
const phone=x.querySelector('#swphone').value;
const {data,error}=await sb.rpc('spin_daily_wheel',{p_phone:phone});if(error)throw error;
const p=data.prize_label,idx=prizes.indexOf(p);x.querySelector('#swwheel').style.transform='rotate('+(1440+(idx<0?0:360-idx*60))+'deg)';
result.textContent=data.already_spun?'Bugünkü hakkınız daha önce kullanılmış: '+p:'🎉 SONUÇ: '+p;
btn.textContent='GÜNLÜK HAK KULLANILDI';btn.disabled=true;
}catch(e){result.textContent=e.message||'İşlem başarısız. Bilgileri kontrol edin.';btn.disabled=false;}}
}
if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',launch,{once:true});else launch();
if(window.MutationObserver)new MutationObserver(launch).observe(document.body,{childList:true,subtree:true});
})();