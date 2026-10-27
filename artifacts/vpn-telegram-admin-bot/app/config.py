from __future__ import annotations

import os
from dataclasses import dataclass


@dataclass(frozen=True)
class Settings:
    bot_token: str
    admin_ids: frozenset[int]
    channel_id: int
    public_host: str
    ws_path: str

    @classmethod
    def from_env(cls) -> "Settings":
        token = os.environ["BOT_TOKEN"].strip()
        admins = frozenset(int(value) for value in os.environ["ADMIN_IDS"].split(",") if value)
        if not token or not admins:
            raise RuntimeError("BOT_TOKEN и ADMIN_IDS обязательны")
        return cls(
            bot_token=token,
            admin_ids=admins,
            channel_id=int(os.environ["CHANNEL_ID"]),
            public_host=os.environ["VPN_PUBLIC_HOST"].strip(),
            ws_path=os.environ.get("VPN_WS_PATH", "/vpn-ws"),
        )
