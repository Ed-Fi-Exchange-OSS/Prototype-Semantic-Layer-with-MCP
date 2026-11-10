// SPDX-License-Identifier: Apache-2.0
// Licensed to the Ed-Fi Alliance under one or more agreements.
// The Ed-Fi Alliance licenses this file to you under the Apache License, Version 2.0.
// See the LICENSE and NOTICES files in the project root for more information.

import type { RequestListener } from 'node:http';
import { McpServer } from '@modelcontextprotocol/sdk/server/mcp.js';
import { StreamableHTTPServerTransport } from '@modelcontextprotocol/sdk/server/streamableHttp.js';
import { authenticate, resourceMetadata, type AuthConfig } from './auth.js';
import { query } from './db.js';
import { registerTools, type UserResolver } from './tools.js';

/** The data mart user for an email address, if any. */
export function userByEmail(email: string | undefined): UserResolver {
    let userKey: Promise<string | undefined> | undefined;
    return () => {
        userKey ??= email
            ? query<{ userkey: string }>('user', [email]).then(rows => rows[0]?.userkey)
            : Promise.resolve(undefined);
        return userKey;
    };
}

export function createMcpServer(user: UserResolver): McpServer {
    const server = new McpServer({ name: 'ed-fi-early-warning', version: '0.1.0' });
    registerTools(server, user);
    return server;
}

/**
 * Handles MCP over Streamable HTTP, stateless: a new server and transport for each request, so requests share
 * nothing. With sign-in, each request must carry an access token, and the user comes from it; without it,
 * the demo user is used for every request.
 */
export function createRequestHandler(
    options: { auth?: AuthConfig; demoUserEmail?: string },
): RequestListener {
    const { auth } = options;
    const demoUser = userByEmail(options.demoUserEmail);
    const metadataPaths = new Set(['/.well-known/oauth-protected-resource',
        '/.well-known/oauth-protected-resource/mcp']);

    return async (req, res) => {
        const path = (req.url ?? '').split('?')[0];
        if (auth && req.method === 'GET' && metadataPaths.has(path)) {
            res.writeHead(200, { 'Content-Type': 'application/json' })
                .end(JSON.stringify(resourceMetadata(auth)));
            return;
        }
        if (path !== '/mcp') {
            res.writeHead(404).end();
            return;
        }
        let user = demoUser;
        if (auth) {
            const result = await authenticate(req, auth);
            if (!result.ok) {
                res.writeHead(401, { 'WWW-Authenticate': result.wwwAuthenticate }).end();
                return;
            }
            user = userByEmail(result.email);
        }
        const server = createMcpServer(user);
        const transport = new StreamableHTTPServerTransport({ sessionIdGenerator: undefined });
        res.on('close', () => {
            void transport.close();
            void server.close();
        });
        await server.connect(transport);
        await transport.handleRequest(req, res);
    };
}
