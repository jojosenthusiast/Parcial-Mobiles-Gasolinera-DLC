DO $$
BEGIN
 IF EXISTS (
  SELECT 1 FROM tank_inventory_balances b
  LEFT JOIN (SELECT tank_id,sum(delta_l)::numeric(24,12) AS ledger_l FROM inventory_movements GROUP BY tank_id) m USING(tank_id)
  WHERE b.on_hand_l IS DISTINCT FROM coalesce(m.ledger_l,0)
 ) THEN RAISE EXCEPTION 'Restored fuel balances do not match the movement ledger'; END IF;
 IF EXISTS (
  SELECT 1 FROM pos_stock_lots l LEFT JOIN pos_stock_movements m ON m.lot_id=l.id
  GROUP BY l.id,l.quantity_received HAVING coalesce(sum(m.delta_units),0)<0 OR coalesce(sum(m.delta_units),0)>l.quantity_received
 ) THEN RAISE EXCEPTION 'Restored store-lot balances are outside received quantity'; END IF;
 IF EXISTS (
  SELECT 1 FROM audit_events e LEFT JOIN users u ON u.id=e.actor_user_id AND u.organization_id=e.organization_id
  LEFT JOIN branches b ON b.id=e.branch_id AND b.organization_id=e.organization_id
  WHERE (e.actor_user_id IS NOT NULL AND u.id IS NULL) OR (e.branch_id IS NOT NULL AND b.id IS NULL)
 ) THEN RAISE EXCEPTION 'Restored audit events have invalid tenant references'; END IF;
 IF EXISTS (SELECT 1 FROM report_runs WHERE jsonb_array_length(rows_snapshot)<>row_count)
  THEN RAISE EXCEPTION 'Restored report snapshots are incomplete'; END IF;
END $$;
SELECT json_build_object(
 'inventoryTanks',(SELECT count(*) FROM tank_inventory_balances),
 'inventoryMovements',(SELECT count(*) FROM inventory_movements),
 'storeLots',(SELECT count(*) FROM pos_stock_lots),
 'auditEvents',(SELECT count(*) FROM audit_events),
 'closedCuts',(SELECT count(*) FROM operational_cut_closures),
 'reportSnapshots',(SELECT count(*) FROM report_runs)
) AS verified_counts;
