from dataclasses import dataclass
import os


def _env(name: str, default: str = "") -> str:
    value = os.getenv(name, default)
    return value.strip() if isinstance(value, str) else value


@dataclass(frozen=True)
class Settings:
    bot_token: str
    webhook_host: str
    webhook_path: str
    crm_base_url: str
    crm_api_key: str
    log_level: str

    @property
    def webhook_url(self) -> str:
        base = self.webhook_host.rstrip("/")
        path = self.webhook_path if self.webhook_path.startswith("/") else f"/{self.webhook_path}"
        return f"{base}{path}"


def load_settings() -> Settings:
    return Settings(
        bot_token=_env("BOT_TOKEN"),
        webhook_host=_env("WEBHOOK_HOST", "https://bot.example.com"),
        webhook_path=_env("WEBHOOK_PATH", "/telegram/webhook"),
        crm_base_url=_env("CRM_BASE_URL", "https://crm.example.internal"),
        crm_api_key=_env("CRM_API_KEY"),
        log_level=_env("LOG_LEVEL", "INFO"),
    )
