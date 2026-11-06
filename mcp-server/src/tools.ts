// SPDX-License-Identifier: Apache-2.0
// Licensed to the Ed-Fi Alliance under one or more agreements.
// The Ed-Fi Alliance licenses this file to you under the Apache License, Version 2.0.
// See the LICENSE and NOTICES files in the project root for more information.

import type { McpServer } from '@modelcontextprotocol/sdk/server/mcp.js';
import { z } from 'zod';
import { query } from './db.js';

const DEFAULT_LIMIT = 25;
const MAX_LIMIT = 100;

/** Resolves the data mart user key for the session's user. Never taken from a tool argument. */
export type UserResolver = () => Promise<string | undefined>;

const limit = z.number().int().min(1).max(MAX_LIMIT).optional()
    .describe(`Maximum number of rows (default ${DEFAULT_LIMIT}, maximum ${MAX_LIMIT})`);
const key = z.string().min(1).max(300);

function result(data: Record<string, unknown>, sources: string[]) {
    const body = { ...data, as_of: new Date().toISOString().slice(0, 10), sources };
    return { content: [{ type: 'text' as const, text: JSON.stringify(body) }] };
}

function message(text: string) {
    return { content: [{ type: 'text' as const, text }], isError: true };
}

/** Runs a capped query: asks for one row more than the limit to tell whether the result was cut. */
async function capped<T extends Record<string, unknown>>(name: string, params: unknown[], max: number) {
    const rows = await query<T>(name, [...params, max + 1]);
    return { rows: rows.slice(0, max), truncated: rows.length > max };
}

export function registerTools(server: McpServer, currentUser: UserResolver): void {
    const readOnly = { readOnlyHint: true, openWorldHint: false };

    async function withUser<R>(run: (user: string) => Promise<R>) {
        const user = await currentUser();
        if (!user) {
            return message('The signed-in user has no access to student data in the data mart.');
        }
        return run(user);
    }

    server.registerTool('get_my_scope', {
        title: 'My scope',
        description: 'Shows what the signed-in educator may see: schools, sections and the number of '
            + 'students.',
        annotations: readOnly,
    }, () => withUser(async user => {
        const [scope] = await query('my-scope', [user]);
        return result(scope, ['rls_userdim', 'rls_userauthorization', 'staffsectiondim',
            'rls_userstudentdataauthorization']);
    }));

    server.registerTool('list_my_sections', {
        title: 'My sections',
        description: 'Lists the sections the signed-in educator teaches, with the course, the session and '
            + 'the number of students. Use a section key with find_students, list_students_at_risk or '
            + 'get_attendance_trend.',
        annotations: readOnly,
    }, () => withUser(async user => {
        const sections = await query('my-sections', [user]);
        return result({ sections }, ['staffsectiondim', 'sectiondim', 'studentsectiondim']);
    }));

    server.registerTool('find_students', {
        title: 'Find students',
        description: 'Finds students the signed-in educator may see, by part of the name, section or grade '
            + 'level. Returns student keys for get_student_summary and get_attendance_trend.',
        inputSchema: {
            name: z.string().min(2).max(100).optional().describe('Part of the student\'s name'),
            section: key.optional().describe('Section key from list_my_sections'),
            grade_level: z.string().max(50).optional().describe('Grade level, for example "Ninth grade"'),
            limit,
        },
        annotations: readOnly,
    }, args => withUser(async user => {
        const { rows, truncated } = await capped('find-students',
            [user, args.name ?? null, args.section ?? null, args.grade_level ?? null],
            args.limit ?? DEFAULT_LIMIT);
        return result({ students: rows, truncated }, ['studentschooldim', 'schooldim', 'studentsectiondim']);
    }));

    server.registerTool('list_students_at_risk', {
        title: 'Students at risk',
        description: 'Lists the students the signed-in educator may see who meet at least one early warning '
            + 'indicator: absent from at least one class on at least absence_threshold percent of '
            + 'instructional days so far, a grade below passing_grade in the latest grading period, a Fail or Well Below Basic '
            + 'assessment result, or at least discipline_threshold discipline actions (removal from class, '
            + 'suspension, expulsion) so far. Sorted by the number of indicators, then by absence rate. '
            + '"evidence" lists the indicators whose records get_indicator_evidence can show.',
        inputSchema: {
            section: key.optional().describe('Only students in this section (key from list_my_sections)'),
            absence_threshold: z.number().min(1).max(100).optional()
                .describe('Absence rate that flags attendance, in percent (default 10)'),
            passing_grade: z.number().min(1).max(100).optional()
                .describe('Numeric grades below this flag course performance (default 70)'),
            discipline_threshold: z.number().int().min(1).max(50).optional()
                .describe('Number of discipline actions that flags behavior (default 1)'),
            limit,
        },
        annotations: readOnly,
    }, args => withUser(async user => {
        const absenceThreshold = args.absence_threshold ?? 10;
        const passingGrade = args.passing_grade ?? 70;
        const disciplineThreshold = args.discipline_threshold ?? 1;
        const { rows, truncated } = await capped('students-at-risk',
            [user, args.section ?? null, absenceThreshold, passingGrade, disciplineThreshold],
            args.limit ?? DEFAULT_LIMIT);
        return result({
            thresholds: {
                absence_rate: absenceThreshold,
                passing_grade: passingGrade,
                discipline_actions: disciplineThreshold,
            },
            students: rows,
            truncated,
        }, ['ews_studentearlywarningfact', 'ews_studentsectiongradefact', 'gradingperioddim',
            'asmt_studentassessmentfact', 'equity_studentdisciplineactiondim', 'studentschooldim',
            'lineage.indicator_evidence']);
    }));

    server.registerTool('get_student_summary', {
        title: 'Student summary',
        description: 'Summarizes one student the signed-in educator may see: attendance so far, grades in '
            + 'the latest grading period, assessment results, discipline actions and programs. "evidence" '
            + 'lists the indicators whose records get_indicator_evidence can show.',
        inputSchema: { student: key.describe('Student key from find_students or list_students_at_risk') },
        annotations: readOnly,
    }, args => withUser(async user => {
        const [row] = await query<{ summary: Record<string, unknown> }>('student-summary',
            [user, args.student]);
        if (!row) {
            return message(`No student ${args.student} among the students you may see.`);
        }
        return result(row.summary, ['studentschooldim', 'ews_studentearlywarningfact',
            'ews_studentsectiongradefact', 'gradingperioddim', 'studentsectiondim',
            'asmt_studentassessmentfact', 'asmt_assessmentfact', 'equity_studentdisciplineactiondim',
            'studentprogramdim', 'lineage.indicator_evidence']);
    }));

    server.registerTool('get_indicator_evidence', {
        title: 'Indicator evidence',
        description: 'Shows the records behind one early warning indicator for one student the signed-in '
            + 'educator may see: the absences, the grades below passing, the low assessment results or the '
            + 'discipline actions, each with its Ed-Fi ODS resource and id, and the source system and its '
            + 'record id when known. Attendance has one record per class missed: "days" is the number of '
            + 'different days, the same as days_absent (days absent from at least one class). Lineage covers '
            + 'a demonstration set of students; the "evidence" field of '
            + 'list_students_at_risk and get_student_summary says which indicators have records. The source '
            + 'system in the demonstration is a fictional sample.',
        inputSchema: {
            student: key.describe('Student key from find_students or list_students_at_risk'),
            indicator: z.enum(['attendance', 'course_performance', 'assessments', 'behavior'])
                .describe('The early warning indicator'),
            limit,
        },
        annotations: readOnly,
    }, args => withUser(async user => {
        const max = args.limit ?? DEFAULT_LIMIT;
        const [row] = await query<{ evidence: { total: number; days: number; records: unknown[] } }>(
            'indicator-evidence', [user, args.student, args.indicator, max]);
        if (!row) {
            return message(`No student ${args.student} among the students you may see.`);
        }
        const { total, days, records } = row.evidence;
        return result({
            student: args.student,
            indicator: args.indicator,
            total,
            days,
            records,
            truncated: total > records.length,
            ...(total === 0 && {
                note: 'No lineage records for this student and indicator. Lineage covers a demonstration '
                    + 'set of students only, so this does not mean the indicator has no underlying records.',
            }),
        }, ['lineage.indicator_evidence', 'lineage.ods_record', 'lineage.source_system',
            'rls_userstudentdataauthorization']);
    }));

    server.registerTool('get_attendance_trend', {
        title: 'Attendance trend',
        description: 'Shows absences per week over the last weeks, for one student or for a section, '
            + 'counting only the students the signed-in educator may see.',
        inputSchema: {
            student: key.optional().describe('Student key (give a student or a section)'),
            section: key.optional().describe('Section key (give a student or a section)'),
            weeks: z.number().int().min(1).max(40).optional().describe('Number of weeks (default 6)'),
        },
        annotations: readOnly,
    }, args => withUser(async user => {
        if (!args.student === !args.section) {
            return message('Give either a student or a section.');
        }
        const weeks = await query('attendance-trend',
            [user, args.student ?? null, args.section ?? null, args.weeks ?? 6]);
        return result({ weeks }, ['ews_studentearlywarningfact', 'datedim', 'studentsectiondim']);
    }));
}
