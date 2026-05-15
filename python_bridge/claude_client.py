import json
import logging
from typing import Any, Dict

import requests


class ClaudeClient:
    def __init__(self, api_key: str, model: str, timeout_seconds: int = 30) -> None:
        self.api_key = api_key
        self.model = model
        self.timeout_seconds = timeout_seconds
        self.url = "https://api.anthropic.com/v1/messages"

    def is_configured(self) -> bool:
        return bool(self.api_key and self.api_key != "your_api_key_here")

    def analyze_market(self, market_snapshot: Dict[str, Any], rules: Dict[str, Any]) -> Dict[str, Any]:
        if not self.is_configured():
            return self._hold_signal("Claude API key is not configured")

        payload = {
            "model": self.model,
            "max_tokens": 600,
            "temperature": 0.1,
            "messages": [
                {
                    "role": "user",
                    "content": self._build_prompt(market_snapshot, rules),
                }
            ],
        }
        headers = {
            "x-api-key": self.api_key,
            "anthropic-version": "2023-06-01",
            "content-type": "application/json",
        }

        try:
            response = requests.post(self.url, headers=headers, json=payload, timeout=self.timeout_seconds)
            response.raise_for_status()
            body = response.json()
            text = body["content"][0]["text"]
            return self._parse_signal(text)
        except Exception as exc:
            logging.exception("Claude request failed")
            return self._hold_signal(f"Claude request failed: {exc}")

    def _build_prompt(self, market_snapshot: Dict[str, Any], rules: Dict[str, Any]) -> str:
        return (
            "You are a strict XAUUSD scalping signal engine. "
            "Return only valid JSON with keys: action, confidence, reason, stop_loss, take_profit. "
            "Action must be BUY, SELL, or HOLD. "
            f"Rules: {json.dumps(rules, ensure_ascii=False)} "
            f"Market: {json.dumps(market_snapshot, ensure_ascii=False)}"
        )

    def _parse_signal(self, text: str) -> Dict[str, Any]:
        try:
            start = text.find("{")
            end = text.rfind("}") + 1
            raw = text[start:end] if start >= 0 and end > start else text
            signal = json.loads(raw)
        except json.JSONDecodeError:
            return self._hold_signal("Claude returned invalid JSON")

        action = str(signal.get("action", "HOLD")).upper()
        if action not in {"BUY", "SELL", "HOLD"}:
            action = "HOLD"

        return {
            "action": action,
            "confidence": float(signal.get("confidence", 0)),
            "reason": str(signal.get("reason", "")),
            "stop_loss": signal.get("stop_loss"),
            "take_profit": signal.get("take_profit"),
        }

    def _hold_signal(self, reason: str) -> Dict[str, Any]:
        return {
            "action": "HOLD",
            "confidence": 0.0,
            "reason": reason,
            "stop_loss": None,
            "take_profit": None,
        }
