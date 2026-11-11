# ADR 0003: Lineage sidecar tables for the early warning data mart

- **Status:** Proposed
- **Date:** 2026-11-06
- **Requirements:** [PRD](../PRD.md), FR-LINEAGE-1 to FR-LINEAGE-3
- **Builds on:** [ADR 0001](0001-mcp-server-architecture.md),
  [ADR 0002](0002-sign-in-with-keycloak.md)

## Context

When the AI application flags a student, the educator and the district need to
see what the flag rests on: which absences, which grade, which assessment
result, which discipline action, and where each one came from. The PRD asks for
lineage records that link the semantic layer's records to the source records in
the ODS and, where known, the source system (FR-LINEAGE-1), and for tools that
can report them (FR-LINEAGE-2). API-native lineage is planned for Ed-Fi API 8;
until then the proof of concept keeps lineage in "sidecar" tables next to the
data mart, populated by hand at first.

The Ed-Fi API lineage proposal,
[Tracking Lineage](https://github.com/Ed-Fi-Alliance-OSS/Ed-Fi-Technology-Roadmap/issues/20),
weighs three options. This design follows option 2, "Last Modified (History)":
each record reports the application and the time of every modification, as a
`_lineage` list:

```javascript
{
  "_lineage": [
    { "applicationName": "Example SIS", "timestamp": 1711761837 },
    { "applicationName": "Example HR System", "timestamp": 1723054999 }
  ]
}
```

What the data offers:

- Every ODS resource has a stable `id`, the same one the Ed-Fi API exposes, and
  a natural key. For example, a student's absence is a
  `studentSectionAttendanceEvent` with its own `id`, date and section.
- The data mart's facts are aggregates: a row of `ews_studentearlywarningfact` is
  one student, school and day, built from several attendance events. The facts
  don't carry ODS `id`s.
- The ODS doesn't record which application created or changed a resource; that
  has to be supplied. Northridge is sample data, so the applications are
  fictional, and will stay so: the proof of concept won't use real data.

This ADR records the design (DEVOPS-186). Reporting lineage through the tools is
the next phase (DEVOPS-187).

## Decision

### Lineage lives in its own schema

The tables live in a `lineage` schema in the data mart database. The data mart
build owns them. On a full build and on a refresh, after it rebuilds the
`analytics` tables (and, on a full build, after it moves the ODS dates to the
current school year), it creates the `lineage` tables if they don't exist and
reruns the population script. The
script replaces the demonstration rows, so their dates, natural keys and
summaries match the facts after every build. Rebuilding `analytics` doesn't
touch the `lineage` schema; if the data mart database itself is dropped, the
next build recreates the lineage with it.

The ODS `id`s stay the same from one build to the next only because they come
from the Northridge backup, which every full build restores. Moving the dates
changes dates, not `id`s.

### Read access

The MCP server's role, `mcp_reader`, gets `USAGE` on the `lineage` schema and
`SELECT` on its tables, in the same script that grants `analytics`. It gets no
write access: the build fills the tables as the database owner, and
`mcp_reader` sessions stay read-only. This amends ADR 0001, which limited
`mcp_reader` to the `analytics` schema.

### Four tables

```sql
-- Applications that write to the ODS: the API client's application name
-- (for the demo, fictional applications)
CREATE TABLE lineage.application (
    application_id     text PRIMARY KEY,         -- e.g. 'northridge-sis-sample'
    name               text NOT NULL,            -- e.g. 'Northridge SIS (fictional sample)'
    description        text
);

-- One row per ODS record that supports a fact: the evidence
CREATE TABLE lineage.ods_record (
    ods_resource       text NOT NULL,            -- e.g. 'studentSectionAttendanceEvents'
    ods_id             uuid NOT NULL,            -- the ODS/API resource id
    natural_key        jsonb NOT NULL,           -- the resource's identity, readable
    student_key        text NOT NULL,            -- studentUniqueId, for scope checks
    event_date         date,                     -- when it happened, if it has a date
    summary            text NOT NULL,            -- e.g. 'Unexcused Absence, World History'
    recorded_at        timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (ods_resource, ods_id)
);

-- Every modification of an ODS record: which application, and when (option 2)
CREATE TABLE lineage.ods_record_change (
    ods_resource       text NOT NULL,
    ods_id             uuid NOT NULL,
    application_id     text NOT NULL REFERENCES lineage.application,
    modified_at        timestamptz NOT NULL,
    PRIMARY KEY (ods_resource, ods_id, modified_at, application_id),
    FOREIGN KEY (ods_resource, ods_id) REFERENCES lineage.ods_record
);

-- Which ODS records support which indicator for a student
CREATE TABLE lineage.indicator_evidence (
    student_key        text NOT NULL,
    indicator          text NOT NULL,            -- 'attendance', 'course_performance',
                                                 -- 'assessments', 'behavior'
    ods_resource       text NOT NULL,
    ods_id             uuid NOT NULL,
    PRIMARY KEY (student_key, indicator, ods_resource, ods_id),
    FOREIGN KEY (ods_resource, ods_id) REFERENCES lineage.ods_record
);
```

The link is by indicator, not by fact row: the question an educator asks is
"why is this student flagged for attendance?", and the answer is a list of
absences, not a list of daily fact rows. The same ODS record can support more
than one indicator.

`ods_record_change` holds what option 2 would add to the API: when API 8
reports `_lineage`, a load can copy it here unchanged.

### Populated by hand, for a demonstration set

A script fills the tables for a few students who appear in the demonstration
(for example the teacher's top at-risk students), for all four indicators, from
the ODS:

- `ods_record` and `indicator_evidence` from the ODS rows behind each indicator:
  the absences up to today, the grades below passing in the latest grading
  period, the failing assessment results, the discipline actions;
- `application` with a few fictional applications, such as a SIS, a gradebook,
  an assessment vendor and an attendance app, clearly marked as samples;
- `ods_record_change` with a made-up history for each record: the application
  that created it, and for some records a later change by another application
  (for example an absence later marked excused by the attendance app).

"By hand" means a reviewed script for a chosen set of students, not an automated
pipeline: it shows the shape and the value of lineage without claiming a
complete capture. A real deployment would record lineage when data is loaded.

### What the tools will report (DEVOPS-187)

- Results that flag or describe a student say whether evidence is available.
- A new tool, for example `get_indicator_evidence(student, indicator)`, returns
  the evidence for one student and indicator: for each record, the date, a
  summary, the ODS resource and `id`, and its `_lineage` as in option 2. It is
  limited to students in the user's scope, like every other tool.

## Options considered

### Link fact rows, or link indicators

Linking each fact row (student, school, day) to its ODS records mirrors the
data mart, but the tools don't show fact rows, and an attendance indicator would
need hundreds of rows to explain. Chosen: link by student and indicator.

### Store natural keys only, or ODS `id`s

Natural keys are readable but change when a key changes; the ODS `id` is stable
and is what the Ed-Fi API uses to fetch a record. Chosen: both, with the `id` as
the key and the natural key for people to read.

### One source system per record, or a history of changes

A single source system and source record id per record is simpler, but it
doesn't match any of the Ed-Fi API lineage options, and it can't show a record
that more than one application touched. Option 1 of the proposal (last modified
by) has the same limit; option 3 (the fields modified) needs more than the ODS
can supply here. Chosen: option 2, the application and time of every change.

### Populate everything automatically now, or a demonstration set by hand

Generating evidence for every student is possible for the ODS part, but the
application history has to be supplied, and the brief calls for manual
population first. Chosen: a demonstration set by hand; automatic population is
a later improvement.

## Consequences

- The demonstration lineage is rebuilt with the data mart, so it matches the
  facts after every build. Between builds it can go stale if the ODS records
  behind it change.
- Students outside the demonstration set have no evidence yet; tools say so
  rather than inventing it.
- The applications and their changes in the demonstration are fictional; the
  documentation says so.
- The proposal also asks whether lineage should include the education
  organization behind a change, not just the application. That isn't in this
  design; it can be added to `ods_record_change` if the API work settles it.
