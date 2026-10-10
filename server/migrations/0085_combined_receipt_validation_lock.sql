-- Avoid PL/pgSQL name collisions between the local lock variable and ledger columns.
CREATE OR REPLACE FUNCTION validate_combined_internal_receipt() RETURNS trigger
 LANGUAGE plpgsql SET search_path=public,pg_temp AS $$
DECLARE fuel sales%ROWTYPE; pos sales%ROWTYPE; locked_sale_id uuid;
BEGIN
 -- Match payment-attempt locking so grouping cannot race a first collection.
 FOR locked_sale_id IN
  SELECT unnest(ARRAY[NEW.fuel_sale_id,NEW.pos_sale_id]) ORDER BY 1
 LOOP
  PERFORM pg_advisory_xact_lock(hashtextextended('sale-collection:'||locked_sale_id::text,0));
 END LOOP;
 SELECT * INTO fuel FROM sales WHERE id=NEW.fuel_sale_id AND organization_id=NEW.organization_id AND branch_id=NEW.branch_id;
 SELECT * INTO pos FROM sales WHERE id=NEW.pos_sale_id AND organization_id=NEW.organization_id AND branch_id=NEW.branch_id;
 IF fuel.id IS NULL OR pos.id IS NULL OR fuel.authorization_id IS NULL OR pos.authorization_id IS NOT NULL THEN
  RAISE EXCEPTION 'Combined internal receipt requires one fuel and one POS sale in the same branch' USING ERRCODE='23514';
 END IF;
 IF EXISTS(SELECT 1 FROM sale_collection_balances scb
     WHERE scb.id IN(NEW.fuel_sale_id,NEW.pos_sale_id) AND scb.collection_status<>'pending_collection')
   OR EXISTS(SELECT 1 FROM payment_attempts pa WHERE pa.sale_id IN(NEW.fuel_sale_id,NEW.pos_sale_id))
   OR EXISTS(SELECT 1 FROM prepayment_allocations allocation WHERE allocation.sale_id=NEW.fuel_sale_id)
   OR EXISTS(SELECT 1 FROM prepayment_advances advance WHERE advance.authorization_id=fuel.authorization_id)
   OR EXISTS(SELECT 1 FROM store_returns r JOIN sale_lines l ON l.id=r.sale_line_id WHERE l.sale_id=NEW.pos_sale_id) THEN
  RAISE EXCEPTION 'Sales with previous collection activity cannot be grouped' USING ERRCODE='23514';
 END IF;
 RETURN NEW;
END; $$;
REVOKE ALL ON FUNCTION validate_combined_internal_receipt() FROM PUBLIC,anon,authenticated,service_role;
