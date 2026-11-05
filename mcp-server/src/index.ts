// SPDX-License-Identifier: Apache-2.0
// Licensed to the Ed-Fi Alliance under one or more agreements.
// The Ed-Fi Alliance licenses this file to you under the Apache License, Version 2.0.
// See the LICENSE and NOTICES files in the project root for more information.

import { createServer as createHttpServer } from 'node:http';
import { McpServer } from '@modelcontextprotocol/sdk/server/mcp.js';
import { StdioServerTransport } from '@modelcontextprotocol/sdk/server/stdio.js';
import { StreamableHTTPServerTransport } from '@modelcontextprotocol/sdk/server/streamableHttp.js';
import { query } from './db.js';
import { registerTools, type UserResolver } from './tools.js';

/**
 * The demo user: until OAuth is in place, DEMO_USER_EMAIL picks whose data the tools return. The user is
 * looked up once and cached.
 */
const demoUserEmail = process.env.DEMO_USER_EMAIL;
let demoUserKey: Promise<string | undefined> | undefined;
const demoUser: UserResolver = () => {
    demoUserKey ??= demoUserEmail
        ? query<{ userkey: string }>('user', [demoUserEmail]).then(rows => rows[0]?.userkey)
        : Promise.resolve(undefined);
    return demoUserKey;
};

function createMcpServer(): McpServer {
    const server = new McpServer({ name: 'ed-fi-early-warning', version: '0.1.0' });
    registerTools(server, demoUser);
    return server;
}

if (process.argv.includes('--stdio')) {
    await createMcpServer().connect(new StdioServerTransport());
} else {
    const port = Number(process.env.PORT ?? 3000);
    // Stateless: a new server and transport for each request, so requests share nothing.
    createHttpServer(async (req, res) => {
        if (req.url !== '/mcp') {
            res.writeHead(404).end();
            return;
        }
        const server = createMcpServer();
        const transport = new StreamableHTTPServerTransport({ sessionIdGenerator: undefined });
        res.on('close', () => {
            void transport.close();
            void server.close();
        });
        await server.connect(transport);
        await transport.handleRequest(req, res);
    }).listen(port, () => console.error(`Early warning MCP server on http://localhost:${port}/mcp`));
}
