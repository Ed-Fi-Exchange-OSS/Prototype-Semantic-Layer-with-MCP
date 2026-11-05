// SPDX-License-Identifier: Apache-2.0
// Licensed to the Ed-Fi Alliance under one or more agreements.
// The Ed-Fi Alliance licenses this file to you under the Apache License, Version 2.0.
// See the LICENSE and NOTICES files in the project root for more information.

// Runs the tools through an MCP client against the local data mart (see ../README.md).

import assert from 'node:assert/strict';
import { after, before, describe, test } from 'node:test';
import { Client } from '@modelcontextprotocol/sdk/client/index.js';
import { McpServer } from '@modelcontextprotocol/sdk/server/mcp.js';
import { InMemoryTransport } from '@modelcontextprotocol/sdk/inMemory.js';
import { pool, query } from '../src/db.js';
import { registerTools } from '../src/tools.js';

const teacherEmail = process.env.TEST_USER_EMAIL ?? 'tina.blevins@RidgemontHighSchool.edu';

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

describe('early warning tools', () => {
    let teacher: string;
    let client: Client;
    let outsider: string;

    before(async () => {
        [{ userkey: teacher }] = await query<{ userkey: string }>('user', [teacherEmail]);
        client = await connect(teacher);
        [{ studentkey: outsider }] = (await pool.query<{ studentkey: string }>(
            `SELECT s.studentkey FROM analytics.studentschooldim s
             WHERE NOT EXISTS (SELECT 1 FROM analytics.rls_userstudentdataauthorization a
                               WHERE a.userkey = $1 AND a.studentkey = s.studentkey)
             LIMIT 1`, [teacher])).rows;
    });

    after(async () => {
        await client.close();
        await pool.end();
    });

    test('lists the six tools, all read-only', async () => {
        const { tools } = await client.listTools();
        assert.deepEqual(tools.map(t => t.name).sort(), ['find_students', 'get_attendance_trend',
            'get_my_scope', 'get_student_summary', 'list_my_sections', 'list_students_at_risk']);
        assert.ok(tools.every(t => t.annotations?.readOnlyHint === true));
    });

    test('get_my_scope counts the students the teacher may see', async () => {
        const scope = JSON.parse((await call(client, 'get_my_scope')).text);
        assert.equal(scope.email.toLowerCase(), teacherEmail.toLowerCase());
        assert.ok(Number(scope.students) > 0);
        assert.ok(scope.sources.includes('rls_userstudentdataauthorization'));
    });

    test('list_students_at_risk flags students and caps the rows', async () => {
        const risk = JSON.parse((await call(client, 'list_students_at_risk', { limit: 5 })).text);
        assert.equal(risk.students.length, 5);
        assert.equal(risk.truncated, true);
        for (const s of risk.students) {
            assert.ok(s.indicators >= 1);
        }
        const counts = risk.students.map((s: { indicators: number }) => s.indicators);
        assert.deepEqual(counts, [...counts].sort((a, b) => b - a));
    });

    test('find_students and get_student_summary work for a student in scope', async () => {
        const found = JSON.parse((await call(client, 'find_students', { limit: 1 })).text);
        const student = found.students[0].key;
        const summary = await call(client, 'get_student_summary', { student });
        assert.equal(summary.isError, false);
        const body = JSON.parse(summary.text);
        assert.equal(body.student.key, student);
        assert.ok(body.attendance.instructional_days > 0);
    });

    test('a student outside the teacher\'s scope returns nothing', async () => {
        const summary = await call(client, 'get_student_summary', { student: outsider });
        assert.equal(summary.isError, true);
        assert.doesNotMatch(summary.text, /attendance|grades/);
        const trend = JSON.parse((await call(client, 'get_attendance_trend', { student: outsider })).text);
        assert.deepEqual(trend.weeks, []);
        const found = JSON.parse((await call(client, 'find_students', { name: outsider })).text);
        assert.deepEqual(found.students, []);
    });

    test('rejects parameters out of range', async () => {
        const response = await call(client, 'find_students', { limit: 1000 });
        assert.equal(response.isError, true);
    });

    test('a user with no access gets an error, not data', async () => {
        const nobody = await connect(undefined);
        const response = await call(nobody, 'list_students_at_risk');
        assert.equal(response.isError, true);
        await nobody.close();
    });
});
