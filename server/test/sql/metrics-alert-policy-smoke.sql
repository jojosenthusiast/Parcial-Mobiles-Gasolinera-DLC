BEGIN;
INSERT INTO organizations(id,name)
VALUES('11111111-1111-4111-8111-111111111171','metrics-smoke');
INSERT INTO branches(id,organization_id,code,name,zone,status)
VALUES('11111111-1111-4111-8111-111111111172','11111111-1111-4111-8111-111111111171','SMOKE71','Alerta de prueba','central','active');
INSERT INTO branch_inventory_alert_policies(branch_id,organization_id,warning_percent,critical_percent)
VALUES('11111111-1111-4111-8111-111111111172','11111111-1111-4111-8111-111111111171',25,12);
DO $$ BEGIN
  BEGIN
    UPDATE branch_inventory_alert_policies SET critical_percent=30
    WHERE branch_id='11111111-1111-4111-8111-111111111172';
    RAISE EXCEPTION 'El umbral crítico superó el aviso';
  EXCEPTION WHEN check_violation THEN NULL;
  END;
  IF (SELECT critical_percent FROM branch_inventory_alert_policies
      WHERE branch_id='11111111-1111-4111-8111-111111111172')<>12 THEN
    RAISE EXCEPTION 'El rechazo modificó la política vigente';
  END IF;
END $$;
ROLLBACK;
SELECT count(*)::integer AS residue FROM branches WHERE code='SMOKE71';
