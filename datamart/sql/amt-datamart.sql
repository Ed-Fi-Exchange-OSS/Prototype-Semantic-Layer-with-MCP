-- SPDX-License-Identifier: Apache-2.0
-- Licensed to the Ed-Fi Alliance under one or more agreements.
-- The Ed-Fi Alliance licenses this file to you under the Apache License, Version 2.0.
-- See the LICENSE and NOTICES files in the project root for more information.

-- Builds a PostgreSQL data mart from the Analytics Middle Tier (AMT) views of an Ed-Fi ODS, with the views
-- materialized into tables. Port of AMT-Unreleased-DS-5/samples/AMT-DataMart.sql (T-SQL).
--
-- Run with psql, connected to the data mart database, on the same server as the ODS:
--   psql -d edfi_datamart -v ods_db=EdFi_Ods_Northridge -v ods_user=postgres -v ods_password=...
--        -f amt-datamart.sql
-- Run it again to refresh the data.
--
-- Differences from the T-SQL script:
--   * reads the ODS through postgres_fdw (PostgreSQL can't query another database directly);
--   * copies every AMT view the ODS has (the collections installed there), instead of a fixed list;
--   * swaps the staging tables in and builds the indexes in one transaction, so readers never see a
--     half-built mart;
--   * the second-ODS section (commented out in the original) and the fake schema version log are left out:
--     the early warning views are copied as tables like the rest.

\set ON_ERROR_STOP on

-- Connection to the ODS
CREATE EXTENSION IF NOT EXISTS postgres_fdw;
DROP SERVER IF EXISTS ods CASCADE;
CREATE SERVER ods FOREIGN DATA WRAPPER postgres_fdw OPTIONS (host 'localhost', dbname :'ods_db');
CREATE USER MAPPING FOR CURRENT_USER SERVER ods OPTIONS (user :'ods_user', password :'ods_password');

DROP SCHEMA IF EXISTS ods_analytics CASCADE;
CREATE SCHEMA ods_analytics;
IMPORT FOREIGN SCHEMA analytics FROM SERVER ods INTO ods_analytics;
IMPORT FOREIGN SCHEMA edfi LIMIT TO (schoolyeartype) FROM SERVER ods INTO ods_analytics;

CREATE SCHEMA IF NOT EXISTS analytics;

-- Staging tables: one per AMT view, with the source school year
DO $$
DECLARE
    v record;
    school_year smallint := (SELECT schoolyear FROM ods_analytics.schoolyeartype WHERE currentschoolyear);
BEGIN
    FOR v IN SELECT foreign_table_name AS name FROM information_schema.foreign_tables
             WHERE foreign_table_schema = 'ods_analytics' AND foreign_table_name <> 'schoolyeartype'
             ORDER BY 1
    LOOP
        RAISE NOTICE 'Copying %', v.name;
        EXECUTE format('DROP TABLE IF EXISTS analytics.%I', 'stg_' || v.name);
        EXECUTE format('CREATE TABLE analytics.%I AS '
                       'SELECT *, %s::smallint AS schoolyearsource FROM ods_analytics.%I',
                       'stg_' || v.name, school_year, v.name);
    END LOOP;
END $$;

-- Swap the staging tables in and build the indexes (index list from the T-SQL script)
BEGIN;

DO $$
DECLARE
    t record;
    ix record;
BEGIN
    FOR t IN SELECT table_name AS name FROM information_schema.tables
             WHERE table_schema = 'analytics' AND table_type = 'BASE TABLE' AND table_name LIKE 'stg\_%'
    LOOP
        EXECUTE format('DROP TABLE IF EXISTS analytics.%I', substr(t.name, 5));
        EXECUTE format('ALTER TABLE analytics.%I RENAME TO %I', t.name, substr(t.name, 5));
    END LOOP;

    FOR ix IN
        SELECT * FROM (VALUES
            ('academictimeperioddim', 'ucx_academictimeperioddim', true, 'academictimeperiodkey'),
            ('academictimeperioddim', 'ix_academictimeperioddim_gradingperiodkey', false, 'gradingperiodkey'),
            ('classperioddim', 'ucx_classperioddim', true, 'classperiodkey'),
            ('classperioddim', 'ix_classperioddim_sectionkey', false, 'sectionkey'),
            ('contactpersondim', 'ucx_contactpersondim', true, 'uniquekey'),
            ('contactpersondim', 'ix_contactpersondim_studentkey', false, 'studentkey'),
            ('datedim', 'ucx_datedim', true, 'datekey'),
            ('demographicdim', 'ucx_demographicdim', true, 'demographickey'),
            ('gradingperioddim', 'ucx_gradingperioddim', true, 'gradingperiodkey'),
            ('gradingperioddim', 'ix_gradingperioddim_schoolkey', false, 'schoolkey'),
            ('localeducationagencydim', 'ucx_localeducationagencydim', true, 'localeducationagencykey'),
            ('mostrecentgradingperiod', 'ucx_mostrecentgradingperiod', true, 'schoolkey'),
            ('schooldim', 'ucx_schooldim', true, 'schoolkey'),
            ('schooldim', 'ix_schooldim_localeducationagencykey', false, 'localeducationagencykey'),
            ('schooldim', 'ix_schooldim_stateeducationagencykey', false, 'stateeducationagencykey'),
            ('sectiondim', 'ucx_sectiondim', true, 'sectionkey'),
            ('sectiondim', 'ix_sectiondim_schoolkey', false, 'schoolkey'),
            ('staffsectiondim', 'ucx_staffsectiondim', true, 'staffsectionkey'),
            ('staffsectiondim', 'ix_staffsectiondim_schoolkey', false, 'schoolkey'),
            ('staffsectiondim', 'ix_staffsectiondim_sectionkey', false, 'sectionkey'),
            ('studentlocaleducationagencydemographicsbridge', 'ix_studentleademographicsbridge_bridgekey',
                false, 'studentschooldemographicbridgekey'),
            ('studentlocaleducationagencydim', 'ucx_studentlocaleducationagencydim',
                true, 'studentlocaleducationagencykey'),
            ('studentlocaleducationagencydim', 'ix_studentlocaleducationagencydim_studentkey',
                false, 'studentkey'),
            ('studentprogramdim', 'ucx_studentprogramdim', true, 'studentschoolprogramkey'),
            ('studentprogramdim', 'ix_studentprogramdim_studentkey', false, 'studentkey'),
            ('studentprogramdim', 'ix_studentprogramdim_schoolkey', false, 'schoolkey'),
            ('studentprogramdim', 'ix_studentprogramdim_studentschoolkey', false, 'studentschoolkey'),
            ('studentschooldemographicsbridge', 'ix_studentschooldemographicsbridge_bridgekey',
                false, 'studentschooldemographicbridgekey'),
            ('studentschooldim', 'ucx_studentschooldim', true, 'studentschoolkey'),
            ('studentschooldim', 'ix_studentschooldim_studentkey', false, 'studentkey'),
            ('studentschooldim', 'ix_studentschooldim_schoolkey', false, 'schoolkey'),
            ('studentsectiondim', 'ucx_studentsectiondim', true, 'studentsectionkey'),
            ('studentsectiondim', 'ix_studentsectiondim_schoolkey', false, 'schoolkey'),
            ('studentsectiondim', 'ix_studentsectiondim_studentkey', false, 'studentkey'),
            ('studentsectiondim', 'ix_studentsectiondim_sectionkey', false, 'sectionkey'),
            ('studentsectiondim', 'ix_studentsectiondim_studentsectionkey',
                false, 'studentkey, studentsectionkey, subject, schoolkey'),
            ('asmt_assessmentfact', 'ucx_asmt_assessmentfact', true, 'assessmentfactkey'),
            ('asmt_assessmentfact', 'ix_asmt_assessmentfact_assessmentkey', false, 'assessmentkey'),
            ('asmt_studentassessmentfact', 'ucx_asmt_studentassessmentfact',
                true, 'studentassessmentfactkey'),
            ('asmt_studentassessmentfact', 'ix_asmt_studentassessmentfact_studentassessmentkey',
                false, 'studentassessmentkey'),
            ('asmt_studentassessmentfact', 'ix_asmt_studentassessmentfact_assessmentkey',
                false, 'assessmentkey'),
            ('chrab_chronicabsenteeismattendancefact', 'ucx_chrab_chronicabsenteeismattendancefact',
                true, 'studentschoolkey, datekey'),
            ('chrab_chronicabsenteeismattendancefact', 'ix_chrab_chronicabsenteeismattendancefact_studentkey',
                false, 'studentkey'),
            ('chrab_chronicabsenteeismattendancefact', 'ix_chrab_chronicabsenteeismattendancefact_schoolkey',
                false, 'schoolkey'),
            ('rls_studentdataauthorization', 'ucx_rls_studentdataauthorization',
                true, 'studentkey, schoolkey, begindate, enddate, sectionid'),
            ('rls_userauthorization', 'ucx_rls_userauthorization',
                true, 'userkey, userscope, studentpermission, sectionpermission, schoolpermission'),
            ('rls_userdim', 'ucx_rls_userdim', true, 'userkey'),
            ('rls_userstudentdataauthorization', 'ucx_rls_userstudentdataauthorization',
                true, 'userkey, studentkey'),
            ('ews_studentearlywarningfact', 'ucx_ews_studentearlywarningfact',
                true, 'studentkey, schoolkey, datekey'),
            ('ews_studentearlywarningfact', 'ix_ews_studentearlywarningfact_schoolkey', false, 'schoolkey'),
            ('ews_studentearlywarningfact', 'ix_ews_studentearlywarningfact_datekey', false, 'datekey'),
            ('ews_studentsectiongradefact', 'ucx_ews_studentsectiongradefact',
                true, 'studentsectionkey, gradingperiodkey, gradetype'),
            ('ews_studentsectiongradefact', 'ix_ews_studentsectiongradefact_studentkey', false, 'studentkey'),
            ('ews_studentsectiongradefact', 'ix_ews_studentsectiongradefact_schoolkey', false, 'schoolkey'),
            ('ews_studentsectiongradefact', 'ix_ews_studentsectiongradefact_sectionkey', false, 'sectionkey'),
            ('ews_studentsectiongradefact', 'ix_ews_studentsectiongradefact_gradingperiodkey',
                false, 'gradingperiodkey'),
            ('equity_feederschooldim', 'ucx_equity_feederschooldim', true, 'feederschooluniquekey'),
            ('equity_feederschooldim', 'ix_equity_feederschooldim_schoolkey', false, 'schoolkey'),
            ('equity_feederschooldim', 'ix_equity_feederschooldim_feederschoolkey', false, 'feederschoolkey'),
            ('equity_studentdisciplineactiondim', 'ucx_equity_studentdisciplineactiondim',
                true, 'studentdisciplineactionkey'),
            ('equity_studentdisciplineactiondim', 'ix_equity_studentdisciplineactiondim_studentschoolkey',
                false, 'studentschoolkey'),
            ('equity_studentdisciplineactiondim', 'ix_equity_studentdisciplineactiondim_disciplinedatekey',
                false, 'disciplinedatekey'),
            ('equity_studentschoolfoodserviceprogramdim', 'ucx_equity_studentschoolfoodserviceprogramdim',
                true, 'studentschoolfoodserviceprogramkey'),
            ('equity_studentschoolfoodserviceprogramdim',
                'ix_equity_studentschoolfoodserviceprogramdim_programkey', false, 'studentschoolprogramkey'),
            ('equity_studentprogramcohortdim', 'ucx_equity_studentprogramcohortdim',
                true, 'studentprogramcohortkey'),
            ('equity_studentprogramcohortdim', 'ix_equity_studentprogramcohortdim_programkey',
                false, 'studentschoolprogramkey'),
            ('equity_studenthistorydim', 'ucx_equity_studenthistorydim', true, 'studentschoolkey')
        ) AS i(table_name, index_name, is_unique, columns)
        WHERE EXISTS (SELECT 1 FROM information_schema.tables x
                      WHERE x.table_schema = 'analytics' AND x.table_name = i.table_name)
    LOOP
        EXECUTE format('CREATE %s INDEX %I ON analytics.%I (%s)',
                       CASE WHEN ix.is_unique THEN 'UNIQUE' ELSE '' END,
                       ix.index_name, ix.table_name, ix.columns);
    END LOOP;
END $$;

COMMIT;

ANALYZE;
