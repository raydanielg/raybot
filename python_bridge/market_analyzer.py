from datetime import datetime, timezone
from typing import Any, Dict, List, Optional

import numpy as np
import pandas as pd

try:
    import MetaTrader5 as mt5
except ImportError:
    mt5 = None


class MarketAnalyzer:
    def __init__(self, symbol: str, timeframe: str, candle_count: int) -> None:
        self.symbol = symbol
        self.timeframe = timeframe
        self.candle_count = candle_count

    def collect_snapshot(self) -> Dict[str, Any]:
        rates = self._fetch_rates()
        if rates is None or len(rates) < 50:
            return self._offline_snapshot()

        frame = pd.DataFrame(rates)
        frame["time"] = pd.to_datetime(frame["time"], unit="s")
        frame["ema_50"] = frame["close"].ewm(span=50, adjust=False).mean()
        frame["ema_200"] = frame["close"].ewm(span=200, adjust=False).mean()
        frame["atr"] = self._atr(frame)
        latest = frame.iloc[-1]
        previous = frame.iloc[-2]
        trend = "bullish" if latest["ema_50"] > latest["ema_200"] else "bearish"

        return {
            "source": "mt5",
            "symbol": self.symbol,
            "timeframe": self.timeframe,
            "timestamp": datetime.now(timezone.utc).isoformat(),
            "price": float(latest["close"]),
            "previous_close": float(previous["close"]),
            "ema_50": float(latest["ema_50"]),
            "ema_200": float(latest["ema_200"]),
            "atr": float(latest["atr"]),
            "trend": trend,
            "volume": float(latest.get("tick_volume", 0)),
            "recent_candles": self._recent_candles(frame.tail(10)),
        }

    def _fetch_rates(self) -> Optional[Any]:
        if mt5 is None:
            return None

        timeframe_value = self._timeframe_value()
        if timeframe_value is None:
            return None

        return mt5.copy_rates_from_pos(self.symbol, timeframe_value, 0, self.candle_count)

    def _timeframe_value(self) -> Optional[int]:
        if mt5 is None:
            return None

        mapping = {
            "M1": mt5.TIMEFRAME_M1,
            "M5": mt5.TIMEFRAME_M5,
            "M15": mt5.TIMEFRAME_M15,
            "M30": mt5.TIMEFRAME_M30,
            "H1": mt5.TIMEFRAME_H1,
        }
        return mapping.get(self.timeframe.upper())

    def _atr(self, frame: pd.DataFrame, period: int = 14) -> pd.Series:
        high_low = frame["high"] - frame["low"]
        high_close = np.abs(frame["high"] - frame["close"].shift())
        low_close = np.abs(frame["low"] - frame["close"].shift())
        true_range = pd.concat([high_low, high_close, low_close], axis=1).max(axis=1)
        return true_range.rolling(period).mean().bfill()

    def _recent_candles(self, frame: pd.DataFrame) -> List[Dict[str, Any]]:
        candles = []
        for _, row in frame.iterrows():
            candles.append(
                {
                    "time": row["time"].isoformat(),
                    "open": float(row["open"]),
                    "high": float(row["high"]),
                    "low": float(row["low"]),
                    "close": float(row["close"]),
                    "volume": float(row.get("tick_volume", 0)),
                }
            )
        return candles

    def _offline_snapshot(self) -> Dict[str, Any]:
        return {
            "source": "offline",
            "symbol": self.symbol,
            "timeframe": self.timeframe,
            "timestamp": datetime.now(timezone.utc).isoformat(),
            "price": None,
            "previous_close": None,
            "ema_50": None,
            "ema_200": None,
            "atr": None,
            "trend": "unknown",
            "volume": 0,
            "recent_candles": [],
        }
