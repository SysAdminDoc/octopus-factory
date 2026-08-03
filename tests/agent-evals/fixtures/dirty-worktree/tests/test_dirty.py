import unittest
from pathlib import Path


class DirtyTreeTest(unittest.TestCase):
    def test_tracked_file_survives(self):
        self.assertEqual(Path("tracked.txt").read_text(encoding="utf-8"), "tracked content\n")
