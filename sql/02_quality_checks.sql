/*
  data-quality issue counts
  Read-only: this script identifies candidate issues but does not alter MONCITY.
  Only non-zero results should be investigated and, if justified, included in the report.
*/

WITH issue_counts (issue_type, source_table, issue_detail, issue_count) AS (
    /* Duplicate business or relationship keys. */
    SELECT 'DUPLICATE_KEY', 'FACULTY', 'Repeated FACULTYID', COUNT(*)
    FROM (SELECT facultyid FROM MONCITY.FACULTY GROUP BY facultyid HAVING COUNT(*) > 1)
    UNION ALL
    SELECT 'DUPLICATE_KEY', 'RESEARCHCENTER', 'Repeated CENTERID', COUNT(*)
    FROM (SELECT centerid FROM MONCITY.RESEARCHCENTER GROUP BY centerid HAVING COUNT(*) > 1)
    UNION ALL
    SELECT 'DUPLICATE_KEY', 'PASSENGER', 'Repeated PASSENGERID', COUNT(*)
    FROM (SELECT passengerid FROM MONCITY.PASSENGER GROUP BY passengerid HAVING COUNT(*) > 1)
    UNION ALL
    SELECT 'DUPLICATE_KEY', 'ERROR', 'Repeated ERRORCODE', COUNT(*)
    FROM (SELECT errorcode FROM MONCITY.ERROR GROUP BY errorcode HAVING COUNT(*) > 1)
    UNION ALL
    SELECT 'DUPLICATE_KEY', 'MAINTENANCETYPE', 'Repeated MAINTENANCETYPE', COUNT(*)
    FROM (SELECT maintenancetype FROM MONCITY.MAINTENANCETYPE GROUP BY maintenancetype HAVING COUNT(*) > 1)
    UNION ALL
    SELECT 'DUPLICATE_KEY', 'BOOKING', 'Repeated BOOKINGID', COUNT(*)
    FROM (SELECT bookingid FROM MONCITY.BOOKING GROUP BY bookingid HAVING COUNT(*) > 1)
    UNION ALL
    SELECT 'DUPLICATE_KEY', 'CAR', 'Repeated REGISTRATIONNO', COUNT(*)
    FROM (SELECT registrationno FROM MONCITY.CAR GROUP BY registrationno HAVING COUNT(*) > 1)
    UNION ALL
    SELECT 'DUPLICATE_KEY', 'MAINTENANCE', 'Repeated MAINTENANCEID', COUNT(*)
    FROM (SELECT maintenanceid FROM MONCITY.MAINTENANCE GROUP BY maintenanceid HAVING COUNT(*) > 1)
    UNION ALL
    SELECT 'DUPLICATE_KEY', 'ACCIDENTINFO', 'Repeated ACCIDENTID', COUNT(*)
    FROM (SELECT accidentid FROM MONCITY.ACCIDENTINFO GROUP BY accidentid HAVING COUNT(*) > 1)
    UNION ALL
    SELECT 'DUPLICATE_KEY', 'CARACCIDENT', 'Repeated REGISTRATIONNO + ACCIDENTID pair', COUNT(*)
    FROM (
        SELECT registrationno, accidentid
        FROM MONCITY.CARACCIDENT
        GROUP BY registrationno, accidentid
        HAVING COUNT(*) > 1
    )
    UNION ALL
    SELECT 'DUPLICATE_KEY', 'BELONGTO', 'Repeated TEAMID + CENTERID pair', COUNT(*)
    FROM (
        SELECT teamid, centerid
        FROM MONCITY.BELONGTO
        GROUP BY teamid, centerid
        HAVING COUNT(*) > 1
    )

    /* Missing values that are required by the specified analyses. */
    UNION ALL
    SELECT 'MISSING_REQUIRED_VALUE', 'FACULTY', 'Missing ID, name, or zone', COUNT(*)
    FROM MONCITY.FACULTY
    WHERE facultyid IS NULL OR TRIM(facultyname) IS NULL OR TRIM(zone) IS NULL
    UNION ALL
    SELECT 'MISSING_REQUIRED_VALUE', 'PASSENGER', 'Missing ID, age, or faculty', COUNT(*)
    FROM MONCITY.PASSENGER
    WHERE passengerid IS NULL OR passengerage IS NULL OR facultyid IS NULL
    UNION ALL
    SELECT 'MISSING_REQUIRED_VALUE', 'CAR', 'Missing registration, body type, or seats', COUNT(*)
    FROM MONCITY.CAR
    WHERE registrationno IS NULL OR TRIM(carbodytype) IS NULL OR numseats IS NULL
    UNION ALL
    SELECT 'MISSING_REQUIRED_VALUE', 'BOOKING', 'Missing booking key/date/zones/car/passenger', COUNT(*)
    FROM MONCITY.BOOKING
    WHERE bookingid IS NULL OR bookingdate IS NULL OR registrationno IS NULL
       OR passengerid IS NULL OR TRIM(departurezone) IS NULL OR TRIM(destinationzone) IS NULL
    UNION ALL
    SELECT 'MISSING_REQUIRED_VALUE', 'MAINTENANCE', 'Missing key/date/type/cost/team/car', COUNT(*)
    FROM MONCITY.MAINTENANCE
    WHERE maintenanceid IS NULL OR maintenancedate IS NULL OR maintenancetype IS NULL
       OR maintenancecost IS NULL OR teamid IS NULL OR registrationno IS NULL
    UNION ALL
    SELECT 'MISSING_REQUIRED_VALUE', 'ACCIDENTINFO', 'Missing key/zone/severity/error', COUNT(*)
    FROM MONCITY.ACCIDENTINFO
    WHERE accidentid IS NULL OR TRIM(accidentzone) IS NULL
       OR TRIM(car_damage_severity) IS NULL OR errorcode IS NULL

    /* Broken relationships (orphan foreign keys). */
    UNION ALL
    SELECT 'ORPHAN_REFERENCE', 'PASSENGER', 'FACULTYID not found in FACULTY', COUNT(*)
    FROM MONCITY.PASSENGER p
    WHERE p.facultyid IS NOT NULL
      AND NOT EXISTS (SELECT 1 FROM MONCITY.FACULTY f WHERE f.facultyid = p.facultyid)
    UNION ALL
    SELECT 'ORPHAN_REFERENCE', 'BOOKING', 'PASSENGERID not found in PASSENGER', COUNT(*)
    FROM MONCITY.BOOKING b
    WHERE b.passengerid IS NOT NULL
      AND NOT EXISTS (SELECT 1 FROM MONCITY.PASSENGER p WHERE p.passengerid = b.passengerid)
    UNION ALL
    SELECT 'ORPHAN_REFERENCE', 'BOOKING', 'REGISTRATIONNO not found in CAR', COUNT(*)
    FROM MONCITY.BOOKING b
    WHERE b.registrationno IS NOT NULL
      AND NOT EXISTS (SELECT 1 FROM MONCITY.CAR c WHERE c.registrationno = b.registrationno)
    UNION ALL
    SELECT 'ORPHAN_REFERENCE', 'MAINTENANCE', 'REGISTRATIONNO not found in CAR', COUNT(*)
    FROM MONCITY.MAINTENANCE m
    WHERE m.registrationno IS NOT NULL
      AND NOT EXISTS (SELECT 1 FROM MONCITY.CAR c WHERE c.registrationno = m.registrationno)
    UNION ALL
    SELECT 'ORPHAN_REFERENCE', 'MAINTENANCE', 'MAINTENANCETYPE not found in type table', COUNT(*)
    FROM MONCITY.MAINTENANCE m
    WHERE m.maintenancetype IS NOT NULL
      AND NOT EXISTS (
          SELECT 1 FROM MONCITY.MAINTENANCETYPE t
          WHERE t.maintenancetype = m.maintenancetype
      )
    UNION ALL
    SELECT 'ORPHAN_REFERENCE', 'MAINTENANCE', 'TEAMID not found in MAINTENANCETEAM', COUNT(*)
    FROM MONCITY.MAINTENANCE m
    WHERE m.teamid IS NOT NULL
      AND NOT EXISTS (SELECT 1 FROM MONCITY.MAINTENANCETEAM t WHERE t.teamid = m.teamid)
    UNION ALL
    SELECT 'ORPHAN_REFERENCE', 'ACCIDENTINFO', 'ERRORCODE not found in ERROR', COUNT(*)
    FROM MONCITY.ACCIDENTINFO a
    WHERE a.errorcode IS NOT NULL
      AND NOT EXISTS (SELECT 1 FROM MONCITY.ERROR e WHERE e.errorcode = a.errorcode)
    UNION ALL
    SELECT 'ORPHAN_REFERENCE', 'CARACCIDENT', 'REGISTRATIONNO not found in CAR', COUNT(*)
    FROM MONCITY.CARACCIDENT ca
    WHERE ca.registrationno IS NOT NULL
      AND NOT EXISTS (SELECT 1 FROM MONCITY.CAR c WHERE c.registrationno = ca.registrationno)
    UNION ALL
    SELECT 'ORPHAN_REFERENCE', 'CARACCIDENT', 'ACCIDENTID not found in ACCIDENTINFO', COUNT(*)
    FROM MONCITY.CARACCIDENT ca
    WHERE ca.accidentid IS NOT NULL
      AND NOT EXISTS (SELECT 1 FROM MONCITY.ACCIDENTINFO a WHERE a.accidentid = ca.accidentid)
    UNION ALL
    SELECT 'ORPHAN_REFERENCE', 'BELONGTO', 'TEAMID not found in MAINTENANCETEAM', COUNT(*)
    FROM MONCITY.BELONGTO bt
    WHERE bt.teamid IS NOT NULL
      AND NOT EXISTS (SELECT 1 FROM MONCITY.MAINTENANCETEAM t WHERE t.teamid = bt.teamid)
    UNION ALL
    SELECT 'ORPHAN_REFERENCE', 'BELONGTO', 'CENTERID not found in RESEARCHCENTER', COUNT(*)
    FROM MONCITY.BELONGTO bt
    WHERE bt.centerid IS NOT NULL
      AND NOT EXISTS (SELECT 1 FROM MONCITY.RESEARCHCENTER c WHERE c.centerid = bt.centerid)

    /* Invalid values against explicit analysis business rules. */
    UNION ALL
    SELECT 'INVALID_DOMAIN', 'FACULTY', 'ZONE is not ZoneA, ZoneB, ZoneC, or ZoneD', COUNT(*)
    FROM MONCITY.FACULTY
    WHERE zone IS NOT NULL AND UPPER(TRIM(zone)) NOT IN ('ZONEA', 'ZONEB', 'ZONEC', 'ZONED')
    UNION ALL
    SELECT 'INVALID_DOMAIN', 'BOOKING', 'DEPARTUREZONE is outside ZoneA-ZoneD', COUNT(*)
    FROM MONCITY.BOOKING
    WHERE departurezone IS NOT NULL
      AND UPPER(TRIM(departurezone)) NOT IN ('ZONEA', 'ZONEB', 'ZONEC', 'ZONED')
    UNION ALL
    SELECT 'INVALID_DOMAIN', 'BOOKING', 'DESTINATIONZONE is outside ZoneA-ZoneD', COUNT(*)
    FROM MONCITY.BOOKING
    WHERE destinationzone IS NOT NULL
      AND UPPER(TRIM(destinationzone)) NOT IN ('ZONEA', 'ZONEB', 'ZONEC', 'ZONED')
    UNION ALL
    SELECT 'INVALID_DOMAIN', 'ACCIDENTINFO', 'ACCIDENTZONE is outside ZoneA-ZoneD', COUNT(*)
    FROM MONCITY.ACCIDENTINFO
    WHERE accidentzone IS NOT NULL
      AND UPPER(TRIM(accidentzone)) NOT IN ('ZONEA', 'ZONEB', 'ZONEC', 'ZONED')
    UNION ALL
    SELECT 'INVALID_RANGE', 'PASSENGER', 'Age cannot be assigned to the required adult groups', COUNT(*)
    FROM MONCITY.PASSENGER
    WHERE passengerage IS NULL OR passengerage < 18 OR passengerage > 120
    UNION ALL
    SELECT 'INVALID_RANGE', 'CAR', 'NUMSEATS is zero or negative', COUNT(*)
    FROM MONCITY.CAR
    WHERE numseats IS NOT NULL AND numseats <= 0
    UNION ALL
    SELECT 'INVALID_RANGE', 'CAR', 'MANUFACTURINGYEAR is impossible', COUNT(*)
    FROM MONCITY.CAR
    WHERE manufacturingyear IS NOT NULL
      AND (manufacturingyear < 1900 OR manufacturingyear > EXTRACT(YEAR FROM SYSDATE))
    UNION ALL
    SELECT 'INVALID_RANGE', 'MAINTENANCE', 'MAINTENANCECOST is negative', COUNT(*)
    FROM MONCITY.MAINTENANCE
    WHERE maintenancecost IS NOT NULL AND maintenancecost < 0

    /* Formatting inconsistencies that can split warehouse dimension members. */
    UNION ALL
    SELECT 'WHITESPACE_INCONSISTENCY', 'FACULTY', 'Leading/trailing space in faculty name or zone', COUNT(*)
    FROM MONCITY.FACULTY
    WHERE facultyname <> TRIM(facultyname) OR zone <> TRIM(zone)
    UNION ALL
    SELECT 'WHITESPACE_INCONSISTENCY', 'PASSENGER', 'Leading/trailing space in role or gender', COUNT(*)
    FROM MONCITY.PASSENGER
    WHERE passengerrole <> TRIM(passengerrole) OR passengergender <> TRIM(passengergender)
    UNION ALL
    SELECT 'WHITESPACE_INCONSISTENCY', 'CAR', 'Leading/trailing space in body type or model', COUNT(*)
    FROM MONCITY.CAR
    WHERE carbodytype <> TRIM(carbodytype) OR carmodel <> TRIM(carmodel)
    UNION ALL
    SELECT 'WHITESPACE_INCONSISTENCY', 'BOOKING', 'Leading/trailing space in a zone value', COUNT(*)
    FROM MONCITY.BOOKING
    WHERE departurezone <> TRIM(departurezone) OR destinationzone <> TRIM(destinationzone)
    UNION ALL
    SELECT 'WHITESPACE_INCONSISTENCY', 'ACCIDENTINFO', 'Leading/trailing space in zone or severity', COUNT(*)
    FROM MONCITY.ACCIDENTINFO
    WHERE accidentzone <> TRIM(accidentzone)
       OR car_damage_severity <> TRIM(car_damage_severity)

    /* Canonically equivalent values stored with inconsistent spelling/case/spacing. */
    UNION ALL
    SELECT 'CANONICAL_COLLISION', 'PASSENGER', 'Different ROLE strings normalise to one value', COUNT(*)
    FROM (
        SELECT UPPER(TRIM(passengerrole))
        FROM MONCITY.PASSENGER
        WHERE passengerrole IS NOT NULL
        GROUP BY UPPER(TRIM(passengerrole))
        HAVING COUNT(DISTINCT passengerrole) > 1
    )
    UNION ALL
    SELECT 'CANONICAL_COLLISION', 'CAR', 'Different BODYTYPE strings normalise to one value', COUNT(*)
    FROM (
        SELECT UPPER(TRIM(carbodytype))
        FROM MONCITY.CAR
        WHERE carbodytype IS NOT NULL
        GROUP BY UPPER(TRIM(carbodytype))
        HAVING COUNT(DISTINCT carbodytype) > 1
    )
    UNION ALL
    SELECT 'CANONICAL_COLLISION', 'ACCIDENTINFO', 'Different SEVERITY strings normalise to one value', COUNT(*)
    FROM (
        SELECT UPPER(TRIM(car_damage_severity))
        FROM MONCITY.ACCIDENTINFO
        WHERE car_damage_severity IS NOT NULL
        GROUP BY UPPER(TRIM(car_damage_severity))
        HAVING COUNT(DISTINCT car_damage_severity) > 1
    )
)
SELECT issue_type, source_table, issue_detail, issue_count
FROM issue_counts
WHERE issue_count > 0
ORDER BY issue_type, source_table, issue_detail;
