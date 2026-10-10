import { spawn } from 'node:child_process';
import { createReadStream, createWriteStream } from 'node:fs';
import { mkdtemp, rm, stat } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { basename, dirname, resolve } from 'node:path';
import { pipeline } from 'node:stream/promises';
import { createDecipheriv } from 'node:crypto';
import { fileURLToPath } from 'node:url';
import { BACKUP_MAGIC, backupKey } from './backup-crypto.mjs';

function connection(raw){if(!raw)throw new Error('RESTORE_DATABASE_URL is required.');const u=new URL(raw);if(!['postgres:','postgresql:'].includes(u.protocol))throw new Error('RESTORE_DATABASE_URL must be PostgreSQL.');return{...process.env,PGHOST:u.hostname,PGPORT:u.port||'5432',PGUSER:decodeURIComponent(u.username),PGPASSWORD:decodeURIComponent(u.password),PGDATABASE:decodeURIComponent(u.pathname.slice(1)),PGSSLMODE:process.env.DATABASE_SSL_MODE||'verify-full'}}
async function decryptFile(input,output,key){
 const size=(await stat(input)).size;if(size<36)throw new Error('Backup is incomplete.');
 const fd=await import('node:fs/promises').then(m=>m.open(input,'r'));
 try{const header=Buffer.alloc(20),tag=Buffer.alloc(16);await fd.read(header,0,20,0);await fd.read(tag,0,16,size-16);
  if(!header.subarray(0,8).equals(BACKUP_MAGIC))throw new Error('Backup format is invalid.');
  const decipher=createDecipheriv('aes-256-gcm',key,header.subarray(8));decipher.setAuthTag(tag);
  await pipeline(createReadStream(input,{start:20,end:size-17}),decipher,createWriteStream(output,{flags:'wx',mode:0o600}));
 }finally{await fd.close();}
}
async function main(){
 const file=resolve(process.argv[2]||'');if(!process.argv[2])throw new Error('Pass the encrypted backup path.');
 const targetURL=process.env.RESTORE_DATABASE_URL,sourceURL=process.env.DATABASE_URL;
 if(!sourceURL)throw new Error('DATABASE_URL is required to prevent restoring onto the source database.');
 const source=new URL(sourceURL),target=new URL(targetURL||'');
 if(source.hostname===target.hostname&&source.port===target.port&&source.pathname===target.pathname)
  throw new Error('Restore target equals DATABASE_URL; choose an isolated, empty restore database.');
 const env=connection(targetURL),key=backupKey(),dir=await mkdtemp(`${tmpdir()}/dlc-restore-`),dump=resolve(dir,basename(file).replace(/\.enc$/,''));
 try{await decryptFile(file,dump,key);const child=spawn(process.env.PG_RESTORE_BIN||'pg_restore',['--exit-on-error','--single-transaction','--no-owner','--no-acl','--dbname',env.PGDATABASE,'--verbose',dump],{env,stdio:['ignore','ignore','pipe']});
  let errors='';child.stderr.on('data',x=>{if(errors.length<16000)errors+=x.toString()});const code=await new Promise((resolve,reject)=>{child.once('error',reject);child.once('close',resolve)});
  if(code!==0)throw new Error(`pg_restore exited ${code}: ${errors.replace(/password|token|secret/gi,'[REDACTED]').slice(-1000)}`);
  const sql=resolve(dirname(fileURLToPath(import.meta.url)),'verify-restore.sql');
  const verifier=spawn(process.env.PSQL_BIN||'psql',['--no-psqlrc','--set=ON_ERROR_STOP=1','--file',sql],{env,stdio:['ignore','pipe','pipe']});
  let report='',verifyError='';verifier.stdout.on('data',x=>{if(report.length<4000)report+=x.toString()});verifier.stderr.on('data',x=>{if(verifyError.length<4000)verifyError+=x.toString()});
  const verifyCode=await new Promise((resolve,reject)=>{verifier.once('error',reject);verifier.once('close',resolve)});
  if(verifyCode!==0)throw new Error(`Restore integrity checks failed: ${verifyError.slice(-1000)}`);
  console.log(report.trim()||'Restore integrity checks passed.');
 }finally{await rm(dir,{recursive:true,force:true});}
}
main().catch(error=>{console.error(error.message);process.exitCode=1;});
