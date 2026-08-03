import unittest
from pathlib import Path


class UiTest(unittest.TestCase):
    def test_current_title(self):
        self.assertIn("Factory UI", Path("index.html").read_text(encoding="utf-8"))
