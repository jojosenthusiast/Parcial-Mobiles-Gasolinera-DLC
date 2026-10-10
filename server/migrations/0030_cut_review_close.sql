-- Separate reviewer and immutable close; neither path posts inventory again.
CREATE TABLE operational_cut_reviews (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),cut_id uuid NOT NULL UNIQUE,
 preparation_id uuid NOT NULL UNIQUE REFERENCES operational_cut_preparations(id),
 organization_id uuid NOT NULL,branch_id uuid NOT NULL,prepared_version integer NOT NULL,
 decision text NOT NULL CHECK(decision='approved'),reason text NOT NULL CHECK(length(btrim(reason)) BETWEEN 8 AND 500),
 reviewed_by uuid NOT NULL,reviewed_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 FOREIGN KEY(cut_id,organization_id,branch_id) REFERENCES operational_cuts(id,organization_id,branch_id),
 FOREIGN KEY(reviewed_by,organization_id) REFERENCES users(id,organization_id)
);
CREATE TABLE operational_cut_closures (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),cut_id uuid NOT NULL UNIQUE,
 preparation_id uuid NOT NULL UNIQUE REFERENCES operational_cut_preparations(id),review_id uuid UNIQUE REFERENCES operational_cut_reviews(id),
 organization_id uuid NOT NULL,branch_id uuid NOT NULL,input_version integer NOT NULL,output_version integer NOT NULL,
 snapshot jsonb NOT NULL CHECK(jsonb_typeof(snapshot)='object'),
 closed_by uuid NOT NULL,closed_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 FOREIGN KEY(cut_id,organization_id,branch_id) REFERENCES operational_cuts(id,organization_id,branch_id),
 FOREIGN KEY(closed_by,organization_id) REFERENCES users(id,organization_id),
 CHECK(output_version=input_version+1)
);
CREATE TRIGGER operational_cut_reviews_immutable BEFORE UPDATE OR DELETE ON operational_cut_reviews
 FOR EACH ROW EXECUTE FUNCTION prevent_inventory_movement_mutation();
CREATE TRIGGER operational_cut_closures_immutable BEFORE UPDATE OR DELETE ON operational_cut_closures
 FOR EACH ROW EXECUTE FUNCTION prevent_inventory_movement_mutation();

CREATE FUNCTION review_operational_cut(org uuid,branch uuid,target_cut uuid,actor uuid,expected_version integer,review_reason text)
 RETURNS TABLE(review_id uuid,version integer)
 LANGUAGE plpgsql SET search_path=public,pg_temp AS $$
DECLARE c operational_cuts%ROWTYPE; prep operational_cut_preparations%ROWTYPE; rid uuid;
BEGIN
 SELECT oc.* INTO c FROM operational_cuts oc WHERE oc.id=target_cut AND oc.organization_id=org AND oc.branch_id=branch FOR UPDATE;
 SELECT p.* INTO prep FROM operational_cut_preparations p WHERE p.cut_id=target_cut;
 IF c.id IS NULL OR c.status<>'inReview' OR c.version<>expected_version OR
  prep.id IS NULL OR NOT prep.review_required OR prep.output_version<>expected_version THEN
  RAISE EXCEPTION 'Review does not match the current prepared cut' USING ERRCODE='40001'; END IF;
 IF actor=prep.prepared_by OR NOT EXISTS(SELECT 1 FROM users u WHERE u.id=actor AND u.organization_id=org AND u.status='active') THEN
  RAISE EXCEPTION 'Review requires another active user' USING ERRCODE='23514'; END IF;
 INSERT INTO operational_cut_reviews(cut_id,preparation_id,organization_id,branch_id,prepared_version,decision,reason,reviewed_by)
 VALUES(target_cut,prep.id,org,branch,expected_version,'approved',review_reason,actor) RETURNING id INTO rid;
 UPDATE operational_cuts oc SET version=oc.version+1 WHERE oc.id=target_cut;
 RETURN QUERY SELECT rid,expected_version+1;
END; $$;

CREATE FUNCTION close_operational_cut(org uuid,branch uuid,target_cut uuid,actor uuid,expected_version integer)
 RETURNS TABLE(closure_id uuid,version integer,closed_at timestamptz)
 LANGUAGE plpgsql SET search_path=public,pg_temp AS $$
DECLARE c operational_cuts%ROWTYPE; prep operational_cut_preparations%ROWTYPE; review operational_cut_reviews%ROWTYPE; cid uuid; stamp timestamptz:=clock_timestamp();
BEGIN
 SELECT oc.* INTO c FROM operational_cuts oc WHERE oc.id=target_cut AND oc.organization_id=org AND oc.branch_id=branch FOR UPDATE;
 SELECT p.* INTO prep FROM operational_cut_preparations p WHERE p.cut_id=target_cut;
 SELECT r.* INTO review FROM operational_cut_reviews r WHERE r.cut_id=target_cut;
 IF c.id IS NULL OR c.version<>expected_version OR c.status NOT IN('prepared','inReview') OR prep.id IS NULL THEN
  RAISE EXCEPTION 'Cut not prepared or version changed' USING ERRCODE='40001'; END IF;
 IF (prep.review_required AND (c.status<>'inReview' OR review.id IS NULL OR review.preparation_id<>prep.id
      OR review.prepared_version<>prep.output_version OR c.version<>review.prepared_version+1))
   OR (NOT prep.review_required AND (c.status<>'prepared' OR c.version<>prep.output_version OR review.id IS NOT NULL)) THEN
  RAISE EXCEPTION 'A fresh independent review is required for this discrepancy' USING ERRCODE='23514'; END IF;
 IF NOT EXISTS(SELECT 1 FROM users u WHERE u.id=actor AND u.organization_id=org AND u.status='active') THEN
  RAISE EXCEPTION 'Inactive closer' USING ERRCODE='23514'; END IF;
 IF EXISTS(SELECT 1 FROM operational_cuts previous WHERE previous.branch_id=branch AND previous.ends_at=c.starts_at
  AND previous.status<>'closed') THEN
  RAISE EXCEPTION 'Previous contiguous cut must close first' USING ERRCODE='23514'; END IF;
 INSERT INTO operational_cut_closures(cut_id,preparation_id,review_id,organization_id,branch_id,input_version,output_version,snapshot,closed_by,closed_at)
 VALUES(target_cut,prep.id,review.id,org,branch,expected_version,expected_version+1,
  jsonb_build_object('policyId',prep.policy_id,'products',prep.product_summary,'tanks',prep.tank_summary,
    'finance',prep.financial_summary,'reviewRequired',prep.review_required,'preparedAt',prep.prepared_at,
    'reviewId',review.id,'operationalDate',c.operational_date,'slot',c.slot,'startsAt',c.starts_at,'endsAt',c.ends_at),actor,stamp)
 RETURNING id INTO cid;
 UPDATE operational_cuts oc SET status='closed',version=oc.version+1 WHERE oc.id=target_cut;
 INSERT INTO outbox_events(event_type,aggregate_type,aggregate_id,payload)
 VALUES('operational_cut.closed','operational_cut',target_cut,
  jsonb_build_object('organizationId',org,'branchId',branch,'cutId',target_cut,'closureId',cid,'closedAt',stamp));
 RETURN QUERY SELECT cid,expected_version+1,stamp;
END; $$;

-- Protect append-only evidence even if a future server mistakenly issues a direct INSERT.
CREATE FUNCTION guard_cut_evidence_insert() RETURNS trigger LANGUAGE plpgsql SET search_path=public,pg_temp AS $$
BEGIN
 IF NOT EXISTS(SELECT 1 FROM operational_cuts c WHERE c.id=NEW.cut_id AND c.status='open' AND
  c.branch_id=NEW.branch_id AND c.organization_id=NEW.organization_id) THEN
  RAISE EXCEPTION 'Cannot add evidence outside an open cut' USING ERRCODE='23514'; END IF;
 RETURN NEW;
END; $$;
CREATE TRIGGER cut_meter_insert_guard BEFORE INSERT ON operational_cut_meter_captures
 FOR EACH ROW EXECUTE FUNCTION guard_cut_evidence_insert();
CREATE TRIGGER cut_tank_insert_guard BEFORE INSERT ON operational_cut_tank_measurements
 FOR EACH ROW EXECUTE FUNCTION guard_cut_evidence_insert();

DO $$ DECLARE t text; BEGIN
 FOREACH t IN ARRAY ARRAY['operational_cut_reviews','operational_cut_closures'] LOOP
  EXECUTE format('ALTER TABLE %I ENABLE ROW LEVEL SECURITY',t);
  EXECUTE format('REVOKE ALL ON TABLE %I FROM PUBLIC,anon,authenticated,service_role',t);
  EXECUTE format('GRANT SELECT,INSERT ON TABLE %I TO dlc_api_runtime',t);
  EXECUTE format('CREATE POLICY dlc_api_select ON %I FOR SELECT TO dlc_api_runtime USING(true)',t);
  EXECUTE format('CREATE POLICY dlc_api_insert ON %I FOR INSERT TO dlc_api_runtime WITH CHECK(true)',t);
 END LOOP;
END $$;
REVOKE ALL ON FUNCTION review_operational_cut(uuid,uuid,uuid,uuid,integer,text),close_operational_cut(uuid,uuid,uuid,uuid,integer),guard_cut_evidence_insert() FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION review_operational_cut(uuid,uuid,uuid,uuid,integer,text),close_operational_cut(uuid,uuid,uuid,uuid,integer) TO dlc_api_runtime;
