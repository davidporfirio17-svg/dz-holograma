const SA='davizin',MXD=30,MXG=10;
function gk(n=8){const c='ABCDEFGHJKLMNPQRSTUVWXYZ23456789';let r='';for(let i=0;i<n;i++)r+=c[Math.floor(Math.random()*c.length)];return r;}
function gsid(req){const c=req.headers.get('Cookie')||'';const t=c.split(';').find(x=>x.trim().startsWith('dz='));return t?t.trim().slice(3):null;}
async function al(env,who,action,detail=''){await env.DZH_KV.put('dzh_log:'+Date.now()+':'+gk(4),JSON.stringify({who,action,detail,ts:Date.now()}),{expirationTtl:2592000});}
async function keyLog(env,key,who,action,detail=''){try{await env.DZH_KV.put('keylog:'+key+':'+Date.now()+':'+gk(4),JSON.stringify({key,who,action,detail,ts:Date.now()}),{expirationTtl:7776000});}catch(e){}}
function keyHistoryEsc(v){return String(v??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));}
async function hmacHex(secret,msg){const k=await crypto.subtle.importKey('raw',new TextEncoder().encode(secret),{name:'HMAC',hash:'SHA-256'},false,['sign']);const sig=await crypto.subtle.sign('HMAC',k,new TextEncoder().encode(msg));return[...new Uint8Array(sig)].map(b=>b.toString(16).padStart(2,'0')).join('');}
async function deviceFP(hwid,dev){const raw=hwid+'|'+((dev&&dev.model)||'');const buf=await crypto.subtle.digest('SHA-256',new TextEncoder().encode(raw));return[...new Uint8Array(buf)].slice(0,16).map(b=>b.toString(16).padStart(2,'0')).join('');}
async function freezeStart(env){try{const cur=await env.DZH_KV.get('freeze_since');if(!cur)await env.DZH_KV.put('freeze_since',String(Date.now()));}catch(e){}}
async function freezeEnd(env){try{const since=parseInt(await env.DZH_KV.get('freeze_since')||'0',10);if(!since)return;const stillMaint=(await env.DZH_KV.get('dzh_maintenance'))==='1';const stillKill=(await env.DZH_KV.get('dzh_killswitch'))==='1';if(stillMaint||stillKill)return;const downMs=Date.now()-since;if(downMs>0){const kl=await env.DZH_KV.list({prefix:'dzh_key:'});for(const k of kl.keys){const r=await env.DZH_KV.get(k.name);if(!r)continue;const d=JSON.parse(r);if(d.activated){d.activated=d.activated+downMs;await env.DZH_KV.put(k.name,JSON.stringify(d));}}}await env.DZH_KV.delete('freeze_since');}catch(e){}}
async function maintenanceAllowed(env,key){return key==='1'||!!(key&&await env.DZH_KV.get('maintenance_allow:'+key));}
function isVPN(org){if(!org)return false;const o=org.toLowerCase();const bad=['amazon','aws','google','gcp','microsoft','azure','ovh','digitalocean','linode','vultr','hetzner','nordvpn','expressvpn','surfshark','protonvpn','cyberghost','private internet','mullvad','windscribe','hostinger','contabo','choopa','datacamp','m247','leaseweb','colocrossing','quadranet','vpn','proxy','hosting','datacenter','data center','cloud','server'];return bad.some(b=>o.includes(b));}
async function deriveKey(secret){const raw=await crypto.subtle.digest('SHA-256',new TextEncoder().encode('dzcache:'+secret));return crypto.subtle.importKey('raw',raw,{name:'AES-GCM'},false,['encrypt']);}
async function encryptAESGCM(secret,data){const k=await deriveKey(secret);const iv=crypto.getRandomValues(new Uint8Array(12));const ct=new Uint8Array(await crypto.subtle.encrypt({name:'AES-GCM',iv},k,data));const out=new Uint8Array(12+ct.length);out.set(iv,0);out.set(ct,12);return out;}
function safeJson(v){try{return JSON.parse(v)}catch(e){return null}}
function fmtDate(ts){if(!ts)return'—';const d=new Date(ts);return d.toLocaleDateString('es-MX',{day:'2-digit',month:'short',year:'numeric'});}
function fmtDateTime(ts){if(!ts)return'—';return new Date(ts).toLocaleString('es-MX',{timeZone:'America/Mexico_City',day:'2-digit',month:'2-digit',year:'numeric',hour:'2-digit',minute:'2-digit',second:'2-digit',hour12:false});}
async function hasHologramAccess(env,key){return !!(await env.DZH_KV.get('dzh_holoAccess:'+key)||await env.DZH_KV.get('dzh_holoAdmin:'+key));}
function durationSecondsOf(d){const explicit=Number(d.durationSeconds);if(Number.isFinite(explicit)&&explicit>0)return Math.floor(explicit);const legacyDays=Number(d.days||0);return Math.max(0,Math.round(legacyDays*86400));}
function secondsLeft(d){const duration=durationSecondsOf(d);if(!d.activated)return duration;return Math.max(0,Math.ceil((d.activated+duration*1000-Date.now())/1000));}
function daysLeft(d){return Math.ceil(secondsLeft(d)/86400);}
function expDate(d){if(!d.activated)return null;return d.activated+durationSecondsOf(d)*1000;}
function formatDuration(totalSeconds){const seconds=Math.max(0,Math.floor(Number(totalSeconds)||0));const totalMinutes=Math.ceil(seconds/60);const hours=Math.floor(totalMinutes/60);const minutes=totalMinutes%60;if(hours&&minutes)return`${hours} h ${minutes} min`;if(hours)return`${hours} h`;return`${minutes} min`;}
async function allowedAppBuild(env,build){const raw=await env.DZH_KV.get('allowed_app_builds');if(!raw)return String(build)==='2';try{const list=JSON.parse(raw);return Array.isArray(list)&&list.map(String).includes(String(build));}catch(e){return false;}}
async function appBuildsPage(req,env,ses){let msg='';if(req.method==='POST'){const f=await req.formData();const input=String(f.get('allowed')||'');const list=[...new Set(input.split(',').map(x=>x.trim()).filter(x=>/^[0-9]+$/.test(x)).map(x=>String(Number(x))))].slice(0,32);if(!list.length)return new Response('Debes permitir al menos un build.',{status:400});await env.DZH_KV.put('allowed_app_builds',JSON.stringify(list));await al(env,ses.user,'app-builds:update',list.join(','));msg='Builds permitidos actualizados: '+list.join(', ');}const raw=await env.DZH_KV.get('allowed_app_builds');const list=raw?safeJson(raw):null;const allowed=Array.isArray(list)&&list.length?list.map(String).join(', '):'2';return wrap('Builds permitidos',`<div class="ph"><div><h1>▣ Builds permitidos</h1><p>Control remoto de las versiones de Nyxel que pueden validar keys.</p></div></div>${msg?`<div class="al al-s">✓ ${msg}</div>`:''}<div class="card"><div class="card-h"><span class="card-t">Allowlist de IPA</span></div><div class="card-b"><form method="POST"><div class="fg"><label>Builds permitidos</label><input name="allowed" value="${allowed}" placeholder="2,3" required><p style="color:var(--t3);font-size:11px;margin-top:8px">Escribe los builds separados por coma. La IPA actual es la build 2.</p></div><button class="btn b-pr">Guardar allowlist</button></form></div></div>`,ses);}

const CSS=`
/* ==========================================================================
   DAVIZIN CONTROL — Panel stylesheet v3 "Obsidian Emerald"
   Single source of truth. One token set, one dark theme, one light theme.
   Motion: transform + opacity only. Easing: custom cubic-beziers only.
   ========================================================================== */
@import url("https://fonts.googleapis.com/css2?family=Plus+Jakarta+Sans:wght@300..800&display=swap");
@import url("https://api.fontshare.com/v2/css?f[]=clash-display@500,600,700&display=swap");

/* ---------- 01 · TOKENS · STRUCTURAL ---------- */
:root{
  --f-body:"Plus Jakarta Sans",ui-sans-serif,system-ui,-apple-system,"Segoe UI",Roboto,"Helvetica Neue",sans-serif;
  --f-disp:"Clash Display","Plus Jakarta Sans",ui-sans-serif,system-ui,-apple-system,"Segoe UI",sans-serif;
  --f-mono:ui-monospace,"SF Mono","JetBrains Mono",Menlo,Consolas,"Liberation Mono",monospace;

  --ease:cubic-bezier(.32,.72,0,1);
  --out:cubic-bezier(.16,1,.3,1);
  --spring:cubic-bezier(.34,1.56,.64,1);
  --glide:cubic-bezier(.65,0,.35,1);

  --sw:268px;
}

/* ---------- 01b · TOKENS · DARK (default) ---------- */
:root,html[data-dz-theme="dark"]{
  color-scheme:dark;

  --bg:#05070A;
  --s0:rgba(8,12,18,.96);
  --s1:rgba(14,20,30,.9);
  --s2:#0E141C;
  --s3:#151D28;
  --b0:rgba(148,163,184,.06);
  --b1:rgba(148,163,184,.12);
  --b2:rgba(148,163,184,.22);

  --a:#6EE7B7;--ac:#6EE7B7;
  --ag:#34D399;
  --a2:#818CF8;
  --ok:#6EE7B7;
  --w:#FCD34D;
  --e:#FCA5A5;
  --info:#818CF8;
  --sky:#7DD3FC;
  --t:#F1F5F9;
  --t2:#94A3B8;
  --t3:#64748B;
  --ink:#04130D;

  --glow:rgba(110,231,183,.12);
  --a-line:rgba(110,231,183,.24);
  --ok-bg:rgba(110,231,183,.1);   --ok-bd:rgba(110,231,183,.24);
  --w-bg:rgba(252,211,77,.09);    --w-bd:rgba(252,211,77,.24);
  --e-bg:rgba(252,165,165,.09);   --e-bd:rgba(252,165,165,.24);
  --i-bg:rgba(129,140,248,.11);   --i-bd:rgba(129,140,248,.3);
  --sky-bg:rgba(125,211,252,.1);  --sky-bd:rgba(125,211,252,.26);

  --bg2:rgba(255,255,255,.035);
  --field:rgba(255,255,255,.035);
  --field-f:rgba(255,255,255,.06);
  --chip:rgba(255,255,255,.045);
  --chip-h:rgba(255,255,255,.08);

  --card-bg:linear-gradient(165deg,rgba(19,27,40,.8),rgba(8,12,19,.9));
  --stat-bg:linear-gradient(160deg,rgba(21,30,44,.82),rgba(8,12,19,.92));
  --mode-bg:linear-gradient(150deg,rgba(14,34,36,.84),rgba(8,12,19,.93));
  --tw-bg:rgba(3,6,10,.42);
  --th:rgba(10,15,22,.72);
  --stick:#0A0F16;
  --stick-h:#101823;
  --row-h:rgba(110,231,183,.045);
  --sb-bg:rgba(8,12,18,.7);
  --bar-bg:rgba(8,12,18,.62);
  --drawer:rgba(8,12,18,.97);
  --dock-bg:rgba(8,12,18,.9);
  --scrim:rgba(2,4,8,.68);
  --toast-bg:rgba(12,18,27,.68);

  --ring:rgba(255,255,255,.024);
  --ring-edge:rgba(148,163,184,.07);
  --hl:rgba(255,255,255,.075);
  --sh-md:0 20px 44px -24px rgba(0,0,0,.75);
  --sh-lg:0 44px 80px -40px rgba(0,0,0,.9);
  --track:rgba(148,163,184,.14);

  --grid:rgba(148,163,184,.045);
  --orb1:rgba(110,231,183,.14);
  --orb2:rgba(129,140,248,.15);
  --pulse:rgba(110,231,183,.5);
  --code:#A7F3D0;
  --wm:rgba(241,245,249,.07);
  --grain:.035;

  --globe-ocean:#0B2F33;
  --globe-land:#6EE7B7;
  --globe-grid:rgba(190,255,230,.4);
  --globe-edge:rgba(167,243,208,.7);
}

/* ---------- 02 · TOKENS · LIGHT ---------- */
html[data-dz-theme="light"]{
  color-scheme:light;
  --bg:#F2F5F9;
  --s0:rgba(255,255,255,.94);
  --s1:rgba(255,255,255,.88);
  --s2:#F8FAFC;
  --s3:#EEF2F7;
  --b0:rgba(15,23,42,.06);
  --b1:rgba(15,23,42,.1);
  --b2:rgba(15,23,42,.19);

  --a:#059669;--ac:#059669;
  --ag:#047857;
  --a2:#4F46E5;
  --ok:#047857;
  --w:#B45309;
  --e:#DC2626;
  --info:#4F46E5;
  --sky:#0369A1;
  --t:#0F172A;
  --t2:#475569;
  --t3:#64748B;
  --ink:#FFFFFF;

  --glow:rgba(5,150,105,.1);
  --a-line:rgba(5,150,105,.28);
  --ok-bg:rgba(5,150,105,.1);     --ok-bd:rgba(5,150,105,.26);
  --w-bg:rgba(217,119,6,.1);      --w-bd:rgba(217,119,6,.28);
  --e-bg:rgba(220,38,38,.08);     --e-bd:rgba(220,38,38,.24);
  --i-bg:rgba(79,70,229,.09);     --i-bd:rgba(79,70,229,.26);
  --sky-bg:rgba(3,105,161,.08);   --sky-bd:rgba(3,105,161,.24);

  --bg2:rgba(255,255,255,.9);
  --field:rgba(255,255,255,.85);
  --field-f:#FFFFFF;
  --chip:rgba(15,23,42,.045);
  --chip-h:rgba(15,23,42,.08);

  --card-bg:linear-gradient(165deg,rgba(255,255,255,.97),rgba(247,250,253,.92));
  --stat-bg:linear-gradient(160deg,rgba(255,255,255,.98),rgba(244,248,252,.92));
  --mode-bg:linear-gradient(150deg,rgba(236,253,245,.96),rgba(255,255,255,.94));
  --tw-bg:rgba(255,255,255,.6);
  --th:rgba(243,246,250,.78);
  --stick:#FBFCFE;
  --stick-h:#EEF3F8;
  --row-h:rgba(5,150,105,.05);
  --sb-bg:rgba(255,255,255,.72);
  --bar-bg:rgba(255,255,255,.72);
  --drawer:rgba(255,255,255,.98);
  --dock-bg:rgba(255,255,255,.92);
  --scrim:rgba(15,23,42,.38);
  --toast-bg:rgba(255,255,255,.78);

  --ring:rgba(15,23,42,.03);
  --ring-edge:rgba(15,23,42,.06);
  --hl:rgba(255,255,255,.95);
  --sh-md:0 18px 40px -24px rgba(15,23,42,.24);
  --sh-lg:0 36px 70px -38px rgba(15,23,42,.3);
  --track:rgba(15,23,42,.1);

  --grid:rgba(15,23,42,.045);
  --orb1:rgba(16,185,129,.17);
  --orb2:rgba(99,102,241,.14);
  --pulse:rgba(5,150,105,.4);
  --code:#047857;
  --wm:rgba(15,23,42,.07);
  --grain:.028;

  --globe-ocean:#D1FAE5;
  --globe-land:#059669;
  --globe-grid:rgba(4,120,87,.34);
  --globe-edge:rgba(5,150,105,.55);
}

/* ---------- 03 · BASE ---------- */
*,*::before,*::after{box-sizing:border-box}
*{margin:0;padding:0}
html{
  background:var(--bg);
  scroll-behavior:smooth;
  scroll-padding-top:96px;
  -webkit-text-size-adjust:100%;
  text-size-adjust:100%;
  -webkit-tap-highlight-color:transparent;
}
body{
  position:relative;
  isolation:isolate;
  min-width:320px;
  min-height:100vh;
  min-height:100dvh;
  overflow-x:hidden;
  background:var(--bg);
  color:var(--t);
  font-family:var(--f-body);
  font-size:14px;
  line-height:1.5;
  -webkit-font-smoothing:antialiased;
  -moz-osx-font-smoothing:grayscale;
  text-rendering:optimizeLegibility;
}
a{color:inherit;text-decoration:none}
button,input,select,textarea{font:inherit;color:inherit}
button{cursor:pointer;background:none;border:0}
button:disabled{cursor:not-allowed}
h1,h2,h3,h4{font-family:var(--f-disp);font-weight:600;letter-spacing:-.02em;color:var(--t)}
p{color:inherit}
strong,b{font-weight:700}
small{font-size:.85em}
code,kbd,samp{font-family:var(--f-mono)}
code{font-size:11.5px;color:var(--code);background:var(--chip);padding:2px 7px;border-radius:7px;overflow-wrap:anywhere}
hr{border:0;height:1px;background:linear-gradient(90deg,transparent,var(--b2),transparent);margin:22px 0}
::selection{background:rgba(110,231,183,.28);color:var(--t)}
html[data-dz-theme="light"] ::selection{background:rgba(5,150,105,.22)}
img,svg{max-width:100%}

/* scrollbars */
*{scrollbar-width:thin;scrollbar-color:rgba(148,163,184,.3) transparent}
*::-webkit-scrollbar{width:10px;height:10px}
*::-webkit-scrollbar-track{background:transparent}
*::-webkit-scrollbar-thumb{background:rgba(148,163,184,.26);border:3px solid transparent;background-clip:padding-box;border-radius:999px;transition:background-color .4s var(--ease)}
*::-webkit-scrollbar-thumb:hover{background:rgba(110,231,183,.5);border:3px solid transparent;background-clip:padding-box}
*::-webkit-scrollbar-corner{background:transparent}

/* focus: glowing, accessible */
html body :is(a,button,.btn,.sb-lnk,.theme-toggle,.mobile-menu,.mobile-dock-item,.key-detail-button,.key-menu-toggle,summary,[tabindex]):focus-visible{
  outline:2px solid var(--a);
  outline-offset:3px;
  box-shadow:0 0 0 6px rgba(110,231,183,.14),0 0 28px -4px rgba(110,231,183,.4);
}
html[data-dz-theme="light"] body :is(a,button,.btn,.sb-lnk,.theme-toggle,.mobile-menu,.mobile-dock-item,.key-detail-button,.key-menu-toggle,summary,[tabindex]):focus-visible{
  box-shadow:0 0 0 6px rgba(5,150,105,.16),0 0 24px -4px rgba(5,150,105,.35);
}
html body :is(input,select,textarea):focus-visible{
  outline:2px solid transparent;
  outline-offset:2px;
  border-color:var(--a)!important;
  background:var(--field-f);
  box-shadow:0 0 0 4px rgba(110,231,183,.14),0 0 28px -6px rgba(110,231,183,.45);
}
html[data-dz-theme="light"] body :is(input,select,textarea):focus-visible{
  box-shadow:0 0 0 4px rgba(5,150,105,.14),0 0 24px -6px rgba(5,150,105,.35);
}

/* ---------- 04 · ATMOSPHERE ---------- */
body::before{
  content:"";position:fixed;inset:0;z-index:0;pointer-events:none;
  background-image:linear-gradient(var(--grid) 1px,transparent 1px),linear-gradient(90deg,var(--grid) 1px,transparent 1px);
  background-size:72px 72px;
  -webkit-mask-image:radial-gradient(ellipse 75% 55% at 50% 0%,#000,transparent 78%);
  mask-image:radial-gradient(ellipse 75% 55% at 50% 0%,#000,transparent 78%);
}
body::after{
  content:"";position:fixed;inset:0;z-index:2;pointer-events:none;opacity:var(--grain);
  background-image:url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' width='180' height='180'%3E%3Cfilter id='n'%3E%3CfeTurbulence type='fractalNoise' baseFrequency='.85' numOctaves='2' stitchTiles='stitch'/%3E%3C/filter%3E%3Crect width='100%25' height='100%25' filter='url(%23n)'/%3E%3C/svg%3E");
  background-size:180px 180px;
}
.global-atmosphere{
  position:fixed;inset:0;z-index:0;overflow:hidden;pointer-events:none;
  background:
    radial-gradient(55% 45% at 88% -8%,rgba(110,231,183,.07),transparent 70%),
    radial-gradient(50% 45% at -6% 104%,rgba(129,140,248,.07),transparent 70%);
}
.global-atmosphere::before,.global-atmosphere::after{
  content:"";position:absolute;border-radius:50%;will-change:transform;
}
.global-atmosphere::before{
  width:68vmax;height:68vmax;left:-22vmax;top:-34vmax;
  background:radial-gradient(closest-side,var(--orb1),transparent);
  animation:ambient 26s var(--glide) infinite alternate;
}
.global-atmosphere::after{
  width:62vmax;height:62vmax;right:-24vmax;bottom:-30vmax;
  background:radial-gradient(closest-side,var(--orb2),transparent);
  animation:ambient 32s var(--glide) -9s infinite alternate-reverse;
}

/* ---------- 05 · SHELL ---------- */
.main{
  position:relative;z-index:1;isolation:isolate;
  min-width:0;min-height:100vh;min-height:100dvh;
  display:flex;flex-direction:column;
  margin-left:calc(var(--sw) + 28px);
}
.main.guest-main{margin-left:0;width:100%;background:transparent}
.content{
  position:relative;z-index:1;flex:1;
  width:min(1480px,100%);margin:0 auto;
  padding:clamp(28px,3.4vw,48px) clamp(18px,3vw,44px) 88px;
}

/* ---------- 06 · SIDEBAR (floating glass) ---------- */
.sb{
  position:fixed;inset:14px auto 14px 14px;z-index:60;
  width:var(--sw);
  display:flex;flex-direction:column;overflow:hidden;
  background:var(--sb-bg);
  -webkit-backdrop-filter:blur(30px) saturate(160%);
  backdrop-filter:blur(30px) saturate(160%);
  border:1px solid var(--b1);
  border-radius:28px;
  box-shadow:inset 0 1px 0 var(--hl),0 0 0 5px var(--ring),0 0 0 6px var(--ring-edge),var(--sh-lg);
  transition:transform .7s var(--ease),visibility 0s linear 0s;
}
.sb::before{
  content:"";position:absolute;inset:0;z-index:0;pointer-events:none;border-radius:inherit;
  background:radial-gradient(120% 50% at 0% 0%,rgba(110,231,183,.12),transparent 62%),radial-gradient(90% 40% at 100% 100%,rgba(129,140,248,.1),transparent 70%);
}
.sb>*{position:relative;z-index:1}
.sb-top{
  height:88px;padding:0 24px;flex-shrink:0;
  display:flex;align-items:center;
  border-bottom:1px solid var(--b0);
}
.sb-logo{display:flex;align-items:center;gap:14px;min-width:0}
.sb-icon{
  width:42px;height:42px;flex-shrink:0;display:grid;place-items:center;
  border-radius:14px;
  background:linear-gradient(145deg,rgba(110,231,183,.2),rgba(129,140,248,.1));
  border:1px solid var(--a-line);
  box-shadow:inset 0 1px 0 rgba(255,255,255,.14),0 10px 28px -10px rgba(110,231,183,.5);
}
.brand-glyph{
  width:30px;height:30px;display:inline-block;position:relative;
  transform:rotate(-5deg);
  filter:drop-shadow(0 0 10px rgba(110,231,183,.4));
}
.brand-glyph::before,.brand-glyph::after{
  content:"";position:absolute;border-radius:2px 8px 2px 2px;
  background:linear-gradient(160deg,var(--a),var(--ag));
}
.brand-glyph::before{width:10px;height:27px;left:5px;top:1px;transform:skewY(-27deg)}
.brand-glyph::after{width:15px;height:10px;left:11px;top:8px;transform:skewX(-27deg);background:linear-gradient(90deg,var(--a),var(--a2))}
.brand-glyph.mini{width:24px;height:24px;transform:scale(.8)}
.sb-name{font:600 18px/1 var(--f-disp);letter-spacing:.2em;color:var(--t)}
.sb-ver{margin-top:7px;font:600 9px/1 var(--f-body);letter-spacing:.16em;text-transform:uppercase;color:var(--t3)}
.sb-nav{flex:1;min-height:0;padding:20px 12px 16px;overflow-y:auto;overscroll-behavior:contain}
.sb-sec{
  padding:0 14px 10px;
  font:700 9.5px/1.3 var(--f-body);letter-spacing:.18em;text-transform:uppercase;color:var(--t3);
}
.sb-sec:not(:first-child){margin-top:26px}
.sb-lnk{
  position:relative;display:flex;align-items:center;gap:12px;
  min-height:44px;margin:2px 0;padding:0 12px 0 8px;
  border:1px solid transparent;border-radius:16px;
  font-size:13px;font-weight:550;letter-spacing:-.005em;color:var(--t2);
  transition:color .45s var(--ease),background-color .45s var(--ease),border-color .45s var(--ease),transform .55s var(--spring);
}
.sb-lnk::before{
  content:"";position:absolute;left:-10px;top:50%;width:3px;height:20px;margin-top:-10px;
  border-radius:0 4px 4px 0;background:var(--a);
  box-shadow:0 0 16px var(--a);
  opacity:0;transform:scaleY(.3);
  transition:opacity .45s var(--ease),transform .6s var(--spring);
}
.sb-lnk .ic{
  width:30px;height:30px;flex-shrink:0;display:grid;place-items:center;
  border-radius:10px;background:var(--chip);border:1px solid var(--b0);
  font-size:13px;line-height:1;filter:saturate(.7);
  transition:background-color .45s var(--ease),border-color .45s var(--ease),transform .6s var(--spring),color .45s var(--ease);
}
.sb-lnk .badge-n{
  margin-left:auto;padding:4px 8px;border-radius:999px;
  font:700 10px/1 var(--f-body);color:var(--a);background:var(--glow);border:1px solid var(--a-line);
}
.sb-lnk:hover{color:var(--t);background:var(--chip);transform:translateX(3px)}
.sb-lnk:hover .ic{background:var(--chip-h);transform:scale(1.06) rotate(-3deg)}
.sb-lnk:active{transform:translateX(3px) scale(.98)}
.sb-lnk.on{
  color:var(--t);
  background:linear-gradient(90deg,rgba(110,231,183,.14),rgba(110,231,183,.02));
  border-color:rgba(110,231,183,.16);
  box-shadow:inset 0 1px 0 var(--hl);
}
html[data-dz-theme="light"] .sb-lnk.on{background:linear-gradient(90deg,rgba(5,150,105,.12),rgba(5,150,105,.02));border-color:rgba(5,150,105,.18)}
.sb-lnk.on::before{opacity:1;transform:scaleY(1)}
.sb-lnk.on .ic{color:var(--a);background:var(--glow);border-color:var(--a-line);filter:none}
.sb-bottom{padding:12px;flex-shrink:0;border-top:1px solid var(--b0)}
.sb-user{
  display:flex;align-items:center;gap:12px;padding:10px;
  border-radius:18px;background:var(--chip);border:1px solid var(--b0);
  box-shadow:inset 0 1px 0 var(--hl);
  transition:background-color .45s var(--ease),border-color .45s var(--ease);
}
.sb-user:hover{background:var(--chip-h);border-color:var(--b1)}
.sb-avatar{
  width:38px;height:38px;flex-shrink:0;display:grid;place-items:center;
  border-radius:13px;background:linear-gradient(140deg,var(--a),var(--a2));
  color:var(--ink);font:700 15px/1 var(--f-disp);
  box-shadow:inset 0 1px 0 rgba(255,255,255,.35),0 8px 20px -8px rgba(110,231,183,.6);
}
.sb-user>div:last-child{min-width:0}
.sb-uname{font:600 13px/1.2 var(--f-body);color:var(--t);overflow:hidden;text-overflow:ellipsis;white-space:nowrap}
.sb-urole{margin-top:4px;font-size:10.5px;color:var(--t3)}
.sb-out{
  display:flex;align-items:center;justify-content:center;gap:8px;
  min-height:42px;margin-top:8px;border:1px solid transparent;border-radius:999px;
  font-size:12px;font-weight:600;color:var(--t2);
  transition:color .45s var(--ease),background-color .45s var(--ease),border-color .45s var(--ease),transform .5s var(--spring);
}
.sb-out:hover{color:var(--e);background:var(--e-bg);border-color:var(--e-bd)}
.sb-out:active{transform:scale(.97)}

/* ---------- 07 · TOPBAR (floating island) ---------- */
.topbar{
  position:sticky;top:14px;z-index:40;flex-shrink:0;
  height:62px;margin:14px clamp(14px,2.6vw,36px) 0;padding:0 16px 0 22px;
  display:flex;align-items:center;justify-content:space-between;gap:12px;
  background:var(--bar-bg);
  -webkit-backdrop-filter:blur(26px) saturate(160%);
  backdrop-filter:blur(26px) saturate(160%);
  border:1px solid var(--b1);border-radius:999px;
  box-shadow:inset 0 1px 0 var(--hl),0 0 0 4px var(--ring),0 0 0 5px var(--ring-edge),var(--sh-md);
}
.tb-title{display:flex;align-items:center;gap:12px;min-width:0;font:600 16px/1.2 var(--f-disp);letter-spacing:-.01em;color:var(--t)}
.tb-title::before{
  content:"CONTROL /";flex-shrink:0;
  padding:5px 10px;border-radius:999px;background:var(--chip);border:1px solid var(--b0);
  font:700 9px/1 var(--f-body);letter-spacing:.16em;color:var(--t3);
}
.tb-right{display:flex;align-items:center;gap:10px}
.mobile-menu{
  display:none;align-items:center;justify-content:center;flex-shrink:0;
  width:40px;height:40px;border-radius:14px;
  background:var(--chip);border:1px solid var(--b1);color:var(--t);font-size:16px;
  transition:background-color .45s var(--ease),border-color .45s var(--ease),transform .5s var(--spring);
}
.mobile-menu:hover{background:var(--glow);border-color:var(--a-line)}
.mobile-menu:active{transform:scale(.94)}
.nav-scrim{
  display:none;position:fixed;inset:0;z-index:55;padding:0;border:0;
  background:var(--scrim);
  -webkit-backdrop-filter:blur(6px);backdrop-filter:blur(6px);
  opacity:0;pointer-events:none;
  transition:opacity .6s var(--ease);
}
.theme-toggle{
  min-height:36px;display:inline-flex;align-items:center;justify-content:center;gap:8px;
  padding:0 14px;border-radius:999px;
  background:var(--chip);border:1px solid var(--b1);color:var(--t2);
  font-size:12px;font-weight:600;
  transition:color .45s var(--ease),background-color .45s var(--ease),border-color .45s var(--ease),transform .5s var(--spring);
}
.theme-toggle:hover{color:var(--t);background:var(--chip-h);border-color:var(--b2)}
.theme-toggle:active{transform:scale(.96)}
.theme-toggle .theme-icon{display:inline-block;font-size:14px;line-height:1;transition:transform .8s var(--spring)}
.theme-toggle:hover .theme-icon{transform:rotate(180deg)}
.pill{
  height:36px;display:inline-flex;align-items:center;gap:9px;padding:0 15px;border-radius:999px;
  background:var(--ok-bg);border:1px solid var(--ok-bd);color:var(--ok);
  font:650 11.5px/1 var(--f-body);letter-spacing:.01em;white-space:nowrap;
}
.pill::before{
  content:"";width:7px;height:7px;flex-shrink:0;border-radius:50%;
  background:var(--ok);box-shadow:0 0 0 0 var(--pulse);
  animation:pulse 2.6s var(--out) infinite;
}

/* ---------- 08 · PAGE HEAD ---------- */
.ph{
  display:flex;align-items:flex-end;justify-content:space-between;flex-wrap:wrap;gap:22px;
  margin-bottom:34px;padding-bottom:26px;
  background:linear-gradient(90deg,var(--b1),transparent 80%) left bottom/100% 1px no-repeat;
  animation:reveal 1s var(--out) backwards;
}
.ph>div{min-width:0}
.ph h1{
  font:600 clamp(30px,3.5vw,48px)/1.02 var(--f-disp);letter-spacing:-.035em;color:var(--t);
}
.ph h1::before{
  content:"RESUMEN OPERATIVO";
  display:flex;align-items:center;width:max-content;max-width:100%;
  margin-bottom:18px;padding:7px 13px 7px 26px;border-radius:999px;
  background:radial-gradient(circle at 13px 50%,var(--a) 0 2.5px,transparent 3.5px),var(--glow);
  border:1px solid var(--a-line);
  font:700 9.5px/1 var(--f-body);letter-spacing:.2em;color:var(--a);
}
.ph p{max-width:68ch;margin-top:14px;font-size:14px;line-height:1.7;color:var(--t2)}
.acts{display:flex;align-items:center;flex-wrap:wrap;gap:10px}
.ph .acts{align-self:flex-end}

/* ---------- 09 · STATS ---------- */
.sg{
  display:grid;gap:16px;margin-bottom:26px;
  grid-template-columns:repeat(auto-fit,minmax(min(100%,210px),1fr));
}
.stat{
  position:relative;isolation:isolate;overflow:hidden;
  min-height:148px;padding:22px 22px 20px;
  border-radius:24px;background:var(--stat-bg);
  box-shadow:inset 0 1px 0 var(--hl),var(--sh-md);
  transition:transform .7s var(--ease),box-shadow .7s var(--ease);
  animation:reveal 1s var(--out) backwards;
}
.stat::before{
  content:"";position:absolute;inset:0;z-index:2;pointer-events:none;border-radius:inherit;padding:1px;
  background:linear-gradient(150deg,rgba(255,255,255,.2),rgba(255,255,255,.03) 38%,rgba(110,231,183,.06) 62%,rgba(129,140,248,.34));
  -webkit-mask:linear-gradient(#000 0 0) content-box,linear-gradient(#000 0 0);
  mask:linear-gradient(#000 0 0) content-box,linear-gradient(#000 0 0);
  -webkit-mask-composite:xor;
  mask-composite:exclude;
  opacity:.55;transition:opacity .7s var(--ease);
}
html[data-dz-theme="light"] .stat::before{background:linear-gradient(150deg,rgba(15,23,42,.14),rgba(15,23,42,.03) 40%,rgba(5,150,105,.08) 62%,rgba(79,70,229,.3))}
.stat::after{
  content:"";position:absolute;z-index:-1;right:-56px;top:-64px;width:170px;height:170px;border-radius:50%;
  background:radial-gradient(closest-side,rgba(110,231,183,.2),transparent);
  opacity:.65;transition:transform .9s var(--ease),opacity .9s var(--ease);
}
.stat:nth-child(even)::after{background:radial-gradient(closest-side,rgba(129,140,248,.22),transparent)}
.stat:hover{transform:translateY(-5px);box-shadow:inset 0 1px 0 var(--hl),0 34px 60px -26px rgba(0,0,0,.85),0 0 46px -18px rgba(110,231,183,.3)}
html[data-dz-theme="light"] .stat:hover{box-shadow:inset 0 1px 0 var(--hl),0 30px 56px -26px rgba(15,23,42,.3),0 0 40px -18px rgba(5,150,105,.3)}
.stat:hover::before{opacity:1}
.stat:hover::after{transform:scale(1.35) translate3d(-8px,8px,0);opacity:1}
.stat:nth-child(1){animation-delay:.05s}.stat:nth-child(2){animation-delay:.1s}.stat:nth-child(3){animation-delay:.15s}.stat:nth-child(4){animation-delay:.2s}
.stat:nth-child(5){animation-delay:.25s}.stat:nth-child(6){animation-delay:.3s}.stat:nth-child(7){animation-delay:.35s}.stat:nth-child(8){animation-delay:.4s}
.stat-n{margin-top:24px;font:600 clamp(30px,2.6vw,42px)/1 var(--f-disp);letter-spacing:-.035em;font-variant-numeric:tabular-nums;color:var(--t)}
.stat-l{margin-top:12px;font:700 10.5px/1.3 var(--f-body);letter-spacing:.12em;text-transform:uppercase;color:var(--t2)}
.stat-sub{margin-top:8px;font-size:11.5px;line-height:1.45;color:var(--t3)}

/* ---------- 10 · CARDS · DOUBLE-BEZEL ---------- */
.card{
  position:relative;overflow:hidden;margin-bottom:28px;
  background:var(--card-bg);
  border:1px solid var(--b1);border-radius:24px;
  box-shadow:inset 0 1px 0 var(--hl),0 0 0 5px var(--ring),0 0 0 6px var(--ring-edge),var(--sh-lg);
  transition:border-color .6s var(--ease),box-shadow .6s var(--ease);
  animation:panelIn 1s var(--out) .1s backwards;
}
.card:hover{border-color:var(--b2)}
.card-h{
  position:relative;min-height:66px;padding:16px 24px;
  display:flex;align-items:center;justify-content:space-between;flex-wrap:wrap;gap:12px;
  background:linear-gradient(180deg,var(--chip),transparent);
  border-bottom:1px solid var(--b0);
}
.card-t{display:flex;align-items:center;gap:10px;font:600 15px/1.25 var(--f-disp);letter-spacing:0;color:var(--t)}
.card-b{padding:24px}
.g2,.g3{display:grid;gap:22px;align-items:start}
.g2{grid-template-columns:repeat(2,minmax(0,1fr))}
.g3{grid-template-columns:repeat(3,minmax(0,1fr))}
.g2>.card,.g3>.card{margin-bottom:0}
.fg{margin-bottom:18px}

/* mode widget + rail */
.mode-rail{position:relative;isolation:isolate}
.mode-rail::before{
  content:"";position:absolute;inset:-70%;z-index:-2;pointer-events:none;
  background:conic-gradient(from 120deg,transparent 0deg,rgba(110,231,183,.16) 70deg,rgba(129,140,248,.1) 150deg,transparent 235deg,rgba(110,231,183,.08) 300deg,transparent 360deg);
  filter:blur(36px);opacity:.6;
  animation:modeOrbit 28s linear infinite;
}
.mode-rail::after{
  content:"";position:absolute;inset:0;z-index:-1;pointer-events:none;
  background:radial-gradient(ellipse at 18% 0%,rgba(110,231,183,.12),transparent 46%),radial-gradient(ellipse at 88% 100%,rgba(129,140,248,.1),transparent 48%);
  animation:modeBreath 8s var(--glide) infinite alternate;
}
.mode-rail>.card-h,.mode-rail>.card-b{position:relative;z-index:1}
.mode-widget{
  isolation:isolate;
  background:var(--mode-bg);
  border-color:rgba(110,231,183,.26);
  box-shadow:inset 0 1px 0 rgba(255,255,255,.1),0 0 0 5px rgba(110,231,183,.035),0 0 0 6px rgba(110,231,183,.12),var(--sh-lg),0 0 70px -24px rgba(110,231,183,.28);
  animation:modeWidgetIn 1s var(--out) backwards;
}
html[data-dz-theme="light"] .mode-widget{border-color:rgba(5,150,105,.28);box-shadow:inset 0 1px 0 #fff,0 0 0 5px rgba(5,150,105,.04),0 0 0 6px rgba(5,150,105,.14),var(--sh-lg)}
.mode-widget::before{
  content:"";position:absolute;inset:-60%;z-index:-2;pointer-events:none;
  background:conic-gradient(from 0deg,transparent 0deg,rgba(110,231,183,.26) 55deg,rgba(129,140,248,.2) 125deg,transparent 195deg,rgba(110,231,183,.14) 275deg,transparent 360deg);
  filter:blur(42px);opacity:.55;
  animation:modeOrbit 24s linear infinite;
}
.mode-widget::after{
  content:"";position:absolute;left:0;right:0;top:0;height:1px;z-index:3;pointer-events:none;
  background:linear-gradient(90deg,transparent,var(--a),var(--a2),transparent);
  box-shadow:0 0 20px var(--a);
  animation:modeScan 6.5s var(--glide) infinite;
}
.mode-widget .card-h{
  min-height:84px;padding:20px 24px;
  background:linear-gradient(100deg,rgba(110,231,183,.12),rgba(129,140,248,.05) 55%,transparent);
  border-bottom-color:var(--b1);
}
.mode-widget .card-t{font:600 12px/1 var(--f-body);letter-spacing:.2em;text-transform:uppercase}
.mode-widget .card-t::before{content:"◈";font-size:18px;color:var(--a);text-shadow:0 0 16px var(--a)}
.mode-widget .card-b{padding:22px 24px}
.mode-widget{--stick:#0B1719;--stick-h:#10241f}
html[data-dz-theme="light"] .mode-widget{--stick:#F3FBF7;--stick-h:#E6F6EE}
.mode-widget .tw{background:rgba(3,7,11,.3);border-color:var(--b1)}
html[data-dz-theme="light"] .mode-widget .tw{background:rgba(255,255,255,.6)}
.mode-widget th{background:rgba(110,231,183,.06)}
.mode-widget td{padding-top:17px;padding-bottom:17px}
.mode-widget tbody tr td:first-child{color:var(--t);font-weight:650}

/* ---------- 11 · FORMS ---------- */
label{display:block;margin-bottom:8px;font:650 10.5px/1.4 var(--f-body);letter-spacing:.1em;text-transform:uppercase;color:var(--t2)}
input,select,textarea{
  width:100%;max-width:100%;min-height:46px;padding:11px 16px;
  background:var(--field);color:var(--t);
  border:1px solid var(--b1);border-radius:16px;
  font:500 13.5px/1.4 var(--f-body);
  outline:2px solid transparent;outline-offset:2px;
  box-shadow:inset 0 1px 2px rgba(0,0,0,.18);
  transition:border-color .45s var(--ease),box-shadow .45s var(--ease),background-color .45s var(--ease);
}
html[data-dz-theme="light"] input,html[data-dz-theme="light"] select,html[data-dz-theme="light"] textarea{box-shadow:inset 0 1px 2px rgba(15,23,42,.06)}
input:not([type=checkbox]):not([type=radio]),select,textarea{border-radius:16px!important}
input:hover,select:hover,textarea:hover{border-color:var(--b2)}
input:focus,select:focus,textarea:focus{
  background:var(--field-f);
  border-color:var(--a)!important;
  box-shadow:0 0 0 4px rgba(110,231,183,.14),0 0 28px -6px rgba(110,231,183,.45);
}
html[data-dz-theme="light"] input:focus,html[data-dz-theme="light"] select:focus,html[data-dz-theme="light"] textarea:focus{box-shadow:0 0 0 4px rgba(5,150,105,.14),0 0 24px -6px rgba(5,150,105,.35)}
input::placeholder,textarea::placeholder{color:var(--t3);opacity:1}
textarea{min-height:104px;resize:vertical}
select option{background:var(--s2);color:var(--t)}
input[type=checkbox],input[type=radio]{width:auto;min-height:0;accent-color:var(--a);box-shadow:none}
input[type=file]{padding:9px 12px}
input::file-selector-button{margin-right:12px;padding:6px 14px;border:1px solid var(--b2);border-radius:999px;background:var(--chip);color:var(--t);font:600 11.5px var(--f-body);cursor:pointer;transition:background-color .4s var(--ease)}
input::file-selector-button:hover{background:var(--chip-h)}
input:disabled,select:disabled,textarea:disabled{opacity:.5;cursor:not-allowed}
input:-webkit-autofill,input:-webkit-autofill:hover,input:-webkit-autofill:focus{
  -webkit-text-fill-color:var(--t);caret-color:var(--t);
  -webkit-box-shadow:0 0 0 1000px var(--s2) inset;
  transition:background-color 9999s linear 0s;
}
.sf{position:relative;margin-bottom:18px}
.sf input{padding-left:46px}
.sf::before{content:"⌕";position:absolute;left:17px;top:50%;transform:translateY(-52%);z-index:1;font-size:18px;line-height:1;color:var(--a);pointer-events:none}

/* ---------- 12 · BUTTONS ---------- */
.btn{
  position:relative;display:inline-flex;align-items:center;justify-content:center;gap:8px;
  min-height:44px;padding:0 22px;
  border:1px solid transparent;border-radius:999px;
  font:650 12.5px/1 var(--f-body);letter-spacing:-.005em;white-space:nowrap;
  cursor:pointer;user-select:none;-webkit-user-select:none;
  transition:transform .6s var(--spring),background-color .45s var(--ease),border-color .45s var(--ease),box-shadow .45s var(--ease),color .45s var(--ease),filter .45s var(--ease);
}
.btn:hover{transform:translateY(-2px)}
.btn:active{transform:translateY(0) scale(.97);transition-duration:.12s,.2s,.2s,.2s,.2s,.2s}
.b-sm{min-height:34px;padding:0 15px;font-size:11.5px}
.b-pr{
  color:var(--ink);
  background:linear-gradient(135deg,#9FF3CD 0%,#6EE7B7 45%,#34D399 100%);
  border-color:rgba(255,255,255,.28);
  box-shadow:inset 0 1px 0 rgba(255,255,255,.55),inset 0 -1px 0 rgba(0,0,0,.12),0 12px 32px -8px rgba(110,231,183,.5);
}
.b-pr:hover{filter:brightness(1.07);box-shadow:inset 0 1px 0 rgba(255,255,255,.6),inset 0 -1px 0 rgba(0,0,0,.12),0 18px 42px -8px rgba(110,231,183,.62)}
html[data-dz-theme="light"] .b-pr{background:linear-gradient(135deg,#10B981 0%,#059669 55%,#047857 100%);border-color:rgba(255,255,255,.2);box-shadow:inset 0 1px 0 rgba(255,255,255,.3),0 12px 28px -8px rgba(5,150,105,.5)}
html[data-dz-theme="light"] .b-pr:hover{box-shadow:inset 0 1px 0 rgba(255,255,255,.35),0 18px 38px -8px rgba(5,150,105,.6)}
.b-gh{background:var(--chip);border-color:var(--b1);color:var(--t2)}
.b-gh:hover{background:var(--chip-h);border-color:var(--b2);color:var(--t)}
.b-ok{background:var(--ok-bg);border-color:var(--ok-bd);color:var(--ok)}
.b-ok:hover{background:rgba(110,231,183,.18);box-shadow:0 10px 28px -10px rgba(110,231,183,.5)}
.b-w{background:var(--w-bg);border-color:var(--w-bd);color:var(--w)}
.b-w:hover{background:rgba(252,211,77,.17);box-shadow:0 10px 28px -10px rgba(252,211,77,.4)}
.b-e{background:var(--e-bg);border-color:var(--e-bd);color:var(--e)}
.b-e:hover{background:rgba(252,165,165,.17);box-shadow:0 10px 28px -10px rgba(252,165,165,.4)}
.b-info{background:var(--i-bg);border-color:var(--i-bd);color:var(--info)}
.b-info:hover{background:rgba(129,140,248,.2);box-shadow:0 10px 28px -10px rgba(129,140,248,.5)}
html[data-dz-theme="light"] .b-ok:hover{background:rgba(5,150,105,.17);box-shadow:0 10px 24px -10px rgba(5,150,105,.4)}
html[data-dz-theme="light"] .b-w:hover{background:rgba(217,119,6,.17);box-shadow:0 10px 24px -10px rgba(217,119,6,.35)}
html[data-dz-theme="light"] .b-e:hover{background:rgba(220,38,38,.14);box-shadow:0 10px 24px -10px rgba(220,38,38,.35)}
html[data-dz-theme="light"] .b-info:hover{background:rgba(79,70,229,.15);box-shadow:0 10px 24px -10px rgba(79,70,229,.4)}
.btn:disabled,.btn[aria-disabled="true"]{opacity:.45;cursor:not-allowed;filter:saturate(.5);box-shadow:none;transform:none;pointer-events:none}

/* ---------- 13 · TABLES (frosted heads) ---------- */
.tw{
  position:relative;width:100%;max-width:100%;overflow:auto;
  background:var(--tw-bg);
  border:1px solid var(--b1);border-radius:20px;
  box-shadow:inset 0 1px 0 var(--hl);
  overscroll-behavior-x:contain;-webkit-overflow-scrolling:touch;
}
table{width:100%;border-collapse:separate;border-spacing:0}
.tw table{min-width:760px}
th{
  position:sticky;top:0;z-index:2;padding:15px 18px;text-align:left;white-space:nowrap;
  font:700 10px/1.2 var(--f-body);letter-spacing:.14em;text-transform:uppercase;color:var(--t3);
  background:var(--th);
  -webkit-backdrop-filter:blur(18px) saturate(160%);backdrop-filter:blur(18px) saturate(160%);
  border-bottom:1px solid var(--b1);
}
td{padding:16px 18px;border-bottom:1px solid var(--b0);vertical-align:middle;font-size:13px;line-height:1.5;color:var(--t2)}
tbody tr:last-child td{border-bottom:0}
tbody tr td{transition:background-color .35s var(--ease),color .35s var(--ease)}
tbody tr:hover td{background:var(--row-h);color:var(--t)}
.tw td:last-child,.tw th:last-child{position:sticky;right:0;box-shadow:-16px 0 22px -14px rgba(0,0,0,.5)}
html[data-dz-theme="light"] .tw td:last-child,html[data-dz-theme="light"] .tw th:last-child{box-shadow:-16px 0 22px -14px rgba(15,23,42,.18)}
.tw td:last-child{z-index:1;background:var(--stick)}
.tw th:last-child{z-index:3;background:var(--stick)}
.tw tbody tr:hover td:last-child{background:var(--stick-h)}
.ui-empty-hint{margin-top:8px;font-size:12px;color:var(--t3)}

/* ---------- 14 · BADGES · ALERTS · MISC ---------- */
.bd{
  display:inline-flex;align-items:center;gap:7px;padding:5px 11px;border-radius:999px;
  font:650 11px/1.2 var(--f-body);letter-spacing:.01em;white-space:nowrap;
  border:1px solid transparent;
}
.bd::before{content:"";width:6px;height:6px;flex-shrink:0;border-radius:50%;background:currentColor;box-shadow:0 0 8px currentColor}
.bv{background:var(--ok-bg);border-color:var(--ok-bd);color:var(--ok)}
.bw,.bt{background:var(--w-bg);border-color:var(--w-bd);color:var(--w)}
.be{background:var(--e-bg);border-color:var(--e-bd);color:var(--e)}
.bb{background:var(--sky-bg);border-color:var(--sky-bd);color:var(--sky)}
.ba{background:var(--i-bg);border-color:var(--i-bd);color:var(--info)}
.tag{
  display:inline-flex;align-items:center;padding:4px 10px;border-radius:9px;
  background:var(--chip);border:1px solid var(--b1);
  font:600 11px/1.3 var(--f-body);color:var(--t2);
}
.al{
  display:flex;align-items:flex-start;gap:10px;margin-bottom:20px;padding:15px 18px;
  border:1px solid var(--b1);border-radius:18px;
  font-size:13px;line-height:1.55;
  box-shadow:inset 0 1px 0 var(--hl);
  animation:reveal .8s var(--out) backwards;
}
.al-e{background:var(--e-bg);border-color:var(--e-bd);color:var(--e)}
.al-s{background:var(--ok-bg);border-color:var(--ok-bd);color:var(--ok)}
.al-w{background:var(--w-bg);border-color:var(--w-bd);color:var(--w)}
.data-read-warning{margin:14px 0!important;border-color:var(--w-bd)!important}
.kb{
  max-height:240px;overflow-y:auto;padding:18px;
  background:rgba(0,0,0,.34);border:1px solid var(--b1);border-radius:18px;
  font:500 12px/1.9 var(--f-mono);color:var(--code);
  word-break:break-all;white-space:pre-wrap;
  box-shadow:inset 0 2px 10px rgba(0,0,0,.25);
}
html[data-dz-theme="light"] .kb{background:rgba(15,23,42,.045);box-shadow:inset 0 1px 4px rgba(15,23,42,.06)}
.mbar{
  padding:12px 18px;border-radius:999px;text-align:center;
  background:var(--w-bg);border:1px solid var(--w-bd);color:var(--w);
  font:700 11px/1.4 var(--f-body);letter-spacing:.08em;
}
.trial-glow{box-shadow:inset 0 1px 0 var(--hl),0 0 0 1px rgba(252,211,77,.2),0 22px 52px -20px rgba(252,211,77,.3)}
html[data-dz-theme="light"] .trial-glow{box-shadow:inset 0 1px 0 #fff,0 0 0 1px rgba(217,119,6,.26),0 22px 48px -20px rgba(217,119,6,.3)}
.exp-warn{color:var(--e)}
.exp-soon{color:var(--w)}
.sbar{height:6px;margin-top:10px;overflow:hidden;border-radius:999px;background:var(--track)}
.sbar-f{height:100%;border-radius:999px;background:linear-gradient(90deg,var(--a),var(--a2));box-shadow:0 0 14px rgba(110,231,183,.4);transform-origin:left center;animation:barGrow 1.3s var(--out) .3s backwards}
.sess-item{
  display:flex;align-items:center;justify-content:space-between;flex-wrap:wrap;gap:12px;
  margin-bottom:10px;padding:15px 18px;
  background:var(--chip);border:1px solid var(--b1);border-radius:18px;
  transition:border-color .45s var(--ease),background-color .45s var(--ease),transform .6s var(--ease);
}
.sess-item:hover{border-color:var(--b2);transform:translateX(3px)}
.sess-item.current{background:var(--glow);border-color:var(--a-line)}
.em{
  min-height:180px;padding:44px 20px;display:grid;justify-items:center;align-content:center;gap:0;text-align:center;
}
.em-ic{
  width:68px;height:68px;margin:0 auto 18px;display:grid;place-items:center;
  border-radius:22px;background:var(--chip);border:1px solid var(--b1);
  box-shadow:inset 0 1px 0 var(--hl),0 18px 40px -18px rgba(110,231,183,.35);
  font-size:30px;line-height:1;
}
.em-t{max-width:420px;font:600 17px/1.3 var(--f-disp);color:var(--t)}
.em-s{max-width:380px;margin-top:8px;font-size:13px;line-height:1.6;color:var(--t3)}
dialog,[role="dialog"]{
  border:1px solid var(--b2);border-radius:28px;background:var(--drawer);color:var(--t);
  box-shadow:inset 0 1px 0 var(--hl),0 0 0 6px var(--ring),var(--sh-lg);
}
dialog::backdrop{background:var(--scrim);-webkit-backdrop-filter:blur(6px);backdrop-filter:blur(6px)}

/* ---------- 15 · LICENCE DETAIL DRAWER ---------- */
.key-detail-scrim{
  position:fixed;inset:0;z-index:89;padding:0;border:0;
  background:var(--scrim);-webkit-backdrop-filter:blur(5px);backdrop-filter:blur(5px);
  opacity:0;visibility:hidden;
  transition:opacity .6s var(--ease),visibility 0s linear .6s;
}
.key-detail-scrim.show{opacity:1;visibility:visible;transition-delay:0s}
.key-detail-panel{
  position:fixed;inset:14px 14px 14px auto;z-index:90;
  width:min(470px,calc(100vw - 28px));padding:28px;overflow:auto;
  background:var(--drawer);color:var(--t);
  -webkit-backdrop-filter:blur(30px) saturate(160%);backdrop-filter:blur(30px) saturate(160%);
  border:1px solid var(--b1);border-radius:30px;
  box-shadow:inset 0 1px 0 var(--hl),0 0 0 5px var(--ring),0 0 0 6px var(--ring-edge),var(--sh-lg);
  transform:translateX(calc(100% + 40px));visibility:hidden;
  transition:transform .8s var(--ease),visibility 0s linear .8s;
}
.key-detail-panel.open{transform:translateX(0);visibility:visible;transition-delay:0s}
.key-detail-head{display:flex;align-items:flex-start;justify-content:space-between;gap:16px;padding-bottom:22px;border-bottom:1px solid var(--b0)}
.key-detail-head .card-t{font:700 9.5px/1 var(--f-body);letter-spacing:.2em;text-transform:uppercase;color:var(--a)}
.key-detail-head h2{margin-top:14px;font:600 24px/1.15 var(--f-disp);letter-spacing:-.02em;overflow-wrap:anywhere}
.key-detail-grid{display:grid;grid-template-columns:1fr 1fr;gap:12px;margin-top:22px}
.key-detail-grid>div{min-width:0;padding:15px 16px;background:var(--chip);border:1px solid var(--b0);border-radius:18px;box-shadow:inset 0 1px 0 var(--hl)}
.key-detail-grid .wide{grid-column:1/-1}
.key-detail-grid dt{margin-bottom:8px;font:700 9.5px/1.3 var(--f-body);letter-spacing:.14em;text-transform:uppercase;color:var(--t3)}
.key-detail-grid dd{margin:0;font-size:13px;font-weight:600;line-height:1.5;color:var(--t);overflow-wrap:anywhere;white-space:pre-wrap}
.key-cell{display:flex;align-items:center;gap:8px;min-width:0}
.key-cell code{overflow-wrap:anywhere}
.key-detail-button{
  flex:0 0 30px;width:30px;min-width:30px;height:30px;min-height:30px;padding:0;
  display:inline-grid;place-items:center;
  border:1px solid var(--b1);border-radius:50%;background:var(--chip);color:var(--a);font-size:14px;cursor:pointer;
  transition:background-color .45s var(--ease),border-color .45s var(--ease),transform .6s var(--spring);
}
.key-detail-button:hover{border-color:var(--a-line);background:var(--glow);transform:scale(1.12)}
.key-detail-button:active{transform:scale(.92)}

/* key actions */
.key-actions{align-items:center}
.key-menu-toggle{display:none;min-width:36px;min-height:36px;padding:0 10px;font-size:17px;line-height:1}
.key-action-menu{display:contents}
.key-action-menu-label{display:none}

/* ---------- 16 · AUTH · CINEMATIC SPLIT ---------- */
body.guest .content{width:100%;max-width:none;margin:0;padding:0}
.lw{
  position:relative;isolation:isolate;overflow:hidden;
  min-height:100vh;min-height:100dvh;
  display:grid;grid-template-columns:minmax(0,1.2fr) minmax(380px,.8fr);
  align-items:center;justify-items:center;
  gap:clamp(24px,5vw,90px);padding:clamp(24px,4vw,64px);
  background:
    radial-gradient(60% 55% at 22% 48%,rgba(110,231,183,.1),transparent 70%),
    radial-gradient(45% 50% at 82% 54%,rgba(129,140,248,.1),transparent 70%);
}
.lw::before{
  content:"";position:absolute;z-index:-1;left:-12vw;top:50%;width:min(76vw,1060px);aspect-ratio:1;
  transform:translateY(-50%);border-radius:50%;pointer-events:none;
  background:
    radial-gradient(circle,rgba(110,231,183,.22) 0 1px,transparent 2px),
    repeating-radial-gradient(circle,transparent 0 62px,rgba(110,231,183,.09) 63px 64px,transparent 65px 124px),
    conic-gradient(from 20deg,transparent 0 8%,rgba(110,231,183,.07) 8.1% 8.3%,transparent 8.4% 34%,rgba(129,140,248,.06) 34.1% 34.3%,transparent 34.4% 68%,rgba(110,231,183,.05) 68.1% 68.3%,transparent 68.4%);
  -webkit-mask-image:radial-gradient(circle,transparent 0 10%,#000 24% 66%,transparent 76%);
  mask-image:radial-gradient(circle,transparent 0 10%,#000 24% 66%,transparent 76%);
  animation:spin 160s linear infinite;
}
.lw::after{
  content:"DAVIZIN";position:absolute;z-index:-1;left:3vw;bottom:-1.4vw;pointer-events:none;white-space:nowrap;
  font:700 clamp(84px,16vw,248px)/.8 var(--f-disp);letter-spacing:-.05em;
  color:transparent;-webkit-text-stroke:1px var(--wm);
}
.lc:only-child{grid-column:1/-1;justify-self:center}
.auth-story{
  position:relative;z-index:1;justify-self:stretch;align-self:stretch;
  min-height:min(700px,82vh);padding:clamp(8px,2vw,28px) 0;
  display:flex;flex-direction:column;justify-content:space-between;color:var(--t);
}
.auth-brand{display:flex;align-items:center;gap:14px;animation:reveal 1s var(--out) backwards}
.auth-brand-mark{
  width:46px;height:46px;display:grid;place-items:center;border-radius:15px;
  background:linear-gradient(145deg,rgba(110,231,183,.22),rgba(129,140,248,.12));
  border:1px solid var(--a-line);color:var(--a);
  font:700 19px/1 var(--f-disp);
  box-shadow:inset 0 1px 0 rgba(255,255,255,.14),0 12px 30px -10px rgba(110,231,183,.5);
}
.auth-brand-name{display:block;font:600 16px/1 var(--f-disp);letter-spacing:.22em;color:var(--t)}
.auth-brand-meta{display:block;margin-top:8px;font:600 9px/1 var(--f-body);letter-spacing:.2em;color:var(--t3)}
.auth-copy{max-width:660px;margin:56px 0}
.auth-kicker{
  display:inline-flex;align-items:center;gap:10px;padding:8px 14px;border-radius:999px;
  background:var(--glow);border:1px solid var(--a-line);
  font:700 10px/1 var(--f-body);letter-spacing:.2em;text-transform:uppercase;color:var(--a);
  animation:reveal 1s var(--out) .1s backwards;
}
.auth-kicker::before{content:"";width:7px;height:7px;border-radius:50%;background:var(--a);box-shadow:0 0 0 0 var(--pulse);animation:pulse 2.6s var(--out) infinite}
.auth-copy h1{
  margin:28px 0 20px;
  font:600 clamp(48px,7vw,106px)/.92 var(--f-disp);letter-spacing:-.045em;color:var(--t);
  animation:reveal 1.2s var(--out) .18s backwards;
}
.auth-copy h1 em{
  font-style:normal;
  background:linear-gradient(110deg,var(--a) 10%,var(--a2) 90%);
  -webkit-background-clip:text;background-clip:text;
  -webkit-text-fill-color:transparent;color:transparent;
}
.auth-copy p{max-width:440px;font-size:16px;line-height:1.75;color:var(--t2);animation:reveal 1.2s var(--out) .28s backwards}
.auth-modules{display:flex;flex-wrap:wrap;gap:10px;margin-top:34px;animation:reveal 1.2s var(--out) .38s backwards}
.auth-modules span{
  padding:9px 14px;border-radius:999px;background:var(--chip);border:1px solid var(--b1);
  -webkit-backdrop-filter:blur(10px);backdrop-filter:blur(10px);
  font:650 10px/1 var(--f-body);letter-spacing:.12em;color:var(--t2);
  transition:border-color .45s var(--ease),color .45s var(--ease),transform .6s var(--spring);
}
.auth-modules span:hover{border-color:var(--a-line);color:var(--a);transform:translateY(-2px)}
.auth-footer{display:flex;justify-content:space-between;align-items:center;gap:18px;font:600 9.5px/1.4 var(--f-body);letter-spacing:.16em;color:var(--t3)}
.auth-footer i{display:inline-block;width:7px;height:7px;margin-right:10px;border-radius:50%;background:var(--ok);box-shadow:0 0 12px var(--ok)}
.auth-footer span:last-child{opacity:.7}

.lc{
  position:relative;z-index:1;grid-column:2;justify-self:center;
  width:min(100%,456px);max-width:456px;padding:clamp(32px,3.6vw,52px);
  background:var(--s1);
  -webkit-backdrop-filter:blur(34px) saturate(170%);backdrop-filter:blur(34px) saturate(170%);
  border:1px solid var(--b2);border-radius:34px;
  box-shadow:inset 0 1px 0 var(--hl),0 0 0 8px var(--ring),0 0 0 9px var(--ring-edge),var(--sh-lg),0 0 90px -30px rgba(110,231,183,.22);
  animation:panelIn 1.2s var(--out) .15s backwards;
}
.lc::before{
  content:"ACCESO / 01";position:absolute;top:22px;right:26px;
  font:700 9px/1 var(--f-body);letter-spacing:.2em;color:var(--t3);
}
.lc::after{
  content:"SESIÓN PROTEGIDA · DAVIZIN CONTROL";display:block;margin-top:26px;padding-top:18px;
  border-top:1px solid var(--b0);text-align:center;
  font:600 8.5px/1.4 var(--f-body);letter-spacing:.16em;color:var(--t3);
}
.l-logo{
  display:grid;grid-template-columns:60px minmax(0,1fr);grid-template-rows:auto auto;column-gap:16px;align-items:center;
  margin:4px 0 36px;text-align:left;
}
.l-ic{
  grid-column:1;grid-row:1/span 2;width:58px;height:58px;margin:0;display:grid;place-items:center;
  border-radius:19px;font-size:0;
  background:linear-gradient(145deg,rgba(110,231,183,.22),rgba(129,140,248,.1));
  border:1px solid var(--a-line);
  box-shadow:inset 0 1px 0 rgba(255,255,255,.14),0 14px 34px -12px rgba(110,231,183,.5);
}
.l-n{grid-column:2;grid-row:1;font:600 24px/1 var(--f-disp);letter-spacing:.16em;color:var(--t)}
.l-s{grid-column:2;grid-row:2;margin-top:8px;font-size:11.5px;letter-spacing:.02em;color:var(--t3)}
.lc .fg{margin-bottom:20px}
.lc input{min-height:54px;padding:0 18px;font-size:14px}
.lc .btn.b-pr{min-height:54px;margin-top:6px;font-size:14px}

/* ---------- 17 · DASHBOARD ---------- */
.dz-dashboard-head{display:flex;align-items:center;gap:20px;min-width:0}
.dz-dashboard-globe{
  position:relative;order:-1;display:block;flex:0 0 clamp(64px,6.4vw,88px);
  width:clamp(64px,6.4vw,88px);height:clamp(64px,6.4vw,88px);border-radius:50%;
  box-shadow:0 0 36px -4px rgba(110,231,183,.4),inset -8px -7px 18px rgba(0,0,0,.35);
  transition:transform .8s var(--spring),box-shadow .8s var(--ease);
}
.dz-dashboard-globe:hover{transform:translateY(-3px) rotate(-6deg) scale(1.04);box-shadow:0 0 48px -2px rgba(110,231,183,.55),inset -8px -7px 18px rgba(0,0,0,.35)}
.dz-dashboard-globe svg{position:relative;z-index:1;display:block;width:100%;height:100%;overflow:visible;border-radius:50%}
.dz-dashboard-globe .dz-globe-ocean{fill:var(--globe-ocean)}
.dz-dashboard-globe .dz-globe-land{fill:var(--globe-land);opacity:.92}
.dz-dashboard-globe .dz-globe-grid{fill:none;stroke:var(--globe-grid);stroke-width:.8}
.dz-dashboard-globe .dz-globe-edge{fill:none;stroke:var(--globe-edge);stroke-width:1}
.dz-dashboard-globe .dz-globe-sheen{fill:url(#dz-globe-shine);opacity:.55}
html[data-dz-theme="light"] .dz-dashboard-globe{box-shadow:0 10px 30px -8px rgba(5,150,105,.35)}

body.page-dashboard .ph{
  position:relative;isolation:isolate;overflow:hidden;
  min-height:176px;padding:clamp(24px,3.4vw,40px);margin-bottom:26px;
  background:
    radial-gradient(60% 120% at 92% 0%,rgba(110,231,183,.16),transparent 62%),
    radial-gradient(50% 100% at 0% 100%,rgba(129,140,248,.12),transparent 66%),
    var(--card-bg);
  border:1px solid var(--b1);border-radius:32px;
  box-shadow:inset 0 1px 0 var(--hl),0 0 0 5px var(--ring),0 0 0 6px var(--ring-edge),var(--sh-lg);
  animation:panelIn 1.1s var(--out) backwards;
}
body.page-dashboard .ph::before{
  content:"";position:absolute;inset:0;z-index:-1;pointer-events:none;opacity:.5;
  background-image:linear-gradient(var(--grid) 1px,transparent 1px),linear-gradient(90deg,var(--grid) 1px,transparent 1px);
  background-size:40px 40px;
  -webkit-mask-image:linear-gradient(110deg,#000,transparent 72%);mask-image:linear-gradient(110deg,#000,transparent 72%);
}
body.page-dashboard .ph::after{
  content:"";position:absolute;z-index:-1;right:4%;top:-250px;width:340px;height:340px;border-radius:50%;pointer-events:none;
  border:1px solid rgba(110,231,183,.2);
  box-shadow:0 0 0 28px rgba(110,231,183,.025),0 0 0 58px rgba(110,231,183,.018);
  animation:ambient 16s var(--glide) infinite alternate;
}
body.page-dashboard .ph h1{font-size:clamp(34px,4.2vw,56px)}
body.page-dashboard .sg{grid-template-columns:repeat(4,minmax(0,1fr))}

.dash-health{margin-bottom:28px}
.dash-health-top{position:relative;z-index:1;display:flex;align-items:flex-start;justify-content:space-between;gap:20px;padding:24px 28px 18px;border-bottom:1px solid var(--b0)}
.dash-eyebrow,.health-index{font:700 9.5px/1.4 var(--f-body);letter-spacing:.2em;text-transform:uppercase;color:var(--a)}
.dash-health-top h2{margin-top:9px;font:600 22px/1.2 var(--f-disp);letter-spacing:-.02em;color:var(--t)}
.dash-health-top p{margin-top:6px;font-size:13px;color:var(--t3)}
.dash-stamp{display:flex;align-items:center;gap:9px;padding:8px 13px;border-radius:999px;background:var(--chip);border:1px solid var(--b1);font:650 10px/1 var(--f-body);letter-spacing:.1em;color:var(--t3);white-space:nowrap}
.dash-stamp i,.health-marker{display:inline-block;width:7px;height:7px;border-radius:50%;background:var(--ok);box-shadow:0 0 12px var(--ok)}
.dash-stamp i{animation:beacon 2.4s var(--glide) infinite}
.dash-health-grid{position:relative;z-index:1;display:grid;grid-template-columns:156px minmax(220px,1fr) minmax(200px,.85fr);align-items:center;gap:26px;padding:24px 28px 28px}
.health-ring{
  --progress:0%;
  width:132px;height:132px;display:grid;place-items:center;border-radius:50%;
  background:conic-gradient(from 0deg,var(--a2) 0%,var(--a) var(--progress),var(--track) var(--progress) 100%);
  box-shadow:0 0 44px -6px rgba(110,231,183,.3);
  animation:ringIn 1.4s var(--out) backwards;
}
.health-ring-inner{width:102px;height:102px;display:flex;flex-direction:column;align-items:center;justify-content:center;border-radius:50%;background:var(--stick);border:1px solid var(--b1);box-shadow:inset 0 2px 12px rgba(0,0,0,.2)}
.health-ring-inner strong{font:600 30px/1 var(--f-disp);letter-spacing:-.04em;color:var(--t)}
.health-ring-inner span{margin-top:7px;font:700 8.5px/1 var(--f-body);letter-spacing:.16em;color:var(--t3)}
.health-stats{display:grid;gap:0}
.health-stats>div{display:flex;align-items:center;justify-content:space-between;gap:14px;padding:12px 0;border-bottom:1px solid var(--b0);font-size:13px;color:var(--t2)}
.health-stats>div:last-child{border-bottom:0}
.health-stats>div>span{display:flex;align-items:center;gap:10px}
.health-stats strong{font:600 17px/1 var(--f-disp);color:var(--t)}
.health-marker{width:8px;height:8px;box-shadow:none}
.health-marker.active{background:var(--ok);box-shadow:0 0 10px var(--ok)}
.health-marker.soon{background:var(--w);box-shadow:0 0 10px var(--w)}
.health-marker.paused{background:var(--t3)}
.health-callout{
  position:relative;min-height:122px;display:flex;flex-direction:column;justify-content:center;gap:10px;
  padding:20px 48px 20px 22px;
  background:linear-gradient(140deg,rgba(110,231,183,.12),rgba(129,140,248,.07));
  border:1px solid var(--b1);border-radius:22px;color:var(--t);
  box-shadow:inset 0 1px 0 var(--hl);
  transition:transform .7s var(--ease),border-color .5s var(--ease),box-shadow .7s var(--ease);
}
.health-callout:hover{transform:translateY(-4px);border-color:var(--a-line);box-shadow:inset 0 1px 0 var(--hl),0 24px 44px -22px rgba(110,231,183,.4)}
.health-callout:active{transform:translateY(-1px) scale(.98)}
.health-callout strong{font:600 17px/1.25 var(--f-disp)}
.health-callout>span:last-of-type{font-size:12px;color:var(--t3)}
.health-callout b{position:absolute;right:20px;top:20px;display:grid;place-items:center;width:30px;height:30px;border-radius:50%;background:var(--glow);border:1px solid var(--a-line);color:var(--a);font-size:14px;transition:transform .6s var(--spring)}
.health-callout:hover b{transform:translate(3px,-3px) scale(1.08)}

.dash-insights{display:grid;grid-template-columns:1fr 1fr;gap:22px;margin:0 0 28px}
.dash-insight-card{min-width:0;margin-bottom:0;padding:24px}
.dash-insight-head{display:flex;align-items:flex-start;justify-content:space-between;gap:14px;margin-bottom:18px}
.dash-insight-head h2{margin:8px 0 4px;font:600 20px/1.2 var(--f-disp);letter-spacing:-.02em;color:var(--t)}
.dash-insight-head p{margin:0;font-size:12.5px;line-height:1.55;color:var(--t3)}
.dash-insight-link,.dash-insight-footer{
  display:inline-flex;align-items:center;gap:8px;
  border:1px solid var(--a-line);border-radius:999px;color:var(--a);font-size:12px;font-weight:650;
  transition:background-color .45s var(--ease),transform .6s var(--spring);
}
.dash-insight-link{flex:0 0 auto;padding:8px 14px}
.dash-insight-link:hover,.dash-insight-footer:hover{background:var(--glow);transform:translateY(-2px)}
.dash-insight-kpis{display:grid;grid-template-columns:1fr 1fr;gap:10px;margin-bottom:16px}
.dash-insight-kpis>div{display:flex;align-items:baseline;gap:9px;padding:13px 15px;background:var(--chip);border:1px solid var(--b0);border-radius:16px;box-shadow:inset 0 1px 0 var(--hl)}
.dash-insight-kpis strong{font:600 26px/1 var(--f-disp);letter-spacing:-.03em;color:var(--t)}
.dash-insight-kpis span{font-size:11.5px;color:var(--t3)}
.dash-insight-list,.dash-seller-list{display:grid;gap:4px;align-content:start;min-height:70px}
.dash-insight-row{display:flex;align-items:center;justify-content:space-between;gap:14px;padding:11px 12px;border-bottom:1px solid var(--b0);border-radius:12px;font-size:12.5px;transition:background-color .35s var(--ease)}
.dash-insight-row:hover{background:var(--row-h)}
.dash-insight-name{overflow:hidden;text-overflow:ellipsis;white-space:nowrap;color:var(--t2)}
.dash-insight-count{flex:0 0 auto;font-weight:700;font-variant-numeric:tabular-nums;color:var(--a)}
.dash-insight-empty{padding:22px 12px;text-align:center;font-size:12.5px;color:var(--t3)}
.dash-seller-row{display:grid;grid-template-columns:30px minmax(80px,1fr) auto auto;align-items:center;gap:10px;padding:10px 12px;border-bottom:1px solid var(--b0);border-radius:12px;transition:background-color .35s var(--ease)}
.dash-seller-row:hover{background:var(--row-h)}
.dash-seller-rank{font:600 12px var(--f-disp);color:var(--t3)}
.dash-seller-label{min-width:0;overflow:hidden;text-overflow:ellipsis;white-space:nowrap;font-size:12.5px;color:var(--t2)}
.dash-seller-state{display:inline-block;margin-left:8px;font-size:9.5px;font-style:normal;font-weight:700;letter-spacing:.06em;color:var(--ok)}
.dash-seller-state.is-paused{color:var(--t3)}
.dash-seller-row>strong{white-space:nowrap;font:600 13px var(--f-disp);color:var(--ok)}
.dash-seller-row>strong small{font:500 10px var(--f-body);color:var(--t3)}
.dash-seller-total{white-space:nowrap;font-size:10.5px;color:var(--t3)}
.dash-seller-meter{display:block;height:3px;margin-top:6px;border-radius:3px;background:var(--track)}
.dash-seller-meter i{display:block;height:100%;border-radius:3px;background:linear-gradient(90deg,var(--a),var(--a2));box-shadow:0 0 10px rgba(110,231,183,.4);transform-origin:left center;animation:barGrow 1.2s var(--out) .3s backwards}
.dash-insight-footer{justify-content:space-between;width:100%;margin-top:14px;padding:12px 16px}
.dash-insight-footer b{font-size:15px}

body.page-expiring .ph{
  position:relative;overflow:hidden;padding:26px 28px;margin-bottom:26px;
  background:radial-gradient(60% 130% at 96% 0%,rgba(252,211,77,.13),transparent 62%),var(--card-bg);
  border:1px solid var(--b1);border-radius:28px;
  box-shadow:inset 0 1px 0 var(--hl),0 0 0 5px var(--ring),0 0 0 6px var(--ring-edge),var(--sh-md);
}
body.page-expiring .ph h1::before{border-color:var(--w-bd);color:var(--w);background:radial-gradient(circle at 13px 50%,var(--w) 0 2.5px,transparent 3.5px),var(--w-bg)}
body.page-expiring .stat:hover{box-shadow:inset 0 1px 0 var(--hl),0 34px 60px -26px rgba(0,0,0,.8),0 0 46px -18px rgba(252,211,77,.35)}
body.page-expiring .tw tbody tr{animation:reveal .7s var(--out) backwards}
body.page-expiring .tw tbody tr:nth-child(2){animation-delay:.03s}body.page-expiring .tw tbody tr:nth-child(3){animation-delay:.06s}body.page-expiring .tw tbody tr:nth-child(4){animation-delay:.09s}body.page-expiring .tw tbody tr:nth-child(5){animation-delay:.12s}
body.page-expiring .tw tbody tr:nth-child(6){animation-delay:.15s}body.page-expiring .tw tbody tr:nth-child(7){animation-delay:.18s}body.page-expiring .tw tbody tr:nth-child(8){animation-delay:.21s}body.page-expiring .tw tbody tr:nth-child(9){animation-delay:.24s}body.page-expiring .tw tbody tr:nth-child(10){animation-delay:.27s}

/* ---------- 18 · MOBILE DOCK ---------- */
.mobile-dock{display:none}

/* ---------- 19 · TOAST + CONFIRM MODAL (override JS inline styles) ---------- */
#ui-toasts>div{
  padding:13px 18px!important;
  background:var(--toast-bg)!important;
  -webkit-backdrop-filter:blur(26px) saturate(170%);backdrop-filter:blur(26px) saturate(170%);
  border:1px solid var(--b2)!important;border-radius:18px!important;
  color:var(--t)!important;
  font:600 12.5px/1.45 var(--f-body)!important;letter-spacing:-.003em;
  box-shadow:inset 0 1px 0 var(--hl),0 0 0 4px var(--ring),0 24px 50px -18px rgba(0,0,0,.65)!important;
  transition:opacity .5s var(--ease),transform .7s var(--spring)!important;
}
#ui-toasts>div[style*="90, 215, 160"]{border-color:var(--ok-bd)!important;box-shadow:inset 0 1px 0 var(--hl),0 0 0 4px var(--ring),0 24px 50px -18px rgba(0,0,0,.65),0 0 34px -10px var(--ok)!important}
#ui-toasts>div[style*="255, 111, 120"]{border-color:var(--e-bd)!important;box-shadow:inset 0 1px 0 var(--hl),0 0 0 4px var(--ring),0 24px 50px -18px rgba(0,0,0,.65),0 0 34px -10px var(--e)!important}
#ui-modal{
  background:var(--scrim)!important;
  -webkit-backdrop-filter:blur(8px)!important;backdrop-filter:blur(8px)!important;
  animation:fadeIn .5s var(--ease);
}
#ui-modal>div{
  padding:28px!important;
  background:var(--drawer)!important;
  border:1px solid var(--b2)!important;border-radius:30px!important;
  box-shadow:inset 0 1px 0 var(--hl),0 0 0 6px var(--ring),0 0 0 7px var(--ring-edge),var(--sh-lg)!important;
  animation:modalIn .8s var(--spring);
}
#ui-modal>div>div:first-child{font:700 10px/1.4 var(--f-body)!important;letter-spacing:.2em!important;color:var(--a)!important;margin-bottom:14px!important}
#ui-modal>div>div:nth-child(2){font:500 15px/1.6 var(--f-body)!important;color:var(--t)!important;margin-bottom:24px!important}

/* ---------- 20 · KEYFRAMES ---------- */
@keyframes reveal{from{opacity:0;transform:translate3d(0,28px,0) scale(.985)}to{opacity:1;transform:translate3d(0,0,0) scale(1)}}
@keyframes panelIn{from{opacity:0;transform:translate3d(0,22px,0) scale(.99)}to{opacity:1;transform:translate3d(0,0,0) scale(1)}}
@keyframes pulse{0%{box-shadow:0 0 0 0 var(--pulse)}70%,100%{box-shadow:0 0 0 10px transparent}}
@keyframes beacon{0%,100%{opacity:.5;transform:scale(.9)}50%{opacity:1;transform:scale(1.15)}}
@keyframes ambient{0%{transform:translate3d(0,0,0) scale(1)}50%{transform:translate3d(4vmax,3vmax,0) scale(1.08)}100%{transform:translate3d(-3vmax,5vmax,0) scale(.96)}}
@keyframes modeWidgetIn{from{opacity:0;transform:translate3d(0,26px,0) scale(.975)}to{opacity:1;transform:translate3d(0,0,0) scale(1)}}
@keyframes spin{from{rotate:0deg}to{rotate:360deg}}
@keyframes modeOrbit{from{transform:rotate(0deg)}to{transform:rotate(360deg)}}
@keyframes modeScan{0%,100%{transform:translate3d(-30%,0,0);opacity:.15}50%{transform:translate3d(30%,0,0);opacity:.95}}
@keyframes modeBreath{from{opacity:.45}to{opacity:.95}}
@keyframes ringIn{from{opacity:.2;transform:rotate(-60deg) scale(.86)}to{opacity:1;transform:rotate(0deg) scale(1)}}
@keyframes barGrow{from{transform:scaleX(0)}to{transform:scaleX(1)}}
@keyframes fadeIn{from{opacity:0}to{opacity:1}}
@keyframes modalIn{from{opacity:0;transform:translate3d(0,24px,0) scale(.94)}to{opacity:1;transform:translate3d(0,0,0) scale(1)}}
@keyframes ui-toast-in{from{opacity:0;transform:translate3d(0,10px,0)}to{opacity:1;transform:translate3d(0,0,0)}}

/* scroll-driven entry (progressive enhancement: fine pointers only) */
@supports (animation-timeline:view()){
  @media (hover:hover) and (pointer:fine){
    .content .card:not(.mode-widget):not(.dash-insight-card),
    .content>.tw,
    .content .dash-insights>.card{
      animation:reveal 1s cubic-bezier(.32,.72,0,1) backwards;
      animation-timeline:view();
      animation-range:entry 0% entry 60%;
    }
  }
}

/* ---------- 21 · RESPONSIVE ---------- */
@media (max-width:1180px){
  :root{--sw:244px}
  .content{padding-left:clamp(16px,2.4vw,30px);padding-right:clamp(16px,2.4vw,30px)}
  .dash-health-grid{grid-template-columns:132px minmax(200px,1fr) minmax(170px,.85fr);gap:20px;padding:22px}
  .health-ring{width:116px;height:116px}
  .health-ring-inner{width:90px;height:90px}
  .dash-health-top{padding:22px 22px 16px}
  .g3{grid-template-columns:repeat(2,minmax(0,1fr))}
}
@media (max-width:900px){
  :root{--sw:300px}
  .main{margin-left:0}
  .sb{
    inset:0 auto 0 0;width:min(86vw,var(--sw));border-radius:0 32px 32px 0;
    transform:translateX(-108%);visibility:hidden;
    transition:transform .8s var(--ease),visibility 0s linear .8s;
  }
  .sb.open{transform:none;visibility:visible;transition-delay:0s}
  .nav-scrim{display:block}
  .nav-scrim.show{opacity:1;pointer-events:auto}
  .nav-scrim:not(.show){pointer-events:none}
  .mobile-menu{display:inline-flex}
  .topbar{margin:12px 12px 0;top:12px;height:58px;padding:0 10px 0 12px}
  .tb-title::before{display:none}
  .content{padding:28px 18px 64px}
  .g2,.g3{grid-template-columns:repeat(2,minmax(0,1fr));gap:18px}
  .dash-insights{grid-template-columns:1fr}
  .key-detail-panel{inset:10px 10px 10px auto}
  /* compact key actions */
  .key-actions{position:relative;justify-content:flex-end;min-width:44px}
  .key-menu-toggle{display:inline-flex;width:38px;height:38px;align-items:center;justify-content:center}
  .key-action-menu{
    display:none;position:fixed;z-index:100;right:12px;top:12px;
    width:min(250px,calc(100vw - 24px));max-height:min(72vh,520px);overflow-y:auto;
    flex-direction:column;align-items:stretch;gap:8px;padding:12px;
    background:var(--drawer);border:1px solid var(--b2);border-radius:22px;
    box-shadow:inset 0 1px 0 var(--hl),0 0 0 4px var(--ring),var(--sh-lg);
    pointer-events:auto;touch-action:pan-y;
  }
  .key-action-menu.open{display:flex;animation:modalIn .6s var(--spring)}
  .key-action-menu-label{display:block;padding:4px 6px 10px;border-bottom:1px solid var(--b0);font:700 9.5px/1 var(--f-body);letter-spacing:.16em;text-transform:uppercase;color:var(--t3)}
  .key-action-menu>a.btn,.key-action-menu>form{width:100%;min-height:44px;justify-content:flex-start}
  .key-action-menu>form{display:flex!important;flex-wrap:wrap;align-items:center;gap:6px!important;margin:0!important}
  .key-action-menu>form input{flex:1 1 56px;width:auto!important;min-width:0}
  .key-action-menu>form button{min-width:42px}
  .key-action-menu a,.key-action-menu button,.key-action-menu input,.key-action-menu form{pointer-events:auto;touch-action:manipulation}
  .key-action-menu{z-index:130}
  button,a,input,select,textarea,label{touch-action:manipulation}
  /* login collapses */
  .lw{grid-template-columns:minmax(0,1fr);gap:8px;padding:28px 20px;align-content:center}
  .lw::before{left:50%;top:6%;width:150vw;transform:translate(-50%,0);opacity:.55}
  .lw::after{left:50%;bottom:auto;top:4%;transform:translateX(-50%);font-size:clamp(64px,22vw,150px)}
  .auth-story{min-height:0;align-self:auto;padding:4px 0 0}
  .auth-copy{margin:clamp(34px,8vh,60px) 0 26px}
  .auth-copy h1{font-size:clamp(44px,12vw,72px);margin:20px 0 14px}
  .auth-copy p{font-size:14px}
  .auth-modules{margin-top:22px}
  .auth-footer{margin:8px 0 22px}
  .auth-footer span:last-child{display:none}
  .lc{grid-column:1;width:min(100%,456px);margin:0 auto 20px;padding:36px 28px}
}
@media (max-width:760px){
  body.page-dashboard .sg{grid-template-columns:repeat(2,minmax(0,1fr))}
  .dash-health-grid{grid-template-columns:132px 1fr}
  .health-callout{grid-column:1/-1;min-height:92px}
}
@media (max-width:640px){
  html,body{overflow-x:hidden;overscroll-behavior-x:none}
  .topbar{margin:10px 10px 0;top:10px;height:56px;padding:0 8px 0 10px;gap:8px}
  .mobile-menu{width:42px;height:42px;border-radius:50%}
  .tb-right{gap:7px}
  .theme-toggle{min-width:42px;min-height:42px;padding:0 10px;border-radius:50%}
  .theme-toggle .theme-label{display:none}
  .pill{height:34px;padding:0 12px}
  .content{width:100%;min-width:0;padding:24px 12px calc(124px + env(safe-area-inset-bottom,0px));overflow-x:clip}
  .main{min-width:0}
  .ph{flex-direction:column;align-items:flex-start;gap:18px;margin-bottom:26px;padding-bottom:20px}
  .ph,.ph>div,.card,.tw{min-width:0;max-width:100%}
  .ph h1{font-size:clamp(28px,8.4vw,34px)}
  .ph h1,.ph p,.card-t{overflow-wrap:anywhere}
  .ph .acts{width:100%;gap:8px}
  .ph .acts .btn{flex:1 1 auto;min-width:0;max-width:100%;min-height:46px;padding-inline:14px;border-radius:16px;white-space:normal;text-align:center}
  .btn{min-height:46px}
  .b-sm{min-height:38px}
  .sg{grid-template-columns:repeat(2,minmax(0,1fr));gap:10px;margin-bottom:20px}
  .stat{min-height:122px;padding:16px 15px;border-radius:20px}
  .stat-n{margin-top:18px;font-size:clamp(24px,7.4vw,30px)}
  .stat-l{font-size:9.5px;letter-spacing:.1em}
  .card{border-radius:20px;margin-bottom:22px;box-shadow:inset 0 1px 0 var(--hl),0 0 0 4px var(--ring),0 0 0 5px var(--ring-edge),var(--sh-md)}
  .card-h{min-height:58px;padding:14px 16px}
  .card-b{min-width:0;padding:18px 16px}
  .g2,.g3{grid-template-columns:minmax(0,1fr);gap:20px}
  .tw{width:100%;margin:0;overflow-x:auto;overflow-y:visible;border-radius:16px;touch-action:pan-x pan-y}
  .tw table{min-width:720px}
  th,td{padding-left:14px;padding-right:14px}
  .tw th:first-child,.tw td:first-child{position:sticky;left:0;z-index:4;background:var(--stick);box-shadow:12px 0 18px -12px rgba(0,0,0,.5)}
  .tw th:first-child{z-index:5}
  .tw th:last-child,.tw td:last-child{z-index:5;min-width:60px}
  .tw th:last-child{z-index:6}
  .tw td:last-child .key-actions{min-width:44px;justify-content:center}
  .key-detail-panel{inset:0;width:100vw;max-width:100vw;max-height:100dvh;border-radius:0;padding:22px}
  .key-action-menu{width:calc(100vw - 24px);max-height:calc(100dvh - 24px);overscroll-behavior:contain;-webkit-overflow-scrolling:touch}
  /* dashboard */
  body.page-dashboard .ph{padding:22px 18px;min-height:150px;border-radius:26px}
  body.page-dashboard .sg{grid-template-columns:repeat(2,minmax(0,1fr));gap:10px}
  body.page-dashboard .sg .stat{min-height:112px;padding:14px 13px}
  .dz-dashboard-head{gap:14px}
  .dz-dashboard-globe{flex-basis:58px;width:58px;height:58px}
  .dash-health{margin-bottom:20px}
  .dash-health-top{align-items:flex-start;gap:10px;padding:18px 16px 14px}
  .dash-health-top h2{font-size:18px}
  .dash-stamp{font-size:8.5px;padding:7px 9px}
  .dash-health-grid{grid-template-columns:104px minmax(0,1fr);gap:14px;padding:16px}
  .health-ring{width:96px;height:96px}
  .health-ring-inner{width:74px;height:74px}
  .health-ring-inner strong{font-size:21px}
  .health-ring-inner span{font-size:7px;letter-spacing:.1em}
  .health-stats>div{gap:8px;padding:9px 0;font-size:11.5px}
  .health-stats strong{font-size:14px}
  .health-callout{grid-column:1/-1;min-height:78px;padding:15px 44px 15px 16px}
  .dash-insights{grid-template-columns:minmax(0,1fr);gap:20px;margin-bottom:22px}
  .dash-insight-card{padding:18px 16px}
  .dash-insight-head h2{font-size:18px}
  .dash-insight-kpis>div{min-height:50px}
  .dash-seller-row{grid-template-columns:24px minmax(0,1fr) auto;gap:8px;padding:10px 8px}
  .dash-seller-label{font-size:12px}
  .dash-seller-total{display:none}
  .dash-insight-footer{min-height:46px}
  body.page-expiring .ph{padding:20px 18px;border-radius:24px}
  /* login */
  .lc{padding:34px 24px;border-radius:30px}
  .lw{padding:22px 14px}
  /* dock */
  .mobile-dock{
    position:fixed;z-index:50;inset:auto 12px calc(12px + env(safe-area-inset-bottom,0px)) 12px;
    display:grid;grid-template-columns:repeat(5,minmax(0,1fr));gap:4px;padding:7px;
    background:var(--dock-bg);
    -webkit-backdrop-filter:blur(26px) saturate(170%);backdrop-filter:blur(26px) saturate(170%);
    border:1px solid var(--b2);border-radius:30px;
    box-shadow:inset 0 1px 0 var(--hl),0 0 0 4px var(--ring),0 30px 60px -20px rgba(0,0,0,.7);
  }
  .mobile-dock-item{
    min-width:0;min-height:54px;display:flex;flex-direction:column;align-items:center;justify-content:center;gap:4px;
    background:transparent;border:1px solid transparent;border-radius:22px;color:var(--t3);
    text-decoration:none;touch-action:manipulation;
    transition:background-color .45s var(--ease),color .45s var(--ease),border-color .45s var(--ease),transform .6s var(--spring);
  }
  .mobile-dock-item>span{font-size:19px;line-height:1;transition:transform .6s var(--spring)}
  .mobile-dock-item>small{max-width:100%;overflow:hidden;text-overflow:ellipsis;white-space:nowrap;font:650 9.5px/1.2 var(--f-body);letter-spacing:.01em}
  .mobile-dock-item:active{transform:scale(.92)}
  .mobile-dock-item.is-active{color:var(--a);background:linear-gradient(180deg,rgba(110,231,183,.16),rgba(110,231,183,.04));border-color:var(--a-line);box-shadow:inset 0 1px 0 var(--hl)}
  html[data-dz-theme="light"] .mobile-dock-item.is-active{background:linear-gradient(180deg,rgba(5,150,105,.14),rgba(5,150,105,.03))}
  .mobile-dock-item.is-active>span{transform:translateY(-1px) scale(1.08)}
  .mobile-dock-more{font-family:inherit;font-size:inherit;cursor:pointer}
  /* toast clears the dock */
  #ui-toasts{right:12px!important;left:12px!important;bottom:calc(96px + env(safe-area-inset-bottom,0px))!important;max-width:none!important}
}
@media (max-width:460px){
  .content{padding-left:10px;padding-right:10px}
  .stat-sub{font-size:10.5px}
  .card-b{padding:16px 14px}
  .key-detail-panel{padding:18px}
  .key-detail-grid{gap:8px}
  .key-detail-grid>div{padding:12px}
  .dash-insight-card{padding:16px 14px}
  .dash-seller-row{grid-template-columns:20px minmax(64px,1fr) auto}
  .dash-insight-kpis>div{padding:10px 9px;gap:6px}
  .dash-insight-kpis strong{font-size:22px}
  .auth-copy h1{font-size:clamp(40px,13vw,54px)}
  .auth-modules span{padding:8px 11px;font-size:9px}
  .lc{padding:32px 20px}
  .l-logo{margin-bottom:30px}
  .topbar .tb-title{font-size:15px}
}
@media (max-width:340px){
  .sg,body.page-dashboard .sg{grid-template-columns:1fr}
  .stat{min-height:108px}
  .acts .btn{width:100%}
  .mobile-dock{inset:auto 6px calc(8px + env(safe-area-inset-bottom,0px)) 6px;gap:2px;padding:5px}
  .mobile-dock-item>small{font-size:8.5px}
  .mobile-dock-item>span{font-size:17px}
  body.page-dashboard .dash-health-grid{grid-template-columns:84px minmax(0,1fr);gap:10px;padding:12px 10px}
  body.page-dashboard .health-ring{width:80px;height:80px}
  body.page-dashboard .health-ring-inner{width:62px;height:62px}
  .lc{padding:28px 16px}
  .pill{padding:0 10px;font-size:10.5px}
}

/* ---------- 22 · COARSE POINTER / LOW POWER ---------- */
@media (pointer:coarse),(max-width:640px){
  .global-atmosphere::before,.global-atmosphere::after,
  .mode-rail::before,.mode-rail::after,.mode-widget::before,.mode-widget::after,
  .lw::before,body.page-dashboard .ph::after,.pill::before,.auth-kicker::before,.dash-stamp i{animation:none}
  .mode-rail::before,.mode-widget::before{display:none}
  .topbar,.sb,.nav-scrim,.mobile-dock,.key-detail-panel,.key-detail-scrim,.key-action-menu,.lc,.auth-modules span,th,.tw th,#ui-toasts>div,#ui-modal,#ui-modal>div{
    -webkit-backdrop-filter:none!important;backdrop-filter:none!important;
  }
  .topbar{background:var(--s0)}
  .sb,.key-detail-panel,.key-action-menu,.lc{background:var(--drawer)}
  .mobile-dock{background:var(--drawer)}
  #ui-toasts>div{background:var(--drawer)!important}
  .stat::after{transition:none}
  .stat:hover,.btn:hover,.health-callout:hover,.sess-item:hover{transform:none}
  .tw,.card-b{min-width:0;max-width:100%}
  .tw{width:100%;overflow-x:auto;overflow-y:visible;touch-action:pan-x pan-y}
  .tw table{min-width:720px}
  .tw th:first-child,.tw td:first-child{position:sticky;left:0;z-index:4;background:var(--stick);box-shadow:12px 0 18px -12px rgba(0,0,0,.5)}
  .tw th:first-child{z-index:5}
  .tw th:last-child,.tw td:last-child{position:sticky;right:0;z-index:5;min-width:58px;background:var(--stick)}
  .tw th:last-child{z-index:6}
  .key-action-menu{position:fixed;z-index:130;right:12px;top:12px;pointer-events:auto;touch-action:pan-y}
  .nav-scrim:not(.show),.key-detail-scrim:not(.show){pointer-events:none}
}

/* ---------- 23 · ACCESSIBILITY · REDUCED MOTION ---------- */
@media (prefers-reduced-motion:reduce){
  html{scroll-behavior:auto}
  *,*::before,*::after{
    animation-duration:.001ms!important;animation-iteration-count:1!important;animation-delay:0s!important;
    transition-duration:.001ms!important;transition-delay:0s!important;scroll-behavior:auto!important;
  }
  .content .card,.content .tw,.stat,.ph{animation:none!important;animation-timeline:auto!important}
  .global-atmosphere::before,.global-atmosphere::after,.mode-rail::before,.mode-widget::before,.mode-widget::after,.lw::before{animation:none!important}
  .btn:hover,.stat:hover,.sb-lnk:hover,.health-callout:hover,.dz-dashboard-globe:hover{transform:none!important}
}
@media (forced-colors:active){
  .btn,.card,.stat,.tw,input,select,textarea,.sb,.topbar{border:1px solid CanvasText}
  .sb-lnk.on{outline:2px solid Highlight}
}
`;

function wrap(title,body,ses){
  const sa=ses?.role==='superadmin',me=ses?.user||'';
  const init=(me.charAt(0)||'D').toUpperCase();
  const mark='<span class="brand-glyph" aria-hidden="true"></span>';
  const mobileDock=ses?`<nav class="mobile-dock" aria-label="Navegación rápida">
<a href="/dashboard" class="mobile-dock-item ${title==='Dashboard'?'is-active':''}" ${title==='Dashboard'?'aria-current="page"':''}><span aria-hidden="true">◫</span><small>Inicio</small></a>
<a href="/keys" class="mobile-dock-item ${title==='Keys'?'is-active':''}" ${title==='Keys'?'aria-current="page"':''}><span aria-hidden="true">⌁</span><small>Keys</small></a>
${sa?`<a href="/vendors" class="mobile-dock-item ${title==='Vendedores'?'is-active':''}" ${title==='Vendedores'?'aria-current="page"':''}><span aria-hidden="true">◇</span><small>Vendedores</small></a><a href="/devices" class="mobile-dock-item ${title==='Dispositivos'?'is-active':''}" ${title==='Dispositivos'?'aria-current="page"':''}><span aria-hidden="true">▯</span><small>Equipos</small></a>`:`<a href="/keys/create-trial" class="mobile-dock-item ${title==='Trial'?'is-active':''}" ${title==='Trial'?'aria-current="page"':''}><span aria-hidden="true">◷</span><small>Trial</small></a><a href="/trash" class="mobile-dock-item ${title==='Papelera'?'is-active':''}" ${title==='Papelera'?'aria-current="page"':''}><span aria-hidden="true">⌫</span><small>Papelera</small></a>`}
<button type="button" class="mobile-dock-item mobile-dock-more" aria-label="Abrir el menú completo" onclick="toggleNav(true)"><span aria-hidden="true">☰</span><small>Más</small></button>
</nav>`:'';
  const nav=ses?`
<aside class="sb" id="sb">
<div class="sb-top"><div class="sb-logo"><div class="sb-icon">${mark}</div><div><div class="sb-name">DAVIZIN</div><div class="sb-ver">Control Ledger · v2.0</div></div></div></div>
<nav class="sb-nav">
<div class="sb-sec">Principal</div>
<a href="/dashboard" class="sb-lnk ${title==='Dashboard'?'on':''}"><span class="ic">◫</span>Dashboard</a>
<a href="/keys" class="sb-lnk ${title==='Keys'?'on':''}"><span class="ic">⌁</span>Keys</a><a href="/pause-mine" class="sb-lnk ${title==='Pausar mis Keys'?'on':''}"><span class="ic">⏸</span>Pausar mis Keys</a>
<a href="/keys/create-trial" class="sb-lnk ${title==='Trial'?'on':''}"><span class="ic">◷</span>Crear Trial</a>
<a href="/trash" class="sb-lnk ${title==='Papelera'?'on':''}"><span class="ic">⌫</span>Papelera</a>
${sa?`<div class="sb-sec">Administración</div>
<a href="/vendors" class="sb-lnk ${title==='Vendedores'?'on':''}"><span class="ic">◇</span>Vendedores</a>
<a href="/precios" class="sb-lnk ${title==='Precios'?'on':''}"><span class="ic">💲</span>Precios</a>
<a href="/devices" class="sb-lnk ${title==='Dispositivos'?'on':''}"><span class="ic">▯</span>Dispositivos</a><a href="/ips" class="sb-lnk ${title==='IPs'?'on':''}"><span class="ic">🌐</span>IPs</a><a href="/live" class="sb-lnk ${title==='Live'?'on':''}"><span class="ic">◉</span>En Vivo</a> <a href="/usage" class="sb-lnk ${title==='Uso'?'on':''}"><span class="ic">▥</span>Estadísticas de uso</a>
<a href="/bans" class="sb-lnk ${title==='Bans'?'on':''}"><span class="ic">⊘</span>Bans</a>
<a href="/sessions" class="sb-lnk ${title==='Sesiones'?'on':''}"><span class="ic">◎</span>Sesiones</a>
<a href="/activity" class="sb-lnk ${title==='Actividad'?'on':''}"><span class="ic">≡</span>Actividad</a>
<a href="/anuncio" class="sb-lnk ${title==='Anuncio'?'on':''}"><span class="ic">📢</span>Anuncio Global</a><a href="/tiempo" class="sb-lnk ${title==='Tiempo'?'on':''}"><span class="ic">⏳</span>Agregar Tiempo</a><a href="/maintenance" class="sb-lnk ${title==='Sistema'?'on':''}"><span class="ic">⚙</span>Sistema</a><a href="/app-builds" class="sb-lnk ${title==='Builds permitidos'?'on':''}"><span class="ic">▣</span>Builds permitidos</a>
<div class="sb-sec">Contenido</div>
<a href="/avatarfiles" class="sb-lnk ${title==='Avatar Files'?'on':''}"><span class="ic">🎭</span>Avatar Files</a>`:''}
</nav>
<div class="sb-bottom"><div class="sb-user"><div class="sb-avatar">${init}</div><div><div class="sb-uname">${me}</div><div class="sb-urole">${sa?'Superadmin':'Vendedor'}</div></div></div><a href="/logout" class="sb-out">↗ Cerrar sesión</a></div>
</aside>`:'';
  return new Response(`<!DOCTYPE html><html lang="es"><head>
<meta charset="UTF-8"><meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover"><meta name="theme-color" content="#05070A">
<script>try{if(localStorage.getItem("dz-panel-theme")==="light")document.documentElement.dataset.dzTheme="light"}catch(e){}</script>
<title>${title} · Davizin</title><style>${CSS}</style></head><body class="${ses?`has-session ${title==='Dashboard'?'page-dashboard':title==='Por vencer'?'page-expiring':''}`:'guest'}">
${nav}<div class="global-atmosphere" aria-hidden="true"></div>${ses?'<button class="nav-scrim" id="navScrim" aria-label="Cerrar navegación" onclick="toggleNav(false)"></button>':''}
<div class="main ${ses?'':'guest-main'}">
${ses?`<div class="topbar"><div style="display:flex;align-items:center;gap:11px"><button class="mobile-menu" type="button" aria-label="Abrir navegación" onclick="toggleNav(true)">☰</button><span class="tb-title">${title}</span></div><div class="tb-right"><button class="theme-toggle" id="themeToggle" type="button" aria-label="Cambiar tema" aria-pressed="false" title="Cambiar a tema claro"><span class="theme-icon" aria-hidden="true">◐</span><span class="theme-label">Oscuro</span></button><span class="pill">En línea</span></div></div>`:''}
<div class="content">${body}</div>${ses&&title==='Keys'?`
<button id="keyDetailScrim" class="key-detail-scrim" type="button" aria-label="Cerrar detalle de licencia" tabindex="-1"></button>
<aside id="keyDetailPanel" class="key-detail-panel" role="dialog" aria-modal="true" aria-labelledby="keyDetailTitle" aria-hidden="true"><div class="key-detail-head"><div><span class="card-t">DETALLE DE LICENCIA</span><h2 id="keyDetailTitle">Licencia</h2></div><button type="button" id="keyDetailClose" class="btn b-gh b-sm" aria-label="Cerrar detalle">×</button></div><dl class="key-detail-grid"><div><dt>Estado</dt><dd id="detailStatus">—</dd></div><div><dt>Tipo</dt><dd id="detailType">—</dd></div><div><dt>Plan</dt><dd id="detailTier">—</dd></div><div><dt>Tiempo restante</dt><dd id="detailRemaining">—</dd></div><div><dt>Vencimiento</dt><dd id="detailExpiry">—</dd></div><div><dt>Usos</dt><dd id="detailUses">—</dd></div><div><dt>Vendedor</dt><dd id="detailVendor">—</dd></div><div class="wide"><dt>Dispositivo</dt><dd id="detailDevice">—</dd></div><div class="wide"><dt>Nota</dt><dd id="detailNote">—</dd></div><div><dt>Motivo de pausa</dt><dd id="detailPauseReason">—</dd></div><div><dt>Motivo de bloqueo</dt><dd id="detailLockReason">—</dd></div><div class="wide"><dt>Anuncio</dt><dd id="detailNotice">—</dd></div><div><dt>Última IP</dt><dd id="detailLastIp">—</dd></div><div><dt>Ubicación</dt><dd id="detailLocation">—</dd></div><div class="wide"><dt>HWID</dt><dd id="detailHwid">—</dd></div><div class="wide" style="display:flex;justify-content:flex-end"><a id="detailHistoryLink" class="btn b-gh b-sm" href="#">⌁ Ver historial</a></div></dl></aside>`:''}${mobileDock}</div>
<script>
function closeKeyActionMenus(restoreFocus=false){document.querySelectorAll('.key-action-menu.open').forEach(menu=>{menu.classList.remove('open');const toggle=[...document.querySelectorAll('.key-menu-toggle')].find(button=>button.getAttribute('aria-controls')===menu.id);toggle?.setAttribute('aria-expanded','false');if(menu._keyActionsHome?.isConnected){menu._keyActionsHome.insertBefore(menu,menu._keyActionsAfter?.parentNode===menu._keyActionsHome?menu._keyActionsAfter:null);delete menu._keyActionsHome;delete menu._keyActionsAfter;menu.removeAttribute('data-floating');menu.style.top='';menu.style.right=''}if(restoreFocus)toggle?.focus()})}
function toggleKeyActionMenu(toggle){const id=toggle.getAttribute('aria-controls'),menu=id?document.getElementById(id):null;if(!menu)return;const shouldOpen=!menu.classList.contains('open');closeKeyActionMenus();if(!shouldOpen)return;if(matchMedia('(max-width:900px),(pointer:coarse)').matches&&menu.parentElement?.classList.contains('key-actions')){menu._keyActionsHome=menu.parentElement;menu._keyActionsAfter=menu.nextSibling;document.body.appendChild(menu);menu.setAttribute('data-floating','true')}menu.classList.add('open');toggle.setAttribute('aria-expanded','true');const r=toggle.getBoundingClientRect(),h=menu.getBoundingClientRect().height;menu.style.top=Math.max(8,Math.min(r.bottom+6,innerHeight-h-8))+'px';menu.style.right=Math.max(8,innerWidth-r.right)+'px'}
document.addEventListener('click',event=>{const target=event.target;if(!(target instanceof Element))return;const toggle=target.closest('.key-menu-toggle');if(toggle){event.preventDefault();toggleKeyActionMenu(toggle);return}const inside=target.closest('.key-action-menu');if(inside){if(target.closest('a,button,input,select,textarea,label,form'))return;closeKeyActionMenus();return}closeKeyActionMenus()});
document.addEventListener('keydown',event=>{if(event.key==='Escape')closeKeyActionMenus(true)});document.addEventListener('touchend',event=>{if(!matchMedia('(pointer:coarse)').matches)return;const el=event.target instanceof Element?event.target.closest('.key-action-menu a,.key-action-menu button,.key-actions>a,.key-actions>button'):null;if(!el||el.disabled||el.dataset.dzTouchPending)return;el.dataset.dzTouchPending='1';event.preventDefault();setTimeout(()=>{el.click();setTimeout(()=>{delete el.dataset.dzTouchPending},350)},0)},{passive:false});
window.addEventListener('resize',()=>closeKeyActionMenus());

function applyTheme(light){document.documentElement.dataset.dzTheme=light?'light':'dark';const b=document.getElementById('themeToggle');if(b){b.setAttribute('aria-pressed',String(light));const label=b.querySelector('.theme-label');const action=light?'Cambiar a tema oscuro':'Cambiar a tema claro';if(label)label.textContent=light?'Oscuro':'Claro';b.title=action;b.setAttribute('aria-label',action);}}
function toggleTheme(){const light=document.documentElement.dataset.dzTheme!=='light';applyTheme(light);try{localStorage.setItem('dz-panel-theme',light?'light':'dark')}catch(e){}}
let savedTheme='dark';try{savedTheme=localStorage.getItem('dz-panel-theme')||'dark'}catch(e){}applyTheme(savedTheme==='light');document.getElementById('themeToggle')?.addEventListener('click',toggleTheme);
let keyDetailReturnFocus=null,keyDetailPreviousOverflow='';
function closeKeyDetail(){const panel=document.getElementById('keyDetailPanel');if(!panel||!panel.classList.contains('open'))return;panel.classList.remove('open');panel.setAttribute('aria-hidden','true');document.getElementById('keyDetailScrim')?.classList.remove('show');document.body.style.overflow=keyDetailPreviousOverflow;if(keyDetailReturnFocus?.isConnected)keyDetailReturnFocus.focus();keyDetailReturnFocus=null;}
function openKeyDetail(button){try{const data=JSON.parse(decodeURIComponent(button.dataset.keyDetail||''));const panel=document.getElementById('keyDetailPanel');if(!panel)return;if(!panel.classList.contains('open'))keyDetailPreviousOverflow=document.body.style.overflow;const fields={key:'keyDetailTitle',status:'detailStatus',type:'detailType',tier:'detailTier',remaining:'detailRemaining',expiry:'detailExpiry',uses:'detailUses',vendor:'detailVendor',device:'detailDevice',note:'detailNote',pauseReason:'detailPauseReason',lockReason:'detailLockReason',notice:'detailNotice',lastIp:'detailLastIp',location:'detailLocation',hwid:'detailHwid'};for(const [key,id] of Object.entries(fields)){const node=document.getElementById(id);if(node)node.textContent=String(data[key]??'—')}const historyLink=document.getElementById('detailHistoryLink');if(historyLink)historyLink.href='/keys/'+encodeURIComponent(data.key)+'/history';keyDetailReturnFocus=button;panel.classList.add('open');panel.setAttribute('aria-hidden','false');document.getElementById('keyDetailScrim')?.classList.add('show');document.body.style.overflow='hidden';document.getElementById('keyDetailClose')?.focus();}catch(e){toast('No se pudieron cargar los detalles','err')}}
document.addEventListener('click',event=>{const target=event.target;if(!(target instanceof Element))return;const button=target.closest('.key-detail-button');if(button){openKeyDetail(button);return}if(target.closest('#keyDetailClose,#keyDetailScrim'))closeKeyDetail()});
document.addEventListener('keydown',event=>{const panel=document.getElementById('keyDetailPanel');if(!panel?.classList.contains('open'))return;if(event.key==='Escape'){closeKeyDetail();return}if(event.key==='Tab'){event.preventDefault();document.getElementById('keyDetailClose')?.focus()}});

function toggleNav(open){const sb=document.getElementById('sb'),sc=document.getElementById('navScrim');if(!sb)return;sb.classList.toggle('open',open);sc?.classList.toggle('show',open);document.body.style.overflow=open?'hidden':'';}
function ft(inp,tid){const v=inp.value.toLowerCase();document.querySelectorAll('#'+tid+' tr').forEach(r=>{r.style.display=r.innerText.toLowerCase().includes(v)?'':'none'});}
function cp(id,btn){const el=document.getElementById(id);if(!el)return;const text=el.innerText||el.value||'';const done=()=>{const old=btn.textContent;btn.textContent='✓ Copiado';toast('Copiado al portapapeles','ok');setTimeout(()=>btn.textContent=old||'Copiar',1800)};if(navigator.clipboard&&window.isSecureContext){navigator.clipboard.writeText(text).then(done).catch(()=>{toast('No se pudo copiar','err')})}else{const ta=document.createElement('textarea');ta.value=text;ta.style.position='fixed';ta.style.opacity='0';document.body.appendChild(ta);ta.select();try{document.execCommand('copy');done()}catch(e){toast('No se pudo copiar','err')}ta.remove()}};
function csv(id,name){const rows=[...document.querySelectorAll('#'+id+' tr')];const c=rows.map(r=>[...r.querySelectorAll('th,td')].slice(0,-1).map(c=>'"'+c.innerText.replace(/"/g,'""')+'"').join(',')).join('\\n');const a=document.createElement('a');a.href='data:text/csv;charset=utf-8,\\uFEFF'+encodeURIComponent(c);a.download=name+'.csv';a.click();}
function delAll(){if(!confirm('⚠️ ¿Estás SEGURO de eliminar TODAS las keys?'))return;if(!confirm('🔴 ÚLTIMA ADVERTENCIA — Esta acción es IRREVERSIBLE. ¿Confirmas definitivamente?'))return;document.getElementById('daForm').submit();}
/* UI_FEEDBACK_V1 */ /* SYSTEM_BUTTON_FIX_V1 */
function toast(msg,kind='info'){let host=document.getElementById('ui-toasts');if(!host){host=document.createElement('div');host.id='ui-toasts';host.setAttribute('aria-live','polite');host.style.cssText='position:fixed;right:18px;bottom:18px;z-index:120;display:grid;gap:8px;max-width:min(360px,calc(100vw - 36px));font-family:inherit';document.body.appendChild(host)}const el=document.createElement('div');el.textContent=msg;el.style.cssText='padding:11px 14px;border:1px solid rgba(184,218,232,.16);border-radius:10px 4px 10px 4px;background:rgba(10,22,34,.96);color:#eff8fb;box-shadow:0 14px 34px rgba(0,0,0,.3);font-size:11px;opacity:0;transform:translateY(8px);transition:opacity .18s ease,transform .18s ease';if(kind==='ok')el.style.borderColor='rgba(90,215,160,.4)';if(kind==='err')el.style.borderColor='rgba(255,111,120,.45)';host.appendChild(el);requestAnimationFrame(()=>{el.style.opacity='1';el.style.transform='translateY(0)'});setTimeout(()=>{el.style.opacity='0';el.style.transform='translateY(8px)';setTimeout(()=>el.remove(),220)},2600)}
document.addEventListener('submit',e=>{const form=e.target;if(!form||form.dataset.uiBusy==='1')return;form.dataset.uiBusy='1';const b=form.querySelector('button[type=submit],button:not([type])');if(b&&b.name!=='action'){b.disabled=true;b.dataset.uiOriginal=b.textContent;b.textContent='Procesando…'}else if(b){b.dataset.uiOriginal=b.textContent;b.textContent='Procesando…'}toast('Procesando…','info')});
document.addEventListener('click',e=>{const b=e.target.closest('button');if(!b||b.disabled)return;if((b.type==='submit'||b.closest('form'))&&b.name!=='action'){setTimeout(()=>{if(!b.disabled){b.disabled=true;b.dataset.uiOriginal=b.textContent;b.textContent='Procesando…'}},0)}});
/* UI_MODAL_MOBILE_V1 */
function uiModal(message,go){let x=document.getElementById('ui-modal');if(x)x.remove();x=document.createElement('div');x.id='ui-modal';x.setAttribute('role','dialog');x.setAttribute('aria-modal','true');x.style.cssText='position:fixed;inset:0;z-index:130;display:grid;place-items:center;padding:18px;background:rgba(2,5,9,.72);backdrop-filter:blur(5px)';x.innerHTML='<div style="width:min(420px,100%);padding:22px;background:linear-gradient(150deg,rgba(14,27,41,.98),rgba(8,16,26,.99));border:1px solid rgba(184,218,232,.2);border-radius:16px 5px 16px 5px;box-shadow:0 28px 90px rgba(0,0,0,.5)"><div style="font:600 11px/1.4 IBM Plex Mono,monospace;text-transform:uppercase;letter-spacing:.1em;color:#58d6e8;margin-bottom:12px">Confirmar acción</div><div style="font-size:13px;line-height:1.5;color:#eff8fb;margin-bottom:20px"></div><div style="display:flex;justify-content:flex-end;gap:8px"><button type="button" class="btn b-gh b-sm" data-cancel>Cancelar</button><button type="button" class="btn b-e b-sm" data-ok>Continuar</button></div></div>';x.querySelector('div div').textContent=message;const close=()=>x.remove();x.querySelector('[data-cancel]').onclick=close;x.querySelector('[data-ok]').onclick=()=>{close();go()};x.onclick=e=>{if(e.target===x)close()};document.body.appendChild(x);x.querySelector('[data-ok]').focus()}
document.addEventListener('click',e=>{const a=e.target.closest('a[onclick*="confirm("]');if(!a||a.dataset.uiModalHandled==='1')return;e.preventDefault();e.stopImmediatePropagation();const href=a.href;const text=(a.getAttribute('title')||a.textContent||'Confirmar esta acción').trim();uiModal(text,()=>{window.location.href=href})},true);
/* KEY_FILTER_UI_V1 */
(function(){if(!document.title.startsWith('Keys'))return;const host=document.querySelector('.ph .acts');if(!host||document.getElementById('key-filter-actions'))return;const box=document.createElement('div');box.id='key-filter-actions';box.className='acts';box.style.cssText='width:100%;margin-top:4px;justify-content:flex-end';box.innerHTML='<a class="btn b-e b-sm" href="/keys?status=expired">Aparecer todas las expiradas</a><a class="btn b-ok b-sm" href="/keys?status=active">Aparecer todas las activas</a><a class="btn b-w b-sm" href="/keys?status=unused">Aparecer todas las que no han sido usadas</a>';host.parentNode.appendChild(box)})();
document.addEventListener('keydown',e=>{if(e.key==='Escape')toggleNav(false)});document.querySelectorAll('.sb-lnk').forEach(a=>a.addEventListener('click',()=>toggleNav(false)));
</script></body></html>`,{headers:{'Content-Type':'text/html;charset=UTF-8','Cache-Control':ses?'private, no-cache, no-store, must-revalidate, max-age=0':'public, max-age=30, s-maxage=30','Pragma':ses?'no-cache':'','Expires':ses?'0':''}});
}

function loginPg(err=false){
  return wrap('Login',`<div class="lw"><section class="auth-story"><div class="auth-brand"><span class="auth-brand-mark">D</span><div><span class="auth-brand-name">DAVIZIN</span><small class="auth-brand-meta">CONTROL / OPERATIONS</small></div></div><div class="auth-copy"><span class="auth-kicker">PANEL DE OPERACIÓN</span><h1>Todo en su<br/><em>lugar.</em></h1><p>Accesos, equipos y distribución en un mismo espacio de control.</p><div class="auth-modules"><span>01 / LICENCIAS</span><span>02 / DISPOSITIVOS</span><span>03 / VENDEDORES</span></div></div><div class="auth-footer"><span><i></i>ACCESO PRIVADO</span><span>DAVIZIN / CONTROL DESK</span></div></section><div class="lc">
<div class="l-logo"><div class="l-ic"><span aria-hidden="true" class="brand-glyph mini"></span></div><div class="l-n">DAVIZIN</div><div class="l-s">Key Management System</div></div>
${err?'<div class="al al-e">⚠ Usuario o contraseña incorrectos.</div>':''}
<form method="POST">
<div class="fg"><label>Usuario</label><input autocomplete="username" name="u" placeholder="Ingresa tu usuario" required=""/></div>
<div class="fg"><label>Contraseña</label><input autocomplete="current-password" name="p" placeholder="••••••••••" required="" type="password"/></div>
<button class="btn b-pr" style="width:100%;padding:11px 16px;margin-top:6px;font-size:13px">Iniciar sesión →</button>
</form></div></div>`);
}

async function modeDefinitions(env){
  const defaults=[
    {id:'drag',label:'Drag',enabled:true,enabledMax:true,enabledNormal:true,accessTier:'basic',oneTime:false,consumed:false,pathMax:null,pathNormal:null,noticeTitle:'⚠️ Drag — Precaución',noticeBody:'Modo para mejorar el arrastre y la precisión. Puede variar según la actualización.',noticeLevel:'yellow',noticeEnabled:true},
    {id:'pecho',label:'Pecho',enabled:true,enabledMax:true,enabledNormal:true,accessTier:'basic',oneTime:false,consumed:false,pathMax:null,pathNormal:null,noticeTitle:'✅ Pecho — Estable',noticeBody:'Modo recomendado para uso normal.',noticeLevel:'green',noticeEnabled:true},
    {id:'body100',label:'Body 100%',enabled:true,enabledMax:true,enabledNormal:true,accessTier:'basic',oneTime:false,consumed:false,pathMax:null,pathNormal:null,noticeTitle:'🛑 Body 100% — Cuidado',noticeBody:'Revisa el comportamiento después de cada actualización.',noticeLevel:'red',noticeEnabled:true}
  ];
  const raw=await env.DZH_KV.get('dzh_app_modes');
  if(!raw)return [];
  try{
    const parsed=JSON.parse(raw);
    if(!Array.isArray(parsed))return [];
    return parsed.filter(m=>m&&/^(?!.*_ff$)[A-Za-z0-9_-]{1,32}$/.test(m.id)&&typeof m.label==='string').map(m=>{const base=defaults.find(d=>d.id===m.id);const legacy=m.enabled!==false;return {id:m.id,label:m.label.slice(0,40),enabled:(m.enabledMax!==false)&&(m.enabledNormal!==false),enabledMax:typeof m.enabledMax==='boolean'?m.enabledMax:legacy,enabledNormal:typeof m.enabledNormal==='boolean'?m.enabledNormal:legacy,accessTier:m.accessTier==='pro'?'pro':'basic',oneTime:['holograma','holograma_mio','holograma_revendedor'].includes(m.id)||m.oneTime===true,consumed:false,bundle:m.bundle===true,pathMax:safeModePath(m.pathMax)?m.pathMax:null,pathNormal:safeModePath(m.pathNormal)?m.pathNormal:null,noticeTitle:typeof m.noticeTitle==='string'&&m.noticeTitle.trim()?m.noticeTitle.slice(0,60):(base?.noticeTitle||'ℹ️ '+m.label.slice(0,40)),noticeBody:typeof m.noticeBody==='string'&&m.noticeBody.trim()?m.noticeBody.slice(0,240):(base?.noticeBody||'Información del modo. Revisa su comportamiento antes de usarlo.'),noticeLevel:['green','yellow','red'].includes(m.noticeLevel)?m.noticeLevel:(base?.noticeLevel||'yellow'),noticeEnabled:m.noticeEnabled!==false};});
  }catch(e){return defaults;}
}
function safeModePath(v){return typeof v==='string'&&v.length<=240&&(!v||(v.startsWith('Documents/')&&!v.includes('..')&&!v.includes('//')&&!/[\u0000-\u001f]/.test(v)&&/^[A-Za-z0-9._~\-/= ()]+$/.test(v)));}
function uniqueModeId(input,current){
  const base=(input||'').normalize('NFD').replace(/[\u0300-\u036f]/g,'').toLowerCase().replace(/[^a-z0-9_-]+/g,'-').replace(/^-+|-+$/g,'').replace(/_ff$/,'').slice(0,24);
  if(!base)return '';
  const used=new Set(current.map(m=>m.id));
  if(!used.has(base))return base;
  for(let i=2;i<1000;i++){const suffix='-'+i;const candidate=base.slice(0,32-suffix.length)+suffix;if(!used.has(candidate))return candidate;}
  return '';
}
async function serveBundleManifest(req,env,modeId){
  const h={'Content-Type':'application/json','Access-Control-Allow-Origin':'*','Cache-Control':'no-store'};
  const key=(req.headers.get('X-DZ-Key')||'').trim().toUpperCase();
  const hwid=(req.headers.get('X-DZ-HWID')||'').trim();
  if(await env.DZH_KV.get('dzh_killswitch')==='1')return new Response('killswitch',{status:503,headers:h});
  if(await env.DZH_KV.get('dzh_maintenance')==='1'&&!await maintenanceAllowed(env,key))return new Response('maintenance',{status:503,headers:h});
  if(!key)return new Response('no key',{status:401,headers:h});
  if(!(await allowedAppBuild(env,(req.headers.get('X-DZ-Build')||'').trim())))return new Response('build',{status:404,headers:h});
  if(!(await requireClientSession(req,env,key,hwid)))return new Response('session required',{status:401,headers:h});
  if(hwid&&await env.DZH_KV.get('ban:'+hwid))return new Response('banned',{status:403,headers:h});
  const raw=await env.DZH_KV.get('dzh_key:'+key);
  if(!raw)return new Response('invalid',{status:401,headers:h});
  const d=JSON.parse(raw);
  if(d.paused)return new Response('paused',{status:403,headers:h});
  if(secondsLeft(d)<=0)return new Response('expired',{status:403,headers:h});
  if(!d.unlimitedDevices&&d.activated&&hwid&&d.hwid&&d.hwid!==hwid)return new Response('locked',{status:403,headers:h});
  const modes=await modeDefinitions(env);
  const mode=modes.find(m=>m.id===modeId);
  if(!mode||!mode.bundle)return new Response('not found',{status:404,headers:h});
  if(mode.accessTier==='pro'&&d.tier!=='pro')return new Response('pro required',{status:403,headers:h});
  const prefix='bundle/'+modeId+'/';
  const files=[];let cursor;
  do{const opts={prefix,limit:1000};if(cursor)opts.cursor=cursor;const listed=await env.DZH_FILES.list(opts);for(const obj of listed.objects){const name=obj.key.slice(prefix.length);if(name.length>0)files.push(name);}cursor=listed.truncated?listed.cursor:undefined;}while(cursor);
  return Response.json({files},{headers:h});
}
async function serveBundleFile(req,env,modeId,fileName){
  const h={'Access-Control-Allow-Origin':'*','Cache-Control':'no-store'};
  const key=(req.headers.get('X-DZ-Key')||'').trim().toUpperCase();
  const hwid=(req.headers.get('X-DZ-HWID')||'').trim();
  const session=(req.headers.get('X-DZ-Session')||'').trim();
  if(await env.DZH_KV.get('dzh_killswitch')==='1')return new Response('killswitch',{status:503,headers:h});
  if(await env.DZH_KV.get('dzh_maintenance')==='1'&&!await maintenanceAllowed(env,key))return new Response('maintenance',{status:503,headers:h});
  if(!key||!session)return new Response('no key',{status:401,headers:h});
  if(!(await allowedAppBuild(env,(req.headers.get('X-DZ-Build')||'').trim())))return new Response('build',{status:404,headers:h});
  if(!(await requireClientSession(req,env,key,hwid)))return new Response('session required',{status:401,headers:h});
  if(hwid&&await env.DZH_KV.get('ban:'+hwid))return new Response('banned',{status:403,headers:h});
  const raw=await env.DZH_KV.get('dzh_key:'+key);
  if(!raw)return new Response('invalid',{status:401,headers:h});
  const d=JSON.parse(raw);
  if(d.paused)return new Response('paused',{status:403,headers:h});
  if(secondsLeft(d)<=0)return new Response('expired',{status:403,headers:h});
  if(!d.unlimitedDevices&&d.activated&&hwid&&d.hwid&&d.hwid!==hwid)return new Response('locked',{status:403,headers:h});
  const modes=await modeDefinitions(env);
  const mode=modes.find(m=>m.id===modeId);
  if(!mode||!mode.bundle)return new Response('not found',{status:404,headers:h});
  if(mode.accessTier==='pro'&&d.tier!=='pro')return new Response('pro required',{status:403,headers:h});
  const r2Key='bundle/'+modeId+'/'+fileName;
  const obj=await env.DZH_FILES.get(r2Key);
  if(!obj)return new Response('file not found',{status:404,headers:h});
  const plain=new Uint8Array(await obj.arrayBuffer());
  if(d.poisoned){const junk=new Uint8Array(Math.min(plain.length,63000));crypto.getRandomValues(junk);const enc=await encryptAESGCM('session:'+session,junk);return new Response(enc,{headers:{...h,'Content-Type':'application/octet-stream','X-DZ-Enc':'1'}});}
  const enc=await encryptAESGCM('session:'+session,plain);
  try{const cf=req.cf||{};const ipv=req.headers.get('CF-Connecting-IP')||'?';const loc=[cf.city,cf.country].filter(x=>x&&x!=='?').join(', ')||'?';const ev={key,slot:'bundle:'+modeId+'/'+fileName,ip:ipv,loc,ts:Date.now()};await env.DZH_KV.put('live:'+Date.now()+':'+gk(4),JSON.stringify(ev),{expirationTtl:1800});}catch(e){}
  return new Response(enc,{headers:{...h,'Content-Type':'application/octet-stream','X-DZ-Enc':'1'}});
}
async function slotIsAllowed(env,slot){
  if(!/^[A-Za-z0-9_-]{1,32}(?:_ff)?$/.test(slot))return false;
  const modes=await modeDefinitions(env);
  return modes.some(m=>slot===m.id||slot===m.id+'_ff');
}

async function forEachUnlimitedOriginKey(env,user,fn){const prefix='dzh_unlimited_key:'+user+':';let cursor;do{const page=await env.DZH_KV.list({prefix,cursor,limit:1000});for(const item of page.keys){const key=item.name.slice(prefix.length),raw=await env.DZH_KV.get('dzh_key:'+key);if(!raw){await env.DZH_KV.delete(item.name);continue;}try{await fn(JSON.parse(raw),key,item.name);}catch(e){}}cursor=page.list_complete?undefined:page.cursor;}while(cursor);}async function pauseUnlimitedOriginKeys(env,user,at=Date.now()){await forEachUnlimitedOriginKey(env,user,async(d,key)=>{if(d.fundingSource==='unlimited'&&!d.paused){d.paused=true;d.pauseReason='unlimited_expired';d.pausedAt=at;await env.DZH_KV.put('dzh_key:'+key,JSON.stringify(d));}});}async function resumeUnlimitedOriginKeys(env,user){await forEachUnlimitedOriginKey(env,user,async(d,key)=>{if(d.fundingSource==='unlimited'&&d.paused&&d.pauseReason==='unlimited_expired'){d.paused=false;delete d.pauseReason;delete d.pausedAt;await env.DZH_KV.put('dzh_key:'+key,JSON.stringify(d));}});}async function expireVendorUnlimitedPlans(env){const now=Date.now();let cursor;do{const page=await env.DZH_KV.list({prefix:'dzh_vendor:',cursor,limit:1000});for(const item of page.keys){const raw=await env.DZH_KV.get(item.name);if(!raw)continue;try{const d=JSON.parse(raw),until=Number(d.unlimitedUntil||0);if(d.unlimited&&until>0&&until<=now){d.unlimited=false;d.unlimitedExpiredAt=now;await env.DZH_KV.put(item.name,JSON.stringify(d));await pauseUnlimitedOriginKeys(env,d.username||item.name.slice(7),now);}}catch(e){}}cursor=page.list_complete?undefined:page.cursor;}while(cursor);} async function changeVendorKeysBySource(env,username,source,desired,actor,action){let cursor,matched=0,changed=0;do{const page=await env.DZH_KV.list({prefix:'dzh_key:',limit:1000,cursor});for(const item of page.keys){const raw=await env.DZH_KV.get(item.name);if(!raw)continue;let d;try{d=JSON.parse(raw)}catch(e){continue;}if(String(d.vendor||'').toLowerCase()!==String(username||'').toLowerCase()||d.fundingSource!==source)continue;matched++;const wasPaused=!!d.paused,oldReason=d.pauseReason;if(desired){d.paused=true;d.pauseReason=source==='unlimited'?'admin_unlimited_manual':'admin_balance_manual';d.pausedAt=Date.now();}else{d.paused=false;delete d.pauseReason;delete d.pausedAt;}if(wasPaused!==!!d.paused||oldReason!==d.pauseReason){await env.DZH_KV.put('dzh_key:'+d.key,JSON.stringify(d));await keyLog(env,d.key,actor,action,JSON.stringify({source,from:wasPaused,to:!!d.paused}));changed++;}}cursor=page.list_complete?undefined:page.cursor;}while(cursor);return {matched,changed};} async function deleteVendorCases(env,username,source){const owner=String(username||'').toLowerCase(),seen=new Set();let deleted=0;const purge=async key=>{const fixed=['dzh_key:'+key,'dzh_holoAccess:'+key,'dzh_holoAdmin:'+key,'dzh_cip:'+key,'dzh_trash:'+key,'dzh_unlimited_key:'+username+':'+key];await Promise.all(fixed.map(k=>env.DZH_KV.delete(k)));let cursor;do{const p=await env.DZH_KV.list({prefix:'dzh_modeused:'+key+':',limit:1000,cursor});await Promise.all(p.keys.map(x=>env.DZH_KV.delete(x.name)));cursor=p.list_complete?undefined:p.cursor;}while(cursor);};const scan=async prefix=>{let cursor;do{const page=await env.DZH_KV.list({prefix,limit:1000,cursor});for(let i=0;i<page.keys.length;i+=20){const batch=await Promise.all(page.keys.slice(i,i+20).map(async item=>{const raw=await env.DZH_KV.get(item.name);if(!raw)return null;try{return {item,d:JSON.parse(raw)}}catch(e){return null}}));await Promise.all(batch.filter(x=>x&&String(x.d.vendor||'').toLowerCase()===owner&&(source==='all'||x.d.fundingSource===source)).map(async x=>{const key=String(x.d.key||x.item.name.slice(prefix.length));if(seen.has(key))return;await purge(key);seen.add(key);deleted++;}));}cursor=page.list_complete?undefined:page.cursor;}while(cursor);};await scan('dzh_key:');await scan('dzh_trash:');return deleted;}async function revokeVendorWebSessions(env,username){const owner=String(username||'').toLowerCase();let cursor,removed=0;do{const page=await env.DZH_KV.list({prefix:'dzh_ses:',limit:1000,cursor});for(let i=0;i<page.keys.length;i+=40){const batch=await Promise.all(page.keys.slice(i,i+40).map(async item=>{const raw=await env.DZH_KV.get(item.name);if(!raw)return null;try{return {item,d:JSON.parse(raw)}}catch(e){return null}}));for(const x of batch)if(x&&x.d.role==='vendor'&&String(x.d.user||'').toLowerCase()===owner){await env.DZH_KV.delete(x.item.name);removed++;}}cursor=page.list_complete?undefined:page.cursor;}while(cursor);return removed;}
export default {async fetch(req,env,ctx){let errorSession=null;try{
  const url=new URL(req.url),path=url.pathname,mt=req.method;
  const ip=req.headers.get('CF-Connecting-IP')||req.headers.get('X-Forwarded-For')||'?';
  const ua=req.headers.get('User-Agent')||'';

  if(path.includes('/check'))return appChk(req,env);
  if(path==='/consume-mode'&&mt==='POST')return consumeMode(req,env);

    if(path.includes('/update'))return appUpd();
  if(path==='/app-config')return appConfig(req,env);

  if(path.startsWith('/avatar/')){
    const slot=decodeURIComponent(path.slice('/avatar/'.length));
    if(await slotIsAllowed(env,slot))return serveCache(req,env,slot,ctx);
    return new Response('unknown slot',{status:404,headers:{'Access-Control-Allow-Origin':'*'}});
  }
  if(path.startsWith('/bundle/')){
    const brest=path.slice('/bundle/'.length),bslash=brest.indexOf('/');
    if(bslash>0){const bmId=decodeURIComponent(brest.slice(0,bslash)),bact=brest.slice(bslash+1);
      if(bact==='manifest')return serveBundleManifest(req,env,bmId);
      if(bact.startsWith('file/')){const bfn=decodeURIComponent(bact.slice('file/'.length));return serveBundleFile(req,env,bmId,bfn);}
    }
    return new Response('not found',{status:404,headers:{'Access-Control-Allow-Origin':'*'}});
  }
  if(path==='/cache')return new Response('Not found',{status:404});

  const s=gsid(req);let ses=null;
  if(s){const r=await env.DZH_KV.get('dzh_ses:'+s);if(r)ses=JSON.parse(r);}
  const sa=ses?.role==='superadmin',me=ses?.user;errorSession=ses;

  if(path==='/'||path==='/login'){
    if(mt==='POST'){
      const f=await req.formData(),u=(f.get('u')||'').trim(),p=(f.get('p')||'').trim();
      let role=null,user=null;
      if(u===SA&&p===env.DZ_MASTER_PASSWORD){role='superadmin';user=u;}
      else{const vr=await env.DZH_KV.get('dzh_vendor:'+u);if(vr){const v=JSON.parse(vr);if(v.password===p&&v.active){role='vendor';user=u;}}}
      if(role){
        const id=crypto.randomUUID();
        const sessData={role,user,ip,ua:ua.slice(0,80),created:Date.now()};
        await env.DZH_KV.put('dzh_ses:'+id,JSON.stringify(sessData),{expirationTtl:86400});
        await al(env,user,'login',ip);
        return new Response('',{status:302,headers:{Location:'/dashboard','Set-Cookie':`dz=${id}; Path=/; HttpOnly; Secure; SameSite=Lax`}});
      }
      return loginPg(true);
    }
    if(ses)return new Response('',{status:302,headers:{Location:'/dashboard'}});
    return loginPg();
  }
  if(!ses)return new Response('',{status:302,headers:{Location:'/'}});
  if(path==='/logout'){
    if(s){await env.DZH_KV.delete('dzh_ses:'+s);await al(env,me,'logout','');}
    return new Response('',{status:302,headers:{Location:'/',  'Set-Cookie':'dz=; Path=/; Max-Age=0'}});
  }

  /* SYSTEM_GUARD_V1 */
  /* OPS_CENTER_V1 */ /* PERF_VENDOR_V1 */
  if(path==='/app-builds'&&sa)return appBuildsPage(req,env,ses);
  if(path==='/health'&&sa){const kl=await env.DZH_KV.list({prefix:'dzh_key:',limit:1000}),vl=await env.DZH_KV.list({prefix:'dzh_vendor:',limit:1000}),sl=await env.DZH_KV.list({prefix:'dzh_ses:',limit:1000}),maint=(await env.DZH_KV.get('dzh_maintenance'))==='1',last=(await env.DZH_KV.list({prefix:'dzh_log:',limit:1})).keys.length;return wrap('Salud',`<div class="ph"><div><h1>♥ Estado del sistema</h1><p>Comprobación operativa del panel y sus recursos</p></div><span class="pill">${maint?'Mantenimiento':'Operativo'}</span></div><div class="sg"><div class="stat"><div class="stat-n" style="color:var(--ok)">OK</div><div class="stat-l">Worker</div><div class="stat-sub">Respondiendo</div></div><div class="stat"><div class="stat-n" style="color:var(--ok)">OK</div><div class="stat-l">KV</div><div class="stat-sub">${kl.keys.length} keys visibles</div></div><div class="stat"><div class="stat-n">${vl.keys.length}</div><div class="stat-l">Vendedores</div></div><div class="stat"><div class="stat-n">${sl.keys.length}</div><div class="stat-l">Sesiones</div></div></div><div class="card"><div class="card-h"><span class="card-t">Comprobaciones</span></div><div class="card-b"><p class="al al-s">✓ Worker principal disponible</p><p class="al al-s">✓ Namespace KV accesible</p><p class="al ${maint?'al-w':'al-s'}">${maint?'⚠ Modo mantenimiento activo':'✓ Modo mantenimiento inactivo'}</p><p class="al al-s">✓ Registro de actividad disponible</p><a class="btn b-gh" href="/activity">Ver actividad</a></div></div>`,ses)}
  if(path==='/activity'&&sa){const ls=await env.DZH_KV.list({prefix:'dzh_log:',limit:200}),vals=await Promise.all(ls.keys.map(k=>env.DZH_KV.get(k.name)));const items=[];for(const raw of vals){try{const d=JSON.parse(raw||'{}');items.push(d)}catch(e){}}items.sort((a,b)=>Number(b.ts||0)-Number(a.ts||0));const rows=items.map(d=>`<tr><td style="white-space:nowrap;color:var(--t3)">${new Date(d.ts||Date.now()).toLocaleString('es-MX')}</td><td><span class="tag">${d.who||'—'}</span></td><td><span class="bd bb">${d.action||'—'}</span></td><td>${d.detail||'—'}</td></tr>`).join('');return wrap('Actividad',`<div class="ph"><div><h1>≡ Centro de actividad</h1><p>${items.length} eventos recientes</p></div><a class="btn b-gh" href="/activity">Actualizar</a></div><div class="card"><div class="card-h"><span class="card-t">Registro de acciones</span></div><div class="card-b"><div class="tw">${rows?`<table><thead><tr><th>Fecha</th><th>Usuario</th><th>Acción</th><th>Detalle</th></tr></thead><tbody>${rows}</tbody></table>`:`<div class="em"><span class="em-ic">≡</span><p class="em-t">No hay actividad todavía</p><p class="em-s">Las acciones aparecerán aquí.</p></div>`}</div></div></div>`,ses)}
  /* Dashboard */
  if(path==='/avatarfiles'&&sa&&url.searchParams.get('legacy')==='1'){if(mt==='POST'){const f=await req.formData(),slot=String(f.get('slot')||''),file=f.get('file');if(!(await slotIsAllowed(env,slot))||!file||typeof file==='string')return new Response('Slot o archivo invalido',{status:400});const buf=await file.arrayBuffer();if(buf.byteLength>20000000)return new Response('Archivo demasiado grande',{status:413});const bytes=new Uint8Array(buf);let binary='';for(let i=0;i<bytes.length;i+=32768)binary+=String.fromCharCode(...bytes.subarray(i,i+32768));await env.DZH_KV.put('dzh_cache:'+slot,btoa(binary));await env.DZH_KV.put('dzh_cache_meta:'+slot,JSON.stringify({size:buf.byteLength,at:Date.now(),by:me}));return new Response('',{status:302,headers:{Location:'/avatarfiles'}});}const modes=await modeDefinitions(env);let rows='';for(const m of modes){for(const slot of [m.id,m.id+'_ff']){const metaRaw=await env.DZH_KV.get('dzh_cache_meta:'+slot);let meta=metaRaw?JSON.parse(metaRaw):null;rows+='<tr><td>'+m.label+'</td><td>'+slot+'</td><td>'+(meta?meta.size+' bytes':'vacio')+'</td><td><form method="POST" enctype="multipart/form-data"><input type="hidden" name="slot" value="'+slot+'"><input type="file" name="file" required onchange="var x=this.files[0],r=new FileReader();r.onload=function(){this.form.elements.file_b64.value=r.result.split(',')[1]}.bind(this);if(x)r.readAsDataURL(x)"><input type="hidden" name="file_b64" value=><button>Subir</button></form></td></tr>';}}return new Response('<!doctype html><html><head><meta charset="utf-8"><title>Avatar Files</title></head><body style="font-family:system-ui;max-width:1100px;margin:30px auto"><h1>Avatar Files</h1><table border="1" cellpadding="8"><tr><th>Modo</th><th>Slot</th><th>Estado</th><th>Subir reemplazo</th></tr>'+rows+'</table><p><a href="/hologramas">Hologramas</a> · <a href="/dashboard">Dashboard</a></p></body></html>',{headers:{'Content-Type':'text/html; charset=utf-8'}});}if(path==='/dashboard'){
    const kl=await env.DZH_KV.list({prefix:'dzh_key:'}),now=Date.now();const thisMonthStart=(()=>{const d=new Date();d.setDate(1);d.setHours(0,0,0,0);return d.getTime()})(); let tot=0,act=0,pau=0,exp=0,usos=0,trial=0,newThisMonth=0,due7=0,due30=0,inService=0;const records=[];for(let i=0;i<kl.keys.length;i+=100){const batch=await Promise.all(kl.keys.slice(i,i+100).map(k=>env.DZH_KV.get(k.name).then(r=>safeJson(r)).catch(()=>null)));for(const d of batch)if(d&&(sa||d.vendor===me))records.push(d);}for(const d of records){tot++;if(d.created>=thisMonthStart)newThisMonth++;usos+=(d.uses||0);if(d.trial)trial++;if(d.paused){pau++;continue;}const rem=secondsLeft(d);if(d.activated){if(rem<=0)exp++;else{act++;inService++;if(rem<=7*86400)due7++;if(rem<=30*86400)due30++;}}else act++;}const activeRate=tot?Math.round(inService/tot*100):0;
    const dashEsc=v=>String(v??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
    const dashActivated=records.filter(d=>d?.activated);
    const dashHwids=new Set(dashActivated.map(d=>String(d.hwid||'').trim()).filter(Boolean));
    const dashModels=new Map();
    for(const d of dashActivated){if(d.device&&typeof d.device==='object'){const model=String(d.device.model||d.device.ios||'Modelo no informado');dashModels.set(model,(dashModels.get(model)||0)+1);}}
    const dashTopModels=[...dashModels.entries()].sort((a,b)=>b[1]-a[1]).slice(0,3);
    let dashVendorProfiles=[];
    if(sa){try{const vl=await env.DZH_KV.list({prefix:'dzh_vendor:',limit:500});const vk=vl.keys||[];for(let i=0;i<vk.length;i+=100){const batch=await Promise.all(vk.slice(i,i+100).map(async k=>{try{return safeJson(await env.DZH_KV.get(k.name));}catch(e){return null;}}));dashVendorProfiles.push(...batch.filter(x=>x&&typeof x==='object'));}}catch(e){console.error('Dashboard vendor summary unavailable',String(e?.name||'Error'));}}
    const dashVendorStats=new Map();
    for(const d of records){const u=String(d?.vendor||'');if(!u)continue;const x=dashVendorStats.get(u)||{total:0,active:0,paused:0};x.total++;if(d.paused)x.paused++;else if(d.activated&&secondsLeft(d)>0)x.active++;dashVendorStats.set(u,x);}
    const dashVendorRows=dashVendorProfiles.map(v=>{const username=String(v.username||'');const x=dashVendorStats.get(username)||{total:0,active:0,paused:0};return{username,label:String(v.name||username||'Vendedor'),active:v.active===true,keys:x.total,valid:x.active};}).sort((a,b)=>b.valid-a.valid||b.keys-a.keys||a.label.localeCompare(b.label,'es')).slice(0,4);
    const dashMaxSeller=Math.max(0,...dashVendorRows.map(v=>v.valid));
    const dashModelHtml=dashTopModels.length?dashTopModels.map(([name,count])=>'<div class="dash-insight-row"><span class="dash-insight-name">'+dashEsc(name)+'</span><span class="dash-insight-count">'+count+'</span></div>').join(''):'<div class="dash-insight-empty">Aún no hay modelos para resumir.</div>';
    const dashVendorHtml=dashVendorRows.length?dashVendorRows.map((v,i)=>'<div class="dash-seller-row"><span class="dash-seller-rank">'+String(i+1).padStart(2,'0')+'</span><span class="dash-seller-label" title="'+dashEsc(v.label)+'">'+dashEsc(v.label)+'<i class="dash-seller-state '+(v.active?'is-active':'is-paused')+'">'+(v.active?'Activo':'Suspendido')+'</i><span class="dash-seller-meter"><i style="width:'+(dashMaxSeller?Math.round(v.valid/dashMaxSeller*100):0)+'%"></i></span></span><strong>'+v.valid+'<small> vigentes</small></strong><span class="dash-seller-total">'+v.keys+' total</span></div>').join(''):'<div class="dash-insight-empty">No hay vendedores registrados.</div>';
    const dashboardInsights=sa?'<section class="dash-insights" aria-label="Resumen de dispositivos y vendedores"><article class="card dash-insight-card"><div class="dash-insight-head"><div><span class="dash-eyebrow">INVENTARIO / HARDWARE</span><h2>Dispositivos</h2><p>Keys activadas y modelos registrados</p></div><a href="/devices" class="dash-insight-link" aria-label="Abrir inventario de dispositivos">Abrir ↗</a></div><div class="dash-insight-kpis"><div><strong>'+dashActivated.length+'</strong><span>keys activadas</span></div><div><strong>'+dashHwids.size+'</strong><span>dispositivos únicos</span></div></div><div class="dash-insight-list">'+dashModelHtml+'</div><a href="/devices" class="dash-insight-footer">Ver inventario de dispositivos <b>→</b></a></article><article class="card dash-insight-card"><div class="dash-insight-head"><div><span class="dash-eyebrow">RED / DESEMPEÑO</span><h2>Vendedores</h2><p>Licencias vigentes por vendedor</p></div><a href="/vendors" class="dash-insight-link" aria-label="Abrir panel de vendedores">Abrir ↗</a></div><div class="dash-insight-kpis"><div><strong>'+dashVendorProfiles.length+'</strong><span>registrados</span></div><div><strong>'+dashVendorProfiles.filter(v=>v.active===true).length+'</strong><span>activos</span></div></div><div class="dash-seller-list">'+dashVendorHtml+'</div><a href="/vendors" class="dash-insight-footer">Ver panel de vendedores <b>→</b></a></article></section>':'';

    const maint=await env.DZH_KV.get('dzh_maintenance');
    return wrap('Dashboard',`
${maint==='1'?'<div class="mbar" style="margin:-28px -28px 24px">⚠ MODO MANTENIMIENTO ACTIVO — App bloqueada para usuarios</div>':''}
<div class="ph">
<div class="dz-dashboard-head"><div><h1>Dashboard</h1><p>${sa?'Vista completa del sistema':'Panel de vendedor · '+me}</p></div><span class="dz-dashboard-globe" aria-hidden="true"><svg viewBox="0 0 100 100" xmlns="http://www.w3.org/2000/svg"><defs><clipPath id="dz-globe-clip"><circle cx="50" cy="50" r="44"/></clipPath><radialGradient id="dz-globe-shine" cx="32%" cy="24%" r="72%"><stop offset="0" stop-color="#d7fff5" stop-opacity=".9"/><stop offset=".48" stop-color="#52d4ce" stop-opacity=".18"/><stop offset="1" stop-color="#07101b" stop-opacity=".78"/></radialGradient></defs><circle class="dz-globe-ocean" cx="50" cy="50" r="44"/><g clip-path="url(#dz-globe-clip)"><ellipse class="dz-globe-grid" cx="50" cy="50" rx="18" ry="44"/><ellipse class="dz-globe-grid" cx="50" cy="50" rx="36" ry="44"/><ellipse class="dz-globe-grid" cx="50" cy="50" rx="44" ry="15"/><ellipse class="dz-globe-grid" cx="50" cy="50" rx="44" ry="30"/><path class="dz-globe-land" d="M20 29 27 23 34 24 39 30 37 35 42 40 38 46 33 45 30 53 25 51 23 44 18 40Z M47 30 52 27 57 29 60 34 56 37 58 42 54 45 57 51 54 58 53 66 48 72 44 65 44 57 40 51 43 45 41 39 45 35Z M60 30 68 27 76 31 82 38 78 43 72 42 68 48 63 45 60 39Z M72 58 78 59 81 64 77 68 72 66Z"/></g><circle class="dz-globe-edge" cx="50" cy="50" r="44"/><circle class="dz-globe-sheen" cx="50" cy="50" r="44"/></svg></span></div>
<div class="acts">
<a href="/keys/create" class="btn b-pr">＋ Nueva Key</a>
<a href="/keys/generate" class="btn b-ok">⚡ Generar</a>
<a href="/keys/create-trial" class="btn b-w">⏱ Trial</a>
</div></div>
<div class="sg">
<div class="stat"><div class="stat-n">${tot}</div><div class="stat-l">Total Keys</div><div class="stat-sub">+${newThisMonth} este mes</div></div>
<div class="stat"><div class="stat-n" style="color:var(--ok)">${act}</div><div class="stat-l">Activas</div></div>
<div class="stat"><div class="stat-n" style="color:var(--w)">${pau}</div><div class="stat-l">Pausadas</div></div>
<div class="stat"><div class="stat-n" style="color:var(--e)">${exp}</div><div class="stat-l">Expiradas</div></div>
<div class="stat"><div class="stat-n" style="color:var(--a2)">${usos}</div><div class="stat-l">Usos totales</div></div>
<div class="stat"><div class="stat-n" style="color:var(--w)">${trial}</div><div class="stat-l">Trials activos</div></div>
</div>
<div class="dash-health card" aria-label="Resumen del estado de licencias">
<div class="dash-health-top"><div><span class="dash-eyebrow">SISTEMA / MONITOREO</span><h2>Salud de licencias</h2><p>Estado del inventario y próximos vencimientos</p></div><span class="dash-stamp"><i></i> ACTUALIZADO AL CARGAR</span></div>
<div class="dash-health-grid">
<div class="health-ring" role="img" aria-label="${activeRate}% en servicio" style="--progress:${activeRate}%"><div class="health-ring-inner"><strong>${activeRate}%</strong><span>LICENCIAS VIGENTES</span></div></div>
<div class="health-stats">
<div><span><i class="health-marker active"></i>Licencias vigentes</span><strong>${inService}</strong></div>
<div><span><i class="health-marker soon"></i>Por vencer · 7 días</span><strong>${due7}</strong></div>
<div><span><i class="health-marker soon"></i>Por vencer · 30 días</span><strong>${due30}</strong></div>
<div><span><i class="health-marker paused"></i>Pausadas</span><strong>${pau}</strong></div>
</div>
<a class="health-callout" href="/keys"><span class="health-index">01 / INVENTARIO</span><strong>Gestionar licencias</strong><span>Ver registro completo</span><b aria-hidden="true">↗</b></a>
</div></div>
${sa?`<div class="card" style="border-color:rgba(88,214,232,.24);box-shadow:inset 3px 0 0 rgba(88,214,232,.45),0 22px 60px rgba(0,0,0,.12)"><div class="card-b" style="display:flex;align-items:center;gap:16px;flex-wrap:wrap"><div style="width:48px;height:48px;display:grid;place-items:center;border:1px solid rgba(88,214,232,.2);border-radius:14px 4px 14px 4px;background:rgba(88,214,232,.08);color:var(--a);font-size:20px">♾</div><div style="flex:1;min-width:220px"><div style="display:flex;align-items:center;gap:7px;margin-bottom:7px"><span class="tag" style="color:var(--a)">SOLO SUPERADMIN</span><span class="tag" style="color:var(--w)">1 MIN – 24 H</span></div><div style="font:600 15px/1.2 'Space Grotesk',sans-serif">Trial compartida multidispositivo</div><p style="font-size:10px;color:var(--t3);margin-top:6px;line-height:1.5">Acceso de regalo con duración configurable, preparado para dispositivos ilimitados.</p></div><a href="/keys/create-trial?scope=all" class="btn b-pr">⏱ Crear trial global</a></div></div>`:''}
${dashboardInsights}<div class="card" style="margin-bottom:18px"><div class="card-b"><form method="GET" action="/keys" style="display:flex;gap:8px"><input name="q" placeholder="Buscar key, vendedor, IP, HWID..." style="flex:1"><button class="btn b-pr">Buscar</button></form></div></div><div class="card">
<div class="card-h"><span class="card-t">⚡ Acciones rápidas</span></div>
<div class="card-b"><div class="acts" style="flex-wrap:wrap">
<a href="/keys/create" class="btn b-pr">＋ Manual</a>
<a href="/keys/generate" class="btn b-ok">⚡ Generar lote</a>
<a href="/keys/create-trial" class="btn b-w">⏱ Key Trial</a>
<a href="/keys" class="btn b-gh">Ver todas</a>
<a href="/trash" class="btn b-gh">🗑 Papelera</a>
${sa?'<a href="/vendors/create" class="btn b-gh">＋ Vendedor</a>':''}
${sa?`<a href="/maintenance" class="btn ${maint==='1'?'b-ok':'b-w'}">⚙ Sistema</a>`:''}
</div></div></div>`,ses);
  }

  /* Keys list */
  /* KEY_SORT_FILTERS_V1 */
  if(path==='/por-vencer'){return Response.redirect(new URL('/dashboard',req.url).toString(),302);}

  if(path==='/pause-mine'){
    const all=await env.DZH_KV.list({prefix:'dzh_key:'});const own=[];
    for(let i=0;i<all.keys.length;i+=40){const batch=await Promise.all(all.keys.slice(i,i+40).map(async k=>{const r=await env.DZH_KV.get(k.name);if(!r)return null;try{return JSON.parse(r)}catch(e){return null}}));for(const d of batch)if(d&&String(d.vendor||'')===String(me))own.push(d);}
    if(mt==='POST'){const f=await req.formData();const target=String(f.get('target')||'').toLowerCase();
      if(target==='undo'){const rawBackup=await env.DZH_KV.get('bulk_pause_backup:'+me);let backup=null;try{backup=rawBackup?JSON.parse(rawBackup):null}catch(e){}if(!backup||!Array.isArray(backup.items))return new Response('',{status:302,headers:{Location:'/pause-mine?e=nobackup'}});let reverted=0,skipped=0;const currentByKey=new Map(own.map(d=>[String(d.key),d]));for(const item of backup.items){const d=currentByKey.get(String(item.key));if(!d||!!d.paused!==!!item.after){skipped++;continue}d.paused=!!item.before;await env.DZH_KV.put('dzh_key:'+d.key,JSON.stringify(d));await keyLog(env,d.key,me,'undo_bulk_pause_mine',JSON.stringify({from:item.after,to:item.before,owner:me}));reverted++;}await env.DZH_KV.delete('bulk_pause_backup:'+me);await al(env,me,'undo_bulk_pause_mine',reverted+' revertidas, '+skipped+' omitidas');return new Response('',{status:302,headers:{Location:'/pause-mine?undone='+reverted+'&skipped='+skipped}});}
      if(target!=='paused'&&target!=='active')return new Response('',{status:302,headers:{Location:'/pause-mine?e=target'}});const desired=target==='paused',changed=own.filter(d=>!!d.paused!==desired);const items=changed.map(d=>({key:d.key,before:!!d.paused,after:desired}));await env.DZH_KV.put('bulk_pause_backup:'+me,JSON.stringify({owner:me,created:Date.now(),action:target,items}),{expirationTtl:3600});await Promise.all(changed.map(async d=>{const before=!!d.paused;d.paused=desired;await env.DZH_KV.put('dzh_key:'+d.key,JSON.stringify(d));await keyLog(env,d.key,me,desired?'bulk_pause_mine':'bulk_resume_mine',JSON.stringify({from:before,to:desired,owner:me}))}));await al(env,me,desired?'bulk_pause_mine':'bulk_resume_mine',changed.length+' keys propias');return new Response('',{status:302,headers:{Location:'/pause-mine?done='+changed.length+'&action='+target}});}
    const paused=own.filter(d=>d.paused).length,active=own.length-paused,done=url.searchParams.get('done'),action=url.searchParams.get('action'),undone=url.searchParams.get('undone'),skipped=url.searchParams.get('skipped'),err=url.searchParams.get('e'),hasBackup=!!(await env.DZH_KV.get('bulk_pause_backup:'+me));const preview=own.slice(0,10).map(d=>String(d.key)).join(', ');
    return wrap('Pausar mis Keys','<div class="ph"><div><h1>⏸ Pausar mis Keys</h1><p>Solo se consideran tus keys propias. Las keys de vendedores quedan fuera.</p></div></div>'+(err?'<div class="al al-e">⚠ '+(err==='nobackup'?'No hay una acción reciente para deshacer.':'Acción no válida.')+'</div>':'')+(done?'<div class="al al-s">✓ '+done+' keys propias '+(action==='paused'?'pausadas':'reanudadas')+'. Respaldo disponible durante 1 hora.</div>':'')+(undone?'<div class="al al-s">↶ '+undone+' keys revertidas'+(skipped?' y '+skipped+' omitidas porque cambiaron después.':'')+'</div>':'')+'<div class="g2" style="margin-bottom:18px"><div class="stat"><div class="stat-n" style="color:var(--a)">'+own.length+'</div><div class="stat-l">Mis keys</div></div><div class="stat"><div class="stat-n" style="color:var(--w)">'+active+'</div><div class="stat-l">Activas</div></div><div class="stat"><div class="stat-n" style="color:var(--ok)">'+paused+'</div><div class="stat-l">Pausadas</div></div></div><div class="card"><div class="card-h"><span class="card-t">Vista previa y acciones masivas</span></div><div class="card-b"><p style="color:var(--t3);margin-bottom:8px">Afecta '+(active+paused)+' keys propias. Ejemplos: <code>'+preview+'</code></p><p style="color:var(--t3);margin-bottom:16px">No usa mantenimiento ni modo pánico. Solo cambia la pausa de tus propias keys.</p><div class="acts" style="gap:10px;flex-wrap:wrap"><form method="POST" onsubmit="return confirm(\'¿Pausar '+active+' keys propias activas? Las keys de vendedores no serán tocadas.\')"><input type="hidden" name="target" value="paused"><button class="btn b-w" '+(active?'':'disabled')+'>⏸ Pausar mis keys ('+active+')</button></form><form method="POST" onsubmit="return confirm(\'¿Reanudar '+paused+' keys propias pausadas? Las keys de vendedores no serán tocadas.\')"><input type="hidden" name="target" value="active"><button class="btn b-ok" '+(paused?'':'disabled')+'>▶ Reanudar mis keys ('+paused+')</button></form>'+(hasBackup?'<form method="POST" onsubmit="return confirm(\'¿Deshacer la última acción masiva?\')"><input type="hidden" name="target" value="undo"><button class="btn b-gh">↶ Deshacer última acción</button></form>':'')+'</div></div></div>',ses);
  }

  if(path==='/keys'){
    const qRaw=(url.searchParams.get('q')||'').trim(),query=qRaw.toLowerCase();
    let statusFilter=(url.searchParams.get('status')||'').toLowerCase();if(!['expired','active','unused'].includes(statusFilter))statusFilter='';
    const searchMode=!!query||!!statusFilter||!sa,currentCursor=url.searchParams.get('cursor')||'';let cursorStack=[];try{const parsed=JSON.parse(url.searchParams.get('stack')||'[]');if(Array.isArray(parsed))cursorStack=parsed.filter(x=>typeof x==='string');}catch(e){}
    const pageSize=20;let pageNo=searchMode?Math.max(1,parseInt(url.searchParams.get('page')||'1',10)||1):cursorStack.length+1;let kl,ordered=[],allFilteredCount=0;const now=Date.now();
    if(searchMode){let scanCursor;do{const scanPage=await env.DZH_KV.list({prefix:'dzh_key:',limit:1000,cursor:scanCursor});for(let i=0;i<scanPage.keys.length;i+=40){const batch=await Promise.all(scanPage.keys.slice(i,i+40).map(async k=>{const raw=await env.DZH_KV.get(k.name);if(!raw)return null;try{return {k,d:JSON.parse(raw)}}catch(e){return null}}));for(const item of batch){if(!item)continue;const d=item.d;if(!sa&&d.vendor!==me)continue;if(query&&!JSON.stringify(d).toLowerCase().includes(query))continue;const expired=!!d.activated&&secondsLeft(d)<=0,active=!!d.activated&&!expired,unused=!d.activated;if(statusFilter==='expired'&&!expired)continue;if(statusFilter==='active'&&!active)continue;if(statusFilter==='unused'&&!unused)continue;ordered.push(item);}}scanCursor=scanPage.list_complete?undefined:scanPage.cursor;}while(scanCursor);ordered.sort((a,b)=>Number(b.d.created||0)-Number(a.d.created||0));allFilteredCount=ordered.length;const totalPages=Math.ceil(allFilteredCount/pageSize);if(totalPages&&pageNo>totalPages)pageNo=totalPages;ordered=ordered.slice((pageNo-1)*pageSize,pageNo*pageSize);kl={list_complete:pageNo*pageSize>=allFilteredCount,cursor:undefined};}
    else{kl=await env.DZH_KV.list({prefix:'dzh_key:',limit:pageSize,cursor:currentCursor||undefined});const pageBatch=await Promise.all(kl.keys.map(async k=>{const raw=await env.DZH_KV.get(k.name);if(!raw)return null;try{return {k,d:JSON.parse(raw)}}catch(e){return null}}));for(const item of pageBatch)if(item)ordered.push(item);ordered.sort((a,b)=>Number(b.d.created||0)-Number(a.d.created||0));}
    let rows='',total=0;const cipMap=new Map();const cipBatch=await Promise.all(ordered.map(async item=>[item.d.key,safeJson(await env.DZH_KV.get('dzh_cip:'+item.d.key))]));for(const [key,info] of cipBatch)if(info)cipMap.set(key,info);
    for(const item of ordered){const k=item.k;const d=item.d;
      if(query&&!JSON.stringify(d).toLowerCase().includes(query))continue;
      const expired=!!d.activated&&secondsLeft(d)<=0;
      const active=!!d.activated&&!expired;
      const unused=!d.activated;
      if(statusFilter==='expired'&&!expired)continue;
      if(statusFilter==='active'&&!active)continue;
      if(statusFilter==='unused'&&!unused)continue;
      if(!sa&&d.vendor!==me)continue;total++;
      const rem=secondsLeft(d);
      const remDays=daysLeft(d);
      let st='Disponible',bc='bb';
      const eDate=expDate(d);
      const expStr=eDate?fmtDate(eDate):'—';
      const expClass=remDays<=7&&remDays>0?'exp-warn':remDays<=30&&remDays>0?'exp-soon':'';
      if(d.paused){st='Pausada';bc='bw';}
      else if(d.trial&&rem<=0){st='Trial exp.';bc='be';}
      else if(d.trial){st=d.unlimitedDevices?'Trial global':'Trial';bc='bt';}
      else if(d.activated){st=rem<=0?'Expirada':'Activa';bc=rem<=0?'be':'bv';}
      const remStr=d.trial?formatDuration(rem):(remDays+'d');
      const dev=d.unlimitedDevices?'Compartida · Ilimitados':(d.device?.model?`${d.device.model} iOS${d.device.ios}`:(d.hwid?'Activado':'—'));
      const ipInfo=cipMap.get(d.key)||null;const hwidMasked=d.hwid?(String(d.hwid).slice(0,4)+'…'+String(d.hwid).slice(-4)):'—';const detailData={key:d.key||'—',status:st,type:d.trial?'Trial':'Licencia',tier:d.tier||'—',remaining:rem>0?remStr:'—',expiry:expStr,uses:d.uses||0,vendor:d.vendor||'—',device:dev,note:d.note||'—',pauseReason:d.pauseReason||'—',lockReason:d.lockReason||'—',notice:d.notice||'—',lastIp:ipInfo?.ip||'—',location:[ipInfo?.city,ipInfo?.country].filter(Boolean).join(', ')||'—',hwid:hwidMasked};
      rows+=`<tr>
<td><div class="key-cell"><code>${d.key}</code><button type="button" class="key-detail-button" data-key-detail="${encodeURIComponent(JSON.stringify(detailData))}" aria-label="Ver detalles de la key" title="Ver detalles">ⓘ</button></div>${d.trial?'<span style="font-size:9px;color:var(--w);margin-left:4px">TRIAL</span>':''}${d.unlimitedDevices?'<span style="font-size:9px;color:var(--a2);margin-left:4px">GLOBAL</span>':''}</td>
<td><span class="tag">${d.tier}</span></td><td><span class="bd ${bc}">${st}</span></td>
<td class="${expClass}">${rem>0?remStr:'—'}</td>
<td style="color:var(--t3);font-size:11px">${expStr}</td>
<td>${d.uses||0}</td>
<td><span class="tag">${d.vendor||'—'}</span></td>
<td style="color:var(--t3);max-width:100px;overflow:hidden;text-overflow:ellipsis;white-space:nowrap">${dev}</td>
<td style="color:var(--t3)">${d.note||'—'}</td>
<td><div class="acts key-actions"><button type="button" class="btn b-gh key-menu-toggle" aria-label="Abrir menú de acciones" aria-expanded="false" aria-controls="key-actions-${encodeURIComponent(d.key)}" title="Acciones">⋯</button><div class="key-action-menu" id="key-actions-${encodeURIComponent(d.key)}"><div class="key-action-menu-label">Acciones de licencia</div>
${sa?`<form method="POST" action="/keys/${encodeURIComponent(d.key)}/addtime" onsubmit="return confirm('¿Aplicar este cambio de tiempo? Usa días negativos para restar.')" style="display:inline-flex;gap:3px;align-items:center;margin-right:3px"><input name="d" type="number" min="-3650" max="3650" placeholder="d" title="días" style="width:38px;padding:5px;font-size:11px;background:var(--bg2);border:1px solid var(--b1);border-radius:6px;color:var(--t)"><input name="h" type="number" min="0" max="23" placeholder="h" title="horas" style="width:38px;padding:5px;font-size:11px;background:var(--bg2);border:1px solid var(--b1);border-radius:6px;color:var(--t)"><button class="btn b-sm b-ok" title="Agregar tiempo">➕</button></form>`:''}
${sa?`<form method="POST" action="/keys/${encodeURIComponent(d.key)}/notice" style="display:inline-flex;gap:3px;align-items:center;margin-right:3px"><input name="notice" value="${(d.notice||'').replace(/"/g,'&quot;')}" placeholder="motivo o anuncio..." title="Motivo visible si se bloquea o pausa" style="width:110px;padding:5px;font-size:11px;background:var(--bg2);border:1px solid ${d.notice?'var(--a)':'var(--b1)'};border-radius:6px;color:var(--t)"><button class="btn b-sm ${d.notice?'b-pr':'b-w'}" title="Guardar mensaje">💬</button></form>`:''}
${sa?`<form method="POST" action="/keys/${encodeURIComponent(d.key)}/reasons" style="display:inline-flex;gap:3px;align-items:center;margin-right:3px"><input name="pauseReason" value="${(d.pauseReason||'').replace(/"/g,'&quot;')}" placeholder="pausa..." title="Motivo de pausa" style="width:76px;padding:5px;font-size:11px;background:var(--bg2);border:1px solid ${d.pauseReason?'var(--w)':'var(--b1)'};border-radius:6px;color:var(--t)"><input name="lockReason" value="${(d.lockReason||'').replace(/"/g,'&quot;')}" placeholder="bloqueo..." title="Motivo de bloqueo" style="width:76px;padding:5px;font-size:11px;background:var(--bg2);border:1px solid ${d.lockReason?'var(--e)':'var(--b1)'};border-radius:6px;color:var(--t)"><button class="btn b-sm b-gh" title="Guardar motivos">⚑</button></form>`:''}
${sa?`<a href="/keys/${encodeURIComponent(d.key)}/history" class="btn b-sm b-gh" title="Historial de la key">⌁</a>`:''}
<a href="/keys/${encodeURIComponent(d.key)}/pause" class="btn b-sm ${d.paused?'b-ok':'b-w'}" onclick="return confirm('${d.paused?'¿Reanudar esta key?':'¿Pausar esta key?'}')" title="${d.paused?'Reanudar':'Pausar'}">${d.paused?'▶':'⏸'}</a>
${sa?`<a href="/keys/${encodeURIComponent(d.key)}/poison" class="btn b-sm ${d.poisoned?'b-e':'b-w'}" title="${d.poisoned?'Quitar veneno':'Envenenar (crashea Free Fire)'}" onclick="return confirm('${d.poisoned?'¿Quitar el veneno de esta key?':'¿ENVENENAR esta key? Su Free Fire crasheará al inyectar.'}')">${d.poisoned?'☠️':'☠'}</a>`:''}
${d.unlimitedDevices?'':`<a href="/keys/${encodeURIComponent(d.key)}/reset" class="btn b-sm b-gh" onclick="return confirm('¿Resetear el dispositivo y reactivar la key?')" title="Reset HWID">↺</a>`}
${sa&&d.hwid?`<a href="/keys/${encodeURIComponent(d.key)}/ban" class="btn b-sm b-e" onclick="return confirm('¿Banear dispositivo y enviar key a papelera?')">🚫</a>`:''}
<a href="/keys/${encodeURIComponent(d.key)}/trash" class="btn b-sm b-e" onclick="return confirm('¿Mover a papelera?')">🗑</a>
</div></div></td></tr>`;
    }
        const pageHref=(cur,stack,n)=>{const p=new URLSearchParams();if(qRaw)p.set('q',qRaw);if(statusFilter)p.set('status',statusFilter);if(searchMode){if(n>1)p.set('page',String(n));}else{if(cur)p.set('cursor',cur);if(stack.length)p.set('stack',JSON.stringify(stack));}return '/keys'+(p.toString()?'?'+p.toString().replace(/&/g,'&amp;'):'');};
    const pageLinks=[];if(searchMode){const totalPages=Math.ceil(allFilteredCount/pageSize);if(pageNo>1)pageLinks.push('<a class="btn b-gh b-sm" href="'+pageHref('',[],pageNo-1)+'">← Anterior</a>');const firstPage=Math.max(1,pageNo-3),lastPage=Math.min(totalPages,pageNo+3);if(firstPage>1){pageLinks.push('<a class="btn b-gh b-sm" href="'+pageHref('',[],1)+'">1</a>');if(firstPage>2)pageLinks.push('<span style="padding:6px;color:var(--t3)">…</span>');}for(let n=firstPage;n<=lastPage;n++)pageLinks.push(n===pageNo?'<span class="btn b-pr b-sm" aria-current="page">'+n+'</span>':'<a class="btn b-gh b-sm" href="'+pageHref('',[],n)+'">'+n+'</a>');if(pageNo<totalPages)pageLinks.push('<a class="btn b-gh b-sm" href="'+pageHref('',[],pageNo+1)+'">Siguiente →</a>');}
    else{if(pageNo>1)pageLinks.push('<a class="btn b-gh b-sm" href="'+pageHref(cursorStack[cursorStack.length-1]||'',cursorStack.slice(0,-1))+'">← Anterior</a>');const firstPage=Math.max(1,pageNo-3);if(firstPage>1){pageLinks.push('<a class="btn b-gh b-sm" href="'+pageHref('',[],1)+'">1</a>');if(firstPage>2)pageLinks.push('<span style="padding:6px;color:var(--t3)">…</span>');}for(let n=firstPage;n<=pageNo;n++){const c=n===1?'':n===pageNo?currentCursor:(cursorStack[n-1]||''),st=cursorStack.slice(0,n-1);pageLinks.push(n===pageNo?'<span class="btn b-pr b-sm" aria-current="page">'+n+'</span>':'<a class="btn b-gh b-sm" href="'+pageHref(c,st)+'">'+n+'</a>');}if(!kl.list_complete&&kl.cursor)pageLinks.push('<a class="btn b-gh b-sm" href="'+pageHref(kl.cursor,cursorStack.concat([currentCursor]))+'">Siguiente →</a>');}
    const paginationHtml=pageLinks.length?'<nav class="acts" aria-label="Paginación" style="display:flex;justify-content:center;gap:6px;flex-wrap:wrap;margin-top:16px">'+pageLinks.join('')+'</nav>':'';
    const keysSummary=searchMode?total+' keys mostradas · '+allFilteredCount+' coincidencias · página '+pageNo+' · máximo 20':total+' keys en esta página · página '+pageNo+' · máximo 20';
return wrap('Keys',`
<div class="ph">
<div><h1>Keys</h1><p>${keysSummary}</p></div>
<div class="acts">
<a href="/keys/create" class="btn b-pr">＋ Manual</a>
<a href="/keys/generate" class="btn b-ok">⚡ Generar</a>
<a href="/keys/create-trial" class="btn b-w">⏱ Trial</a>
${rows?`<button class="btn b-gh" onclick="csv('ktbl','keys-${new Date().toISOString().slice(0,10)}')">↓ CSV</button>`:''}
${sa?`<button class="btn b-e" onclick="delAll()">🗑 Eliminar TODAS</button><form id="daForm" method="POST" action="/keys/delete-all" style="display:none"></form>`:''}
</div></div>
<div class="card">
<div class="card-h"><span class="card-t">🔑 Lista de Keys</span></div>
<div class="card-b">
<div class="sf"><input placeholder="Filtrar las keys de esta página (máx. 20)" oninput="ft(this,'ktbl')"></div>
<div class="tw">${rows
  ?`<table><thead><tr><th>Key</th><th>Nivel</th><th>Estado</th><th>Restante</th><th>Expira</th><th>Usos</th><th>Vendedor</th><th>Dispositivo</th><th>Nota</th><th>Holograma</th><th>Acciones</th></tr></thead><tbody id="ktbl">${rows}</tbody></table>`
  :`<div class="em"><span class="em-ic">🔑</span><p class="em-t">No hay keys</p><p class="em-s">Crea una key manual o genera un lote</p></div>`}
</div>${paginationHtml}</div></div>`,ses);
  }

  /* Delete ALL */
  if(path==='/keys/delete-all'&&mt==='POST'&&sa){
    const kl=await env.DZH_KV.list({prefix:'dzh_key:'});let cnt=0;
    for(const k of kl.keys){await env.DZH_KV.delete(k.name);cnt++;}
    await al(env,me,'DELETE_ALL',cnt+' keys');
    return new Response('',{status:302,headers:{Location:'/keys'}});
  }

  /* Create key */
  if(path==='/keys/create'){
    if(mt==='POST'){
      const f=await req.formData();
      const kn=(f.get('key')||'').trim().toUpperCase()||`DZ-${gk(4)}-${gk(4)}`;
      let days=parseInt(f.get('days')||'30');
      const note=f.get('note')||'';
      const tier=(sa&&f.get('tier')==='pro')?'pro':'basic';
      if(!sa&&days>MXD)days=MXD;
      if(await env.DZH_KV.get('dzh_key:'+kn))return new Response('',{status:302,headers:{Location:'/keys/create?e=2'}});
      await env.DZH_KV.put('dzh_key:'+kn,JSON.stringify({key:kn,days,vendor:me,created:Date.now(),activated:null,hwid:null,paused:false,note,device:null,uses:0,trial:false,tier}));
      await al(env,me,'create_key',kn+' ('+days+'d)');
      return new Response('',{status:302,headers:{Location:'/keys'}});
    }
    const e=url.searchParams.get('e'),maxD=sa?9999:MXD;
    return wrap('Nueva Key',`
<div class="ph"><div><h1>＋ Nueva Key</h1><p>Crear acceso de forma manual</p></div></div>
${e==='2'?'<div class="al al-e">⚠ Esa key ya existe, elige otro nombre.</div>':''}
<div class="card" style="max-width:500px">
<div class="card-h"><span class="card-t">Configuración</span></div>
<div class="card-b"><form method="POST">
<div class="fg"><label>Nombre de la Key <span style="color:var(--t3);font-size:9px;text-transform:none">(vacío = auto-generar)</span></label><input name="key" placeholder="DZ-XXXX-XXXX" style="text-transform:uppercase;font-family:monospace" autocomplete="off"></div>
<div class="g2">
<div class="fg"><label>Duración en días ${!sa?'(máx '+MXD+')':''}</label><input name="days" type="number" value="30" min="1" max="${maxD}"></div>
<div class="fg"><label>Nota (opcional)</label><input name="note" placeholder="Cliente, promo..."></div>
</div>
<div class="fg"><label>Nivel de acceso</label><select name="tier"><option value="basic">Basic</option>${sa?'<option value="pro">Pro</option>':''}</select></div>
<button class="btn b-pr" style="width:100%;padding:11px">Crear Key →</button>
</form></div></div>`,ses);
  }

  /* Trial key - configurable (GET form + POST create) */
  if(path==='/keys/create-trial'){
    const trialForm=(err='',vals={})=>{
      const h=vals.hours??0,m=vals.minutes??1,q=vals.quantity??1,sc=vals.scope||'single';
      const preset=(hh,mm)=>`<button type="button" class="btn b-sm b-gh" data-h="${hh}" data-m="${mm}" onclick="setTrial(${hh},${mm})">${hh?hh+' h':''}${hh&&mm?' ':''}${mm?mm+' min':''}</button>`;
      return wrap('Trial',`
<div class="ph"><div><h1>⏱ Crear Trial</h1><p>Duración entre 1 minuto y 24 horas · la cuenta regresiva inicia en la primera activación</p></div></div>
${err?`<div class="al al-e">⚠ ${err}</div>`:''}
<div class="card" style="max-width:560px">
<div class="card-h"><span class="card-t">Configuración de la Trial</span></div>
<div class="card-b"><form method="POST" action="/keys/create-trial">
<div class="fg"><label>Presets rápidos</label><div class="acts" style="flex-wrap:wrap">${preset(0,1)}${preset(0,30)}${preset(1,0)}${preset(1,30)}${preset(6,0)}${preset(24,0)}</div></div>
<div class="g2">
<div class="fg"><label>Horas (0–24)</label><input id="tHours" name="hours" type="number" value="${h}" min="0" max="24" step="1" required></div>
<div class="fg"><label>Minutos (0–59)</label><input id="tMinutes" name="minutes" type="number" value="${m}" min="0" max="59" step="1" required></div>
</div>
<div class="g2">
<div class="fg"><label>Alcance</label><select id="tScope" name="scope" onchange="trialScope()">
<option value="single" ${sc==='single'?'selected':''}>Individual · 1 dispositivo por key</option>
${sa?`<option value="all" ${sc==='all'?'selected':''}>Global · dispositivos ilimitados</option>`:`<option value="all" disabled>Global · Sólo superadmin</option>`}
</select></div>
<div class="fg"><label>Cantidad de keys (1–10)</label><input id="tQty" name="quantity" type="number" value="${q}" min="1" max="10" step="1" required></div>
</div>
<div class="al al-w" style="font-size:11px">Las keys individuales se ligan al primer dispositivo que las active. La trial global funciona en dispositivos ilimitados y sólo genera una key.</div>
<button class="btn b-w" style="width:100%;padding:11px">⏱ Crear Trial →</button>
</form></div></div>
<script>
function setTrial(h,m){document.getElementById('tHours').value=h;document.getElementById('tMinutes').value=m;}
function trialScope(){const all=document.getElementById('tScope').value==='all',q=document.getElementById('tQty');if(all){q.value=1;q.disabled=true;}else q.disabled=false;}
trialScope();
</script>`,ses);
    };
    if(mt==='POST'){
      const f=await req.formData();
      const hours=Number(f.get('hours')||0);
      const minutes=Number(f.get('minutes')||0);
      const requestedScope=f.get('scope')==='all'?'all':'single';
      const requestedQuantity=Number(f.get('quantity')||1);
      const vals={hours,minutes,scope:requestedScope,quantity:requestedQuantity};
      if(!Number.isInteger(hours)||hours<0||hours>24)return trialForm('Horas inválidas',vals);
      if(!Number.isInteger(minutes)||minutes<0||minutes>59)return trialForm('Minutos inválidos',vals);
      const totalMinutes=hours*60+minutes;
      const durationSeconds=totalMinutes*60;
      if(durationSeconds<60||durationSeconds>86400)return trialForm('La duración debe estar entre 1 minuto y 24 horas',vals);
      if(requestedScope==='all'&&!sa)return new Response('Forbidden',{status:403});
      if(!Number.isInteger(requestedQuantity))return trialForm('Cantidad inválida',vals);
      const scope=requestedScope;
      const quantity=scope==='all'?1:requestedQuantity;
      if(scope==='single'&&(quantity<1||quantity>10))return trialForm('La cantidad debe estar entre 1 y 10',vals);
      const generated=[];
      for(let i=0;i<quantity;i++){
        let key,attempts=0;
        do{key=`${scope==='all'?'GIFT':'TRIAL'}-${gk(8)}`;attempts++;}while(await env.DZH_KV.get('dzh_key:'+key)&&attempts<30);
        if(attempts>=30)continue;
        const record={key,days:durationSeconds/86400,durationSeconds,vendor:me,created:Date.now(),activated:null,hwid:null,paused:false,note:`Trial ${formatDuration(durationSeconds)}`,device:null,uses:0,trial:true,unlimitedDevices:scope==='all'};
        await env.DZH_KV.put('dzh_key:'+key,JSON.stringify(record));
        generated.push(key);
      }
      await al(env,me,'create_trial',generated.length+'x '+formatDuration(durationSeconds)+' ('+(scope==='all'?'global':'individual')+')');
      return wrap('Trial',`
<div class="ph"><div><h1>⏱ Trial${generated.length>1?'s':''} creada${generated.length>1?'s':''}</h1><p>${generated.length} key${generated.length>1?'s':''} · ${formatDuration(durationSeconds)} · ${scope==='all'?'global · dispositivos ilimitados':'individual · 1 dispositivo por key'}</p></div>
<div class="acts"><a href="/keys/create-trial" class="btn b-w">⏱ Crear otra trial</a><a href="/keys" class="btn b-pr">Ver Keys</a></div></div>
${generated.length>0?`
<div class="al al-w" style="font-size:12px">La cuenta regresiva de <b>${formatDuration(durationSeconds)}</b> comienza cuando el usuario active cada key.</div>
<div class="card">
<div class="card-h"><span class="card-t">${generated.length} Key${generated.length>1?'s':''} generada${generated.length>1?'s':''}</span><button class="btn b-sm b-gh" onclick="cp('kbox',this)">📋 Copiar todo</button></div>
<div class="card-b"><div class="kb" id="kbox">${generated.join('\n')}</div></div></div>`:'<div class="al al-e">Error al generar keys.</div>'}`,ses);
    }
    const pre=url.searchParams.get('scope')==='all'&&sa?{scope:'all',hours:24,minutes:0,quantity:1}:{};
    return trialForm('',pre);
  }

  /* Generate */
  if(path==='/keys/generate'){if(mt==='POST'){const f=await req.formData();const vr=sa?null:await env.DZH_KV.get('dzh_vendor:'+me);if(!sa&&!vr)return wrap('Vendedor no encontrado','<div class="al al-e">No existe una cuenta de vendedor activa.</div>',ses);const v=vr?JSON.parse(vr):{},unlimited=!!v.unlimited&&(!v.unlimitedUntil||Number(v.unlimitedUntil)>Date.now());let qty=Math.min(MXG,Math.max(1,parseInt(f.get('qty')||'5',10)||5));if(!sa&&!unlimited)qty=Math.min(qty,10);let days=parseInt(f.get('days')||'30',10)||30;days=sa?Math.max(1,Math.min(9999,days)):Math.max(1,Math.min(30,days));const prefix=sa?(f.get('prefix')||'DZ').toUpperCase().replace(/[^A-Z0-9]/g,'').slice(0,8):String(v.keyPrefix||'DZ').toUpperCase().replace(/[^A-Z0-9]/g,'').slice(0,8);const note=(f.get('note')||'').toString().slice(0,300),tier=(sa&&f.get('tier')==='pro')?'pro':'basic',prices=JSON.parse((await env.DZH_KV.get('dzh_precios'))||'{}'),pr=v.customPrice||prices,cost=sa||unlimited?0:Math.max(0,Number(pr['d'+days]||0)),balance=Number(v.balance||0),requestedTotal=cost*qty;if(!sa&&!unlimited&&balance<requestedTotal)return wrap('Saldo insuficiente','<div class="ph"><div><h1>Saldo insuficiente</h1><p>El lote cuesta '+requestedTotal+' créditos y el saldo disponible es '+balance+'.</p></div><a href="/keys/generate" class="btn b-ok">Volver</a></div>',ses);const generated=[];for(let i=0;i<qty;i++){let key,att=0;do{key=prefix+'-'+gk(4)+'-'+gk(4);att++;}while(await env.DZH_KV.get('dzh_key:'+key)&&att<30);if(att>=30)continue;const fundingSource=sa?'admin':unlimited?'unlimited':'balance',rec={key,days,durationSeconds:days*86400,vendor:me,created:Date.now(),activated:null,hwid:null,paused:false,note,device:null,uses:0,trial:false,tier,fundingSource};if(fundingSource==='unlimited')rec.fundingUnlimitedUntil=v.unlimitedUntil||null;await env.DZH_KV.put('dzh_key:'+key,JSON.stringify(rec));if(fundingSource==='unlimited')await env.DZH_KV.put('dzh_unlimited_key:'+me+':'+key,'1');generated.push(key);}const charged=(!sa&&!unlimited)?cost*generated.length:0;if(!sa&&charged>0){v.balance=Math.max(0,balance-charged);await env.DZH_KV.put('dzh_vendor:'+me,JSON.stringify(v));}await al(env,me,'gen_keys',generated.length+'x ('+days+'d) · '+(unlimited?'ilimitado':charged+' créditos'));return wrap('Generadas','<div class="ph"><div><h1>⚡ Keys generadas</h1><p>'+generated.length+' keys · '+days+' días · '+(unlimited?'Ilimitado':('Cobrado: '+charged+' · saldo: '+(v.balance||0)))+'</p></div><div class="acts"><a href="/keys/generate" class="btn b-ok">⚡ Generar más</a><a href="/keys" class="btn b-pr">Ver Keys</a></div></div>'+(generated.length?'<div class="card"><div class="card-h"><span class="card-t">'+generated.length+' Keys</span><button class="btn b-sm b-gh" onclick="cp(&quot;kbox&quot;,this)">📋 Copiar todo</button></div><div class="card-b"><div class="kb" id="kbox">'+generated.join('\n')+'</div></div></div>':'<div class="al al-e">No se generaron keys.</div>'),ses);}const vr=sa?null:await env.DZH_KV.get('dzh_vendor:'+me),v=vr?JSON.parse(vr):{},unlimited=!!v.unlimited&&(!v.unlimitedUntil||Number(v.unlimitedUntil)>Date.now()),maxD=sa?9999:30,maxQ=sa||unlimited?MXG:10,prefixDefault=sa?'DZ':String(v.keyPrefix||'DZ').toUpperCase().replace(/[^A-Z0-9]/g,'').slice(0,8);return wrap('Generar Keys','<div class="ph"><div><h1>⚡ Generar Keys</h1><p>Lote Bulk · máximo '+maxQ+' por generación</p></div></div><div class="card" style="max-width:520px"><div class="card-h"><span class="card-t">Parámetros</span></div><div class="card-b"><form method="POST"><div class="g3"><div class="fg"><label>Cantidad (máx '+maxQ+')</label><input name="qty" type="number" value="5" min="1" max="'+maxQ+'" required></div><div class="fg"><label>Días '+(sa?'':'(máx 30)')+'</label><input name="days" type="number" value="30" min="1" max="'+maxD+'" required></div><div class="fg"><label>Prefijo</label><input name="prefix" value="'+prefixDefault+'" maxlength="8" style="text-transform:uppercase;font-family:monospace" '+(sa?'':'readonly')+'></div><div class="fg"><label>Nivel</label><select name="tier"><option value="basic">Basic</option>'+(sa?'<option value="pro">Pro</option>':'')+'</select></div></div><div class="fg"><label>Nota (opcional)</label><input name="note" placeholder="Batch, promo..."></div><div class="al al-w" style="font-size:11px">'+(sa?'Generación administrativa.':(unlimited?'Ilimitado activo hasta '+(v.unlimitedUntil?fmtDate(Number(v.unlimitedUntil)):'revocación')+'.':'Cada key se cobra con la tabla de precios compartida; saldo actual: '+(v.balance||0)+' créditos.'))+'</div><button class="btn b-ok" style="width:100%;padding:11px">⚡ Generar ahora</button></form></div></div>',ses);}/* Key actions */
  const msgm=path.match(/^\/keys\/(.+)\/notice$/);
  if(msgm&&sa&&mt==='POST'){const kn=decodeURIComponent(msgm[1]);const f=await req.formData();const txt=(f.get('notice')||'').toString().slice(0,300);const r=await env.DZH_KV.get('dzh_key:'+kn);if(r){const d=JSON.parse(r),before=d.notice||'';d.notice=txt;await env.DZH_KV.put('dzh_key:'+kn,JSON.stringify(d));await al(env,me,'set_notice',kn+' '+(txt?'msg':'vacio'));await keyLog(env,kn,me,'set_notice',before+' -> '+txt);}return new Response('',{status:302,headers:{Location:'/keys'}});}
  const khm=path.match(/^\/keys\/(.+)\/history$/);
  if(khm&&sa){const kn=decodeURIComponent(khm[1]);const list=await env.DZH_KV.list({prefix:'keylog:'+kn+':'});const entries=[];for(const x of list.keys){const v=await env.DZH_KV.get(x.name);if(v){try{entries.push(JSON.parse(v));}catch(e){}}}entries.sort((a,b)=>(b.ts||0)-(a.ts||0));const rows=entries.slice(0,200).map(x=>`<tr><td>${keyHistoryEsc(new Date(x.ts||0).toLocaleString('es-MX'))}</td><td><span class="tag">${keyHistoryEsc(x.action||'')}</span></td><td>${keyHistoryEsc(x.who||'')}</td><td style="white-space:pre-wrap;max-width:520px">${keyHistoryEsc(x.detail||'')}</td></tr>`).join('');return wrap('Historial de key',`<div class="ph"><div><h1>⌁ Historial</h1><p><code>${keyHistoryEsc(kn)}</code> · últimos ${Math.min(entries.length,200)} cambios</p></div><div class="acts"><a href="/keys" class="btn b-gh">Volver a Keys</a></div></div><div class="card"><div class="card-h"><span class="card-t">Cambios registrados</span></div><div class="card-b"><div class="tw">${rows?`<table><thead><tr><th>Fecha</th><th>Acción</th><th>Usuario</th><th>Detalle</th></tr></thead><tbody>${rows}</tbody></table>`:`<div class="em"><p class="em-t">No hay cambios registrados todavía.</p></div>`}</div></div></div>`,ses);}
  const rsm=path.match(/^\/keys\/(.+)\/reasons$/);
  if(rsm&&sa&&mt==='POST'){const kn=decodeURIComponent(rsm[1]);const f=await req.formData();const r=await env.DZH_KV.get('dzh_key:'+kn);if(r){const d=JSON.parse(r),before={pauseReason:d.pauseReason||'',lockReason:d.lockReason||''};d.pauseReason=(f.get('pauseReason')||'').toString().slice(0,300);d.lockReason=(f.get('lockReason')||'').toString().slice(0,300);await env.DZH_KV.put('dzh_key:'+kn,JSON.stringify(d));await al(env,me,'set_key_reasons',kn);await keyLog(env,kn,me,'set_key_reasons',JSON.stringify({before,after:{pauseReason:d.pauseReason,lockReason:d.lockReason}}));}return new Response('',{status:302,headers:{Location:'/keys'}});}
  const atm=path.match(/^\/keys\/(.+)\/addtime$/);
  if(atm&&sa&&mt==='POST'){const kn=decodeURIComponent(atm[1]);const f=await req.formData();const dd=parseInt(f.get('d')||'0',10)||0;const hh=parseInt(f.get('h')||'0',10)||0;const deltaSec=dd*86400+hh*3600;if(Math.abs(dd)>3650||hh<0||hh>23)return new Response('',{status:302,headers:{Location:'/keys'}});const r=await env.DZH_KV.get('dzh_key:'+kn);if(r&&deltaSec!==0){const d=JSON.parse(r),before=expDate(d)||durationSecondsOf(d);if(d.activated){d.activated=d.activated+deltaSec*1000;}else{d.durationSeconds=Math.max(0,durationSecondsOf(d)+deltaSec);}await env.DZH_KV.put('dzh_key:'+kn,JSON.stringify(d));await al(env,me,deltaSec>0?'add_time_key':'remove_time_key',kn+' '+(deltaSec>0?'+':'')+dd+'d'+hh+'h');await keyLog(env,kn,me,deltaSec>0?'add_time_key':'remove_time_key',String(before)+' -> '+String(expDate(d)||durationSecondsOf(d)));}return new Response('',{status:302,headers:{Location:'/keys'}});}
  const rh=path.match(/^\/keys\/(.+)\/revive-hologram$/);
  if(rh&&sa){const vendor=url.searchParams.get('vendor')==='1';const kn=decodeURIComponent(rh[1]);const r=await env.DZH_KV.get('dzh_key:'+kn);if(r){const adminLive=!!(await env.DZH_KV.get('dzh_holoAdmin:'+kn)&&!await env.DZH_KV.get('dzh_modeused:'+kn+':holograma_mio'));const vendorLive=!!(await env.DZH_KV.get('dzh_holoAccess:'+kn)&&!await env.DZH_KV.get('dzh_modeused:'+kn+':holograma_revendedor'));if(vendor&&!adminLive){if(!vendorLive){await env.DZH_KV.put('dzh_holoAccess:'+kn,'1');await env.DZH_KV.delete('dzh_holoAdmin:'+kn);for(const mid of ['holograma','holograma_mio','holograma_revendedor'])await env.DZH_KV.delete('dzh_modeused:'+kn+':'+mid);await al(env,me,'grant_vendor_hologram',kn);}}else if(!vendor&&!vendorLive){if(!adminLive){await env.DZH_KV.put('dzh_holoAdmin:'+kn,'1');await env.DZH_KV.delete('dzh_holoAccess:'+kn);for(const mid of ['holograma','holograma_mio','holograma_revendedor'])await env.DZH_KV.delete('dzh_modeused:'+kn+':'+mid);await al(env,me,'grant_admin_hologram',kn);}}}return new Response('',{status:302,headers:{Location:'/keys'}});} if(false){const kn=decodeURIComponent(rh[1]);const r=await env.DZH_KV.get('dzh_key:'+kn);if(r){const d=JSON.parse(r);await env.DZH_KV.put('dzh_holoAdmin:'+kn,'1');for(const mid of ['holograma','holograma_mio','holograma_revendedor'])await env.DZH_KV.delete('dzh_modeused:'+kn+':'+mid);await al(env,me,'grant_admin_hologram',kn);};return new Response('',{status:302,headers:{Location:'/keys'}});}
  const km=path.match(/^\/keys\/(.+)\/(pause|reset|trash|ban|poison)$/);
  if(km){
    const kn=decodeURIComponent(km[1]),act=km[2];
    const r=await env.DZH_KV.get('dzh_key:'+kn);
    if(r){const d=JSON.parse(r);if(sa||d.vendor===me){
      if(act==='pause'){const before=d.paused;d.paused=!d.paused;await env.DZH_KV.put('dzh_key:'+kn,JSON.stringify(d));await keyLog(env,kn,me,d.paused?'pause_key':'resume_key',JSON.stringify({from:before,to:d.paused,pauseReason:d.pauseReason||''}));}
      if(act==='poison'){d.poisoned=!d.poisoned;await env.DZH_KV.put('dzh_key:'+kn,JSON.stringify(d));await al(env,me,'poison',kn+' '+(d.poisoned?'ON':'OFF'));await keyLog(env,kn,me,'poison',d.poisoned?'ON':'OFF');}
      if(act==='reset'){const before=d.hwid||'';d.hwid=null;d.activated=null;d.device=null;d.fp=null;await env.DZH_KV.put('dzh_key:'+kn,JSON.stringify(d));await keyLog(env,kn,me,'reset_key',before?'HWID reset':'key reset');}
      if(act==='trash'){d.trashedAt=Date.now();d.trashedBy=me;await env.DZH_KV.put('dzh_trash:'+kn,JSON.stringify(d));await env.DZH_KV.delete('dzh_key:'+kn);await keyLog(env,kn,me,'trash_key',d.note||'');}
      if(act==='ban'&&d.hwid){await env.DZH_KV.put('ban:'+d.hwid,JSON.stringify({hwid:d.hwid,reason:'Key '+kn,created:Date.now(),by:me}));d.trashedAt=Date.now();d.trashedBy=me;d.banReason='Dispositivo baneado';await env.DZH_KV.put('dzh_trash:'+kn,JSON.stringify(d));await env.DZH_KV.delete('dzh_key:'+kn);await keyLog(env,kn,me,'ban_key',d.lockReason||d.notice||'Dispositivo baneado');}
      await al(env,me,act+'_key',kn);
    }}
    return new Response('',{status:302,headers:{Location:'/keys'}});
  }

  /* Trash */
  if(path==='/trash'){
    const tl=await env.DZH_KV.list({prefix:'dzh_trash:'});let rows='';
    for(const t of tl.keys){const r=await env.DZH_KV.get(t.name);if(!r)continue;const d=JSON.parse(r);if(!sa&&d.vendor!==me)continue;rows+=`<tr><td><code>${d.key}</code></td><td><span class="tag">${d.vendor||'—'}</span></td><td>${d.durationSeconds?formatDuration(durationSecondsOf(d)):d.days+'d'}</td><td style="color:var(--t3)">${d.trashedBy||'—'}</td><td style="color:var(--t3)">${d.trashedAt?fmtDate(d.trashedAt):'—'}</td><td style="color:var(--e)">${d.banReason||d.note||'—'}</td><td><div class="acts"><a href="/trash/${encodeURIComponent(d.key)}/restore" class="btn b-sm b-ok">↺ Restaurar</a><a href="/trash/${encodeURIComponent(d.key)}/delete" class="btn b-sm b-e" onclick="return confirm('¿Eliminar permanentemente?')">✕</a></div></td></tr>`;}
    return wrap('Papelera',`
<div class="ph"><div><h1>🗑 Papelera</h1><p>Keys eliminadas — puedes restaurarlas</p></div></div>
<div class="card"><div class="card-h"><span class="card-t">Keys en papelera</span></div><div class="card-b"><div class="tw">
${rows?`<table><thead><tr><th>Key</th><th>Vendedor</th><th>Duración</th><th>Eliminada por</th><th>Fecha</th><th>Motivo</th><th>Acciones</th></tr></thead><tbody>${rows}</tbody></table>`:`<div class="em"><span class="em-ic">🗑</span><p class="em-t">Papelera vacía</p></div>`}
</div></div></div>`,ses);
  }
  const tm=path.match(/^\/trash\/(.+)\/(restore|delete)$/);
  if(tm){const kn=decodeURIComponent(tm[1]),act=tm[2];const r=await env.DZH_KV.get('dzh_trash:'+kn);if(r){const d=JSON.parse(r);if(sa||d.vendor===me){if(act==='restore'){delete d.trashedAt;delete d.trashedBy;delete d.banReason;await env.DZH_KV.put('dzh_key:'+kn,JSON.stringify(d));await env.DZH_KV.delete('dzh_trash:'+kn);}if(act==='delete')await env.DZH_KV.delete('dzh_trash:'+kn);await al(env,me,act+'_key',kn);}}return new Response('',{status:302,headers:{Location:'/trash'}});}

  /* Vendors */
  if(path==='/vendors'&&sa){
    const vl=await env.DZH_KV.list({prefix:'dzh_vendor:',limit:1000});let rows='';const vendorStats=new Map();
    const thisMonth=new Date();thisMonth.setDate(1);thisMonth.setHours(0,0,0,0);
    let keyCursor;do{const keyPage=await env.DZH_KV.list({prefix:'dzh_key:',limit:1000,cursor:keyCursor});for(let i=0;i<keyPage.keys.length;i+=100){const batch=await Promise.all(keyPage.keys.slice(i,i+100).map(async k=>{const kr=await env.DZH_KV.get(k.name);if(!kr)return null;try{return JSON.parse(kr)}catch(e){return null}}));for(const kd of batch){if(!kd||!kd.vendor)continue;const x=vendorStats.get(kd.vendor)||{cnt:0,usos:0,newM:0,actM:0};x.cnt++;x.usos+=Number(kd.uses||0);if(Number(kd.created||0)>=thisMonth.getTime())x.newM++;if(kd.activated&&secondsLeft(kd)>0)x.actM++;vendorStats.set(kd.vendor,x);}}keyCursor=keyPage.list_complete?undefined:keyPage.cursor;}while(keyCursor);
    for(const v of vl.keys){
      const r=await env.DZH_KV.get(v.name);if(!r)continue;const d=JSON.parse(r);

      const agg=vendorStats.get(d.username)||{cnt:0,usos:0,newM:0,actM:0},cnt=agg.cnt,usos=agg.usos,newM=agg.newM,actM=agg.actM;
      const pct=cnt>0?Math.min(100,Math.round(actM/cnt*100)):0;
      rows+=`<tr>
<td><b>${d.username}</b><div style="font-size:10px;color:var(--t3)">${d.name||''}</div></td>
<td><code style="font-family:monospace;color:var(--a2)">${d.keyPrefix||'DZ'}</code></td>
<td><span class="bd ${d.active?'bv':'be'}">${d.active?'Activo':'Suspendido'}</span></td>
<td>${cnt}<div class="sbar"><div class="sbar-f" style="width:${pct}%"></div></div></td>
<td style="color:var(--ok)">+${newM}</td>
<td style="color:var(--a2)">${usos}</td>
<td style="color:var(--t3);font-size:11px">${fmtDate(d.created)}</td>
<td>${d.unlimited&&(!d.unlimitedUntil||Number(d.unlimitedUntil)>Date.now())?'<span style="color:var(--a2);font-weight:700">∞ ilimitado'+(d.unlimitedUntil?' · hasta '+fmtDate(Number(d.unlimitedUntil)):' · sin vencimiento')+'</span>':('<b>'+(d.balance||0)+'</b> <span style="color:var(--t3);font-size:11px">créditos</span>')}</td>
<td><div class="acts">
<form method="POST" action="/vendors/${d.username}/balance" style="display:inline-flex;gap:3px;align-items:center;margin-right:3px"><input name="amt" type="number" placeholder="+/-" style="width:56px;padding:5px;font-size:11px;background:var(--bg2);border:1px solid var(--b1);border-radius:6px;color:var(--t)"><button class="btn b-sm b-ok" title="Sumar/restar saldo">💰</button></form>
<form method="POST" action="/vendors/${d.username}/unlimited" style="display:inline-flex;gap:3px;align-items:center;flex-wrap:wrap;margin-right:3px" onsubmit="return confirm('Asignar o extender ilimitado por el periodo elegido. Se suma a la fecha de vencimiento actual.')"><input name="amount" type="number" min="1" max="365" value="30" required style="width:52px;padding:4px;font-size:11px;background:var(--bg2);border:1px solid var(--b1);border-radius:6px;color:var(--t)"><select name="unit" onchange="const i=this.form.elements.amount;i.max=this.value==='minutes'?'1440':'365';if(Number(i.value)>Number(i.max))i.value=i.max" style="width:82px;padding:4px;font-size:11px;background:var(--bg2);border:1px solid var(--b1);border-radius:6px;color:var(--t)"><option value="days">días</option><option value="minutes">minutos</option></select><button class="btn b-sm b-ok" title="Asignar o extender ilimitado">${d.unlimited&&(!d.unlimitedUntil||Number(d.unlimitedUntil)>Date.now())?'Extender ∞':'Asignar ∞'}</button></form> <form method="POST" action="/vendors/${d.username}/unlimited/revoke" style="display:inline-flex" onsubmit="return confirm('¿Quitar ilimitado? Sus keys de ilimitado se pausarán; las keys de saldo no se modifican.')"><button class="btn b-sm b-e" title="Quitar ilimitado y pausar solo las keys de ese origen" ${d.unlimited?'':'disabled'}>⛔ Quitar ilimitado</button></form>
<a href="/vendors/${d.username}/profile" class="btn b-sm b-pr" title="Configurar prefijo de keys e ID de Telegram">🔤 Prefijo</a> <a href="/vendor/${d.username}" class="btn b-sm b-pr">📋</a>
<a href="/vendors/${d.username}/toggle" class="btn b-sm ${d.active?'b-w':'b-ok'}">${d.active?'⏸':'▶'}</a>
<form method="POST" action="/vendors/${d.username}/archive" style="display:inline" onsubmit="return confirm('⚠️ Eliminar el vendedor y todas sus keys permanentemente?')&&confirm('🔴 No se puede deshacer. ¿Confirmas?')"><button type="submit" class="btn b-sm b-e" title="Eliminar vendedor y revocar su acceso">🗑 Eliminar vendedor</button></form>
</div></td></tr>`;
    }
    return wrap('Vendedores',`
<div class="ph"><div><h1>🏪 Vendedores</h1><p>Gestión de revendedores</p></div><a href="/vendors/create" class="btn b-ok">＋ Nuevo Vendedor</a></div>
<div class="card"><div class="card-h"><span class="card-t">Lista de vendedores</span></div><div class="card-b"><div class="tw">
${rows?`<table><thead><tr><th>Vendedor</th><th>Prefijo</th><th>Estado</th><th>Saldo</th><th>Keys (activas)</th><th>Nuevas mes</th><th>Registro</th><th>Acciones</th></tr></thead><tbody>${rows}</tbody></table>`:`<div class="em"><span class="em-ic">🏪</span><p class="em-t">No hay vendedores</p></div>`}
</div></div></div>`,ses);
  }
  if(path==='/vendors/create'&&sa){
    if(mt==='POST'){const f=await req.formData();const u=(f.get('u')||'').trim().toLowerCase(),p=f.get('p')||'',n=(f.get('n')||'').trim(),tg=(f.get('tg')||'').trim(),prefix=(f.get('prefix')||'').trim().toUpperCase().replace(/[^A-Z0-9]/g,'').slice(0,8);if(!u||!p||!/^[0-9]{5,15}$/.test(tg)||!/^[A-Z0-9]{2,8}$/.test(prefix))return new Response('',{status:302,headers:{Location:'/vendors/create?e=1'}});if(await env.DZH_KV.get('dzh_vendor:'+u))return new Response('',{status:302,headers:{Location:'/vendors/create?e=2'}});if(await env.DZH_KV.get('vendor_tg:'+tg))return new Response('',{status:302,headers:{Location:'/vendors/create?e=3'}});await env.DZH_KV.put('dzh_vendor:'+u,JSON.stringify({username:u,password:p,name:n,telegramId:tg,keyPrefix:prefix,active:true,created:Date.now(),balance:0,unlimited:false}));await env.DZH_KV.put('vendor_tg:'+tg,u);await al(env,me,'create_vendor',u);return new Response('',{status:302,headers:{Location:'/vendors'}});}
    const e=url.searchParams.get('e');
    return wrap('Nuevo Vendedor',`<div class="ph"><div><h1>＋ Nuevo Vendedor</h1></div></div>${e?'<div class="al al-e">Error: usuario ya existe o datos incompletos.</div>':''}<div class="card" style="max-width:440px"><div class="card-h"><span class="card-t">Datos del vendedor</span></div><div class="card-b"><form method="POST"><div class="fg"><label>Nombre completo</label><input name="n" placeholder="Nombre completo"></div><div class="fg"><label>Usuario</label><input name="u" placeholder="usuario123" autocomplete="off" required></div><div class="fg"><label>Contraseña web</label><input name="p" type="password" placeholder="Contraseña segura" autocomplete="new-password" required></div><div class="fg"><label>ID de Telegram</label><input name="tg" inputmode="numeric" pattern="[0-9]{5,15}" placeholder="Ej. 123456789" required></div><div class="fg"><label>Prefijo para sus keys</label><input name="prefix" value="DZ" minlength="2" maxlength="8" pattern="[A-Za-z0-9]{2,8}" style="text-transform:uppercase;font-family:monospace" required><small style="font-size:11px;color:var(--t3)">Ejemplo: AB genera keys que empiezan con AB-. Solo afecta keys nuevas.</small></div><button class="btn b-ok" style="width:100%">Crear Vendedor</button></form></div></div>`,ses);
  }
  {const vtelegramprofilematch=path.match(new RegExp('^/vendors/([^/]+)/profile$'));if(vtelegramprofilematch&&sa){const vu=vtelegramprofilematch[1];if(mt==='POST'){const f=await req.formData(),tg=(f.get('tg')||'').trim(),prefix=(f.get('prefix')||'').trim().toUpperCase().replace(/[^A-Z0-9]/g,'').slice(0,8),r=await env.DZH_KV.get('dzh_vendor:'+vu);if(!r)return new Response('',{status:302,headers:{Location:'/vendors'}});if(!/^[0-9]{5,15}$/.test(tg)||!/^[A-Z0-9]{2,8}$/.test(prefix))return new Response('',{status:302,headers:{Location:'/vendors/'+vu+'/profile?e=1'}});const owner=await env.DZH_KV.get('vendor_tg:'+tg);if(owner&&owner!==vu)return new Response('',{status:302,headers:{Location:'/vendors/'+vu+'/profile?e=2'}});const d=JSON.parse(r);if(d.telegramId&&d.telegramId!==tg&&await env.DZH_KV.get('vendor_tg:'+d.telegramId)===vu)await env.DZH_KV.delete('vendor_tg:'+d.telegramId);d.telegramId=tg;d.keyPrefix=prefix;await env.DZH_KV.put('dzh_vendor:'+vu,JSON.stringify(d));await env.DZH_KV.put('vendor_tg:'+tg,vu);await al(env,me,'vendor_identity_update',vu);return new Response('',{status:302,headers:{Location:'/vendors'}});}const r=await env.DZH_KV.get('dzh_vendor:'+vu);if(!r)return new Response('',{status:302,headers:{Location:'/vendors'}});const d=JSON.parse(r),e=url.searchParams.get('e'),escProfile=x=>String(x??'').replaceAll('&','&amp;').replaceAll('<','&lt;').replaceAll('>','&gt;').replaceAll('"','&quot;').replaceAll("'",'&#39;');return wrap('Telegram y prefijo', '<div class="ph"><div><h1>Telegram y prefijo</h1><p>Vendedor: '+escProfile(vu)+'</p></div><a href="/vendors" class="btn b-gh">Volver</a></div>'+(e?'<div class="al al-e">ID inválido o ya asociado a otro vendedor.</div>':'')+'<div class="card" style="max-width:520px"><div class="card-b"><form method="POST"><div class="fg"><label>ID de Telegram</label><input name="tg" inputmode="numeric" pattern="[0-9]{5,15}" value="'+escProfile(d.telegramId||'')+'" required></div><div class="fg"><label>Prefijo para las keys futuras</label><input name="prefix" minlength="2" maxlength="8" pattern="[A-Za-z0-9]{2,8}" value="'+escProfile(d.keyPrefix||'DZ')+'" style="text-transform:uppercase;font-family:monospace" required><small style="font-size:11px;color:var(--t3)">El prefijo se aplica a keys nuevas desde la web y Telegram. Ejemplo: AB produce AB-...; las keys existentes no cambian.</small></div><button class="btn b-ok">Guardar</button></form></div></div>',ses);}}const vm=path.match(/^\/vendors\/(.+)\/(toggle|archive)$/);
  // Recargar/quitar saldo a un vendedor
  const vbm=path.match(/^\/vendors\/([^\/]+)\/balance$/);
  if(vbm&&sa&&mt==='POST'){const vu=vbm[1];const f=await req.formData();const amt=parseInt(f.get('amt')||'0',10)||0;const r=await env.DZH_KV.get('dzh_vendor:'+vu);if(r&&amt!==0){const d=JSON.parse(r);d.balance=(d.balance||0)+amt;if(d.balance<0)d.balance=0;await env.DZH_KV.put('dzh_vendor:'+vu,JSON.stringify(d));await al(env,me,'balance',vu+' '+(amt>0?'+':'')+amt);}return new Response('',{status:302,headers:{Location:'/vendors'}});}
  {const vum=path.match(new RegExp('^/vendors/([^/]+)/unlimited$'));if(vum&&sa&&mt==='POST'){const vu=decodeURIComponent(vum[1]),f=await req.formData(),amount=Number(f.get('amount')||f.get('days')||30),unit=String(f.get('unit')||'days'),factor=unit==='days'?86400000:unit==='minutes'?60000:0,max=unit==='days'?365:unit==='minutes'?1440:0;if(!Number.isInteger(amount)||amount<1||amount>max)return new Response('',{status:302,headers:{Location:'/vendors?unlimited_error=duration'}});const r=await env.DZH_KV.get('dzh_vendor:'+vu);if(r){const d=JSON.parse(r),now=Date.now();d.unlimitedUntil=Math.max(now,Number(d.unlimitedUntil)||0)+amount*factor;d.unlimited=true;delete d.unlimitedExpiredAt;await env.DZH_KV.put('dzh_vendor:'+vu,JSON.stringify(d));await resumeUnlimitedOriginKeys(env,vu);await al(env,me,'unlimited_grant',vu+' '+amount+(unit==='days'?'d':'m'));}return new Response('',{status:302,headers:{Location:'/vendors?unlimited_updated=1'}});}const vurm=path.match(new RegExp('^/vendors/([^/]+)/unlimited/revoke$'));if(vurm&&sa&&mt==='POST'){const vu=decodeURIComponent(vurm[1]),r=await env.DZH_KV.get('dzh_vendor:'+vu);if(r){const d=JSON.parse(r),now=Date.now();d.unlimited=false;d.unlimitedUntil=now;d.unlimitedExpiredAt=now;await env.DZH_KV.put('dzh_vendor:'+vu,JSON.stringify(d));await pauseUnlimitedOriginKeys(env,vu,now);await al(env,me,'unlimited_revoke',vu);}return new Response('',{status:302,headers:{Location:'/vendors?unlimited_revoked=1'}});}}if(vm&&sa){const vu=vm[1],act=vm[2];if(act==='archive'&&mt!=='POST')return new Response('Method Not Allowed',{status:405});const r=await env.DZH_KV.get('dzh_vendor:'+vu);if(r){const d=JSON.parse(r);if(act==='toggle'){d.active=!d.active;await env.DZH_KV.put('dzh_vendor:'+vu,JSON.stringify(d));}if(act==='archive'){const deleted=await deleteVendorCases(env,vu,'all'),sessions=await revokeVendorWebSessions(env,vu);if(d.telegramId){const tgKey='vendor_tg:'+d.telegramId;if(await env.DZH_KV.get(tgKey)===vu)await env.DZH_KV.delete(tgKey);}await env.DZH_KV.put('vendor_archive:'+vu+':'+Date.now(),r);await env.DZH_KV.delete('dzh_vendor:'+vu);await al(env,me,'archive_vendor',vu+' keys='+deleted+' sessions='+sessions);}}return new Response('',{status:302,headers:{Location:'/vendors'}});}

  /* Bans */
  if(path==='/bans'&&sa){
    if(mt==='POST'){const f=await req.formData();const h=(f.get('hwid')||'').trim(),reason=f.get('reason')||'';if(h){await env.DZH_KV.put('ban:'+h,JSON.stringify({hwid:h,reason,created:Date.now(),by:me}));await al(env,me,'ban',h);}return new Response('',{status:302,headers:{Location:'/bans'}});}
    const bl=await env.DZH_KV.list({prefix:'ban:'});let rows='';
    for(const b of bl.keys){const r=await env.DZH_KV.get(b.name);if(!r)continue;const d=safeJson(r);if(!d)continue;rows+=`<tr><td><code>${d.hwid}</code></td><td>${d.reason||'—'}</td><td><span class="tag">${d.by||'—'}</span></td><td style="color:var(--t3)">${fmtDate(d.created)}</td><td><a href="/bans/${encodeURIComponent(d.hwid)}/remove" class="btn b-sm b-ok" onclick="return confirm('¿Desbanear?')">Desbanear</a></td></tr>`;}
    return wrap('Bans',`<div class="ph"><div><h1>🚫 Dispositivos Baneados</h1><p>Lista negra permanente</p></div></div>
<div class="card" style="max-width:600px"><div class="card-h"><span class="card-t">Banear manualmente</span></div><div class="card-b"><form method="POST" style="display:flex;gap:10px;flex-wrap:wrap;align-items:flex-end"><div class="fg" style="flex:1;min-width:180px;margin:0"><label>HWID del dispositivo</label><input name="hwid" placeholder="ID único del dispositivo" style="font-family:monospace"></div><div class="fg" style="flex:1;min-width:140px;margin:0"><label>Motivo</label><input name="reason" placeholder="Motivo del ban"></div><button class="btn b-e">🚫 Banear</button></form></div></div>
<div class="card"><div class="card-h"><span class="card-t">Baneados (${(await env.DZH_KV.list({prefix:'ban:'})).keys.length})</span></div><div class="card-b"><div class="tw">${rows?`<table><thead><tr><th>HWID</th><th>Motivo</th><th>Baneado por</th><th>Fecha</th><th></th></tr></thead><tbody>${rows}</tbody></table>`:`<div class="em"><span class="em-ic">✅</span><p class="em-t">No hay dispositivos baneados</p></div>`}</div></div></div>`,ses);
  }
  const bm=path.match(/^\/bans\/(.+)\/remove$/);if(bm&&sa){await env.DZH_KV.delete('ban:'+decodeURIComponent(bm[1]));return new Response('',{status:302,headers:{Location:'/bans'}});}

  /* Sessions */
  if(path==='/sessions'&&sa){
    const sl=await env.DZH_KV.list({prefix:'dzh_ses:'});let rows='';
    for(const sv of sl.keys){const r=await env.DZH_KV.get(sv.name);if(!r)continue;const d=JSON.parse(r);const isCurrent=sv.name==='dzh_ses:'+s;rows+=`<tr class="${isCurrent?'current':''}"><td><span class="tag">${d.user}</span>${isCurrent?' <span style="color:var(--a);font-size:10px">← tú</span>':''}</td><td><span class="bd ${d.role==='superadmin'?'ba':'bv'}">${d.role}</span></td><td style="font-size:11px;color:var(--t3)">${d.ip||'—'}</td><td style="font-size:11px;color:var(--t3);max-width:160px;overflow:hidden;text-overflow:ellipsis">${(d.ua||'—').slice(0,60)}</td><td style="color:var(--t3)">${fmtDate(d.created)}</td><td>${!isCurrent?`<a href="/sessions/${sv.name.replace('dzh_ses:','')}/kill" class="btn b-sm b-e" onclick="return confirm('¿Cerrar esta sesión?')">Cerrar</a>`:''}</td></tr>`;}
    return wrap('Sesiones',`<div class="ph"><div><h1>🔐 Sesiones Activas</h1><p>Usuarios conectados actualmente</p></div></div>
<div class="card"><div class="card-h"><span class="card-t">Sesiones activas</span></div><div class="card-b"><div class="tw">
${rows?`<table><thead><tr><th>Usuario</th><th>Rol</th><th>IP</th><th>Dispositivo</th><th>Inicio</th><th>Acción</th></tr></thead><tbody>${rows}</tbody></table>`:`<div class="em"><span class="em-ic">🔐</span><p class="em-t">No hay sesiones activas</p></div>`}
</div></div></div>`,ses);
  }
  const sm=path.match(/^\/sessions\/(.+)\/kill$/);if(sm&&sa){await env.DZH_KV.delete('dzh_ses:'+sm[1]);await al(env,me,'kill_session',sm[1]);return new Response('',{status:302,headers:{Location:'/sessions'}});}

  /* Devices */
  if(path==='/devices'&&sa){
    const kl=await env.DZH_KV.list({prefix:'dzh_key:'});let rows='';
    for(const k of kl.keys){const r=await env.DZH_KV.get(k.name);if(!r)continue;const d=safeJson(r);if(!d)continue;if(!d.activated)continue;rows+=`<tr><td><code style="font-size:11px">${d.key}</code></td><td><span class="tag">${d.vendor||'—'}</span></td><td>${d.unlimitedDevices?'Compartida':(d.device?.model||'—')}</td><td>${d.unlimitedDevices?'Ilimitados':(d.device?.ios||'—')}</td><td>${d.uses||0}</td><td style="font-size:10px;color:var(--t3);word-break:break-all;max-width:130px">${d.hwid||'—'}</td><td style="color:var(--t3)">${fmtDate(d.activated)}</td><td>${d.hwid?`<a href="/bans" class="btn b-sm b-e">🚫</a>`:''}</td></tr>`;}
    return wrap('Dispositivos',`<div class="ph"><div><h1>📱 Dispositivos</h1><p>Dispositivos que han activado una key</p></div></div>
<div class="card"><div class="card-h"><span class="card-t">Dispositivos registrados</span></div><div class="card-b"><div class="sf"><input placeholder="Buscar..." oninput="ft(this,'dtbl')"></div><div class="tw">${rows?`<table><thead><tr><th>Key</th><th>Vendedor</th><th>Modelo</th><th>iOS</th><th>Usos</th><th>HWID</th><th>Activado</th><th></th></tr></thead><tbody id="dtbl">${rows}</tbody></table>`:`<div class="em"><span class="em-ic">📱</span><p class="em-t">Sin dispositivos registrados</p></div>`}</div></div></div>`,ses);
  }
  if(path==='/ips'&&sa){
    const kl=await env.DZH_KV.list({prefix:'dzh_cip:'});let rows='';
    const arr=[];
    for(const k of kl.keys){const r=await env.DZH_KV.get(k.name);if(!r)continue;try{arr.push(JSON.parse(r));}catch(e){}}
    arr.sort((a,b)=>(b.ts||0)-(a.ts||0));
    for(const it of arr){const loc=[it.city,it.region,it.country].filter(x=>x&&x!=='?'&&x!=='').join(', ')||'—';const vb=it.vpn?` <span style="background:rgba(255,80,80,.15);color:#ff5050;padding:2px 7px;border-radius:6px;font-size:10px;font-weight:700">🛡 VPN</span>`:'';rows+=`<tr><td><code style="font-size:11px">${it.key}</code></td><td><code style="font-size:12px;color:var(--ac)">${it.ip||'—'}</code>${vb}</td><td>${loc}</td><td style="font-size:11px;color:var(--t3)">${it.org||'—'}</td><td style="color:var(--t3)">${fmtDateTime(it.ts)}</td></tr>`;}
    return wrap('IPs',`<div class="ph"><div><h1>🌐 IPs de Clientes</h1><p>Ubicación aproximada y organización técnica asociada a la IP pública · solo superadmin</p></div></div>
<div class="card"><div class="card-h"><span class="card-t">Registro de IPs</span></div><div class="card-b"><div class="sf"><input placeholder="Buscar key o IP..." oninput="ft(this,'itbl')"></div><div class="tw">${rows?`<table><thead><tr><th>Key</th><th>IP</th><th>Ubicación aproximada</th><th>Organización de red</th><th>Última conexión</th></tr></thead><tbody id="itbl">${rows}</tbody></table>`:`<div class="em"><span class="em-ic">🌐</span><p class="em-t">Sin IPs registradas aún</p></div>`}</div></div></div>`,ses);
  }

  /* Activity */
  if(path==='/activity'&&sa){
    const ll=await env.DZH_KV.list({prefix:'dzh_log:'});const logs=[];for(const l of ll.keys){const r=await env.DZH_KV.get(l.name);if(r){const x=safeJson(r);if(x)logs.push(x);}}logs.sort((a,b)=>b.ts-a.ts);
    let rows=logs.slice(0,200).map(l=>`<tr><td style="color:var(--t3);white-space:nowrap;font-size:11px">${new Date(l.ts).toLocaleString('es-MX')}</td><td><span class="tag">${l.who}</span></td><td><code>${l.action}</code></td><td style="color:var(--t3)">${l.detail||'—'}</td></tr>`).join('');
    return wrap('Actividad',`<div class="ph"><div><h1>📋 Actividad</h1><p>Últimas 200 acciones del sistema</p></div></div>
<div class="card"><div class="card-h"><span class="card-t">Registro</span></div><div class="card-b"><div class="sf"><input placeholder="Buscar en actividad..." oninput="ft(this,'ltbl')"></div><div class="tw">${rows?`<table><thead><tr><th>Fecha y hora</th><th>Usuario</th><th>Acción</th><th>Detalle</th></tr></thead><tbody id="ltbl">${rows}</tbody></table>`:`<div class="em"><span class="em-ic">📋</span><p class="em-t">Sin actividad registrada</p></div>`}</div></div></div>`,ses);
  }

  /* Maintenance */
  if(path==='/maintenance'&&sa){
    if(mt==='POST'){const f=await req.formData(),act=f.get('action');if(act==='on'){await env.DZH_KV.put('dzh_maintenance','1');await freezeStart(env);}if(act==='off'){await env.DZH_KV.delete('dzh_maintenance');await freezeEnd(env);}if(act==='vpn_on')await env.DZH_KV.put('dzh_block_vpn','1');if(act==='vpn_off')await env.DZH_KV.delete('dzh_block_vpn');if(act==='kill_on'){await env.DZH_KV.put('dzh_killswitch','1');await freezeStart(env);}if(act==='kill_off'){await env.DZH_KV.delete('dzh_killswitch');await freezeEnd(env);}await al(env,me,'dzh_maintenance',act);return new Response('',{status:302,headers:{Location:'/maintenance'}});}
    const mn=await env.DZH_KV.get('dzh_maintenance'),on=mn==='1';
    const vpnBlock=(await env.DZH_KV.get('dzh_block_vpn'))==='1';const killOn=(await env.DZH_KV.get('dzh_killswitch'))==='1';
    return wrap('Sistema',`<div class="ph"><div><h1>⚙ Sistema</h1><p>Control global del servicio</p></div></div>${killOn?`<div style="margin-bottom:18px;color:#ff5b5b;background:rgba(239,68,68,.1);font-weight:700;padding:12px 16px;border-radius:10px;border:1px solid #ff5b5b">🚨 SISTEMA APAGADO — Ningún cliente puede entrar ni inyectar</div>`:''}<div class="card" style="max-width:420px;margin-bottom:18px"><div class="card-b" style="padding:32px;text-align:center"><div style="width:72px;height:72px;border-radius:50%;background:rgba(239,68,68,.12);border:2px solid #ff5b5b;display:flex;align-items:center;justify-content:center;font-size:30px;margin:0 auto 16px">🚨</div><div style="font-size:14px;font-weight:700;color:#ff5b5b;margin-bottom:6px">${killOn?'TODO APAGADO':'BOTÓN DE PÁNICO'}</div><p style="color:var(--t3);font-size:12px;margin-bottom:22px;line-height:1.5">${killOn?'El servicio está completamente apagado.<br>Login e inyección bloqueados.':'Apaga TODO al instante: login e inyección.<br>Úsalo si hay riesgo de baneos.'}</p><form method="POST" onsubmit="return ${killOn?'true':'confirm(\'¿APAGAR TODO el servicio?\')'}"><button name="action" value="${killOn?'kill_off':'kill_on'}" class="btn ${killOn?'b-ok':'b-e'}" style="width:100%;padding:12px;font-size:13px">${killOn?'✅ Reactivar servicio':'🚨 APAGAR TODO'}</button></form></div></div>
<div class="card" style="max-width:420px">
<div class="card-b" style="padding:32px;text-align:center">
<div style="width:72px;height:72px;border-radius:50%;background:${on?'rgba(239,68,68,.12)':'rgba(34,197,94,.12)'};border:2px solid ${on?'var(--e)':'var(--ok)'};display:flex;align-items:center;justify-content:center;font-size:30px;margin:0 auto 16px">${on?'🔴':'🟢'}</div>
<div style="font-size:14px;font-weight:700;color:${on?'var(--e)':'var(--ok)'};margin-bottom:6px">${on?'MANTENIMIENTO ACTIVO':'SISTEMA OPERATIVO'}</div>
<p style="color:var(--t3);font-size:12px;margin-bottom:22px;line-height:1.5">${on?'La app está completamente bloqueada.<br>Los usuarios no pueden iniciar sesión.':'La app funciona con normalidad.<br>Todos los usuarios tienen acceso.'}</p>
<form method="POST"><button name="action" value="${on?'off':'on'}" class="btn ${on?'b-ok':'b-e'}" style="width:100%;padding:12px;font-size:13px">${on?'✅ Desactivar mantenimiento':'🔴 Activar mantenimiento'}</button></form></div></div><div class="card" style="max-width:420px;margin-top:18px"><div class="card-b" style="padding:32px;text-align:center"><div style="width:72px;height:72px;border-radius:50%;background:${vpnBlock?'rgba(239,68,68,.12)':'rgba(148,163,184,.12)'};border:2px solid ${vpnBlock?'#ff5b5b':'var(--t3)'};display:flex;align-items:center;justify-content:center;font-size:30px;margin:0 auto 16px">🛡</div><div style="font-size:14px;font-weight:700;color:${vpnBlock?'#ff5b5b':'var(--t2)'};margin-bottom:6px">${vpnBlock?'BLOQUEO DE VPN ACTIVO':'BLOQUEO DE VPN APAGADO'}</div><p style="color:var(--t3);font-size:12px;margin-bottom:22px;line-height:1.5">${vpnBlock?'Los usuarios con VPN NO pueden entrar.':'Los usuarios con VPN pueden entrar.<br>Se marcan con 🛡 en la página IPs.'}</p><form method="POST"><button name="action" value="${vpnBlock?'vpn_off':'vpn_on'}" class="btn ${vpnBlock?'b-ok':'b-w'}" style="width:100%;padding:12px;font-size:13px">${vpnBlock?'✅ Permitir VPN':'🛡 Bloquear VPN'}</button></form>
</div></div>`,ses);
  }

  if(path==='/hologramas'&&sa){return new Response('',{status:302,headers:{Location:'/avatarfiles'}});}if(false&&path==='/hologramas'&&sa){return wrap('Hologramas','<div class="ph"><div><h1>Hologramas</h1><p>Dos hologramas separados, cada uno con archivo normal y archivo MAX.</p></div></div><div class="card"><div class="card-h"><span class="card-t">Holograma Davizin</span></div><div class="card-b"><p style="color:var(--t3);margin-bottom:12px">Solo para keys autorizadas por el administrador.</p><form method="POST" action="/avatarfiles/upload-raw" enctype="application/octet-stream" onsubmit="var i=this.querySelector(&quot;input[type=file]&quot;);if(!i.files.length)return false;fetch(&quot;/avatarfiles/upload-raw?slot=&quot;+encodeURIComponent(this.querySelector(&quot;[name=slot]&quot;).value),{method:&quot;POST&quot;,body:i.files[0],credentials:&quot;same-origin&quot;}).then(function(r){if(!r.ok)return r.text().then(function(t){throw new Error(t)});return r.text()}).then(function(t){alert(t);location.reload()}).catch(function(e){alert(e.message)});return false;"><input type="hidden" name="slot" value="holograma_mio"><label>Archivo normal</label><input type="file" name="file" required onchange="var x=this.files[0],r=new FileReader();r.onload=function(){this.form.elements.file_b64.value=r.result.split(',')[1]}.bind(this);if(x)r.readAsDataURL(x)"><input type="hidden" name="file_b64" value=><button class="btn b-pr" style="margin-top:8px">Subir archivo propio</button></form><form method="POST" action="/avatarfiles/upload-raw" enctype="application/octet-stream" onsubmit="var i=this.querySelector(&quot;input[type=file]&quot;);if(!i.files.length)return false;fetch(&quot;/avatarfiles/upload-raw?slot=&quot;+encodeURIComponent(this.querySelector(&quot;[name=slot]&quot;).value),{method:&quot;POST&quot;,body:i.files[0],credentials:&quot;same-origin&quot;}).then(function(r){if(!r.ok)return r.text().then(function(t){throw new Error(t)});return r.text()}).then(function(t){alert(t);location.reload()}).catch(function(e){alert(e.message)});return false;" style="margin-top:14px"><input type="hidden" name="slot" value="holograma_mio_ff"><label>Archivo Free Fire MAX</label><input type="file" name="file" required onchange="var x=this.files[0],r=new FileReader();r.onload=function(){this.form.elements.file_b64.value=r.result.split(',')[1]}.bind(this);if(x)r.readAsDataURL(x)"><input type="hidden" name="file_b64" value=><button class="btn b-pr" style="margin-top:8px">Subir archivo MAX</button></form></div></div><div class="card"><div class="card-h"><span class="card-t">Holograma Bordes</span></div><div class="card-b"><p style="color:var(--t3);margin-bottom:12px">Solo para keys con acceso de revendedor.</p><form method="POST" action="/avatarfiles/upload-raw" enctype="application/octet-stream" onsubmit="var i=this.querySelector(&quot;input[type=file]&quot;);if(!i.files.length)return false;fetch(&quot;/avatarfiles/upload-raw?slot=&quot;+encodeURIComponent(this.querySelector(&quot;[name=slot]&quot;).value),{method:&quot;POST&quot;,body:i.files[0],credentials:&quot;same-origin&quot;}).then(function(r){if(!r.ok)return r.text().then(function(t){throw new Error(t)});return r.text()}).then(function(t){alert(t);location.reload()}).catch(function(e){alert(e.message)});return false;"><input type="hidden" name="slot" value="holograma_revendedor"><label>Archivo normal</label><input type="file" name="file" required onchange="var x=this.files[0],r=new FileReader();r.onload=function(){this.form.elements.file_b64.value=r.result.split(',')[1]}.bind(this);if(x)r.readAsDataURL(x)"><input type="hidden" name="file_b64" value=><button class="btn b-ok" style="margin-top:8px">Subir archivo de revendedores</button></form><form method="POST" action="/avatarfiles/upload-raw" enctype="application/octet-stream" onsubmit="var i=this.querySelector(&quot;input[type=file]&quot;);if(!i.files.length)return false;fetch(&quot;/avatarfiles/upload-raw?slot=&quot;+encodeURIComponent(this.querySelector(&quot;[name=slot]&quot;).value),{method:&quot;POST&quot;,body:i.files[0],credentials:&quot;same-origin&quot;}).then(function(r){if(!r.ok)return r.text().then(function(t){throw new Error(t)});return r.text()}).then(function(t){alert(t);location.reload()}).catch(function(e){alert(e.message)});return false;" style="margin-top:14px"><input type="hidden" name="slot" value="holograma_revendedor_ff"><label>Archivo Free Fire MAX</label><input type="file" name="file" required onchange="var x=this.files[0],r=new FileReader();r.onload=function(){this.form.elements.file_b64.value=r.result.split(',')[1]}.bind(this);if(x)r.readAsDataURL(x)"><input type="hidden" name="file_b64" value=><button class="btn b-ok" style="margin-top:8px">Subir archivo MAX</button></form></div></div>',ses);}  const fd=path.match(/^\/avatarfiles\/download\/([^/]+)$/);
  if(fd&&sa){
    const slot=decodeURIComponent(fd[1]);
    if(!(await slotIsAllowed(env,slot)))return new Response('Slot inválido',{status:404});
    const b64=await env.DZH_KV.get('dzh_cache:'+slot);if(!b64)return new Response('Archivo no encontrado',{status:404});
    const raw=atob(b64),out=new Uint8Array(raw.length);for(let i=0;i<raw.length;i++)out[i]=raw.charCodeAt(i);
    return new Response(out,{headers:{'Content-Type':'application/octet-stream','Content-Length':String(out.byteLength),'Content-Disposition' : 'attachment; filename="'+slot+'"','Cache-Control':'no-store'}});
  }
  if(path==='/avatarfiles/upload-raw'&&sa&&mt==='POST'){try{const slot=(new URL(req.url)).searchParams.get('slot')||'';if(!/^[A-Za-z0-9_-]{1,32}(?:_ff)?$/.test(slot)||!(await slotIsAllowed(env,slot)))return new Response('Slot inválido',{status:400});const buf=await req.arrayBuffer();if(!buf.byteLength)return new Response('Cuerpo vacío',{status:400});if(buf.byteLength>20000000)return new Response('Archivo muy grande',{status:413});const bytes=new Uint8Array(buf);let binary='';for(let i=0;i<bytes.length;i+=0x8000)binary+=String.fromCharCode(...bytes.subarray(i,i+0x8000));await env.DZH_KV.put('dzh_cache:'+slot,btoa(binary));const meta={size:buf.byteLength,at:Date.now(),by:me,format:bytes[0]===0x55&&bytes[1]===0x6e?'UnityFS':'binary'};await env.DZH_KV.put('dzh_cache_meta:'+slot,JSON.stringify(meta));if(!await env.DZH_KV.get('dzh_cache_meta:'+slot))return new Response('KV no confirmó el guardado',{status:500});try{await al(env,me,'upload_cache',slot+' ('+buf.byteLength+' bytes)');}catch(e){}return new Response('OK '+slot+' '+buf.byteLength+' bytes',{status:200,headers:{'Content-Type':'text/plain','Cache-Control':'no-store'}});}catch(e){return new Response('Error de subida: '+(e?.message||'desconocido'),{status:500});}}
  if(path==='/avatarfiles/upload'&&sa&&mt==='POST'){try{const f=await req.formData();const slot=(f.get('slot')||'').toString().trim();const fileB64=(f.get('file_b64')||'').toString().trim();const file=f.get('file')||f.get('archivo')||f.get('upload')||Array.from(f.values()).find(v=>v&&typeof v.arrayBuffer==='function');if(!/^holograma_(?:mio|revendedor)(?:_ff)?$/.test(slot)&&!(await slotIsAllowed(env,slot)))return new Response('Slot inválido',{status:400});if(!fileB64&&!file)return new Response('Archivo faltante: selecciona un archivo',{status:400});let buf;if(fileB64){const bin=atob(fileB64),out=new Uint8Array(bin.length);for(let i=0;i<bin.length;i++)out[i]=bin.charCodeAt(i);buf=out.buffer;}else{if(typeof file==='string'||typeof file.arrayBuffer!=='function')return new Response('Archivo faltante: selecciona un archivo',{status:400});buf=await file.arrayBuffer();}if(buf.byteLength>20000000)return new Response('Archivo muy grande',{status:413});const bytes=new Uint8Array(buf);let binary='';for(let i=0;i<bytes.length;i+=0x8000)binary+=String.fromCharCode(...bytes.subarray(i,i+0x8000));const b64=btoa(binary);await env.DZH_KV.put('dzh_cache:'+slot,b64);const meta={size:buf.byteLength,at:Date.now(),by:me,format:bytes[0]===0x55&&bytes[1]===0x6e?'UnityFS':'binary'};await env.DZH_KV.put('dzh_cache_meta:'+slot,JSON.stringify(meta));const check=await env.DZH_KV.get('dzh_cache_meta:'+slot);if(!check)return new Response('KV no confirmó el guardado',{status:500});try{await al(env,me,'upload_cache',slot+' ('+buf.byteLength+' bytes)');}catch(e){}return new Response('',{status:303,headers:{Location:'/avatarfiles?uploaded='+encodeURIComponent(slot)}});}catch(e){return new Response('Error de subida: '+(e?.message||'desconocido'),{status:500});}}
  if(path==='/avatarfiles'&&sa){
    if(mt==='POST'){
      const f=await req.formData();const action=(f.get('action')||'').toString().trim().toLowerCase();
      const submittedClearId=(f.get('clear_files')||'').toString().trim().toLowerCase();
      if(action==='clear_files'||submittedClearId){
        const id=(submittedClearId||f.get('mode_id')||'').toString().trim().toLowerCase();

        if(!/^[a-z0-9_-]{1,32}$/.test(id))return cachePg(env,me,'ID de modo inválido.');

        const current=await modeDefinitions(env),index=current.findIndex(m=>m.id===id);
        if(index<0)return cachePg(env,me,'Ese modo no existe.');
        for(const slot of [id,id+'_ff']){await env.DZH_KV.delete('dzh_cache:'+slot);await env.DZH_KV.delete('dzh_cache_meta:'+slot);}
        try{await al(env,me,'clear_app_files',id);}catch(e){}
        return cachePg(env,me,'✓ Archivos quitados de '+id+'; el modo permanece creado.',current);
      }
      // Fallback: si el navegador omite el hidden action, la presencia de estos campos identifica el formulario de alta.
      if(action==='delete_mode'||f.has('delete_mode')){
        const id=(f.get('delete_mode')||f.get('mode_id')||'').toString().trim().toLowerCase();

        if(!/^[a-z0-9_-]{1,32}$/.test(id))return cachePg(env,me,'ID de modo inválido.');

        const current=await modeDefinitions(env),index=current.findIndex(m=>m.id===id);
        if(index<0)return cachePg(env,me,'Ese modo no existe.');
        const kl=await env.DZH_KV.list({prefix:'dzh_modeused:'});
        for(const k of kl.keys){if(k.name.endsWith(':'+id))await env.DZH_KV.delete(k.name);}
        for(const slot of [id,id+'_ff']){await env.DZH_KV.delete('dzh_cache:'+slot);await env.DZH_KV.delete('dzh_cache_meta:'+slot);}
        current.splice(index,1);
        await env.DZH_KV.put('dzh_app_modes',JSON.stringify(current));
        try{await al(env,me,'delete_app_mode',id);}catch(e){}
        return cachePg(env,me,'✓ Modo eliminado: '+id,current);
      }

      if(action==='create_mode'||(action===''&&f.has('new_id')&&f.has('new_label'))){
        const requestedId=(f.get('new_id')||'').toString().trim();
        const label=(f.get('new_label')||'').toString().trim().slice(0,40);
        const tier=f.get('new_tier')==='pro'?'pro':'basic';
        const routeMode=f.get('new_route_mode')==='custom'?'custom':'avatar';
        const isBundle=f.get('new_bundle')==='1';
        const enteredMax=routeMode==='custom'?(f.get('new_path_max')||'').toString().trim():'';
        const enteredNormal=routeMode==='custom'?(f.get('new_path_normal')||'').toString().trim():'';
        // Una sola ruta se reutiliza para ambos juegos; también se permiten dos rutas diferentes.
        const sharedPath=enteredMax||enteredNormal;
        const pathMax=routeMode==='custom'?(enteredMax||sharedPath||null):null;
        const pathNormal=routeMode==='custom'?(enteredNormal||sharedPath||null):null;
        const safeLabel=/^[\p{L}\p{N} %_().+\-]{1,40}$/u;
        if(!safeLabel.test(label))return cachePg(env,me,'Nombre visible inválido.');
        const current=await modeDefinitions(env);
        const id=(requestedId||label).normalize('NFD').replace(/[\u0300-\u036f]/g,'').toLowerCase().replace(/[^a-z0-9_-]+/g,'-').replace(/^-+|-+$/g,'').replace(/_ff$/,'').slice(0,32);
        if(!id)return cachePg(env,me,'Escribe un nombre visible válido para generar el ID interno.');
        if(current.some(m=>m.id===id))return cachePg(env,me,'Ya existe un modo con ese ID. Usa otro ID para no crear duplicados.');
        if(routeMode==='custom'&&(!pathMax||!pathNormal||!safeModePath(pathMax)||!safeModePath(pathNormal)))return cachePg(env,me,'La ruta debe comenzar por Documents/ y no contener ..; puedes usar una sola ruta para ambos juegos.');
        current.push({id,label,enabled:true,enabledMax:true,enabledNormal:true,accessTier:tier,oneTime:id==='holograma',consumed:false,bundle:isBundle,pathMax,pathNormal,noticeTitle:'ℹ️ '+label,noticeBody:'Información del modo. Revisa su comportamiento antes de usarlo.',noticeLevel:'yellow',noticeEnabled:true});
        try{
          await env.DZH_KV.put('dzh_app_modes',JSON.stringify(current));
          try{await al(env,me,'create_app_mode',id);}catch(e){}
        }catch(e){
          return cachePg(env,me,'No se pudo guardar el modo en KV: '+(e?.message||'error de almacenamiento'));
        }
        return cachePg(env,me,'✓ Modo creado: '+label+' (MAX y normal)',current);
      }
      if(action==='move_mode'){
        const parts=(f.get('move_mode')||'').toString().split('|');
        const id=(parts[0]||'').trim().toLowerCase(), direction=parts[1]==='down'?'down':'up';
        const current=await modeDefinitions(env),index=current.findIndex(m=>m.id===id);
        if(index<0)return cachePg(env,me,'Ese modo no existe.');
        const target=direction==='down'?index+1:index-1;
        if(target>=0&&target<current.length){const t=current[index];current[index]=current[target];current[target]=t;await env.DZH_KV.put('dzh_app_modes',JSON.stringify(current));try{await al(env,me,'reorder_app_mode',id+' '+direction);}catch(e){}}
        return cachePg(env,me,'✓ Orden actualizado',current);
      }
      if(action==='save_modes'){
        const current=await modeDefinitions(env);
        const modes=current.map(m=>{const rawMax=(f.get('pathMax_'+m.id)||'').toString().trim();const rawNormal=(f.get('pathNormal_'+m.id)||'').toString().trim();const enabledMax=f.getAll('enabledMax_'+m.id).includes('1');const enabledNormal=f.getAll('enabledNormal_'+m.id).includes('1');return {id:m.id,label:(f.get('label_'+m.id)||m.label||'').toString().trim().slice(0,40),enabled:enabledMax&&enabledNormal,enabledMax,enabledNormal,accessTier:f.get('accessTier_'+m.id)==='pro'?'pro':'basic',oneTime:m.oneTime===true,consumed:false,bundle:f.getAll('bundle_'+m.id).includes('1'),pathMax:rawMax?(safeModePath(rawMax)?rawMax:null):(m.pathMax||null),pathNormal:rawNormal?(safeModePath(rawNormal)?rawNormal:null):(m.pathNormal||null),noticeTitle:(f.get('noticeTitle_'+m.id)||m.noticeTitle||'').toString().trim().slice(0,60),noticeBody:(f.get('noticeBody_'+m.id)||m.noticeBody||'').toString().trim().slice(0,240),noticeLevel:['green','yellow','red'].includes(f.get('noticeLevel_'+m.id))?f.get('noticeLevel_'+m.id):(m.noticeLevel||'yellow'),noticeEnabled:f.getAll('noticeEnabled_'+m.id).includes('1')};});
        const safeLabel=/^[\p{L}\p{N} %_().+\-]{1,40}$/u;
        if(modes.some(m=>!safeLabel.test(m.label)||!m.noticeTitle||!m.noticeBody||(m.pathMax&&!safeModePath(m.pathMax))||(m.pathNormal&&!safeModePath(m.pathNormal))))return cachePg(env,me,'Completa correctamente los datos del modo.');
        await env.DZH_KV.put('dzh_app_modes',JSON.stringify(modes));
        await al(env,me,'save_app_modes','three_modes');
        return cachePg(env,me,'✓ Modos guardados');
      }
      if(action==='save_destinations'){
        const normal=(f.get('freeFire')||'').trim(),max=(f.get('freeFireMax')||'').trim();
        const safe=v=>/^assetindexer\.[A-Za-z0-9._~\-=]{1,170}$/.test(v);
        if(!safe(normal)||!safe(max))return cachePg(env,me,'Nombre inválido: debe comenzar por assetindexer.');
        await env.DZH_KV.put('dzh_app_config',JSON.stringify({version:1,destinations:{freeFire:normal,freeFireMax:max}}));
        await al(env,me,'save_app_config','destinations');
        return cachePg(env,me,'✓ Rutas guardadas');
      }
      const slot=(f.get('slot')||'').trim();const file=f.get('file');
      if(!(await slotIsAllowed(env,slot))&&!/^holograma_(?:mio|revendedor)(?:_ff)?$/.test(slot))return cachePg(env,me,'Slot inválido');
      if(!file||typeof file==='string')return cachePg(env,me,'Selecciona un archivo');
      const buf=await file.arrayBuffer();
      if(buf.byteLength>20000000)return cachePg(env,me,'Archivo muy grande (máx 20 MB)');
      const bytes=new Uint8Array(buf);let binary='';
      for(let i=0;i<bytes.length;i+=0x8000)binary+=String.fromCharCode(...bytes.subarray(i,i+0x8000));
      const b64=btoa(binary);
      await env.DZH_KV.put('dzh_cache:'+slot,b64);
      const uploadMeta={size:buf.byteLength,at:Date.now(),by:me,format:bytes[0]===0x55&&bytes[1]===0x6e?'UnityFS':'binary'};
      await env.DZH_KV.put('dzh_cache_meta:'+slot,JSON.stringify(uploadMeta));
      const persisted=await env.DZH_KV.get('dzh_cache_meta:'+slot);
      if(!persisted)return cachePg(env,me,'No se pudo confirmar la persistencia del archivo en KV.');
      await al(env,me,'upload_cache',slot+' ('+buf.byteLength+' bytes)');
      return cachePg(env,me,'✓ '+slot+' actualizado ('+buf.byteLength+' bytes)');
    }
    return cachePg(env,me,'');
  }
  if(path==='/tiempo'&&sa){
    if(mt==='POST'){
      const f=await req.formData();const grp=(f.get('grupo')||'').trim();const dias=parseInt(f.get('dias')||'0',10)||0;const horas=parseInt(f.get('horas')||'0',10)||0;const deltaSec=(dias*86400)+(horas*3600);
      if(Math.abs(dias)>3650||horas<0||horas>23)return new Response('',{status:302,headers:{Location:'/tiempo'}});
      if(deltaSec!==0){const kl=await env.DZH_KV.list({prefix:'dzh_key:'});let n=0;
        for(const k of kl.keys){const r=await env.DZH_KV.get(k.name);if(!r)continue;const d=safeJson(r);if(!d)continue;if(!d.activated)continue;const rem=secondsLeft(d);if(rem<=0)continue;const days=rem/86400;let match=false;
          if(grp==='all')match=true;else if(grp==='g15'&&days>15)match=true;else if(grp==='g7_15'&&days>=7&&days<=15)match=true;else if(grp==='g1_7'&&days>=1&&days<7)match=true;
          if(match){d.activated=d.activated+deltaSec*1000;await env.DZH_KV.put(k.name,JSON.stringify(d));n++;}}
        await al(env,me,deltaSec>0?'add_time':'remove_time',grp+' '+(deltaSec>0?'+':'')+dias+'d'+horas+'h a '+n+' keys');
        return new Response('',{status:302,headers:{Location:'/tiempo?ok='+n}});}
      return new Response('',{status:302,headers:{Location:'/tiempo'}});}
    const kl=await env.DZH_KV.list({prefix:'dzh_key:'});let g15=0,g7=0,g1=0;
    for(const k of kl.keys){const r=await env.DZH_KV.get(k.name);if(!r)continue;const d=safeJson(r);if(!d)continue;if(!d.activated)continue;const rem=secondsLeft(d);if(rem<=0)continue;const days=rem/86400;if(days>15)g15++;else if(days>=7)g7++;else if(days>=1)g1++;}
    const okMsg=url.searchParams.get('ok'),resultAction=url.searchParams.get('action');
    const card=(title,sub,grp,count,color)=>`<div class="card" style="max-width:520px;margin-bottom:16px;border-left:3px solid ${color}"><div class="card-b" style="padding:22px"><div style="display:flex;justify-content:space-between;align-items:center;margin-bottom:14px"><div><div style="font:700 15px/1.2 'Space Grotesk',sans-serif;color:${color}">${title}</div><div style="font-size:11px;color:var(--t3);margin-top:4px">${sub}</div></div><div style="font:700 26px/1 'Space Grotesk',sans-serif;color:var(--t)">${count}<span style="font-size:11px;color:var(--t3);font-weight:400"> keys</span></div></div><form method="POST" style="display:flex;gap:8px;align-items:center;flex-wrap:wrap"><input type="hidden" name="grupo" value="${grp}"><input name="dias" type="number" min="-3650" max="3650" placeholder="días" style="width:80px;padding:8px;font-size:13px;background:var(--bg2);border:1px solid var(--b1);border-radius:8px;color:var(--t)"><input name="horas" type="number" min="0" max="23" placeholder="horas" style="width:80px;padding:8px;font-size:13px;background:var(--bg2);border:1px solid var(--b1);border-radius:8px;color:var(--t)"><button class="btn b-ok b-sm" onclick="return confirm('¿Aplicar el cambio de tiempo a las ${count} keys de este grupo? Los días negativos restan tiempo.')">➕ Aplicar</button></form></div></div>`;
    return wrap('Tiempo',`<div class="ph"><div><h1>⏳ Agregar Tiempo</h1><p>Regala días u horas a las keys activas · solo superadmin</p></div></div>
${okMsg?`<div class="mbar" style="margin-bottom:18px;border:1px solid var(--ok);color:var(--ok);background:rgba(34,197,94,.1);padding:12px 16px;border-radius:10px">✅ Tiempo agregado a ${okMsg} keys</div>`:''}
<div class="card" style="max-width:520px;margin-bottom:22px;border:1px solid var(--a)"><div class="card-b" style="padding:22px"><div style="font:700 15px/1.2 'Space Grotesk',sans-serif;color:var(--a);margin-bottom:6px">🌐 TODAS las keys activas</div><div style="font-size:11px;color:var(--t3);margin-bottom:14px">Agrega el mismo tiempo a todas sin importar el grupo</div><form method="POST" style="display:flex;gap:8px;align-items:center;flex-wrap:wrap"><input type="hidden" name="grupo" value="all"><input name="dias" type="number" min="-3650" max="3650" placeholder="días" style="width:80px;padding:8px;font-size:13px;background:var(--bg2);border:1px solid var(--b1);border-radius:8px;color:var(--t)"><input name="horas" type="number" min="0" max="23" placeholder="horas" style="width:80px;padding:8px;font-size:13px;background:var(--bg2);border:1px solid var(--b1);border-radius:8px;color:var(--t)"><button class="btn b-pr" onclick="return confirm('¿Agregar tiempo a TODAS las keys activas?')">➕ Agregar a todas</button></form></div></div>
<div style="font-size:11px;color:var(--t3);text-transform:uppercase;letter-spacing:.08em;margin-bottom:12px">Por grupos</div>
${card('Más de 15 días','Keys con bastante tiempo','g15',g15,'#58d6e8')}
${card('Entre 7 y 15 días','Keys a media vida','g7_15',g7,'#f5b301')}
${card('De 1 a 7 días','Keys por vencer pronto','g1_7',g1,'#ff8c42')}
`,ses);
  }

if(path==='/usage'&&sa){
  const period=['today','week','all'].includes(url.searchParams.get('period'))?url.searchParams.get('period'):'today';
  const now=new Date(),parts=new Intl.DateTimeFormat('en-CA',{timeZone:'America/Mexico_City',year:'numeric',month:'2-digit',day:'2-digit'}).formatToParts(now),get=t=>parts.find(x=>x.type===t)?.value||'';
  const today=get('year')+'-'+get('month')+'-'+get('day'),[yy,mm,dd]=today.split('-').map(Number),ref=new Date(Date.UTC(yy,mm-1,dd,12)),offset=(ref.getUTCDay()+6)%7;ref.setUTCDate(ref.getUTCDate()-offset);const weekStart=ref.toISOString().slice(0,10);
  const modes=await modeDefinitions(env),stats=new Map();for(const m of modes)stats.set(m.id,{id:m.id,label:m.label,max:0,normal:0,enabledMax:m.enabledMax!==false,enabledNormal:m.enabledNormal!==false,total:0});
  let dataError=false,dbRows=[],startDate=today;
  try{let sql='SELECT mode_id, game, SUM(requests) AS requests FROM mode_usage_daily WHERE usage_day <= ?';let params=[today];if(period==='today'){sql='SELECT mode_id, game, SUM(requests) AS requests FROM mode_usage_daily WHERE usage_day = ?';params=[today];}else if(period==='week'){sql='SELECT mode_id, game, SUM(requests) AS requests FROM mode_usage_daily WHERE usage_day BETWEEN ? AND ?';params=[weekStart,today];}sql+=' GROUP BY mode_id, game ORDER BY requests DESC';const result=await env.DZ_USAGE_DB.prepare(sql).bind(...params).run();dbRows=result.results||[];const meta=await env.DZ_USAGE_DB.prepare('SELECT value FROM usage_meta WHERE key = ?').bind('started_on').run();startDate=meta.results?.[0]?.value||today;}catch(_){dataError=true;}
  let total=0;for(const r of dbRows){const id=String(r.mode_id||'');if(!id)continue;const n=Math.max(0,Number(r.requests)||0),game=String(r.game||'');let x=stats.get(id);if(!x){x={id,label:id,max:0,normal:0,enabledMax:false,enabledNormal:false,total:0};stats.set(id,x);}if(game==='ffnormal')x.normal+=n;else if(game==='ffmax')x.max+=n;x.total=x.max+x.normal;total+=n;}
  const arr=[...stats.values()].sort((a,b)=>b.total-a.total||a.label.localeCompare(b.label,'es')),enabled=arr.filter(x=>x.enabledMax||x.enabledNormal),noActivity=enabled.filter(x=>x.total===0).length,top=arr.find(x=>x.total>0);
  const esc=v=>String(v).replaceAll('&','&amp;').replaceAll('<','&lt;').replaceAll('>','&gt;').replaceAll('"','&quot;').replaceAll("'",'&#39;'),pct=x=>total?Math.round(x*100/total):0;
  const rows=arr.map(x=>{const share=pct(x.total),status=x.enabledMax&&x.enabledNormal?'Activo en ambos':x.enabledMax?'Solo FF MAX':x.enabledNormal?'Solo FF Normal':'Ya no disponible';return '<tr><td><strong>'+esc(x.label)+'</strong><div style="font-size:10px;color:var(--t3);margin-top:3px">'+status+'</div></td><td>'+x.max+'</td><td>'+x.normal+'</td><td><strong>'+x.total+'</strong></td><td style="min-width:130px"><div style="display:flex;align-items:center;gap:8px"><div style="height:7px;flex:1;border-radius:9px;background:rgba(128,148,165,.16);overflow:hidden"><i style="display:block;height:7px;width:'+share+'%;background:linear-gradient(90deg,#27c7d6,#7388ff)"></i></div><span style="font-size:10px;color:var(--t3)">'+share+'%</span></div></td></tr>';}).join('');
  const weekDates=weekStart+' — '+today,label=period==='today'?'Hoy':period==='week'?'Esta semana':'Histórico',periodText=period==='today'?'Hoy · hora de Ciudad de México':period==='week'?'Semana actual ('+weekDates+') · hora de Ciudad de México':'Desde '+startDate+' · hora de Ciudad de México';
  const tab=(value,text)=>'<a href="/usage?period='+value+'" class="btn '+(period===value?'b-pr':'b-gh')+'"'+(period===value?' aria-current="page"':'')+'>'+text+'</a>';
  const warning=dataError?'<div class="al al-w" style="margin-bottom:14px">No se pudieron consultar las estadísticas ahora. Esto no interrumpe la entrega de recursos.</div>':'';
  const body='<div class="ph"><div><h1>▥ Uso de funciones</h1><p>Modos más usados e inyecciones registradas</p></div><div class="acts"><span class="tag">'+new Intl.DateTimeFormat('es-MX',{timeZone:'America/Mexico_City',hour:'2-digit',minute:'2-digit'}).format(now)+' CDMX</span><a class="btn b-gh" href="/usage?period='+period+'">Actualizar</a></div></div><div class="acts" style="margin:0 0 18px;gap:8px">'+tab('today','Hoy')+tab('week','Esta semana')+tab('all','Histórico')+'<span style="font-size:11px;color:var(--t3);align-self:center;margin-left:6px">'+periodText+'</span></div>'+warning+
  '<div class="sg"><div class="stat"><div class="stat-n">'+(dataError?'—':total)+'</div><div class="stat-l">Entregas autorizadas</div><div class="stat-sub">'+label+' · recursos solicitados</div></div><div class="stat"><div class="stat-n" style="font-size:20px">'+(dataError?'No disponible':esc(top?top.label:'Sin registros'))+'</div><div class="stat-l">Modo con más uso</div><div class="stat-sub">'+(top?top.total+' entregas en este periodo':'Todavía no hay actividad de este periodo')+'</div></div><div class="stat"><div class="stat-n">'+(dataError?'—':noActivity)+'</div><div class="stat-l">Modos activos sin uso</div><div class="stat-sub">Sin entregas registradas en '+label.toLowerCase()+'</div></div></div>'+
  '<div class="card" style="margin-top:18px"><div class="card-h"><span class="card-t">Ranking por modo y juego</span><span style="font-size:11px;color:var(--t3)">Participación del total</span></div><div class="card-b"><div class="tw">'+(rows?'<table><thead><tr><th>Opción</th><th>FF MAX</th><th>FF Normal</th><th>Total</th><th>Participación</th></tr></thead><tbody>'+rows+'</tbody></table>':'<div class="em"><span class="em-ic">▥</span><p class="em-t">'+(dataError?'Estadísticas temporalmente no disponibles':'Sin entregas registradas')+'</p><p class="em-s">'+(dataError?'Inténtalo más tarde; los recursos del cliente siguen funcionando.':'Los conteos históricos empiezan el '+startDate+'. No hay datos anteriores que se puedan recuperar.')+'</p></div>')+'</div></div></div><div class="al al-s" style="margin-top:14px">Se guarda únicamente un contador diario agregado por modo y juego; no se conservan keys, IP ni identificadores de clientes. Cuenta entregas autorizadas del recurso, no confirma que la inyección haya terminado correctamente. Histórico disponible desde '+startDate+'. Si falla el contador o se alcanza la cuota de D1, no se interrumpen las descargas pero puede omitirse ese conteo.</div>';
  return wrap('Uso',body,ses);
}

if(path.startsWith('/bundlefiles/')&&sa){
  const bfRest=path.slice('/bundlefiles/'.length);
  const bfSlash=bfRest.indexOf('/');
  const bfModeId=decodeURIComponent(bfSlash>0?bfRest.slice(0,bfSlash):bfRest).toLowerCase();
  const bfAction=bfSlash>0?bfRest.slice(bfSlash+1):'';
  if(!/^[a-z0-9_-]{1,32}$/.test(bfModeId))return wrap('Bundle Files','<div class="al al-w">ID de modo inválido</div>',{role:'superadmin',user:me});
  const bfModes=await modeDefinitions(env);
  const bfMode=bfModes.find(m=>m.id===bfModeId);
  if(!bfMode)return wrap('Bundle Files','<div class="al al-w">Modo no encontrado: '+esc(bfModeId)+'</div>',{role:'superadmin',user:me});

  if(bfAction==='upload'&&mt==='POST'){
    const isBatch=req.headers.get('X-Bundle-Batch')==='1';
    try{
      const bf=await req.formData();
      const file=bf.get('file')||bf.get('archivo')||bf.get('upload')||Array.from(bf.values()).find(v=>v&&typeof v.arrayBuffer==='function');
      const fileName=(bf.get('filename')||(file&&file.name)||'').toString().trim();
      if(!fileName||!/^[A-Za-z0-9._~\-=]{1,200}$/.test(fileName)){const em='Nombre inválido: '+fileName;if(isBatch)return Response.json({ok:false,error:em},{status:400});return bundleFilesPg(env,me,bfModeId,bfMode,em);}
      if(!file||typeof file==='string'||typeof file.arrayBuffer!=='function'){const em='Sin archivo.';if(isBatch)return Response.json({ok:false,error:em},{status:400});return bundleFilesPg(env,me,bfModeId,bfMode,em);}
      const buf=await file.arrayBuffer();
      if(!buf.byteLength){const em='Archivo vacío.';if(isBatch)return Response.json({ok:false,error:em},{status:400});return bundleFilesPg(env,me,bfModeId,bfMode,em);}
      if(buf.byteLength>15000000){const em='Muy grande (máx 15 MB).';if(isBatch)return Response.json({ok:false,error:em},{status:400});return bundleFilesPg(env,me,bfModeId,bfMode,em);}
      const r2Key='bundle/'+bfModeId+'/'+fileName;
      await env.DZH_FILES.put(r2Key,buf,{httpMetadata:{contentType:'application/octet-stream'},customMetadata:{uploadedBy:me,uploadedAt:String(Date.now()),size:String(buf.byteLength)}});
      try{await al(env,me,'upload_bundle_file',bfModeId+'/'+fileName+' ('+buf.byteLength+' bytes)');}catch(e){}
      if(isBatch)return Response.json({ok:true,name:fileName,size:buf.byteLength});
      return bundleFilesPg(env,me,bfModeId,bfMode,'✓ Archivo subido: '+fileName+' ('+buf.byteLength+' bytes)');
    }catch(e){if(isBatch)return Response.json({ok:false,error:e?.message||'desconocido'},{status:500});return bundleFilesPg(env,me,bfModeId,bfMode,'Error al subir: '+(e?.message||'desconocido'));}
  }

  if(bfAction==='delete'&&mt==='POST'){
    try{
      const bf=await req.formData();
      const fileName=(bf.get('filename')||'').toString().trim();
      if(!fileName)return bundleFilesPg(env,me,bfModeId,bfMode,'Nombre de archivo faltante.');
      const r2Key='bundle/'+bfModeId+'/'+fileName;
      await env.DZH_FILES.delete(r2Key);
      try{await al(env,me,'delete_bundle_file',bfModeId+'/'+fileName);}catch(e){}
      return bundleFilesPg(env,me,bfModeId,bfMode,'✓ Archivo eliminado: '+fileName);
    }catch(e){return bundleFilesPg(env,me,bfModeId,bfMode,'Error al eliminar: '+(e?.message||'desconocido'));}
  }

  return bundleFilesPg(env,me,bfModeId,bfMode,'');
}

if(path==='/live'&&sa){
    const kl=await env.DZH_KV.list({prefix:'live:'});const evs=[];
    for(const k of kl.keys){const r=await env.DZH_KV.get(k.name);if(!r)continue;try{evs.push(JSON.parse(r));}catch(e){}}
    evs.sort((a,b)=>(b.ts||0)-(a.ts||0));
    const liveModes=await modeDefinitions(env);
    const modeName=(sl)=>{const base=sl.endsWith('_ff')?sl.slice(0,-3):sl;return liveModes.find(m=>m.id===base)?.label||base;};
    const gameName=(sl)=>sl.endsWith('_ff')?'FF Normal':'FF MAX';
    const ago=(ts)=>{const s=Math.floor((Date.now()-ts)/1000);if(s<60)return 'hace '+s+'s';return 'hace '+Math.floor(s/60)+'m';};
    let rows='';
    for(const e of evs){if(!e||typeof e.slot!=='string')continue;const gc=e.slot.endsWith('_ff')?'#f5b301':'#58d6e8';rows+=`<tr><td><span style="display:inline-block;width:8px;height:8px;border-radius:50%;background:#22c55e;box-shadow:0 0 8px #22c55e;margin-right:6px"></span><code style="font-size:11px">${e.key}</code></td><td><span style="color:${gc};font-weight:600;font-size:12px">${gameName(e.slot)}</span></td><td>${modeName(e.slot)}${e.poison?' <span style="color:#ff5050">☠</span>':''}</td><td style="font-size:11px;color:var(--t3)">${e.loc||'?'}</td><td><code style="font-size:11px;color:var(--ac)">${e.ip||'?'}</code></td><td style="font-size:11px;color:var(--t3)">${ago(e.ts)}</td></tr>`;}
    const body=`<div class="ph"><div><h1>◉ En Vivo</h1><p>Eventos recientes · últimos 30 min · actualización manual</p></div><div class="acts"><span class="tag" style="color:#22c55e">● ${evs.length} eventos recientes</span></div></div>
<div class="card"><div class="card-b"><div class="tw">${evs.length?`<table><thead><tr><th>Key</th><th>Juego</th><th>Modo</th><th>Ubicación aproximada</th><th>IP</th><th>Cuándo</th></tr></thead><tbody>${rows}</tbody></table>`:`<div class="em"><span class="em-ic">◉</span><p class="em-t">Sin eventos en los últimos 30 minutos</p><p style="font-size:11px;color:var(--t3);margin-top:6px">Los eventos se conservan durante 30 minutos desde que ocurren</p></div>`}</div></div></div>
<div style="margin-top:14px;text-align:right"><a class="btn b-gh b-sm" href="/live">↻ Actualizar</a></div>`;
    return wrap('Live',body,ses);
  }
    if(path==='/anuncio'&&sa&&url.searchParams.get('stable')==='1'){if(mt==='POST'){const f=await req.formData(),txt=String(f.get('texto')||'').slice(0,300);if(txt)await env.DZH_KV.put('global_notice',txt);else await env.DZH_KV.delete('global_notice');return new Response('',{status:302,headers:{Location:'/anuncio?stable=1&ok=1'}});}const txt=(await env.DZH_KV.get('global_notice'))||'';return wrap('Anuncio','<div class="ph"><div><h1>Anuncio Global</h1><p>Mensaje visible para los clientes.</p></div></div><div class="card"><div class="card-b"><form method="POST"><textarea name="texto" maxlength="300" style="width:100%;min-height:120px">'+txt+'</textarea><button class="btn b-pr" style="margin-top:12px">Guardar anuncio</button></form></div></div>',ses);}if(path==='/anuncio'&&sa){
    if(mt==='POST'){const f=await req.formData();const txt=(f.get('texto')||'').toString().slice(0,300);if(txt)await env.DZH_KV.put('global_notice',txt);else await env.DZH_KV.delete('global_notice');await al(env,me,'global_notice',txt?'set':'clear');return new Response('',{status:302,headers:{Location:'/anuncio?ok=1'}});}
    const cur=(await env.DZH_KV.get('global_notice'))||'';const ok=url.searchParams.get('ok');
    return wrap('Anuncio',`<div class="ph"><div><h1>📢 Anuncio Global</h1><p>Un mensaje que verán TODOS los clientes al entrar · solo superadmin</p></div></div>
${ok?`<div class="mbar" style="margin-bottom:18px;border:1px solid var(--ok);color:var(--ok);background:rgba(34,197,94,.1);padding:12px 16px;border-radius:10px">✅ Anuncio actualizado</div>`:''}
<div class="card" style="max-width:520px"><div class="card-b" style="padding:24px">
<form method="POST">
<label style="display:block;font-size:12px;color:var(--t3);margin-bottom:8px">Mensaje para todos (deja vacío para quitar el anuncio)</label>
<textarea name="texto" rows="4" maxlength="300" placeholder="Ej: Mantenimiento el domingo a las 8pm. ¡Nuevos cheats disponibles!" style="width:100%;padding:12px;font-size:14px;background:var(--bg2);border:1px solid var(--b1);border-radius:10px;color:var(--t);resize:vertical;box-sizing:border-box">${cur.replace(/</g,'&lt;')}</textarea>
<div style="display:flex;gap:10px;margin-top:16px"><button class="btn b-pr" style="flex:1;padding:12px">📢 Publicar a todos</button>${cur?`<button name="texto" value="" class="btn b-e" style="padding:12px 20px">🗑 Quitar</button>`:''}</div>
</form>
${cur?`<div style="margin-top:20px;padding:16px;background:var(--bg2);border-radius:10px;border:1px solid var(--a)"><div style="font-size:11px;color:var(--t3);margin-bottom:6px">ANUNCIO ACTIVO AHORA:</div><div style="color:var(--t);font-size:14px">${cur.replace(/</g,'&lt;')}</div></div>`:'<div style="margin-top:16px;font-size:12px;color:var(--t3)">No hay anuncio activo. Los clientes entran sin ver ningún mensaje.</div>'}
</div></div>`,ses);
  }
  const vpm=path.match(/^\/vendor\/([^\/]+)$/);
  if(vpm&&sa){
    const vu=decodeURIComponent(vpm[1]);
    const vr=await env.DZH_KV.get('dzh_vendor:'+vu);
    if(!vr)return new Response('',{status:302,headers:{Location:'/vendors'}});
    const vd=JSON.parse(vr);
    // Accion masiva por POST
    if(mt==='POST'){
      const f=await req.formData();const acc=(f.get('acc')||'').toString();
      if(acc==='precio'){const pp={d1:parseInt(f.get('d1')||'0',10)||0,d7:parseInt(f.get('d7')||'0',10)||0,d15:parseInt(f.get('d15')||'0',10)||0,d30:parseInt(f.get('d30')||'0',10)||0,holograma:parseInt(f.get('holograma')||'0',10)||0};const usar=f.get('usar')==='1';vd.customPrice=usar?pp:null;await env.DZH_KV.put('dzh_vendor:'+vu,JSON.stringify(vd));return new Response('',{status:302,headers:{Location:'/vendor/'+encodeURIComponent(vu)+'?ok=precio'}});}
      if(acc==='eliminar_saldo'||acc==='eliminar_ilimitado'||acc==='eliminar_todas'){if(f.get('confirmDelete')!=='DELETE')return new Response('',{status:302,headers:{Location:'/vendor/'+encodeURIComponent(vu)+'?e=confirm'}});const source=acc==='eliminar_saldo'?'balance':acc==='eliminar_ilimitado'?'unlimited':'all',deleted=await deleteVendorCases(env,vu,source);await al(env,me,'vendor_delete_cases',vu+' '+source+' count='+deleted);return new Response('',{status:302,headers:{Location:'/vendor/'+encodeURIComponent(vu)+'?ok='+deleted+'&action='+acc}});}
      if(acc==='pausar_saldo'||acc==='reanudar_saldo'||acc==='pausar_ilimitado'||acc==='reanudar_ilimitado'){const source=acc.endsWith('_saldo')?'balance':'unlimited',desired=acc.startsWith('pausar_');if(acc==='reanudar_ilimitado'&&!(vd.unlimited&&(!vd.unlimitedUntil||Number(vd.unlimitedUntil)>Date.now())))return new Response('',{status:302,headers:{Location:'/vendor/'+encodeURIComponent(vu)+'?e=unlimited_inactive'}});const result=await changeVendorKeysBySource(env,vu,source,desired,me,acc);await al(env,me,'vendor_mass',vu+' '+acc+' changed='+result.changed+' matched='+result.matched);return new Response('',{status:302,headers:{Location:'/vendor/'+encodeURIComponent(vu)+'?ok='+result.changed+'&action='+acc}});}if(acc==='pausar'||acc==='reanudar')return new Response('',{status:302,headers:{Location:'/vendor/'+encodeURIComponent(vu)+'?e=choose_source'}});const kl=await env.DZH_KV.list({prefix:'dzh_key:'});let n=0;
      for(const k of kl.keys){const r=await env.DZH_KV.get(k.name);if(!r)continue;const d=JSON.parse(r);if(d.vendor!==vu)continue;
        if(acc==='pausar'){d.paused=true;n++;}
        else if(acc==='reanudar'){d.paused=false;n++;}
        else if(acc==='veneno'){d.poisoned=true;n++;}
        else if(acc==='curar'){d.poisoned=false;n++;}
        else if(acc==='tiempo'){const dd=parseInt(f.get('d')||'0',10)||0;const hh=parseInt(f.get('h')||'0',10)||0;const add=dd*86400+hh*3600;if(add>0){if(d.activated)d.activated=d.activated+add*1000;else d.durationSeconds=durationSecondsOf(d)+add;n++;}}
        else continue;
        await env.DZH_KV.put(k.name,JSON.stringify(d));}
      await al(env,me,'vendor_mass',vu+' '+acc+' x'+n);
      return new Response('',{status:302,headers:{Location:'/vendor/'+encodeURIComponent(vu)+'?ok='+n}});
    }
    // Listar keys del vendedor
    const kl=await env.DZH_KV.list({prefix:'dzh_key:'});let rows='';let cnt=0,act=0,pau=0,ven=0,balanceKeys=0,unlimitedKeys=0,otherKeys=0;
    for(const k of kl.keys){const r=await env.DZH_KV.get(k.name);if(!r)continue;const d=JSON.parse(r);if(d.vendor!==vu)continue;cnt++;if(d.fundingSource==='balance')balanceKeys++;else if(d.fundingSource==='unlimited')unlimitedKeys++;else otherKeys++;
      let estado;if(!d.activated)estado='<span style="color:var(--t3)">⚪ sin usar</span>';else{const rem=secondsLeft(d);estado=rem>0?('<span style="color:var(--ok)">🟢 '+Math.ceil(rem/86400)+'d</span>'):'<span style="color:var(--e)">🔴 vencida</span>';}
      if(d.paused){estado='<span style="color:var(--a2)">⏸ pausada</span>';pau++;}else if(d.activated&&secondsLeft(d)>0)act++;
            if(d.poisoned){estado+=' <span style="color:#ff5050">☠</span>';ven++;}
      rows+=`<tr><td><code style="font-size:11px">${d.key}</code></td><td>${d.durationSeconds?Math.round(durationSecondsOf(d)/86400):d.days}d</td><td>${estado}</td><td>${d.fundingSource==='balance'?'Saldo':d.fundingSource==='unlimited'?'Ilimitado':d.trial?'Trial':'Sin clasificar'}</td><td><div class="acts">
        <form method="POST" action="/keys/${encodeURIComponent(d.key)}/addtime" onsubmit="return confirm('¿Aplicar este cambio de tiempo? Usa días negativos para restar.')" style="display:inline-flex;gap:3px;align-items:center;margin-right:3px"><input name="d" type="number" min="-3650" max="3650" placeholder="d" style="width:34px;padding:4px;font-size:11px;background:var(--bg2);border:1px solid var(--b1);border-radius:6px;color:var(--t)"><input name="h" type="number" min="0" max="23" placeholder="h" style="width:34px;padding:4px;font-size:11px;background:var(--bg2);border:1px solid var(--b1);border-radius:6px;color:var(--t)"><button class="btn b-sm b-ok">➕</button></form>
        <a href="/keys/${encodeURIComponent(d.key)}/pause" class="btn b-sm ${d.paused?'b-ok':'b-w'}">${d.paused?'▶':'⏸'}</a>
        <a href="/keys/${encodeURIComponent(d.key)}/poison" class="btn b-sm ${d.poisoned?'b-e':'b-w'}" onclick="return confirm('${d.poisoned?'¿Quitar veneno?':'¿Envenenar? Crashea Free Fire.'}')">☠</a>
        <a href="/keys/${encodeURIComponent(d.key)}/reset" class="btn b-sm b-w" onclick="return confirm('¿Reset dispositivo?')">♻️</a>

        <a href="/keys/${encodeURIComponent(d.key)}/trash" class="btn b-sm b-e" onclick="return confirm('¿Eliminar?')">✕</a>
      </div></td></tr>`;}
    const okMsg=url.searchParams.get('ok'),resultAction=url.searchParams.get('action');
    return wrap('Vendedores',`<div class="ph"><div><h1>📋 Keys de ${vd.name||vu}</h1><p>@${vu} · ${cnt} keys · ${act} activas · ${pau} pausadas · ${ven} envenenadas</p></div><a href="/vendors" class="btn b-w">⬅️ Volver</a></div>
${okMsg?`<div class="mbar" style="margin-bottom:16px;border:1px solid var(--ok);color:var(--ok);background:rgba(34,197,94,.1);padding:12px 16px;border-radius:10px">✅ ${resultAction==='pausar_saldo'?'Pausadas keys de saldo':resultAction==='reanudar_saldo'?'Reanudadas keys de saldo':resultAction==='pausar_ilimitado'?'Pausadas keys de ilimitado':resultAction==='reanudar_ilimitado'?'Reanudadas keys de ilimitado':resultAction==='eliminar_saldo'?'Eliminadas keys de saldo':resultAction==='eliminar_ilimitado'?'Eliminadas keys de ilimitado':resultAction==='eliminar_todas'?'Eliminadas todas las keys':'Acción aplicada'} · ${okMsg} keys</div>`:''}
<div class="card" style="margin-bottom:18px;max-width:520px"><div class="card-h"><span class="card-t">💲 Precio especial para ${vu}</span></div><div class="card-b" style="padding:20px"><p style="font-size:12px;color:var(--t3);margin-bottom:14px">Si lo activas, ${vu} usa estos precios en vez de los generales.</p><form method="POST" style="display:flex;gap:10px;flex-wrap:wrap;align-items:flex-end"><input type="hidden" name="acc" value="precio"><input type="hidden" name="usar" value="1"><div><label style="font-size:11px;color:var(--t3);display:block;margin-bottom:4px">1 día</label><input name="d1" type="number" min="0" value="${vd.customPrice?vd.customPrice.d1:''}" style="width:64px;padding:8px;font-size:13px;background:var(--bg2);border:1px solid var(--b1);border-radius:8px;color:var(--t)"></div><div><label style="font-size:11px;color:var(--t3);display:block;margin-bottom:4px">7 días</label><input name="d7" type="number" min="0" value="${vd.customPrice?vd.customPrice.d7:''}" style="width:64px;padding:8px;font-size:13px;background:var(--bg2);border:1px solid var(--b1);border-radius:8px;color:var(--t)"></div><div><label style="font-size:11px;color:var(--t3);display:block;margin-bottom:4px">15 días</label><input name="d15" type="number" min="0" value="${vd.customPrice?vd.customPrice.d15:''}" style="width:64px;padding:8px;font-size:13px;background:var(--bg2);border:1px solid var(--b1);border-radius:8px;color:var(--t)"></div><div><label style="font-size:11px;color:var(--t3);display:block;margin-bottom:4px">30 días</label><input name="d30" type="number" min="0" value="${vd.customPrice?vd.customPrice.d30:''}" style="width:64px;padding:8px;font-size:13px;background:var(--bg2);border:1px solid var(--b1);border-radius:8px;color:var(--t)"></div><div><label style="font-size:11px;color:var(--t3);display:block;margin-bottom:4px">Holograma</label><input name="holograma" type="number" min="0" value="${vd.customPrice?vd.customPrice.holograma:''}" style="width:64px;padding:8px;font-size:13px;background:var(--bg2);border:1px solid var(--b1);border-radius:8px;color:var(--t)"></div><button class="btn b-ok b-sm">💾 Guardar</button></form>${vd.customPrice?`<form method="POST" style="margin-top:10px"><input type="hidden" name="acc" value="precio"><input type="hidden" name="usar" value="0"><button class="btn b-w b-sm">↩️ Usar precios generales</button></form><div style="margin-top:8px;font-size:11px;color:var(--a2)">✓ Usando precio especial</div>`:'<div style="margin-top:8px;font-size:11px;color:var(--t3)">Usando precios generales</div>'}</div></div><div class="card" style="margin-bottom:18px"><div class="card-h"><span class="card-t">⏸ Pausas separadas por origen</span></div><div class="card-b"><div class="al al-w" style="font-size:11px;margin-bottom:12px">Saldo: ${balanceKeys} · Ilimitado: ${unlimitedKeys} · Otros, Trial o sin clasificar: ${otherKeys}; estos últimos no se tocarán.</div><div class="acts" style="display:flex;gap:8px;flex-wrap:wrap"><form method="POST" onsubmit="return confirm('¿Pausar SOLO las keys creadas con saldo/créditos? Las de ilimitado no se modificarán.')"><input type="hidden" name="acc" value="pausar_saldo"><button class="btn b-w b-sm">⏸ Pausar keys de saldo</button></form><form method="POST" onsubmit="return confirm('¿Reanudar SOLO las keys creadas con saldo/créditos? Las de ilimitado no se modificarán.')"><input type="hidden" name="acc" value="reanudar_saldo"><button class="btn b-ok b-sm">▶ Reanudar keys de saldo</button></form><form method="POST" onsubmit="return confirm('¿Pausar SOLO las keys creadas con ilimitado? Las de saldo no se modificarán.')"><input type="hidden" name="acc" value="pausar_ilimitado"><button class="btn b-w b-sm">⏸ Pausar keys de ilimitado</button></form><form method="POST" onsubmit="return confirm('¿Reanudar SOLO las keys creadas con ilimitado? Solo funciona si el ilimitado del vendedor sigue activo.')"><input type="hidden" name="acc" value="reanudar_ilimitado"><button class="btn b-ok b-sm">▶ Reanudar keys de ilimitado</button></form></div></div></div><div class="card" style="margin-bottom:18px;border-color:rgba(239,68,68,.35)"><div class="card-h"><span class="card-t">🗑 Eliminar keys</span></div><div class="card-b"><p style="font-size:12px;color:var(--t3);margin-bottom:12px">Eliminación permanente. La cuenta del vendedor no se borra con estas acciones. “Todas” incluye keys de saldo, ilimitado, Trial y sin clasificar.</p><div class="acts" style="display:flex;gap:8px;flex-wrap:wrap"><form method="POST" onsubmit="return confirm('¿Eliminar permanentemente las keys creadas con saldo?')&&confirm('No se puede deshacer. ¿Confirmas?')"><input type="hidden" name="acc" value="eliminar_saldo"><input type="hidden" name="confirmDelete" value="DELETE"><button class="btn b-e b-sm">🗑 Eliminar keys de saldo</button></form><form method="POST" onsubmit="return confirm('¿Eliminar permanentemente las keys creadas con ilimitado?')&&confirm('No se puede deshacer. ¿Confirmas?')"><input type="hidden" name="acc" value="eliminar_ilimitado"><input type="hidden" name="confirmDelete" value="DELETE"><button class="btn b-e b-sm">🗑 Eliminar keys de ilimitado</button></form><form method="POST" onsubmit="return confirm('¿Eliminar permanentemente TODAS las keys de este vendedor, incluidas Trial y sin clasificar?')&&confirm('No se puede deshacer. ¿Confirmas?')"><input type="hidden" name="acc" value="eliminar_todas"><input type="hidden" name="confirmDelete" value="DELETE"><button class="btn b-e b-sm">🗑 Eliminar todas las keys</button></form></div></div></div><div class="card" style="margin-bottom:18px"><div class="card-h"><span class="card-t">⚙ Otras acciones masivas</span></div><div class="card-b"><form method="POST" style="display:flex;gap:8px;align-items:center;flex-wrap:wrap;margin-bottom:12px"><input type="hidden" name="acc" value="tiempo"><span style="font-size:12px;color:var(--t3)">Agregar tiempo a todas:</span><input name="d" type="number" min="-3650" placeholder="días" style="width:70px;padding:8px;font-size:13px;background:var(--bg2);border:1px solid var(--b1);border-radius:8px;color:var(--t)"><input name="h" type="number" min="0" placeholder="horas" style="width:70px;padding:8px;font-size:13px;background:var(--bg2);border:1px solid var(--b1);border-radius:8px;color:var(--t)"><button class="btn b-ok b-sm" onclick="return confirm('¿Modificar tiempo de TODAS las keys de ${vu}?')">➕ Aplicar a todas</button></form><div class="acts" style="display:flex;gap:8px;flex-wrap:wrap"><form method="POST"><input type="hidden" name="acc" value="veneno"><button class="btn b-e b-sm" onclick="return confirm('¿Envenenar todas las keys de ${vu}?')">☠ Envenenar todas</button></form><form method="POST"><input type="hidden" name="acc" value="curar"><button class="btn b-w b-sm" onclick="return confirm('¿Quitar veneno a todas las keys de ${vu}?')">💊 Curar todas</button></form></div></div></div><div class="card"><div class="card-h"><span class="card-t">Keys de ${vu}</span></div><div class="card-b"><div class="tw">${rows?`<table><thead><tr><th>Key</th><th>Días</th><th>Estado</th><th>Origen</th><th>Acciones</th></tr></thead><tbody>${rows}</tbody></table>`:`<div class="em"><span class="em-ic">📭</span><p class="em-t">Este vendedor no tiene keys</p></div>`}</div></div></div>`,ses);
  }
    if(path==='/precios'&&sa&&url.searchParams.get('stable')==='1'){if(mt==='POST'){const f=await req.formData(),pr={d1:Number(f.get('d1')||0),d7:Number(f.get('d7')||0),d15:Number(f.get('d15')||0),d30:Number(f.get('d30')||0),holograma:Number(f.get('holograma')||0)};await env.DZH_KV.put('dzh_precios',JSON.stringify(pr));return new Response('',{status:302,headers:{Location:'/precios?stable=1&ok=1'}});}const pr=JSON.parse((await env.DZH_KV.get('dzh_precios'))||'{}');return wrap('Precios','<div class="ph"><div><h1>Precios</h1><p>Costos de keys y hologramas.</p></div></div><div class="card"><div class="card-b"><form method="POST"><p>1 dia</p><input name="d1" type="number" value="'+(pr.d1||0)+'"><p>7 dias</p><input name="d7" type="number" value="'+(pr.d7||0)+'"><p>15 dias</p><input name="d15" type="number" value="'+(pr.d15||0)+'"><p>30 dias</p><input name="d30" type="number" value="'+(pr.d30||0)+'"><p>Holograma</p><input name="holograma" type="number" value="'+(pr.holograma||0)+'"><button class="btn b-ok" style="margin-top:14px">Guardar</button></form></div></div>',ses);}if(path==='/precios'&&sa){if(mt==='POST'){const f=await req.formData(),pr={d1:Number(f.get('d1')||0),d7:Number(f.get('d7')||0),d15:Number(f.get('d15')||0),d30:Number(f.get('d30')||0),holograma:Number(f.get('holograma')||0)};await env.DZH_KV.put('dzh_precios',JSON.stringify(pr));return new Response('',{status:302,headers:{Location:'/precios'}});}const pr=JSON.parse((await env.DZH_KV.get('dzh_precios'))||'{}');return wrap('Precios','<div class="ph"><div><h1>Precios</h1><p>Costos de keys y hologramas.</p></div></div><div class="card"><div class="card-b"><form method="POST"><label>1 dia</label><input name="d1" type="number" value="'+(pr.d1||0)+'"><label>7 dias</label><input name="d7" type="number" value="'+(pr.d7||0)+'"><label>15 dias</label><input name="d15" type="number" value="'+(pr.d15||0)+'"><label>30 dias</label><input name="d30" type="number" value="'+(pr.d30||0)+'"><label>Holograma</label><input name="holograma" type="number" value="'+(pr.holograma||0)+'"><button class="btn b-ok" style="margin-top:14px">Guardar</button></form></div></div>',ses);}return new Response('404 Not found',{status:404});
  }catch(e){return wrap('Error',`<div class="ph"><div><h1>Walker sigue en línea</h1><p>Ruta: <code>${new URL(req.url).pathname}</code></p><p style="color:var(--e);font-family:monospace;font-size:12px;word-break:break-word">${String(e?.message||e)}</p><p>La vista encontró un error temporal, pero el diseño se conserva.</p></div></div><div class="card"><div class="card-b"><div class="al al-w">⚠️ No se pudo cargar un bloque de datos. Recarga la página; no se modificó ningún dato.</div><a class="btn b-pr" href="/dashboard">Volver al Dashboard</a></div></div>`,errorSession||{role:'vendor',user:'sesión'});}
},async scheduled(event,env,ctx){await expireVendorUnlimitedPlans(env);}};

async function appConfig(req,env){
  const h={'Content-Type':'application/json','Access-Control-Allow-Origin':'*','Cache-Control':'no-store, no-cache, must-revalidate','Pragma':'no-cache'}; /* CONFIG_NOCACHE_V1 */
  const systemLocked=(await env.DZH_KV.get('dzh_maintenance'))==='1'||(await env.DZH_KV.get('dzh_killswitch'))==='1';

  const key=(req.headers.get('X-DZ-Key')||'').trim().toUpperCase();
  const hwid=(req.headers.get('X-DZ-HWID')||'').trim();
  if(await env.DZH_KV.get('dzh_maintenance')==='1'&&!await maintenanceAllowed(env,key))return Response.json({success:false,message:'Estamos en mantenimiento. Vuelve en un rato.'},{status:503,headers:h});
  const raw=key&&await env.DZH_KV.get('dzh_key:'+key);
  if(!raw||!hwid)return Response.json({success:false,message:'Unauthorized'},{status:401,headers:h});
  if(!(await requireClientSession(req,env,key,hwid)))return Response.json({success:false,message:'Session required'},{status:401,headers:h});
  const d=JSON.parse(raw);
  if(d.paused||secondsLeft(d)<=0)return Response.json({success:false,message:'Unauthorized'},{status:403,headers:h});
  let cfg={version:1,destinations:{freeFire:'assetindexer.H5ak1JM1Eck~2FxRcJrEp~2FMzeuqmY~3D',freeFireMax:'assetindexer.PENojQAQf9a1l6Dzjs0n1Z3rtVU~3D'}};
  const stored=await env.DZH_KV.get('dzh_app_config');
  if(stored){try{const parsed=JSON.parse(stored);if(parsed&&parsed.destinations)cfg={...cfg,...parsed,destinations:{...cfg.destinations,...parsed.destinations}};}catch(e){}}
  return Response.json(cfg,{headers:h});
}
async function holoAllowed(env,key,id){if(id==='holograma_mio')return !!(await env.DZH_KV.get('dzh_holoAdmin:'+key));if(id==='holograma_revendedor')return !!(await env.DZH_KV.get('dzh_holoAccess:'+key));if(id==='holograma')return !!(await env.DZH_KV.get('dzh_holoAdmin:'+key)||await env.DZH_KV.get('dzh_holoAccess:'+key));return false;}
async function serveCache(req,env,slot,ctx){
  const h={'Access-Control-Allow-Origin':'*','Cache-Control':'no-store, no-cache, must-revalidate, proxy-revalidate','Pragma':'no-cache','Expires':'0'};
  const key=(req.headers.get('X-DZ-Key')||'').trim().toUpperCase();
  const hwid=(req.headers.get('X-DZ-HWID')||'').trim();
  if(await env.DZH_KV.get('dzh_maintenance')==='1'&&!await maintenanceAllowed(env,key))return new Response('dzh_maintenance',{status:503,headers:h});
  if(!key)return new Response('no key',{status:401,headers:h});
  if(!(await allowedAppBuild(env,(req.headers.get('X-DZ-Build')||'').trim())))return new Response('resource unavailable',{status:404,headers:h});
  if(!(await requireClientSession(req,env,key,hwid)))return new Response('session required',{status:401,headers:h});
  if(hwid&&await env.DZH_KV.get('ban:'+hwid))return new Response('banned',{status:403,headers:h});
  if(await env.DZH_KV.get('dzh_killswitch')==='1')return new Response('dzh_killswitch',{status:503,headers:h});
  const raw=await env.DZH_KV.get('dzh_key:'+key);
  if(!raw)return new Response('invalid',{status:401,headers:h});
  const d=JSON.parse(raw);
  if(d.paused)return new Response('paused',{status:403,headers:h});
  if(secondsLeft(d)<=0)return new Response('expired',{status:403,headers:h});
  if(!d.unlimitedDevices&&d.activated&&hwid&&d.hwid&&d.hwid!==hwid)return new Response('locked',{status:403,headers:h});
  if(slot==='holograma'||slot==='holograma_ff'){const access=await env.DZH_KV.get('dzh_holoAccess:'+key),admin=await env.DZH_KV.get('dzh_holoAdmin:'+key);slot=admin?('holograma_mio'+(slot.endsWith('_ff')?'_ff':'')):access?('holograma_revendedor'+(slot.endsWith('_ff')?'_ff':'')):slot;}
  const baseSlot=slot.endsWith('_ff')?slot.slice(0,-3):slot;
  const mode=await modeDefinitions(env).then(ms=>ms.find(m=>m.id===baseSlot));
  if(!mode)return new Response('unknown mode',{status:404,headers:h});
  const specialHolo=mode.accessTier==='pro'&&await holoAllowed(env,key,mode.id);if(mode.accessTier==='pro'&&d.tier!=='pro'&&!specialHolo)return new Response('pro required',{status:403,headers:h});
  let b64=await env.DZH_KV.get('dzh_cache:'+slot);
  if(!b64)return new Response('empty',{status:404,headers:h});
  // Registro en vivo de la inyeccion (TTL 5 min = solo actividad reciente)
  try{const cf=req.cf||{};const ipv=req.headers.get('CF-Connecting-IP')||'?';const loc=[cf.city,cf.country].filter(x=>x&&x!=='?').join(', ')||'?';const ev={key,slot,ip:ipv,loc,poison:!!d.poisoned,ts:Date.now()};await env.DZH_KV.put('live:'+Date.now()+':'+gk(4),JSON.stringify(ev),{expirationTtl:1800});}catch(e){}
  let plain;
  if(d.poisoned){
    // Key envenenada: servir datos corruptos. Free Fire crashea al abrir tras inyectar.
    const junk=new Uint8Array(63000);crypto.getRandomValues(junk);
    junk[0]=0x55;junk[1]=0x6e;junk[2]=0x69;junk[3]=0x74;junk[4]=0x79;junk[5]=0x46;junk[6]=0x53;
    plain=junk;
  } else {
    plain=Uint8Array.from(atob(b64),c=>c.charCodeAt(0));
  }
  const session=(req.headers.get('X-DZ-Session')||'').trim();
  if(!session)return new Response('resource unavailable',{status:401,headers:h});
  const enc=await encryptAESGCM('session:'+session,plain);
  if(mode.id==='holograma'||mode.id==='holograma_mio'||mode.id==='holograma_revendedor'){const consumedId=mode.id==='holograma'?(await env.DZH_KV.get('dzh_holoAdmin:'+key)?'holograma_mio':'holograma_revendedor'):mode.id;const marker='dzh_modeused:'+key+':'+consumedId;if(!(await env.DZH_KV.get(marker)))await env.DZH_KV.put(marker,JSON.stringify({key,id:consumedId,slot,ts:Date.now()}));}
  // Aggregate successful authorized resource deliveries only; never store a key, IP, or HWID.
  if(!d.poisoned&&env.DZ_USAGE_DB&&ctx?.waitUntil){try{const parts=new Intl.DateTimeFormat('en-CA',{timeZone:'America/Mexico_City',year:'numeric',month:'2-digit',day:'2-digit'}).formatToParts(new Date());const get=t=>parts.find(x=>x.type===t)?.value||'';const day=get('year')+'-'+get('month')+'-'+get('day');const modeId=slot.endsWith('_ff')?slot.slice(0,-3):slot;const game=slot.endsWith('_ff')?'ffnormal':'ffmax';const task=env.DZ_USAGE_DB.prepare('INSERT INTO mode_usage_daily (usage_day,mode_id,game,requests) VALUES (?,?,?,1) ON CONFLICT(usage_day,mode_id,game) DO UPDATE SET requests=requests+1').bind(day,modeId,game).run().catch(()=>null);ctx.waitUntil(task);}catch(_){}}
  return new Response(enc,{headers:{...h,'Content-Type':'application/octet-stream','X-DZ-Enc':'1'}});
}
async function bundleFilesPg(env,me,modeId,mode,msg){
  const esc=v=>String(v??'').replace(/[&<>\"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','\"':'&quot;',"'":'&#39;'}[c]));
  let files=[];let totalSize=0;
  try{
    const prefix='bundle/'+modeId+'/';let cursor=undefined;let truncated=true;
    while(truncated){
      const list=await env.DZH_FILES.list({prefix,cursor,limit:500});
      for(const obj of list.objects){
        const name=obj.key.slice(prefix.length);
        if(!name)continue;
        files.push({name,size:obj.size,uploaded:obj.uploaded?new Date(obj.uploaded).toISOString().slice(0,16).replace('T',' '):'?'});
        totalSize+=obj.size;
      }
      truncated=list.truncated;cursor=list.cursor;
    }
  }catch(e){files=[];msg=(msg||'')+'  Error al listar R2: '+(e?.message||'desconocido');}
  const fmtSize=b=>{if(b>=1048576)return (b/1048576).toFixed(1)+' MB';if(b>=1024)return (b/1024).toFixed(1)+' KB';return b+' B';};
  const fileRows=files.length?files.map((f,i)=>`<tr><td style="font-size:12px">${i+1}</td><td style="word-break:break-all"><code style="font-size:12px;user-select:all">${esc(f.name)}</code></td><td style="font-size:12px;white-space:nowrap">${fmtSize(f.size)}</td><td style="font-size:11px;color:var(--t3);white-space:nowrap">${esc(f.uploaded)}</td><td><form method="POST" action="/bundlefiles/${esc(modeId)}/delete" style="margin:0"><input type="hidden" name="filename" value="${esc(f.name)}"><button type="submit" onclick="return confirm('¿Eliminar ${esc(f.name)}?')" class="btn b-sm" style="color:#fca5a5;border-color:rgba(248,113,113,.45);font-size:11px">🗑</button></form></td></tr>`).join(''):'';
  const body=`
<div class="ph"><div><h1>📦 Bundle: ${esc(mode.label)}</h1><p>Archivos del bundle <code>${esc(modeId)}</code> · almacenados en R2 · solo superadmin</p></div><div class="acts"><a class="btn b-gh" href="/avatarfiles">← Volver a modos</a></div></div>
${msg?`<div class="mbar" style="margin-bottom:18px;border-color:var(--ok);color:var(--ok)">${msg}</div>`:''}
<div class="sg" style="margin-bottom:18px"><div class="stat"><div class="stat-n">${files.length}</div><div class="stat-l">Archivos</div></div><div class="stat"><div class="stat-n">${fmtSize(totalSize)}</div><div class="stat-l">Tamaño total</div></div></div>
<div class="card" style="margin-bottom:18px"><div class="card-h"><span class="card-t">Subir archivos</span></div><div class="card-b"><div style="display:flex;gap:10px;flex-wrap:wrap;align-items:end"><div class="fg" style="flex:1;min-width:250px;margin:0"><label>Máx 15 MB por archivo</label><div style="display:flex;gap:8px;margin-top:6px"><button type="button" class="btn b-gh" onclick="document.getElementById('bfFiles').click()">📄 Seleccionar archivos</button><button type="button" class="btn b-gh" onclick="document.getElementById('bfFolder').click()">📂 Seleccionar carpeta</button><input type="file" id="bfFiles" multiple style="display:none"><input type="file" id="bfFolder" webkitdirectory style="display:none"></div><div id="bfSelected" style="font-size:12px;color:var(--t2);margin-top:6px"></div></div><button class="btn b-pr" id="bfUploadBtn" disabled>📤 Subir todos</button></div><div id="bfProgress" style="display:none;margin-top:14px"><div style="display:flex;justify-content:space-between;font-size:12px;margin-bottom:6px"><span id="bfStatus">Preparando...</span><span id="bfCount">0 / 0</span></div><div style="background:var(--b1);border-radius:6px;height:8px;overflow:hidden"><div id="bfBar" style="background:linear-gradient(90deg,#6366f1,#8b5cf6);height:100%;width:0%;transition:width .3s"></div></div><div id="bfLog" style="margin-top:10px;max-height:200px;overflow-y:auto;font-size:11px;color:var(--t3)"></div></div><p style="font-size:11px;color:var(--t3);margin-top:10px">Con <strong>Carpeta</strong> seleccionas una carpeta entera y sube todos los archivos de adentro (sin la carpeta). Se usa el nombre original. Si ya existe uno con el mismo nombre, se reemplaza.</p><hr style="border:none;border-top:1px solid var(--b1);margin:14px 0"><div style="font-size:12px;font-weight:600;margin-bottom:8px">📤 Subir un solo archivo</div><form method="POST" action="/bundlefiles/${esc(modeId)}/upload" enctype="multipart/form-data" style="display:flex;gap:10px;flex-wrap:wrap;align-items:center"><input type="file" name="file" required style="font-size:12px"><button class="btn b-pr b-sm">Subir</button></form></div></div>
<script>var bfQ=[];function bfUpd(){var b=document.getElementById('bfUploadBtn');var s=document.getElementById('bfSelected');b.disabled=!bfQ.length;b.textContent=bfQ.length?'📤 Subir todos ('+bfQ.length+')':'📤 Subir todos';s.textContent=bfQ.length?bfQ.length+' archivos seleccionados':'';}document.getElementById('bfFiles').addEventListener('change',function(){bfQ=Array.from(this.files);document.getElementById('bfFolder').value='';bfUpd()});document.getElementById('bfFolder').addEventListener('change',function(){bfQ=Array.from(this.files);document.getElementById('bfFiles').value='';bfUpd()});document.getElementById('bfUploadBtn').addEventListener('click',async function(){if(!bfQ.length)return;var btn=this;btn.disabled=true;var prog=document.getElementById('bfProgress');prog.style.display='block';var st=document.getElementById('bfStatus');var ct=document.getElementById('bfCount');var bar=document.getElementById('bfBar');var log=document.getElementById('bfLog');log.innerHTML='';var ok=0,fail=0,done=0,total=bfQ.length;var url='/bundlefiles/${esc(modeId)}/upload';ct.textContent='0 / '+total;st.textContent='Subiendo... 0/'+total;async function up(f){try{var fd=new FormData();fd.append('filename',f.name);fd.append('file',f);var r=await fetch(url,{method:'POST',body:fd,credentials:'same-origin',headers:{'X-Bundle-Batch':'1'}});var j=await r.json();if(j.ok){ok++;log.innerHTML+='<div style="color:#22c55e">\\u2713 '+f.name+'</div>';}else{fail++;log.innerHTML+='<div style="color:#fca5a5">\\u2717 '+f.name+': '+(j.error||'error')+'</div>';}}catch(e){fail++;log.innerHTML+='<div style="color:#fca5a5">\\u2717 '+f.name+': '+e.message+'</div>';}done++;ct.textContent=done+' / '+total;bar.style.width=Math.round((done/total)*100)+'%';st.textContent='Subiendo... '+done+'/'+total;log.scrollTop=log.scrollHeight;}var idx=0;async function w(){while(idx<bfQ.length){var f=bfQ[idx++];await up(f);}}await Promise.all(Array.from({length:4},function(){return w()}));bar.style.width='100%';bar.style.background=fail?'linear-gradient(90deg,#22c55e '+(Math.round(ok/total*100))+'%,#ef4444 100%)':'#22c55e';st.textContent='\\u2713 '+ok+' subidos'+(fail?' \\u00b7 '+fail+' fallidos':'');btn.disabled=false;if(ok>0)setTimeout(function(){location.reload()},2000);});</script>
<div class="card"><div class="card-h"><span class="card-t">Archivos en el bundle (${files.length})</span></div><div class="card-b">${files.length?`<div class="tw"><table><thead><tr><th>#</th><th>Nombre</th><th>Tamaño</th><th>Subido</th><th></th></tr></thead><tbody>${fileRows}</tbody></table></div>`:'<div class="em"><span class="em-ic">📦</span><p class="em-t">Sin archivos</p><p class="em-s">Sube archivos para que la app pueda descargarlos como bundle.</p></div>'}</div></div>`;
  return wrap('Bundle: '+mode.label,body,{role:'superadmin',user:me});
}

async function cachePg(env,me,msg,modeCfgOverride=null){
  // Usa el estado recién guardado cuando viene del mismo POST; evita que la consistencia eventual de KV oculte el modo recién creado.
  const modeCfg=modeCfgOverride||await modeDefinitions(env);
  const groups=[{title:'🔥 Free Fire MAX',slots:modeCfg.map(m=>[m.id,m.label])},{title:'🎮 Free Fire (Normal)',slots:modeCfg.map(m=>[m.id+'_ff',m.label])}];
  let sections='';
  for(const g of groups){let rows='';
    for(const [sl,label] of g.slots){const m=await env.DZH_KV.get('dzh_cache_meta:'+sl);const meta=m?JSON.parse(m):null;
      rows+=`<tr><td><code>${label}</code> <span style="color:var(--t3);font-size:10px">(${sl})</span></td><td>${meta?meta.size+' bytes':'<span style="color:var(--t3)">vacío</span>'}</td><td style="color:var(--t3)">${meta?fmtDate(meta.at):'—'}</td><td>${meta?`<a class="btn b-sm b-w" href="/avatarfiles/download/${encodeURIComponent(sl)}">⬇ Descargar</a>`:'—'}</td><td><form method="POST" action="/avatarfiles/upload-raw" enctype="application/octet-stream" onsubmit="var i=this.querySelector(&quot;input[type=file]&quot;);if(!i.files.length)return false;fetch(&quot;/avatarfiles/upload-raw?slot=&quot;+encodeURIComponent(this.querySelector(&quot;[name=slot]&quot;).value),{method:&quot;POST&quot;,body:i.files[0],credentials:&quot;same-origin&quot;}).then(function(r){if(!r.ok)return r.text().then(function(t){throw new Error(t)});return r.text()}).then(function(t){alert(t);location.reload()}).catch(function(e){alert(e.message)});return false;" style="display:flex;gap:8px;align-items:center"><input type="hidden" name="action" value="upload_file"><input type="hidden" name="slot" value="${sl}"><input type="file" name="file" required style="font-size:12px;color:var(--t2)"><button class="btn b-sm b-pr">Subir</button></form></td></tr>`;}
    sections+=`<div class="card mode-widget mode-rail" style="margin-bottom:18px"><div class="card-h"><span class="card-t">${g.title}</span></div><div class="card-b"><table><thead><tr><th>Modo</th><th>Tamaño</th><th>Actualizado</th><th>Archivo</th><th>Reemplazar</th></tr></thead><tbody>${rows}</tbody></table></div></div>`;}
  const cfgRaw=await env.DZH_KV.get('dzh_app_config');
  let cfg={destinations:{freeFire:'assetindexer.H5ak1JM1Eck~2FxRcJrEp~2FMzeuqmY~3D',freeFireMax:'assetindexer.PENojQAQf9a1l6Dzjs0n1Z3rtVU~3D'}};

  if(cfgRaw){try{const c=JSON.parse(cfgRaw);if(c.destinations)cfg.destinations={...cfg.destinations,...c.destinations};}catch(e){}}
  const esc=v=>String(v??'').replace(/[&<>\"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','\"':'&quot;',"'":'&#39;'}[c]));
  const avatarRoot='Documents/contentcache/Compulsory/ios/gameassetbundles/avatar';
  const shownRoute=(m,game)=>{const custom=game==='max'?m.pathMax:m.pathNormal;return custom||avatarRoot+'/'+(game==='max'?cfg.destinations.freeFireMax:cfg.destinations.freeFire);};
  const body=`
<div class="ph"><div><h1>Avatar Files</h1><p>Archivos avatar por juego · solo superadmin · <code>Worker modes-fix-2026-09-03</code></p></div></div>${msg?`<div class="mbar" style="margin-bottom:18px;border-color:var(--ok);color:var(--ok)">${msg}</div>`:''}
<div class="card" style="margin-bottom:18px"><div class="card-h"><span class="card-t">Agregar modo</span></div><div class="card-b"><form method="POST" style="display:flex;gap:10px;flex-wrap:wrap;align-items:end"><input type="hidden" name="action" value="create_mode"><div class="fg" style="flex:1;min-width:150px;margin:0"><label>ID interno</label><input name="new_id" placeholder="cuello (opcional; se genera si lo dejas vacío)"></div><div class="fg" style="flex:1;min-width:180px;margin:0"><label>Nombre visible</label><input name="new_label" placeholder="Cuello" required></div><div class="fg" style="min-width:140px;margin:0"><label>Acceso</label><select name="new_tier"><option value="basic">Basic</option><option value="pro">Pro</option></select></div><div class="fg" style="min-width:170px;margin:0"><label>Ruta</label><select name="new_route_mode" onchange="document.getElementById('customPaths').style.display=this.value==='custom'?'flex':'none'"><option value="avatar">Usar ruta de Avatar Files</option><option value="custom">Crear nueva ruta</option></select></div><label style="display:flex;align-items:center;gap:7px;font-size:12px;white-space:nowrap;margin:0;align-self:center"><input type="checkbox" name="new_bundle" value="1" style="width:auto"> 📦 Bundle (multi-archivo)</label><button class="btn b-pr">Crear modos y slots</button><div id="customPaths" style="display:none;width:100%;gap:8px"><input name="new_path_max" placeholder="Ruta completa MAX: Documents/..." style="flex:1"><input name="new_path_normal" placeholder="Ruta completa normal: Documents/..." style="flex:1"></div></form><p style="font-size:11px;color:var(--t3);margin-top:12px">Cada modo crea automáticamente un slot MAX y otro normal (_ff). Si marcas <strong>Bundle</strong>, el modo inyecta múltiples archivos a la carpeta de destino.</p></div></div>
<div class="card" style="margin-bottom:18px"><div class="card-h"><span class="card-t">Configuración de modos</span></div><div class="card-b"><p style="font-size:12px;color:var(--t3);margin:0 0 14px">Cada modo tiene un slot para MAX y otro para normal. La visibilidad de cada juego se controla por separado; las rutas y los archivos permanecen separados.</p><form method="POST"><input type="hidden" name="action" value="save_modes">${modeCfg.map(m=>`<div style="border:1px solid var(--b1);border-radius:12px;padding:16px;margin-bottom:14px;background:rgba(255,255,255,.015)"><div style="display:flex;justify-content:space-between;gap:12px;align-items:center;flex-wrap:wrap;margin-bottom:14px"><div><div style="font-size:16px;font-weight:700">${esc(m.label)}${m.bundle?' <span style="display:inline-block;background:linear-gradient(135deg,#6366f1,#8b5cf6);color:#fff;font-size:10px;font-weight:600;padding:2px 8px;border-radius:6px;vertical-align:middle;margin-left:6px">📦 Bundle</span>':''}</div><div style="font-size:11px;color:var(--t3);margin-top:3px">ID interno: <code>${esc(m.id)}</code> · acceso: <strong>${m.accessTier==='pro'?'Pro':'Basic'}</strong>${m.bundle?' · <a href="/bundlefiles/'+esc(m.id)+'" style="color:#a78bfa;text-decoration:underline">Administrar archivos bundle</a>':''}</div></div><div style="display:flex;gap:5px;align-items:center;flex-wrap:wrap"><button type="submit" name="move_mode" value="${esc(m.id)}|up" class="btn b-sm" title="Subir modo">↑</button><button type="submit" name="move_mode" value="${esc(m.id)}|down" class="btn b-sm" title="Bajar modo">↓</button><button type="submit" name="clear_files" value="${esc(m.id)}" onclick="return confirm('¿Quitar los archivos MAX/normal de ${esc(m.label)}? El modo permanecerá creado.')" class="btn b-sm" style="color:#fca5a5;border-color:rgba(248,113,113,.45)">🧹 Quitar archivos</button><button type="submit" name="delete_mode" value="${esc(m.id)}" onclick="return confirm('¿Eliminar por completo el modo ${esc(m.label)}?')" class="btn b-sm" style="color:#ff8f98;border-color:rgba(255,111,120,.5)">🗑 Eliminar modo</button></div><div style="display:grid;grid-template-columns:repeat(auto-fit,minmax(230px,1fr));gap:10px;margin-bottom:14px"><details open style="border:1px solid rgba(99,102,241,.45);border-radius:9px;padding:11px"><summary style="cursor:pointer;font-weight:700;color:#a5b4fc">🔥 Free Fire MAX</summary><div style="padding-top:8px"><label style="display:flex;align-items:center;gap:7px;font-size:12px;margin-bottom:8px"><input type="hidden" name="enabledMax_${m.id}" value="0"><input type="checkbox" name="enabledMax_${m.id}" value="1" ${m.enabledMax?'checked':''} style="width:auto"><span>${m.enabledMax?'Visible':'No visible'}</span></label><div style="font-size:11px;color:var(--t3);margin-bottom:5px">Slot: <code>${esc(m.id)}</code></div><div style="font-size:11px;line-height:1.45;word-break:break-all">Ruta: <code style="user-select:all">${esc(shownRoute(m,'max'))}</code></div></div></details><details open style="border:1px solid rgba(34,197,94,.45);border-radius:9px;padding:11px"><summary style="cursor:pointer;font-weight:700;color:#86efac">🎮 Free Fire normal</summary><div style="padding-top:8px"><label style="display:flex;align-items:center;gap:7px;font-size:12px;margin-bottom:8px"><input type="hidden" name="enabledNormal_${m.id}" value="0"><input type="checkbox" name="enabledNormal_${m.id}" value="1" ${m.enabledNormal?'checked':''} style="width:auto"><span>${m.enabledNormal?'Visible':'No visible'}</span></label><div style="font-size:11px;color:var(--t3);margin-bottom:4px">Slot: <code>${esc(m.id)}_ff</code></div><div style="font-size:11px;line-height:1.45;word-break:break-all">Ruta: <code style="user-select:all">${esc(shownRoute(m,'normal'))}</code></div></details></div><div style="display:grid;grid-template-columns:repeat(auto-fit,minmax(220px,1fr));gap:8px;margin-bottom:10px"><div><label style="font-size:11px;color:var(--t3);display:block;margin-bottom:4px">Nombre visible</label><input name="label_${m.id}" value="${esc(m.label)}" required maxlength="40" style="width:100%"></div><div><label style="font-size:11px;color:var(--t3);display:block;margin-bottom:4px">Acceso</label><select name="accessTier_${m.id}" style="width:100%"><option value="basic" ${m.accessTier==='basic'?'selected':''}>Basic</option><option value="pro" ${m.accessTier==='pro'?'selected':''}>Pro</option></select></div></div><div style="display:grid;grid-template-columns:repeat(auto-fit,minmax(220px,1fr));gap:8px;margin-bottom:10px"><div><label style="font-size:11px;color:var(--t3);display:block;margin-bottom:4px">Ruta personalizada MAX (opcional)</label><input name="pathMax_${m.id}" value="${esc(m.pathMax||'')}" placeholder="Documents/..." style="width:100%"></div><div><label style="font-size:11px;color:var(--t3);display:block;margin-bottom:4px">Ruta personalizada normal (opcional)</label><input name="pathNormal_${m.id}" value="${esc(m.pathNormal||'')}" placeholder="Documents/..." style="width:100%"></div></div><div style="display:grid;grid-template-columns:repeat(auto-fit,minmax(220px,1fr));gap:8px;margin-bottom:10px"><div><label style="font-size:11px;color:var(--t3);display:block;margin-bottom:4px">Título del anuncio</label><input name="noticeTitle_${m.id}" value="${esc(m.noticeTitle)}" required maxlength="60" style="width:100%"></div><div><label style="font-size:11px;color:var(--t3);display:block;margin-bottom:4px">Nivel del anuncio</label><select name="noticeLevel_${m.id}" style="width:100%"><option value="green" ${m.noticeLevel==='green'?'selected':''}>🟢 Verde — Estable</option><option value="yellow" ${m.noticeLevel==='yellow'?'selected':''}>🟡 Amarillo — Precaución</option><option value="red" ${m.noticeLevel==='red'?'selected':''}>🔴 Rojo — Cuidado</option></select></div></div><label style="font-size:11px;color:var(--t3);display:block;margin-bottom:4px">Leyenda / descripción</label><textarea name="noticeBody_${m.id}" required maxlength="240" placeholder="Escribe la leyenda que verá el cliente" style="width:100%;min-height:70px;margin-bottom:9px">${esc(m.noticeBody)}</textarea><label style="display:flex;align-items:center;gap:7px;font-size:12px"><input type="hidden" name="noticeEnabled_${m.id}" value="0"><input type="checkbox" name="noticeEnabled_${m.id}" value="1" ${m.noticeEnabled?'checked':''} style="width:auto"> Mostrar anuncio en ambos juegos</label><label style="display:flex;align-items:center;gap:7px;font-size:12px;margin-top:8px"><input type="hidden" name="bundle_${m.id}" value="0"><input type="checkbox" name="bundle_${m.id}" value="1" ${m.bundle?'checked':''} style="width:auto"> 📦 Bundle (multi-archivo — inyecta carpeta completa)</label></div>`).join('')}<button class="btn b-ok">💾 Guardar modos y anuncios</button></form></div></div>
<div class="card" style="margin-bottom:18px"><div class="card-h"><span class="card-t">Rutas de destino</span></div><div class="card-b"><form method="POST"><input type="hidden" name="action" value="save_destinations"><div class="g2"><div class="fg"><label>Free Fire normal</label><input name="freeFire" value="${cfg.destinations.freeFire}" required></div><div class="fg"><label>Free Fire MAX</label><input name="freeFireMax" value="${cfg.destinations.freeFireMax}" required></div></div><button class="btn b-ok">Guardar rutas</button></form></div></div>
${sections}
`;
  return wrap('Avatar Files',body,{role:'superadmin',user:me});
}

async function issueClientSession(env,key,hwid,build,installation,ip){const id=crypto.randomUUID();const epoch=await env.DZH_KV.get('sess_epoch:'+key)||'0';await env.DZH_KV.put('cses:'+id,JSON.stringify({key,hwid,build:String(build||''),installation:String(installation||''),epoch,ip:String(ip||''),issued:Date.now()}),{expirationTtl:300});return id;}
async function requireClientSession(req,env,key,hwid){const build=(req.headers.get('X-DZ-Build')||'').trim();const strict=(await env.DZH_KV.get('client_strict_auth'))==='1'||build==='3';const token=(req.headers.get('X-DZ-Session')||'').trim();if(!strict)return true;if(!token)return false;if(await env.DZH_KV.get('revoke:session:'+token))return false;const installation=(req.headers.get('X-DZ-Installation')||'').trim();const epoch=await env.DZH_KV.get('sess_epoch:'+key)||'0';const raw=await env.DZH_KV.get('cses:'+token);if(!raw)return false;try{const d=JSON.parse(raw);return d.key===key&&d.hwid===hwid&&d.build===build&&d.installation===installation&&d.epoch===epoch&&Date.now()-Number(d.issued||0)<=300000;}catch(e){return false;}}
async function consumeMode(req,env){
  const h={'Content-Type':'application/json','Access-Control-Allow-Origin':'*','Cache-Control':'no-store, no-cache, must-revalidate, proxy-revalidate','Pragma':'no-cache','Expires':'0'};
  const systemLocked=(await env.DZH_KV.get('dzh_maintenance'))==='1'||(await env.DZH_KV.get('dzh_killswitch'))==='1';
  let body;try{body=await req.json();}catch(e){return Response.json({success:false,message:'Invalid request'},{status:400,headers:h});}
  const key=(body.key||'').toString().trim().toUpperCase(),hwid=(body.hwid||'').toString().trim();let id=(body.mode||'').toString().trim();const clientMode=id;if(id==='holograma'){if(await env.DZH_KV.get('dzh_holoAdmin:'+key))id='holograma_mio';else if(await env.DZH_KV.get('dzh_holoAccess:'+key))id='holograma_revendedor';}
  if((await env.DZH_KV.get('dzh_maintenance'))==='1'&&!await maintenanceAllowed(env,key))return Response.json({success:false,message:'Servicio temporalmente bloqueado.'},{status:503,headers:h});
  if((await env.DZH_KV.get('dzh_killswitch'))==='1')return Response.json({success:false,message:'Servicio temporalmente bloqueado.'},{status:503,headers:h});
  if(!key||!hwid||!/^[a-z0-9_-]{1,32}$/.test(id))return Response.json({success:false,message:'Invalid request'},{status:400,headers:h});
  if(!(await requireClientSession(req,env,key,hwid)))return Response.json({success:false,message:'Session required'},{status:401,headers:h});
  const raw=await env.DZH_KV.get('dzh_key:'+key);if(!raw)return Response.json({success:false,message:'Invalid key'},{status:401,headers:h});
  const d=JSON.parse(raw);if(d.paused||secondsLeft(d)<=0||(!d.unlimitedDevices&&d.hwid&&d.hwid!==hwid))return Response.json({success:false,message:'Unauthorized'},{status:403,headers:h});
  const modes=await modeDefinitions(env),mode=modes.find(m=>m.id===id),specialHolo=await holoAllowed(env,key,id);if(!mode||mode.accessTier!=='pro'||(d.tier!=='pro'&&!specialHolo))return Response.json({success:false,message:'Mode not eligible'},{status:403,headers:h});
  const marker='dzh_modeused:'+key+':'+id;if(mode.oneTime&&await env.DZH_KV.get(marker))return Response.json({success:true,mode:clientMode,alreadyConsumed:true},{headers:h});
  if(mode.oneTime)await env.DZH_KV.put(marker,JSON.stringify({key,id,ts:Date.now()}));
  return Response.json({success:true,mode:clientMode},{headers:h});
}

async function appChk(req,env){
  const h={'Content-Type':'application/json','Access-Control-Allow-Origin':'*'};
  let key='',hwid='',dev={},appVersion='',appBuild='';
  try{const b=await req.json();key=(b.key||b.username||b.code||'').toString().trim().toUpperCase();hwid=(b.hwid||b.device||b.udid||b.phone||'').toString().trim();dev={model:b.model||b.device_model||'',ios:b.ios||b.ios_version||''};appVersion=(b.app_version||b.appVersion||'').toString().trim();appBuild=(b.app_build||b.appBuild||'').toString().trim();}
  catch{const t=await req.text();const p=new URLSearchParams(t);key=(p.get('key')||p.get('username')||'').trim().toUpperCase();hwid=(p.get('hwid')||'').trim();appVersion=(p.get('app_version')||'').trim();appBuild=(p.get('app_build')||'').trim();}
  if(await env.DZH_KV.get('dzh_maintenance')==='1'&&!await maintenanceAllowed(env,key))return Response.json({success:false,message:'Estamos en mantenimiento. Vuelve en un rato.'},{headers:h});
  if(!key)return Response.json({success:false,message:'Ingresa una key.'},{headers:h});
  if(!hwid)return Response.json({success:false,message:'HWID requerido. El dispositivo no fue identificado.'},{headers:h});
  if(!(await allowedAppBuild(env,appBuild)))return Response.json({success:false,error_code:'VERSION_UNAVAILABLE',message:'Versión no disponible.'},{headers:h});
  const ban=await env.DZH_KV.get('ban:'+hwid);
  if(ban)return Response.json({success:false,message:'Este dispositivo está bloqueado. Contacta al soporte.'},{headers:h});
  if(await env.DZH_KV.get('dzh_killswitch')==='1')return Response.json({success:false,message:'Servicio suspendido temporalmente por mantenimiento de seguridad. Vuelve más tarde.'},{headers:h});
  try{if(await env.DZH_KV.get('dzh_block_vpn')==='1'){const org=(req.cf&&req.cf.asOrganization)||'';if(isVPN(org))return Response.json({success:false,message:'Detectamos una VPN o proxy. Desactívala para continuar.'},{headers:h});}}catch(e){}
  const raw=await env.DZH_KV.get('dzh_key:'+key);
  if(!raw)return Response.json({success:false,message:'Key incorrecta. Verifica que la escribiste bien.'},{headers:h});
  const d=JSON.parse(raw);
  if(d.paused)return Response.json({success:false,message:'Tu key está pausada temporalmente.'+(d.pauseReason||d.notice?' '+(d.pauseReason||d.notice):' Contacta al soporte.')},{headers:h});
  if(d.vendor){const vr=await env.DZH_KV.get('dzh_vendor:'+d.vendor);if(vr&&!JSON.parse(vr).active)return Response.json({success:false,message:'Key no disponible.'+(d.notice?' '+d.notice:' Contacta a quien te la vendió.')},{headers:h});}
  let rem=secondsLeft(d);
  if(rem<=0)return Response.json({success:false,message:'Tu key ha expirado.'+(d.notice?' '+d.notice:' Renueva para seguir usando.')},{headers:h});
  if(!d.activated){
    d.activated=Date.now();
    if(!d.unlimitedDevices){
      d.hwid=hwid;
      d.device=dev;
      d.fp=await deviceFP(hwid,dev);
    }
    d.uses=1;
  }
  else{
    if(!d.unlimitedDevices){
      const curFP=await deviceFP(hwid,dev);
      // Si la key ya tiene huella guardada, comparar huella completa. Si no (key vieja), comparar solo hwid y guardar huella.
      if(d.fp){if(d.fp!==curFP)return Response.json({success:false,message:'Esta key está bloqueada en otro dispositivo.'+(d.lockReason||d.notice?' '+(d.lockReason||d.notice):' Solicita un reset.')},{headers:h});}
      else{if(d.hwid!==hwid)return Response.json({success:false,message:'Esta key está bloqueada en otro dispositivo.'+(d.lockReason||d.notice?' '+(d.lockReason||d.notice):' Solicita un reset.')},{headers:h});d.fp=curFP;}
    }
    d.uses=(d.uses||0)+1;
  }
  await env.DZH_KV.put('dzh_key:'+key,JSON.stringify(d));
  try{const cf=req.cf||{};const cip=req.headers.get('CF-Connecting-IP')||req.headers.get('X-Forwarded-For')||'?';const org=cf.asOrganization||'';const vpn=isVPN(org);const ipInfo={key,ip:cip,city:cf.city||'?',region:cf.region||'',country:cf.country||'?',org,vpn,ts:Date.now()};await env.DZH_KV.put('dzh_cip:'+key,JSON.stringify(ipInfo));}catch(e){}
  rem=secondsLeft(d);
  const expire=d.activated+durationSecondsOf(d)*1000;
  const secret=env.DZ_SIGN_SECRET||'';
  const signature=await hmacHex(secret,key+'|'+rem+'|'+expire);
  const resource_key=await hmacHex(secret,'res:'+key);
  let notice=(d.notice||'').toString();
  if(!notice){try{const g=await env.DZH_KV.get('global_notice');if(g)notice=g;}catch(e){}}
  const modesRaw=await env.DZH_KV.get('dzh_app_modes');
  const tier=d.tier==='pro'?'pro':'basic';
  let modes=[];
  if(modesRaw){try{const x=JSON.parse(modesRaw);if(Array.isArray(x)){modes=[];for(const m of x){const enabledMax=typeof m.enabledMax==='boolean'?m.enabledMax:m.enabled!==false;const enabledNormal=typeof m.enabledNormal==='boolean'?m.enabledNormal:m.enabled!==false;if(!enabledMax&&!enabledNormal)continue;const holoGrant=m.id==='holograma_mio'?await env.DZH_KV.get('dzh_holoAdmin:'+key):m.id==='holograma_revendedor'?await env.DZH_KV.get('dzh_holoAccess:'+key):m.id==='holograma'&&await hasHologramAccess(env,key);if(tier!=='pro'&&m.accessTier==='pro'&&!holoGrant)continue;if(m.oneTime&&await env.DZH_KV.get('dzh_modeused:'+key+':'+m.id))continue;const legacyHolo=holoGrant&&(m.id==='holograma_mio'||m.id==='holograma_revendedor');modes.push({...m,id:legacyHolo?'holograma':m.id,label:legacyHolo?(m.id==='holograma_mio'?'Holograma Davizin':'Holograma Bordes'):m.label,enabled:enabledMax||enabledNormal,enabledMax,enabledNormal,accessTier:holoGrant?'basic':m.accessTier,hologramAccess:!!holoGrant});}}}catch(e){modes=null;}}
  const client_session=await issueClientSession(env,key,hwid,appBuild,(req.headers.get('X-DZ-Installation')||''),req.headers.get('CF-Connecting-IP')||''); return Response.json({success:true,message:'Login successful.',notice,remaining_seconds:rem,data:{container_access_ready:true,remaining_seconds:rem,expire,token:'',resource_key,tier,modes,client_session,country:(req.cf&&req.cf.country)||null},signature},{headers:h});
}
async function appUpd(){return Response.json({success:true,message:'Device updated.',user_data:{phone:'any',ios:'any',remaining_seconds:999999}},{headers:{'Content-Type':'application/json','Access-Control-Allow-Origin':'*'}});
}
