from __future__ import annotations

import json
from dataclasses import dataclass
from typing import Any, Dict, Optional

import requests


@dataclass
class ProviderPreset:
    id: str
    label: str
    api_kind: str  # "openai_compat" | "anthropic" | "gemini"
    default_base_url: str
    default_model: str
    key_hint: str
    apply_url: str


PROVIDER_PRESETS: list[ProviderPreset] = [
    ProviderPreset(
        id="claude",
        label="Claude / Anthropic",
        api_kind="anthropic",
        default_base_url="https://api.anthropic.com",
        default_model="claude-3-5-sonnet-20241022",
        key_hint="ANTHROPIC_API_KEY",
        apply_url="https://platform.claude.com/settings/keys",
    ),
    ProviderPreset(
        id="chatgpt",
        label="ChatGPT / OpenAI",
        api_kind="openai_compat",
        default_base_url="https://api.openai.com/v1",
        default_model="gpt-4.1-mini",
        key_hint="OPENAI_API_KEY",
        apply_url="https://platform.openai.com/",
    ),
    ProviderPreset(
        id="gemini",
        label="Gemini / Google AI Studio",
        api_kind="gemini",
        default_base_url="https://generativelanguage.googleapis.com",
        default_model="gemini-1.5-pro",
        key_hint="GEMINI_API_KEY",
        apply_url="https://aistudio.google.com/api-keys",
    ),
    ProviderPreset(
        id="kimi",
        label="Kimi / Moonshot（OpenAI 兼容）",
        api_kind="openai_compat",
        default_base_url="https://api.moonshot.cn/v1",
        default_model="moonshot-v1-8k",
        key_hint="MOONSHOT_API_KEY",
        apply_url="https://platform.moonshot.cn/console/api-keys",
    ),
    ProviderPreset(
        id="minimax",
        label="Minimax",
        api_kind="openai_compat",
        default_base_url="https://api.minimax.chat/v1",
        default_model="abab6.5s-chat",
        key_hint="MINIMAX_API_KEY",
        apply_url="https://platform.minimaxi.com/user-center/basic-information",
    ),
    ProviderPreset(
        id="zhipu",
        label="智谱 GLM",
        api_kind="openai_compat",
        default_base_url="https://open.bigmodel.cn/api/paas/v4",
        default_model="glm-4-flash",
        key_hint="ZHIPU_API_KEY",
        apply_url="https://bigmodel.cn/usercenter/proj-mgmt/apikeys",
    ),
]


@dataclass
class OpenAICompatConfig:
    base_url: str
    api_key: str
    model: str
    timeout_s: int = 60


class OpenAICompatClient:
    """
    极简 OpenAI 兼容 Chat Completions 客户端。
    目标：足够稳定、依赖少（requests），便于打包成 exe。
    """

    def __init__(self, cfg: OpenAICompatConfig):
        self.cfg = cfg

    def chat(self, *, system: str, user: str) -> str:
        base = self.cfg.base_url.rstrip("/")
        url = f"{base}/chat/completions"
        headers = {
            "Authorization": f"Bearer {self.cfg.api_key}",
            "Content-Type": "application/json",
        }
        payload: Dict[str, Any] = {
            "model": self.cfg.model,
            "messages": [
                {"role": "system", "content": system},
                {"role": "user", "content": user},
            ],
            "temperature": 0.2,
        }

        resp = requests.post(url, headers=headers, data=json.dumps(payload), timeout=self.cfg.timeout_s)
        if resp.status_code >= 400:
            raise RuntimeError(f"API 请求失败: HTTP {resp.status_code}: {resp.text[:2000]}")

        data: Dict[str, Any] = resp.json()
        choices = data.get("choices") or []
        if not choices:
            raise RuntimeError(f"API 返回无 choices: {data}")

        msg = choices[0].get("message") or {}
        content = msg.get("content")
        if not isinstance(content, str) or not content.strip():
            raise RuntimeError(f"API 返回内容为空: {data}")
        return content.strip()


@dataclass
class AnthropicConfig:
    base_url: str
    api_key: str
    model: str
    timeout_s: int = 60


class AnthropicClient:
    def __init__(self, cfg: AnthropicConfig):
        self.cfg = cfg

    def chat(self, *, system: str, user: str) -> str:
        base = self.cfg.base_url.rstrip("/")
        url = f"{base}/v1/messages"
        headers = {
            "x-api-key": self.cfg.api_key,
            "anthropic-version": "2023-06-01",
            "content-type": "application/json",
        }
        payload: Dict[str, Any] = {
            "model": self.cfg.model,
            "max_tokens": 1200,
            "temperature": 0.2,
            "system": system,
            "messages": [{"role": "user", "content": user}],
        }
        resp = requests.post(url, headers=headers, data=json.dumps(payload), timeout=self.cfg.timeout_s)
        if resp.status_code >= 400:
            raise RuntimeError(f"API 请求失败: HTTP {resp.status_code}: {resp.text[:2000]}")

        data: Dict[str, Any] = resp.json()
        content = data.get("content")
        if isinstance(content, list) and content:
            first = content[0]
            if isinstance(first, dict) and isinstance(first.get("text"), str) and first["text"].strip():
                return first["text"].strip()
        raise RuntimeError(f"API 返回内容无法解析: {data}")


@dataclass
class GeminiConfig:
    base_url: str
    api_key: str
    model: str
    timeout_s: int = 60


class GeminiClient:
    def __init__(self, cfg: GeminiConfig):
        self.cfg = cfg

    def chat(self, *, system: str, user: str) -> str:
        base = self.cfg.base_url.rstrip("/")
        model = self.cfg.model.strip()
        if not model:
            raise RuntimeError("Gemini 必须填写 model（例如 gemini-1.5-pro）。")
        url = f"{base}/v1beta/models/{model}:generateContent?key={self.cfg.api_key}"
        headers = {"content-type": "application/json"}
        text = f"[系统]\\n{system}\\n\\n[用户]\\n{user}"
        payload: Dict[str, Any] = {
            "contents": [{"role": "user", "parts": [{"text": text}]}],
            "generationConfig": {"temperature": 0.2, "maxOutputTokens": 1200},
        }
        resp = requests.post(url, headers=headers, data=json.dumps(payload), timeout=self.cfg.timeout_s)
        if resp.status_code >= 400:
            raise RuntimeError(f"API 请求失败: HTTP {resp.status_code}: {resp.text[:2000]}")

        data: Dict[str, Any] = resp.json()
        candidates = data.get("candidates") or []
        if candidates:
            content = candidates[0].get("content") or {}
            parts = content.get("parts") or []
            if parts and isinstance(parts[0], dict):
                t = parts[0].get("text")
                if isinstance(t, str) and t.strip():
                    return t.strip()
        raise RuntimeError(f"API 返回内容无法解析: {data}")


def safe_get_env(name: str) -> Optional[str]:
    try:
        v = os.environ.get(name)
        return v if v else None
    except Exception:
        return None


def encrypt_api_key(key: str) -> str:
    """简单的 API Key 混淆（Base64 编码），防止明文泄露"""
    import base64
    return base64.b64encode(key.encode()).decode()


def decrypt_api_key(encrypted: str) -> Optional[str]:
    """解密 API Key"""
    import base64
    try:
        return base64.b64decode(encrypted.encode()).decode()
    except Exception:
        return None

