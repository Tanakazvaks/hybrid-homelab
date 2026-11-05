import unittest

from app import build_response


class AppTests(unittest.TestCase):
    def test_health_endpoint(self):
        self.assertEqual(build_response("/health"), (200, {"status": "ok"}))

    def test_root_reports_version_and_pod(self):
        code, body = build_response("/")
        self.assertEqual(code, 200)
        self.assertIn("version", body)
        self.assertIn("pod", body)

    def test_unknown_path_returns_404(self):
        self.assertEqual(build_response("/nope")[0], 404)


if __name__ == "__main__":
    unittest.main()
