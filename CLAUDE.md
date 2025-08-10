# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Development Commands

### Environment Setup
- **Install dependencies**: `poetry install --extras all`
- **Run Synapse**: `poetry run python -m synapse.app.homeserver -c homeserver.yaml`
- **Generate config**: `cp docs/sample_config.yaml homeserver.yaml && cp docs/sample_log_config.yaml log_config.yaml`

### Code Quality
- **Run linters**: `poetry run ./scripts-dev/lint.sh`
- **Lint changed files only**: `poetry run ./scripts-dev/lint.sh -d`
- **Type checking**: `mypy` (run as part of lint.sh)

### Testing
- **Unit tests**: `poetry run trial tests`
- **Parallel unit tests**: `poetry run trial -j4 tests`
- **Specific test**: `poetry run trial tests.rest.admin.test_room`
- **PostgreSQL tests**: `SYNAPSE_POSTGRES=1 poetry run trial tests`
- **Integration tests (Sytest)**: `docker run --rm -it -v $(pwd):/src:ro -v $(pwd)/logs:/logs matrixdotorg/sytest-synapse:focal`
- **Integration tests (Complement)**: `COMPLEMENT_DIR=../complement ./scripts-dev/complement.sh`

### Database Operations
- **Create full schema**: `./scripts-dev/make_full_schema.sh -p postgres_username -o output_dir/`
- **Port database**: `poetry run python -m synapse._scripts.synapse_port_db`

## Architecture Overview

Synapse is a Matrix homeserver implementation with a layered architecture:

### Core Components
- **Handlers** (`synapse/handlers/`): Business logic layer implementing Matrix protocol operations
  - `MessageHandler`: Room message handling
  - `RoomHandler`: Room state and membership management
  - `FederationHandler`: Server-to-server communication
  - `SyncHandler`: Client sync streams
  - `PresenceHandler`: User presence tracking

- **REST API** (`synapse/rest/`): HTTP endpoints divided into:
  - `client/`: Client-Server API endpoints
  - `admin/`: Admin API endpoints
  - `federation/`: Federation API endpoints
  - `media/`: Media repository endpoints

- **Storage** (`synapse/storage/`): Data access layer with multiple logical databases:
  - `main/`: Primary database for most data
  - `state/`: Room state storage (can be separate physical database)
  - `common/`: Schema shared across all databases

- **Application Layer** (`synapse/app/`): Different server applications
  - `homeserver.py`: Main monolithic homeserver
  - `generic_worker.py`: Generic worker for load distribution
  - `media_repository.py`: Dedicated media worker

### Key Infrastructure
- **Event System**: Matrix events flow through handlers → storage → federation
- **Notifier System**: Real-time notifications for client sync streams
- **Federation Layer**: Server-to-server communication using HTTP and EDUs
- **Authentication**: Multiple auth providers (password, SAML, OIDC, JWT)
- **Caching**: Multi-layer caching system for performance

### Rust Integration
- **Location**: `rust/src/` with ACL and push rule evaluation
- **Build**: Uses maturin to build Python extensions
- **Commands**: `cargo build`, `cargo clippy`, `cargo fmt`

### Configuration
- **Main config**: `homeserver.yaml` (generated from `docs/sample_config.yaml`)
- **Log config**: `log_config.yaml` (generated from `docs/sample_log_config.yaml`)
- **Database**: Supports SQLite (development) and PostgreSQL (production)

### Database Schema
- **Versioning**: Managed via `SCHEMA_VERSION` and `SCHEMA_COMPAT_VERSION`
- **Migrations**: Delta files in `synapse/storage/schema/*/delta/`
- **Background updates**: Long-running migrations processed asynchronously

### Worker Architecture
Synapse supports horizontal scaling via specialized workers:
- **Event persister**: Handles event persistence
- **Federation sender**: Manages outgoing federation
- **Synchrotron**: Handles client sync streams
- **Media repository**: Dedicated media handling

## Development Guidelines

### Code Style
- **Python**: Follows Black formatter and isort for imports
- **Rust**: Uses rustfmt and clippy
- **Type hints**: Required with mypy validation

### Testing Strategy
- **Unit tests**: Trial-based testing with SQLite/PostgreSQL
- **Integration tests**: Sytest for protocol compliance
- **Complement**: Black-box tests against homeserver implementation

### Database Changes
- **Backward compatibility**: Maintain 1-2 versions of compatibility
- **Schema versions**: Update `SCHEMA_VERSION` for code changes, `SCHEMA_COMPAT_VERSION` for breaking changes
- **Background updates**: Use for large table migrations

### Federation
- **Implementation**: Matrix federation protocol over HTTP
- **Security**: Server signing keys and event authentication
- **Reliability**: Transaction queues and retry logic