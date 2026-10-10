BEGIN;

-- Earlier API completions updated inventory and authorization state but did not
-- consistently write the sale ticket. Reconstruct the immutable ticket from the
-- original authorization and inventory snapshot without selling inventory again.
WITH inserted_sales AS (
  INSERT INTO sales(organization_id,branch_id,authorization_id,command_id,request_hash,total_usd,created_by,occurred_at,correlation_id)
  SELECT a.organization_id,a.branch_id,a.id,
         CASE WHEN EXISTS(SELECT 1 FROM sales collision WHERE collision.organization_id=a.organization_id
                            AND collision.command_id=coalesce(a.completion_command_id,a.command_id))
              THEN gen_random_uuid() ELSE coalesce(a.completion_command_id,a.command_id) END,
         coalesce(a.completion_hash,a.request_hash),
         a.sale_amount_usd,a.requested_by,a.completed_at,coalesce(ev.correlation_id,a.completion_command_id,a.command_id)
    FROM dispense_authorizations a
    LEFT JOIN LATERAL (SELECT e.correlation_id FROM dispense_authorization_events e
      WHERE e.authorization_id=a.id AND e.event_type='completed' ORDER BY e.occurred_at DESC,e.id DESC LIMIT 1) ev ON true
   WHERE a.status='completed' AND a.actual_l IS NOT NULL AND a.sale_amount_usd IS NOT NULL
     AND a.inventory_movement_id IS NOT NULL AND a.completed_at IS NOT NULL
     AND NOT EXISTS(SELECT 1 FROM sales s WHERE s.authorization_id=a.id)
   ORDER BY a.completed_at,a.id
  ON CONFLICT(authorization_id) DO NOTHING
  RETURNING id,organization_id,branch_id,authorization_id,total_usd,created_by,correlation_id
), inserted_lines AS (
  INSERT INTO sale_lines(organization_id,branch_id,sale_id,line_number,fuel_product_id,description,quantity_l,
    price_usd_per_unit,price_unit,price_version_id,total_usd,inventory_movement_id,cost_usd,unit_cost_usd_per_l,cost_quality)
  SELECT s.organization_id,s.branch_id,s.id,1,p.id,p.display_name,a.actual_l,a.price_usd_per_unit,a.price_unit,
    a.price_version_id,a.sale_amount_usd,m.id,m.cost_recognized_usd,m.unit_cost_usd_per_l,m.valuation_quality
    FROM inserted_sales s JOIN dispense_authorizations a ON a.id=s.authorization_id
    JOIN fuel_products p ON p.id=a.fuel_product_id AND p.organization_id=a.organization_id
    JOIN inventory_movements m ON m.id=a.inventory_movement_id AND m.organization_id=a.organization_id AND m.branch_id=a.branch_id
  RETURNING sale_id,organization_id,branch_id
)
INSERT INTO audit_events(organization_id,branch_id,actor_user_id,correlation_id,action,entity_type,entity_id,after_data,metadata)
SELECT l.organization_id,l.branch_id,s.created_by,s.correlation_id,'sale.backfilled_from_dispense','sale',l.sale_id::text,
       jsonb_build_object('source','completed_dispense','lineRestored',true),'{}'::jsonb
  FROM inserted_lines l JOIN inserted_sales s ON s.id=l.sale_id;

COMMIT;
