import json
import os
from datetime import datetime
from pathlib import Path
from typing import Any, Dict

from flask import Flask, jsonify, render_template, send_from_directory

ROOT_DIR = Path(__file__).resolve().parents[1]
DATA_DIR = ROOT_DIR / "data"
LOG_DIR = ROOT_DIR / "logs"

app = Flask(__name__, template_folder=str(ROOT_DIR / "templates"))


def load_json(path: Path) -> Dict[str, Any]:
    if not path.exists():
        return {}
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError:
        return {}


@app.route("/")
def index():
    return render_template("dashboard.html")


@app.route("/api/signals")
def get_signals():
    return jsonify(load_json(DATA_DIR / "signals.json"))


@app.route("/api/market")
def get_market():
    return jsonify(load_json(DATA_DIR / "market.json"))


@app.route("/api/equity")
def get_equity():
    return jsonify(load_json(DATA_DIR / "equity.json"))


@app.route("/api/logs")
def get_logs():
    try:
        log_file = LOG_DIR / "trading.log"
        if not log_file.exists():
            return jsonify({"lines": []})
        
        lines = log_file.read_text(encoding="utf-8").splitlines()
        return jsonify({"lines": lines[-50:]})
    except Exception as e:
        return jsonify({"lines": [], "error": str(e)})


@app.route("/api/settings")
def get_settings():
    config_dir = ROOT_DIR / "config"
    settings = load_json(config_dir / "settings.json")
    strategy = load_json(config_dir / "strategy.json")
    return jsonify({"settings": settings, "strategy": strategy})


@app.route("/api/orders")
def get_orders():
    orders = load_json(DATA_DIR / "order_requests.json")
    if isinstance(orders, dict):
        orders = list(orders.values())
    return jsonify({"orders": orders[:50]})  # Last 50 orders


@app.route("/api/positions")
def get_positions():
    try:
        import MetaTrader5 as mt5
        if mt5.initialize():
            positions = mt5.positions_get()
            positions_data = []
            if positions:
                for pos in positions:
                    positions_data.append({
                        "ticket": pos.ticket,
                        "symbol": pos.symbol,
                        "type": "BUY" if pos.type == 0 else "SELL",
                        "volume": pos.volume,
                        "price_open": pos.price_open,
                        "price_current": pos.price_current,
                        "profit": pos.profit,
                        "time": datetime.fromtimestamp(pos.time).isoformat()
                    })
            mt5.shutdown()
            return jsonify({"positions": positions_data})
        return jsonify({"positions": []})
    except Exception as e:
        return jsonify({"positions": [], "error": str(e)})


if __name__ == "__main__":
    templates_dir = ROOT_DIR / "templates"
    templates_dir.mkdir(exist_ok=True)
    
    app.run(host="0.0.0.0", port=5000, debug=True)
