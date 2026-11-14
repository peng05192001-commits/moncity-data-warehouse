/*
  Version 1 warehouse (highest required aggregation)

  TARGET
    All created objects use the MC_ prefix and are created only in the
    currently connected analyst schema.

  SOURCE SAFETY
    MONCITY tables are read only. This script never updates, deletes, truncates,
    drops, or otherwise changes any MONCITY object.

  DESIGN
    * Booking fact grain:
        one row per booking month x faculty x passenger age group
        x car body type/seat count.
    * Maintenance fact grain:
        one row per car body type/seat count x maintenance type
        x distinct research-centre membership group.
    * Accident fact grain:
        one row per distinct involved-car group x accident zone
        x error code x damage severity.

  MULTI-VALUED RELATIONSHIPS
    * A maintenance team may belong to several research centres. The centre
      membership set is formed once per TEAMID, then represented by a centre
      group dimension and bridge.
    * An accident may involve several cars. The vehicle membership set is
      formed once per ACCIDENTID before the accident fact is aggregated. This
      avoids multiplying one accident by its number of involved cars.
    * GROUP_LIST and WEIGHT_FACTOR are retained in each group dimension as
      required by the analysis. Bridge weights are also exposed for allocated
      analyses. For a question filtering a single centre/car, use the unweighted
      fact count after the bridge join. Use weights only when allocating totals
      across every member of a multi-member group.

  DATA-QUALITY PRECONDITION
    Run 04_clean_staging.sql first. Every load below reads the analyst
    MC_STG_ cleaned tables; MONCITY remains read only. Reserved
    [UNKNOWN]/[UNCLASSIFIED] members preserve valid information whose original
    relationship cannot be recovered.

  FIRST-RUN BEHAVIOUR
    A read-only preflight confirmed that no non-staging MC_ warehouse tables
    existed before execution, so this script contains no DROP operation.
*/

/* ------------------------------------------------------------------------- */
/* 1. Conformed dimensions used by the booking fact.                          */
/* ------------------------------------------------------------------------- */

CREATE TABLE MC_MONTH_DIM AS
WITH month_values AS (
  SELECT DISTINCT TRUNC(bookingdate, 'MM') AS month_start_date
  FROM MC_STG_BOOKING
  WHERE bookingdate IS NOT NULL
), unknown_month AS (
  SELECT CAST(NULL AS DATE) AS month_start_date
  FROM dual
)
SELECT
  CASE
    WHEN month_start_date IS NULL THEN 0
    ELSE TO_NUMBER(TO_CHAR(month_start_date, 'YYYYMM'))
  END AS month_id,
  month_start_date,
  CASE WHEN month_start_date IS NULL THEN NULL
       ELSE EXTRACT(YEAR FROM month_start_date) END AS calendar_year,
  CASE WHEN month_start_date IS NULL THEN NULL
       ELSE EXTRACT(MONTH FROM month_start_date) END AS month_number,
  CASE WHEN month_start_date IS NULL THEN '[UNKNOWN]'
       ELSE TO_CHAR(month_start_date, 'FMMonth', 'NLS_DATE_LANGUAGE=English') END AS month_name,
  CASE WHEN month_start_date IS NULL THEN '[UNKNOWN]'
       ELSE TO_CHAR(month_start_date, 'YYYY-MM') END AS month_label
FROM (
  SELECT month_start_date FROM month_values
  UNION ALL
  SELECT month_start_date FROM unknown_month
);

ALTER TABLE MC_MONTH_DIM
  ADD CONSTRAINT MC_MONTH_PK PRIMARY KEY (month_id);


CREATE TABLE MC_FACULTY_DIM AS
WITH faculty_ids AS (
  SELECT NVL(UPPER(TRIM(facultyid)), '[UNKNOWN]') AS faculty_code
  FROM MC_STG_FACULTY
  UNION
  SELECT NVL(UPPER(TRIM(facultyid)), '[UNKNOWN]')
  FROM MC_STG_PASSENGER
  UNION
  SELECT '[UNKNOWN]' FROM dual
), faculty_values AS (
  SELECT
    UPPER(TRIM(facultyid)) AS faculty_code,
    MAX(TRIM(facultyname)) AS faculty_name,
    MAX(UPPER(TRIM(zone))) AS faculty_zone
  FROM MC_STG_FACULTY
  WHERE facultyid IS NOT NULL
  GROUP BY UPPER(TRIM(facultyid))
)
SELECT
  DENSE_RANK() OVER (ORDER BY i.faculty_code) AS faculty_key,
  i.faculty_code,
  NVL(v.faculty_name, '[UNKNOWN]') AS faculty_name,
  NVL(v.faculty_zone, '[UNKNOWN]') AS faculty_zone
FROM faculty_ids i
LEFT JOIN faculty_values v
  ON v.faculty_code = i.faculty_code;

ALTER TABLE MC_FACULTY_DIM
  ADD CONSTRAINT MC_FACULTY_PK PRIMARY KEY (faculty_key);
ALTER TABLE MC_FACULTY_DIM
  ADD CONSTRAINT MC_FACULTY_UK UNIQUE (faculty_code);


CREATE TABLE MC_AGE_GROUP_DIM AS
SELECT 1 AS age_group_key, 'YOUNG_ADULT' AS age_group_code,
       'Young adults (18-35)' AS age_group_name, 18 AS min_age, 35 AS max_age
FROM dual
UNION ALL
SELECT 2, 'MIDDLE_AGED', 'Middle-aged adults (36-59)', 36, 59 FROM dual
UNION ALL
SELECT 3, 'OLD_AGED', 'Old-aged adults (60+)', 60, CAST(NULL AS NUMBER) FROM dual
UNION ALL
SELECT 0, 'UNCLASSIFIED', '[UNCLASSIFIED]', CAST(NULL AS NUMBER), CAST(NULL AS NUMBER)
FROM dual;

ALTER TABLE MC_AGE_GROUP_DIM
  ADD CONSTRAINT MC_AGE_GROUP_PK PRIMARY KEY (age_group_key);


CREATE TABLE MC_CAR_BODY_DIM AS
WITH car_shapes AS (
  SELECT DISTINCT
    NVL(UPPER(TRIM(carbodytype)), '[UNKNOWN]') AS car_body_type,
    NVL(numseats, -1) AS number_of_seats
  FROM MC_STG_CAR
), unknown_shape AS (
  SELECT '[UNKNOWN]' AS car_body_type, -1 AS number_of_seats
  FROM dual
), all_shapes AS (
  SELECT car_body_type, number_of_seats FROM car_shapes
  UNION
  SELECT car_body_type, number_of_seats FROM unknown_shape
)
SELECT
  DENSE_RANK() OVER (ORDER BY car_body_type, number_of_seats) AS car_body_key,
  car_body_type,
  number_of_seats
FROM all_shapes;

ALTER TABLE MC_CAR_BODY_DIM
  ADD CONSTRAINT MC_CAR_BODY_PK PRIMARY KEY (car_body_key);
ALTER TABLE MC_CAR_BODY_DIM
  ADD CONSTRAINT MC_CAR_BODY_UK UNIQUE (car_body_type, number_of_seats);

/* ------------------------------------------------------------------------- */
/* 2. Maintenance dimensions and research-centre group bridge.                */
/* ------------------------------------------------------------------------- */

CREATE TABLE MC_MAINT_TYPE_DIM AS
WITH type_codes AS (
  SELECT NVL(UPPER(TRIM(maintenancetype)), '[UNKNOWN]') AS maintenance_type
  FROM MC_STG_MAINT_TYPE
  UNION
  SELECT NVL(UPPER(TRIM(maintenancetype)), '[UNKNOWN]')
  FROM MC_STG_MAINTENANCE
  UNION
  SELECT '[UNKNOWN]' FROM dual
), type_values AS (
  SELECT
    UPPER(TRIM(maintenancetype)) AS maintenance_type,
    MAX(TRIM(maintenancedescription)) AS maintenance_description
  FROM MC_STG_MAINT_TYPE
  WHERE maintenancetype IS NOT NULL
  GROUP BY UPPER(TRIM(maintenancetype))
)
SELECT
  DENSE_RANK() OVER (ORDER BY c.maintenance_type) AS maintenance_type_key,
  c.maintenance_type,
  NVL(v.maintenance_description, '[UNKNOWN]') AS maintenance_description
FROM type_codes c
LEFT JOIN type_values v
  ON v.maintenance_type = c.maintenance_type;

ALTER TABLE MC_MAINT_TYPE_DIM
  ADD CONSTRAINT MC_MTYPE_PK PRIMARY KEY (maintenance_type_key);
ALTER TABLE MC_MAINT_TYPE_DIM
  ADD CONSTRAINT MC_MTYPE_UK UNIQUE (maintenance_type);


CREATE TABLE MC_CENTER_DIM AS
WITH center_codes AS (
  SELECT NVL(UPPER(TRIM(centerid)), '[UNKNOWN]') AS center_code
  FROM MC_STG_RESEARCH_CENTER
  UNION
  SELECT NVL(UPPER(TRIM(centerid)), '[UNKNOWN]')
  FROM MC_STG_BELONGTO
  UNION
  SELECT '[UNKNOWN]' FROM dual
), center_values AS (
  SELECT
    UPPER(TRIM(centerid)) AS center_code,
    MAX(TRIM(centername)) AS center_name,
    MAX(phone) AS phone,
    MAX(TRIM(openinghour)) AS opening_hour
  FROM MC_STG_RESEARCH_CENTER
  WHERE centerid IS NOT NULL
  GROUP BY UPPER(TRIM(centerid))
)
SELECT
  DENSE_RANK() OVER (ORDER BY c.center_code) AS center_key,
  c.center_code,
  NVL(v.center_name, '[UNKNOWN]') AS center_name,
  v.phone,
  v.opening_hour
FROM center_codes c
LEFT JOIN center_values v
  ON v.center_code = c.center_code;

ALTER TABLE MC_CENTER_DIM
  ADD CONSTRAINT MC_CENTER_PK PRIMARY KEY (center_key);
ALTER TABLE MC_CENTER_DIM
  ADD CONSTRAINT MC_CENTER_UK UNIQUE (center_code);


CREATE TABLE MC_CENTER_GROUP_DIM AS
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
    NVL(
      LISTAGG(m.center_code, ',') WITHIN GROUP (ORDER BY m.center_code),
      '[NO_RESEARCH_CENTRE]'
    ) AS group_list,
    COUNT(m.center_code) AS group_size
  FROM team_base t
  LEFT JOIN memberships m
    ON m.team_code = t.team_code
  GROUP BY t.team_code
), distinct_lists AS (
  SELECT DISTINCT group_list, group_size
  FROM team_lists
)
SELECT
  DENSE_RANK() OVER (ORDER BY group_list) AS center_group_key,
  group_list,
  group_size,
  CASE WHEN group_size > 0 THEN 1 / group_size ELSE 1 END AS weight_factor
FROM distinct_lists;

ALTER TABLE MC_CENTER_GROUP_DIM
  ADD CONSTRAINT MC_CGROUP_PK PRIMARY KEY (center_group_key);


CREATE TABLE MC_CENTER_GRP_BRIDGE AS
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
    NVL(
      LISTAGG(m.center_code, ',') WITHIN GROUP (ORDER BY m.center_code),
      '[NO_RESEARCH_CENTRE]'
    ) AS group_list
  FROM team_base t
  LEFT JOIN memberships m
    ON m.team_code = t.team_code
  GROUP BY t.team_code
)
SELECT DISTINCT
  g.center_group_key,
  c.center_key,
  g.weight_factor AS bridge_weight
FROM team_lists tl
JOIN memberships m
  ON m.team_code = tl.team_code
JOIN MC_CENTER_GROUP_DIM g
  ON g.group_list = tl.group_list
JOIN MC_CENTER_DIM c
  ON c.center_code = m.center_code;

ALTER TABLE MC_CENTER_GRP_BRIDGE
  ADD CONSTRAINT MC_CGB_PK PRIMARY KEY (center_group_key, center_key);
ALTER TABLE MC_CENTER_GRP_BRIDGE
  ADD CONSTRAINT MC_CGB_GRP_FK FOREIGN KEY (center_group_key)
      REFERENCES MC_CENTER_GROUP_DIM (center_group_key);
ALTER TABLE MC_CENTER_GRP_BRIDGE
  ADD CONSTRAINT MC_CGB_CTR_FK FOREIGN KEY (center_key)
      REFERENCES MC_CENTER_DIM (center_key);

/* ------------------------------------------------------------------------- */
/* 3. Accident dimensions and involved-car group bridge.                      */
/* ------------------------------------------------------------------------- */

CREATE TABLE MC_CAR_DIM AS
WITH car_codes AS (
  SELECT NVL(UPPER(TRIM(registrationno)), '[UNKNOWN]') AS car_code
  FROM MC_STG_CAR
  UNION
  SELECT NVL(UPPER(TRIM(registrationno)), '[UNKNOWN]')
  FROM MC_STG_CARACCIDENT
  UNION
  SELECT '[UNKNOWN]' FROM dual
), car_values AS (
  SELECT
    UPPER(TRIM(registrationno)) AS car_code,
    MAX(TRIM(carmodel)) AS car_model,
    MAX(manufacturingyear) AS manufacturing_year,
    MAX(UPPER(TRIM(carbodytype))) AS car_body_type,
    MAX(numseats) AS number_of_seats
  FROM MC_STG_CAR
  WHERE registrationno IS NOT NULL
  GROUP BY UPPER(TRIM(registrationno))
)
SELECT
  DENSE_RANK() OVER (ORDER BY c.car_code) AS car_key,
  c.car_code,
  NVL(v.car_model, '[UNKNOWN]') AS car_model,
  v.manufacturing_year,
  NVL(v.car_body_type, '[UNKNOWN]') AS car_body_type,
  NVL(v.number_of_seats, -1) AS number_of_seats
FROM car_codes c
LEFT JOIN car_values v
  ON v.car_code = c.car_code;

ALTER TABLE MC_CAR_DIM
  ADD CONSTRAINT MC_CAR_PK PRIMARY KEY (car_key);
ALTER TABLE MC_CAR_DIM
  ADD CONSTRAINT MC_CAR_UK UNIQUE (car_code);


CREATE TABLE MC_CAR_GROUP_DIM AS
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
    NVL(
      LISTAGG(m.car_code, ',') WITHIN GROUP (ORDER BY m.car_code),
      '[NO_CAR]'
    ) AS group_list,
    COUNT(m.car_code) AS group_size
  FROM accident_ids a
  LEFT JOIN memberships m
    ON m.accident_code = a.accident_code
  GROUP BY a.accident_code
), distinct_lists AS (
  SELECT DISTINCT group_list, group_size
  FROM accident_lists
)
SELECT
  DENSE_RANK() OVER (ORDER BY group_list) AS car_group_key,
  group_list,
  group_size,
  CASE WHEN group_size > 0 THEN 1 / group_size ELSE 1 END AS weight_factor
FROM distinct_lists;

ALTER TABLE MC_CAR_GROUP_DIM
  ADD CONSTRAINT MC_CARGROUP_PK PRIMARY KEY (car_group_key);


CREATE TABLE MC_CAR_GRP_BRIDGE AS
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
    NVL(
      LISTAGG(m.car_code, ',') WITHIN GROUP (ORDER BY m.car_code),
      '[NO_CAR]'
    ) AS group_list
  FROM accident_ids a
  LEFT JOIN memberships m
    ON m.accident_code = a.accident_code
  GROUP BY a.accident_code
)
SELECT DISTINCT
  g.car_group_key,
  c.car_key,
  g.weight_factor AS bridge_weight
FROM accident_lists al
JOIN memberships m
  ON m.accident_code = al.accident_code
JOIN MC_CAR_GROUP_DIM g
  ON g.group_list = al.group_list
JOIN MC_CAR_DIM c
  ON c.car_code = m.car_code;

ALTER TABLE MC_CAR_GRP_BRIDGE
  ADD CONSTRAINT MC_CARB_PK PRIMARY KEY (car_group_key, car_key);
ALTER TABLE MC_CAR_GRP_BRIDGE
  ADD CONSTRAINT MC_CARB_GRP_FK FOREIGN KEY (car_group_key)
      REFERENCES MC_CAR_GROUP_DIM (car_group_key);
ALTER TABLE MC_CAR_GRP_BRIDGE
  ADD CONSTRAINT MC_CARB_CAR_FK FOREIGN KEY (car_key)
      REFERENCES MC_CAR_DIM (car_key);


CREATE TABLE MC_ACC_ZONE_DIM AS
WITH zone_values AS (
  SELECT DISTINCT NVL(UPPER(TRIM(accidentzone)), '[UNKNOWN]') AS accident_zone
  FROM MC_STG_ACCIDENTINFO
  UNION
  SELECT '[UNKNOWN]' FROM dual
)
SELECT
  DENSE_RANK() OVER (ORDER BY accident_zone) AS accident_zone_key,
  accident_zone
FROM zone_values;

ALTER TABLE MC_ACC_ZONE_DIM
  ADD CONSTRAINT MC_AZONE_PK PRIMARY KEY (accident_zone_key);
ALTER TABLE MC_ACC_ZONE_DIM
  ADD CONSTRAINT MC_AZONE_UK UNIQUE (accident_zone);


CREATE TABLE MC_ERROR_DIM AS
WITH error_codes AS (
  SELECT NVL(UPPER(TRIM(errorcode)), '[UNKNOWN]') AS error_code
  FROM MC_STG_ERROR
  UNION
  SELECT NVL(UPPER(TRIM(errorcode)), '[UNKNOWN]')
  FROM MC_STG_ACCIDENTINFO
  UNION
  SELECT '[UNKNOWN]' FROM dual
), error_values AS (
  SELECT
    UPPER(TRIM(errorcode)) AS error_code,
    MAX(TRIM(errormessage)) AS error_message
  FROM MC_STG_ERROR
  WHERE errorcode IS NOT NULL
  GROUP BY UPPER(TRIM(errorcode))
)
SELECT
  DENSE_RANK() OVER (ORDER BY c.error_code) AS error_key,
  c.error_code,
  NVL(v.error_message, '[UNKNOWN]') AS error_message
FROM error_codes c
LEFT JOIN error_values v
  ON v.error_code = c.error_code;

ALTER TABLE MC_ERROR_DIM
  ADD CONSTRAINT MC_ERROR_PK PRIMARY KEY (error_key);
ALTER TABLE MC_ERROR_DIM
  ADD CONSTRAINT MC_ERROR_UK UNIQUE (error_code);


CREATE TABLE MC_SEVERITY_DIM AS
WITH severity_values AS (
  SELECT DISTINCT
    NVL(UPPER(TRIM(car_damage_severity)), '[UNKNOWN]') AS severity_name
  FROM MC_STG_ACCIDENTINFO
  UNION
  SELECT '[UNKNOWN]' FROM dual
)
SELECT
  DENSE_RANK() OVER (ORDER BY severity_name) AS severity_key,
  severity_name
FROM severity_values;

ALTER TABLE MC_SEVERITY_DIM
  ADD CONSTRAINT MC_SEVERITY_PK PRIMARY KEY (severity_key);
ALTER TABLE MC_SEVERITY_DIM
  ADD CONSTRAINT MC_SEVERITY_UK UNIQUE (severity_name);

/* ------------------------------------------------------------------------- */
/* 4. Highest-aggregation fact tables.                                        */
/* ------------------------------------------------------------------------- */

/*
  Grain: one row per month x faculty x age group x car body/seat combination.
*/
CREATE TABLE MC_BOOKING_FACT AS
WITH passenger_canon AS (
  SELECT
    NVL(UPPER(TRIM(passengerid)), '[UNKNOWN_PASSENGER]') AS passenger_code,
    MAX(NVL(UPPER(TRIM(facultyid)), '[UNKNOWN]')) AS faculty_code,
    MAX(passengerage) AS passenger_age
  FROM MC_STG_PASSENGER
  GROUP BY NVL(UPPER(TRIM(passengerid)), '[UNKNOWN_PASSENGER]')
), car_canon AS (
  SELECT
    NVL(UPPER(TRIM(registrationno)), '[UNKNOWN]') AS car_code,
    MAX(NVL(UPPER(TRIM(carbodytype)), '[UNKNOWN]')) AS car_body_type,
    MAX(NVL(numseats, -1)) AS number_of_seats
  FROM MC_STG_CAR
  GROUP BY NVL(UPPER(TRIM(registrationno)), '[UNKNOWN]')
), booking_rows AS (
  SELECT
    CASE WHEN b.bookingdate IS NULL THEN 0
         ELSE TO_NUMBER(TO_CHAR(b.bookingdate, 'YYYYMM')) END AS month_id,
    NVL(p.faculty_code, '[UNKNOWN]') AS faculty_code,
    CASE
      WHEN p.passenger_age BETWEEN 18 AND 35 THEN 1
      WHEN p.passenger_age BETWEEN 36 AND 59 THEN 2
      WHEN p.passenger_age >= 60 THEN 3
      ELSE 0
    END AS age_group_key,
    NVL(c.car_body_type, '[UNKNOWN]') AS car_body_type,
    NVL(c.number_of_seats, -1) AS number_of_seats
  FROM MC_STG_BOOKING b
  LEFT JOIN passenger_canon p
    ON p.passenger_code = NVL(UPPER(TRIM(b.passengerid)), '[UNKNOWN_PASSENGER]')
  LEFT JOIN car_canon c
    ON c.car_code = NVL(UPPER(TRIM(b.registrationno)), '[UNKNOWN]')
)
SELECT
  r.month_id,
  f.faculty_key,
  r.age_group_key,
  cb.car_body_key,
  COUNT(*) AS booking_count
FROM booking_rows r
JOIN MC_FACULTY_DIM f
  ON f.faculty_code = r.faculty_code
JOIN MC_AGE_GROUP_DIM ag
  ON ag.age_group_key = r.age_group_key
JOIN MC_CAR_BODY_DIM cb
  ON cb.car_body_type = r.car_body_type
 AND cb.number_of_seats = r.number_of_seats
JOIN MC_MONTH_DIM md
  ON md.month_id = r.month_id
GROUP BY r.month_id, f.faculty_key, r.age_group_key, cb.car_body_key;

ALTER TABLE MC_BOOKING_FACT
  ADD CONSTRAINT MC_BFACT_PK
      PRIMARY KEY (month_id, faculty_key, age_group_key, car_body_key);
ALTER TABLE MC_BOOKING_FACT
  ADD CONSTRAINT MC_BF_MONTH_FK FOREIGN KEY (month_id)
      REFERENCES MC_MONTH_DIM (month_id);
ALTER TABLE MC_BOOKING_FACT
  ADD CONSTRAINT MC_BF_FAC_FK FOREIGN KEY (faculty_key)
      REFERENCES MC_FACULTY_DIM (faculty_key);
ALTER TABLE MC_BOOKING_FACT
  ADD CONSTRAINT MC_BF_AGE_FK FOREIGN KEY (age_group_key)
      REFERENCES MC_AGE_GROUP_DIM (age_group_key);
ALTER TABLE MC_BOOKING_FACT
  ADD CONSTRAINT MC_BF_BODY_FK FOREIGN KEY (car_body_key)
      REFERENCES MC_CAR_BODY_DIM (car_body_key);

COMMENT ON TABLE MC_BOOKING_FACT IS
  'Grain: month x faculty x passenger age group x car body type/seat count';


/*
  Grain: one row per car body/seat combination x maintenance type
         x research-centre membership group.
*/
CREATE TABLE MC_MAINT_FACT AS
WITH car_canon AS (
  SELECT
    NVL(UPPER(TRIM(registrationno)), '[UNKNOWN]') AS car_code,
    MAX(NVL(UPPER(TRIM(carbodytype)), '[UNKNOWN]')) AS car_body_type,
    MAX(NVL(numseats, -1)) AS number_of_seats
  FROM MC_STG_CAR
  GROUP BY NVL(UPPER(TRIM(registrationno)), '[UNKNOWN]')
), team_base AS (
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
    NVL(
      LISTAGG(m.center_code, ',') WITHIN GROUP (ORDER BY m.center_code),
      '[NO_RESEARCH_CENTRE]'
    ) AS group_list
  FROM team_base t
  LEFT JOIN memberships m
    ON m.team_code = t.team_code
  GROUP BY t.team_code
), maintenance_rows AS (
  SELECT
    NVL(c.car_body_type, '[UNKNOWN]') AS car_body_type,
    NVL(c.number_of_seats, -1) AS number_of_seats,
    NVL(UPPER(TRIM(m.maintenancetype)), '[UNKNOWN]') AS maintenance_type,
    tl.group_list,
    NVL(m.maintenancecost, 0) AS maintenance_cost
  FROM MC_STG_MAINTENANCE m
  LEFT JOIN car_canon c
    ON c.car_code = NVL(UPPER(TRIM(m.registrationno)), '[UNKNOWN]')
  JOIN team_lists tl
    ON tl.team_code = NVL(UPPER(TRIM(m.teamid)), '[UNKNOWN_TEAM]')
)
SELECT
  cb.car_body_key,
  mt.maintenance_type_key,
  cg.center_group_key,
  COUNT(*) AS maintenance_count,
  SUM(r.maintenance_cost) AS total_maintenance_cost
FROM maintenance_rows r
JOIN MC_CAR_BODY_DIM cb
  ON cb.car_body_type = r.car_body_type
 AND cb.number_of_seats = r.number_of_seats
JOIN MC_MAINT_TYPE_DIM mt
  ON mt.maintenance_type = r.maintenance_type
JOIN MC_CENTER_GROUP_DIM cg
  ON cg.group_list = r.group_list
GROUP BY cb.car_body_key, mt.maintenance_type_key, cg.center_group_key;

ALTER TABLE MC_MAINT_FACT
  ADD CONSTRAINT MC_MFACT_PK
      PRIMARY KEY (car_body_key, maintenance_type_key, center_group_key);
ALTER TABLE MC_MAINT_FACT
  ADD CONSTRAINT MC_MF_BODY_FK FOREIGN KEY (car_body_key)
      REFERENCES MC_CAR_BODY_DIM (car_body_key);
ALTER TABLE MC_MAINT_FACT
  ADD CONSTRAINT MC_MF_TYPE_FK FOREIGN KEY (maintenance_type_key)
      REFERENCES MC_MAINT_TYPE_DIM (maintenance_type_key);
ALTER TABLE MC_MAINT_FACT
  ADD CONSTRAINT MC_MF_CGRP_FK FOREIGN KEY (center_group_key)
      REFERENCES MC_CENTER_GROUP_DIM (center_group_key);

COMMENT ON TABLE MC_MAINT_FACT IS
  'Grain: car body type/seat count x maintenance type x centre membership group';


/*
  Grain: one row per involved-car group x accident zone x error code
         x damage severity.
*/
CREATE TABLE MC_ACCIDENT_FACT AS
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
    NVL(
      LISTAGG(m.car_code, ',') WITHIN GROUP (ORDER BY m.car_code),
      '[NO_CAR]'
    ) AS group_list
  FROM accident_ids a
  LEFT JOIN memberships m
    ON m.accident_code = a.accident_code
  GROUP BY a.accident_code
), accident_rows AS (
  SELECT
    al.group_list,
    NVL(UPPER(TRIM(a.accidentzone)), '[UNKNOWN]') AS accident_zone,
    NVL(UPPER(TRIM(a.errorcode)), '[UNKNOWN]') AS error_code,
    NVL(UPPER(TRIM(a.car_damage_severity)), '[UNKNOWN]') AS severity_name
  FROM MC_STG_ACCIDENTINFO a
  JOIN accident_lists al
    ON al.accident_code = NVL(UPPER(TRIM(a.accidentid)), '[UNKNOWN_ACCIDENT]')
)
SELECT
  cg.car_group_key,
  z.accident_zone_key,
  e.error_key,
  s.severity_key,
  COUNT(*) AS accident_count
FROM accident_rows r
JOIN MC_CAR_GROUP_DIM cg
  ON cg.group_list = r.group_list
JOIN MC_ACC_ZONE_DIM z
  ON z.accident_zone = r.accident_zone
JOIN MC_ERROR_DIM e
  ON e.error_code = r.error_code
JOIN MC_SEVERITY_DIM s
  ON s.severity_name = r.severity_name
GROUP BY cg.car_group_key, z.accident_zone_key, e.error_key, s.severity_key;

ALTER TABLE MC_ACCIDENT_FACT
  ADD CONSTRAINT MC_AFACT_PK
      PRIMARY KEY (car_group_key, accident_zone_key, error_key, severity_key);
ALTER TABLE MC_ACCIDENT_FACT
  ADD CONSTRAINT MC_AF_CGRP_FK FOREIGN KEY (car_group_key)
      REFERENCES MC_CAR_GROUP_DIM (car_group_key);
ALTER TABLE MC_ACCIDENT_FACT
  ADD CONSTRAINT MC_AF_ZONE_FK FOREIGN KEY (accident_zone_key)
      REFERENCES MC_ACC_ZONE_DIM (accident_zone_key);
ALTER TABLE MC_ACCIDENT_FACT
  ADD CONSTRAINT MC_AF_ERROR_FK FOREIGN KEY (error_key)
      REFERENCES MC_ERROR_DIM (error_key);
ALTER TABLE MC_ACCIDENT_FACT
  ADD CONSTRAINT MC_AF_SEV_FK FOREIGN KEY (severity_key)
      REFERENCES MC_SEVERITY_DIM (severity_key);

COMMENT ON TABLE MC_ACCIDENT_FACT IS
  'Grain: involved-car group x accident zone x error code x damage severity';

COMMIT;

/* End of Version-1 creation script. Run 11_validate_warehouse.sql next. */
