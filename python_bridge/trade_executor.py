import json
import os
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Dict, Optional


class TradeExecutor:
    def __init__(self, data_dir: Path, settings: Dict[str, Any]) -> None:
        self.data_dir = data_dir
        self.settings = settings
        self.signal_file = data_dir / "signals.json"
        self.market_file = data_dir / "market.json"
        self.equity_file = data_dir / "equity.json"
        self.mt5_common_dir = self._resolve_mt5_common_dir()

    def write_market_snapshot(self, snapshot: Dict[str, Any]) -> None:
        self._write_json(self.market_file, snapshot)

    def write_signal(self, signal: Dict[str, Any], market_snapshot: Dict[str, Any]) -> Dict[str, Any]:
        validated = self._validate_signal(signal, market_snapshot)
        self._write_json(self.signal_file, validated)
        return validated

    def read_equity(self) -> Dict[str, Any]:
        common_equity = self.mt5_common_dir / "equity.json" if self.mt5_common_dir else None
        if common_equity and common_equity.exists():
            try:
                equity = json.loads(common_equity.read_text(encoding="utf-8"))
                self._write_local_json(self.equity_file, equity)
                return equity
            except json.JSONDecodeError:
                pass

        if not self.equity_file.exists():
            equity = self._default_equity()
            self._write_local_json(self.equity_file, equity)
            return equity

        try:
            return json.loads(self.equity_file.read_text(encoding="utf-8"))
        except json.JSONDecodeError:
            return self._default_equity()

    def _validate_signal(self, signal: Dict[str, Any], market_snapshot: Dict[str, Any]) -> Dict[str, Any]:
        equity = self.read_equity()
        risk = self.settings["risk"]
        confidence = float(signal.get("confidence", 0))
        action = str(signal.get("action", "HOLD")).upper()
        reason = str(signal.get("reason", ""))

        if action not in {"BUY", "SELL", "HOLD"}:
            action = "HOLD"
            reason = "Invalid action received"

        if confidence < float(risk["minimum_confidence"]):
            action = "HOLD"
            reason = f"Confidence below threshold: {confidence}"

        if int(equity.get("open_positions", 0)) >= int(risk["max_trades"]):
            action = "HOLD"
            reason = "Maximum open trades reached"

        lot_size = self._calculate_lot_size(float(equity.get("equity", risk["starting_equity"])))

        return {
            "timestamp": datetime.now(timezone.utc).isoformat(),
            "symbol": self.settings["trading"]["symbol"],
            "action": action,
            "confidence": confidence,
            "lot_size": lot_size,
            "stop_loss": signal.get("stop_loss"),
            "take_profit": signal.get("take_profit"),
            "reason": reason,
            "market_price": market_snapshot.get("price"),
            "source": "python_bridge",
        }

    def _calculate_lot_size(self, current_equity: float) -> float:
        risk = self.settings["risk"]
        base_lot = float(risk["base_lot"])
        starting_equity = float(risk["starting_equity"])
        max_lot = float(risk["max_lot"])
        scaled = base_lot * (current_equity / starting_equity)
        return round(max(base_lot, min(scaled, max_lot)), 2)

    def _default_equity(self) -> Dict[str, Any]:
        return {
            "timestamp": datetime.now(timezone.utc).isoformat(),
            "balance": self.settings["risk"]["starting_equity"],
            "equity": self.settings["risk"]["starting_equity"],
            "open_positions": 0,
        }

    def _write_json(self, path: Path, payload: Dict[str, Any]) -> None:
        self._write_local_json(path, payload)

        if self.mt5_common_dir and path.name in {"signals.json", "market.json"}:
            mirror = self.mt5_common_dir / path.name
            self._write_local_json(mirror, payload)

    def _write_local_json(self, path: Path, payload: Dict[str, Any]) -> None:
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(json.dumps(payload, indent=2), encoding="utf-8")

    def _resolve_mt5_common_dir(self) -> Optional[Path]:
        configured = os.getenv("MT5_COMMON_FILES")
        if configured:
            return Path(configured)

        appdata = os.getenv("APPDATA")
        if appdata:
            common = Path(appdata) / "MetaQuotes" / "Terminal" / "Common" / "Files"
            if common.exists():
                return common

        return None
