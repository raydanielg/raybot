import json
import logging
import os
import sys
import time
from datetime import datetime
from pathlib import Path
from typing import Any, Dict

from dotenv import load_dotenv

from claude_client import ClaudeClient
from market_analyzer import MarketAnalyzer
from trade_executor import TradeExecutor

try:
    import MetaTrader5 as mt5
except ImportError:
    mt5 = None


ROOT_DIR = Path(__file__).resolve().parents[1]
CONFIG_DIR = ROOT_DIR / "config"
DATA_DIR = ROOT_DIR / "data"
LOG_DIR = ROOT_DIR / "logs"


def load_json(path: Path) -> Dict[str, Any]:
    with path.open("r", encoding="utf-8") as file:
        return json.load(file)


def setup_logging() -> None:
    LOG_DIR.mkdir(parents=True, exist_ok=True)
    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s | %(levelname)s | %(message)s",
        handlers=[
            logging.FileHandler(LOG_DIR / "trading.log", encoding="utf-8"),
            logging.StreamHandler(sys.stdout),
        ],
    )


def initialize_mt5() -> bool:
    if mt5 is None:
        logging.warning("MetaTrader5 package is not available")
        return False

    account = os.getenv("MT5_ACCOUNT")
    password = os.getenv("MT5_PASSWORD")
    server = os.getenv("MT5_SERVER")

    if not account or not password or not server or password == "your_password":
        logging.warning("MT5 credentials are not configured")
        return False

    if not mt5.initialize(login=int(account), password=password, server=server):
        logging.error("MT5 initialization failed: %s", mt5.last_error())
        return False

    logging.info("MT5 initialized successfully")
    return True


def run_once(settings: Dict[str, Any], strategy: Dict[str, Any]) -> Dict[str, Any]:
    analyzer = MarketAnalyzer(
        symbol=settings["trading"]["symbol"],
        timeframe=settings["trading"]["timeframe"],
        candle_count=int(strategy["candles"]["history_count"]),
    )
    executor = TradeExecutor(DATA_DIR, settings)
    client = ClaudeClient(
        api_key=os.getenv("CLAUDE_API_KEY", ""),
        model=settings["ai"]["model"],
        timeout_seconds=int(settings["ai"]["timeout_seconds"]),
    )

    snapshot = analyzer.collect_snapshot()
    executor.write_market_snapshot(snapshot)
    signal = client.analyze_market(snapshot, {"settings": settings, "strategy": strategy})
    validated = executor.write_signal(signal, snapshot)
    logging.info("Signal generated: %s confidence=%s reason=%s", validated["action"], validated["confidence"], validated["reason"])
    return validated


def main() -> None:
    load_dotenv(ROOT_DIR / ".env")
    setup_logging()

    settings = load_json(CONFIG_DIR / "settings.json")
    strategy = load_json(CONFIG_DIR / "strategy.json")
    interval = int(settings["trading"]["loop_seconds"])
    mt5_connected = initialize_mt5()

    logging.info("XAUUSD AI Scalper started at %s", datetime.now().isoformat())
    logging.info("MT5 connected: %s", mt5_connected)

    try:
        if "--once" in sys.argv:
            run_once(settings, strategy)
            return

        while True:
            run_once(settings, strategy)
            time.sleep(interval)
    except KeyboardInterrupt:
        logging.info("Shutdown requested by user")
    finally:
        if mt5_connected and mt5 is not None:
            mt5.shutdown()
        logging.info("XAUUSD AI Scalper stopped")


if __name__ == "__main__":
    main()
