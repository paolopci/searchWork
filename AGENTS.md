# Repository Guidelines

## Project Structure & Module Organization

This repository contains a small PowerShell utility for assisted company research from LinkedIn profile searches. The main entry point is `Search-LinkedInCompanies.ps1`. Runtime configuration lives in `Data/profile-skills.json`, which defines the profile, skills, search locale, modes, and generated query terms. `Output/` is for local generated files such as `search-queries.csv`, `state.json`, and `LinkedInCompanyTargets.xlsx`; it is intentionally ignored except for `Output/.gitkeep`. `README.md` and `Leggimi.txt` provide usage notes in English-style Markdown and Italian plain text respectively.

## Build, Test, and Development Commands

- `.\Search-LinkedInCompanies.ps1 -NoBrowser -ListQueries`: generates and lists search queries without opening a browser; also updates `Output/search-queries.csv`.
- `.\Search-LinkedInCompanies.ps1 -NoBrowser`: runs the workflow without automatic browser launch.
- `.\Search-LinkedInCompanies.ps1`: runs the normal interactive workflow and opens searches in the default browser.
- `.\Search-LinkedInCompanies.ps1 -NoBrowser -PersonName "Name" -ProfileUrl "https://www.linkedin.com/in/..." -CompanyName "Company"`: adds a result directly from the command line.

Use Windows PowerShell or PowerShell 7+. No package install step is required.

## Coding Style & Naming Conventions

Use idiomatic PowerShell with `Set-StrictMode -Version Latest` and `$ErrorActionPreference = 'Stop'`. Keep functions verb-noun named, for example `Normalize-Website`, `Read-State`, and `Join-UniqueValues`. Use four-space indentation, PascalCase parameter names, and clear local variable names such as `$OutputDir` and `$WorkbookPath`. Prefer structured objects and JSON conversion over manual string parsing where practical.

## Testing Guidelines

There is no automated test suite yet. Before submitting changes, run `.\Search-LinkedInCompanies.ps1 -NoBrowser -ListQueries` to validate configuration parsing and query generation. For workflow changes, run `.\Search-LinkedInCompanies.ps1 -NoBrowser` and verify that output files are created under `Output/` without committing generated personal or job-search data.

## Commit & Pull Request Guidelines

Existing commits use short imperative summaries such as `Clarify query CSV reset commands` and `Add PowerShell usage guide`. Keep commits focused and descriptive. Pull requests should explain the behavior change, list manual validation commands, and call out any change to generated output formats, `.gitignore`, or `Data/profile-skills.json`. Include screenshots only when the change affects generated spreadsheets or user-facing documentation.

## Security & Data Handling

Do not add scraping, login automation, or LinkedIn credential handling. Treat `Output/` contents as private because they may contain people, companies, notes, and job-search state.
