import { createCipheriv, createDecipheriv, randomBytes } from 'node:crypto';
import { Transform } from 'node:stream';

export const BACKUP_MAGIC = Buffer.from('DLCBK001');
export function backupKey(value=process.env.BACKUP_ENCRYPTION_KEY) {
  if(!value)throw new Error('BACKUP_ENCRYPTION_KEY is required.');
  const decoded=Buffer.from(value,'base64');
  if(decoded.length!==32||decoded.toString('base64').replace(/=+$/,'')!==value.replace(/=+$/,''))
    throw new Error('BACKUP_ENCRYPTION_KEY must be a base64 encoded 32-byte key.');
  return decoded;
}
export function encryptStream(key=backupKey()) {
  const iv=randomBytes(12),cipher=createCipheriv('aes-256-gcm',key,iv);let headerSent=false;
  return new Transform({transform(chunk,_encoding,callback){
    try{if(!headerSent){this.push(Buffer.concat([BACKUP_MAGIC,iv]));headerSent=true;}this.push(cipher.update(chunk));callback();}catch(error){callback(error);}
  },flush(callback){
    try{if(!headerSent)this.push(Buffer.concat([BACKUP_MAGIC,iv]));this.push(cipher.final());this.push(cipher.getAuthTag());callback();}catch(error){callback(error);}
  }});
}
export function decryptBuffer(envelope,key=backupKey()) {
  if(envelope.length<36||!envelope.subarray(0,8).equals(BACKUP_MAGIC))throw new Error('Backup format is invalid.');
  const iv=envelope.subarray(8,20),tag=envelope.subarray(-16),body=envelope.subarray(20,-16);
  const decipher=createDecipheriv('aes-256-gcm',key,iv);decipher.setAuthTag(tag);
  return Buffer.concat([decipher.update(body),decipher.final()]);
}
