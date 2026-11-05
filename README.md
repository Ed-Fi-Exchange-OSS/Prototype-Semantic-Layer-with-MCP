# Prototype-Semantic-Layer-with-MCP

[![OpenSSF Scorecard](https://api.securityscorecards.dev/projects/github.com/Ed-Fi-Exchange-OSS/Prototype-Semantic-Layer-with-MCP/badge)](https://securityscorecards.dev/viewer/?uri=github.com/Ed-Fi-Exchange-OSS/Prototype-Semantic-Layer-with-MCP)

Prototype of a semantic layer exposed to AI assistants through the Model Context
Protocol (MCP). This code is for demonstration purposes only; it is not intended
to be a robust production solution. It demonstrates patterns discussed in [The
Ed-Fi Data Standard in the Age of AI: Benefits, Limitations, and a Path
Forward](https://docs.ed-fi.org/getting-started/provider-playbook/implementation/ed-fi-data-standard-in-the-age-of-ai),
which were further elucidated in the [Ed-Fi and AI Special Interest Group
2026](https://edfi.atlassian.net/wiki/spaces/ESIG/pages/2361622529/Ed-Fi+and+AI+Special+Interest+Group+2026).

## Contents

- [`datamart/`](./datamart/README.md): the semantic layer, a PostgreSQL data
  mart for the early warning use case, built from the Northridge sample data
  with the Analytics Middle Tier.

## License

Copyright (c) 2026, Ed-Fi Alliance, LLC. All rights reserved.

This project is licensed under the Apache License, Version 2.0 - see the
[LICENSE](./LICENSE) file for details.
