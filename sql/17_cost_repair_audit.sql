-- One-time non-destructive migration on the existing staging table.
-- The view compares the current source and staging; it is not a historical log.
BEGIN
  EXECUTE IMMEDIATE 'ALTER TABLE MC_STG_MAINTENANCE ADD CONSTRAINT MC_SM_COST_CK CHECK (maintenancecost IS NOT NULL AND maintenancecost >= 0) ENABLE VALIDATE';
  EXECUTE IMMEDIATE 'CREATE VIEW MC_COST_REPAIR_AUDIT AS
    SELECT s.maintenanceid, s.maintenancecost AS source_cost,
           c.maintenancecost AS cleaned_cost,
           CASE WHEN UPPER(TRIM(s.maintenanceid)) = ''M2000''
                     AND s.maintenancecost = -200 AND c.maintenancecost = 200
                THEN ''Documented sign-repair assumption: M2000 -200 to 200''
                ELSE ''UNEXPECTED DIFFERENCE: investigate'' END AS repair_reason
    FROM MONCITY.MAINTENANCE s
    JOIN MC_STG_MAINTENANCE c
      ON c.maintenanceid = UPPER(TRIM(s.maintenanceid))
    WHERE s.maintenancecost <> c.maintenancecost
       OR (s.maintenancecost IS NULL AND c.maintenancecost IS NOT NULL)
       OR (s.maintenancecost IS NOT NULL AND c.maintenancecost IS NULL)';
END;
