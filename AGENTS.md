## Cursor Cloud specific instructions

### Repository overview

This repository is a **collection of SQL queries and Google Apps Scripts** for business analytics in an on-demand home-services company. It is **not** a runnable application.

- **`main` branch**: Contains a single file `QUERIES` (placeholder text).
- **Feature branches**: ~75+ branches, each containing SQL query files (`.sql` or inline in `QUERIES`) or Google Apps Script files (`.gs`).
- SQL queries target a **Snowflake-compatible data warehouse** (uses `DATE_TRUNC`, `ILIKE`, `DAYOFWEEK`, etc.) with tables like `provider__daily__facts`, `REQUEST__HOURLY__FACTS`.
- `.gs` files are Google Apps Scripts meant to run inside Google Sheets (data sync between sheets).

### Development environment

- **No dependencies to install** — no `package.json`, `requirements.txt`, `Makefile`, `Dockerfile`, or any dependency manifest.
- **No build step, no lint, no tests** — there is no CI/CD, test framework, or linter configured.
- **No local services to run** — SQL queries are executed against an external data warehouse; Apps Scripts run in Google Sheets.

### Working with this repo

- To review or edit SQL, check out the relevant feature branch (e.g., `git checkout remotes/origin/cursor/complex-business-sql-queries-d258`).
- SQL files can be validated for syntax using an external SQL linter (e.g., `sqlfluff`) if needed, but none is configured in-repo.
- Google Apps Script files (`.gs`) can be linted with a JS linter, but none is configured.
