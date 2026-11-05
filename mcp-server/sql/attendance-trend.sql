-- SPDX-License-Identifier: Apache-2.0
-- Licensed to the Ed-Fi Alliance under one or more agreements.
-- The Ed-Fi Alliance licenses this file to you under the Apache License, Version 2.0.
-- See the LICENSE and NOTICES files in the project root for more information.

-- Absences per week over the last $4 weeks (counting this one, from Monday), for one student or for the
-- students of a section that the user may see.
-- $1: user key, $2: student key, $3: section key (one of the two), $4: weeks.

WITH students AS (
    SELECT a.studentkey
    FROM analytics.rls_userstudentdataauthorization a
    WHERE a.userkey = $1
      AND ($2::text IS NULL OR a.studentkey = $2)
      AND ($3::text IS NULL OR EXISTS (
              SELECT 1 FROM analytics.studentsectiondim x
              WHERE x.studentkey = a.studentkey AND x.sectionkey = $3))
)
SELECT to_char(date_trunc('week', d.date), 'YYYY-MM-DD') AS week_of,
       count(DISTINCT f.studentkey)::int AS students,
       sum(f.isinstructionalday)::int AS instructional_days,
       sum(greatest(f.isabsentfromanyclassexcused, f.isabsentfromanyclassunexcused))::int AS absences,
       round(100.0 * sum(greatest(f.isabsentfromanyclassexcused, f.isabsentfromanyclassunexcused))
             / nullif(sum(f.isinstructionalday), 0), 1)::float8 AS absence_rate
FROM analytics.ews_studentearlywarningfact f
JOIN students USING (studentkey)
JOIN analytics.datedim d ON d.datekey = f.datekey
WHERE d.date >= date_trunc('week', current_date) - make_interval(weeks => $4::int - 1)
GROUP BY 1
ORDER BY 1;
