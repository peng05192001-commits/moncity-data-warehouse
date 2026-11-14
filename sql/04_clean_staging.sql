/*
  cleaned staging layer

  SOURCE SAFETY
    MONCITY remains read only. All repairs are materialised only in the
    analyst current schema using the MC_STG_ prefix.

  VERIFIED REPAIRS
    1. Remove one exact duplicate BOOKING row for BOOKINGID T1218.
    2. Replace a missing ACCIDENTID with a deterministic technical repair ID.
    3. Represent accidents with no car relationship using [UNKNOWN] car.
    4. Convert the invalid negative maintenance cost -200 to 200.
    5. Add unmapped ERROR codes (Error010) to the cleaned error master with an
       explicit placeholder description instead of discarding the accident.
*/

/*
  First-run script. A read-only preflight confirmed that no MC_STG_ tables
  existed before execution. It therefore contains no DROP operation.
*/

/* Canonical source masters. */
CREATE TABLE MC_STG_FACULTY AS
SELECT UPPER(TRIM(facultyid)) AS facultyid,
       TRIM(facultyname) AS facultyname,
       UPPER(TRIM(zone)) AS zone
FROM MONCITY.FACULTY;

CREATE TABLE MC_STG_PASSENGER AS
SELECT UPPER(TRIM(passengerid)) AS passengerid,
       TRIM(passengername) AS passengername,
       TRIM(passengerrole) AS passengerrole,
       TRIM(passengergender) AS passengergender,
       passengerage,
       UPPER(TRIM(facultyid)) AS facultyid
FROM MONCITY.PASSENGER;

CREATE TABLE MC_STG_CAR AS
SELECT UPPER(TRIM(registrationno)) AS registrationno,
       TRIM(carmodel) AS carmodel,
       manufacturingyear,
       UPPER(TRIM(carbodytype)) AS carbodytype,
       numseats
FROM MONCITY.CAR
UNION ALL
SELECT '[UNKNOWN]', '[UNKNOWN]', NULL, '[UNKNOWN]', -1
FROM dual
WHERE NOT EXISTS (
  SELECT 1 FROM MONCITY.CAR WHERE UPPER(TRIM(registrationno)) = '[UNKNOWN]'
);

CREATE TABLE MC_STG_MAINT_TYPE AS
SELECT UPPER(TRIM(maintenancetype)) AS maintenancetype,
       TRIM(maintenancedescription) AS maintenancedescription
FROM MONCITY.MAINTENANCETYPE;

CREATE TABLE MC_STG_MAINT_TEAM AS
SELECT UPPER(TRIM(teamid)) AS teamid,
       TRIM(teamleader) AS teamleader,
       phone
FROM MONCITY.MAINTENANCETEAM;

CREATE TABLE MC_STG_RESEARCH_CENTER AS
SELECT UPPER(TRIM(centerid)) AS centerid,
       TRIM(centername) AS centername,
       phone,
       TRIM(openinghour) AS openinghour
FROM MONCITY.RESEARCHCENTER;

CREATE TABLE MC_STG_BELONGTO AS
SELECT DISTINCT UPPER(TRIM(teamid)) AS teamid,
                UPPER(TRIM(centerid)) AS centerid
FROM MONCITY.BELONGTO;

/* Error type 1: remove only identical normalized payloads.
   Conflicting payloads with the same bookingid remain visible and the staging
   primary key below rejects them; never choose one arbitrarily. */
CREATE TABLE MC_STG_BOOKING AS
SELECT bookingid, registrationno, bookingdate,
       departurezone, destinationzone, passengerid
FROM (
  SELECT UPPER(TRIM(bookingid)) AS bookingid,
         UPPER(TRIM(registrationno)) AS registrationno,
         bookingdate,
         UPPER(TRIM(departurezone)) AS departurezone,
         UPPER(TRIM(destinationzone)) AS destinationzone,
         UPPER(TRIM(passengerid)) AS passengerid,
         ROW_NUMBER() OVER (
           PARTITION BY UPPER(TRIM(bookingid)), UPPER(TRIM(registrationno)),
                        bookingdate, UPPER(TRIM(departurezone)),
                        UPPER(TRIM(destinationzone)), UPPER(TRIM(passengerid))
           ORDER BY ROWID
         ) AS rn
  FROM MONCITY.BOOKING
)
WHERE rn = 1;

/* Error type 4: apply the documented M2000/-200 sign-repair assumption only.
   Other negative or missing costs are rejected by the staging check below. */
CREATE TABLE MC_STG_MAINTENANCE AS
SELECT UPPER(TRIM(maintenanceid)) AS maintenanceid,
       UPPER(TRIM(registrationno)) AS registrationno,
       maintenancedate,
       UPPER(TRIM(maintenancetype)) AS maintenancetype,
       CASE WHEN UPPER(TRIM(maintenanceid)) = 'M2000'
                 AND maintenancecost = -200 THEN 200
            ELSE maintenancecost END AS maintenancecost,
       UPPER(TRIM(teamid)) AS teamid
FROM MONCITY.MAINTENANCE;

/* Error type 2: generate a traceable key only where the source key is NULL. */
CREATE TABLE MC_STG_ACCIDENTINFO AS
SELECT CASE
         WHEN accidentid IS NULL THEN
           'A2_REPAIRED_' || TO_CHAR(repair_seq, 'FM0000')
         ELSE UPPER(TRIM(accidentid))
       END AS accidentid,
       UPPER(TRIM(accidentzone)) AS accidentzone,
       UPPER(TRIM(car_damage_severity)) AS car_damage_severity,
       UPPER(TRIM(errorcode)) AS errorcode,
       CASE WHEN accidentid IS NULL THEN 'Y' ELSE 'N' END AS repaired_id_flag
FROM (
  SELECT a.*,
         ROW_NUMBER() OVER (
           ORDER BY UPPER(TRIM(accidentzone)),
                    UPPER(TRIM(car_damage_severity)),
                    UPPER(TRIM(errorcode)), ROWID
         ) AS repair_seq
  FROM MONCITY.ACCIDENTINFO a
);

/* Error type 5: retain unmapped source codes as explicit unknown descriptions. */
CREATE TABLE MC_STG_ERROR AS
SELECT errorcode, MAX(errormessage) AS errormessage
FROM (
  SELECT UPPER(TRIM(errorcode)) AS errorcode,
         TRIM(errormessage) AS errormessage
  FROM MONCITY.ERROR
  UNION ALL
  SELECT DISTINCT a.errorcode,
         '[UNMAPPED SOURCE ERROR]' AS errormessage
  FROM MC_STG_ACCIDENTINFO a
  WHERE a.errorcode IS NOT NULL
    AND NOT EXISTS (
      SELECT 1 FROM MONCITY.ERROR e
      WHERE UPPER(TRIM(e.errorcode)) = a.errorcode
    )
)
GROUP BY errorcode;

/*
  Error type 3: keep all valid source pairs and add [UNKNOWN] membership only
  for cleaned accidents that otherwise have no car. The generated repaired ID
  is matched by content for the known NULL-ID source row.
*/
CREATE TABLE MC_STG_CARACCIDENT AS
WITH source_pairs AS (
  SELECT DISTINCT UPPER(TRIM(registrationno)) AS registrationno,
                  UPPER(TRIM(accidentid)) AS accidentid
  FROM MONCITY.CARACCIDENT
  WHERE accidentid IS NOT NULL
), staged_pairs AS (
  SELECT registrationno, accidentid FROM source_pairs
  UNION ALL
  SELECT '[UNKNOWN]' AS registrationno, a.accidentid
  FROM MC_STG_ACCIDENTINFO a
  WHERE NOT EXISTS (
    SELECT 1 FROM source_pairs p WHERE p.accidentid = a.accidentid
  )
)
SELECT DISTINCT registrationno, accidentid
FROM staged_pairs;

/* Keys on the cleaned layer make the repaired rules executable and visible. */
ALTER TABLE MC_STG_FACULTY ADD CONSTRAINT MC_SF_PK PRIMARY KEY (facultyid);
ALTER TABLE MC_STG_PASSENGER ADD CONSTRAINT MC_SP_PK PRIMARY KEY (passengerid);
ALTER TABLE MC_STG_CAR ADD CONSTRAINT MC_SC_PK PRIMARY KEY (registrationno);
ALTER TABLE MC_STG_MAINT_TYPE ADD CONSTRAINT MC_SMT_PK PRIMARY KEY (maintenancetype);
ALTER TABLE MC_STG_MAINT_TEAM ADD CONSTRAINT MC_STEAM_PK PRIMARY KEY (teamid);
ALTER TABLE MC_STG_RESEARCH_CENTER ADD CONSTRAINT MC_SRC_PK PRIMARY KEY (centerid);
ALTER TABLE MC_STG_BOOKING ADD CONSTRAINT MC_SB_PK PRIMARY KEY (bookingid);
ALTER TABLE MC_STG_MAINTENANCE ADD CONSTRAINT MC_SM_PK PRIMARY KEY (maintenanceid);
ALTER TABLE MC_STG_MAINTENANCE ADD CONSTRAINT MC_SM_COST_CK
  CHECK (maintenancecost IS NOT NULL AND maintenancecost >= 0) ENABLE VALIDATE;
ALTER TABLE MC_STG_ACCIDENTINFO ADD CONSTRAINT MC_SA_PK PRIMARY KEY (accidentid);
ALTER TABLE MC_STG_ERROR ADD CONSTRAINT MC_SE_PK PRIMARY KEY (errorcode);
ALTER TABLE MC_STG_BELONGTO ADD CONSTRAINT MC_SBT_PK PRIMARY KEY (teamid, centerid);
ALTER TABLE MC_STG_CARACCIDENT ADD CONSTRAINT MC_SCA_PK PRIMARY KEY (registrationno, accidentid);

COMMIT;

/* Compact after-cleaning evidence. Every UNRESOLVED value must be zero. */
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
