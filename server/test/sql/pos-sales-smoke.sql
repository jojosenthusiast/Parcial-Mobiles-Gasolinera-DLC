DO $tests$
DECLARE org uuid:=gen_random_uuid(); org2 uuid:=gen_random_uuid(); branch uuid:=gen_random_uuid(); branch2 uuid:=gen_random_uuid(); actor uuid:=gen_random_uuid();
 product uuid:=gen_random_uuid(); unknown_product uuid:=gen_random_uuid(); service uuid:=gen_random_uuid();
 offer uuid:=gen_random_uuid(); unknown_offer uuid:=gen_random_uuid(); service_offer uuid:=gen_random_uuid();
 early_lot uuid:=gen_random_uuid(); late_lot uuid:=gen_random_uuid(); unknown_lot uuid:=gen_random_uuid();
 ticket_id uuid; command uuid:=gen_random_uuid(); line_id uuid; local_date date; items jsonb; n bigint; results jsonb:='[]';
BEGIN
 BEGIN
  INSERT INTO organizations(id,name) VALUES(org,'POS transient'),(org2,'Other transient');
  INSERT INTO branches(id,organization_id,code,name,zone,status) VALUES(branch,org,'TESTPOS','Test POS','occidental','active'),(branch2,org2,'OTHER','Other','central','active');
  INSERT INTO users(id,organization_id,email_normalized,display_name,password_hash) VALUES(actor,org,actor::text||'@example.invalid','Test actor','NOT_A_LOGIN_HASH');
  SELECT (clock_timestamp() AT TIME ZONE 'America/El_Salvador')::date INTO local_date;
  INSERT INTO pos_products(id,organization_id,branch_id,sku,kind,expiry_required,created_by) VALUES
   (product,org,branch,'DRINK','store',true,actor),(unknown_product,org,branch,'OIL','store',false,actor),(service,org,branch,'WASH','service',false,actor);
  INSERT INTO pos_offer_versions(id,organization_id,branch_id,product_id,version,description,active,price_usd,service_unit_cost_usd,command_id,request_hash,created_by,correlation_id) VALUES
   (offer,org,branch,product,1,'Drink',true,2.50,NULL,gen_random_uuid(),repeat('a',64),actor,gen_random_uuid()),
   (unknown_offer,org,branch,unknown_product,1,'Oil',true,5,NULL,gen_random_uuid(),repeat('b',64),actor,gen_random_uuid()),
   (service_offer,org,branch,service,1,'Wash',true,7,3,gen_random_uuid(),repeat('c',64),actor,gen_random_uuid());
  INSERT INTO store_catalog_products(organization_id,sku,kind,category,presentation,unit,created_by)
   VALUES(org,'DRINK','store','Bebidas','Botella','unit',actor),(org,'OIL','lubricant','Lubricantes','Envase','bottle',actor);
  INSERT INTO branch_assortments(organization_id,branch_id,catalog_product_id,pos_product_id,created_by)
   SELECT org,branch,c.id,CASE WHEN c.sku='DRINK' THEN product ELSE unknown_product END,actor
   FROM store_catalog_products c WHERE c.organization_id=org;
  SET LOCAL ROLE dlc_api_runtime;
  INSERT INTO pos_stock_lots(id,organization_id,branch_id,product_id,lot_code,expires_on,quantity_received,unit_cost_usd,source_reference,command_id,request_hash,received_by,correlation_id) VALUES
   (late_lot,org,branch,product,'LATER',local_date+3,5,2,'DOC2',gen_random_uuid(),repeat('d',64),actor,gen_random_uuid()),
   (early_lot,org,branch,product,'EARLY',local_date+1,2,1,'DOC1',gen_random_uuid(),repeat('e',64),actor,gen_random_uuid()),
   (unknown_lot,org,branch,unknown_product,'UNKNOWN',NULL,3,NULL,'DOC3',gen_random_uuid(),repeat('f',64),actor,gen_random_uuid());
  IF (SELECT count(*) FROM pos_stock_movements WHERE organization_id=org AND kind='receipt')<>3 THEN RAISE EXCEPTION 'Receipt ledger missing'; END IF;
  results:=results||jsonb_build_object('test','runtime_receipts_create_one_movement_each','result','PASS');
  items:=jsonb_build_array(jsonb_build_object('productId',product,'offerVersionId',offer,'quantity','3'),jsonb_build_object('productId',service,'offerVersionId',service_offer,'quantity','1'));
  ticket_id:=post_pos_sale(org,branch,actor,command,repeat('1',64),items,gen_random_uuid());
  SET CONSTRAINTS ALL IMMEDIATE; SET CONSTRAINTS ALL DEFERRED;
  IF (SELECT total_usd FROM sales WHERE id=ticket_id)<>14.50 OR (SELECT count(*) FROM sale_lines WHERE sale_id=ticket_id)<>2 THEN RAISE EXCEPTION 'Wrong multi-line total'; END IF;
  results:=results||jsonb_build_object('test','multiline_store_service_total','result','PASS');
  IF (SELECT sum(delta_units) FROM pos_stock_movements WHERE lot_id=early_lot)<>0 OR (SELECT sum(delta_units) FROM pos_stock_movements WHERE lot_id=late_lot)<>4 THEN RAISE EXCEPTION 'FEFO wrong'; END IF;
  results:=results||jsonb_build_object('test','fefo_earlier_expiry_consumed_first','result','PASS');
  IF (SELECT cost_usd FROM sale_lines WHERE sale_id=ticket_id AND kind='store')<>4 OR (SELECT cost_usd FROM sale_lines WHERE sale_id=ticket_id AND kind='service')<>3 THEN RAISE EXCEPTION 'Wrong captured cost'; END IF;
  results:=results||jsonb_build_object('test','store_lot_and_service_cost_snapshots','result','PASS');
  SELECT count(*) INTO n FROM pos_stock_movements WHERE organization_id=org;
  IF post_pos_sale(org,branch,actor,command,repeat('1',64),items,gen_random_uuid())<>ticket_id OR (SELECT count(*) FROM pos_stock_movements WHERE organization_id=org)<>n THEN RAISE EXCEPTION 'Replay posted twice'; END IF;
  results:=results||jsonb_build_object('test','command_replay_no_second_stock_outflow','result','PASS');
  IF (SELECT count(*) FROM inventory_movements WHERE organization_id=org)<>0 THEN RAISE EXCEPTION 'Touched tank inventory'; END IF;
  results:=results||jsonb_build_object('test','pos_does_not_touch_fuel_inventory','result','PASS');
  IF EXISTS(SELECT 1 FROM sales s LEFT JOIN sale_tax_snapshots t ON t.sale_id=s.id WHERE s.id=ticket_id AND (s.tax_usd IS NOT NULL OR s.net_usd IS NOT NULL OR t.id IS NOT NULL)) THEN RAISE EXCEPTION 'Invented store tax'; END IF;
  results:=results||jsonb_build_object('test','store_tax_remains_unconfigured','result','PASS');
  SELECT count(*) INTO n FROM (SELECT p.id,p.sku,p.kind,p.expiry_required AS "expiryRequired",o.id AS "offerVersionId",o.version,o.description,o.active,o.price_usd::text AS "priceUsd",
   CASE WHEN false THEN o.service_unit_cost_usd::text END AS "serviceUnitCostUsd",o.created_at AS "updatedAt",
   coalesce(stock.available,0)::text AS "availableUnits",coalesce(stock.expired,0)::text AS "expiredUnits"
   FROM pos_products p JOIN LATERAL(SELECT * FROM pos_offer_versions WHERE product_id=p.id ORDER BY version DESC LIMIT 1)o ON true
   LEFT JOIN LATERAL(SELECT sum(b.balance) FILTER(WHERE b.expires_on IS NULL OR b.expires_on>=(clock_timestamp() AT TIME ZONE br.timezone)::date) AS available,
    sum(b.balance) FILTER(WHERE b.expires_on<(clock_timestamp() AT TIME ZONE br.timezone)::date) AS expired
    FROM (SELECT l.expires_on,coalesce(sum(m.delta_units),0) AS balance FROM pos_stock_lots l LEFT JOIN pos_stock_movements m ON m.lot_id=l.id WHERE l.product_id=p.id GROUP BY l.id) b
    JOIN branches br ON br.id=p.branch_id) stock ON true
   WHERE p.organization_id=org AND p.branch_id=branch AND (NULL::text IS NULL OR p.sku ILIKE '%'||NULL||'%' OR o.description ILIKE '%'||NULL||'%')
   AND ('store'::text IS NULL OR p.kind='store') AND (NULL::uuid IS NULL OR p.id>NULL) AND (false OR o.active) AND (NULL::uuid IS NULL OR p.id=NULL) ORDER BY p.id LIMIT 26) checked;
  IF n<>2 THEN RAISE EXCEPTION 'Catalog filtering lost branch products'; END IF;
  results:=results||jsonb_build_object('test','actual_catalog_query_filters_and_aggregates_stock','result','PASS');
  SELECT count(*) INTO n FROM (SELECT s.id,s.authorization_id AS "authorizationId",cb.collection_status AS status,s.total_usd::text AS "totalUsd",s.currency,s.receipt_type AS "receiptType",
      COALESCE(t.result->>'status',s.tax_status) AS "taxStatus",s.occurred_at AS "occurredAt",s.occurred_at::text AS "cursorAt",l.description,l.quantity_l::text AS "quantityL",l.line_count AS "lineCount"
    FROM sales s JOIN LATERAL(SELECT string_agg(description,' · ' ORDER BY line_number) AS description,
      CASE WHEN count(*)=1 AND min(kind)='fuel' THEN sum(quantity_l) END AS quantity_l,count(*)::int AS line_count FROM sale_lines WHERE sale_id=s.id) l ON true
    LEFT JOIN sale_tax_snapshots t ON t.sale_id=s.id JOIN sale_collection_balances cb ON cb.id=s.id
    WHERE s.organization_id=org AND s.branch_id=branch AND (NULL::text IS NULL OR l.description ILIKE '%'||NULL||'%' OR s.id::text=NULL)
      AND (NULL::timestamptz IS NULL OR (s.occurred_at,s.id)<(NULL::timestamptz,NULL::uuid))
    ORDER BY s.occurred_at DESC,s.id DESC LIMIT 26) checked WHERE "lineCount"=2 AND "quantityL" IS NULL;
  IF n<>1 THEN RAISE EXCEPTION 'Multiline history duplicates tickets or fabricates liters'; END IF;
  results:=results||jsonb_build_object('test','actual_history_query_one_row_per_ticket','result','PASS');
  PERFORM post_pos_sale(org,branch,actor,gen_random_uuid(),repeat('2',64),jsonb_build_array(jsonb_build_object('productId',unknown_product,'offerVersionId',unknown_offer,'quantity','1')),gen_random_uuid());
  SET CONSTRAINTS ALL IMMEDIATE; SET CONSTRAINTS ALL DEFERRED;
  IF EXISTS(SELECT 1 FROM sale_lines WHERE pos_product_id=unknown_product AND (cost_usd IS NOT NULL OR cost_quality<>'unknown')) THEN RAISE EXCEPTION 'Unknown cost invented'; END IF;
  results:=results||jsonb_build_object('test','unknown_lot_cost_is_null_not_retail_price','result','PASS');
  BEGIN
   PERFORM post_pos_sale(org,branch,actor,command,repeat('3',64),items,gen_random_uuid());RAISE EXCEPTION 'FAIL' USING ERRCODE='Z0002';
  EXCEPTION WHEN check_violation THEN results:=results||jsonb_build_object('test','changed_command_rejected','result','PASS'); END;
  BEGIN
   PERFORM post_pos_sale(org,branch,actor,gen_random_uuid(),repeat('4',64),jsonb_build_array(jsonb_build_object('productId',product,'offerVersionId',offer,'quantity','99')),gen_random_uuid());RAISE EXCEPTION 'FAIL' USING ERRCODE='Z0002';
  EXCEPTION WHEN check_violation THEN results:=results||jsonb_build_object('test','insufficient_stock_rolls_back','result','PASS'); END;
  IF (SELECT count(*) FROM sales WHERE organization_id=org)<>2 THEN RAISE EXCEPTION 'Failed sale persisted'; END IF;
  BEGIN
   PERFORM post_pos_sale(org,branch,actor,gen_random_uuid(),repeat('4',64),jsonb_build_array(jsonb_build_object('productId',product,'offerVersionId',offer,'quantity','0.5')),gen_random_uuid());RAISE EXCEPTION 'FAIL' USING ERRCODE='Z0002';
  EXCEPTION WHEN check_violation THEN results:=results||jsonb_build_object('test','store_fraction_rejected','result','PASS'); END;
  BEGIN
   PERFORM post_pos_sale(org,branch,actor,gen_random_uuid(),repeat('4',64),jsonb_build_array(items->0,items->0),gen_random_uuid());RAISE EXCEPTION 'FAIL' USING ERRCODE='Z0002';
  EXCEPTION WHEN check_violation THEN results:=results||jsonb_build_object('test','duplicate_product_rejected','result','PASS'); END;
  BEGIN
   PERFORM post_pos_sale(org2,branch2,actor,gen_random_uuid(),repeat('4',64),items,gen_random_uuid());RAISE EXCEPTION 'FAIL' USING ERRCODE='Z0002';
  EXCEPTION WHEN check_violation THEN results:=results||jsonb_build_object('test','foreign_tenant_products_rejected','result','PASS'); END;
  BEGIN
   INSERT INTO pos_stock_lots(organization_id,branch_id,product_id,lot_code,expires_on,quantity_received,source_reference,command_id,request_hash,received_by,correlation_id)
   VALUES(org,branch,product,'EXPIRED',local_date-1,2,'DOC4',gen_random_uuid(),repeat('a',64),actor,gen_random_uuid());RAISE EXCEPTION 'FAIL' USING ERRCODE='Z0002';
  EXCEPTION WHEN check_violation THEN results:=results||jsonb_build_object('test','expired_receipt_rejected','result','PASS'); END;
  BEGIN
   INSERT INTO pos_stock_lots(organization_id,branch_id,product_id,lot_code,quantity_received,source_reference,command_id,request_hash,received_by,correlation_id)
   VALUES(org,branch,product,'UNDATED',2,'DOC4',gen_random_uuid(),repeat('a',64),actor,gen_random_uuid());RAISE EXCEPTION 'FAIL' USING ERRCODE='Z0002';
  EXCEPTION WHEN check_violation THEN results:=results||jsonb_build_object('test','required_expiry_enforced','result','PASS'); END;
  BEGIN
   INSERT INTO pos_stock_lots(organization_id,branch_id,product_id,lot_code,quantity_received,source_reference,command_id,request_hash,received_by,correlation_id)
   VALUES(org,branch,service,'SERVICE',2,'DOC4',gen_random_uuid(),repeat('a',64),actor,gen_random_uuid());RAISE EXCEPTION 'FAIL' USING ERRCODE='Z0002';
  EXCEPTION WHEN check_violation THEN results:=results||jsonb_build_object('test','service_has_no_stock_lot','result','PASS'); END;
  BEGIN
   INSERT INTO pos_stock_lots(organization_id,branch_id,product_id,lot_code,quantity_received,source_reference,command_id,request_hash,received_by,correlation_id)
   VALUES(org,branch,unknown_product,'UNKNOWN',3,'DOC3',gen_random_uuid(),repeat('a',64),actor,gen_random_uuid());RAISE EXCEPTION 'FAIL' USING ERRCODE='Z0002';
  EXCEPTION WHEN unique_violation THEN results:=results||jsonb_build_object('test','same_document_lot_not_received_twice','result','PASS'); END;
  BEGIN
   UPDATE pos_stock_lots SET unit_cost_usd=99 WHERE id=early_lot;RAISE EXCEPTION 'FAIL' USING ERRCODE='Z0002';
  EXCEPTION WHEN insufficient_privilege THEN results:=results||jsonb_build_object('test','runtime_cannot_rewrite_lot_cost','result','PASS'); END;
  INSERT INTO pos_offer_versions(organization_id,branch_id,product_id,version,description,active,price_usd,command_id,request_hash,created_by,correlation_id)
  VALUES(org,branch,product,2,'Drink new price',true,9,gen_random_uuid(),repeat('a',64),actor,gen_random_uuid());
  IF (SELECT total_usd FROM sales WHERE id=ticket_id)<>14.5 OR (SELECT description FROM sale_lines WHERE sale_id=ticket_id AND kind='store')<>'Drink' THEN RAISE EXCEPTION 'Old ticket revalued'; END IF;
  results:=results||jsonb_build_object('test','catalog_change_preserves_old_ticket','result','PASS');
  BEGIN
   PERFORM post_pos_sale(org,branch,actor,gen_random_uuid(),repeat('4',64),jsonb_build_array(items->0),gen_random_uuid());RAISE EXCEPTION 'FAIL' USING ERRCODE='Z0002';
  EXCEPTION WHEN check_violation THEN results:=results||jsonb_build_object('test','stale_price_version_rejected','result','PASS'); END;
  INSERT INTO pos_offer_versions(organization_id,branch_id,product_id,version,description,active,price_usd,service_unit_cost_usd,command_id,request_hash,created_by,correlation_id)
  VALUES(org,branch,service,2,'Wash',false,7,3,gen_random_uuid(),repeat('a',64),actor,gen_random_uuid());
  BEGIN
   PERFORM post_pos_sale(org,branch,actor,gen_random_uuid(),repeat('4',64),jsonb_build_array(items->1),gen_random_uuid());RAISE EXCEPTION 'FAIL' USING ERRCODE='Z0002';
  EXCEPTION WHEN check_violation THEN results:=results||jsonb_build_object('test','disabled_offer_rejected','result','PASS'); END;
  SELECT id INTO line_id FROM sale_lines WHERE sale_id=ticket_id AND kind='store';
  BEGIN
   INSERT INTO pos_stock_movements(organization_id,branch_id,lot_id,sale_line_id,delta_units,kind) VALUES(org,branch,late_lot,line_id,-1,'sale');
   SET CONSTRAINTS ALL IMMEDIATE; RAISE EXCEPTION 'FAIL' USING ERRCODE='Z0002';
  EXCEPTION WHEN unique_violation OR check_violation THEN results:=results||jsonb_build_object('test','allocation_cannot_be_appended_twice','result','PASS'); END;
  SET CONSTRAINTS ALL IMMEDIATE; RESET ROLE;
  BEGIN
   UPDATE sales SET total_usd=1 WHERE id=ticket_id;RAISE EXCEPTION 'FAIL' USING ERRCODE='Z0002';
  EXCEPTION WHEN SQLSTATE '55000' THEN results:=results||jsonb_build_object('test','ticket_is_immutable','result','PASS'); END;
  BEGIN
   SET LOCAL ROLE anon; PERFORM * FROM pos_products;RAISE EXCEPTION 'FAIL' USING ERRCODE='Z0002';
  EXCEPTION WHEN insufficient_privilege THEN results:=results||jsonb_build_object('test','anonymous_client_has_no_catalog_access','result','PASS'); END;
  BEGIN
   SET LOCAL ROLE authenticated; PERFORM post_pos_sale(org,branch,actor,gen_random_uuid(),repeat('a',64),items,gen_random_uuid());RAISE EXCEPTION 'FAIL' USING ERRCODE='Z0002';
  EXCEPTION WHEN insufficient_privilege THEN results:=results||jsonb_build_object('test','direct_client_cannot_post_sale','result','PASS'); END;
  IF EXISTS(SELECT 1 FROM pg_class WHERE relname IN('pos_products','pos_offer_versions','pos_stock_lots','pos_stock_movements') AND NOT relrowsecurity) THEN RAISE EXCEPTION 'Missing RLS'; END IF;
  results:=results||jsonb_build_object('test','new_tables_have_rls','result','PASS');
  RAISE EXCEPTION 'rollback fixtures' USING ERRCODE='Z0001';
 EXCEPTION WHEN SQLSTATE 'Z0001' THEN NULL;
 END;
 IF EXISTS(SELECT 1 FROM organizations WHERE id=org OR id=org2) THEN RAISE EXCEPTION 'Fixture rollback failed'; END IF;
 results:=results||jsonb_build_object('test','fixtures_rolled_back','result','PASS');
 PERFORM set_config('dlc.test_results',results::text,false);
END; $tests$;
SELECT current_setting('dlc.test_results')::jsonb AS tests;
