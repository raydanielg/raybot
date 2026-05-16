from __future__ import annotations

from dataclasses import asdict
from datetime import datetime, timezone
import json
import logging
from pathlib import Path
from typing import Any
import uuid
from logging import Logger

from market_analyzer import TradeSignal


class TradeExecutor:
	"""Persists outgoing signals for downstream EA consumption."""

	def __init__(self, root_dir: Path) -> None:
		self.root_dir = root_dir
		self.data_file = self.root_dir / "data" / "signals.json"
		self.orders_file = self.root_dir / "data" / "order_requests.json"
		self.latest_order_file = self.root_dir / "data" / "order_request.latest.json"
		self.response_file = self.root_dir / "data" / "order_response.latest.json"
		self.response_history_file = self.root_dir / "data" / "order_response_history.jsonl"
		self.log_file = self.root_dir / "logs" / "trading.log"
		self._last_ack_signature = ""
		self.logger = self._configure_logger()

	def _configure_logger(self) -> Logger:
		self.log_file.parent.mkdir(parents=True, exist_ok=True)
		logger = logging.getLogger("raybot")
		logger.setLevel(logging.INFO)
		logger.propagate = False

		if not logger.handlers:
			formatter = logging.Formatter("%(asctime)s | %(levelname)s | %(message)s")
			file_handler = logging.FileHandler(self.log_file)
			stream_handler = logging.StreamHandler()
			file_handler.setFormatter(formatter)
			stream_handler.setFormatter(formatter)
			logger.addHandler(file_handler)
			logger.addHandler(stream_handler)

		return logger

	def _prune_jsonl_tail(self, file_path: Path, max_lines: int) -> None:
		if max_lines <= 0 or not file_path.exists():
			return

		with file_path.open("r", encoding="utf-8") as handle:
			lines = handle.readlines()

		if len(lines) <= max_lines:
			return

		with file_path.open("w", encoding="utf-8") as handle:
			handle.writelines(lines[-max_lines:])

	def _load_existing(self) -> list[dict[str, Any]]:
		if not self.data_file.exists() or self.data_file.stat().st_size == 0:
			return []

		try:
			raw = json.loads(self.data_file.read_text(encoding="utf-8"))
		except json.JSONDecodeError:
			self.logger.warning("signals.json is malformed. Reinitializing.")
			return []

		if isinstance(raw, list):
			return raw
		return []

	def _load_existing_orders(self) -> list[dict[str, Any]]:
		if not self.orders_file.exists() or self.orders_file.stat().st_size == 0:
			return []

		try:
			raw = json.loads(self.orders_file.read_text(encoding="utf-8"))
		except json.JSONDecodeError:
			self.logger.warning("order_requests.json is malformed. Reinitializing.")
			return []

		if isinstance(raw, list):
			return raw
		return []

	def _load_latest_response(self) -> dict[str, Any] | None:
		if not self.response_file.exists() or self.response_file.stat().st_size == 0:
			return None

		try:
			raw = json.loads(self.response_file.read_text(encoding="utf-8"))
		except json.JSONDecodeError:
			self.logger.warning("order_response.latest.json is malformed. Ignoring.")
			return None

		if isinstance(raw, dict):
			return raw
		return None

	def _append_response_history(self, response: dict[str, Any], signature: str) -> None:
		self.response_history_file.parent.mkdir(parents=True, exist_ok=True)
		entry = {
			"history_logged_at": datetime.now(timezone.utc).isoformat(),
			"ack_signature": signature,
			"response": response,
		}
		with self.response_history_file.open("a", encoding="utf-8") as handle:
			handle.write(json.dumps(entry, ensure_ascii=True) + "\n")

	def persist_signal(self, signal: TradeSignal, max_records: int = 200) -> None:
		self.data_file.parent.mkdir(parents=True, exist_ok=True)
		records = self._load_existing()

		payload = asdict(signal)
		payload["written_at"] = datetime.now(timezone.utc).isoformat()
		records.append(payload)
		records = records[-max_records:]

		self.data_file.write_text(
			json.dumps(records, indent=2, ensure_ascii=True), encoding="utf-8"
		)
		self.logger.info(
			"Signal stored: %s %s @ %.2f (confidence=%.2f)",
			signal.symbol,
			signal.action,
			signal.entry,
			signal.confidence,
		)

	def build_order_request(
		self,
		signal: TradeSignal,
		lot_size: float,
		strategy_id: str = "raybot-v1",
	) -> dict[str, Any] | None:
		if signal.action not in {"BUY", "SELL"}:
			return None

		return {
			"request_id": str(uuid.uuid4()),
			"strategy_id": strategy_id,
			"symbol": signal.symbol,
			"side": signal.action,
			"order_type": "MARKET",
			"volume": round(max(0.01, lot_size), 2),
			"entry_price": signal.entry,
			"stop_loss": signal.stop_loss,
			"take_profit": signal.take_profit,
			"time_in_force": "GTC",
			"status": "PENDING",
			"created_at": datetime.now(timezone.utc).isoformat(),
			"signal_timestamp": signal.timestamp,
		}

	def persist_order_request(
		self,
		order_request: dict[str, Any],
		max_records: int = 200,
	) -> None:
		self.orders_file.parent.mkdir(parents=True, exist_ok=True)
		records = self._load_existing_orders()
		records.append(order_request)
		records = records[-max_records:]

		self.orders_file.write_text(
			json.dumps(records, indent=2, ensure_ascii=True), encoding="utf-8"
		)
		self.latest_order_file.write_text(
			json.dumps(order_request, indent=2, ensure_ascii=True), encoding="utf-8"
		)
		self.logger.info(
			"Order request emitted: %s %s %.2f lots",
			order_request["symbol"],
			order_request["side"],
			order_request["volume"],
		)

	def reconcile_latest_order_response(
		self,
		max_history_records: int = 4000,
	) -> dict[str, Any] | None:
		response = self._load_latest_response()
		if response is None:
			return None

		request_id = str(response.get("request_id", "")).strip()
		status = str(response.get("status", "")).strip().upper()
		processed_at = str(response.get("processed_at", "")).strip()
		if not request_id or not status:
			return None

		signature = f"{request_id}|{status}|{processed_at}"
		if signature == self._last_ack_signature:
			return None

		orders = self._load_existing_orders()
		updated = False
		for order in orders:
			if str(order.get("request_id", "")) != request_id:
				continue

			order["status"] = status
			order["ack_processed_at"] = processed_at or datetime.now(timezone.utc).isoformat()
			order["broker_message"] = str(response.get("message", ""))
			order["order_ticket"] = response.get("order_ticket", 0)
			order["deal_ticket"] = response.get("deal_ticket", 0)
			order["retcode"] = response.get("retcode", 0)
			updated = True

		if not updated:
			return None

		self.orders_file.write_text(
			json.dumps(orders, indent=2, ensure_ascii=True), encoding="utf-8"
		)

		try:
			latest = json.loads(self.latest_order_file.read_text(encoding="utf-8"))
		except (OSError, json.JSONDecodeError):
			latest = None

		if isinstance(latest, dict) and str(latest.get("request_id", "")) == request_id:
			for key, value in response.items():
				if key == "request_id":
					continue
				latest[key] = value
			self.latest_order_file.write_text(
				json.dumps(latest, indent=2, ensure_ascii=True), encoding="utf-8"
			)

		self._append_response_history(response=response, signature=signature)
		self._prune_jsonl_tail(self.response_history_file, max(1, max_history_records))

		self._last_ack_signature = signature
		self.logger.info("Order acknowledgement applied: %s -> %s", request_id, status)
		return {
			"request_id": request_id,
			"status": status,
			"processed_at": processed_at,
		}
