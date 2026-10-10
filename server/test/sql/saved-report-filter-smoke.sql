BEGIN;
INSERT INTO organizations(id,name) VALUES('11111111-1111-4111-8111-111111111191','filter-smoke');
INSERT INTO branches(id,organization_id,code,name,zone,status)
VALUES('11111111-1111-4111-8111-111111111192','11111111-1111-4111-8111-111111111191','SMOKE73','Sucursal','central','active');
INSERT INTO users(id,organization_id,email_normalized,display_name,password_hash,status)
VALUES('11111111-1111-4111-8111-111111111193','11111111-1111-4111-8111-111111111191','filter-smoke@example.invalid','Prueba','not-a-login','active');
INSERT INTO saved_report_filters(organization_id,branch_id,user_id,name,report_type,filters)
VALUES('11111111-1111-4111-8111-111111111191','11111111-1111-4111-8111-111111111192',
 '11111111-1111-4111-8111-111111111193','Mis cortes','closed_cuts','{"from":"2026-10-01","to":"2026-10-08"}');
DO $$ BEGIN
 BEGIN
  INSERT INTO saved_report_filters(organization_id,branch_id,user_id,name,report_type,filters)
  VALUES('11111111-1111-4111-8111-111111111191','11111111-1111-4111-8111-111111111192',
   '11111111-1111-4111-8111-111111111193','Mis cortes','incidents','{}');
  RAISE EXCEPTION 'Se aceptó nombre duplicado por usuario y sucursal';
 EXCEPTION WHEN unique_violation THEN NULL;
 END;
END $$;
ROLLBACK;
SELECT count(*)::integer AS residue FROM branches WHERE code='SMOKE73';
