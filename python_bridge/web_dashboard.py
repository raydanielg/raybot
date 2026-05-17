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


if __name__ == "__main__":
    templates_dir = ROOT_DIR / "templates"
    templates_dir.mkdir(exist_ok=True)
    
    app.run(host="0.0.0.0", port=5000, debug=True)
