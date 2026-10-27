import unittest

from app.config import Settings
from app.vpn_service import build_ws_profile, profile_qr_png


class ProfileTest(unittest.TestCase):
    def test_ws_profile_is_tls_and_has_encoded_path(self):
        settings = Settings("token", frozenset({1}), -1001, "vpn.example.test", "/vpn-ws")
        profile = build_ws_profile(settings, "00000000-0000-4000-8000-000000000000")
        self.assertIn("security=tls", profile)
        self.assertIn("type=ws", profile)
        self.assertIn("path=%2Fvpn-ws", profile)

    def test_happ_qr_is_png(self):
        image = profile_qr_png("vless://test@example.test:443?security=tls#VPN")
        self.assertEqual(image.read(8), b"\x89PNG\r\n\x1a\n")
