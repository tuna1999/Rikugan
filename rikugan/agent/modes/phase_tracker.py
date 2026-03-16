"""Generic phase tracker for resumable agent modes.

Any multi-phase mode (research, exploration, etc.) can use ``ModePhaseTracker``
to persist the current phase in ``session.metadata``.  On cancel + resume, the
tracker tells the mode which phases to skip.

Usage::

    tracker = ModePhaseTracker(loop, phases=["explore", "document", "index"])

    if tracker.should_run("explore"):
        tracker.enter("explore")
        yield from _run_explore(...)

    if tracker.should_run("document"):
        tracker.enter("document")
        yield from _run_document(...)

    tracker.enter("index")
    _generate_index(...)

    tracker.complete()
"""

from __future__ import annotations

from typing import TYPE_CHECKING

from ...core.logging import log_info

if TYPE_CHECKING:
    from ..loop import AgentLoop


class ModePhaseTracker:
    """Track and persist the active phase of a multi-phase mode.

    Parameters
    ----------
    loop:
        The ``AgentLoop`` instance (provides access to ``session.metadata``).
    phases:
        Ordered list of phase names.  The order determines which phases are
        skipped on resume — the interrupted phase and all phases before it
        are skipped (their partial results are in the conversation history).
    """

    def __init__(self, loop: AgentLoop, phases: list[str]) -> None:
        self._loop = loop
        self._phases = phases
        self._phase_set = set(phases)
        self._resume_phase = loop.session.metadata.get("mode_phase", "")
        if self._resume_phase and self._resume_phase not in self._phase_set:
            # Unknown phase (stale metadata?) — ignore and start fresh.
            self._resume_phase = ""
        if self._resume_phase:
            log_info(f"ModePhaseTracker: resuming at phase {self._resume_phase!r}")

    @property
    def resume_phase(self) -> str:
        """The phase to resume from, or ``""`` for a fresh start."""
        return self._resume_phase

    @property
    def is_resuming(self) -> bool:
        """``True`` if the mode is resuming from a previous cancel."""
        return self._resume_phase != ""

    def should_run(self, phase: str) -> bool:
        """Return ``True`` if *phase* should execute.

        The interrupted phase and all phases before it are skipped — they
        already ran (partially) and their results are in the conversation
        history.  Execution resumes at the *next* phase.
        """
        if not self._resume_phase:
            return True  # fresh start — run everything
        try:
            resume_idx = self._phases.index(self._resume_phase)
            phase_idx = self._phases.index(phase)
        except ValueError:
            return True  # unknown phase — run it to be safe
        return phase_idx > resume_idx

    def enter(self, phase: str) -> None:
        """Mark *phase* as the currently active phase.

        Persists to ``session.metadata["mode_phase"]`` so that on cancel
        the mode can resume from this point.
        """
        self._loop.session.metadata["mode_phase"] = phase

    def complete(self) -> None:
        """Clear persisted phase — the mode completed normally."""
        self._loop.session.metadata.pop("mode_phase", None)
