/*
  Power BI decision-support dataset

  READ ONLY. Run after Version-1 validation passes.
  Grain of the result: one row per canonical car body type + seat count.

  Interpretation:
    * BOOKING_RECORDS and maintenance measures are unique source-event totals.
    * ACCIDENT_RECORDS_INVOLVING_BODY counts an accident once for each distinct
      body/seat combination represented in its involved-car group. It does not
      claim that a car caused the accident.
    * Accident data has no source date. Ratios against bookings are descriptive
      cross-sectional indicators, not time-aligned incident rates.
*/

WITH booking_by_body AS (
  SELECT
    cb.car_body_type,
    cb.number_of_seats,
    SUM(bf.booking_count) AS booking_records
  FROM MC_BOOKING_FACT bf
  JOIN MC_CAR_BODY_DIM cb
    ON cb.car_body_key = bf.car_body_key
  WHERE cb.car_body_type <> '[UNKNOWN]'
  GROUP BY cb.car_body_type, cb.number_of_seats
),
maintenance_by_body AS (
  SELECT
    cb.car_body_type,
    cb.number_of_seats,
    SUM(mf.maintenance_count) AS maintenance_records,
    SUM(mf.total_maintenance_cost) AS total_maintenance_cost
  FROM MC_MAINT_FACT mf
  JOIN MC_CAR_BODY_DIM cb
    ON cb.car_body_key = mf.car_body_key
  WHERE cb.car_body_type <> '[UNKNOWN]'
  GROUP BY cb.car_body_type, cb.number_of_seats
),
group_body_members AS (
  SELECT DISTINCT
    br.car_group_key,
    c.car_body_type,
    c.number_of_seats
  FROM MC_CAR_GRP_BRIDGE br
  JOIN MC_CAR_DIM c
    ON c.car_key = br.car_key
  WHERE c.car_body_type <> '[UNKNOWN]'
),
accident_by_body AS (
  SELECT
    gb.car_body_type,
    gb.number_of_seats,
    SUM(af.accident_count) AS accident_records_involving_body,
    SUM(CASE WHEN UPPER(sd.severity_name) LIKE '%SEVERE%'
             THEN af.accident_count ELSE 0 END) AS severe_accident_records
  FROM MC_ACCIDENT_FACT af
  JOIN group_body_members gb
    ON gb.car_group_key = af.car_group_key
  JOIN MC_SEVERITY_DIM sd
    ON sd.severity_key = af.severity_key
  GROUP BY gb.car_body_type, gb.number_of_seats
),
fleet_by_body AS (
  SELECT
    car_body_type,
    number_of_seats,
    COUNT(*) AS fleet_vehicles
  FROM MC_CAR_DIM
  WHERE car_body_type <> '[UNKNOWN]'
  GROUP BY car_body_type, number_of_seats
),
body_keys AS (
  SELECT car_body_type, number_of_seats FROM booking_by_body
  UNION
  SELECT car_body_type, number_of_seats FROM maintenance_by_body
  UNION
  SELECT car_body_type, number_of_seats FROM accident_by_body
  UNION
  SELECT car_body_type, number_of_seats FROM fleet_by_body
)
SELECT
  k.car_body_type,
  k.number_of_seats,
  NVL(f.fleet_vehicles, 0) AS fleet_vehicles,
  NVL(b.booking_records, 0) AS booking_records,
  NVL(m.maintenance_records, 0) AS maintenance_records,
  NVL(m.total_maintenance_cost, 0) AS total_maintenance_cost,
  NVL(a.accident_records_involving_body, 0) AS accident_records_involving_body,
  NVL(a.severe_accident_records, 0) AS severe_accident_records,
  ROUND(NVL(b.booking_records, 0) / NULLIF(f.fleet_vehicles, 0), 2)
    AS bookings_per_vehicle,
  ROUND(NVL(m.total_maintenance_cost, 0) / NULLIF(b.booking_records, 0), 2)
    AS maintenance_cost_per_booking,
  ROUND(100 * NVL(a.accident_records_involving_body, 0)
        / NULLIF(b.booking_records, 0), 2)
    AS accident_involvements_per_100_bookings,
  ROUND(100 * NVL(a.severe_accident_records, 0)
        / NULLIF(a.accident_records_involving_body, 0), 2)
    AS severe_share_pct
FROM body_keys k
LEFT JOIN booking_by_body b
  ON b.car_body_type = k.car_body_type
 AND b.number_of_seats = k.number_of_seats
LEFT JOIN maintenance_by_body m
  ON m.car_body_type = k.car_body_type
 AND m.number_of_seats = k.number_of_seats
LEFT JOIN accident_by_body a
  ON a.car_body_type = k.car_body_type
 AND a.number_of_seats = k.number_of_seats
LEFT JOIN fleet_by_body f
  ON f.car_body_type = k.car_body_type
 AND f.number_of_seats = k.number_of_seats
ORDER BY k.car_body_type, k.number_of_seats;

/*
  Suggested Power BI Web visuals after SQL reconciliation:
    1. Clustered column: Booking records by car body type / seat count.
    2. Combo chart: Maintenance cost per booking and bookings per vehicle.
    3. Clustered column: Accident involvements and severe accident records.

  Final titles and recommendation must reflect the verified data, and all
  values must reconcile to this query before screenshots are used.
*/
