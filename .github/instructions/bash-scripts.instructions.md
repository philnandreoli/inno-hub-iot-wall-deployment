---
applyTo: "{v1/**,v2/**}"
description: "Use when writing or modifying bash scripts for Azure IoT Operations provisioning and infrastructure setup."
---
# Bash Script Guidelines

## Structure

Every script must include:
1. Color variables at the top: `RED`, `YELLOW`, `GREEN`, `RESET` (ANSI escape codes)
2. A `usage()` function with `--help` flag support
3. Long-form `--kebab-case` argument parsing via `while/case/shift 2`
4. Section headers with colored `======` banner blocks

## Variables

- `UPPER_SNAKE_CASE` for all exported variables
- CLI args override env vars: `export VAR="${ARG_VAR:-${ENV_VAR:-default}}"`
- Azure resource names follow pattern: `EXP-MFG-AIO-${DATA_CENTER}-${COUNTRY}-RG`
- Sanitize resource names: `tr '[:upper:]' '[:lower:]' | sed 's/_/-/g'`
- Storage accounts: `tr -cd 'a-z0-9' | cut -c1-24`

## Azure CLI Patterns

- Login with service principal: `az login --service-principal`
- Always set subscription: `az account set --subscription`
- Add extensions before use: `az extension add --name ... --yes`
- Use `--output none` for commands where output isn't needed

## Error Handling

- Do not use `set -e` in provisioning scripts (v2 style)
- Print colored error/warning messages to guide the operator
- Validate required arguments exist before proceeding

## Naming Conventions

- Script files: `stepN-description.sh` (kebab-case description)
- Steps are numbered sequentially and meant to be run in order
