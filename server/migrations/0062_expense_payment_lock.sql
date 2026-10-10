-- Serialize payments without granting UPDATE on immutable expense claims.
CREATE OR REPLACE FUNCTION validate_expense_disbursement() RETURNS trigger LANGUAGE plpgsql SET search_path=public,pg_temp AS $$
DECLARE e expense_claims%ROWTYPE; paid numeric;
BEGIN
 PERFORM pg_advisory_xact_lock(hashtextextended('expense-payment:'||NEW.expense_id,0));
 SELECT * INTO e FROM expense_claims WHERE id=NEW.expense_id;
 IF e.id IS NULL OR e.organization_id<>NEW.organization_id OR e.branch_id<>NEW.branch_id
  OR NOT EXISTS(SELECT 1 FROM expense_decisions WHERE expense_id=e.id AND outcome='approved')
 THEN RAISE EXCEPTION 'Expense is not approved' USING ERRCODE='23514'; END IF;
 SELECT coalesce(sum(amount_usd),0) INTO paid FROM expense_disbursements WHERE expense_id=e.id;
 IF NEW.amount_usd>e.amount_usd-paid THEN RAISE EXCEPTION 'Disbursement exceeds expense' USING ERRCODE='23514'; END IF;
 IF NEW.method='cash' THEN
  PERFORM lock_owned_open_cash(NEW.cash_session_id,NEW.recorded_by,NEW.organization_id,NEW.branch_id);
 END IF;
 RETURN NEW;
END $$;
