"""Shared matchers for the Harmony product contract gates.

Kept import-side-effect free so the contract script and its unit tests can
load it from any working directory.
"""
import re

# The third parameter is restoreCheckpoint, not the periodic-save preference.
# Disabling automatic saves must still restore the user's persisted head and
# retain manual history; only the periodic running-time interval becomes zero.
RUN_GAME_OPEN_RE = re.compile(
    r"this\.play\.open\s*\(\s*context\s*,\s*this\.locator\s*,\s*true\s*,?\s*\)"
)
AUTOSAVE_INTERVAL_RE = re.compile(
    r"if\s*\(\s*!\s*this\.autosaveEnabled\s*\)\s*\{?\s*"
    r"this\.play\.history\.intervalMs\s*=\s*0\s*;"
)


def run_game_forwards_locator_and_autosave(start_body):
    return (RUN_GAME_OPEN_RE.search(start_body) is not None and
            AUTOSAVE_INTERVAL_RE.search(start_body) is not None)
