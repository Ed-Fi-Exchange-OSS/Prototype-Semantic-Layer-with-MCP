-- SPDX-License-Identifier: Apache-2.0
-- Licensed to the Ed-Fi Alliance under one or more agreements.
-- The Ed-Fi Alliance licenses this file to you under the Apache License, Version 2.0.
-- See the LICENSE and NOTICES files in the project root for more information.

-- The lineage records behind one early warning indicator for one student (docs/adr/0003): the ODS records
-- and, where known, their source system. Newest first. No row when the user may not see the student.
-- $1: user key, $2: student key, $3: indicator, $4: row limit.

SELECT json_build_object(
    'total', (
        SELECT count(*)::int FROM lineage.indicator_evidence e
        WHERE e.student_key = $2 AND e.indicator = $3),
    'records', coalesce((
        SELECT json_agg(r ORDER BY r.date DESC NULLS LAST, r.ods_id)
        FROM (
            SELECT to_char(o.event_date, 'YYYY-MM-DD') AS date,
                   o.summary,
                   o.ods_resource,
                   o.ods_id,
                   o.natural_key,
                   s.name AS source_system,
                   o.source_record_id
            FROM lineage.indicator_evidence e
            JOIN lineage.ods_record o ON o.ods_resource = e.ods_resource AND o.ods_id = e.ods_id
            LEFT JOIN lineage.source_system s ON s.source_system_id = o.source_system_id
            WHERE e.student_key = $2 AND e.indicator = $3
            ORDER BY o.event_date DESC NULLS LAST, o.ods_id
            LIMIT $4
        ) r), '[]'::json)
) AS evidence
WHERE EXISTS (
    SELECT 1 FROM analytics.rls_userstudentdataauthorization
    WHERE userkey = $1 AND studentkey = $2);
