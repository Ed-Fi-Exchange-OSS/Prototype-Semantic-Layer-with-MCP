# Analytics Middle Tier scripts for Data Standard 5

PostgreSQL scripts of the [Analytics Middle
Tier](https://github.com/Ed-Fi-Exchange-OSS/Ed-Fi-Analytics-Middle-Tier) (AMT)
for Data Standard 5, unchanged, for the collections the early warning use case
needs:

| Folder | Collection |
| --- | --- |
| `Base` | Dimensions: dates, schools, sections, students, staff, grading periods, demographics |
| `Asmt` | Assessment facts |
| `Ews` | Early warning: daily attendance and discipline, section grades |
| `Chrab` | Chronic absenteeism |
| `RLS` | Row-level security: users and the students each one may see |

## Source

AMT's Data Standard 5.0 support was merged in
[Ed-Fi-Analytics-Middle-Tier#242](https://github.com/Ed-Fi-Exchange-OSS/Ed-Fi-Analytics-Middle-Tier/pull/242),
but its merge commit, `ff2f7eed939c2b33e678a56e86051c9e3d2e7ae3`, isn't on
`main` or in a release. These files are
`src/EdFi.AnalyticsMiddleTier.DataStandard50/<Collection>/PostgreSQL/` at that
commit. They're kept here so the prototype doesn't depend on a commit that no
branch holds.

They install without errors on an ODS/API 7.3 database with Data Standard 5.2.

## Order

Install `Base` first, then the other folders, each in file-name order, as the
AMT installer does.
