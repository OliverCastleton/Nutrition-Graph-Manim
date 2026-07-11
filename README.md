# Nutrition Graph Manim

Create nutrition and sleep animations with Manim using clean PowerShell wrappers.

This repository is now set up for GitHub publishing:
- No hardcoded machine paths
- No forced video auto-open on render
- Local secrets kept out of git
- Consistent project-relative output folders

## Project Structure

- `render.ps1`: render one nutrition animation
- `render-garmin-sleep.ps1`: render one sleep animation
- `render-inputs-batch.ps1`: render nutrition + sleep from `Inputs/`
- `render-foodlog-batch.ps1`: nutrition CSV batch
- `render-sleep-csv-batch.ps1`: sleep CSV batch
- `render-fatsecret-range.ps1`: date range render from CSV
- `setup.ps1`: create local Python environment and install dependencies
- `.env.example`: template for local credentials
- `scripts/common.ps1`: shared helper functions used by all wrappers

Local-only folders (ignored by git):
- `outputs/`
- `logs/`
- `secrets/`
- `.venv/`

## Quick Setup

Run from repository root:

```powershell
.\setup.ps1
```

Then activate environment:

```powershell
.\.venv\Scripts\Activate.ps1
```

If script execution is blocked:

```powershell
Set-ExecutionPolicy -Scope CurrentUser RemoteSigned
```

## Configuration

You can ignore `.env.example` for now. No API credentials are required.

## Rendering Behavior

All wrappers use `manim -q...` (not `-pq...`), so generated videos do not auto-open.

All renders go under:

```text
outputs/manim/
```

## Common Commands

Single nutrition render:

```powershell
.\render.ps1 -TargetCal 3500 -TotalCal 3470 -Protein 171 -Carbs 185 -Fat 71 -Output nutrition_demo -Quality h -Transparent
```

Single sleep render (manual values):

```powershell
.\render-garmin-sleep.ps1 -Date 2026-07-11 -TotalSleepMin 445 -DeepMin 102 -LightMin 246 -RemMin 97 -AwakeMin 18 -Output sleep_demo -Quality h -Transparent
```

Batch render from both CSV files:

```powershell
.\render-inputs-batch.ps1 -Quality h -Transparent
```

Dry run parsing only:

```powershell
.\render-inputs-batch.ps1 -DryRun
```

## Inputs

- `Inputs/FoodLog.CSV`
- `Inputs/Sleep.csv`

Keep these files in place or override paths with script parameters.


