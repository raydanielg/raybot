import logging
from dataclasses import dataclass
from typing import Dict, Optional
from datetime import datetime


logger = logging.getLogger(__name__)


@dataclass
class TradingSignal:
    action: str  # BUY, SELL, HOLD
    confidence: float
    reason: str
    price: float
    lot_size: float
    timestamp: str


class StrategyEngine:
    def __init__(self, config: Dict):
        self.config = config
        self.strategy = config.get("strategy", {})
        self.risk = config.get("risk", {})
        
    def analyze_market(self, market_data: Dict) -> TradingSignal:
        price = market_data.get("price")
        if not price:
            return self._create_hold_signal(price, "No price data available")
        
        # Get indicator values
        ema_50 = market_data.get("ema_50")
        ema_200 = market_data.get("ema_200")
        atr = market_data.get("atr")
        trend = market_data.get("trend")
        
        # Run multiple strategies
        signals = []
        
        # Strategy 1: EMA Crossover
        signals.append(self._ema_crossover_strategy(price, ema_50, ema_200, trend))
        
        # Strategy 2: Trend Following
        signals.append(self._trend_following_strategy(price, trend, atr))
        
        # Strategy 3: Momentum
        signals.append(self._momentum_strategy(price, ema_50, trend))
        
        # Strategy 4: Support/Resistance
        signals.append(self._support_resistance_strategy(price, atr))
        
        # Combine signals
        combined_signal = self._combine_signals(signals, price)
        
        return combined_signal
    
    def _ema_crossover_strategy(self, price: float, ema_50: Optional[float], 
                                 ema_200: Optional[float], trend: str) -> Dict:
        if not ema_50 or not ema_200:
            # Use trend as fallback if EMA data missing
            if trend == "BULLISH":
                return {"action": "BUY", "confidence": 0.6, "reason": f"Bullish trend (no EMA data)"}
            elif trend == "BEARISH":
                return {"action": "SELL", "confidence": 0.6, "reason": f"Bearish trend (no EMA data)"}
            return {"action": "HOLD", "confidence": 0.3, "reason": "Insufficient EMA data"}
        
        if price > ema_50:
            return {
                "action": "BUY",
                "confidence": 0.7,
                "reason": f"Price above EMA 50 ({ema_50:.2f})"
            }
        elif price < ema_50:
            return {
                "action": "SELL",
                "confidence": 0.7,
                "reason": f"Price below EMA 50 ({ema_50:.2f})"
            }
        
        return {"action": "HOLD", "confidence": 0.4, "reason": "Price near EMA 50"}
    
    def _trend_following_strategy(self, price: float, trend: str, atr: Optional[float]) -> Dict:
        if trend == "BULLISH":
            return {
                "action": "BUY",
                "confidence": 0.8,
                "reason": f"Bullish trend detected"
            }
        elif trend == "BEARISH":
            return {
                "action": "SELL",
                "confidence": 0.8,
                "reason": f"Bearish trend detected"
            }
        
        # If trend is unknown, use simple price action
        # Random but consistent decision based on price
        if price % 2 < 1:
            return {
                "action": "BUY",
                "confidence": 0.5,
                "reason": f"Price action bias (unknown trend)"
            }
        else:
            return {
                "action": "SELL",
                "confidence": 0.5,
                "reason": f"Price action bias (unknown trend)"
            }
    
    def _momentum_strategy(self, price: float, ema_50: Optional[float], trend: str) -> Dict:
        if not ema_50:
            return {"action": "HOLD", "confidence": 0.3, "reason": "No EMA 50 data"}
        
        # Price momentum relative to EMA 50
        momentum = (price - ema_50) / ema_50 * 100
        
        if momentum > 0.5:  # Strong bullish momentum
            return {
                "action": "BUY",
                "confidence": 0.70,
                "reason": f"Strong bullish momentum: {momentum:.2f}% above EMA 50"
            }
        elif momentum < -0.5:  # Strong bearish momentum
            return {
                "action": "SELL",
                "confidence": 0.70,
                "reason": f"Strong bearish momentum: {momentum:.2f}% below EMA 50"
            }
        
        return {"action": "HOLD", "confidence": 0.4, "reason": f"Weak momentum: {momentum:.2f}%"}
    
    def _support_resistance_strategy(self, price: float, atr: Optional[float]) -> Dict:
        if not atr:
            return {"action": "HOLD", "confidence": 0.3, "reason": "No ATR data"}
        
        # Simple support/resistance based on ATR
        # In real implementation, this would use historical pivot points
        atr_threshold = atr * 0.5
        
        if atr_threshold > 2.0:  # High volatility - avoid trading
            return {
                "action": "HOLD",
                "confidence": 0.5,
                "reason": f"High volatility detected (ATR: {atr:.2f})"
            }
        
        return {"action": "HOLD", "confidence": 0.4, "reason": "Normal volatility, no clear S/R level"}
    
    def _combine_signals(self, signals: list, price: float) -> TradingSignal:
        buy_count = sum(1 for s in signals if s["action"] == "BUY")
        sell_count = sum(1 for s in signals if s["action"] == "SELL")
        hold_count = sum(1 for s in signals if s["action"] == "HOLD")
        
        # Calculate weighted confidence
        total_confidence = sum(s["confidence"] for s in signals)
        avg_confidence = total_confidence / len(signals)
        
        # Decision logic - more aggressive for trading
        if buy_count >= 2:
            action = "BUY"
            confidence = min(avg_confidence + 0.15, 0.95)
            reason = f"Buy signal ({buy_count}/4 strategies)"
        elif sell_count >= 2:
            action = "SELL"
            confidence = min(avg_confidence + 0.15, 0.95)
            reason = f"Sell signal ({sell_count}/4 strategies)"
        elif buy_count > sell_count:
            action = "BUY"
            confidence = max(avg_confidence + 0.1, 0.5)
            reason = f"Buy bias ({buy_count} vs {sell_count})"
        elif sell_count > buy_count:
            action = "SELL"
            confidence = max(avg_confidence + 0.1, 0.5)
            reason = f"Sell bias ({sell_count} vs {buy_count})"
        else:
            action = "HOLD"
            confidence = avg_confidence
            reason = "Neutral signal - conflicting strategies"
        
        # Check minimum confidence threshold
        min_confidence = self.risk.get("minimum_confidence", 0.3) / 100  # Convert percentage to decimal
        if confidence < min_confidence:
            action = "HOLD"
            reason += f" (confidence below {min_confidence * 100}%)"
        
        # Calculate lot size
        lot_size = self._calculate_lot_size(action)
        
        return TradingSignal(
            action=action,
            confidence=round(confidence, 2),
            reason=reason,
            price=price,
            lot_size=lot_size,
            timestamp=datetime.utcnow().isoformat()
        )
    
    def _calculate_lot_size(self, action: str) -> float:
        if action == "HOLD":
            return 0.0
        
        base_lot = self.risk.get("base_lot", 0.01)
        return base_lot
    
    def _create_hold_signal(self, price: float, reason: str) -> TradingSignal:
        return TradingSignal(
            action="HOLD",
            confidence=0.0,
            reason=reason,
            price=price if price else 0.0,
            lot_size=0.0,
            timestamp=datetime.utcnow().isoformat()
        )
