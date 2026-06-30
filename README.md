# Nutrition-Graph-Manim

Animated macro-nutrition dashboard built with Manim Community Edition. Generates a dark-themed ring chart with animated macro segments and a calorie count-up.

---

## Prerequisites

```powershell
pip install manim
```

---

## Quick Start — render.ps1 (recommended)

Use `render.ps1` to render from **any directory** without navigating to the project folder.

### Parameters

| Parameter      | Description                             | Default        |
| -------------- | --------------------------------------- | -------------- |
| `-TargetCal`   | Daily calorie goal                      | `3400`         |
| `-TotalCal`    | Total calories consumed                 | `3000`         |
| `-Protein`     | Grams of protein                        | `160`          |
| `-Carbs`       | Grams of carbohydrates                  | `300`          |
| `-Fat`         | Grams of fat                            | `71`           |
| `-Output`      | Output file name                        | `macro_output` |
| `-Quality`     | `l` / `m` / `h` (low / medium / high)   | `h`            |
| `-Transparent` | Switch — enables transparent background | off            |

### Examples

**Default values, high quality:**

```powershell
& "C:\Users\Utente\Documents\GitHub\timelapse-scripts\Nutrition-Graph-Manim\render.ps1"
```

**Custom values, high quality:**

```powershell
& "C:\Users\Utente\Documents\GitHub\timelapse-scripts\Nutrition-Graph-Manim\render.ps1" -TargetCal 3500 -TotalCal 3470 -Protein 171 -Carbs 185 -Fat 71 -Output my_video
```

**Custom values, low quality (fast preview):**

```powershell
& "C:\Users\Utente\Documents\GitHub\timelapse-scripts\Nutrition-Graph-Manim\render.ps1" -TargetCal 3500 -TotalCal 3470 -Protein 171 -Carbs 185 -Fat 71 -Quality l
```

**High quality + transparent background:**

```powershell
& "C:\Users\Utente\Documents\GitHub\timelapse-scripts\Nutrition-Graph-Manim\render.ps1" -TargetCal 3500 -TotalCal 3470 -Protein 171 -Carbs 185 -Fat 71 -Output my_video -Transparent
```

> **Note:** If PowerShell blocks the script, run this once:
> 
> ```powershell
> Set-ExecutionPolicy -Scope CurrentUser RemoteSigned
> ```

---

## Manual Command (from project directory)

```powershell
$env:TARGET_CAL=3500; $env:TOTAL_CAL=3470; $env:PROTEIN=171; $env:CARBS=185; $env:FAT=71; manim -pqh macro_tracker.py MacroTracker -o my_video
```

### Environment Variables

| Variable     | Description                     | Default |
| ------------ | ------------------------------- | ------- |
| `TARGET_CAL` | Daily calorie goal              | `3400`  |
| `TOTAL_CAL`  | Total calories consumed         | `3000`  |
| `PROTEIN`    | Grams of protein consumed       | `160`   |
| `CARBS`      | Grams of carbohydrates consumed | `300`   |
| `FAT`        | Grams of fat consumed           | `71`    |

### Quality Flags

| Flag   | Quality | Resolution        | Speed                     |
| ------ | ------- | ----------------- | ------------------------- |
| `-pql` | Low     | 480p              | Fast (use for previewing) |
| `-pqm` | Medium  | 720p              | Medium                    |
| `-pqh` | High    | 1080p (1920×1080) | Slow                      |

---

## Output Location

By default, Manim saves videos to:

```
media/videos/macro_tracker/1080p60/
```

Use the `-o` flag (or `-Output` in render.ps1) to name your output file.

---

## Transparent Background Notes

The `--transparent` flag outputs a `.mov` file with an alpha channel.

- ❌ **Does not work** in Windows Photos or Windows Media Player
- ⚠️ **VLC** will show incorrect colors (known codec issue)
- ✅ **Works correctly** in:
  - DaVinci Resolve (free)
  - Adobe Premiere Pro / After Effects
  - Vegas Pro

For a more compatible transparent format, use WebM manually:

```powershell
$env:TARGET_CAL=3500; $env:TOTAL_CAL=3470; $env:PROTEIN=171; $env:CARBS=185; $env:FAT=71; manim -pqh --transparent --format webm macro_tracker.py MacroTracker -o my_video
```


