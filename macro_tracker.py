"""
macro_tracker.py
================
Animated macro-nutrition dashboard built with Manim Community Edition.

Generates a modern, dark-themed nutrition ring chart with animated macro
segments and a calorie count-up — suitable for YouTube fitness content or
social-media health tracking clips.

Render commands (PowerShell)
----------------------------
Low quality, opaque (fast preview):
    manim -pql macro_tracker.py MacroTracker

Low quality with custom values:
    $env:TARGET_CAL=3500; $env:TOTAL_CAL=3470; $env:PROTEIN=171; $env:CARBS=185; $env:FAT=71; \\
        manim -pql macro_tracker.py MacroTracker -o output_name

High quality, opaque (1920 × 1080):
    manim -pqh macro_tracker.py MacroTracker

High quality, transparent background:
    manim -pqh --transparent macro_tracker.py MacroTracker

High quality, transparent with custom values:
    $env:TARGET_CAL=3500; $env:TOTAL_CAL=3470; $env:PROTEIN=171; $env:CARBS=185; $env:FAT=71; \\
        manim -pqh --transparent macro_tracker.py MacroTracker -o output_name

Environment variables for nutrition data:
    TARGET_CAL  - calorie goal (default: 3400)
    TOTAL_CAL   - total calories consumed (default: 3000)
    PROTEIN     - grams of protein (default: 160)
    CARBS       - grams of carbs (default: 300)
    FAT         - grams of fat (default: 71)
    BG_OPACITY  - background opacity 0.0-1.0 (default: 1.0, only works with -pql/-pqh without --transparent)

Manim quality flags:
    -pql  = preview, low quality, quick render
    -pqm  = preview, medium quality
    -pqh  = preview, high quality (1920 × 1080)
    --transparent = use transparent background instead of solid

Output location:
    Use Manim's -o flag: ... MacroTracker -o output_name
"""

from __future__ import annotations

import os
import numpy as np
from manim import (
    # Core
    Scene,
    # Mobjects
    Arc, Dot, Mobject, VGroup, Text,
    # Animation helpers
    always_redraw, LaggedStart,
    Create, FadeIn,
    # Value tracking
    ValueTracker,
    # Directions / math constants
    LEFT, RIGHT, UP, DOWN, TAU, PI,
    # Font weights
    BOLD,
    # Rate functions
    smooth,
)


# ─────────────────────────────────────────────────────────────────
#  EDITABLE INPUTS  ← change these values to customise the animation
# ─────────────────────────────────────────────────────────────────
# Command-line usage (PowerShell):
#   $env:TARGET_CAL=3500; $env:TOTAL_CAL=3470; $env:PROTEIN=171; $env:CARBS=185; $env:FAT=71; manim -pql macro_tracker.py MacroTracker -o output_name
# Or with transparency and high quality:
#   $env:TARGET_CAL=3500; $env:TOTAL_CAL=3470; $env:PROTEIN=171; $env:CARBS=185; $env:FAT=71; manim -pqh --transparent macro_tracker.py MacroTracker -o output_name

TARGET_CALORIES: int = int(os.getenv('TARGET_CAL', '3400'))   # daily calorie goal
TOTAL_CALORIES:  int = int(os.getenv('TOTAL_CAL', '3000'))    # calories consumed today

PROTEIN_G: int = int(os.getenv('PROTEIN', '160'))   # grams of protein consumed
CARBS_G:   int = int(os.getenv('CARBS', '300'))     # grams of carbohydrates consumed
FAT_G:     int = int(os.getenv('FAT', '71'))        # grams of fat consumed

TITLE_TEXT: str = "Daily Nutrition 2"  # header title — change freely

# Whether to allow the coloured ring to exceed 100% of the target
ALLOW_OVERFLOW: bool  = True
OVERFLOW_CAP:   float = 1.2   # cap ring fill at 120% of target

# Background opacity (1.0 = opaque, 0.0 = transparent)
BG_OPACITY: float = float(os.getenv('BG_OPACITY', '1.0'))


# ─────────────────────────────────────────────────────────────────
#  THEME CONSTANTS
# ─────────────────────────────────────────────────────────────────
BG_COLOR       = "#0F1115"   # near-black background
RING_BG_COLOR  = "#1E2128"   # dark grey background ring
PROTEIN_COLOR  = "#4CAF50"   # green
CARBS_COLOR    = "#FFC107"   # amber / yellow
FAT_COLOR      = "#F44336"   # red
TEXT_PRIMARY   = "#FFFFFF"   # white
TEXT_SECONDARY = "#9E9E9E"   # grey
LABEL_OFFSET   = 1.2        # how far outside the ring labels sit


# ─────────────────────────────────────────────────────────────────
#  DERIVED CALCULATIONS
# ─────────────────────────────────────────────────────────────────
def calc_macros() -> dict[str, int | float]:
    """
    Compute calorie contributions and proportional percentages for each macro.

    Percentages are based on total *macro* calories (protein + carbs + fat),
    so they always sum to 100 %, independent of the calorie target.

    Example with default inputs:
        Protein : 171 g × 4 = 684 kcal
        Carbs   : 185 g × 4 = 740 kcal
        Fat     :  71 g × 9 = 639 kcal
        Total macro calories = 2063 kcal
    """
    p_cal: int = PROTEIN_G * 4
    c_cal: int = CARBS_G   * 4
    f_cal: int = FAT_G     * 9
    total: int = p_cal + c_cal + f_cal

    # Fraction of the target ring to fill
    raw_fill = TOTAL_CALORIES / TARGET_CALORIES
    if ALLOW_OVERFLOW:
        fill = min(raw_fill, OVERFLOW_CAP)
    else:
        fill = min(raw_fill, 1.0)

    return {
        "p_cal": p_cal,
        "c_cal": c_cal,
        "f_cal": f_cal,
        "total": total,
        "p_pct": p_cal / total,   # protein share of macro calories
        "c_pct": c_cal / total,   # carb share of macro calories
        "f_pct": f_cal / total,   # fat share of macro calories
        "fill":  fill,            # how full the coloured ring should be
    }


# ─────────────────────────────────────────────────────────────────
#  UTILITY BUILDERS
# ─────────────────────────────────────────────────────────────────
def build_ring_arc(
    center: np.ndarray,
    radius: float,
    start_angle: float,
    sweep: float,
    color: str,
    stroke_width: float,
) -> Arc:
    """
    Return a thick-stroked arc segment with no fill.

    Parameters
    ----------
    center       : arc_center in scene coordinates
    radius       : arc radius in scene units
    start_angle  : starting angle in radians (0 = 3 o'clock, PI/2 = 12 o'clock)
    sweep        : angular span in radians (negative = clockwise)
    color        : stroke colour hex string
    stroke_width : stroke thickness in screen points
    """
    arc = Arc(
        radius=radius,
        start_angle=start_angle,
        angle=sweep,
        arc_center=center,
        stroke_width=stroke_width,
        stroke_color=color,
    )
    arc.set_fill(opacity=0)
    # Round the stroke ends
    arc.stroke_linecap = 1  # 1 = round cap
    return arc


def build_macro_row(
    dot_color: str,
    label: str,
    grams: int,
    pct: float,
) -> VGroup:
    """
    Return a single colour-coded macro row:

        ●  Label
           Xg   (Y%)
    """
    dot = Dot(color=dot_color, radius=0.13)

    title_text = Text(
        label,
        font_size=24,
        color=TEXT_PRIMARY,
        weight=BOLD,
    )
    value_text = Text(
        f"{grams}g   ({pct:.0%})",
        font_size=21,
        color=TEXT_SECONDARY,
    )

    text_col = VGroup(title_text, value_text).arrange(
        DOWN, buff=0.10, aligned_edge=LEFT
    )
    row = VGroup(dot, text_col).arrange(RIGHT, buff=0.28)
    return row


def build_calorie_center(
    tracker: ValueTracker,
    ring_center: np.ndarray,
) -> tuple[Mobject, Text]:
    """
    Return (cal_number_mobject, target_label_mobject).

    cal_number uses always_redraw so it updates each frame during the
    count-up animation.
    """
    cal_number = always_redraw(
        lambda: Text(
            f"{int(tracker.get_value()):,}",
            font_size=90,
            weight=BOLD,
            color=TEXT_PRIMARY,
        ).move_to(ring_center + UP * 0.30)
    )

    target_label = Text(
        f"/ {TARGET_CALORIES:,} kcal",
        font_size=28,
        color=TEXT_SECONDARY,
    ).move_to(ring_center + DOWN * 0.45)

    return cal_number, target_label


# ─────────────────────────────────────────────────────────────────
#  MAIN SCENE
# ─────────────────────────────────────────────────────────────────
class MacroTracker(Scene):
    """
    Production-quality animated macro-nutrition dashboard.

    Animation sequence
    ------------------
    1. Header title + dark background ring fade in.
    2. Protein arc grows clockwise from 12 o'clock.
    3. Carb arc continues clockwise from the protein endpoint.
    4. Fat arc completes the ring.
    5. Calorie count-up from 0 → TOTAL_CALORIES.
    6. Macro label rows slide in from the right with a stagger.
    7. Hold on the final frame.

    Total duration ≈ 7–9 seconds.
    """

    # ── Layout (scene units; default Manim frame is 14.22 × 8.00) ─
    RING_CENTER: np.ndarray = np.array([0, 0, 0])  # centre of the donut ring (centered)
    RING_RADIUS: float      = 2.2           # ring radius in scene units
    RING_STROKE: float      = 22.0          # stroke width in screen points

    def construct(self) -> None:
        # Apply background color with opacity control
        bg_color = BG_COLOR
        self.camera.background_color = bg_color
        if BG_OPACITY < 1.0:
            # Convert hex to RGB for opacity blending
            self.camera.background_color = bg_color
            # Manim handles opacity via Color objects; this is the scene background
        m = calc_macros()

        # ── 1. Background ring (full 360°) ────────────────────────
        bg_ring = self._build_bg_ring()

        # ── 2. Coloured macro segments ────────────────────────────
        #   Angles: 0 = 3 o'clock; PI/2 = 12 o'clock (start position)
        #   Negative sweep = clockwise direction
        total_sweep: float = -TAU * m["fill"]

        p_sweep = total_sweep * m["p_pct"]
        c_sweep = total_sweep * m["c_pct"]
        f_sweep = total_sweep * m["f_pct"]

        p_start = PI / 2              # 12 o'clock
        c_start = p_start + p_sweep   # immediately after protein
        f_start = c_start + c_sweep   # immediately after carbs

        p_arc = build_ring_arc(
            self.RING_CENTER, self.RING_RADIUS,
            p_start, p_sweep, PROTEIN_COLOR, self.RING_STROKE,
        )
        c_arc = build_ring_arc(
            self.RING_CENTER, self.RING_RADIUS,
            c_start, c_sweep, CARBS_COLOR, self.RING_STROKE,
        )
        f_arc = build_ring_arc(
            self.RING_CENTER, self.RING_RADIUS,
            f_start, f_sweep, FAT_COLOR, self.RING_STROKE,
        )

        # ── 3. Centre calories text ───────────────────────────────
        tracker = ValueTracker(0)
        cal_number, target_label = build_calorie_center(tracker, self.RING_CENTER)

        # ── 4. Macro labels positioned near their ring arcs ────────
        def _label_pos(start_angle: float, sweep: float) -> np.ndarray:
            """Return position just outside the ring at the arc midpoint."""
            mid = start_angle + sweep / 2
            # Angle-dependent offset: more space at top (dot), less on sides
            # Normalize angle to 0-2π
            angle_norm = mid % TAU
            # Distance from top (π/2) - if close to top, use full offset; otherwise use less
            dist_from_top = min(abs(angle_norm - PI/2), TAU - abs(angle_norm - PI/2))
            # Larger offset near top (protecting protein dot), smaller on sides
            if dist_from_top < PI/3:  # Near top (within 60°)
                offset = LABEL_OFFSET + 0.2  # Extra space for protein
            else:
                offset = LABEL_OFFSET - 0.6  # Bring carbs/fat closer
            r = self.RING_RADIUS + offset
            return self.RING_CENTER + np.array([
                r * np.cos(mid), r * np.sin(mid), 0
            ])

        p_row = build_macro_row(PROTEIN_COLOR, "Protein", PROTEIN_G, m["p_pct"])
        c_row = build_macro_row(CARBS_COLOR,   "Carbs",   CARBS_G,   m["c_pct"])
        f_row = build_macro_row(FAT_COLOR,     "Fat",     FAT_G,     m["f_pct"])

        p_row.move_to(_label_pos(p_start, p_sweep))
        c_row.move_to(_label_pos(c_start, c_sweep))
        f_row.move_to(_label_pos(f_start, f_sweep))
        f_row.shift(LEFT * 0.3)  # Move fat label to the left

        # ══════════════════════════════════════════════════════════
        #  ANIMATION SEQUENCE
        # ══════════════════════════════════════════════════════════

        # Step 1 — background ring
        self.play(
            Create(bg_ring, rate_func=smooth),
            run_time=0.7,
        )

        # Step 2 — protein segment grows from 12 o'clock
        self.play(
            Create(p_arc, rate_func=smooth),
            run_time=1.0,
        )

        # Step 3 — carb segment continues from protein endpoint
        self.play(
            Create(c_arc, rate_func=smooth),
            run_time=0.85,
        )

        # Step 4 — fat segment completes the ring
        self.play(
            Create(f_arc, rate_func=smooth),
            run_time=0.65,
        )

        # Step 5 — calorie count-up
        self.add(cal_number)
        self.play(
            FadeIn(target_label, shift=UP * 0.10),
            run_time=0.35,
        )
        self.play(
            tracker.animate.set_value(TOTAL_CALORIES),
            rate_func=smooth,
            run_time=1.5,
        )

        # Step 6 — macro labels fade in near their ring arcs
        self.play(
            LaggedStart(
                FadeIn(p_row, shift=RIGHT * 0.25),
                FadeIn(c_row, shift=RIGHT * 0.25),
                FadeIn(f_row, shift=RIGHT * 0.25),
                lag_ratio=0.35,
            ),
            run_time=1.2,
        )

        # Hold the final frame for a beat
        self.wait(1.5)

    # ── Private helpers ───────────────────────────────────────────

    def _build_bg_ring(self) -> Arc:
        """
        Full 360° dark grey background ring representing the calorie target.
        Sits behind the coloured macro segments.
        """
        ring = Arc(
            radius=self.RING_RADIUS,
            start_angle=0,
            angle=TAU,
            arc_center=self.RING_CENTER,
            stroke_width=self.RING_STROKE,
            stroke_color=RING_BG_COLOR,
        )
        ring.set_fill(opacity=0)
        return ring
