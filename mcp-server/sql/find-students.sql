-- SPDX-License-Identifier: Apache-2.0
-- Licensed to the Ed-Fi Alliance under one or more agreements.
-- The Ed-Fi Alliance licenses this file to you under the Apache License, Version 2.0.
-- See the LICENSE and NOTICES files in the project root for more information.

-- Students the user may see, filtered by name, section and grade level.
-- $1: user key, $2: part of the name, $3: section key, $4: grade level (each optional), $5: row limit.

SELECT key, name, grade_level, school
FROM (
    SELECT DISTINCT ON (s.studentkey)
           s.studentkey AS key,
           s.studentfirstname || ' ' || s.studentlastname AS name,
           s.gradelevel AS grade_level,
           sc.schoolname AS school
    FROM analytics.rls_userstudentdataauthorization a
    JOIN analytics.studentschooldim s ON s.studentkey = a.studentkey
    JOIN analytics.schooldim sc ON sc.schoolkey = s.schoolkey
    WHERE a.userkey = $1
      AND ($2::text IS NULL OR s.studentfirstname || ' ' || s.studentlastname ILIKE '%' || $2 || '%')
      AND ($3::text IS NULL OR EXISTS (
              SELECT 1 FROM analytics.studentsectiondim x
              WHERE x.studentkey = s.studentkey AND x.sectionkey = $3))
      AND ($4::text IS NULL OR s.gradelevel ILIKE $4)
    ORDER BY s.studentkey
) t
ORDER BY name, key
LIMIT $5;
