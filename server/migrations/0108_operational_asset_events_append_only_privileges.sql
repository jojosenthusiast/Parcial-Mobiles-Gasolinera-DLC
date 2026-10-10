BEGIN;

REVOKE UPDATE, DELETE ON TABLE public.operational_asset_events FROM dlc_api_runtime;
DROP POLICY IF EXISTS dlc_api_update ON public.operational_asset_events;

COMMIT;
