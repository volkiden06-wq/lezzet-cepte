/* Yemek Tadında - Daily Spin Wheel (branch prototype)
 * Daily limit and reward state are client-side only in this prototype.
 * Server-side validation must be added before production use.
 */
(()=>{'use strict';
const KEY='yt_spin_daily_v1',REWARD_KEY='yt_spin_reward_v1';
const prizes=[{label:'%10 İNDİRİM',kind:'discount',value:10},{label:'ÜCRETSİZ İÇECEK',kind:'gift',value:'İçecek'},{label:'%15 İNDİRİM',kind:'discount',value:15},{label:'TATLI HEDİYE',kind:'gift',value:'Tatlı'},{label:'%5 İNDİRİM',kind:'discount',value:5},{label:'BUGÜN ŞANS YOK',kind:'none',value:0}];
const day=()=>new Date().toLocaleDateString('sv-SE');
const read=(k)=>{try{return JSON.parse(localStorage.getItem(k)||'null')}catch{return null}};
const used=()=>read(KEY)?.date===day();
function inject(){if(document.getElementById('yt-spin-launch'))return;
const b=document.createElement('button');b.id='yt-spin-launch';b.type='button';b.textContent='🎡 ŞANSINI DENE';b.setAttribute('aria-label','Günlük hediye çarkını aç');
b.style.cssText='position:fixed;z-index:9998;right:18px;bottom:86px;border:2px solid #f3c65a;border-radius:999px;padding:14px 20px;background:linear-gradient(135deg,#111,#850b16);color:#fff;font-weight:900;box-shadow:0 8px 28px #0005;cursor:pointer';
document.body.appendChild(b);b.onclick=openWheel;}
function openWheel(){if(document.getElementById('yt-spin-modal'))return;
const overlay=document.createElement('div');overlay.id='yt-spin-modal';overlay.style.cssText='position:fixed;inset:0;z-index:9999;background:#000b;display:flex;align-items:center;justify-content:center;padding:14px;font-family:inherit';
overlay.innerHTML='<div style="position:relative;max-width:440px;width:100%;border:1px solid #d9ae43;border-radius:24px;background:radial-gradient(circle at top,#4c1118,#111 65%);color:white;padding:24px;text-align:center;box-shadow:0 20px 80px #0009"><button id="yt-spin-close" style="position:absolute;right:12px;top:12px;border:0;background:#ffffff18;color:white;border-radius:50%;width:36px;height:36px;font-size:20px">×</button><div style="font-size:12px;color:#f4cc62;letter-spacing:3px;font-weight:900">YEMEK TADINDA</div><h2 style="margin:8px 0;color:white">🎡 ŞANS ÇARKI</h2><p id="yt-spin-status" style="color:#ddd">Her gün 1 şans!</p><div id="yt-spin-wheel" style="width:min(76vw,300px);height:min(76vw,300px);max-width:300px;max-height:300px;border-radius:50%;margin:20px auto;border:8px solid #f4cc62;background:conic-gradient(#d71927 0 60deg,#171717 60deg 120deg,#d71927 120deg 180deg,#171717 180deg 240deg,#d71927 240deg 300deg,#171717 300deg);display:flex;align-items:center;justify-content:center;box-shadow:0 0 30px #d7192755;transition:transform 4s cubic-bezier(.12,.75,.12,1);"><div style="background:#111;border:3px solid #f4cc62;border-radius:50%;width:90px;height:90px;display:flex;align-items:center;justify-content:center;font-weight:900;color:#f4cc62">ÇEVİR</div></div><button id="yt-spin-btn" style="width:100%;border:0;border-radius:14px;padding:15px;background:linear-gradient(90deg,#f4cc62,#e6a52b);color:#241500;font-weight:1000;font-size:16px">ÇARKI ÇEVİR</button><div id="yt-spin-result" style="min-height:48px;margin-top:15px;font-size:17px;font-weight:900;color:#f4cc62"></div><small style="color:#aaa">Ödül durumu bu prototipte cihaz üzerinde saklanır.</small></div>';
document.body.appendChild(overlay);overlay.querySelector('#yt-spin-close').onclick=()=>overlay.remove();overlay.onclick=e=>{if(e.target===overlay)overlay.remove()};
const btn=overlay.querySelector('#yt-spin-btn'),wheel=overlay.querySelector('#yt-spin-wheel'),result=overlay.querySelector('#yt-spin-result');
if(used()){btn.disabled=true;btn.textContent='BUGÜN KULLANILDI';overlay.querySelector('#yt-spin-status').textContent='Bugünkü çevirme hakkın kullanılmış.';const reward=read(REWARD_KEY);if(reward?.date===day())result.textContent='Bugünkü ödül: '+reward.label;return}
btn.onclick=()=>{btn.disabled=true;btn.textContent='DÖNÜYOR…';const idx=Math.floor(Math.random()*prizes.length),prize=prizes[idx];wheel.style.transform='rotate('+(1440+idx*60+Math.random()*45)+'deg)';setTimeout(()=>{localStorage.setItem(KEY,JSON.stringify({date:day()}));localStorage.setItem(REWARD_KEY,JSON.stringify({...prize,date:day()}));result.textContent=prize.kind==='none'?'Bugün olmadı, yarın tekrar dene!':'🎉 KAZANDIN: '+prize.label;btn.textContent='BUGÜN KULLANILDI';overlay.querySelector('#yt-spin-status').textContent='Kazandığın ödül kaydedildi.'},4100)};
}
function start(){inject();new MutationObserver(inject).observe(document.body,{childList:true,subtree:true});}
if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',start,{once:true});else start();
})();