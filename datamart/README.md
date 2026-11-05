# Early warning data mart

A small PostgreSQL data mart for the early warning use case, built from the
Ed-Fi Northridge sample data with the [Analytics Middle
Tier](https://github.com/Ed-Fi-Exchange-OSS/Ed-Fi-Analytics-Middle-Tier) (AMT).
It's the semantic layer the MCP server reads: Ed-Fi data reshaped into
dimensions and facts about attendance, assessments and grades, plus the
user-to-student mappings that row-level security needs.

## Requirements

- Docker with Docker Compose
- PowerShell 7
- About 4 GB of disk space

## Build

```powershell
Copy-Item .env.example .env   # then set POSTGRES_PASSWORD in .env
./build-datamart.ps1
```

The first build takes about 15 minutes. It runs every step in a PostgreSQL 16
container (`docker-compose.yml`, port 5440 by default):

1. **Sample data:** downloads Northridge (ODS/API 7.3, Data Standard 5.2, about
   21,600 students in 13 schools) and restores it as `EdFi_Ods_Northridge`.
2. **Current school year:** Northridge holds the 2017-2018 school year.
   `sql/time-travel.sql` moves every date to the current school year, keeping
   weekdays, so the AMT views that look for current enrollments return data.
3. **Analytics Middle Tier:** installs the AMT views for Data Standard 5
   (`sql/amt`) on the ODS, and maps Northridge's staff email type so each staff
   member becomes a user (`sql/amt-descriptor-map.sql`).
4. **Data mart:** `sql/amt-datamart.sql` copies every AMT view into a table in
   the `edfi_datamart` database, schema `analytics`, and indexes them.

To rebuild only the data mart from the ODS, run
`./build-datamart.ps1 -RefreshOnly`.

## What's in it

| Table | What it holds |
| --- | --- |
| `ews_studentearlywarningfact` | One row per student, school and day: attendance (school, homeroom, any class) and discipline counts |
| `ews_studentsectiongradefact` | Grades per student, section and grading period |
| `chrab_chronicabsenteeismattendancefact` | Daily attendance for chronic absenteeism |
| `asmt_studentassessmentfact`, `asmt_assessmentfact` | Assessment results and assessments |
| `studentschooldim`, `studentsectiondim`, `schooldim`, `sectiondim`, `datedim`, ... | Dimensions |
| `rls_userdim` | One user per staff member, keyed by email |
| `rls_userstudentdataauthorization` | The students each user may see |

Every table has a `schoolyearsource` column with the source school year.

## Example: a teacher's students with the most absences

```sql
SELECT f.studentkey,
       sum(f.isinstructionalday) AS days,
       sum(greatest(f.isabsentfromanyclassexcused, f.isabsentfromanyclassunexcused)) AS days_absent
FROM analytics.ews_studentearlywarningfact f
JOIN analytics.rls_userstudentdataauthorization a ON a.studentkey = f.studentkey
JOIN analytics.rls_userdim u ON u.userkey = a.userkey
WHERE u.useremail = :'email'
GROUP BY f.studentkey
ORDER BY days_absent DESC
LIMIT 10;
```

## Notes

- Northridge has no school-level attendance events; attendance comes from
  section attendance (`...anyclass` columns).
- The early warning and chronic absenteeism facts stop at today's date, as they
  would mid-year.
- Some Northridge birth dates are implausible (from the source data, not from
  the date shift).
- This is a prototype for demonstration, not a production data mart.
