BEGIN;

-- Two daily cuts that do not cover 24 hours (academicLab22: morning 06:00-14:00 and evening 14:00-22:00).
-- operational_cut_profiles.day_end (NULL = legacy behaviour: the second window runs until the next day_start)
-- declares where the second window ends; the period day_end..next day_start is explicitly NOT a cut.
-- Sales, readings and stock movements recorded in that period belong to no cut window; the first cut after it
-- reconciles them (its accounting start is the previous cut's end), and meter/tank continuity is preserved
-- through previous_operational_cut(). Windows still never overlap and each branch/day/slot is unique.
-- Forward-only and idempotent. Rollback: restore the 0024/0027/0031/0032 function bodies, drop
-- previous_operational_cut and ALTER TABLE operational_cut_profiles DROP COLUMN day_end.

ALTER TABLE operational_cut_profiles ADD COLUMN IF NOT EXISTS day_end time
 CONSTRAINT operational_cut_profiles_day_end_check CHECK (day_end IS NULL OR (day_end<>day_start AND day_end<>split_at));

CREATE OR REPLACE FUNCTION validate_operational_cut_profile() RETURNS trigger LANGUAGE plpgsql SET search_path=public,pg_temp AS $$
DECLARE branch_timezone text;
BEGIN
 SELECT timezone INTO branch_timezone FROM branches WHERE id=NEW.branch_id AND organization_id=NEW.organization_id;
 IF branch_timezone IS NULL OR branch_timezone<>NEW.timezone OR NOT EXISTS(SELECT 1 FROM pg_timezone_names WHERE name=NEW.timezone) THEN
  RAISE EXCEPTION 'Cut profile needs the branch current valid timezone' USING ERRCODE='23514';
 END IF;
 IF NEW.day_end IS NOT NULL AND mod(extract(epoch FROM (NEW.day_end-NEW.day_start))::integer+86400,86400)
    <= mod(extract(epoch FROM (NEW.split_at-NEW.day_start))::integer+86400,86400) THEN
  RAISE EXCEPTION 'The evening end must fall after the split within one 24-hour day' USING ERRCODE='23514';
 END IF;
 IF EXISTS(SELECT 1 FROM operational_cuts c WHERE c.branch_id=NEW.branch_id AND c.operational_date>=NEW.effective_date) THEN
  RAISE EXCEPTION 'Cannot insert a retroactive profile over generated cuts' USING ERRCODE='23514';
 END IF;
 RETURN NEW;
END; $$;

CREATE OR REPLACE FUNCTION assert_two_cut_windows() RETURNS trigger LANGUAGE plpgsql SET search_path=public,pg_temp AS $$
DECLARE first_cut operational_cuts%ROWTYPE; second_cut operational_cuts%ROWTYPE;
BEGIN
 SELECT * INTO first_cut FROM operational_cuts WHERE branch_id=NEW.branch_id AND operational_date=NEW.operational_date AND slot=1;
 SELECT * INTO second_cut FROM operational_cuts WHERE branch_id=NEW.branch_id AND operational_date=NEW.operational_date AND slot=2;
 IF first_cut.id IS NULL OR second_cut.id IS NULL OR first_cut.ends_at<>second_cut.starts_at
   OR first_cut.profile_id<>second_cut.profile_id OR first_cut.organization_id<>second_cut.organization_id THEN
  RAISE EXCEPTION 'An operational day needs exactly two contiguous cuts' USING ERRCODE='23514';
 END IF;
 IF EXISTS(SELECT 1 FROM operational_cuts o WHERE o.branch_id=NEW.branch_id AND o.id<>NEW.id
    AND o.starts_at<NEW.ends_at AND o.ends_at>NEW.starts_at) THEN
  RAISE EXCEPTION 'Operational cut windows of a branch cannot overlap' USING ERRCODE='23514';
 END IF;
 RETURN NULL;
END; $$;

-- The cut that immediately precedes target_cut: the one ending exactly when it starts or, across a declared
-- non-cut period (profile with day_end), the second window of the previous operating day.
CREATE OR REPLACE FUNCTION previous_operational_cut(target_cut uuid) RETURNS uuid
 LANGUAGE sql STABLE SET search_path=public,pg_temp AS $$
 SELECT p.id FROM operational_cuts c
 JOIN operational_cuts p ON p.branch_id=c.branch_id AND p.organization_id=c.organization_id AND p.ends_at<=c.starts_at
 WHERE c.id=target_cut AND (p.ends_at=c.starts_at OR (c.slot=1 AND p.slot=2 AND p.operational_date=c.operational_date-1
   AND EXISTS(SELECT 1 FROM operational_cut_profiles pr WHERE pr.id=p.profile_id AND pr.day_end IS NOT NULL)))
 ORDER BY p.ends_at DESC LIMIT 1
$$;
REVOKE ALL ON FUNCTION previous_operational_cut(uuid) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION previous_operational_cut(uuid) TO dlc_api_runtime;

CREATE OR REPLACE FUNCTION generate_operational_cuts(org uuid, branch uuid, target_date date)
 RETURNS TABLE(cut_id uuid, slot smallint, starts_at timestamptz, ends_at timestamptz)
 LANGUAGE plpgsql SET search_path=public,pg_temp AS $$
DECLARE profile operational_cut_profiles%ROWTYPE; start_utc timestamptz; split_utc timestamptz; end_utc timestamptz; next_start_utc timestamptz;
BEGIN
 IF target_date IS NULL THEN RAISE EXCEPTION 'Operational date is required' USING ERRCODE='23514'; END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended('cut-windows:'||branch::text||':'||target_date::text,0));
 IF NOT EXISTS(SELECT 1 FROM branches b WHERE b.id=branch AND b.organization_id=org AND b.status='active') THEN
  RAISE EXCEPTION 'Cuts require an active branch' USING ERRCODE='23514';
 END IF;
 SELECT * INTO profile FROM operational_cut_profiles p WHERE p.organization_id=org AND p.branch_id=branch
  AND p.effective_date<=target_date ORDER BY p.effective_date DESC LIMIT 1;
 IF profile.id IS NULL THEN RAISE EXCEPTION 'Configure two cut windows before generating the day' USING ERRCODE='23514'; END IF;
 start_utc:=(target_date+profile.day_start) AT TIME ZONE profile.timezone;
 split_utc:=((target_date+CASE WHEN profile.split_at<profile.day_start THEN 1 ELSE 0 END)+profile.split_at) AT TIME ZONE profile.timezone;
 next_start_utc:=((target_date+1)+profile.day_start) AT TIME ZONE profile.timezone;
 IF profile.day_end IS NULL THEN end_utc:=next_start_utc;
 ELSE end_utc:=((target_date+CASE WHEN profile.day_end<=profile.day_start THEN 1 ELSE 0 END)+profile.day_end) AT TIME ZONE profile.timezone;
 END IF;
 IF split_utc<=start_utc OR end_utc<=split_utc OR end_utc>next_start_utc THEN RAISE EXCEPTION 'Invalid cut windows in the branch timezone' USING ERRCODE='23514'; END IF;
 IF EXISTS(SELECT 1 FROM operational_cuts c LEFT JOIN operational_cut_profiles pp ON pp.id=c.profile_id
    WHERE c.branch_id=branch AND c.operational_date=target_date-1 AND c.slot=2
    AND (c.ends_at>start_utc OR (c.ends_at<start_utc AND pp.day_end IS NULL))) OR
    EXISTS(SELECT 1 FROM operational_cuts c WHERE c.branch_id=branch AND c.operational_date=target_date+1
    AND c.slot=1 AND (c.starts_at<end_utc OR (c.starts_at>end_utc AND profile.day_end IS NULL))) THEN
  RAISE EXCEPTION 'New cut windows cannot leave an undeclared gap or overlap the neighboring operating day' USING ERRCODE='23514';
 END IF;
 INSERT INTO operational_cuts(organization_id,branch_id,operational_date,slot,profile_id,starts_at,ends_at)
 VALUES(org,branch,target_date,1,profile.id,start_utc,split_utc),
       (org,branch,target_date,2,profile.id,split_utc,end_utc)
 ON CONFLICT ON CONSTRAINT operational_cuts_branch_id_operational_date_slot_key DO NOTHING;
 IF (SELECT count(*) FROM operational_cuts c WHERE c.branch_id=branch AND c.operational_date=target_date
    AND c.profile_id=profile.id AND ((c.slot=1 AND c.starts_at=start_utc AND c.ends_at=split_utc)
      OR (c.slot=2 AND c.starts_at=split_utc AND c.ends_at=end_utc)))<>2 THEN
  RAISE EXCEPTION 'Cut windows already exist with another configuration' USING ERRCODE='23514';
 END IF;
 RETURN QUERY SELECT c.id,c.slot,c.starts_at,c.ends_at FROM operational_cuts c
  WHERE c.organization_id=org AND c.branch_id=branch AND c.operational_date=target_date ORDER BY c.slot;
END; $$;

CREATE OR REPLACE FUNCTION capture_cut_meter(org uuid, branch uuid, target_cut uuid, target_nozzle uuid, target_reading uuid,
 actor uuid, expected_version integer)
 RETURNS TABLE(cut_id uuid,nozzle_id uuid,version integer,opening_value numeric,closing_value numeric,measured_l numeric)
 LANGUAGE plpgsql SET search_path=public,pg_temp AS $$
DECLARE c operational_cuts%ROWTYPE; r nozzle_meter_readings%ROWTYPE; prior operational_cut_meter_captures%ROWTYPE;
 starting numeric(24,9); liters numeric(24,9);
BEGIN
 SELECT * INTO c FROM operational_cuts WHERE id=target_cut AND branch_id=branch AND organization_id=org FOR UPDATE;
 IF c.id IS NULL OR c.status<>'open' OR c.version<>expected_version THEN
  RAISE EXCEPTION 'Cut not open or version changed' USING ERRCODE='40001'; END IF;
 IF NOT EXISTS(SELECT 1 FROM operational_cut_nozzles n WHERE n.cut_id=target_cut AND n.nozzle_id=target_nozzle AND n.participation='expected') THEN
  RAISE EXCEPTION 'Nozzle not expected in this cut' USING ERRCODE='23514'; END IF;
 SELECT mr.* INTO r FROM nozzle_meter_readings mr WHERE mr.id=target_reading AND mr.nozzle_id=target_nozzle AND
  mr.branch_id=branch AND mr.organization_id=org;
 IF r.id IS NULL OR r.reading_type<>'regular' OR r.captured_at<c.starts_at OR r.captured_at>c.ends_at+interval '24 hours' THEN
  RAISE EXCEPTION 'Regular meter reading outside cut capture period' USING ERRCODE='23514'; END IF;
 IF NOT EXISTS(SELECT 1 FROM users WHERE id=actor AND organization_id=org AND status='active') THEN
  RAISE EXCEPTION 'Cut actor inactive' USING ERRCODE='23514'; END IF;
 IF r.unit IS DISTINCT FROM (SELECT cn.meter_unit FROM operational_cut_nozzles cn WHERE cn.cut_id=target_cut AND cn.nozzle_id=target_nozzle) THEN
  RAISE EXCEPTION 'Meter unit changed after opening' USING ERRCODE='23514'; END IF;
 SELECT x.* INTO prior FROM operational_cut_meter_captures x
 WHERE x.cut_id=previous_operational_cut(target_cut) AND x.nozzle_id=target_nozzle;
 IF prior.reading_id IS NOT NULL AND (r.prior_reading_id IS DISTINCT FROM prior.reading_id OR
  r.prior_value IS DISTINCT FROM prior.closing_value) THEN
  RAISE EXCEPTION 'Meter reading does not continue previous cut' USING ERRCODE='23514'; END IF;
 IF prior.reading_id IS NULL AND EXISTS(SELECT 1 FROM operational_cut_nozzles pn
  WHERE pn.cut_id=previous_operational_cut(target_cut) AND pn.nozzle_id=target_nozzle AND pn.participation='expected') THEN
  RAISE EXCEPTION 'Previous cut lacks expected nozzle reading' USING ERRCODE='23514'; END IF;
 IF prior.reading_id IS NULL AND NOT EXISTS(SELECT 1 FROM nozzle_meter_readings baseline
   WHERE baseline.id=r.prior_reading_id AND baseline.nozzle_id=target_nozzle AND baseline.captured_at<=c.starts_at) THEN
  RAISE EXCEPTION 'First cut needs a meter baseline at or before its start' USING ERRCODE='23514'; END IF;
 starting:=COALESCE(prior.closing_value,r.prior_value);
 IF starting IS NULL OR r.value<starting OR (prior.reading_id IS NULL AND r.prior_value IS NULL) THEN
  RAISE EXCEPTION 'Meter requires a valid opening baseline and nondecreasing final' USING ERRCODE='23514'; END IF;
 liters:=round((r.value-starting)*CASE WHEN r.unit='gallon_us' THEN 3.785411784 ELSE 1 END,9);
 INSERT INTO operational_cut_meter_captures(cut_id,organization_id,branch_id,nozzle_id,reading_id,opening_value,closing_value,measured_l,meter_unit,captured_by)
 VALUES(target_cut,org,branch,target_nozzle,target_reading,starting,r.value,liters,r.unit,actor);
 UPDATE operational_cuts c2 SET version=c2.version+1 WHERE c2.id=target_cut;
 RETURN QUERY SELECT target_cut,target_nozzle,expected_version+1,starting,r.value,liters;
END; $$;

CREATE OR REPLACE FUNCTION prepare_operational_cut(org uuid, branch uuid, target_cut uuid, actor uuid, expected_version integer)
 RETURNS TABLE(preparation_id uuid,version integer,review_required boolean)
 LANGUAGE plpgsql SET search_path=public,pg_temp AS $$
DECLARE c operational_cuts%ROWTYPE; pol operational_cut_reconciliation_policies%ROWTYPE; acct_start timestamptz;
 products jsonb; tank_levels jsonb; finance jsonb; warnings_list jsonb; requires_review boolean; pid uuid;
BEGIN
 SELECT oc.* INTO c FROM operational_cuts oc WHERE oc.id=target_cut AND oc.organization_id=org AND oc.branch_id=branch FOR UPDATE;
 IF c.id IS NULL OR c.status<>'open' OR c.version<>expected_version THEN
  RAISE EXCEPTION 'Cut not open or version changed' USING ERRCODE='40001'; END IF;
 IF NOT EXISTS(SELECT 1 FROM users u WHERE u.id=actor AND u.organization_id=org AND u.status='active') THEN
  RAISE EXCEPTION 'Inactive preparer' USING ERRCODE='23514'; END IF;
 -- Sales, stock movements and payments recorded after the previous cut ended (the declared non-cut period)
 -- are reconciled in this cut, so meter deltas (which span that period) and sold liters stay comparable.
 acct_start:=COALESCE((SELECT pc.ends_at FROM operational_cuts pc WHERE pc.id=previous_operational_cut(target_cut)),c.starts_at);
 SELECT p.* INTO pol FROM operational_cut_reconciliation_policies p WHERE p.branch_id=branch AND p.organization_id=org
  AND p.effective_date<=c.operational_date ORDER BY p.effective_date DESC LIMIT 1;
 IF pol.id IS NULL THEN RAISE EXCEPTION 'Reconciliation policy is missing' USING ERRCODE='23514'; END IF;
 IF EXISTS(SELECT 1 FROM operational_cut_nozzles n LEFT JOIN operational_cut_meter_captures m ON m.cut_id=n.cut_id AND m.nozzle_id=n.nozzle_id
  WHERE n.cut_id=target_cut AND n.participation='expected' AND m.reading_id IS NULL) THEN
  RAISE EXCEPTION 'Expected nozzle readings are missing' USING ERRCODE='23514'; END IF;
 IF EXISTS(SELECT 1 FROM tanks t LEFT JOIN operational_cut_tank_measurements m ON m.cut_id=target_cut AND m.tank_id=t.id
  WHERE t.branch_id=branch AND t.organization_id=org AND t.status='active' AND m.tank_id IS NULL) THEN
  RAISE EXCEPTION 'Active tank measurement is missing' USING ERRCODE='23514'; END IF;
 IF EXISTS(SELECT 1 FROM operational_cut_tank_measurements m WHERE m.cut_id=target_cut AND NOT EXISTS(
  SELECT 1 FROM inventory_movements im WHERE im.tank_id=m.tank_id AND im.organization_id=org AND im.occurred_at<c.ends_at)) THEN
  RAISE EXCEPTION 'Tank has no opening inventory baseline' USING ERRCODE='23514'; END IF;
 IF EXISTS(SELECT 1 FROM dispense_authorizations a WHERE a.branch_id=branch AND a.organization_id=org AND
  a.created_at<c.ends_at AND a.created_at>=acct_start AND a.status IN('authorized','dispensing','unknown','posting')) THEN
  RAISE EXCEPTION 'Unresolved dispatches in the cut window' USING ERRCODE='23514'; END IF;
 IF EXISTS(SELECT 1 FROM dispense_authorizations a LEFT JOIN sales s ON s.authorization_id=a.id
  WHERE a.branch_id=branch AND a.organization_id=org AND a.status='completed' AND
  a.completed_at>=acct_start AND a.completed_at<c.ends_at AND s.id IS NULL) THEN
  RAISE EXCEPTION 'Completed dispatch lacks its sale ticket' USING ERRCODE='23514'; END IF;
 WITH meter AS (SELECT n.fuel_product_id AS product_id,COALESCE(sum(m.measured_l),0) AS liters
  FROM operational_cut_nozzles n LEFT JOIN operational_cut_meter_captures m ON m.cut_id=n.cut_id AND m.nozzle_id=n.nozzle_id
  WHERE n.cut_id=target_cut GROUP BY n.fuel_product_id),
 sold AS (SELECT a.fuel_product_id AS product_id,sum(a.actual_l) AS liters,sum(a.sale_amount_usd) AS usd
  FROM dispense_authorizations a WHERE a.branch_id=branch AND a.organization_id=org AND a.status='completed'
  AND a.completed_at>=acct_start AND a.completed_at<c.ends_at GROUP BY a.fuel_product_id),
 stock AS (SELECT im.fuel_product_id AS product_id,
   COALESCE(sum(im.delta_l) FILTER(WHERE im.movement_type='receipt'),0) AS receipts_l,
   COALESCE(-sum(im.delta_l) FILTER(WHERE im.movement_type='loss'),0) AS losses_l
  FROM inventory_movements im WHERE im.branch_id=branch AND im.organization_id=org
  AND im.occurred_at>=acct_start AND im.occurred_at<c.ends_at GROUP BY im.fuel_product_id),
 combined AS (SELECT COALESCE(m.product_id,s.product_id,st.product_id) AS product_id,
  COALESCE(m.liters,0) AS measured_l,COALESCE(s.liters,0) AS sold_l,COALESCE(s.usd,0) AS sales_usd,
  COALESCE(st.receipts_l,0) AS receipts_l,COALESCE(st.losses_l,0) AS losses_l
  FROM meter m FULL JOIN sold s ON m.product_id=s.product_id FULL JOIN stock st ON st.product_id=COALESCE(m.product_id,s.product_id))
 SELECT COALESCE(jsonb_agg(jsonb_build_object('fuelProductId',product_id,'meterLiters',measured_l,'soldLiters',sold_l,
  'salesUsd',sales_usd,'priceVersions',COALESCE((SELECT jsonb_agg(jsonb_build_object(
    'priceVersionId',pv.price_version_id,'unitPriceUsd',pv.price_usd_per_unit,'priceUnit',pv.price_unit,
    'liters',pv.liters,'salesUsd',pv.usd) ORDER BY pv.price_version_id) FROM (
    SELECT a.price_version_id,a.price_usd_per_unit,a.price_unit,sum(a.actual_l) AS liters,sum(a.sale_amount_usd) AS usd
    FROM dispense_authorizations a WHERE a.organization_id=org AND a.branch_id=branch
      AND a.fuel_product_id=product_id AND a.status='completed' AND a.completed_at>=acct_start
      AND a.completed_at<c.ends_at GROUP BY a.price_version_id,a.price_usd_per_unit,a.price_unit) pv),'[]'::jsonb),
  'receiptsLiters',receipts_l,'lossLiters',losses_l,'varianceLiters',measured_l-sold_l)
  ORDER BY product_id),'[]'::jsonb),COALESCE(bool_or(abs(measured_l-sold_l)>pol.meter_tolerance_l),false)
 INTO products,requires_review FROM combined;
 WITH levels AS (SELECT m.tank_id,m.fuel_product_id,m.measured_l,
  (SELECT im.after_quantity_l FROM inventory_movements im WHERE im.tank_id=m.tank_id AND im.organization_id=org
   AND im.occurred_at<c.ends_at ORDER BY im.occurred_at DESC,im.id DESC LIMIT 1) AS ledger_l
  FROM operational_cut_tank_measurements m WHERE m.cut_id=target_cut)
 SELECT COALESCE(jsonb_agg(jsonb_build_object('tankId',tank_id,'fuelProductId',fuel_product_id,
  'measuredLiters',measured_l,'ledgerLiters',ledger_l,'varianceLiters',measured_l-ledger_l) ORDER BY tank_id),'[]'::jsonb),
  COALESCE(bool_or(ledger_l IS NULL OR abs(measured_l-ledger_l)>pol.tank_tolerance_l),false) OR requires_review
 INTO tank_levels,requires_review FROM levels;
 -- Payment is attributed to the original sale in this window, irrespective of when it was collected.
 SELECT jsonb_build_object('salesUsd',COALESCE((SELECT sum(s.total_usd) FROM sales s WHERE s.branch_id=branch AND
   s.organization_id=org AND s.occurred_at>=acct_start AND s.occurred_at<c.ends_at),0),
  'confirmedCollectionUsd',COALESCE((SELECT sum(a.amount_usd) FROM payment_attempts a JOIN payment_events e
    ON e.attempt_id=a.id AND e.outcome='confirmed' JOIN sales s ON s.id=a.sale_id
    WHERE s.branch_id=branch AND s.organization_id=org AND s.occurred_at>=acct_start AND s.occurred_at<c.ends_at),0),
  'cashConfirmedUsd',COALESCE((SELECT sum(a.amount_usd) FROM payment_attempts a JOIN payment_events e
    ON e.attempt_id=a.id AND e.outcome='confirmed' JOIN sales s ON s.id=a.sale_id WHERE a.method='cash'
    AND s.branch_id=branch AND s.organization_id=org AND s.occurred_at>=acct_start AND s.occurred_at<c.ends_at),0),
  'cardConfirmedUsd',COALESCE((SELECT sum(a.amount_usd) FROM payment_attempts a JOIN payment_events e
    ON e.attempt_id=a.id AND e.outcome='confirmed' JOIN sales s ON s.id=a.sale_id WHERE a.method='card'
    AND s.branch_id=branch AND s.organization_id=org AND s.occurred_at>=acct_start AND s.occurred_at<c.ends_at),0),
  'refundedUsd',COALESCE((SELECT sum(r.amount_usd) FROM payment_refunds r JOIN payment_events e ON e.id=r.payment_event_id
    JOIN payment_attempts a ON a.id=e.attempt_id JOIN sales s ON s.id=a.sale_id
    WHERE s.branch_id=branch AND s.organization_id=org AND s.occurred_at>=acct_start AND s.occurred_at<c.ends_at),0))
 INTO finance;
 requires_review:=requires_review OR
  abs((finance->>'salesUsd')::numeric-(finance->>'confirmedCollectionUsd')::numeric+(finance->>'refundedUsd')::numeric)>pol.collection_tolerance_usd;
 SELECT COALESCE(jsonb_agg(issue),'[]'::jsonb) INTO warnings_list FROM (
  SELECT jsonb_build_object('code','meter_variance','fuelProductId',p->>'fuelProductId','varianceLiters',p->>'varianceLiters') AS issue
   FROM jsonb_array_elements(products) p WHERE abs((p->>'varianceLiters')::numeric)>pol.meter_tolerance_l
  UNION ALL
  SELECT jsonb_build_object('code','tank_variance','tankId',t->>'tankId','varianceLiters',t->>'varianceLiters')
   FROM jsonb_array_elements(tank_levels) t WHERE abs((t->>'varianceLiters')::numeric)>pol.tank_tolerance_l
  UNION ALL
  SELECT jsonb_build_object('code','collection_variance','salesUsd',finance->>'salesUsd',
   'confirmedUsd',finance->>'confirmedCollectionUsd','refundedUsd',finance->>'refundedUsd')
   WHERE abs((finance->>'salesUsd')::numeric-(finance->>'confirmedCollectionUsd')::numeric+
     (finance->>'refundedUsd')::numeric)>pol.collection_tolerance_usd
 ) issues;
 INSERT INTO operational_cut_preparations(cut_id,organization_id,branch_id,policy_id,input_version,output_version,
  product_summary,tank_summary,financial_summary,review_required,warnings,prepared_by)
 VALUES(target_cut,org,branch,pol.id,expected_version,expected_version+1,products,tank_levels,finance,requires_review,warnings_list,actor)
 RETURNING id INTO pid;
 UPDATE operational_cuts oc SET status=CASE WHEN requires_review THEN 'inReview' ELSE 'prepared' END,version=oc.version+1
  WHERE oc.id=target_cut;
 RETURN QUERY SELECT pid,expected_version+1,requires_review;
END; $$;

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
 IF EXISTS(SELECT 1 FROM operational_cuts previous WHERE previous.id=previous_operational_cut(target_cut)
  AND previous.status<>'closed') THEN
  RAISE EXCEPTION 'Previous contiguous cut must close first' USING ERRCODE='23514'; END IF;
 INSERT INTO operational_cut_closures(cut_id,preparation_id,review_id,organization_id,branch_id,input_version,output_version,snapshot,closed_by,closed_at)
 VALUES(target_cut,prep.id,review.id,org,branch,expected_version,expected_version+1,
  jsonb_build_object('policyId',prep.policy_id,'products',prep.product_summary,'tanks',prep.tank_summary,
    'finance',prep.financial_summary,'reviewRequired',prep.review_required,'preparedAt',prep.prepared_at,
    'reviewId',review.id,'operationalDate',c.operational_date,'slot',c.slot,'startsAt',c.starts_at,'endsAt',c.ends_at,
    'accountingStartsAt',COALESCE((SELECT pc.ends_at FROM operational_cuts pc WHERE pc.id=previous_operational_cut(target_cut)),c.starts_at)),actor,stamp)
 RETURNING id INTO cid;
 UPDATE operational_cuts oc SET status='closed',version=oc.version+1 WHERE oc.id=target_cut;
 INSERT INTO outbox_events(event_type,aggregate_type,aggregate_id,payload)
 VALUES('operational_cut.closed','operational_cut',target_cut,
  jsonb_build_object('organizationId',org,'branchId',branch,'cutId',target_cut,'closureId',cid,'closedAt',stamp));
 RETURN QUERY SELECT cid,expected_version+1,stamp;
END; $$;

COMMIT;
