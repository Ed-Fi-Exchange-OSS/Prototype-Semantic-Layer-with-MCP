-- SPDX-License-Identifier: Apache-2.0
-- Licensed to the Ed-Fi Alliance under one or more agreements.
-- The Ed-Fi Alliance licenses this file to you under the Apache License, Version 2.0.
-- See the LICENSE and NOTICES files in the project root for more information.

-- Lineage for a demonstration set of students (docs/adr/0003-lineage-sidecar-tables.md), filled by hand from
-- the ODS. Run on the data mart database after sql/datamart.sql and sql/lineage.sql; it reads the ODS through
-- the `ods` foreign server that sql/datamart.sql creates. Running it again replaces the demonstration rows.
--
-- The evidence for each indicator is what the early warning tools count, up to today:
--   attendance: excused and unexcused absences from class;
--   course_performance: grades below 70 in the latest grading period that has started;
--   assessments: Fail and Well Below Basic results;
--   behavior: discipline actions.
-- The source system and its record identifiers are FICTIONAL sample values: Northridge doesn't say where its
-- records came from.

\set ON_ERROR_STOP on
SET client_min_messages = warning;

BEGIN;

DROP SCHEMA IF EXISTS lineage_ods CASCADE;
CREATE SCHEMA lineage_ods;
IMPORT FOREIGN SCHEMA edfi LIMIT TO (student, descriptor, studentsectionattendanceevent, grade, gradingperiod,
    studentassessment, studentassessmentperformancelevel, disciplineaction, disciplineactiondiscipline)
    FROM SERVER ods INTO lineage_ods;

INSERT INTO lineage.source_system (source_system_id, name, description)
VALUES ('northridge-sis-sample', 'Northridge SIS (fictional sample)',
        'Stands in for the student information system behind the Northridge sample data. Its record '
        || 'identifiers are made up for the demonstration.')
ON CONFLICT (source_system_id) DO UPDATE SET name = EXCLUDED.name, description = EXCLUDED.description;

-- The demonstration set: a Ridgemont High teacher's students with the most early warning indicators
CREATE TEMP TABLE demo_student (student_key text PRIMARY KEY) ON COMMIT DROP;
INSERT INTO demo_student VALUES ('004688'), ('004761'), ('004488'), ('004104'), ('004067'), ('004544');

DELETE FROM lineage.indicator_evidence WHERE student_key IN (SELECT student_key FROM demo_student);
DELETE FROM lineage.ods_record r
WHERE r.student_key IN (SELECT student_key FROM demo_student)
  AND NOT EXISTS (SELECT 1 FROM lineage.indicator_evidence e
                  WHERE e.ods_resource = r.ods_resource AND e.ods_id = r.ods_id);

CREATE TEMP TABLE evidence (
    indicator text, ods_resource text, ods_id uuid, natural_key jsonb, student_key text, event_date date,
    summary text, sample_prefix text
) ON COMMIT DROP;

-- Attendance: absences from class
INSERT INTO evidence
SELECT 'attendance', 'studentSectionAttendanceEvents', e.id,
       jsonb_build_object('studentUniqueId', s.studentuniqueid, 'schoolId', e.schoolid,
           'schoolYear', e.schoolyear, 'sessionName', e.sessionname, 'localCourseCode', e.localcoursecode,
           'sectionIdentifier', e.sectionidentifier, 'eventDate', e.eventdate,
           'attendanceEventCategory', d.codevalue),
       s.studentuniqueid, e.eventdate, d.codevalue || ', ' || e.localcoursecode, 'ATT'
FROM lineage_ods.studentsectionattendanceevent e
JOIN lineage_ods.student s ON s.studentusi = e.studentusi
JOIN lineage_ods.descriptor d ON d.descriptorid = e.attendanceeventcategorydescriptorid
WHERE s.studentuniqueid IN (SELECT student_key FROM demo_student)
  AND d.codevalue IN ('Excused Absence', 'Unexcused Absence')
  AND e.eventdate <= current_date;

-- Course performance: grades below 70 in the latest grading period that has started, for each school
INSERT INTO evidence
SELECT 'course_performance', 'grades', g.id,
       jsonb_build_object('studentUniqueId', s.studentuniqueid, 'schoolId', g.schoolid,
           'schoolYear', g.schoolyear, 'sessionName', g.sessionname, 'localCourseCode', g.localcoursecode,
           'sectionIdentifier', g.sectionidentifier, 'gradingPeriodName', g.gradingperiodname,
           'gradingPeriod', gp.codevalue, 'gradeType', gt.codevalue),
       s.studentuniqueid, latest.begindate,
       format('Grade %s (%s), %s, %s', g.numericgradeearned::int, g.lettergradeearned, g.localcoursecode,
              gp.codevalue),
       'GRD'
FROM lineage_ods.grade g
JOIN lineage_ods.student s ON s.studentusi = g.studentusi
JOIN lineage_ods.descriptor gt ON gt.descriptorid = g.gradetypedescriptorid
JOIN lineage_ods.descriptor gp ON gp.descriptorid = g.gradingperioddescriptorid
JOIN (SELECT DISTINCT ON (schoolid)
             schoolid, schoolyear, gradingperiodname, gradingperioddescriptorid, begindate
      FROM lineage_ods.gradingperiod
      WHERE begindate <= current_date
      ORDER BY schoolid, begindate DESC) latest
  ON latest.schoolid = g.schoolid AND latest.schoolyear = g.gradingperiodschoolyear
 AND latest.gradingperiodname = g.gradingperiodname
 AND latest.gradingperioddescriptorid = g.gradingperioddescriptorid
WHERE s.studentuniqueid IN (SELECT student_key FROM demo_student)
  AND g.numericgradeearned < 70;

-- Assessments: Fail and Well Below Basic results up to today
INSERT INTO evidence
SELECT 'assessments', 'studentAssessments', a.id,
       jsonb_build_object('studentUniqueId', s.studentuniqueid,
           'assessmentIdentifier', a.assessmentidentifier,
           'namespace', a.namespace, 'studentAssessmentIdentifier', a.studentassessmentidentifier),
       s.studentuniqueid, a.administrationdate::date, a.assessmentidentifier || ': ' || d.codevalue, 'ASM'
FROM lineage_ods.studentassessment a
JOIN lineage_ods.student s ON s.studentusi = a.studentusi
JOIN lineage_ods.studentassessmentperformancelevel p
  ON p.studentusi = a.studentusi AND p.assessmentidentifier = a.assessmentidentifier
 AND p.namespace = a.namespace AND p.studentassessmentidentifier = a.studentassessmentidentifier
JOIN lineage_ods.descriptor d ON d.descriptorid = p.performanceleveldescriptorid
WHERE s.studentuniqueid IN (SELECT student_key FROM demo_student)
  AND d.codevalue IN ('Fail', 'Well Below Basic')
  AND a.administrationdate::date <= current_date;

-- Behavior: discipline actions up to today
INSERT INTO evidence
SELECT DISTINCT ON (a.id) 'behavior', 'disciplineActions', a.id,
       jsonb_build_object('studentUniqueId', s.studentuniqueid,
           'disciplineActionIdentifier', a.disciplineactionidentifier, 'disciplineDate', a.disciplinedate),
       s.studentuniqueid, a.disciplinedate, d.codevalue, 'DIS'
FROM lineage_ods.disciplineaction a
JOIN lineage_ods.student s ON s.studentusi = a.studentusi
JOIN lineage_ods.disciplineactiondiscipline dd
  ON dd.disciplineactionidentifier = a.disciplineactionidentifier AND dd.disciplinedate = a.disciplinedate
 AND dd.studentusi = a.studentusi
JOIN lineage_ods.descriptor d ON d.descriptorid = dd.disciplinedescriptorid
WHERE s.studentuniqueid IN (SELECT student_key FROM demo_student)
  AND a.disciplinedate <= current_date
ORDER BY a.id, d.codevalue;

INSERT INTO lineage.ods_record (ods_resource, ods_id, natural_key, student_key, event_date, summary,
    source_system_id, source_record_id)
SELECT DISTINCT ON (ods_resource, ods_id) ods_resource, ods_id, natural_key, student_key, event_date, summary,
       'northridge-sis-sample', 'SAMPLE-' || sample_prefix || '-' || upper(left(md5(ods_id::text), 8))
FROM evidence
ON CONFLICT (ods_resource, ods_id) DO UPDATE
SET natural_key = EXCLUDED.natural_key, event_date = EXCLUDED.event_date, summary = EXCLUDED.summary,
    recorded_at = now();

INSERT INTO lineage.indicator_evidence (student_key, indicator, ods_resource, ods_id)
SELECT DISTINCT student_key, indicator, ods_resource, ods_id FROM evidence
ON CONFLICT DO NOTHING;

DROP SCHEMA lineage_ods CASCADE;

COMMIT;
