-- Non-destructive, one-time migration. Execute the whole BEGIN ... END block.
-- Preflight: all existing values must satisfy these predicates.
-- Oracle DDL commits independently; inspect user_constraints before any retry.
BEGIN
  EXECUTE IMMEDIATE 'ALTER TABLE MC_BOOKING_FACT ADD CONSTRAINT MC_BF_COUNT_CK CHECK (booking_count IS NOT NULL AND booking_count >= 0 AND booking_count = TRUNC(booking_count)) ENABLE VALIDATE';
  EXECUTE IMMEDIATE 'ALTER TABLE MC_MAINT_FACT ADD CONSTRAINT MC_MF_COUNT_CK CHECK (maintenance_count IS NOT NULL AND maintenance_count >= 0 AND maintenance_count = TRUNC(maintenance_count)) ENABLE VALIDATE';
  EXECUTE IMMEDIATE 'ALTER TABLE MC_MAINT_FACT ADD CONSTRAINT MC_MF_COST_CK CHECK (total_maintenance_cost IS NOT NULL AND total_maintenance_cost >= 0) ENABLE VALIDATE';
  EXECUTE IMMEDIATE 'ALTER TABLE MC_ACCIDENT_FACT ADD CONSTRAINT MC_AF_COUNT_CK CHECK (accident_count IS NOT NULL AND accident_count >= 0 AND accident_count = TRUNC(accident_count)) ENABLE VALIDATE';
  EXECUTE IMMEDIATE 'ALTER TABLE MC_CENTER_GRP_BRIDGE ADD CONSTRAINT MC_CGB_WEIGHT_CK CHECK (bridge_weight IS NOT NULL AND bridge_weight > 0 AND bridge_weight <= 1) ENABLE VALIDATE';
  EXECUTE IMMEDIATE 'ALTER TABLE MC_CAR_GRP_BRIDGE ADD CONSTRAINT MC_CARB_WEIGHT_CK CHECK (bridge_weight IS NOT NULL AND bridge_weight > 0 AND bridge_weight <= 1) ENABLE VALIDATE';
END;
