import unittest

from cli import add


class CliTest(unittest.TestCase):
    def test_add(self):
        self.assertEqual(add(2, 3), 5)
