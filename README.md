# DLVM Core
## Core Compiler Infrastructure

Welcome to DLVM! For general information about the DLVM project,
please visit [dlvm-team.github.io](https://dlvm-team.github.io).

This repository does not include a code generator.

## Targets

### [DLVM Core](Sources)

| Module             | Description                                             |
|--------------------|---------------------------------------------------------|
| DLVM               | Compiler infrastructure (ADT, IR, Analyses, Transforms) |
| DLParse            | Textual IR parser                                       |
| DLCommandLineTools | Tools for building DLVM CLIs                            |
| dlopt              | CLI for DLVM optimizer                                  |

### [DLVM Runtime](Runtime)

The DLVM runtime (dlrt) includes runtime routines including memory tracking,
reference counting, etc.

## Building

- [**macOS instructions**](https://github.com/rxwei/dlvm-core/wiki/Building-for-macOS)
- [**Linux instructions**](https://github.com/rxwei/dlvm-core/wiki/Building-for-Linux)

## License

[Apache 2](LICENSE)
