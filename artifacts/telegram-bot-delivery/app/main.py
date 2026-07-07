import asyncio
import logging
from typing import Any

from aiohttp import ClientSession, web

from config import load_settings


settings = load_settings()
logging.basicConfig(level=settings.log_level)
log = logging.getLogger("telegram-bot")


async def send_telegram_message(chat_id: int, text: str) -> None:
    url = f"https://api.telegram.org/bot{settings.bot_token}/sendMessage"
    payload = {"chat_id": chat_id, "text": text}
    async with ClientSession() as session:
        async with session.post(url, json=payload, timeout=15) as response:
            response.raise_for_status()


async def push_lead_to_crm(payload: dict[str, Any]) -> None:
    headers = {"Authorization": f"Bearer {settings.crm_api_key}"}
    async with ClientSession(headers=headers) as session:
        async with session.post(
            f"{settings.crm_base_url.rstrip('/')}/leads",
            json=payload,
            timeout=15,
        ) as response:
            response.raise_for_status()


async def healthz(_request: web.Request) -> web.Response:
    return web.json_response({"status": "ok"})


async def readyz(_request: web.Request) -> web.Response:
    return web.json_response({"ready": True, "webhook": settings.webhook_url})


async def webhook(request: web.Request) -> web.Response:
    update = await request.json()
    message = update.get("message", {})
    text = (message.get("text") or "").strip()
    chat = message.get("chat", {})
    chat_id = chat.get("id")

    if not chat_id:
        return web.json_response({"ok": True, "ignored": True})

    if text == "/start":
        await send_telegram_message(
            chat_id,
            "Привет. Я бот для первичной квалификации. Напишите имя и задачу.",
        )
        return web.json_response({"ok": True})

    if text:
        await push_lead_to_crm(
            {
                "source": "telegram",
                "chat_id": str(chat_id),
                "message": text,
            }
        )
        await send_telegram_message(chat_id, "Спасибо, запрос принят и отправлен в CRM.")

    return web.json_response({"ok": True})


async def setup_webhook() -> None:
    if not settings.bot_token:
        log.warning("BOT_TOKEN is empty; webhook setup skipped")
        return

    url = f"https://api.telegram.org/bot{settings.bot_token}/setWebhook"
    payload = {"url": settings.webhook_url}
    async with ClientSession() as session:
        async with session.post(url, json=payload, timeout=15) as response:
            response.raise_for_status()
            log.info("Webhook configured: %s", settings.webhook_url)


async def on_startup(_app: web.Application) -> None:
    await setup_webhook()


def build_app() -> web.Application:
    app = web.Application()
    app.router.add_get("/healthz", healthz)
    app.router.add_get("/readyz", readyz)
    app.router.add_post(settings.webhook_path, webhook)
    app.on_startup.append(on_startup)
    return app


if __name__ == "__main__":
    web.run_app(build_app(), host="0.0.0.0", port=8080)
