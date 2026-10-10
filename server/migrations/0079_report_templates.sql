ALTER TABLE report_runs DROP CONSTRAINT IF EXISTS report_runs_report_type_check;
ALTER TABLE report_runs ADD CONSTRAINT report_runs_report_type_check
 CHECK(report_type IN('closed_cuts','fuel_sales','tank_movements','incidents','purchase_orders',
  'fuel_prices','expenses','cash_closures','store_stock','maintenance_orders','staff_shifts'));
ALTER TABLE saved_report_filters DROP CONSTRAINT IF EXISTS saved_report_filters_report_type_check;
ALTER TABLE saved_report_filters ADD CONSTRAINT saved_report_filters_report_type_check
 CHECK(report_type IN('closed_cuts','fuel_sales','tank_movements','incidents','purchase_orders',
  'fuel_prices','expenses','cash_closures','store_stock','maintenance_orders','staff_shifts'));
