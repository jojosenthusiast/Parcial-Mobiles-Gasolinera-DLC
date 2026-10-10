import { createHash } from 'node:crypto';
import { readdir, readFile } from 'node:fs/promises';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

// Only for a confirmed empty database. Submit the output as ONE atomic MCP
// migration so no application table is ever exposed before RLS/revokes run.
const directory = join(dirname(fileURLToPath(import.meta.url)), '..', 'migrations');
const names = (await readdir(directory)).filter(name => /^\d{4}_[a-z0-9_]+\.sql$/.test(name)).sort();
const statements = ["SELECT pg_advisory_xact_lock(hashtext('dlc-schema-migrations'));", `DO $$ BEGIN
  IF to_regclass('public.organizations') IS NOT NULL OR to_regclass('public.schema_migrations') IS NOT NULL THEN
    RAISE EXCEPTION 'DLC bootstrap requires an empty application database';
  END IF;
END $$;`];
for (const name of names) {
  const sql = await readFile(join(directory, name), 'utf8');
  const checksum = createHash('sha256').update(sql).digest('hex');
  statements.push(`-- ${name}\n${sql}\nINSERT INTO schema_migrations(version,checksum) VALUES ('${name}','${checksum}');`);
}
process.stdout.write(statements.join('\n\n') + '\n');
