/*
  MonCity operational database exploration
  Read-only: this script does not modify MONCITY.
*/

/* 1. Confirm the source tables and row counts. */
SELECT 'ACCIDENTINFO' AS table_name, COUNT(*) AS row_count FROM MONCITY.ACCIDENTINFO
UNION ALL SELECT 'BELONGTO', COUNT(*) FROM MONCITY.BELONGTO
UNION ALL SELECT 'BOOKING', COUNT(*) FROM MONCITY.BOOKING
UNION ALL SELECT 'CAR', COUNT(*) FROM MONCITY.CAR
UNION ALL SELECT 'CARACCIDENT', COUNT(*) FROM MONCITY.CARACCIDENT
UNION ALL SELECT 'ERROR', COUNT(*) FROM MONCITY.ERROR
UNION ALL SELECT 'FACULTY', COUNT(*) FROM MONCITY.FACULTY
UNION ALL SELECT 'MAINTENANCE', COUNT(*) FROM MONCITY.MAINTENANCE
UNION ALL SELECT 'MAINTENANCETEAM', COUNT(*) FROM MONCITY.MAINTENANCETEAM
UNION ALL SELECT 'MAINTENANCETYPE', COUNT(*) FROM MONCITY.MAINTENANCETYPE
UNION ALL SELECT 'PASSENGER', COUNT(*) FROM MONCITY.PASSENGER
UNION ALL SELECT 'RESEARCHCENTER', COUNT(*) FROM MONCITY.RESEARCHCENTER
ORDER BY table_name;

/* 2. Inspect exact column names and Oracle data types. */
SELECT
    table_name,
    column_id,
    column_name,
    data_type,
    data_length,
    data_precision,
    data_scale,
    nullable
FROM all_tab_columns
WHERE owner = 'MONCITY'
  AND table_name IN (
      'ACCIDENTINFO', 'BELONGTO', 'BOOKING', 'CAR', 'CARACCIDENT',
      'ERROR', 'FACULTY', 'MAINTENANCE', 'MAINTENANCETEAM',
      'MAINTENANCETYPE', 'PASSENGER', 'RESEARCHCENTER'
  )
ORDER BY table_name, column_id;

/* 3. Inspect declared primary/unique/foreign-key constraints. */
SELECT
    c.table_name,
    c.constraint_name,
    c.constraint_type,
    cc.position,
    cc.column_name,
    rc.table_name AS referenced_table,
    rcc.column_name AS referenced_column
FROM all_constraints c
JOIN all_cons_columns cc
  ON cc.owner = c.owner
 AND cc.constraint_name = c.constraint_name
LEFT JOIN all_constraints rc
  ON rc.owner = c.r_owner
 AND rc.constraint_name = c.r_constraint_name
LEFT JOIN all_cons_columns rcc
  ON rcc.owner = rc.owner
 AND rcc.constraint_name = rc.constraint_name
 AND rcc.position = cc.position
WHERE c.owner = 'MONCITY'
  AND c.constraint_type IN ('P', 'U', 'R')
ORDER BY c.table_name, c.constraint_type, c.constraint_name, cc.position;

/* 4. Values that define the required business dimensions. */
SELECT 'FACULTY.ZONE' AS attribute_name, TRIM(zone) AS raw_value, COUNT(*) AS row_count
FROM MONCITY.FACULTY GROUP BY TRIM(zone)
UNION ALL
SELECT 'PASSENGER.ROLE', TRIM(passengerrole), COUNT(*)
FROM MONCITY.PASSENGER GROUP BY TRIM(passengerrole)
UNION ALL
SELECT 'PASSENGER.GENDER', TRIM(passengergender), COUNT(*)
FROM MONCITY.PASSENGER GROUP BY TRIM(passengergender)
UNION ALL
SELECT 'CAR.BODYTYPE', TRIM(carbodytype), COUNT(*)
FROM MONCITY.CAR GROUP BY TRIM(carbodytype)
UNION ALL
SELECT 'BOOKING.DEPARTUREZONE', TRIM(departurezone), COUNT(*)
FROM MONCITY.BOOKING GROUP BY TRIM(departurezone)
UNION ALL
SELECT 'BOOKING.DESTINATIONZONE', TRIM(destinationzone), COUNT(*)
FROM MONCITY.BOOKING GROUP BY TRIM(destinationzone)
UNION ALL
SELECT 'MAINTENANCE.TYPE', TRIM(maintenancetype), COUNT(*)
FROM MONCITY.MAINTENANCE GROUP BY TRIM(maintenancetype)
UNION ALL
SELECT 'ACCIDENT.ZONE', TRIM(accidentzone), COUNT(*)
FROM MONCITY.ACCIDENTINFO GROUP BY TRIM(accidentzone)
UNION ALL
SELECT 'ACCIDENT.SEVERITY', TRIM(car_damage_severity), COUNT(*)
FROM MONCITY.ACCIDENTINFO GROUP BY TRIM(car_damage_severity)
ORDER BY attribute_name, raw_value;

/* 5. Range and date profiles used to validate grouping rules. */
SELECT
    MIN(passengerage) AS min_passenger_age,
    MAX(passengerage) AS max_passenger_age,
    SUM(CASE WHEN passengerage BETWEEN 18 AND 35 THEN 1 ELSE 0 END) AS young_adult_rows,
    SUM(CASE WHEN passengerage BETWEEN 36 AND 59 THEN 1 ELSE 0 END) AS middle_aged_rows,
    SUM(CASE WHEN passengerage >= 60 THEN 1 ELSE 0 END) AS old_aged_rows,
    SUM(CASE WHEN passengerage IS NULL OR passengerage < 18 THEN 1 ELSE 0 END) AS unclassified_rows
FROM MONCITY.PASSENGER;

SELECT
    MIN(bookingdate) AS first_booking_date,
    MAX(bookingdate) AS last_booking_date,
    COUNT(DISTINCT TRUNC(bookingdate, 'MM')) AS booking_months
FROM MONCITY.BOOKING;

SELECT
    MIN(maintenancedate) AS first_maintenance_date,
    MAX(maintenancedate) AS last_maintenance_date,
    MIN(maintenancecost) AS min_maintenance_cost,
    MAX(maintenancecost) AS max_maintenance_cost
FROM MONCITY.MAINTENANCE;

SELECT
    MIN(manufacturingyear) AS earliest_manufacturing_year,
    MAX(manufacturingyear) AS latest_manufacturing_year,
    MIN(numseats) AS minimum_seats,
    MAX(numseats) AS maximum_seats
FROM MONCITY.CAR;

/* 6. Relationship cardinality relevant to the maintenance bridge design. */
SELECT
    teamid,
    COUNT(DISTINCT centerid) AS research_center_count
FROM MONCITY.BELONGTO
GROUP BY teamid
ORDER BY teamid;
