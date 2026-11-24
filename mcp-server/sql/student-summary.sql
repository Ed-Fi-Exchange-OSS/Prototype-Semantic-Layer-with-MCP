-- SPDX-License-Identifier: Apache-2.0
-- Licensed to the Ed-Fi Alliance under one or more agreements.
-- The Ed-Fi Alliance licenses this file to you under the Apache License, Version 2.0.
-- See the LICENSE and NOTICES files in the project root for more information.

-- One student's attendance so far, grades in the latest grading period, assessment results and discipline
-- actions up to today, programs, and the indicators that have lineage records (docs/adr/0003). No row when
-- the user may not see the student.
-- $1: user key, $2: student key.

WITH latest_period AS (
    SELECT DISTINCT ON (schoolkey) schoolkey, gradingperiodkey, gradingperioddescription
    FROM analytics.gradingperioddim
    WHERE gradingperiodbegindatekey <= to_char(current_date, 'YYYYMMDD')
    ORDER BY schoolkey, gradingperiodbegindatekey DESC
)
SELECT json_build_object(
    'student', (
        SELECT json_build_object(
            'key', s.studentkey,
            'name', s.studentfirstname || ' ' || s.studentlastname,
            'grade_level', s.gradelevel,
            'school', sc.schoolname)
        FROM analytics.studentschooldim s
        JOIN analytics.schooldim sc ON sc.schoolkey = s.schoolkey
        WHERE s.studentkey = $2
        LIMIT 1),
    'attendance', (
        SELECT json_build_object(
            'instructional_days', sum(f.isinstructionalday),
            'days_absent', sum(greatest(f.isabsentfromanyclassexcused, f.isabsentfromanyclassunexcused)),
            'excused', sum(f.isabsentfromanyclassexcused),
            'unexcused', sum(f.isabsentfromanyclassunexcused),
            'tardy', sum(f.istardytoanyclass),
            'absence_rate', round(100.0 * sum(greatest(f.isabsentfromanyclassexcused,
                f.isabsentfromanyclassunexcused)) / nullif(sum(f.isinstructionalday), 0), 1))
        FROM analytics.ews_studentearlywarningfact f
        WHERE f.studentkey = $2),
    'grades', (
        SELECT json_agg(json_build_object(
                   'course', ss.coursetitle,
                   'grading_period', p.gradingperioddescription,
                   'numeric', g.numericgradeearned,
                   'letter', g.lettergradeearned)
               ORDER BY ss.coursetitle)
        FROM analytics.ews_studentsectiongradefact g
        JOIN latest_period p ON p.schoolkey = g.schoolkey AND p.gradingperiodkey = g.gradingperiodkey
        JOIN analytics.studentsectiondim ss ON ss.studentsectionkey = g.studentsectionkey
        WHERE g.studentkey = $2),
    'assessments', (
        SELECT json_agg(json_build_object(
                   'assessment', t.title,
                   'date', to_char(to_date(r.administrationdate, 'YYYYMMDD'), 'YYYY-MM-DD'),
                   'score', r.studentscore,
                   'performance', r.performanceresult)
               ORDER BY r.administrationdate DESC)
        FROM analytics.asmt_studentassessmentfact r
        LEFT JOIN LATERAL (
            SELECT title FROM analytics.asmt_assessmentfact a
            WHERE a.assessmentkey = r.assessmentkey
            LIMIT 1
        ) t ON true
        WHERE r.studentkey = $2
          AND r.administrationdate <= to_char(current_date, 'YYYYMMDD')),
    'discipline_actions', (
        SELECT json_agg(json_build_object('date', a.date, 'action', a.action) ORDER BY a.date DESC)
        FROM (
            SELECT DISTINCT to_char(to_date(d.disciplinedatekey, 'YYYYMMDD'), 'YYYY-MM-DD') AS date,
                   d.disciplineactiondescription AS action,
                   regexp_replace(d.studentdisciplineactionkey, '-[^-]*$', '') AS action_key
            FROM analytics.equity_studentdisciplineactiondim d
            WHERE d.studentkey = $2
              AND d.disciplinedatekey <= to_char(current_date, 'YYYYMMDD')
        ) a),
    'programs', (
        SELECT json_agg(DISTINCT p.programname)
        FROM analytics.studentprogramdim p
        WHERE p.studentkey = $2),
    'evidence', (
        SELECT coalesce(json_agg(DISTINCT e.indicator), '[]'::json)
        FROM lineage.indicator_evidence e
        WHERE e.student_key = $2)
) AS summary
WHERE EXISTS (
    SELECT 1 FROM analytics.rls_userstudentdataauthorization
    WHERE userkey = $1 AND studentkey = $2);
