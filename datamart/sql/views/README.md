# Analytics views

PostgreSQL scripts that build a simple data mart over an ODS/API database on
Data Standard 5.2, focused on a few use cases. They create the views in the
`analytics` schema and their configuration in `analytics_config`.

| Folder | Use case |
| --- | --- |
| `Base` | Dimensions: dates, schools, sections, students, staff, grading periods, demographics |
| `Asmt` | Assessment results |
| `Ews` | Early warning: daily attendance and discipline, section grades |
| `Chrab` | Chronic absenteeism |
| `RLS` | Row-level security: users and the students each one may see |

Install `Base` first, then the other folders, each in file-name order.
