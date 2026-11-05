-- SPDX-License-Identifier: Apache-2.0
-- Licensed to the Ed-Fi Alliance under one or more agreements.
-- The Ed-Fi Alliance licenses this file to you under the Apache License, Version 2.0.
-- See the LICENSE and NOTICES files in the project root for more information.

-- Students the user may see who meet at least one early warning indicator:
--   attendance: absent from any class on at least $3 percent of instructional days so far;
--   course performance: a numeric grade below $4 in the latest grading period that has started;
--   assessments: a Fail or Well Below Basic result up to today.
-- $1: user key, $2: section key (optional), $3: absence threshold (percent), $4: passing grade,
-- $5: row limit.

WITH students AS (
    SELECT a.studentkey
    FROM analytics.rls_userstudentdataauthorization a
    WHERE a.userkey = $1
      AND ($2::text IS NULL OR EXISTS (
              SELECT 1 FROM analytics.studentsectiondim x
              WHERE x.studentkey = a.studentkey AND x.sectionkey = $2))
),
attendance AS (
    SELECT f.studentkey,
           sum(f.isinstructionalday) AS days,
           sum(greatest(f.isabsentfromanyclassexcused, f.isabsentfromanyclassunexcused)) AS absent
    FROM analytics.ews_studentearlywarningfact f
    JOIN students USING (studentkey)
    GROUP BY f.studentkey
),
latest_period AS (
    SELECT DISTINCT ON (schoolkey) schoolkey, gradingperiodkey, gradingperioddescription
    FROM analytics.gradingperioddim
    WHERE gradingperiodbegindatekey <= to_char(current_date, 'YYYYMMDD')
    ORDER BY schoolkey, gradingperiodbegindatekey DESC
),
grades AS (
    SELECT g.studentkey,
           count(*) FILTER (WHERE g.numericgradeearned < $4) AS failing,
           min(p.gradingperioddescription) AS grading_period
    FROM analytics.ews_studentsectiongradefact g
    JOIN students USING (studentkey)
    JOIN latest_period p ON p.schoolkey = g.schoolkey AND p.gradingperiodkey = g.gradingperiodkey
    GROUP BY g.studentkey
),
assessments AS (
    SELECT r.studentkey,
           count(*) FILTER (WHERE r.performanceresult IN ('Fail', 'Well Below Basic')) AS low
    FROM analytics.asmt_studentassessmentfact r
    JOIN students USING (studentkey)
    WHERE r.administrationdate <= to_char(current_date, 'YYYYMMDD')
    GROUP BY r.studentkey
),
flags AS (
    SELECT s.studentkey,
           coalesce(a.days, 0)::int AS days,
           coalesce(a.absent, 0)::int AS absent,
           round(100.0 * a.absent / nullif(a.days, 0), 1)::float8 AS absence_rate,
           coalesce(g.failing, 0)::int AS failing_grades,
           g.grading_period,
           coalesce(r.low, 0)::int AS low_assessments
    FROM students s
    LEFT JOIN attendance a USING (studentkey)
    LEFT JOIN grades g USING (studentkey)
    LEFT JOIN assessments r USING (studentkey)
)
SELECT f.studentkey AS key,
       n.name,
       n.grade_level,
       f.days AS instructional_days,
       f.absent AS days_absent,
       f.absence_rate,
       f.failing_grades,
       f.grading_period,
       f.low_assessments,
       (CASE WHEN f.absence_rate >= $3 THEN 1 ELSE 0 END
        + CASE WHEN f.failing_grades > 0 THEN 1 ELSE 0 END
        + CASE WHEN f.low_assessments > 0 THEN 1 ELSE 0 END) AS indicators
FROM flags f
JOIN LATERAL (
    SELECT studentfirstname || ' ' || studentlastname AS name, gradelevel AS grade_level
    FROM analytics.studentschooldim
    WHERE studentkey = f.studentkey
    LIMIT 1
) n ON true
WHERE f.absence_rate >= $3 OR f.failing_grades > 0 OR f.low_assessments > 0
ORDER BY indicators DESC, f.absence_rate DESC NULLS LAST, n.name
LIMIT $5;
