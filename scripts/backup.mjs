import { spawn } from 'node:child_process';
import { createWriteStream } from 'node:fs';
import { mkdir, readdir, stat, unlink } from 'node:fs/promises';
import { dirname, resolve, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { pipeline } from 'node:stream/promises';
import { encryptStream, backupKey } from './backup-crypto.mjs';

const root=resolve(dirname(fileURLToPath(import.meta.url)),'..');
function connection(envName) {
  const raw=process.env[envName];if(!raw)throw new Error(`${envName} is required.`);
  const u=new URL(raw);if(!['postgres:','postgresql:'].includes(u.protocol))throw new Error(`${envName} must be a PostgreSQL URL.`);
  const env={...process.env,PGHOST:u.hostname,PGPORT:u.port||'5432',PGUSER:decodeURIComponent(u.username),PGPASSWORD:decodeURIComponent(u.password),
    PGDATABASE:decodeURIComponent(u.pathname.slice(1)),PGSSLMODE:process.env.DATABASE_SSL_MODE||'verify-full'};
  if(u.searchParams.has('sslmode'))env.PGSSLMODE=u.searchParams.get('sslmode');
  return env;
}
function pgDump(env) { return spawn(process.env.PG_DUMP_BIN||'pg_dump',['--format=custom','--no-owner','--no-acl'],{env,stdio:['ignore','pipe','pipe']}); }
async function retention(directory,days) {
  const cutoff=Date.now()-days*86400000;
  for(const name of await readdir(directory)){if(!name.endsWith('.dump.enc'))continue;const path=join(directory,name);const details=await stat(path);if(details.mtimeMs<cutoff)await unlink(path);}
}
async function main(){
  backupKey();const env=connection('DATABASE_URL');const directory=resolve(process.env.BACKUP_DIRECTORY||join(root,'backups'));
  const days=Number(process.env.BACKUP_RETENTION_DAYS||30);if(!Number.isInteger(days)||days<1||days>3650)throw new Error('BACKUP_RETENTION_DAYS must be 1–3650.');
  await mkdir(directory,{recursive:true,mode:0o700});const now=new Date().toISOString().replace(/[:.]/g,'-');const file=join(directory,`dlc-${now}.dump.enc`);
  const child=pgDump(env);let stderr='';child.stderr.on('data',chunk=>{if(stderr.length<16000)stderr+=chunk.toString();});
  const exited=new Promise((resolve,reject)=>{child.once('error',reject);child.once('close',resolve)});
  try{await pipeline(child.stdout,encryptStream(),createWriteStream(file,{flags:'wx',mode:0o600}));
    const code=await exited;
    if(code!==0)throw new Error(`pg_dump exited ${code}: ${stderr.replace(/password|token|secret/gi,'[REDACTED]').slice(0,1000)}`);
    await retention(directory,days);console.log(`Encrypted backup written: ${file}`);
  }catch(error){child.kill('SIGTERM');await unlink(file).catch(()=>undefined);throw error;}
}
main().catch(error=>{console.error(error.message);process.exitCode=1;});
