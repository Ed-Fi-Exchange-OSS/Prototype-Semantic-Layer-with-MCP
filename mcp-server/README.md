# Early warning MCP server

An MCP server with early warning tools on the
[data mart](../datamart/README.md). An AI assistant connected to it can answer
questions such as "which of my students are at risk?" for the signed-in
educator, and only about the students that educator may see. The requirements
are in [docs/PRD.md](../docs/PRD.md) and the architecture decisions in
[`docs/adr/`](../docs/adr/).

Educators sign in through Keycloak (OAuth), and the server takes the user from
the token's verified email. For development, sign-in can be turned off so that a
demo user, set with `DEMO_USER_EMAIL`, stands in for the signed-in educator.

What was tested and the results, including runs with Claude Code and GitHub
Copilot, are in [TESTING.md](./TESTING.md).

## Tools

| Tool | What it answers |
| --- | --- |
| `get_my_scope` | What the user may see: schools, sections, number of students |
| `list_my_sections` | The sections the user teaches |
| `find_students` | Students by part of the name, section or grade level |
| `list_students_at_risk` | Students flagged by attendance, behavior (discipline actions), grades in the latest grading period or assessment results |
| `get_student_summary` | One student's attendance, grades, assessments, discipline actions and programs |
| `get_attendance_trend` | Absences per week for a student or a section |

Every tool is read-only and returns compact JSON with the date and the data
mart tables it used.

## Run it

Build the data mart first (see [`datamart/`](../datamart/README.md)). The
data mart only needs `POSTGRES_PASSWORD` and `MCP_READER_PASSWORD` in
`datamart/.env`; sign-in also needs `KEYCLOAK_ADMIN_PASSWORD` (Keycloak's
`admin` user) and `DEMO_USER_PASSWORD` (the demo users). Then, from `datamart/`:

```bash
docker compose --profile mcp up -d --build
```

The server listens on `https://localhost:3000/mcp` (Streamable HTTP). The first
start creates a self-signed certificate for `localhost` in
`mcp-server/certs/server.crt`; MCP clients have to trust it (see below). The
server connects to the data mart as `mcp_reader`, a role that can only read the
`analytics` schema.

To choose another demo user, set `DEMO_USER_EMAIL` in `datamart/.env` to a staff
email from the data mart. What the user sees follows their role:

- a teacher, the students in their sections (for example
  `tina.blevins@RidgemontHighSchool.edu`);
- a principal, the students of their school (for example
  `carmen.helms@RidgemontHighSchool.edu`);
- the superintendent, the whole district (`superintendent@NorthridgeISD.edu`).

```sql
SELECT u.useremail, a.userscope
FROM analytics.rls_userdim u
JOIN analytics.rls_userauthorization a ON a.userkey = u.userkey
LIMIT 10;
```

## Connect an assistant

The certificate is self-signed, so each client has to trust it. Clients sign
in through Keycloak with the pre-registered client ID `edfi-mcp`: on the first
request the server answers `401` and points them to Keycloak, and they open a
browser to sign in. The demo users are `tina.blevins@RidgemontHighSchool.edu`
(a teacher), `carmen.helms@RidgemontHighSchool.edu` (a principal) and
`superintendent@NorthridgeISD.edu`, with the password set in
`DEMO_USER_PASSWORD` in `datamart/.env`.

Claude Code and the GitHub Copilot CLI run on Node.js: point
`NODE_EXTRA_CA_CERTS` to the certificate before starting them, for example from
the repository root:

```bash
export NODE_EXTRA_CA_CERTS="$PWD/mcp-server/certs/server.crt"
claude mcp add --transport http early-warning https://localhost:3000/mcp \
  --client-id edfi-mcp --callback-port 33419
```

Then run `/mcp` in Claude Code and choose to authenticate.

VS Code (GitHub Copilot) uses the operating system's trusted certificates: add
`server.crt` to them (on Windows, "Trusted Root Certification Authorities" for
the current user; on macOS, the login keychain, set to "Always Trust"), then in
`.vscode/mcp.json`:

```json
{
  "servers": {
    "early-warning": { "type": "http", "url": "https://localhost:3000/mcp" }
  }
}
```

When VS Code asks for a client ID, enter `edfi-mcp`, and leave the client
secret empty.

Then ask, for example: "Which of my students are at risk?", "How is Clark
Vernon doing?" or "Show the attendance trend for my World History section."

## Develop

Requires Node.js 22.

```bash
npm ci
npm run build
npm start              # port 3000 (PORT); HTTPS with TLS_CERT_FILE and TLS_KEY_FILE
node dist/src/index.js --stdio
```

The server reads the standard `PGHOST`, `PGPORT`, `PGDATABASE`, `PGUSER` and
`PGPASSWORD` variables (or `DATAMART_DATABASE_URL`) and `DEMO_USER_EMAIL`.

`npm test` runs every tool through an MCP client against the local data mart,
including checks that a student outside the user's scope returns nothing. Set
the `PG*` variables first; the tests use `TEST_USER_EMAIL`, or a Ridgemont High
teacher by default.
