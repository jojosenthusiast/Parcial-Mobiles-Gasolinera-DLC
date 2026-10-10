BEGIN;
ALTER TABLE incidents DROP CONSTRAINT incidents_category_check;
ALTER TABLE incidents ADD CONSTRAINT incidents_category_check CHECK(category IN(
 'personal_injury','third_party_damage','premises_damage','equipment_damage','fuel_spill',
 'wrong_tank_delivery','fuel_variance','safety','other'));
ALTER TABLE incidents ADD CONSTRAINT incidents_wrong_tank_guard CHECK(
 category<>'wrong_tank_delivery' OR (asset_type='tank' AND asset_id IS NOT NULL AND severity IN('high','critical')));
-- Registration blocks use through the API. Financial disposal is deliberately separate.
COMMIT;
