/*
  read-only after-cleaning validation.
  Every UNRESOLVED value must be zero.
*/

SELECT issue_order, issue_name, source_rows, cleaned_rows, unresolved
FROM (
  SELECT 1 issue_order, 'Exact duplicate booking rows removed' issue_name,
         (SELECT COUNT(*) FROM MONCITY.BOOKING) source_rows,
         (SELECT COUNT(*) FROM MC_STG_BOOKING) cleaned_rows,
         (SELECT COUNT(*) FROM (
            SELECT bookingid FROM MC_STG_BOOKING
            GROUP BY bookingid HAVING COUNT(*) > 1
          )) unresolved
  FROM dual
  UNION ALL
  SELECT 2, 'Missing accident IDs repaired',
         (SELECT COUNT(*) FROM MONCITY.ACCIDENTINFO),
         (SELECT COUNT(*) FROM MC_STG_ACCIDENTINFO),
         (SELECT COUNT(*) FROM MC_STG_ACCIDENTINFO WHERE accidentid IS NULL)
  FROM dual
  UNION ALL
  SELECT 3, 'Accidents without car mapped to UNKNOWN',
         (SELECT COUNT(*) FROM MONCITY.CARACCIDENT),
         (SELECT COUNT(*) FROM MC_STG_CARACCIDENT),
         (SELECT COUNT(*) FROM MC_STG_ACCIDENTINFO a
          WHERE NOT EXISTS (
            SELECT 1 FROM MC_STG_CARACCIDENT ca WHERE ca.accidentid = a.accidentid
          ))
  FROM dual
  UNION ALL
  SELECT 4, 'Negative maintenance costs repaired',
         (SELECT COUNT(*) FROM MONCITY.MAINTENANCE),
         (SELECT COUNT(*) FROM MC_STG_MAINTENANCE),
         (SELECT COUNT(*) FROM MC_STG_MAINTENANCE WHERE maintenancecost < 0)
  FROM dual
  UNION ALL
  SELECT 5, 'Unmapped accident error codes repaired',
         (SELECT COUNT(*) FROM MONCITY.ERROR),
         (SELECT COUNT(*) FROM MC_STG_ERROR),
         (SELECT COUNT(*) FROM MC_STG_ACCIDENTINFO a
          WHERE NOT EXISTS (
            SELECT 1 FROM MC_STG_ERROR e WHERE e.errorcode = a.errorcode
          ))
  FROM dual
)
ORDER BY issue_order;
