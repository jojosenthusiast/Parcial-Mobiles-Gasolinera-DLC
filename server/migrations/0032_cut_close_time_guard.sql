-- Prevent closing a shift before its local operating window ends.
CREATE OR REPLACE FUNCTION close_operational_cut(org uuid,branch uuid,target_cut uuid,actor uuid,expected_version integer)
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
 IF clock_timestamp()<c.ends_at THEN
  RAISE EXCEPTION 'Cut cannot close before the operating window ends' USING ERRCODE='23514'; END IF;
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

