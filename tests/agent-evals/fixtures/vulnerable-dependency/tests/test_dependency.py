import unittest
from pathlib import Path


class DependencyTest(unittest.TestCase):
    def test_safe_pin(self):
        self.assertIn("safe-package==2.0", Path("requirements.txt").read_text(encoding="utf-8"))
