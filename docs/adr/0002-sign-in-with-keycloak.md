# ADR 0002: Sign-in to the early warning MCP server with Keycloak

- **Status:** Proposed
- **Date:** 2026-11-06
- **Requirements:** [PRD](../PRD.md), FR-AUTH-1 to FR-AUTH-4
- **Builds on:** [ADR 0001](0001-mcp-server-architecture.md)

## Context

[ADR 0001](0001-mcp-server-architecture.md) left sign-in for a later phase: a
demo user stood in for the signed-in educator. This phase replaces the demo
user with OAuth sign-in, so the AI application only gets data about the
students of the person who signed in.

The PRD first named Ed-Fi Admin App's user management as the identity source.
Admin App signs its users in through Keycloak, but it holds no link from users
to Ed-Fi staff records, and its roles describe administration of Ed-Fi
deployments rather than access to student data. Stephen Fuqua confirmed that
Keycloak on its own is enough and that Admin App can be left out.

## Decision

- **Authorization server:** Keycloak, in the same Docker Compose setup as the
  data mart, with a realm named `edfi` like Admin App's, on
  `https://localhost:8443` with the demonstration's self-signed certificate.
- **The MCP server is a resource server only.** It validates access tokens and
  never issues them:
  - signature against Keycloak's published keys (read inside Docker over the
    internal network);
  - issuer `https://localhost:8443/realms/edfi`;
  - audience: the MCP server's own URL, `https://localhost:3000/mcp`, added to
    tokens by an audience mapper on the client;
  - expiry, with 30 seconds of clock tolerance.
- **Discovery for MCP clients.** The server publishes protected resource
  metadata (RFC 9728) at `/.well-known/oauth-protected-resource/mcp`, naming
  Keycloak as the authorization server, and answers a request without a valid
  token with `401` and a `WWW-Authenticate: Bearer resource_metadata="..."`
  header, as the MCP authorization specification requires.
- **The user is the token's verified email.** A token without `email`, or with
  `email_verified` not `true`, is rejected. The email is matched without regard
  to case to the staff emails in the data mart (Keycloak stores emails in lower
  case); no match means no data. Access then follows the data mart's mappings,
  as before.
- **Pre-registered public client.** `edfi-mcp` uses the authorization code flow
  with PKCE (S256 required), with the redirect URIs of Claude Code and VS Code.
  A separate `edfi-mcp-tests` client allows the password grant, only for local
  automated tests.
- **Demo users** for a teacher, a principal and the superintendent are created
  in Keycloak by a setup step, with a password from `.env`.
- **Demo user without sign-in** remains for development: when `OAUTH_ISSUER` is
  empty, every request uses `DEMO_USER_EMAIL`, as in phase 1.

## Options considered

### Admin App's user management, or Keycloak alone

Requiring an active Admin App user would add the whole Admin App stack to the
demonstration and a lookup in its database, without adding a link to staff or
any student-level access rule. Chosen: Keycloak alone, as confirmed by Stephen
Fuqua.

### Dynamic client registration, or a pre-registered client

The MCP specification lets clients register dynamically, but Keycloak only
allows anonymous registration with its client policies loosened, and the
common MCP clients accept a pre-registered client ID. Chosen: a pre-registered
public client.

### Audience from resource indicators (RFC 8707), or an audience mapper

The MCP specification asks clients to send the `resource` parameter so tokens
are bound to one server; Keycloak 26.1 doesn't apply it. Chosen: an audience
mapper on the client that always adds the MCP server's URL. A token issued to
another client, without that audience, is rejected.

## Consequences

- An MCP client that connects without a token now gets `401` and the metadata
  URL, instead of the demo user's data. Clients have to sign in first.
- The tools don't change: only how the user is found changed.
- Anyone who can sign in to the realm with an email that matches a staff email
  gets that staff member's access, so the realm is the place to control users.
- Staff whose classification has no access scope (assistant principals, the
  district administrator) can sign in but see no students.
- A real deployment would use its own identity provider and trusted
  certificates; the realm, the users and `start-dev` here are for the
  demonstration.
