"""Sanitized example: Russian UI, long polling and an explicit admin boundary."""
from __future__ import annotations

import asyncio
import json
from io import BytesIO

from telegram import ReplyKeyboardMarkup, Update
from telegram.ext import Application, CommandHandler, ContextTypes, MessageHandler, filters

from .config import Settings
from .vpn_service import build_ws_profile, create_client_id, profile_qr_png

USER_MENU = ReplyKeyboardMarkup(
    [
        ["Активировать VPN", "Мой доступ"],
        ["Инструкция: телефон", "Инструкция: ПК"],
        ["Обход VPN для VK и Госуслуг", "Помощь"],
    ],
    resize_keyboard=True,
)
ADMIN_MENU = ReplyKeyboardMarkup([["Статус сервера", "Клиенты VPN"], ["Журнал действий"]], resize_keyboard=True)


def is_admin(update: Update, settings: Settings) -> bool:
    return bool(update.effective_user and update.effective_user.id in settings.admin_ids)


async def helper_status() -> dict:
    """Фиксированная команда; пользователь не передаёт shell-аргументы."""
    process = await asyncio.create_subprocess_exec(
        "/usr/bin/sudo", "-n", "/usr/local/sbin/vpn-bot-helper", "status",
        stdout=asyncio.subprocess.PIPE, stderr=asyncio.subprocess.DEVNULL,
    )
    stdout, _ = await asyncio.wait_for(process.communicate(), timeout=15)
    if process.returncode:
        raise RuntimeError("status helper failed")
    return json.loads(stdout)["data"]


async def start(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    settings: Settings = context.application.bot_data["settings"]
    menu = ADMIN_MENU if is_admin(update, settings) else USER_MENU
    await update.effective_message.reply_text("Добро пожаловать в личный VPN-бот.", reply_markup=menu)


async def status(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    settings: Settings = context.application.bot_data["settings"]
    if not is_admin(update, settings):
        await update.effective_message.reply_text("Эта функция доступна только администратору.")
        return
    data = await helper_status()
    await update.effective_message.reply_text(
        f"Статус сервера\nCPU: {data['load']}\nRAM: {data['memory_available_mib']} MiB\n"
        f"Диск: {data['disk_free_gib']} GiB\nnginx: {data['nginx']}\nXray: {data['xray']}"
    )


async def demo_profile(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    """В production здесь: approval check -> SQLite -> root helper -> private response."""
    settings: Settings = context.application.bot_data["settings"]
    profile = build_ws_profile(settings, create_client_id())
    await update.effective_message.reply_text(
        f"Демонстрационный профиль:\n{profile}\n\nНе пересылайте профиль другим людям.",
        protect_content=True,
    )


async def phone_instruction(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    """Демонстрирует безопасную выдачу VLESS-ссылки для Happ в личном чате."""
    settings: Settings = context.application.bot_data["settings"]
    profile = build_ws_profile(settings, create_client_id())
    await update.effective_message.reply_text(
        "Телефон — Happ\n\n"
        "1. В Happ нажмите «+» и выберите импорт/сканирование QR-кода.\n"
        "2. Отсканируйте QR из следующего сообщения и подключитесь.\n"
        "3. Если сканирование недоступно, используйте резервную VLESS-ссылку.\n\n"
        "В рабочем варианте ссылка выдаётся только после одобрения и только владельцу профиля."
    )
    await update.effective_message.reply_photo(profile_qr_png(profile), protect_content=True)
    await update.effective_message.reply_text(profile, protect_content=True)


async def pc_instruction(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    """Демонстрирует импорт текстового VLESS-ключа в AmneziaVPN на ПК."""
    settings: Settings = context.application.bot_data["settings"]
    profile = build_ws_profile(settings, create_client_id())
    await update.effective_message.reply_text(
        "ПК — AmneziaVPN\n\n"
        "Выберите добавление по текстовому ключу и вставьте VLESS-ссылку. "
        "Для переноса между устройствами бот может выдать ту же строку в .txt-файле."
    )
    profile_file = BytesIO(profile.encode("utf-8"))
    profile_file.name = "vpn-vless-key.txt"
    await update.effective_message.reply_document(profile_file, protect_content=True)


async def bypass_instruction(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    await update.effective_message.reply_text(
        "Обход VPN для Госуслуг и VK\n\n"
        "В AmneziaVPN на Windows добавьте соответствующие приложения в исключения раздельного туннелирования. "
        "Для сайтов в браузере лучше использовать отдельный браузер без VPN: исключение приложения не разделяет вкладки.\n\n"
        "У Happ правила маршрутизации зависят от версии клиента, поэтому рабочий бот не применяет их автоматически."
    )


async def help_command(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    await update.effective_message.reply_text("Используйте кнопки выдачи профиля, инструкций для устройств и настройки обхода VPN.")


async def menu_text(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    text = update.effective_message.text if update.effective_message else ""
    handlers = {
        "Активировать VPN": demo_profile,
        "Мой доступ": demo_profile,
        "Инструкция: телефон": phone_instruction,
        "Инструкция: ПК": pc_instruction,
        "Обход VPN для VK и Госуслуг": bypass_instruction,
        "Помощь": help_command,
        "Статус сервера": status,
    }
    handler = handlers.get(text)
    if handler:
        await handler(update, context)


def main() -> None:
    settings = Settings.from_env()
    app = Application.builder().token(settings.bot_token).build()
    app.bot_data["settings"] = settings
    app.add_handler(CommandHandler("start", start))
    app.add_handler(CommandHandler("status", status))
    app.add_handler(CommandHandler("demo_profile", demo_profile))
    app.add_handler(CommandHandler("phone", phone_instruction))
    app.add_handler(CommandHandler("pc", pc_instruction))
    app.add_handler(CommandHandler("bypass", bypass_instruction))
    app.add_handler(MessageHandler(filters.TEXT & ~filters.COMMAND, menu_text))
    app.run_polling(allowed_updates=[Update.MESSAGE, Update.CALLBACK_QUERY, Update.CHAT_JOIN_REQUEST])


if __name__ == "__main__":
    main()
