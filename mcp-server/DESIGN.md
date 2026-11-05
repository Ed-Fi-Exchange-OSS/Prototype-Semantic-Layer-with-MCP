# Early warning MCP server: design

The MCP server lets an AI assistant answer early warning questions for the
signed-in educator ("which of my students are at risk?", "how is this student
doing?") from the data mart in [`datamart/`](../datamart/README.md), and only
for the students that educator may see. The assistant never writes SQL or calls
the Ed-Fi API: it picks from a small set of tools, each one a fixed query with
validated parameters.

## Principles

1. **Narrow, deterministic tools.** Each tool runs one parameterized query. No
   free-form SQL, no table or column names as parameters, no access to the ODS
   or the Ed-Fi API.
2. **Authorization in the server, never in the prompt.** The user comes from
   the session (a configured demo user at first, the OAuth token later), never
   from a tool argument. Every query joins `rls_userstudentdataauthorization` on
   that user, so a prompt that asks for another student's data gets nothing.
3. **Small, readable answers.** Results are compact JSON with the fields a
   person would read (names, courses, rates), capped row counts (default 25,
   maximum 100), and a `truncated` flag. Internal keys appear only when another
   tool needs them.
4. **Read-only.** The server's database role can only `SELECT` from the
   `analytics` schema of the data mart.
5. **Traceable.** Every result names its source tables and the as-of date, so
   lineage can be added later without changing the tool shapes.

## Tools

| Tool | Parameters | Returns | Data mart tables |
| --- | --- | --- | --- |
| `get_my_scope` | none | The user's schools, sections and number of students they may see | `rls_userdim`, `rls_userauthorization`, `staffsectiondim`, `rls_userstudentdataauthorization` |
| `list_my_sections` | none | Each section the user teaches: course, session, student count | `staffsectiondim`, `sectiondim`, `studentsectiondim` |
| `find_students` | `name`, `section`, `grade_level` (all optional), `limit` | Matching students the user may see: name, grade level, school, student key | `studentschooldim`, `studentsectiondim` |
| `list_students_at_risk` | `section` (optional), `absence_threshold` (default 10%), `limit` | Students flagged by attendance, course grades or assessments, with the indicators that flagged them | `ews_studentearlywarningfact`, `ews_studentsectiongradefact`, `gradingperioddim`, `asmt_studentassessmentfact` |
| `get_student_summary` | `student` (key) | One student: attendance so far, current grades by course, recent assessment results, programs | the fact tables above, `studentsectiondim`, `studentprogramdim` |
| `get_attendance_trend` | `student` or `section`, `weeks` (default 6) | Absence rate per week | `ews_studentearlywarningfact`, `datedim` |

### Risk indicators

`list_students_at_risk` uses the attendance, behavior and course performance
("ABC") indicators common in early warning systems, with the thresholds as tool
parameters:

- **Attendance:** absent from any class on at least 10% of instructional days
  so far this school year (chronic absenteeism). Northridge has section
  attendance only, so this uses the `...anyclass` columns.
- **Course performance:** a numeric grade below 70 in the most recent grading
  period.
- **Assessments:** a result of `Fail` or `Well Below Basic` this school year.
- **Behavior:** not yet; the discipline counts in the data mart are all zero
  (see below).

Each student comes back with the indicators that flagged them and the numbers
behind them, sorted by the number of indicators, then by absence rate. On the
local data mart, the query for a Ridgemont High teacher who may see 716 students
takes about 120 ms.

## Approach

- **Language:** TypeScript with the official MCP SDK
  (`@modelcontextprotocol/sdk`) and `pg`.
- **Transport:** Streamable HTTP, since OAuth applies to the HTTP transport;
  stdio as an option for local use with Claude Desktop or VS Code.
- **User:** at first, a `DEMO_USER_EMAIL` setting picks the user (for example a
  Ridgemont High teacher). Taking it from the OAuth token later changes one
  function.
- **Queries:** one SQL file per tool, loaded at startup, run with bind
  parameters only. Parameters are validated with a schema before any query
  runs (types, ranges, `limit` capped).
- **Docker:** a service added to `datamart/docker-compose.yml`, so the data
  mart build plus `docker compose up` gives the whole demo.
- **Tests:** each tool against the local data mart, including a check that a
  user can't read a student outside their scope.

## Scope

- **First:** the teacher's view, with the tools above and a demo user
  (DEVOPS-183).
- **Later:** OAuth through Ed-Fi Admin App users (DEVOPS-184), school and
  district scope for principals and superintendents (DEVOPS-185), and lineage in
  the tool results (DEVOPS-186, DEVOPS-187).

## Data issues found while checking the queries

- **Only teachers have a scope.** `rls_userauthorization` has section scope for
  every user and no school or district scope, so principals and
  superintendents see nothing yet. The views assign scope from the staff
  classification; Northridge's classifications need to be mapped to school and
  district scope.
- **No behavior data in the facts.** The ODS has 1,970 discipline incidents,
  but the early warning fact's discipline counts are all zero; likely a
  descriptor mapping, to check.
- **Session names still say "2017 - 2018"** after the date shift: the time
  travel script moves date and year columns, not text. Cosmetic, but visible in
  answers.
- **Large sections:** some Northridge sections have about 700 students.
- **Results dated in the future:** Northridge holds a whole school year, so
  after the date shift some assessment results fall after today. The tools only
  count results up to today.
