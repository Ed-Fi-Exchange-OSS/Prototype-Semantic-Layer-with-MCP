// SPDX-License-Identifier: Apache-2.0
// Licensed to the Ed-Fi Alliance under one or more agreements.
// The Ed-Fi Alliance licenses this file to you under the Apache License, Version 2.0.
// See the LICENSE and NOTICES files in the project root for more information.

// Runs the tools through an MCP client against the local data mart (see ../README.md), and checks their
// results against direct queries.

import assert from 'node:assert/strict';
import { after, before, describe, test } from 'node:test';
import { Client } from '@modelcontextprotocol/sdk/client/index.js';
import { McpServer } from '@modelcontextprotocol/sdk/server/mcp.js';
import { InMemoryTransport } from '@modelcontextprotocol/sdk/inMemory.js';
import { pool, query } from '../src/db.js';
import { registerTools } from '../src/tools.js';

const teacherEmail = process.env.TEST_USER_EMAIL ?? 'tina.blevins@RidgemontHighSchool.edu';
const today = new Date().toISOString().slice(0, 10).replaceAll('-', '');

type Row = Record<string, any>;

async function connect(user: string | undefined): Promise<Client> {
    const server = new McpServer({ name: 'test', version: '0.0.0' });
    registerTools(server, async () => user);
    const [clientSide, serverSide] = InMemoryTransport.createLinkedPair();
    await server.connect(serverSide);
    const client = new Client({ name: 'test-client', version: '0.0.0' });
    await client.connect(clientSide);
    return client;
}

async function call(client: Client, name: string, args: Record<string, unknown> = {}) {
    const response = await client.callTool({ name, arguments: args });
    const content = response.content as { type: string; text: string }[];
    return { isError: response.isError === true, text: content[0].text };
}

async function json(client: Client, name: string, args: Record<string, unknown> = {}): Promise<Row> {
    const response = await call(client, name, args);
    assert.equal(response.isError, false, response.text);
    return JSON.parse(response.text);
}

async function rows(text: string, params: unknown[] = []): Promise<Row[]> {
    return (await pool.query(text, params)).rows;
}

describe('early warning tools', () => {
    let teacher: string;
    let client: Client;
    let inScope: Set<string>;
    let section: string;
    let outsider: { key: string; name: string };
    let otherTeacher: string;

    before(async () => {
        [{ userkey: teacher }] = await query<{ userkey: string }>('user', [teacherEmail]);
        client = await connect(teacher);
        inScope = new Set((await rows(
            'SELECT studentkey FROM analytics.rls_userstudentdataauthorization WHERE userkey = $1',
            [teacher])).map(r => r.studentkey));
        [{ sectionkey: section }] = await rows(
            `SELECT st.sectionkey FROM analytics.staffsectiondim st
             JOIN analytics.studentsectiondim ss ON ss.sectionkey = st.sectionkey
             WHERE st.userkey = $1 GROUP BY st.sectionkey ORDER BY count(*) DESC LIMIT 1`, [teacher]);
        // A student the teacher may not see, whose name no student in scope shares
        [outsider] = await rows(
            `SELECT s.studentkey AS key, s.studentfirstname || ' ' || s.studentlastname AS name
             FROM analytics.studentschooldim s
             WHERE NOT EXISTS (SELECT 1 FROM analytics.rls_userstudentdataauthorization a
                               WHERE a.userkey = $1 AND a.studentkey = s.studentkey)
               AND NOT EXISTS (SELECT 1 FROM analytics.studentschooldim o
                               JOIN analytics.rls_userstudentdataauthorization a
                                 ON a.studentkey = o.studentkey AND a.userkey = $1
                               WHERE o.studentlastname = s.studentlastname)
             LIMIT 1`, [teacher]) as { key: string; name: string }[];
        [{ userkey: otherTeacher }] = await rows(
            `SELECT userkey FROM analytics.rls_userstudentdataauthorization
             WHERE userkey <> $1 AND studentkey = $2 LIMIT 1`, [teacher, outsider.key]);
    });

    after(async () => {
        await client.close();
        await pool.end();
    });

    describe('tool list', () => {
        test('has the six tools, each read-only and described', async () => {
            const { tools } = await client.listTools();
            assert.deepEqual(tools.map(t => t.name).sort(), ['find_students', 'get_attendance_trend',
                'get_my_scope', 'get_student_summary', 'list_my_sections', 'list_students_at_risk']);
            for (const tool of tools) {
                assert.equal(tool.annotations?.readOnlyHint, true, tool.name);
                assert.ok((tool.description ?? '').length > 40, tool.name);
            }
        });

        test('no tool takes a user, SQL, table or column as a parameter', async () => {
            const { tools } = await client.listTools();
            const params = tools.flatMap(t => Object.keys(t.inputSchema.properties ?? {}));
            for (const forbidden of ['user', 'email', 'sql', 'query', 'table', 'column']) {
                assert.ok(!params.includes(forbidden), forbidden);
            }
        });
    });

    describe('get_my_scope and list_my_sections', () => {
        test('get_my_scope matches the authorization tables', async () => {
            const scope = await json(client, 'get_my_scope');
            assert.equal(scope.email.toLowerCase(), teacherEmail.toLowerCase());
            assert.equal(scope.students, inScope.size);
            const [{ n }] = await rows(
                `SELECT count(DISTINCT sectionkey)::int AS n
                 FROM analytics.staffsectiondim WHERE userkey = $1`,
                [teacher]);
            assert.equal(scope.sections, n);
            assert.match(scope.as_of, /^\d{4}-\d{2}-\d{2}$/);
            assert.ok(scope.sources.includes('rls_userstudentdataauthorization'));
        });

        test('list_my_sections returns only the teacher\'s sections', async () => {
            const { sections } = await json(client, 'list_my_sections');
            const mine = new Set((await rows(
                'SELECT sectionkey FROM analytics.staffsectiondim WHERE userkey = $1', [teacher]))
                .map(r => r.sectionkey));
            assert.equal(sections.length, mine.size);
            for (const s of sections) {
                assert.ok(mine.has(s.key), s.key);
            }
        });
    });

    describe('find_students', () => {
        test('matches part of the name, ignoring case, within scope', async () => {
            const [{ studentlastname }] = await rows(
                `SELECT s.studentlastname FROM analytics.studentschooldim s
                 JOIN analytics.rls_userstudentdataauthorization a ON a.studentkey = s.studentkey
                 WHERE a.userkey = $1 LIMIT 1`, [teacher]);
            const { students } = await json(client, 'find_students', { name: studentlastname.toUpperCase() });
            assert.ok(students.length > 0);
            for (const s of students) {
                assert.ok(inScope.has(s.key));
                assert.match(s.name.toLowerCase(), new RegExp(studentlastname.toLowerCase()));
            }
        });

        test('filters by section', async () => {
            const { students } = await json(client, 'find_students', { section, limit: 100 });
            const enrolled = new Set((await rows(
                'SELECT studentkey FROM analytics.studentsectiondim WHERE sectionkey = $1', [section]))
                .map(r => r.studentkey));
            assert.ok(students.length > 0);
            for (const s of students) {
                assert.ok(enrolled.has(s.key) && inScope.has(s.key));
            }
        });

        test('caps the rows and says when it did', async () => {
            const result = await json(client, 'find_students', { limit: 3 });
            assert.equal(result.students.length, 3);
            assert.equal(result.truncated, true);
        });
    });

    describe('list_students_at_risk', () => {
        test('every student is in scope, and the indicators match the numbers', async () => {
            const { students, thresholds } = await json(client, 'list_students_at_risk', { limit: 100 });
            assert.deepEqual(thresholds, { absence_rate: 10, passing_grade: 70, discipline_actions: 1 });
            assert.ok(students.length > 0);
            for (const s of students) {
                assert.ok(inScope.has(s.key), s.key);
                const expected = Number(s.absence_rate >= 10) + Number(s.failing_grades > 0)
                    + Number(s.low_assessments > 0) + Number(s.discipline_actions >= 1);
                assert.equal(s.indicators, expected, s.key);
                assert.ok(s.indicators >= 1);
            }
        });

        test('is sorted by indicators, then by absence rate', async () => {
            const { students } = await json(client, 'list_students_at_risk', { limit: 100 });
            for (let i = 1; i < students.length; i++) {
                const [a, b] = [students[i - 1], students[i]];
                assert.ok(a.indicators > b.indicators
                    || (a.indicators === b.indicators && (a.absence_rate ?? -1) >= (b.absence_rate ?? -1)));
            }
        });

        test('uses the absence threshold it is given', async () => {
            const { students } = await json(client, 'list_students_at_risk',
                { absence_threshold: 50, limit: 100 });
            for (const s of students) {
                assert.ok(s.absence_rate >= 50 || s.failing_grades > 0 || s.low_assessments > 0
                    || s.discipline_actions >= 1, s.key);
                assert.equal(s.indicators, Number(s.absence_rate >= 50) + Number(s.failing_grades > 0)
                    + Number(s.low_assessments > 0) + Number(s.discipline_actions >= 1));
            }
        });

        test('counts discipline actions up to today, once each', async () => {
            const { students } = await json(client, 'list_students_at_risk', { limit: 100 });
            const flagged = students.filter((s: Row) => s.discipline_actions > 0);
            assert.ok(flagged.length > 0, 'some students in scope have discipline actions');
            for (const s of flagged.slice(0, 5)) {
                const [{ n }] = await rows(
                    `SELECT count(DISTINCT regexp_replace(studentdisciplineactionkey, '-[^-]*$', ''))::int
                            AS n
                     FROM analytics.equity_studentdisciplineactiondim
                     WHERE studentkey = $1 AND disciplinedatekey <= $2`, [s.key, today]);
                assert.equal(s.discipline_actions, n, s.key);
                const summary = await json(client, 'get_student_summary', { student: s.key });
                assert.equal(summary.discipline_actions.length, n, s.key);
                for (const a of summary.discipline_actions) {
                    assert.ok(a.date.replaceAll('-', '') <= today, `action dated ${a.date}`);
                }
            }
        });

        test('filters by section', async () => {
            const { students } = await json(client, 'list_students_at_risk', { section, limit: 100 });
            const enrolled = new Set((await rows(
                'SELECT studentkey FROM analytics.studentsectiondim WHERE sectionkey = $1', [section]))
                .map(r => r.studentkey));
            for (const s of students) {
                assert.ok(enrolled.has(s.key));
            }
        });
    });

    describe('get_student_summary', () => {
        test('matches the data mart for a student in scope', async () => {
            const { students } = await json(client, 'list_students_at_risk', { limit: 1 });
            const key = students[0].key;
            const summary = await json(client, 'get_student_summary', { student: key });
            assert.equal(summary.student.key, key);
            const [direct] = await rows(
                `SELECT sum(isinstructionalday)::int AS days,
                        sum(greatest(isabsentfromanyclassexcused,
                                     isabsentfromanyclassunexcused))::int AS absent
                 FROM analytics.ews_studentearlywarningfact WHERE studentkey = $1`, [key]);
            assert.equal(summary.attendance.instructional_days, direct.days);
            assert.equal(summary.attendance.days_absent, direct.absent);
            for (const a of summary.assessments ?? []) {
                assert.ok(a.date.replaceAll('-', '') <= today, `assessment dated ${a.date}`);
            }
        });
    });

    describe('get_attendance_trend', () => {
        test('returns at most the weeks asked for, each starting on a Monday', async () => {
            const { weeks } = await json(client, 'get_attendance_trend', { section, weeks: 4 });
            assert.ok(weeks.length > 0 && weeks.length <= 4);
            for (const w of weeks) {
                assert.equal(new Date(`${w.week_of}T00:00:00Z`).getUTCDay(), 1, w.week_of);
            }
        });

        test('needs exactly one of student and section', async () => {
            assert.equal((await call(client, 'get_attendance_trend')).isError, true);
            const both = await call(client, 'get_attendance_trend', { section, student: [...inScope][0] });
            assert.equal(both.isError, true);
        });
    });

    describe('scope', () => {
        test('a student outside the teacher\'s scope returns nothing from any tool', async () => {
            const summary = await call(client, 'get_student_summary', { student: outsider.key });
            assert.equal(summary.isError, true);
            assert.doesNotMatch(summary.text, new RegExp(outsider.name));
            const trend = await json(client, 'get_attendance_trend', { student: outsider.key });
            assert.deepEqual(trend.weeks, []);
            const lastName = outsider.name.split(' ').pop()!;
            const found = await json(client, 'find_students', { name: lastName });
            assert.ok(!found.students.some((s: Row) => s.key === outsider.key));
            const risk = await json(client, 'list_students_at_risk', { limit: 100, absence_threshold: 1 });
            assert.ok(!risk.students.some((s: Row) => s.key === outsider.key));
        });

        test('another teacher who may see that student gets it', async () => {
            const other = await connect(otherTeacher);
            const summary = await json(other, 'get_student_summary', { student: outsider.key });
            assert.equal(summary.student.key, outsider.key);
            await other.close();
        });

        test('an extra "user" argument doesn\'t change whose data comes back', async () => {
            const asked = await json(client, 'find_students', { limit: 100 });
            const response = await client.callTool({ name: 'find_students',
                arguments: { limit: 100, user: otherTeacher, email: 'someone@else.edu' } });
            const injected = JSON.parse((response.content as { text: string }[])[0].text);
            assert.deepEqual(injected.students, asked.students);
        });

        test('a session with no user gets an error, not data', async () => {
            const nobody = await connect(undefined);
            for (const name of ['get_my_scope', 'list_students_at_risk']) {
                const response = await call(nobody, name);
                assert.equal(response.isError, true);
                assert.doesNotMatch(response.text, /"students"/);
            }
            await nobody.close();
        });
    });

    describe('roles', () => {
        async function roleUser(scope: string): Promise<Row> {
            const [user] = await rows(
                `SELECT userkey, schoolpermission FROM analytics.rls_userauthorization
                 WHERE userscope = $1 ORDER BY userkey LIMIT 1`, [`AuthorizationScope.${scope}`]);
            return user;
        }

        test('a principal sees students enrolled at their school, and no one else', async () => {
            const { userkey, schoolpermission: school } = await roleUser('School');
            const principal = await connect(userkey);
            const scope = await json(principal, 'get_my_scope');
            assert.deepEqual(scope.scopes.map((s: Row) => s.scope), ['School']);
            const [{ outside }] = await rows(
                `SELECT count(*)::int AS outside FROM analytics.rls_userstudentdataauthorization a
                 WHERE a.userkey = $1 AND NOT EXISTS (
                     SELECT 1 FROM analytics.studentschooldim s
                     WHERE s.studentkey = a.studentkey AND s.schoolkey = $2)`, [userkey, school]);
            assert.equal(outside, 0);
            assert.ok(scope.students > inScope.size, 'more than a teacher');
            const [other] = await rows(
                `SELECT s.studentkey FROM analytics.studentschooldim s
                 WHERE NOT EXISTS (SELECT 1 FROM analytics.rls_userstudentdataauthorization a
                                   WHERE a.userkey = $1 AND a.studentkey = s.studentkey) LIMIT 1`,
                [userkey]);
            const response = await call(principal, 'get_student_summary', { student: other.studentkey });
            assert.equal(response.isError, true);
            await principal.close();
        });

        test('the superintendent sees the district', async () => {
            const { userkey } = await roleUser('District');
            const superintendent = await connect(userkey);
            const scope = await json(superintendent, 'get_my_scope');
            assert.equal(scope.scopes[0].scope, 'District');
            assert.ok(scope.scopes[0].district);
            const [{ n }] = await rows(
                'SELECT count(DISTINCT studentkey)::int AS n FROM analytics.studentschooldim');
            assert.equal(scope.students, n);
            const summary = await json(superintendent, 'get_student_summary', { student: outsider.key });
            assert.equal(summary.student.key, outsider.key);
            await superintendent.close();
        });
    });

    describe('input handling', () => {
        test('rejects values out of range', async () => {
            const cases: [string, Record<string, unknown>][] = [
                ['find_students', { limit: 1000 }],
                ['find_students', { name: 'a' }],
                ['list_students_at_risk', { absence_threshold: 0 }],
                ['list_students_at_risk', { passing_grade: 101 }],
                ['list_students_at_risk', { discipline_threshold: 0 }],
                ['get_attendance_trend', { section, weeks: 100 }],
            ];
            for (const [name, args] of cases) {
                const response = await call(client, name, args);
                assert.equal(response.isError, true, `${name} ${JSON.stringify(args)}`);
            }
        });

        test('treats SQL in a parameter as plain text', async () => {
            const attacks = ["x' OR '1'='1", "'; DROP TABLE analytics.rls_userdim; --", '%%'];
            for (const name of attacks) {
                const found = await json(client, 'find_students', { name, limit: 100 });
                for (const s of found.students) {
                    assert.ok(inScope.has(s.key));
                }
            }
            const risk = await json(client, 'list_students_at_risk', { section: "x' OR '1'='1" });
            assert.deepEqual(risk.students, []);
            const [{ n }] = await rows('SELECT count(*)::int AS n FROM analytics.rls_userdim');
            assert.ok(n > 0);
        });

        test('the server\'s database session is read-only', async () => {
            await assert.rejects(
                pool.query('CREATE TABLE analytics.should_not_exist (id int)'),
                /read-only transaction/);
        });
    });
});
