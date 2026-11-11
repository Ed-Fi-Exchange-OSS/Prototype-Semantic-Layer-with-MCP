// SPDX-License-Identifier: Apache-2.0
// Licensed to the Ed-Fi Alliance under one or more agreements.
// The Ed-Fi Alliance licenses this file to you under the Apache License, Version 2.0.
// See the LICENSE and NOTICES files in the project root for more information.

// Calls the lineage tools on the running server container as a signed-in user, and prints what comes back.
// For the test record in TESTING.md, section 7. Needs DEMO_USER_PASSWORD (datamart/.env) and
// NODE_EXTRA_CA_CERTS=certs/server.crt.
//
// Usage: node test/lineage/evidence-call.mjs [email] [student]

import { Client } from '@modelcontextprotocol/sdk/client/index.js';
import { StreamableHTTPClientTransport } from '@modelcontextprotocol/sdk/client/streamableHttp.js';

const email = process.argv[2] ?? 'tina.blevins@RidgemontHighSchool.edu';
const student = process.argv[3] ?? '004688';
const issuer = `${process.env.KEYCLOAK_URL ?? 'https://localhost:8443'}/realms/edfi`;
const server = process.env.MCP_URL ?? 'https://localhost:3000/mcp';

const response = await fetch(`${issuer}/protocol/openid-connect/token`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({
        grant_type: 'password', client_id: 'edfi-mcp-tests', username: email,
        password: process.env.DEMO_USER_PASSWORD ?? '',
    }),
});
const { access_token: token } = await response.json();
if (!token) {
    throw new Error(`No token for ${email}`);
}

const client = new Client({ name: 'lineage-check', version: '0.0.0' });
await client.connect(new StreamableHTTPClientTransport(new URL(server),
    { requestInit: { headers: { Authorization: `Bearer ${token}` } } }));

async function show(name, args) {
    const result = await client.callTool({ name, arguments: args });
    console.log(`\n> ${name} ${JSON.stringify(args)}${result.isError ? ' (error)' : ''}`);
    const text = result.content[0].text;
    try {
        console.log(JSON.stringify(JSON.parse(text), null, 2));
    } catch {
        console.log(text);
    }
}

console.log(`Signed in as ${email}; server ${server}`);
const { tools } = await client.listTools();
console.log(`Tools: ${tools.map(t => t.name).sort().join(', ')}`);
const risk = JSON.parse((await client.callTool({ name: 'list_students_at_risk', arguments: { limit: 100 } }))
    .content[0].text);
const row = risk.students.find(s => s.key === student);
console.log(`\nlist_students_at_risk, student ${student}: `
    + JSON.stringify(row ? { indicators: row.indicators, evidence: row.evidence } : 'not in the list'));
for (const indicator of ['attendance', 'course_performance', 'assessments', 'behavior']) {
    await show('get_indicator_evidence', { student, indicator, limit: 2 });
}
await client.close();
