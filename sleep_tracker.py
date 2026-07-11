"""
sleep_tracker.py
===============
Animated sleep dashboard built with Manim Community Edition.

Creates a ring chart similar to macro_tracker.py but for sleep stages.

Environment variables:
    TARGET_SLEEP_MIN - sleep goal in minutes (default: 480)
    TOTAL_SLEEP_MIN  - total sleep in minutes (default: 430)
    DEEP_MIN         - deep sleep minutes (default: 95)
    LIGHT_MIN        - light sleep minutes (default: 240)
    REM_MIN          - REM sleep minutes (default: 95)
    AWAKE_MIN        - awake minutes (default: 25)
    SLEEP_TITLE      - title text (default: "Sleep Recovery")
    SLEEP_DATE       - subtitle date text (default: "")
"""

from __future__ import annotations

import os
import numpy as np
from manim import (
    Scene,
    Arc, Mobject, Text,
    always_redraw,
    Create, FadeIn,
    ValueTracker,
    UP, DOWN, TAU, PI,
    BOLD,
    smooth,
)

TARGET_SLEEP_MIN: int = int(os.getenv("TARGET_SLEEP_MIN", "480"))
TOTAL_SLEEP_MIN: int = int(os.getenv("TOTAL_SLEEP_MIN", "430"))

DEEP_MIN: int = int(os.getenv("DEEP_MIN", "95"))
LIGHT_MIN: int = int(os.getenv("LIGHT_MIN", "240"))
REM_MIN: int = int(os.getenv("REM_MIN", "95"))
AWAKE_MIN: int = int(os.getenv("AWAKE_MIN", "25"))

TITLE_TEXT: str = os.getenv("SLEEP_TITLE", "Sleep Recovery")
ALLOW_OVERFLOW: bool = True
OVERFLOW_CAP: float = 1.2

BG_COLOR = "#0D1117"
RING_BG_COLOR = "#1E2530"
DEEP_COLOR = "#1B66FF"
LIGHT_COLOR = "#4EC3FF"
REM_COLOR = "#9B7BFF"
TEXT_PRIMARY = "#FFFFFF"
TEXT_SECONDARY = "#A8B2C0"

def calc_sleep() -> dict[str, int | float]:
    stage_total = max(DEEP_MIN + LIGHT_MIN + REM_MIN, 1)
    raw_fill = TOTAL_SLEEP_MIN / max(TARGET_SLEEP_MIN, 1)
    fill = min(raw_fill, OVERFLOW_CAP) if ALLOW_OVERFLOW else min(raw_fill, 1.0)

    return {
        "deep_pct": DEEP_MIN / stage_total,
        "light_pct": LIGHT_MIN / stage_total,
        "rem_pct": REM_MIN / stage_total,
        "fill": fill,
        "sleep_eff": (TOTAL_SLEEP_MIN / max(TOTAL_SLEEP_MIN + AWAKE_MIN, 1)) * 100.0,
    }


def build_ring_arc(
    center: np.ndarray,
    radius: float,
    start_angle: float,
    sweep: float,
    color: str,
    stroke_width: float,
) -> Arc:
    arc = Arc(
        radius=radius,
        start_angle=start_angle,
        angle=sweep,
        arc_center=center,
        stroke_width=stroke_width,
        stroke_color=color,
    )
    arc.set_fill(opacity=0)
    arc.stroke_linecap = 1
    return arc


def format_minutes_as_hm(minutes: int) -> str:
    hours = max(minutes, 0) // 60
    mins = max(minutes, 0) % 60
    return f"{hours}h {mins:02d}m"


def build_center_text(tracker: ValueTracker, ring_center: np.ndarray) -> tuple[Mobject, Text]:
    sleep_number = always_redraw(
        lambda: Text(
            format_minutes_as_hm(int(tracker.get_value())),
            font_size=70,
            weight=BOLD,
            color=TEXT_PRIMARY,
        ).move_to(ring_center + UP * 0.22)
    )

    goal = Text(
        f"/ {format_minutes_as_hm(TARGET_SLEEP_MIN)}",
        font_size=24,
        color=TEXT_SECONDARY,
    ).move_to(ring_center + DOWN * 0.40)

    return sleep_number, goal


class SleepTracker(Scene):
    RING_CENTER: np.ndarray = np.array([0, 0, 0])
    RING_RADIUS: float = 2.2
    RING_STROKE: float = 22.0

    def construct(self) -> None:
        self.camera.background_color = BG_COLOR
        s = calc_sleep()

        title = Text(TITLE_TEXT, font_size=42, weight=BOLD, color=TEXT_PRIMARY)
        title.to_edge(UP).shift(DOWN * 0.35)
        self.play(FadeIn(title, shift=DOWN * 0.12), run_time=0.45)

        bg_ring = Arc(
            radius=self.RING_RADIUS,
            start_angle=0,
            angle=TAU,
            arc_center=self.RING_CENTER,
            stroke_width=self.RING_STROKE,
            stroke_color=RING_BG_COLOR,
        )
        bg_ring.set_fill(opacity=0)

        total_sweep = -TAU * s["fill"]

        deep_sweep = total_sweep * s["deep_pct"]
        light_sweep = total_sweep * s["light_pct"]
        rem_sweep = total_sweep * s["rem_pct"]

        deep_start = PI / 2
        light_start = deep_start + deep_sweep
        rem_start = light_start + light_sweep

        deep_arc = build_ring_arc(self.RING_CENTER, self.RING_RADIUS, deep_start, deep_sweep, DEEP_COLOR, self.RING_STROKE)
        light_arc = build_ring_arc(self.RING_CENTER, self.RING_RADIUS, light_start, light_sweep, LIGHT_COLOR, self.RING_STROKE)
        rem_arc = build_ring_arc(self.RING_CENTER, self.RING_RADIUS, rem_start, rem_sweep, REM_COLOR, self.RING_STROKE)

        tracker = ValueTracker(0)
        sleep_number, goal_text = build_center_text(tracker, self.RING_CENTER)

        efficiency = Text(
            f"Awake {AWAKE_MIN}m   Sleep efficiency {s['sleep_eff']:.0f}%",
            font_size=20,
            color=TEXT_SECONDARY,
        ).to_edge(DOWN).shift(UP * 0.35)

        self.play(Create(bg_ring, rate_func=smooth), run_time=0.7)
        self.play(Create(deep_arc, rate_func=smooth), run_time=0.9)
        self.play(Create(light_arc, rate_func=smooth), run_time=0.85)
        self.play(Create(rem_arc, rate_func=smooth), run_time=0.75)

        self.add(sleep_number)
        self.play(FadeIn(goal_text, shift=UP * 0.08), run_time=0.3)
        self.play(tracker.animate.set_value(TOTAL_SLEEP_MIN), rate_func=smooth, run_time=1.5)

        self.play(FadeIn(efficiency, shift=UP * 0.08), run_time=0.35)
        self.wait(1.4)
