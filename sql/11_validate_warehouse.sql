/*
  Version 1 warehouse validation and required queries

  Read only: this script does not change MONCITY or any MC_ object.
  Run it only after 10_create_warehouse.sql finishes successfully.

  Interpretation of bridges:
    * The seven analysis questions filter a particular centre or car. Their
      counts below are intentionally UNWEIGHTED: a fact group contains a given
      member at most once, so each qualifying source record is counted once.
    * BRIDGE_WEIGHT is for proportional allocation when totals are deliberately
      distributed across every member of a multi-member group.
*/

/* ------------------------------------------------------------------------- */
/* A. Target inventory and representative contents.                          */
/* ------------------------------------------------------------------------- */

SELECT table_name, num_rows
FROM user_tables
WHERE table_name LIKE 'A2MC\_%' ESCAPE '\'
ORDER BY 1;

SELECT
  table_name,
  column_id,
  column_name,
  data_type,
  data_length,
  data_precision,
  data_scale,
  nullable
FROM user_tab_columns
WHERE table_name LIKE 'A2MC\_%' ESCAPE '\'
ORDER BY table_name, column_id;

SELECT
  table_name,
  constraint_name,
  constraint_type,
  status
FROM user_constraints
WHERE table_name LIKE 'A2MC\_%' ESCAPE '\'
ORDER BY table_name, constraint_type, constraint_name;

SELECT 'MC_MONTH_DIM' AS table_name, COUNT(*) AS row_count FROM MC_MONTH_DIM
UNION ALL SELECT 'MC_FACULTY_DIM', COUNT(*) FROM MC_FACULTY_DIM
UNION ALL SELECT 'MC_AGE_GROUP_DIM', COUNT(*) FROM MC_AGE_GROUP_DIM
UNION ALL SELECT 'MC_CAR_BODY_DIM', COUNT(*) FROM MC_CAR_BODY_DIM
UNION ALL SELECT 'MC_MAINT_TYPE_DIM', COUNT(*) FROM MC_MAINT_TYPE_DIM
UNION ALL SELECT 'MC_CENTER_DIM', COUNT(*) FROM MC_CENTER_DIM
UNION ALL SELECT 'MC_CENTER_GROUP_DIM', COUNT(*) FROM MC_CENTER_GROUP_DIM
UNION ALL SELECT 'MC_CENTER_GRP_BRIDGE', COUNT(*) FROM MC_CENTER_GRP_BRIDGE
UNION ALL SELECT 'MC_CAR_DIM', COUNT(*) FROM MC_CAR_DIM
UNION ALL SELECT 'MC_CAR_GROUP_DIM', COUNT(*) FROM MC_CAR_GROUP_DIM
UNION ALL SELECT 'MC_CAR_GRP_BRIDGE', COUNT(*) FROM MC_CAR_GRP_BRIDGE
UNION ALL SELECT 'MC_ACC_ZONE_DIM', COUNT(*) FROM MC_ACC_ZONE_DIM
UNION ALL SELECT 'MC_ERROR_DIM', COUNT(*) FROM MC_ERROR_DIM
UNION ALL SELECT 'MC_SEVERITY_DIM', COUNT(*) FROM MC_SEVERITY_DIM
UNION ALL SELECT 'MC_BOOKING_FACT', COUNT(*) FROM MC_BOOKING_FACT
UNION ALL SELECT 'MC_MAINT_FACT', COUNT(*) FROM MC_MAINT_FACT
UNION ALL SELECT 'MC_ACCIDENT_FACT', COUNT(*) FROM MC_ACCIDENT_FACT
ORDER BY 1;

/* Dimension labels: verify the stored source terminology before screenshots. */
SELECT 'FACULTY' AS dimension_name, faculty_code AS member_code,
       faculty_name AS member_name
FROM MC_FACULTY_DIM
UNION ALL
SELECT 'CAR_BODY', car_body_type, TO_CHAR(number_of_seats)
FROM MC_CAR_BODY_DIM
UNION ALL
SELECT 'MAINTENANCE_TYPE', maintenance_type, maintenance_description
FROM MC_MAINT_TYPE_DIM
UNION ALL
SELECT 'ACCIDENT_ZONE', accident_zone, accident_zone
FROM MC_ACC_ZONE_DIM
UNION ALL
SELECT 'SEVERITY', severity_name, severity_name
FROM MC_SEVERITY_DIM
ORDER BY 1, 2;

/* ------------------------------------------------------------------------- */
/* B. Conservation: source measures must equal warehouse measures.            */
/*    Every DIFFERENCE should be 0.                                           */
/* ------------------------------------------------------------------------- */

SELECT
  metric,
  source_value,
  warehouse_value,
  warehouse_value - source_value AS difference,
  CASE WHEN warehouse_value = source_value THEN 'PASS' ELSE 'FAIL' END AS status
FROM (
  SELECT
    'BOOKING_RECORD_COUNT' AS metric,
    (SELECT COUNT(*) FROM MC_STG_BOOKING) AS source_value,
    (SELECT NVL(SUM(booking_count), 0) FROM MC_BOOKING_FACT) AS warehouse_value
  FROM dual
  UNION ALL
  SELECT
    'MAINTENANCE_RECORD_COUNT',
    (SELECT COUNT(*) FROM MC_STG_MAINTENANCE),
    (SELECT NVL(SUM(maintenance_count), 0) FROM MC_MAINT_FACT)
  FROM dual
  UNION ALL
  SELECT
    'TOTAL_MAINTENANCE_COST',
    (SELECT NVL(SUM(NVL(maintenancecost, 0)), 0) FROM MC_STG_MAINTENANCE),
    (SELECT NVL(SUM(total_maintenance_cost), 0) FROM MC_MAINT_FACT)
  FROM dual
  UNION ALL
  SELECT
    'ACCIDENT_RECORD_COUNT',
    (SELECT COUNT(*) FROM MC_STG_ACCIDENTINFO),
    (SELECT NVL(SUM(accident_count), 0) FROM MC_ACCIDENT_FACT)
  FROM dual
)
ORDER BY 1;

/* ------------------------------------------------------------------------- */
/* C. Grain uniqueness: every result should be 0.                             */
/* ------------------------------------------------------------------------- */

SELECT 'BOOKING_FACT_DUPLICATE_GRAINS' AS check_name, COUNT(*) AS issue_count
FROM (
  SELECT month_id, faculty_key, age_group_key, car_body_key
  FROM MC_BOOKING_FACT
  GROUP BY month_id, faculty_key, age_group_key, car_body_key
  HAVING COUNT(*) > 1
)
UNION ALL
SELECT 'MAINT_FACT_DUPLICATE_GRAINS', COUNT(*)
FROM (
  SELECT car_body_key, maintenance_type_key, center_group_key
  FROM MC_MAINT_FACT
  GROUP BY car_body_key, maintenance_type_key, center_group_key
  HAVING COUNT(*) > 1
)
UNION ALL
SELECT 'ACCIDENT_FACT_DUPLICATE_GRAINS', COUNT(*)
FROM (
  SELECT car_group_key, accident_zone_key, error_key, severity_key
  FROM MC_ACCIDENT_FACT
  GROUP BY car_group_key, accident_zone_key, error_key, severity_key
  HAVING COUNT(*) > 1
)
UNION ALL
SELECT 'CENTER_BRIDGE_DUPLICATE_PAIRS', COUNT(*)
FROM (
  SELECT center_group_key, center_key
  FROM MC_CENTER_GRP_BRIDGE
  GROUP BY center_group_key, center_key
  HAVING COUNT(*) > 1
)
UNION ALL
SELECT 'CAR_BRIDGE_DUPLICATE_PAIRS', COUNT(*)
FROM (
  SELECT car_group_key, car_key
  FROM MC_CAR_GRP_BRIDGE
  GROUP BY car_group_key, car_key
  HAVING COUNT(*) > 1
)
ORDER BY 1;

/* ------------------------------------------------------------------------- */
/* D. Bridge membership and weight checks. Every STATUS should be PASS.       */
/* ------------------------------------------------------------------------- */

SELECT
  'CENTER_GROUP' AS group_type,
  g.center_group_key AS group_key,
  g.group_list,
  g.group_size AS expected_members,
  COUNT(b.center_key) AS bridge_members,
  NVL(SUM(b.bridge_weight), 0) AS bridge_weight_sum,
  CASE
    WHEN COUNT(b.center_key) = g.group_size
     AND (g.group_size = 0 OR ABS(NVL(SUM(b.bridge_weight), 0) - 1) < 0.000001)
    THEN 'PASS' ELSE 'FAIL'
  END AS status
FROM MC_CENTER_GROUP_DIM g
LEFT JOIN MC_CENTER_GRP_BRIDGE b
  ON b.center_group_key = g.center_group_key
GROUP BY g.center_group_key, g.group_list, g.group_size
UNION ALL
SELECT
  'CAR_GROUP',
  g.car_group_key,
  g.group_list,
  g.group_size,
  COUNT(b.car_key),
  NVL(SUM(b.bridge_weight), 0),
  CASE
    WHEN COUNT(b.car_key) = g.group_size
     AND (g.group_size = 0 OR ABS(NVL(SUM(b.bridge_weight), 0) - 1) < 0.000001)
    THEN 'PASS' ELSE 'FAIL'
  END
FROM MC_CAR_GROUP_DIM g
LEFT JOIN MC_CAR_GRP_BRIDGE b
  ON b.car_group_key = g.car_group_key
GROUP BY g.car_group_key, g.group_list, g.group_size
ORDER BY 1, 2;

/* ------------------------------------------------------------------------- */
/* E. Explicit fan-out checks for the two multi-valued source relationships.  */
/*    SOURCE_ROWS and MAPPED_ROWS must match.                                 */
/* ------------------------------------------------------------------------- */

WITH team_base AS (
  SELECT NVL(UPPER(TRIM(teamid)), '[UNKNOWN_TEAM]') AS team_code
  FROM MC_STG_MAINT_TEAM
  UNION
  SELECT NVL(UPPER(TRIM(teamid)), '[UNKNOWN_TEAM]')
  FROM MC_STG_MAINTENANCE
), memberships AS (
  SELECT DISTINCT
    NVL(UPPER(TRIM(teamid)), '[UNKNOWN_TEAM]') AS team_code,
    NVL(UPPER(TRIM(centerid)), '[UNKNOWN]') AS center_code
  FROM MC_STG_BELONGTO
), team_lists AS (
  SELECT
    t.team_code,
    NVL(LISTAGG(m.center_code, ',') WITHIN GROUP (ORDER BY m.center_code),
        '[NO_RESEARCH_CENTRE]') AS group_list
  FROM team_base t
  LEFT JOIN memberships m ON m.team_code = t.team_code
  GROUP BY t.team_code
), maintenance_mapping AS (
  SELECT m.rowid AS source_rowid, g.center_group_key
  FROM MC_STG_MAINTENANCE m
  JOIN team_lists tl
    ON tl.team_code = NVL(UPPER(TRIM(m.teamid)), '[UNKNOWN_TEAM]')
  JOIN MC_CENTER_GROUP_DIM g
    ON g.group_list = tl.group_list
)
SELECT
  'MAINTENANCE_TO_ONE_CENTER_GROUP' AS check_name,
  (SELECT COUNT(*) FROM MC_STG_MAINTENANCE) AS source_rows,
  COUNT(*) AS mapped_rows,
  CASE WHEN COUNT(*) = (SELECT COUNT(*) FROM MC_STG_MAINTENANCE)
       THEN 'PASS' ELSE 'FAIL' END AS status
FROM maintenance_mapping;


WITH accident_ids AS (
  SELECT DISTINCT NVL(UPPER(TRIM(accidentid)), '[UNKNOWN_ACCIDENT]') AS accident_code
  FROM MC_STG_ACCIDENTINFO
), memberships AS (
  SELECT DISTINCT
    NVL(UPPER(TRIM(accidentid)), '[UNKNOWN_ACCIDENT]') AS accident_code,
    NVL(UPPER(TRIM(registrationno)), '[UNKNOWN]') AS car_code
  FROM MC_STG_CARACCIDENT
), accident_lists AS (
  SELECT
    a.accident_code,
    NVL(LISTAGG(m.car_code, ',') WITHIN GROUP (ORDER BY m.car_code),
        '[NO_CAR]') AS group_list
  FROM accident_ids a
  LEFT JOIN memberships m ON m.accident_code = a.accident_code
  GROUP BY a.accident_code
), accident_mapping AS (
  SELECT a.rowid AS source_rowid, g.car_group_key
  FROM MC_STG_ACCIDENTINFO a
  JOIN accident_lists al
    ON al.accident_code = NVL(UPPER(TRIM(a.accidentid)), '[UNKNOWN_ACCIDENT]')
  JOIN MC_CAR_GROUP_DIM g
    ON g.group_list = al.group_list
)
SELECT
  'ACCIDENT_TO_ONE_CAR_GROUP' AS check_name,
  (SELECT COUNT(*) FROM MC_STG_ACCIDENTINFO) AS source_rows,
  COUNT(*) AS mapped_rows,
  CASE WHEN COUNT(*) = (SELECT COUNT(*) FROM MC_STG_ACCIDENTINFO)
       THEN 'PASS' ELSE 'FAIL' END AS status
FROM accident_mapping;

/* ------------------------------------------------------------------------- */
/* F. Seven questions specified in C3.                                       */
/* ------------------------------------------------------------------------- */

/* Q1. Booking records made by IT-faculty passengers in July using Bus. */
SELECT NVL(SUM(bf.booking_count), 0) AS july_it_bus_bookings
FROM MC_BOOKING_FACT bf
JOIN MC_MONTH_DIM md ON md.month_id = bf.month_id
JOIN MC_FACULTY_DIM fd ON fd.faculty_key = bf.faculty_key
JOIN MC_CAR_BODY_DIM cb ON cb.car_body_key = bf.car_body_key
WHERE md.month_number = 7
  AND (
    fd.faculty_code = 'IT'
    OR REGEXP_LIKE(UPPER(fd.faculty_name),
                   '(^|[^A-Z])IT([^A-Z]|$)|INFORMATION TECHNOLOGY')
  )
  AND UPPER(TRIM(cb.car_body_type)) = 'BUS';

/* Q2. Booking records made by each required passenger age group. */
SELECT
  ag.age_group_name,
  NVL(SUM(bf.booking_count), 0) AS booking_records
FROM MC_AGE_GROUP_DIM ag
LEFT JOIN MC_BOOKING_FACT bf
  ON bf.age_group_key = ag.age_group_key
WHERE ag.age_group_key IN (1, 2, 3)
GROUP BY ag.age_group_key, ag.age_group_name
ORDER BY ag.age_group_key;

/* Q3. Maintenance records whose team belongs to centre CE04. */
SELECT NVL(SUM(mf.maintenance_count), 0) AS ce04_maintenance_records
FROM MC_MAINT_FACT mf
JOIN MC_CENTER_GRP_BRIDGE br
  ON br.center_group_key = mf.center_group_key
JOIN MC_CENTER_DIM cd
  ON cd.center_key = br.center_key
WHERE UPPER(TRIM(cd.center_code)) = 'CE04';

/* Q4. Total maintenance cost by maintenance type for Mini Bus. */
SELECT
  mt.maintenance_type,
  mt.maintenance_description,
  SUM(mf.total_maintenance_cost) AS total_maintenance_cost
FROM MC_MAINT_FACT mf
JOIN MC_MAINT_TYPE_DIM mt
  ON mt.maintenance_type_key = mf.maintenance_type_key
JOIN MC_CAR_BODY_DIM cb
  ON cb.car_body_key = mf.car_body_key
WHERE REGEXP_REPLACE(UPPER(cb.car_body_type), '[^A-Z0-9]', '') = 'MINIBUS'
GROUP BY mt.maintenance_type, mt.maintenance_description
ORDER BY mt.maintenance_type;

/* Q5. Accidents in ZoneA involving Car01. */
SELECT NVL(SUM(af.accident_count), 0) AS zonea_car01_accidents
FROM MC_ACCIDENT_FACT af
JOIN MC_ACC_ZONE_DIM zd
  ON zd.accident_zone_key = af.accident_zone_key
JOIN MC_CAR_GRP_BRIDGE br
  ON br.car_group_key = af.car_group_key
JOIN MC_CAR_DIM cd
  ON cd.car_key = br.car_key
WHERE REGEXP_REPLACE(UPPER(zd.accident_zone), '[^A-Z0-9]', '') = 'ZONEA'
  AND REGEXP_REPLACE(UPPER(cd.car_code), '[^A-Z0-9]', '') = 'CAR01';

/* Q6. Number of ZoneB/Car06 accidents for each error code. */
SELECT
  ed.error_code,
  ed.error_message,
  SUM(af.accident_count) AS accident_records
FROM MC_ACCIDENT_FACT af
JOIN MC_ACC_ZONE_DIM zd
  ON zd.accident_zone_key = af.accident_zone_key
JOIN MC_ERROR_DIM ed
  ON ed.error_key = af.error_key
JOIN MC_CAR_GRP_BRIDGE br
  ON br.car_group_key = af.car_group_key
JOIN MC_CAR_DIM cd
  ON cd.car_key = br.car_key
WHERE REGEXP_REPLACE(UPPER(zd.accident_zone), '[^A-Z0-9]', '') = 'ZONEB'
  AND REGEXP_REPLACE(UPPER(cd.car_code), '[^A-Z0-9]', '') = 'CAR06'
GROUP BY ed.error_code, ed.error_message
ORDER BY ed.error_code;

/* Q7. Accidents with severe damage involving Car05. */
SELECT NVL(SUM(af.accident_count), 0) AS severe_car05_accidents
FROM MC_ACCIDENT_FACT af
JOIN MC_SEVERITY_DIM sd
  ON sd.severity_key = af.severity_key
JOIN MC_CAR_GRP_BRIDGE br
  ON br.car_group_key = af.car_group_key
JOIN MC_CAR_DIM cd
  ON cd.car_key = br.car_key
WHERE UPPER(sd.severity_name) LIKE '%SEVERE%'
  AND REGEXP_REPLACE(UPPER(cd.car_code), '[^A-Z0-9]', '') = 'CAR05';

/* ------------------------------------------------------------------------- */
/* G. Optional allocation examples (not used for the seven questions).        */
/* ------------------------------------------------------------------------- */

/* Allocated maintenance count; no-centre groups remain visible as UNALLOCATED. */
SELECT
  NVL(cd.center_code, '[UNALLOCATED]') AS center_code,
  SUM(
    mf.maintenance_count
    * CASE WHEN cg.group_size = 0 THEN 1 ELSE br.bridge_weight END
  ) AS allocated_maintenance_records
FROM MC_MAINT_FACT mf
JOIN MC_CENTER_GROUP_DIM cg
  ON cg.center_group_key = mf.center_group_key
LEFT JOIN MC_CENTER_GRP_BRIDGE br
  ON br.center_group_key = mf.center_group_key
LEFT JOIN MC_CENTER_DIM cd
  ON cd.center_key = br.center_key
GROUP BY NVL(cd.center_code, '[UNALLOCATED]')
ORDER BY center_code;

/* Allocated accident count; no-car groups remain visible as UNALLOCATED. */
SELECT
  NVL(cd.car_code, '[UNALLOCATED]') AS car_code,
  SUM(
    af.accident_count
    * CASE WHEN cg.group_size = 0 THEN 1 ELSE br.bridge_weight END
  ) AS allocated_accident_records
FROM MC_ACCIDENT_FACT af
JOIN MC_CAR_GROUP_DIM cg
  ON cg.car_group_key = af.car_group_key
LEFT JOIN MC_CAR_GRP_BRIDGE br
  ON br.car_group_key = af.car_group_key
LEFT JOIN MC_CAR_DIM cd
  ON cd.car_key = br.car_key
GROUP BY NVL(cd.car_code, '[UNALLOCATED]')
ORDER BY car_code;
