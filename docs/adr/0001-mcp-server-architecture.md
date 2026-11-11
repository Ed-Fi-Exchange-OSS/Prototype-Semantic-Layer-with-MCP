# ADR 0001: Phase 1 architecture of the early warning MCP server

- **Status:** Accepted
- **Date:** 2026-11-05
- **Requirements:** [PRD](../PRD.md)

## Context

The [PRD](../PRD.md) asks for an MCP server that lets an AI application answer
early warning questions for the signed-in educator, only about the students
that educator may see, without giving the AI application SQL or Ed-Fi API
access. This ADR records how the proof of concept implements the semantic layer
and the MCP server for the first phases of the PRD's phased delivery (the
semantic layer, the design and the tools for a demo user), and what it leaves
ready for sign-in and lineage. Those later phases will have their own
decisions, for example how lineage sidecar tables are populated and read.

## Decision

### Semantic layer

- **Analytics views over the ODS, materialized into a separate database.** A
  set of analytics views for Data Standard 5 (dimensions and facts for
  attendance, grades, assessments and chronic absenteeism, plus user-to-student
  access mappings) is installed on the ODS. A build step copies every view into
  a table in its own database (`edfi_datamart`, schema `analytics`), indexed,
  and swaps the tables in one transaction.
- **Sample data in the current school year.** Northridge is restored and its
  dates are moved to the current school year by a PostgreSQL time travel
  script, so the views that look for current enrollments return data.
- **One build for everything.** Bash and PowerShell scripts run every step in a
  PostgreSQL container with Docker Compose.

### MCP server

- **Language:** TypeScript on Node.js 22, with the official MCP SDK
  (`@modelcontextprotocol/sdk`) and `pg`. Stephen Fuqua had no preference; this
  matches the Alliance's earlier MCP work.
- **Transport:** Streamable HTTP over HTTPS, stateless (a new server and
  transport per request), because OAuth in MCP applies to the HTTP transport
  and tokens shouldn't travel in clear text. For the local demonstration, the
  Docker setup creates a self-signed certificate for `localhost`, and MCP
  clients must trust it (Node.js-based clients such as Claude Code and the
  GitHub Copilot CLI through `NODE_EXTRA_CA_CERTS`). Without a certificate the
  server falls back to plain HTTP, for development. Stdio is also available for
  local use.
- **Six fixed tools.** Each tool runs one SQL file with bind parameters only.
  Parameters are validated with a schema (types, ranges, lengths) before any
  query runs. No tool takes SQL, a table, a column or a user.

  | Tool | Capability (PRD) |
  | --- | --- |
  | `get_my_scope` | FR-SCOPE-1 |
  | `list_my_sections` | FR-ROSTER-1 |
  | `find_students` | FR-ROSTER-2 |
  | `list_students_at_risk` | FR-RISK-1 to FR-RISK-7 |
  | `get_student_summary` | FR-STUDENT-1 |
  | `get_attendance_trend` | FR-TREND-1 |

- **Authorization in the server.** The server resolves the user from the
  session and every query joins the user-to-student access mapping
  (`rls_userstudentdataauthorization`) on that user. A student outside the
  mapping simply isn't in the result.
- **User before sign-in.** A `DEMO_USER_EMAIL` setting names the user until
  OAuth. Resolving the user is one function, so sign-in replaces
  it without changing the tools.
- **Read-only access.** The server connects as `mcp_reader`, a role that can
  only read the `analytics` schema of the data mart and has no access to the
  ODS; its sessions are also read-only. [ADR 0003](0003-lineage-sidecar-tables.md)
  extends this to read the `lineage` schema.
- **Compact, traceable results.** Results are JSON with the fields a person
  would read, row caps (default 25, maximum 100) with a `truncated` flag, the
  as-of date and the data mart tables used. Lineage can add source
  references to the same shape.
- **Deployment:** a container defined next to the data mart in the same
  Docker Compose file (profile `mcp`).

## Options considered

### Language: TypeScript, C# or Python

C# would match the ODS/API and the Data Management Service, and Python is common
for data work. TypeScript has the reference MCP SDK, which gets new features of
the specification first, and matches the earlier Ed-Fi MCP servers. Chosen:
TypeScript.

### Free-form questions (generated SQL) or fixed tools

Generated SQL answers more questions, but its correctness and its access rules
would depend on the AI application, which the PRD treats as untrusted
(NFR-SEC-1, NFR-SEC-2). Chosen: fixed tools.

### Where to enforce access: PostgreSQL row-level security or the queries

PostgreSQL row-level security would enforce access in the database itself, but
it needs the user in the database session (a role per user or a session
setting) and policies on every table. Joining the access mapping in each query
is simpler for a few fixed queries, and the tests check it for every tool.
Chosen: the queries, with a read-only role. Row-level security stays an option
when sign-in brings real users.

### Views over the ODS or a materialized data mart

Reading the views directly is always current, but every question runs the
views' joins over the operational tables, and the server would need access to
the ODS. A materialized data mart is fast, isolates the server from the ODS,
and is where lineage tables can live. Chosen: the materialized data mart,
refreshed on demand.

### HTTPS with a self-signed certificate, or plain HTTP

Plain HTTP is simpler for a local demonstration, but sign-in will put access
tokens on the wire, and clients and reviewers expect HTTPS. A self-signed
certificate costs one step at setup and one setting per client. Chosen: HTTPS
with a self-signed certificate; a real deployment would use a trusted
certificate.

### Stateful or stateless HTTP sessions

The tools don't need conversation state, and a stateless server is simpler to
run and scale. Chosen: stateless.

## Consequences

- An AI application can only ask the questions the tools answer. New questions
  mean new tools, each reviewed for scope and size.
- Every new tool must join the access mapping; the tests check scope for each
  tool, and a tool without that check shouldn't be merged.
- The data mart is as current as its last refresh. For the demonstration, the
  build refreshes it; a real deployment would schedule it.
- Changing to sign-in replaces the user resolution and adds token validation;
  the tools stay the same.
- The data issues found while checking the queries are listed in the PRD's
  known limitations.
