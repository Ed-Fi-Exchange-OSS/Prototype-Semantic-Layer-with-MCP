# Early warning MCP server

An MCP server with early warning tools on the
[data mart](../datamart/README.md). An AI assistant connected to it can answer
questions such as "which of my students are at risk?" for the signed-in
educator, and only about the students that educator may see. The requirements
are in [docs/PRD.md](../docs/PRD.md) and the architecture decisions in
[ADR 0001](../docs/adr/0001-mcp-server-architecture.md).

This first version has no sign-in: a demo user, set with `DEMO_USER_EMAIL`,
stands in for the signed-in educator.

What was tested and the results, including runs with Claude Code and GitHub
Copilot, are in [TESTING.md](./TESTING.md).

## Tools

| Tool | What it answers |
| --- | --- |
| `get_my_scope` | What the user may see: schools, sections, number of students |
| `list_my_sections` | The sections the user teaches |
| `find_students` | Students by part of the name, section or grade level |
| `list_students_at_risk` | Students flagged by attendance, grades in the latest grading period or assessment results |
| `get_student_summary` | One student's attendance, grades, assessments and programs |
| `get_attendance_trend` | Absences per week for a student or a section |

Every tool is read-only and returns compact JSON with the date and the data
mart tables it used.

## Run it

Build the data mart first (see [`datamart/`](../datamart/README.md)), with
`MCP_READER_PASSWORD` set in `datamart/.env`. Then, from `datamart/`:

```bash
docker compose --profile mcp up -d --build
```

The server listens on `http://localhost:3000/mcp` (Streamable HTTP). It
connects to the data mart as `mcp_reader`, a role that can only read the
`analytics` schema.

To choose another demo user, set `DEMO_USER_EMAIL` in `datamart/.env` to a staff
email from the data mart, for example:

```sql
SELECT useremail FROM analytics.rls_userdim LIMIT 10;
```

## Connect an assistant

Claude Code:

```bash
claude mcp add --transport http early-warning http://localhost:3000/mcp
```

VS Code (GitHub Copilot), in `.vscode/mcp.json`:

```json
{
  "servers": {
    "early-warning": { "type": "http", "url": "http://localhost:3000/mcp" }
  }
}
```

Then ask, for example: "Which of my students are at risk?", "How is Clark
Vernon doing?" or "Show the attendance trend for my World History section."

## Develop

Requires Node.js 22.

```bash
npm ci
npm run build
npm start              # HTTP on port 3000 (PORT to change it)
node dist/src/index.js --stdio
```

The server reads the standard `PGHOST`, `PGPORT`, `PGDATABASE`, `PGUSER` and
`PGPASSWORD` variables (or `DATAMART_DATABASE_URL`) and `DEMO_USER_EMAIL`.

`npm test` runs every tool through an MCP client against the local data mart,
including checks that a student outside the user's scope returns nothing. Set
the `PG*` variables first; the tests use `TEST_USER_EMAIL`, or a Ridgemont High
teacher by default.
