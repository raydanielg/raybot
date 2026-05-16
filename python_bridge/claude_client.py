from __future__ import annotations

import json
import os
from typing import Any
from urllib import error, request

from market_analyzer import TradeSignal


class ClaudeClient:
	"""Tiny client wrapper for optional model-generated trade commentary."""

	def __init__(self) -> None:
		self.api_key = os.getenv("ANTHROPIC_API_KEY", "").strip()
		self.model = os.getenv("ANTHROPIC_MODEL", "claude-3-5-sonnet-latest")
		self.endpoint = "https://api.anthropic.com/v1/messages"

	def summarize_signal(self, signal: TradeSignal) -> str:
		if not self.api_key:
			return self._fallback_summary(signal)

		prompt = (
			"Summarize this trading signal in one short sentence for a log file: "
			f"{signal.action} {signal.symbol} at {signal.entry} with confidence "
			f"{signal.confidence} and reason {signal.reason}."
		)

		body: dict[str, Any] = {
			"model": self.model,
			"max_tokens": 120,
			"messages": [{"role": "user", "content": prompt}],
		}

		req = request.Request(
			self.endpoint,
			data=json.dumps(body).encode("utf-8"),
			headers={
				"content-type": "application/json",
				"x-api-key": self.api_key,
				"anthropic-version": "2023-06-01",
			},
			method="POST",
		)

		try:
			with request.urlopen(req, timeout=20) as resp:
				payload = json.loads(resp.read().decode("utf-8"))
			text = payload.get("content", [{}])[0].get("text", "").strip()
			return text or self._fallback_summary(signal)
		except (error.URLError, error.HTTPError, TimeoutError, KeyError, IndexError, json.JSONDecodeError):
			return self._fallback_summary(signal)

	@staticmethod
	def _fallback_summary(signal: TradeSignal) -> str:
		return (
			f"{signal.action} {signal.symbol} at {signal.entry:.2f}, "
			f"SL {signal.stop_loss:.2f}, TP {signal.take_profit:.2f}, "
			f"confidence {signal.confidence:.2f}."
		)
