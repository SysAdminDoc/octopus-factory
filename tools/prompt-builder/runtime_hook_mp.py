"""PyInstaller runtime hook — fork-bomb guard belt-and-braces.

Fires before any user code in frozen workers. Combined with the same
freeze_support() call at the top of prompt_builder/__main__.py, this
prevents PyInstaller's Windows multiprocessing fork-bomb where workers
re-spawn the GUI.

See ~/.claude/CLAUDE.md "PyInstaller fork-bomb — Windows" section.
"""

import multiprocessing

multiprocessing.freeze_support()
