import pg from 'pg';

if(process.env.LOCAL_DATABASE_SETUP!=='true')throw new Error('Set LOCAL_DATABASE_SETUP=true only for the local compose database.');
const adminURL=new URL(process.env.ADMIN_DATABASE_URL||'');
if(!['localhost','127.0.0.1','postgres'].includes(adminURL.hostname)||adminURL.pathname!=='/dlc_dev')
  throw new Error('Local runtime account setup is restricted to the local dlc_dev database.');
const password=process.env.RUNTIME_DATABASE_PASSWORD;
if(typeof password!=='string'||password.length<32)throw new Error('RUNTIME_DATABASE_PASSWORD must contain at least 32 characters.');
const pool=new pg.Pool({connectionString:adminURL.toString(),max:1,application_name:'dlc-local-runtime-setup'});
try{
 await pool.query(`DO $$ BEGIN IF NOT EXISTS(SELECT 1 FROM pg_roles WHERE rolname='dlc_api_local') THEN CREATE ROLE dlc_api_local LOGIN; END IF; END $$`);
 const command=await pool.query(`SELECT format('ALTER ROLE dlc_api_local LOGIN INHERIT NOSUPERUSER NOCREATEDB NOCREATEROLE NOBYPASSRLS PASSWORD %L', $1) AS sql`,[password]);
 await pool.query(command.rows[0].sql);
 await pool.query('GRANT dlc_api_runtime TO dlc_api_local');
 const check=await pool.query(`SELECT r.rolsuper,r.rolbypassrls,r.rolcreaterole,r.rolcreatedb,pg_has_role('dlc_api_local','dlc_api_runtime','MEMBER') AS member
  FROM pg_roles r WHERE r.rolname='dlc_api_local'`);
 const role=check.rows[0];if(!role?.member||role.rolsuper||role.rolbypassrls||role.rolcreaterole||role.rolcreatedb)throw new Error('Local runtime database role failed its privilege check.');
 process.stdout.write('Restricted local database login configured; credential was not printed.\n');
}finally{await pool.end();}
