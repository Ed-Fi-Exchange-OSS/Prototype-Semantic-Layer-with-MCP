# MCP for Early Warning: product requirements

- **Status:** Draft
- **Owner:** Stephen Fuqua (Ed-Fi Alliance); written by Rafael Ceballos
  (Simpat Tech)
- **Repository:** Ed-Fi-Exchange-OSS/Prototype-Semantic-Layer-with-MCP
- **Jira:** epic DEVOPS-180 (Early Warning System MCP Server POC), tasks
  DEVOPS-181 to DEVOPS-187
- **Sources:** Project Brief "Semantic Layer and Model Context Protocol (MCP)
  for Ed-Fi" (Ed-Fi and AI SIG, Confluence); the DEVOPS-180 tasks; Stephen
  Fuqua's answers on Slack (2026-11-04 and 2026-11-05)
- **Architecture decisions:** [ADR 0001](adr/0001-mcp-server-architecture.md)

## 1. Product overview

MCP for Early Warning is a proof of concept of the pattern the Ed-Fi Alliance
recommends for AI applications that work with Ed-Fi data: Ed-Fi operational
data is reshaped into a small semantic layer around analytical concepts, access
is limited to what each user may see, and the AI application gets a few
curated, deterministic operations through the Model Context Protocol (MCP)
instead of open access to SQL or the Ed-Fi API.

The proof of concept uses the early warning use case: helping educators find
students at risk from attendance, course performance and assessment results,
and see why.

It is a demonstration, not a product the Alliance will run or support. Its
deliverables are working code, reference patterns and documentation that the
community can adapt to build its own semantic layers and MCP servers.

### 1.1 Strategic alignment

- **Problems with AI on the Ed-Fi API today** (from the Project Brief):
  - the API can limit access to a school's data, but not to a teacher's
    sections or a counselor's caseload;
  - an AI system that enforces access through its prompt is open to prompt
    injection;
  - the API is "chatty" for AI interaction patterns: many round trips, many
    tokens;
  - there is no way to trace an AI recommendation back to the source data;
  - the OpenAPI specification is too large to load into an AI system's context.
- **Release objective:** a working proof of concept by the November 2026 Ed-Fi
  Summit, with API-native lineage targeted for 2027.
- **Related initiatives:** 1EdTech Trusted Portable Learning Context (TPLC), on
  consent, provenance and audit trails for AI access; data lineage as a
  priority for Ed-Fi API 8 (2027).
- **Principle:** educators remain the decision-makers. The AI application is a
  recommendation surface, not a decision-making authority.

### 1.2 Target users and personas

- **Teacher:** wants to know which students in their sections need attention
  and why, without exporting data or learning a reporting tool. Sees only the
  students in their sections. First persona delivered.
- **Principal:** wants a school-wide view of students at risk and of
  attendance trends. Sees the students of their school.
- **Counselor:** wants to follow the students on their caseload. Sees only that
  caseload.
- **Superintendent:** wants district-wide trends. Sees the district's students.
- **Student or family:** sees only their own records. Emerging; not planned for
  this proof of concept.
- **District data or IT staff:** set up the semantic layer, the users and the
  MCP server, and need to trust that access rules hold whatever the AI is
  asked.
- **AI application developer:** connects an AI assistant or application to the
  MCP server and relies on its tools being predictable and well described.

### 1.3 Jobs to be done

- When I plan my week, I want to see which of my students are at risk and
  which indicators flagged them, so that I can decide whom to reach out to
  first.
- When I'm worried about a student, I want a short summary of their
  attendance, grades and assessment results, so that I can talk to them or
  their family with facts.
- When attendance seems to be slipping in a class, I want to see the weekly
  trend, so that I can tell a bad week from a pattern.
- When the AI recommends an intervention, I want to see the source records
  behind it, so that I can check it and the district can audit it.
- When someone asks the AI about students I'm not responsible for, I want it
  to return nothing about them, whatever the prompt says.
- As district IT staff, when I give an educator access, I want their access
  to follow their role and assignments without configuring the AI.

## 2. System context

- **Ed-Fi ODS/API:** the source of operational data. The proof of concept uses
  the Northridge sample data (ODS/API 7.3, Data Standard 5.2, PostgreSQL),
  moved to the current school year.
- **Semantic layer:** a small data mart reshaped around early warning
  concepts (attendance, course grades, assessments), with the mappings from
  users to the students they may see. Refreshed from the ODS on demand.
- **MCP server:** the only way the AI application reaches the data. It offers
  a few curated tools and applies each user's access.
- **Identity:** Ed-Fi Admin App user management, for sign-in through OAuth
  (later phase). Until then, a configured demo user stands in for the
  signed-in educator.
- **AI application:** any MCP client, such as Claude Code, Claude Desktop or
  GitHub Copilot. Treated as an untrusted client.
- **Lineage records:** sidecar tables that link semantic layer records to their
  source records (later phase, populated by hand at first).

```text
AI application (MCP client)
        |  curated MCP tools
MCP server  <-- identity (demo user, then Admin App OAuth)
        |  fixed, read-only queries
Semantic layer (data mart, user-to-student access, lineage)
        |  refresh
Ed-Fi ODS (Northridge sample data)
```

## 3. Functional requirements

### Access scope

- **FR-SCOPE-1:** The system SHALL tell the signed-in user what they may see:
  their schools, their sections and how many students.
- **FR-SCOPE-2:** Every capability SHALL return data only about the students
  the signed-in user may see.
- **FR-SCOPE-3:** The user SHALL come from the session (the configured demo
  user, later the sign-in). No capability SHALL accept a user, role or scope
  from the AI application.
- **FR-SCOPE-4:** A request about a student outside the user's scope SHALL
  return no data about that student, and SHALL NOT reveal whether the student
  exists.
- **FR-SCOPE-5:** A session without a known user SHALL get an error and no
  data.

### Roster

- **FR-ROSTER-1:** The system SHALL list the sections the user teaches, with
  the course, the session and the number of students.
- **FR-ROSTER-2:** The system SHALL find students by part of their name, by
  section or by grade level.

### Students at risk

- **FR-RISK-1:** The system SHALL list the students at risk, with the
  indicators that flagged each one and the values behind them.
- **FR-RISK-2:** The attendance indicator SHALL flag a student absent on at
  least a given share of instructional days so far this school year
  (default 10%, chronic absenteeism).
- **FR-RISK-3:** The course performance indicator SHALL flag a student with a
  grade below a given passing grade (default 70) in the latest grading period
  that has started.
- **FR-RISK-4:** The assessment indicator SHALL flag a student with a failing
  or "well below basic" result this school year, up to today.
- **FR-RISK-5:** The system SHOULD add a behavior indicator from discipline
  incidents when the semantic layer has that data.
- **FR-RISK-6:** The list SHALL be sorted by the number of indicators, then by
  absence rate, and MAY be limited to one section.
- **FR-RISK-7:** The thresholds SHALL be parameters the user can change.

### Student summary and trends

- **FR-STUDENT-1:** The system SHALL summarize one student: attendance so far,
  grades in the latest grading period, assessment results up to today, and
  programs.
- **FR-TREND-1:** The system SHALL show absences per week over a given number
  of weeks, for one student or for a section.

### Authentication and authorization (later phases)

- **FR-AUTH-1:** The MCP server SHALL authenticate users with OAuth access
  tokens through Ed-Fi Admin App user management.
- **FR-AUTH-2:** Admin App users SHALL be linked to Ed-Fi staff records and
  their roles.
- **FR-AUTH-3:** Access SHALL follow the role: a teacher sees their sections'
  students; a principal, their school; a superintendent, their district; a
  counselor, their caseload.

### Lineage (later phases)

- **FR-LINEAGE-1:** The semantic layer SHALL keep lineage records that link
  its records to the source records in the ODS and, where known, the source
  system.
- **FR-LINEAGE-2:** Results that flag or describe a student SHALL be able to
  report the source records behind them.
- **FR-LINEAGE-3:** Every result SHALL state its as-of date and the semantic
  layer data it used.

### Semantic layer

- **FR-DATA-1:** The semantic layer SHALL be buildable from the Northridge
  sample data with one command, on Windows, macOS and Linux.
- **FR-DATA-2:** The sample data SHALL reflect the current school year, so the
  demonstration shows current enrollments and recent attendance.
- **FR-DATA-3:** The semantic layer SHALL be refreshable from the ODS without
  rebuilding the sample data.

## 4. Non-functional requirements

### Security and privacy

- **NFR-SEC-1:** The AI application SHALL be treated as an untrusted client.
  Access rules SHALL be enforced by the system, never by instructions to the
  AI.
- **NFR-SEC-2:** The system SHALL offer only fixed, narrow operations. It SHALL
  NOT run SQL, call the Ed-Fi API or reach other data on the AI application's
  behalf.
- **NFR-SEC-3:** The system SHALL only read data. Its access to the semantic
  layer SHALL be read-only, and it SHALL have no access to the ODS.
- **NFR-SEC-4:** Values that the AI application passes SHALL be validated
  (types, ranges, lengths) and treated as data, never as query text.
- **NFR-PRIV-1:** Results SHALL include only the fields needed to answer the
  question, and SHALL cap the number of rows.
- **NFR-PRIV-2:** Logs SHALL NOT contain student data.
- **NFR-PRIV-3:** The proof of concept SHALL use only fictional sample data.

### Performance and token use

- **NFR-PERF-1:** Each operation SHOULD answer in under one second for a user
  who may see up to about a thousand students.
- **NFR-PERF-2:** Results SHALL be compact, so an AI application can answer a
  question in a few calls without loading large data sets into its context.

### Compatibility

- **NFR-COMPAT-1:** The MCP server SHALL follow the MCP specification and
  support the Streamable HTTP transport, so that the common MCP clients can
  connect, and SHOULD support stdio for local use.
- **NFR-COMPAT-2:** Each operation SHALL describe itself well enough for an AI
  application to choose it without other documentation.

### Operations and SDLC

- **NFR-OPS-1:** The whole demonstration SHALL run locally with Docker and
  documented steps.
- **NFR-OPS-2:** Every capability SHALL have automated tests against the
  sample data, including tests that a user can't reach students outside their
  scope.
- **NFR-OPS-3:** The code SHALL follow the Ed-Fi license and contribution
  conventions (Apache 2.0, license headers).
- **NFR-OPS-4:** The documentation SHALL describe the patterns well enough for
  the community to apply them to their own data.

### Accessibility

- The proof of concept has no user interface of its own; accessibility depends
  on the AI application used with it.

## 5. System architecture

| Component | Responsibility | Runtime | Data ownership |
| --- | --- | --- | --- |
| Sample ODS | Operational data (Northridge), moved to the current school year | PostgreSQL in Docker | Source records |
| Semantic layer | Early warning dimensions and facts, user-to-student access, lineage | PostgreSQL in Docker, refreshed from the ODS | Derived data, access mappings, lineage records |
| MCP server | Curated tools, user resolution, access enforcement | Container next to the semantic layer, Streamable HTTP | None |
| Identity | User sign-in and roles (later phase) | Ed-Fi Admin App | Users, roles, links to staff |
| AI application | Asks questions on the user's behalf | Any MCP client | None |

The implementation decisions are recorded in
[ADR 0001](adr/0001-mcp-server-architecture.md).

### Phased delivery

1. Sample semantic layer on Northridge for the early warning use case
   (DEVOPS-181).
2. Design of the MCP tools and the server (DEVOPS-182).
3. Tools that query the semantic layer, for a configured demo user, without
   sign-in (DEVOPS-183).
4. Sign-in through Ed-Fi Admin App user management with OAuth (DEVOPS-184).
   1. Admin App users linked to staff roles, with access for each role
      (DEVOPS-185).
5. Design of the lineage records, populated by hand (DEVOPS-186).
6. Lineage reported by the tools (DEVOPS-187).

## 6. Out of scope and known limitations

### Out of scope

- An official Ed-Fi semantic layer. The Alliance provides the proof of concept,
  patterns and documentation; organizations build their own.
- Production use: hardening, scaling, high availability, support.
- Writing data back to the ODS, or any change to source systems.
- Free-form questions answered by generated SQL or direct Ed-Fi API calls.
- Use cases other than early warning, such as school-to-workforce tracking
  (named in the Project Brief as a candidate).
- Access for students and families.
- API-native lineage (planned for Ed-Fi API 8).

### Known limitations of the sample data

- In the sample data, only teachers have an access scope today; principals and
  superintendents need their staff classifications mapped (phase 4.1).
- The early warning data has no behavior counts yet, although the source has
  discipline incidents.
- Northridge has class attendance only, no daily school attendance.
- Moving the sample data to the current school year shifts dates, not text, so
  session names still show the original school year; some results fall after
  today and are ignored.
- Some Northridge sections are unusually large (about 700 students).

### Assumptions and risks

- The pattern is shown with one sample data set; other data sets may need
  their own mappings.
- An AI application can still misread or misreport correct data. The tools
  reduce, but don't remove, the need for educators to check what they act on.

## 7. Open questions and decision log

### Open questions

- What does success look like for the proof of concept: a demonstration at the
  Summit, use in SIG sessions, or community adoption?
- Will counselors (caseload access) be part of a phase? The sample data has no
  caseloads.
- Is the "fuzzy lookup" for data discovery in the Project Brief (finding how a
  source field maps to an Ed-Fi entity) part of this proof of concept or a
  separate one?
- Which Admin App version, and how are its users linked to staff records?

### Decision log

- **2026-11-04:** Northridge's dates may be adjusted to the current school year;
  a new sample data set isn't feasible. (Stephen Fuqua)
- **2026-11-05:** The proof of concept lives in this repository; the MCP server
  sits next to the semantic layer. (Stephen Fuqua)
- **2026-11-05:** The teacher's view comes first; the principal's view comes
  with the role mapping. (Stephen Fuqua)
- **2026-11-05:** No preference on programming language; the implementation
  choice is in ADR 0001. (Stephen Fuqua)
- **2026-11-05:** The documentation doesn't refer to the product the analytics
  views came from; it describes the views on their own. (Stephen Fuqua)

## 8. Glossary

- **Early warning indicators:** signals that a student may need support.
  Commonly attendance, behavior and course performance ("ABC").
- **Chronic absenteeism:** missing at least 10% of instructional days.
- **Semantic layer:** data reshaped around concepts users understand, between
  operational data and the applications that use it. Here, a data mart.
- **Data mart:** a small database of dimensions and facts for a set of
  analytical questions.
- **MCP (Model Context Protocol):** a protocol through which AI applications
  call tools offered by a server.
- **Tool:** one operation the MCP server offers, with a name, a description and
  parameters.
- **Scope:** the set of students a user may see, from their role and
  assignments.
- **Lineage:** the link from a result back to the source records it came from.
- **ODS:** the Ed-Fi Operational Data Store behind the Ed-Fi API.
- **Northridge:** a fictional Ed-Fi sample data set (about 21,600 students in
  13 schools).
