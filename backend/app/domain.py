from __future__ import annotations

from dataclasses import dataclass
from math import ceil, floor, isfinite


def attendance_percentage(present: int, absent: int) -> float:
    if present < 0 or absent < 0:
        raise ValueError("attendance counts cannot be negative")
    total = present + absent
    if total == 0:
        return 0.0
    return round((present / total) * 100, 2)


@dataclass(frozen=True)
class Forecast:
    current_percentage: float
    classes_to_attend_to_reach_threshold: int
    misses_available_before_below_threshold: int


def forecast_attendance(present: int, absent: int, threshold_percent: float) -> Forecast:
    if present < 0 or absent < 0:
        raise ValueError("attendance counts cannot be negative")
    if threshold_percent < 0 or threshold_percent > 100:
        raise ValueError("threshold must be between 0 and 100")

    total = present + absent
    current = attendance_percentage(present, absent)
    threshold = threshold_percent / 100

    if threshold == 0:
        needed = 0
    elif threshold == 1:
        needed = 0 if absent == 0 else -1
    elif total == 0:
        needed = 1
    elif present / total >= threshold:
        needed = 0
    else:
        needed_float = (threshold * total - present) / (1 - threshold)
        needed = ceil(needed_float)

    if threshold == 0:
        misses = 10**9
    elif total == 0:
        misses = 0
    else:
        misses_float = (present / threshold) - total
        misses = max(0, floor(misses_float))

    if not isfinite(misses):
        misses = 10**9

    return Forecast(
        current_percentage=current,
        classes_to_attend_to_reach_threshold=needed,
        misses_available_before_below_threshold=misses,
    )

