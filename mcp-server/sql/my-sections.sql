-- SPDX-License-Identifier: Apache-2.0
-- Licensed to the Ed-Fi Alliance under one or more agreements.
-- The Ed-Fi Alliance licenses this file to you under the Apache License, Version 2.0.
-- See the LICENSE and NOTICES files in the project root for more information.

-- The sections the user teaches, with the number of students in each. $1: user key.

SELECT s.sectionkey AS key,
       s.coursetitle AS course,
       s.sessionname AS session,
       count(DISTINCT ss.studentkey)::int AS students
FROM analytics.staffsectiondim st
JOIN analytics.sectiondim s ON s.sectionkey = st.sectionkey
LEFT JOIN analytics.studentsectiondim ss ON ss.sectionkey = s.sectionkey
WHERE st.userkey = $1
GROUP BY s.sectionkey, s.coursetitle, s.sessionname
ORDER BY s.coursetitle, s.sessionname, s.sectionkey;
