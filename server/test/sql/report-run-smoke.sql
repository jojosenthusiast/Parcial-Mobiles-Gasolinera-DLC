BEGIN;
INSERT INTO organizations(id,name) VALUES('11111111-1111-4111-8111-111111111181','report-smoke');
INSERT INTO branches(id,organization_id,code,name,zone,status)
VALUES('11111111-1111-4111-8111-111111111182','11111111-1111-4111-8111-111111111181','SMOKE72','Sucursal de prueba','central','active');
INSERT INTO users(id,organization_id,email_normalized,display_name,password_hash,status)
VALUES('11111111-1111-4111-8111-111111111183','11111111-1111-4111-8111-111111111181','report-smoke@example.invalid','Prueba','not-a-login','active');
INSERT INTO report_runs(id,organization_id,branch_id,report_type,filter_snapshot,rows_snapshot,row_count,as_of,
 timezone,unit,created_by,command_id,request_hash)
VALUES('11111111-1111-4111-8111-111111111184','11111111-1111-4111-8111-111111111181',
'11111111-1111-4111-8111-111111111182','closed_cuts','{"from":"2026-10-01"}',
'[{"operationalDate":"2026-10-01"}]',1,clock_timestamp(),
'America/El_Salvador','liter','11111111-1111-4111-8111-111111111183',
'11111111-1111-4111-8111-111111111185',repeat('a',64));
DO $$ BEGIN
 BEGIN
  UPDATE report_runs SET row_count=0 WHERE id='11111111-1111-4111-8111-111111111184';
  RAISE EXCEPTION 'Instantánea editable';
 EXCEPTION WHEN object_not_in_prerequisite_state THEN NULL;
 END;
 BEGIN
  INSERT INTO report_runs(organization_id,branch_id,report_type,filter_snapshot,rows_snapshot,row_count,as_of,
   timezone,unit,created_by,command_id,request_hash)
  VALUES('11111111-1111-4111-8111-111111111181','11111111-1111-4111-8111-111111111182',
   'closed_cuts','{}','[]',1,clock_timestamp(),'America/El_Salvador','liter',
   '11111111-1111-4111-8111-111111111183','11111111-1111-4111-8111-111111111186',repeat('b',64));
  RAISE EXCEPTION 'Conteo inconsistente aceptado';
 EXCEPTION WHEN check_violation THEN NULL;
 END;
END $$;
ROLLBACK;
SELECT count(*)::integer AS residue FROM branches WHERE code='SMOKE72';
