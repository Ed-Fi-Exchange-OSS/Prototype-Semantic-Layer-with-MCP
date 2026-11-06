-- SPDX-License-Identifier: Apache-2.0
-- Licensed to the Ed-Fi Alliance under one or more agreements.
-- The Ed-Fi Alliance licenses this file to you under the Apache License, Version 2.0.
-- See the LICENSE and NOTICES files in the project root for more information.

-- Lineage sidecar tables (docs/adr/0003-lineage-sidecar-tables.md). Run on the data mart database. They live
-- in their own schema, so rebuilding the data mart (schema analytics) leaves them in place. Running it again
-- changes nothing.

SET client_min_messages = warning;

CREATE SCHEMA IF NOT EXISTS lineage;

-- Earlier versions kept one source system per record; the history of changes replaces it
ALTER TABLE IF EXISTS lineage.ods_record DROP COLUMN IF EXISTS source_system_id,
    DROP COLUMN IF EXISTS source_record_id;
DROP TABLE IF EXISTS lineage.source_system;

-- Applications that write to the ODS: the API client's application name
CREATE TABLE IF NOT EXISTS lineage.application (
    application_id     text PRIMARY KEY,
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
    recorded_at        timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (ods_resource, ods_id)
);

-- Every modification of an ODS record: which application, and when (option 2 of the Ed-Fi lineage proposal)
CREATE TABLE IF NOT EXISTS lineage.ods_record_change (
    ods_resource       text NOT NULL,
    ods_id             uuid NOT NULL,
    application_id     text NOT NULL REFERENCES lineage.application,
    modified_at        timestamptz NOT NULL,
    PRIMARY KEY (ods_resource, ods_id, modified_at, application_id),
    FOREIGN KEY (ods_resource, ods_id) REFERENCES lineage.ods_record ON DELETE CASCADE
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
