-- SPDX-License-Identifier: Apache-2.0
-- Licensed to the Ed-Fi Alliance under one or more agreements.
-- The Ed-Fi Alliance licenses this file to you under the Apache License, Version 2.0.
-- See the LICENSE and NOTICES files in the project root for more information.

-- What the user may see. $1: user key.

SELECT
    (SELECT useremail FROM analytics.rls_userdim WHERE userkey = $1) AS email,
    (SELECT json_agg(DISTINCT jsonb_build_object(
                'scope', replace(ua.userscope, 'AuthorizationScope.', ''),
                'school', sc.schoolname))
     FROM analytics.rls_userauthorization ua
     LEFT JOIN analytics.schooldim sc ON sc.schoolkey = ua.schoolpermission
     WHERE ua.userkey = $1) AS scopes,
    (SELECT count(DISTINCT sectionkey)::int FROM analytics.staffsectiondim WHERE userkey = $1) AS sections,
    (SELECT count(*)::int FROM analytics.rls_userstudentdataauthorization WHERE userkey = $1) AS students;
