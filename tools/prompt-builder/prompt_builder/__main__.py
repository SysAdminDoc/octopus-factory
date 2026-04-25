"""Entry point: `python -m prompt_builder`.

PyInstaller fork-bomb guards (per global CLAUDE.md):
  1. multiprocessing.freeze_support() is the first executable statement.
  2. Bootstrap / runtime work short-circuits when frozen (sys.frozen).
"""

from __future__ import annotations

import multiprocessing
multiprocessing.freeze_support()

import sys


def _is_frozen() -> bool:
    return getattr(sys, "frozen", False) or hasattr(sys, "_MEIPASS")


def main() -> int:
    # Imports below the freeze_support call so PyInstaller workers don't
    # transitively import the whole GUI just to reach freeze_support().
    from PyQt6.QtWidgets import QApplication

    from .theme import stylesheet
    from .window import PromptBuilderWindow

    app = QApplication(sys.argv)
    app.setApplicationName("Octopus Factory Prompt Builder")
    app.setApplicationDisplayName("Octopus Factory — Prompt Builder")
    app.setOrganizationName("octopus-factory")
    app.setStyleSheet(stylesheet())

    window = PromptBuilderWindow()
    window.show()
    return app.exec()


if __name__ == "__main__":
    raise SystemExit(main())
