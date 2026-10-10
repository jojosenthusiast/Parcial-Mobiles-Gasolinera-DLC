-- One supplier document identifies one quotation for the same product.
CREATE UNIQUE INDEX supplier_quote_document_identity ON supplier_fuel_quotes
 (organization_id,supplier_id,fuel_product_id,lower(btrim(document_reference)));
