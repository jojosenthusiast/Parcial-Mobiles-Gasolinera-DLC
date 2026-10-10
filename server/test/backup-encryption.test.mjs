import test from 'node:test';
import assert from 'node:assert/strict';
import { Readable, Writable } from 'node:stream';
import { pipeline } from 'node:stream/promises';
import { randomBytes } from 'node:crypto';
import { BACKUP_MAGIC, backupKey, decryptBuffer, encryptStream } from '../../scripts/backup-crypto.mjs';

async function encrypted(input,key){const chunks=[];await pipeline(Readable.from([input]),encryptStream(key),new Writable({write(chunk,_encoding,done){chunks.push(Buffer.from(chunk));done()}}));return Buffer.concat(chunks)}

test('backup encryption is authenticated, versioned and rejects any tampering',async()=>{
 const key=randomBytes(32),plain=Buffer.from('DLC recovery test payload\n');
 const encryptedFile=await encrypted(plain,key);
 assert.ok(encryptedFile.subarray(0,8).equals(BACKUP_MAGIC));
 assert.deepEqual(decryptBuffer(encryptedFile,key),plain);
 const damaged=Buffer.from(encryptedFile);damaged[25]^=1;
 assert.throws(()=>decryptBuffer(damaged,key));
});

test('backup key must decode to exactly 32 bytes',()=>{
 assert.throws(()=>backupKey('short'),/32-byte key/);
 assert.equal(backupKey(randomBytes(32).toString('base64')).length,32);
});
