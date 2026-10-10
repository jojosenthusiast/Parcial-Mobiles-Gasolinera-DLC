-- Branch-local operating days have exactly two contiguous windows. A profile is
-- explicit and immutable; changing the schedule requires a new effective date.
CREATE TABLE operational_cut_profiles (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), organization_id uuid NOT NULL, branch_id uuid NOT NULL,
 effective_date date NOT NULL, day_start time NOT NULL, split_at time NOT NULL,
 timezone text NOT NULL, created_by uuid NOT NULL, created_at timestamptz NOT NULL DEFAULT now(),
 CHECK(day_start<>split_at), CHECK(length(timezone) BETWEEN 1 AND 80),
 FOREIGN KEY(branch_id,organization_id) REFERENCES branches(id,organization_id),
 FOREIGN KEY(created_by,organization_id) REFERENCES users(id,organization_id),
 UNIQUE(branch_id,effective_date), UNIQUE(id,organization_id,branch_id)
);
CREATE TABLE operational_cuts (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), organization_id uuid NOT NULL, branch_id uuid NOT NULL,
 operational_date date NOT NULL, slot smallint NOT NULL CHECK(slot IN(1,2)),
 profile_id uuid NOT NULL, starts_at timestamptz NOT NULL, ends_at timestamptz NOT NULL,
 status text NOT NULL DEFAULT 'scheduled' CHECK(status IN('scheduled','open','prepared','inReview','closed')),
 version integer NOT NULL DEFAULT 1 CHECK(version>0), created_at timestamptz NOT NULL DEFAULT now(),
 CHECK(ends_at>starts_at),
 FOREIGN KEY(branch_id,organization_id) REFERENCES branches(id,organization_id),
 FOREIGN KEY(profile_id,organization_id,branch_id) REFERENCES operational_cut_profiles(id,organization_id,branch_id),
 UNIQUE(branch_id,operational_date,slot), UNIQUE(id,organization_id,branch_id)
);
CREATE INDEX operational_cuts_branch_period_idx ON operational_cuts(branch_id,starts_at DESC);

CREATE FUNCTION assert_two_cut_windows() RETURNS trigger LANGUAGE plpgsql SET search_path=public,pg_temp AS $$
DECLARE first_cut operational_cuts%ROWTYPE; second_cut operational_cuts%ROWTYPE;
BEGIN
 SELECT * INTO first_cut FROM operational_cuts WHERE branch_id=NEW.branch_id AND operational_date=NEW.operational_date AND slot=1;
 SELECT * INTO second_cut FROM operational_cuts WHERE branch_id=NEW.branch_id AND operational_date=NEW.operational_date AND slot=2;
 IF first_cut.id IS NULL OR second_cut.id IS NULL OR first_cut.ends_at<>second_cut.starts_at
   OR first_cut.profile_id<>second_cut.profile_id OR first_cut.organization_id<>second_cut.organization_id THEN
  RAISE EXCEPTION 'An operational day needs exactly two contiguous cuts' USING ERRCODE='23514';
 END IF;
 RETURN NULL;
END; $$;
CREATE CONSTRAINT TRIGGER operational_cut_pair_guard AFTER INSERT ON operational_cuts
 DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION assert_two_cut_windows();

CREATE FUNCTION validate_operational_cut_profile() RETURNS trigger LANGUAGE plpgsql SET search_path=public,pg_temp AS $$
DECLARE branch_timezone text;
BEGIN
 SELECT timezone INTO branch_timezone FROM branches WHERE id=NEW.branch_id AND organization_id=NEW.organization_id;
 IF branch_timezone IS NULL OR branch_timezone<>NEW.timezone OR NOT EXISTS(SELECT 1 FROM pg_timezone_names WHERE name=NEW.timezone) THEN
  RAISE EXCEPTION 'Cut profile needs the branch current valid timezone' USING ERRCODE='23514';
 END IF;
 IF EXISTS(SELECT 1 FROM operational_cuts c WHERE c.branch_id=NEW.branch_id AND c.operational_date>=NEW.effective_date) THEN
  RAISE EXCEPTION 'Cannot insert a retroactive profile over generated cuts' USING ERRCODE='23514';
 END IF;
 RETURN NEW;
END; $$;
CREATE TRIGGER operational_cut_profile_guard BEFORE INSERT ON operational_cut_profiles
 FOR EACH ROW EXECUTE FUNCTION validate_operational_cut_profile();
CREATE TRIGGER operational_cut_profiles_immutable BEFORE UPDATE OR DELETE ON operational_cut_profiles
 FOR EACH ROW EXECUTE FUNCTION prevent_inventory_movement_mutation();

CREATE FUNCTION generate_operational_cuts(org uuid, branch uuid, target_date date)
 RETURNS TABLE(cut_id uuid, slot smallint, starts_at timestamptz, ends_at timestamptz)
 LANGUAGE plpgsql SET search_path=public,pg_temp AS $$
DECLARE profile operational_cut_profiles%ROWTYPE; start_utc timestamptz; split_utc timestamptz; end_utc timestamptz;
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
 end_utc:=((target_date+1)+profile.day_start) AT TIME ZONE profile.timezone;
 IF split_utc<=start_utc OR end_utc<=split_utc THEN RAISE EXCEPTION 'Invalid cut windows in the branch timezone' USING ERRCODE='23514'; END IF;
 IF EXISTS(SELECT 1 FROM operational_cuts c WHERE c.branch_id=branch AND c.operational_date=target_date-1
    AND c.slot=2 AND c.ends_at<>start_utc) OR
    EXISTS(SELECT 1 FROM operational_cuts c WHERE c.branch_id=branch AND c.operational_date=target_date+1
    AND c.slot=1 AND c.starts_at<>end_utc) THEN
  RAISE EXCEPTION 'New cut windows cannot leave a gap or overlap the neighboring operating day' USING ERRCODE='23514';
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

DO $$ DECLARE t text; BEGIN
 FOREACH t IN ARRAY ARRAY['operational_cut_profiles','operational_cuts'] LOOP
  EXECUTE format('ALTER TABLE %I ENABLE ROW LEVEL SECURITY',t);
  EXECUTE format('REVOKE ALL ON TABLE %I FROM PUBLIC,anon,authenticated,service_role',t);
  EXECUTE format('GRANT SELECT,INSERT ON TABLE %I TO dlc_api_runtime',t);
  EXECUTE format('CREATE POLICY dlc_api_select ON %I FOR SELECT TO dlc_api_runtime USING(true)',t);
  EXECUTE format('CREATE POLICY dlc_api_insert ON %I FOR INSERT TO dlc_api_runtime WITH CHECK(true)',t);
 END LOOP;
END; $$;
REVOKE ALL ON FUNCTION validate_operational_cut_profile(),assert_two_cut_windows(),generate_operational_cuts(uuid,uuid,date) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION generate_operational_cuts(uuid,uuid,date) TO dlc_api_runtime;
