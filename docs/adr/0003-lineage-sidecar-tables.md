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

What the data offers:

- Every ODS resource has a stable `id`, the same one the Ed-Fi API exposes, and
  a natural key. For example, a student's absence is a
  `studentSectionAttendanceEvent` with its own `id`, date and section.
- The data mart's facts are aggregates: a row of `ews_studentearlywarningfact` is
  one student, school and day, built from several attendance events. The facts
  don't carry ODS `id`s.
- The ODS doesn't record which source system or record a resource came from;
  that has to be supplied.

This ADR records the design (DEVOPS-186). Reporting lineage through the tools is
the next phase (DEVOPS-187).

## Decision

### Lineage lives in its own schema

The tables live in a `lineage` schema in the data mart database. The data mart
build replaces only the `analytics` schema, so lineage records survive a
refresh. The MCP server's role can read them.

### Three tables

```sql
-- Systems that send data to the ODS (for the demo, a fictional SIS)
CREATE TABLE lineage.source_system (
    source_system_id   text PRIMARY KEY,         -- e.g. 'northridge-sis'
    name               text NOT NULL,            -- e.g. 'Northridge SIS (sample)'
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
    source_system_id   text REFERENCES lineage.source_system,
    source_record_id   text,                     -- the record's id in the source system
    recorded_at        timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (ods_resource, ods_id)
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

### Populated by hand, for a demonstration set

A script fills the tables for a few students who appear in the demonstration
(for example the teacher's top at-risk students), from the ODS:

- `ods_record` and `indicator_evidence` from the ODS rows behind each indicator:
  the absences up to today, the grades below passing in the latest grading
  period, the failing assessment results, the discipline actions;
- `source_system` with one fictional SIS, and `source_record_id` with fictional
  SIS identifiers, clearly marked as sample values.

"By hand" means a reviewed script for a chosen set of students, not an automated
pipeline: it shows the shape and the value of lineage without claiming a
complete capture. A real deployment would record lineage when data is loaded.

### What the tools will report (DEVOPS-187)

- Results that flag or describe a student say whether evidence is available.
- A new tool, for example `get_indicator_evidence(student, indicator)`, returns
  the evidence for one student and indicator: for each record, the date, a
  summary, the ODS resource and `id`, and the source system and record when
  known. It is limited to students in the user's scope, like every other tool.

## Options considered

### Link fact rows, or link indicators

Linking each fact row (student, school, day) to its ODS records mirrors the
data mart, but the tools don't show fact rows, and an attendance indicator would
need hundreds of rows to explain. Chosen: link by student and indicator.

### Store natural keys only, or ODS `id`s

Natural keys are readable but change when a key changes; the ODS `id` is stable
and is what the Ed-Fi API uses to fetch a record. Chosen: both, with the `id` as
the key and the natural key for people to read.

### Populate everything automatically now, or a demonstration set by hand

Generating evidence for every student is possible for the ODS part, but the
source system part has to be supplied, and the brief calls for manual
population first. Chosen: a demonstration set by hand; automatic population is
a later improvement.

## Consequences

- Lineage survives data mart refreshes, but can go stale if the ODS records
  behind it change; the demonstration script can be rerun.
- Students outside the demonstration set have no evidence yet; tools say so
  rather than inventing it.
- Source system identifiers in the demonstration are fictional; the
  documentation says so.

## Open questions

- Should the demonstration cover all four indicators, or start with attendance?
- Is a fictional SIS with made-up record identifiers acceptable for the
  demonstration, or should the source system part wait for real data?
- Should the shape follow any draft of the Ed-Fi API 8 lineage work?
