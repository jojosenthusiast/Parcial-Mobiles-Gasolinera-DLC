import { createServer } from 'node:http';
import { readFile } from 'node:fs/promises';
import { createCipheriv, createDecipheriv, randomBytes, randomUUID, timingSafeEqual } from 'node:crypto';
import { extname, join, normalize } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = fileURLToPath(new URL('./public/', import.meta.url));
const port = Number(process.env.PORT || 4173);
const host = process.env.HOST || '127.0.0.1';
const apiBase = new URL(process.env.WEB_API_BASE_URL || 'http://127.0.0.1:4000/api/v1');
const production = process.env.NODE_ENV === 'production';
const key = process.env.WEB_SESSION_KEY;
if (!key || Buffer.byteLength(key) < 32) throw new Error('WEB_SESSION_KEY debe contener al menos 32 bytes aleatorios.');
if (production && apiBase.protocol !== 'https:') throw new Error('WEB_API_BASE_URL debe usar HTTPS en producción.');
if (!production && !['https:', 'http:'].includes(apiBase.protocol)) throw new Error('WEB_API_BASE_URL inválida.');
const encryptionKey = Buffer.from(key).subarray(0, 32);
const mime = { '.html':'text/html; charset=utf-8', '.js':'text/javascript; charset=utf-8', '.css':'text/css; charset=utf-8', '.svg':'image/svg+xml', '.png':'image/png', '.ico':'image/x-icon', '.webp':'image/webp' };
const binaryTypes = new Set(['.png', '.ico', '.webp']);
const cookieSecure = production ? '; Secure' : '';
const refreshFlights = new Map();
const securityHeaders = {'X-Content-Type-Options':'nosniff','X-Frame-Options':'DENY','Referrer-Policy':'no-referrer',...(production?{'Strict-Transport-Security':'max-age=31536000; includeSubDomains'}:{})};
const publicAuthRoutes = new Map([['/auth/activate','auth/activate'],['/auth/password-reset/complete','auth/password-reset/complete']]);

function cookies(req) {
  return Object.fromEntries((req.headers.cookie || '').split(';').map(v => v.trim()).filter(Boolean)
    .map(v => { const i=v.indexOf('='); return [v.slice(0,i), decodeURIComponent(v.slice(i+1))]; }));
}
function seal(value) {
  const iv=randomBytes(12), cipher=createCipheriv('aes-256-gcm',encryptionKey,iv);
  const body=Buffer.concat([cipher.update(JSON.stringify(value)),cipher.final()]);
  return Buffer.concat([iv,cipher.getAuthTag(),body]).toString('base64url');
}
function open(value) {
  const b=Buffer.from(value,'base64url'); if(b.length<29) throw new Error('Invalid session');
  const decipher=createDecipheriv('aes-256-gcm',encryptionKey,b.subarray(0,12));
  decipher.setAuthTag(b.subarray(12,28));
  return JSON.parse(Buffer.concat([decipher.update(b.subarray(28)),decipher.final()]).toString());
}
function send(res,status,body,headers={}) {
  const data=typeof body==='string'?body:JSON.stringify(body);
  res.writeHead(status,{'Content-Type':typeof body==='string'?'text/plain; charset=utf-8':'application/json; charset=utf-8',
    'Cache-Control':'no-store',...securityHeaders,...headers});res.end(data);
}
function setSession(res,tokens) {
  const expiry=Date.parse(tokens.accessExpiresAt||'')||Date.now()+5*60_000;
  const value=seal({...tokens,expires:expiry});
  res.setHeader('Set-Cookie',`dlc_session=${encodeURIComponent(value)}; HttpOnly; Path=/; SameSite=Lax; Max-Age=43200${cookieSecure}`);
}
function clearSession(res) { res.setHeader('Set-Cookie',`dlc_session=; HttpOnly; Path=/; SameSite=Lax; Max-Age=0${cookieSecure}`); }
function csrfValid(req) {
  const header=req.headers['x-csrf-token']; const cookie=cookies(req).dlc_csrf;
  if(typeof header!=='string'||!cookie) return false;
  const a=Buffer.from(header),b=Buffer.from(cookie); return a.length===b.length&&timingSafeEqual(a,b);
}
async function body(req,limit=64*1024) {
  const chunks=[];let size=0;for await(const chunk of req){size+=chunk.length;if(size>limit)throw Object.assign(new Error('Solicitud demasiado grande'),{status:413});chunks.push(chunk);}
  const raw=Buffer.concat(chunks).toString();return raw?JSON.parse(raw):{};
}
async function upstream(path,method='GET',accessToken, payload) {
  const target=new URL(path.replace(/^\/+/,''),apiBase.href.replace(/\/?$/,'/'));
  if(target.origin!==apiBase.origin||!target.pathname.startsWith(apiBase.pathname.replace(/\/$/,'')+'/')) throw new Error('Ruta API inválida');
  const response=await fetch(target,{method,headers:{...(accessToken?{Authorization:`Bearer ${accessToken}`} : {}),...(payload?{'Content-Type':'application/json'}:{}),...(!['GET','HEAD'].includes(method)?{'X-Request-Id':randomUUID()}: {})},body:payload?JSON.stringify(payload):undefined,signal:AbortSignal.timeout(20_000)});
  const type=response.headers.get('content-type')||'';
  return {response, data:type.includes('json')?await response.json():Buffer.from(await response.arrayBuffer()),type};
}
async function sessionFor(req,res) {
  const raw=cookies(req).dlc_session;if(!raw) return null;
  let session;try{session=open(raw);}catch{clearSession(res);return null;}
  if(session.expires<Date.now()+30_000){
    if(!session.refreshToken){clearSession(res);return null;}
    let flight=refreshFlights.get(session.refreshToken);
    if(!flight||flight.expiresAt<Date.now()){
      const promise=(async()=>{const refreshed=await upstream('auth/refresh','POST',null,{refreshToken:session.refreshToken});
        if(!refreshed.response.ok)return null;return refreshed.data.data||refreshed.data;})();
      flight={promise,expiresAt:Date.now()+60_000};refreshFlights.set(session.refreshToken,flight);
      const expiry=setTimeout(()=>{if(refreshFlights.get(session.refreshToken)===flight)refreshFlights.delete(session.refreshToken);},60_000);expiry.unref();
    }
    const refreshed=await flight.promise;
    if(!refreshed){refreshFlights.delete(session.refreshToken);clearSession(res);return null;}session=refreshed;setSession(res,session);
  }
  return session;
}
function pathSafe(name){const path=normalize(name).replace(/^([./\\]|\.\.[/\\])+/g,'');return join(root,path||'index.html');}

const server=createServer(async(req,res)=>{
 try{
  const url=new URL(req.url,'http://localhost');
  if(req.method==='GET'&&url.pathname==='/healthz')return send(res,200,{ok:true});
  if(req.method==='GET'&&url.pathname==='/csrf'){
   const token=randomBytes(24).toString('base64url');res.setHeader('Set-Cookie',`dlc_csrf=${token}; Path=/; SameSite=Strict; Max-Age=3600${cookieSecure}`);return send(res,200,{csrfToken:token});
  }
  if(url.pathname==='/login'&&req.method==='POST'){
   if(!csrfValid(req))return send(res,403,{message:'Token CSRF inválido.'});
   const input=await body(req);if(typeof input.email!=='string'||typeof input.password!=='string')return send(res,400,{message:'Correo y contraseña son obligatorios.'});
   const result=await upstream('auth/login','POST',null,{email:input.email,password:input.password,deviceLabel:'DLC Web'});
   if(!result.response.ok)return send(res,result.response.status,result.data);
   const tokens=result.data.data||result.data;setSession(res,tokens);
   return send(res,200,{authenticated:true});
  }
  if(publicAuthRoutes.has(url.pathname)&&req.method==='POST'){
   if(!csrfValid(req))return send(res,403,{message:'Token CSRF inválido.'});
   const input=await body(req);if(typeof input.token!=='string'||typeof input.password!=='string'||input.token.length<32||input.token.length>200)return send(res,400,{message:'Token y contraseña son obligatorios.'});
   const result=await upstream(publicAuthRoutes.get(url.pathname),'POST',null,{token:input.token,password:input.password});
   return send(res,result.response.status,result.data);
  }
  if(url.pathname==='/logout'&&req.method==='POST'){
   if(!csrfValid(req))return send(res,403,{message:'Token CSRF inválido.'});
   const session=await sessionFor(req,res);if(session?.accessToken)await upstream('auth/logout','POST',session.accessToken).catch(()=>undefined);
   clearSession(res);return send(res,200,{authenticated:false});
  }
  if(url.pathname.startsWith('/api/')){
   if(!['GET','POST','PATCH','PUT','DELETE'].includes(req.method))return send(res,405,{message:'Método no permitido.'},{Allow:'GET, POST, PATCH, PUT, DELETE'});
   if(req.method!=='GET'&&!csrfValid(req))return send(res,403,{message:'Token CSRF inválido.'});
   const session=await sessionFor(req,res);if(!session?.accessToken)return send(res,401,{message:'Inicia sesión nuevamente.'});
   const apiPath=url.pathname.slice('/api/'.length);
   if(!apiPath.startsWith('v1/'))return send(res,404,{message:'Ruta no encontrada.'});
   const relativePath=apiPath.slice(3)+url.search;
   const input=['GET','DELETE'].includes(req.method)?undefined:await body(req);
   const result=await upstream(relativePath,req.method,session.accessToken,input);
   if(!result.response.ok)return send(res,result.response.status,result.data);
   if(!result.type.includes('json')){
    res.writeHead(result.response.status,{'Content-Type':result.type,'Content-Disposition':result.response.headers.get('content-disposition')||'attachment','Cache-Control':'private, no-store',...securityHeaders});return res.end(result.data);
   }
   return send(res,result.response.status,result.data);
  }
  if(req.method==='GET'){
   const name=url.pathname==='/'?'index.html':url.pathname.slice(1);const file=pathSafe(name);
   const data=await readFile(file);
   if(binaryTypes.has(extname(file))){res.writeHead(200,{'Content-Type':mime[extname(file)],'Cache-Control':'public, max-age=3600',...securityHeaders});return res.end(data);}
   return send(res,200,data.toString(),{'Content-Type':mime[extname(file)]||'application/octet-stream',
    'Content-Security-Policy':"default-src 'self'; script-src 'self'; style-src 'self'; img-src 'self' data:; connect-src 'self'; base-uri 'none'; frame-ancestors 'none'; form-action 'self'"});
  }
  return send(res,404,{message:'Ruta no encontrada.'});
 }catch(error){return send(res,error.status||502,{message:error.status?error.message:'No se pudo completar la solicitud.',detail:production?undefined:String(error?.message||error)});}
});
server.listen(port,host,()=>console.log(`DLC web escuchando en ${host}:${port}`));
