import unittest
from pathlib import Path


class RoadmapTest(unittest.TestCase):
    def test_roadmap_is_valid_after_repair(self):
        roadmap = Path("ROADMAP.md").read_text(encoding="utf-8")
        self.assertTrue(roadmap.startswith("# Roadmap"))
        self.assertNotIn("this is malformed", roadmap)
