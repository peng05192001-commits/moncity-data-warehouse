/*
  the seven required analysis answers in one grid.
  Read only.
*/

WITH results AS (
  SELECT
    1 AS question_no,
    1 AS item_order,
    'July IT-faculty Bus bookings' AS metric,
    'ALL' AS item,
    TO_CHAR(NVL(SUM(bf.booking_count), 0)) AS value
  FROM MC_BOOKING_FACT bf
  JOIN MC_MONTH_DIM md ON md.month_id = bf.month_id
  JOIN MC_FACULTY_DIM fd ON fd.faculty_key = bf.faculty_key
  JOIN MC_CAR_BODY_DIM cb ON cb.car_body_key = bf.car_body_key
  WHERE md.month_number = 7
    AND (
      fd.faculty_code = 'IT'
      OR REGEXP_LIKE(
           UPPER(fd.faculty_name),
           '(^|[^A-Z])IT([^A-Z]|$)|INFORMATION TECHNOLOGY'
         )
    )
    AND UPPER(TRIM(cb.car_body_type)) = 'BUS'

  UNION ALL
  SELECT
    2,
    ag.age_group_key,
    'Bookings by passenger age group',
    ag.age_group_name,
    TO_CHAR(NVL(SUM(bf.booking_count), 0))
  FROM MC_AGE_GROUP_DIM ag
  LEFT JOIN MC_BOOKING_FACT bf ON bf.age_group_key = ag.age_group_key
  WHERE ag.age_group_key IN (1, 2, 3)
  GROUP BY ag.age_group_key, ag.age_group_name

  UNION ALL
  SELECT
    3,
    1,
    'Maintenance records for centre CE04',
    'CE04',
    TO_CHAR(NVL(SUM(mf.maintenance_count), 0))
  FROM MC_MAINT_FACT mf
  JOIN MC_CENTER_GRP_BRIDGE br
    ON br.center_group_key = mf.center_group_key
  JOIN MC_CENTER_DIM cd ON cd.center_key = br.center_key
  WHERE UPPER(TRIM(cd.center_code)) = 'CE04'

  UNION ALL
  SELECT
    4,
    mt.maintenance_type_key,
    'Mini Bus maintenance cost by type',
    mt.maintenance_type || ' - ' || mt.maintenance_description,
    TO_CHAR(SUM(mf.total_maintenance_cost))
  FROM MC_MAINT_FACT mf
  JOIN MC_MAINT_TYPE_DIM mt
    ON mt.maintenance_type_key = mf.maintenance_type_key
  JOIN MC_CAR_BODY_DIM cb ON cb.car_body_key = mf.car_body_key
  WHERE REGEXP_REPLACE(UPPER(cb.car_body_type), '[^A-Z0-9]', '') = 'MINIBUS'
  GROUP BY mt.maintenance_type_key, mt.maintenance_type, mt.maintenance_description

  UNION ALL
  SELECT
    5,
    1,
    'ZoneA accidents involving Car01',
    'Car01',
    TO_CHAR(NVL(SUM(af.accident_count), 0))
  FROM MC_ACCIDENT_FACT af
  JOIN MC_ACC_ZONE_DIM zd ON zd.accident_zone_key = af.accident_zone_key
  JOIN MC_CAR_GRP_BRIDGE br ON br.car_group_key = af.car_group_key
  JOIN MC_CAR_DIM cd ON cd.car_key = br.car_key
  WHERE REGEXP_REPLACE(UPPER(zd.accident_zone), '[^A-Z0-9]', '') = 'ZONEA'
    AND REGEXP_REPLACE(UPPER(cd.car_code), '[^A-Z0-9]', '') = 'CAR01'

  UNION ALL
  SELECT
    6,
    ed.error_key,
    'ZoneB Car06 accidents by error',
    ed.error_code || ' - ' || ed.error_message,
    TO_CHAR(SUM(af.accident_count))
  FROM MC_ACCIDENT_FACT af
  JOIN MC_ACC_ZONE_DIM zd ON zd.accident_zone_key = af.accident_zone_key
  JOIN MC_ERROR_DIM ed ON ed.error_key = af.error_key
  JOIN MC_CAR_GRP_BRIDGE br ON br.car_group_key = af.car_group_key
  JOIN MC_CAR_DIM cd ON cd.car_key = br.car_key
  WHERE REGEXP_REPLACE(UPPER(zd.accident_zone), '[^A-Z0-9]', '') = 'ZONEB'
    AND REGEXP_REPLACE(UPPER(cd.car_code), '[^A-Z0-9]', '') = 'CAR06'
  GROUP BY ed.error_key, ed.error_code, ed.error_message

  UNION ALL
  SELECT
    7,
    1,
    'Severe-damage accidents involving Car05',
    'Car05',
    TO_CHAR(NVL(SUM(af.accident_count), 0))
  FROM MC_ACCIDENT_FACT af
  JOIN MC_SEVERITY_DIM sd ON sd.severity_key = af.severity_key
  JOIN MC_CAR_GRP_BRIDGE br ON br.car_group_key = af.car_group_key
  JOIN MC_CAR_DIM cd ON cd.car_key = br.car_key
  WHERE UPPER(sd.severity_name) LIKE '%SEVERE%'
    AND REGEXP_REPLACE(UPPER(cd.car_code), '[^A-Z0-9]', '') = 'CAR05'
)
SELECT question_no, metric, item, value
FROM results
ORDER BY question_no, item_order;
