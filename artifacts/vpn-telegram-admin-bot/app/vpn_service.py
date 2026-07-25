from __future__ import annotations

from io import BytesIO
from urllib.parse import quote
from uuid import uuid4

import qrcode

from .config import Settings


def create_client_id() -> str:
    """UUID создаётся только при выдаче профиля, никогда не логируется."""
    return str(uuid4())


def build_ws_profile(settings: Settings, client_id: str, name: str = "Личный VPN") -> str:
    """Профиль выдаётся только в личном чате, а не попадает в audit log."""
    return (
        f"vless://{client_id}@{settings.public_host}:443?encryption=none&security=tls"
        f"&sni={settings.public_host}&type=ws&host={settings.public_host}"
        f"&path={quote(settings.ws_path, safe='')}#{quote(name, safe='')}"
    )


def profile_qr_png(profile: str) -> BytesIO:
    """QR создаётся в памяти и отправляется только в приватный чат."""
    code = qrcode.QRCode(error_correction=qrcode.constants.ERROR_CORRECT_M, box_size=10, border=4)
    code.add_data(profile)
    code.make(fit=True)
    image = code.make_image(fill_color="black", back_color="white")
    result = BytesIO()
    image.save(result, format="PNG")
    result.name = "vpn-happ-qr.png"
    result.seek(0)
    return result
