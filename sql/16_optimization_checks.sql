WITH canonical_booking AS (
  SELECT DISTINCT UPPER(TRIM(bookingid)) bookingid,
    UPPER(TRIM(registrationno)) registrationno, bookingdate,
    UPPER(TRIM(departurezone)) departurezone,
    UPPER(TRIM(destinationzone)) destinationzone,
    UPPER(TRIM(passengerid)) passengerid
  FROM MONCITY.BOOKING
), missing_booking AS (
  SELECT * FROM canonical_booking
  MINUS SELECT bookingid, registrationno, bookingdate, departurezone,
    destinationzone, passengerid FROM MC_STG_BOOKING
), extra_booking AS (
  SELECT bookingid, registrationno, bookingdate, departurezone,
    destinationzone, passengerid FROM MC_STG_BOOKING
  MINUS SELECT * FROM canonical_booking
)
SELECT 'BOOKINGS' metric, SUM(booking_count) value FROM MC_BOOKING_FACT
UNION ALL SELECT 'MAINT_COUNT', SUM(maintenance_count) FROM MC_MAINT_FACT
UNION ALL SELECT 'MAINT_COST', SUM(total_maintenance_cost) FROM MC_MAINT_FACT
UNION ALL SELECT 'ACCIDENTS', SUM(accident_count) FROM MC_ACCIDENT_FACT
UNION ALL SELECT 'VALIDATED_MEASURE_CHECKS', COUNT(*) FROM user_constraints
 WHERE constraint_name IN ('MC_BF_COUNT_CK','MC_MF_COUNT_CK',
 'MC_MF_COST_CK','MC_AF_COUNT_CK','MC_CGB_WEIGHT_CK','MC_CARB_WEIGHT_CK')
 AND status = 'ENABLED' AND validated = 'VALIDATED'
UNION ALL SELECT 'CONFLICTING_BOOKING_IDS', COUNT(*) FROM (
 SELECT bookingid FROM canonical_booking GROUP BY bookingid HAVING COUNT(*) > 1)
UNION ALL SELECT 'MISSING_CANONICAL_BOOKINGS', COUNT(*) FROM missing_booking
UNION ALL SELECT 'EXTRA_STAGED_BOOKINGS', COUNT(*) FROM extra_booking
UNION ALL SELECT 'BAD_STAGING_COST', COUNT(*) FROM MC_STG_MAINTENANCE
 WHERE maintenancecost IS NULL OR maintenancecost < 0;
