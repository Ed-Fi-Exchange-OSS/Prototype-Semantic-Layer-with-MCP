-- SPDX-License-Identifier: Apache-2.0
-- Licensed to the Ed-Fi Alliance under one or more agreements.
-- The Ed-Fi Alliance licenses this file to you under the Apache License, Version 2.0.
-- See the LICENSE and NOTICES files in the project root for more information.

-- Lineage sidecar tables (docs/adr/0003-lineage-sidecar-tables.md). Run on the data mart database. They live
-- in their own schema, so rebuilding the data mart (schema analytics) leaves them in place. Running it again
-- changes nothing.

SET client_min_messages = warning;

CREATE SCHEMA IF NOT EXISTS lineage;

-- Systems that send data to the ODS
CREATE TABLE IF NOT EXISTS lineage.source_system (
    source_system_id   text PRIMARY KEY,
    name               text NOT NULL,
    description        text
);

-- ODS records that serve as evidence, by their ODS/API resource id
CREATE TABLE IF NOT EXISTS lineage.ods_record (
    ods_resource       text NOT NULL,
    ods_id             uuid NOT NULL,
    natural_key        jsonb NOT NULL,
    student_key        text NOT NULL,
    event_date         date,
    summary            text NOT NULL,
    source_system_id   text REFERENCES lineage.source_system,
    source_record_id   text,
    recorded_at        timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (ods_resource, ods_id)
);

-- Which ODS records support which early warning indicator for a student
CREATE TABLE IF NOT EXISTS lineage.indicator_evidence (
    student_key        text NOT NULL,
    indicator          text NOT NULL
        CHECK (indicator IN ('attendance', 'course_performance', 'assessments', 'behavior')),
    ods_resource       text NOT NULL,
    ods_id             uuid NOT NULL,
    PRIMARY KEY (student_key, indicator, ods_resource, ods_id),
    FOREIGN KEY (ods_resource, ods_id) REFERENCES lineage.ods_record
);

CREATE INDEX IF NOT EXISTS ix_ods_record_student ON lineage.ods_record (student_key);
