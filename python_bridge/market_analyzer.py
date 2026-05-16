from __future__ import annotations

from dataclasses import asdict, dataclass
from datetime import datetime, timezone
import json
from pathlib import Path
import random
from typing import Any


@dataclass
class MarketSnapshot:
	symbol: str
	price: float
	spread: float
	atr: float
	momentum: float
	timestamp: str
	source: str


@dataclass
class TradeSignal:
	symbol: str
	action: str
	confidence: float
	entry: float
	stop_loss: float
	take_profit: float
	reason: str
	timestamp: str


class MarketAnalyzer:
	"""Creates deterministic, rule-based signals from basic market features."""

	def __init__(
		self,
		symbol: str = "XAUUSD",
		feed_file: Path | None = None,
		max_feed_age_seconds: int = 5,
	) -> None:
		self.symbol = symbol
		self.feed_file = feed_file
		self.max_feed_age_seconds = max(1, max_feed_age_seconds)

	def _parse_iso_datetime(self, value: str | None) -> datetime | None:
		if not value:
			return None
		try:
			parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
			if parsed.tzinfo is None:
				return parsed.replace(tzinfo=timezone.utc)
			return parsed
		except ValueError:
			return None

	def _load_feed_payload(self) -> dict[str, Any] | None:
		if self.feed_file is None or not self.feed_file.exists():
			return None

		try:
			payload = json.loads(self.feed_file.read_text(encoding="utf-8"))
		except (OSError, json.JSONDecodeError):
			return None

		if not isinstance(payload, dict):
			return None

		ts = self._parse_iso_datetime(str(payload.get("timestamp", "")))
		if ts is None:
			return None

		age_seconds = (datetime.now(timezone.utc) - ts).total_seconds()
		if age_seconds > self.max_feed_age_seconds:
			return None

		return payload

	def _build_snapshot_from_feed(self, payload: dict[str, Any]) -> MarketSnapshot | None:
		symbol = str(payload.get("symbol", self.symbol))
		if symbol != self.symbol:
			return None

		try:
			bid = float(payload["bid"])
			ask = float(payload["ask"])
			atr = float(payload["atr"])
			momentum = float(payload["momentum"])
		except (KeyError, TypeError, ValueError):
			return None

		if ask < bid:
			return None

		ts = self._parse_iso_datetime(str(payload.get("timestamp", "")))
		if ts is None:
			return None

		price = (bid + ask) / 2
		spread = ask - bid
		return MarketSnapshot(
			symbol=symbol,
			price=round(price, 2),
			spread=round(spread, 2),
			atr=round(max(atr, 0.01), 2),
			momentum=round(momentum, 3),
			timestamp=ts.astimezone(timezone.utc).isoformat(),
			source="mt5_feed",
		)

	def _simulated_snapshot(self) -> MarketSnapshot:
		# Simulated fallback when no fresh MT5 feed is available.
		base = 2360.0
		price = base + random.uniform(-8.0, 8.0)
		spread = random.uniform(0.1, 0.6)
		atr = random.uniform(1.5, 5.0)
		momentum = random.uniform(-1.0, 1.0)
		return MarketSnapshot(
			symbol=self.symbol,
			price=round(price, 2),
			spread=round(spread, 2),
			atr=round(atr, 2),
			momentum=round(momentum, 3),
			timestamp=datetime.now(timezone.utc).isoformat(),
			source="simulated",
		)

	def fetch_market_snapshot(self) -> MarketSnapshot:
		payload = self._load_feed_payload()
		if payload is not None:
			snapshot = self._build_snapshot_from_feed(payload)
			if snapshot is not None:
				return snapshot

		return self._simulated_snapshot()

	def analyze(self, snapshot: MarketSnapshot) -> TradeSignal:
		action = "HOLD"
		confidence = 0.45

		if snapshot.momentum >= 0.35 and snapshot.spread <= 0.4:
			action = "BUY"
			confidence = min(0.95, 0.55 + snapshot.momentum * 0.3)
		elif snapshot.momentum <= -0.35 and snapshot.spread <= 0.4:
			action = "SELL"
			confidence = min(0.95, 0.55 + abs(snapshot.momentum) * 0.3)

		rr = 1.8
		stop_distance = max(snapshot.atr * 0.7, 1.2)
		tp_distance = stop_distance * rr

		if action == "BUY":
			stop_loss = snapshot.price - stop_distance
			take_profit = snapshot.price + tp_distance
		elif action == "SELL":
			stop_loss = snapshot.price + stop_distance
			take_profit = snapshot.price - tp_distance
		else:
			stop_loss = snapshot.price
			take_profit = snapshot.price

		reason = (
			f"momentum={snapshot.momentum}, spread={snapshot.spread}, "
			f"atr={snapshot.atr}, source={snapshot.source}"
		)

		return TradeSignal(
			symbol=snapshot.symbol,
			action=action,
			confidence=round(confidence, 2),
			entry=snapshot.price,
			stop_loss=round(stop_loss, 2),
			take_profit=round(take_profit, 2),
			reason=reason,
			timestamp=snapshot.timestamp,
		)


def signal_to_dict(signal: TradeSignal) -> dict:
	return asdict(signal)
