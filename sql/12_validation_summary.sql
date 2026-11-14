/*
  compact V1 validation (one result grid)
  Read only. Every STATUS value should be PASS.
*/

WITH
team_base AS (
  SELECT NVL(UPPER(TRIM(teamid)), '[UNKNOWN_TEAM]') AS team_code
  FROM MC_STG_MAINT_TEAM
  UNION
  SELECT NVL(UPPER(TRIM(teamid)), '[UNKNOWN_TEAM]')
  FROM MC_STG_MAINTENANCE
),
team_membership AS (
  SELECT DISTINCT
    NVL(UPPER(TRIM(teamid)), '[UNKNOWN_TEAM]') AS team_code,
    NVL(UPPER(TRIM(centerid)), '[UNKNOWN]') AS center_code
  FROM MC_STG_BELONGTO
),
team_lists AS (
  SELECT
    t.team_code,
    NVL(
      LISTAGG(m.center_code, ',') WITHIN GROUP (ORDER BY m.center_code),
      '[NO_RESEARCH_CENTRE]'
    ) AS group_list
  FROM team_base t
  LEFT JOIN team_membership m ON m.team_code = t.team_code
  GROUP BY t.team_code
),
maintenance_mapping AS (
  SELECT m.rowid AS source_rowid, g.center_group_key
  FROM MC_STG_MAINTENANCE m
  JOIN team_lists tl
    ON tl.team_code = NVL(UPPER(TRIM(m.teamid)), '[UNKNOWN_TEAM]')
  JOIN MC_CENTER_GROUP_DIM g ON g.group_list = tl.group_list
),
accident_ids AS (
  SELECT DISTINCT NVL(UPPER(TRIM(accidentid)), '[UNKNOWN_ACCIDENT]') AS accident_code
  FROM MC_STG_ACCIDENTINFO
),
car_membership AS (
  SELECT DISTINCT
    NVL(UPPER(TRIM(accidentid)), '[UNKNOWN_ACCIDENT]') AS accident_code,
    NVL(UPPER(TRIM(registrationno)), '[UNKNOWN]') AS car_code
  FROM MC_STG_CARACCIDENT
),
accident_lists AS (
  SELECT
    a.accident_code,
    NVL(
      LISTAGG(m.car_code, ',') WITHIN GROUP (ORDER BY m.car_code),
      '[NO_CAR]'
    ) AS group_list
  FROM accident_ids a
  LEFT JOIN car_membership m ON m.accident_code = a.accident_code
  GROUP BY a.accident_code
),
accident_mapping AS (
  SELECT a.rowid AS source_rowid, g.car_group_key
  FROM MC_STG_ACCIDENTINFO a
  JOIN accident_lists al
    ON al.accident_code = NVL(UPPER(TRIM(a.accidentid)), '[UNKNOWN_ACCIDENT]')
  JOIN MC_CAR_GROUP_DIM g ON g.group_list = al.group_list
),
checks AS (
  SELECT 1 AS check_order, 'V1_TARGET_TABLE_COUNT' AS check_name,
         (SELECT COUNT(*) FROM user_tables
          WHERE table_name IN (
            'MC_MONTH_DIM','MC_FACULTY_DIM','MC_AGE_GROUP_DIM',
            'MC_CAR_BODY_DIM','MC_MAINT_TYPE_DIM','MC_CENTER_DIM',
            'MC_CENTER_GROUP_DIM','MC_CENTER_GRP_BRIDGE','MC_CAR_DIM',
            'MC_CAR_GROUP_DIM','MC_CAR_GRP_BRIDGE','MC_ACC_ZONE_DIM',
            'MC_ERROR_DIM','MC_SEVERITY_DIM','MC_BOOKING_FACT',
            'MC_MAINT_FACT','MC_ACCIDENT_FACT'
          )) AS actual_value,
         17 AS expected_value
  FROM dual

  UNION ALL
  SELECT 2, 'BOOKING_RECORD_COUNT',
         (SELECT NVL(SUM(booking_count),0) FROM MC_BOOKING_FACT),
         (SELECT COUNT(*) FROM MC_STG_BOOKING)
  FROM dual

  UNION ALL
  SELECT 3, 'MAINTENANCE_RECORD_COUNT',
         (SELECT NVL(SUM(maintenance_count),0) FROM MC_MAINT_FACT),
         (SELECT COUNT(*) FROM MC_STG_MAINTENANCE)
  FROM dual

  UNION ALL
  SELECT 4, 'TOTAL_MAINTENANCE_COST',
         (SELECT NVL(SUM(total_maintenance_cost),0) FROM MC_MAINT_FACT),
         (SELECT NVL(SUM(NVL(maintenancecost,0)),0) FROM MC_STG_MAINTENANCE)
  FROM dual

  UNION ALL
  SELECT 5, 'ACCIDENT_RECORD_COUNT',
         (SELECT NVL(SUM(accident_count),0) FROM MC_ACCIDENT_FACT),
         (SELECT COUNT(*) FROM MC_STG_ACCIDENTINFO)
  FROM dual

  UNION ALL
  SELECT 6, 'BOOKING_DUPLICATE_GRAINS',
         (SELECT COUNT(*) FROM (
            SELECT month_id, faculty_key, age_group_key, car_body_key
            FROM MC_BOOKING_FACT
            GROUP BY month_id, faculty_key, age_group_key, car_body_key
            HAVING COUNT(*) > 1)), 0
  FROM dual

  UNION ALL
  SELECT 7, 'MAINTENANCE_DUPLICATE_GRAINS',
         (SELECT COUNT(*) FROM (
            SELECT car_body_key, maintenance_type_key, center_group_key
            FROM MC_MAINT_FACT
            GROUP BY car_body_key, maintenance_type_key, center_group_key
            HAVING COUNT(*) > 1)), 0
  FROM dual

  UNION ALL
  SELECT 8, 'ACCIDENT_DUPLICATE_GRAINS',
         (SELECT COUNT(*) FROM (
            SELECT car_group_key, accident_zone_key, error_key, severity_key
            FROM MC_ACCIDENT_FACT
            GROUP BY car_group_key, accident_zone_key, error_key, severity_key
            HAVING COUNT(*) > 1)), 0
  FROM dual

  UNION ALL
  SELECT 9, 'CENTER_BRIDGE_BAD_GROUPS',
         (SELECT COUNT(*) FROM (
            SELECT g.center_group_key
            FROM MC_CENTER_GROUP_DIM g
            LEFT JOIN MC_CENTER_GRP_BRIDGE b
              ON b.center_group_key = g.center_group_key
            GROUP BY g.center_group_key, g.group_size
            HAVING COUNT(b.center_key) <> g.group_size
                OR (g.group_size > 0
                    AND ABS(NVL(SUM(b.bridge_weight),0) - 1) >= 0.000001))), 0
  FROM dual

  UNION ALL
  SELECT 10, 'CAR_BRIDGE_BAD_GROUPS',
         (SELECT COUNT(*) FROM (
            SELECT g.car_group_key
            FROM MC_CAR_GROUP_DIM g
            LEFT JOIN MC_CAR_GRP_BRIDGE b
              ON b.car_group_key = g.car_group_key
            GROUP BY g.car_group_key, g.group_size
            HAVING COUNT(b.car_key) <> g.group_size
                OR (g.group_size > 0
                    AND ABS(NVL(SUM(b.bridge_weight),0) - 1) >= 0.000001))), 0
  FROM dual

  UNION ALL
  SELECT 11, 'MAINTENANCE_ONE_GROUP_MAPPING',
         (SELECT COUNT(*) FROM maintenance_mapping),
         (SELECT COUNT(*) FROM MC_STG_MAINTENANCE)
  FROM dual

  UNION ALL
  SELECT 12, 'ACCIDENT_ONE_GROUP_MAPPING',
         (SELECT COUNT(*) FROM accident_mapping),
         (SELECT COUNT(*) FROM MC_STG_ACCIDENTINFO)
  FROM dual
)
SELECT
  check_order,
  check_name,
  actual_value,
  expected_value,
  actual_value - expected_value AS difference,
  CASE WHEN actual_value = expected_value THEN 'PASS' ELSE 'FAIL' END AS status
FROM checks
ORDER BY check_order;
