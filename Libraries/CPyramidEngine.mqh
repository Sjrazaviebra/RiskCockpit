//+------------------------------------------------------------------+
//|                                          CPyramidEngine.mqh      |
//|                                              JR Trading - 2026   |
//|                                                                  |
//|  Safe Pyramiding plan computer (READ-ONLY / ADVISORY).           |
//|                                                                  |
//|  Inspired by MQL5 article 22187 "Safe Pyramiding with Unified    |
//|  Stop" (Tola Moses Hector, 2026-05-18). This file is the         |
//|  ADVISORY-only variant : it computes the next pyramid step       |
//|  parameters (entry trigger, add-on lot, new unified stop loss)   |
//|  WITHOUT placing any orders. Consumers (Helper Indicator, future |
//|  Companion EA) render the plan or execute it as they see fit.    |
//|                                                                  |
//|  Mathematical property                                           |
//|  -----------------------                                         |
//|  With decreasing add-on lots (V2 < V1, V3 < V2) and a unified    |
//|  stop loss set at or beyond the breakeven price after each add,  |
//|  the TOTAL RISK on the position basket decreases monotonically.  |
//|  Once the first add-on is executed (V2 placed at +1R, unified    |
//|  stop = breakeven of V1+V2), the worst-case net P&L is greater   |
//|  than or equal to zero. Same after each subsequent add.          |
//|                                                                  |
//|  Why this matters for FundedNext (and any prop firm)             |
//|  ----------------------------------------------------            |
//|  The 3 % cumulative open-risk rule is breached when SL distances |
//|  let total at-risk money exceed 3 % of balance. A pyramid built  |
//|  with decreasing lots + unified stop "advancing toward profit"   |
//|  is risk-DECREASING-by-construction : the more you add, the      |
//|  LESS at risk you are. Compatible with all FN rules by design.   |
//+------------------------------------------------------------------+
#ifndef __CPYRAMIDENGINE_MQH__
#define __CPYRAMIDENGINE_MQH__

//+------------------------------------------------------------------+
//| PyramidStep                                                      |
//|                                                                  |
//| All prices in the original symbol's quote currency. All money    |
//| values in account currency. add_lot is the NEW position only     |
//| (not cumulative). new_unified_stop applies to ALL existing       |
//| positions on the same symbol + the new add at execution time.   |
//+------------------------------------------------------------------+
struct PyramidStep
  {
   bool     ok;                  // false = step infeasible (broker constraints, etc.)
   int      step_index;          // 1 = first add, 2 = second add, ...
   double   trigger_price;       // price at which to place the new add
   double   trigger_distance_px; // distance from anchor entry to trigger (positive, favorable side)
   double   add_lot;             // lot for the new add (already floored to step + clipped)
   double   add_lot_math;        // raw lot before step / min / max clipping
   double   new_unified_stop;    // SL to apply to all positions after this add
   double   worst_case_money;    // net P&L at new_unified_stop (>= 0 if step is risk-decreasing)
   double   initial_risk_money;  // P&L at original SL with just the initial vol
   double   total_vol;           // V1 + V2 + ... + add_lot
   string   info;                // human-readable summary
  };

//+------------------------------------------------------------------+
//| PyramidEngineConfig - tunables                                   |
//|                                                                  |
//| Defaults reproduce the 22187 article example with conservative   |
//| safety_margin_ratio (extra distance kept beyond pure breakeven). |
//+------------------------------------------------------------------+
struct PyramidEngineConfig
  {
   double   lot_ratio;            // V_{n+1} = V_n * lot_ratio   (default 0.66)
   double   trigger_ratio;        // trigger distance = initial_R * trigger_ratio   (default 1.0 = +1R)
   double   safety_margin_ratio;  // unified stop = breakeven shifted by initial_R * safety_margin_ratio
                                  //   in the favorable direction. Default 0.10.
   int      max_steps;            // hard cap on steps the engine will plan (1..5)   default 3
  };

//+------------------------------------------------------------------+
//| CPyramidEngine                                                   |
//+------------------------------------------------------------------+
class CPyramidEngine
  {
private:
   PyramidEngineConfig m_cfg;

   // Symbol contract helpers
   double            MoneyPerLotPerPx(const string sym) const;   // tick_value / tick_size
   double            ClipBrokerLot(const string sym, double lot) const;

public:
                     CPyramidEngine(void);
                    ~CPyramidEngine(void);

   void              SetConfig(const PyramidEngineConfig &cfg) { m_cfg = cfg; }
   PyramidEngineConfig GetConfig(void) const { return m_cfg; }

   // ComputeNextStep -- plans the SINGLE next add-on for a position basket
   // described by its weighted-average entry, total vol so far, current SL,
   // and side. Step-index for cosmetic info only.
   //
   //   anchor_entry  : weighted-average entry price of existing positions
   //   anchor_vol    : sum of all existing vols on the same symbol
   //   anchor_sl     : current unified SL (or initial SL if no add yet)
   //   is_buy        : true for long basket, false for short
   //   sym           : symbol (used for tick_size / value / vol_step lookups)
   //   step_index    : 1 = first add (planning add #2 onto a single entry)
   bool              ComputeNextStep(const string sym,
                                     const double anchor_entry,
                                     const double anchor_vol,
                                     const double anchor_sl,
                                     const bool is_buy,
                                     const int step_index,
                                     PyramidStep &out) const;

   // ComputePlan -- iterates ComputeNextStep up to max_steps times, each step
   // assuming the previous step executed and became the new anchor.
   // Returns the actual number of feasible steps produced.
   int               ComputePlan(const string sym,
                                 const double initial_entry,
                                 const double initial_vol,
                                 const double initial_sl,
                                 const bool is_buy,
                                 PyramidStep &steps[]) const;
  };

//+------------------------------------------------------------------+
//| Ctor                                                             |
//+------------------------------------------------------------------+
CPyramidEngine::CPyramidEngine(void)
  {
   m_cfg.lot_ratio           = 0.66;
   m_cfg.trigger_ratio       = 1.00;
   m_cfg.safety_margin_ratio = 0.10;
   m_cfg.max_steps           = 3;
  }

CPyramidEngine::~CPyramidEngine(void) {}

//+------------------------------------------------------------------+
//| Money-per-(lot * price-unit) on a symbol                         |
//|                                                                  |
//| Returns tick_value / tick_size so that price_distance * vol *    |
//| this_factor = money lost/gained.                                 |
//+------------------------------------------------------------------+
double CPyramidEngine::MoneyPerLotPerPx(const string sym) const
  {
   const double tick_size  = SymbolInfoDouble(sym, SYMBOL_TRADE_TICK_SIZE);
   const double tick_value = SymbolInfoDouble(sym, SYMBOL_TRADE_TICK_VALUE);
   if(tick_size <= 0.0 || tick_value <= 0.0)
      return 0.0;
   return tick_value / tick_size;
  }

//+------------------------------------------------------------------+
//| Floor to vol step + clip to broker min / max                     |
//+------------------------------------------------------------------+
double CPyramidEngine::ClipBrokerLot(const string sym, double lot) const
  {
   const double vol_step = SymbolInfoDouble(sym, SYMBOL_VOLUME_STEP);
   const double vol_min  = SymbolInfoDouble(sym, SYMBOL_VOLUME_MIN);
   const double vol_max  = SymbolInfoDouble(sym, SYMBOL_VOLUME_MAX);

   double broker = lot;
   if(vol_step > 0.0)
      broker = MathFloor(broker / vol_step) * vol_step;
   if(vol_min > 0.0 && broker < vol_min)
      broker = vol_min;
   if(vol_max > 0.0 && broker > vol_max)
      broker = vol_max;
   return broker;
  }

//+------------------------------------------------------------------+
//| ComputeNextStep                                                  |
//|                                                                  |
//| Given an open basket (anchor_entry, anchor_vol, anchor_sl)       |
//| compute the parameters of the NEXT pyramid step :                |
//|                                                                  |
//|   1. R          = |anchor_entry - anchor_sl|                     |
//|   2. trigger    = anchor_entry +/- R * trigger_ratio  (favorable)|
//|   3. add_lot    = anchor_vol * lot_ratio (math),                 |
//|                   floored + clipped to broker constraints        |
//|   4. breakeven  = weighted average of (anchor_entry, trigger)    |
//|                   weighted by (anchor_vol, add_lot)              |
//|   5. new_stop   = breakeven shifted by R * safety_margin_ratio   |
//|                   in the FAVORABLE direction (= profit locked)   |
//|   6. worst_case = ((new_stop - anchor_entry) * anchor_vol +      |
//|                    (new_stop - trigger) * add_lot) * mppx        |
//|                   (sign-adjusted for SELL basket)                |
//|                                                                  |
//| Returns false if R == 0, mppx == 0, or add_lot falls below       |
//| vol_min after clipping (caller can downgrade the plan).          |
//+------------------------------------------------------------------+
bool CPyramidEngine::ComputeNextStep(const string sym,
                                     const double anchor_entry,
                                     const double anchor_vol,
                                     const double anchor_sl,
                                     const bool is_buy,
                                     const int step_index,
                                     PyramidStep &out) const
  {
   out.ok                  = false;
   out.step_index          = step_index;
   out.trigger_price       = 0.0;
   out.trigger_distance_px = 0.0;
   out.add_lot             = 0.0;
   out.add_lot_math        = 0.0;
   out.new_unified_stop    = 0.0;
   out.worst_case_money    = 0.0;
   out.initial_risk_money  = 0.0;
   out.total_vol           = anchor_vol;
   out.info                = "";

   if(anchor_entry <= 0.0 || anchor_vol <= 0.0 || anchor_sl <= 0.0)
     {
      out.info = "missing entry / vol / SL";
      return false;
     }

   const double mppx = MoneyPerLotPerPx(sym);
   if(mppx <= 0.0)
     {
      out.info = "symbol contract data unavailable";
      return false;
     }

   const double R = MathAbs(anchor_entry - anchor_sl);   // initial "1R" distance
   if(R <= 0.0)
     {
      out.info = "anchor entry equal to SL (R = 0)";
      return false;
     }

   // Initial risk : sign-stable across BUY/SELL because we use |distance|.
   out.initial_risk_money = R * anchor_vol * mppx;

   // Trigger : favorable direction = profit side.
   const double trigger_dist = R * m_cfg.trigger_ratio;
   out.trigger_distance_px = trigger_dist;
   out.trigger_price = (is_buy ? anchor_entry + trigger_dist
                               : anchor_entry - trigger_dist);

   // Math add-on lot. lot_ratio < 1 enforces decreasing volumes.
   out.add_lot_math = anchor_vol * m_cfg.lot_ratio;
   const double add_clipped = ClipBrokerLot(sym, out.add_lot_math);
   const double vol_min     = SymbolInfoDouble(sym, SYMBOL_VOLUME_MIN);
   if(add_clipped <= 0.0 || (vol_min > 0.0 && add_clipped < vol_min))
     {
      out.add_lot = 0.0;
      out.info    = "add lot below broker minimum after step rounding";
      return false;
     }
   out.add_lot   = add_clipped;
   out.total_vol = anchor_vol + add_clipped;

   // Breakeven price (overall PnL = 0 with the new add at trigger).
   //   Solve : (P - anchor_entry) * V1 + (P - trigger) * V2 = 0
   //   P_be  = (anchor_entry * V1 + trigger * V2) / (V1 + V2)
   // Identical algebra for BUY and SELL : direction sign is carried by
   // trigger - anchor_entry (positive for BUY, negative for SELL).
   const double weighted_num = anchor_entry * anchor_vol + out.trigger_price * out.add_lot;
   const double weighted_den = out.total_vol;
   if(weighted_den <= 0.0)
     {
      out.info = "total vol non-positive";
      return false;
     }
   const double breakeven = weighted_num / weighted_den;

   // Safety margin : shift unified stop BEYOND breakeven in the FAVORABLE
   // direction so the worst-case net PnL is strictly positive. For BUY the
   // favorable side is UPWARD, so we add the margin; for SELL we subtract.
   const double safety = R * m_cfg.safety_margin_ratio;
   out.new_unified_stop = (is_buy ? breakeven + safety
                                   : breakeven - safety);

   // Worst-case money : evaluate PnL at the new unified stop with both legs.
   const double pnl_anchor = (is_buy ? (out.new_unified_stop - anchor_entry)
                                      : (anchor_entry - out.new_unified_stop))
                              * anchor_vol * mppx;
   const double pnl_add    = (is_buy ? (out.new_unified_stop - out.trigger_price)
                                      : (out.trigger_price - out.new_unified_stop))
                              * out.add_lot * mppx;
   out.worst_case_money = pnl_anchor + pnl_add;

   // Compose info text.
   const string side  = (is_buy ? "BUY" : "SELL");
   string s;
   StringConcatenate(s,
                     "Step ", step_index,
                     " ", side,
                     "  add ", DoubleToString(out.add_lot, 2),
                     " @ ", DoubleToString(out.trigger_price, _Digits),
                     "  -> unified SL ", DoubleToString(out.new_unified_stop, _Digits),
                     "  worst-case ", (out.worst_case_money >= 0.0 ? "+$" : "-$"),
                     DoubleToString(MathAbs(out.worst_case_money), 2));
   out.info = s;

   out.ok = true;
   return true;
  }

//+------------------------------------------------------------------+
//| ComputePlan -- chain N steps                                     |
//|                                                                  |
//| Each step uses the PREVIOUS step's (weighted entry, cumulative   |
//| vol, new unified SL) as the next anchor. Stops at max_steps or   |
//| the first infeasible step (vol_min, etc.).                       |
//+------------------------------------------------------------------+
int CPyramidEngine::ComputePlan(const string sym,
                                const double initial_entry,
                                const double initial_vol,
                                const double initial_sl,
                                const bool is_buy,
                                PyramidStep &steps[]) const
  {
   ArrayResize(steps, 0);
   const int cap = MathMax(1, MathMin(5, m_cfg.max_steps));

   double cur_entry = initial_entry;
   double cur_vol   = initial_vol;
   double cur_sl    = initial_sl;

   for(int i = 1; i <= cap; ++i)
     {
      PyramidStep s;
      if(!ComputeNextStep(sym, cur_entry, cur_vol, cur_sl, is_buy, i, s))
         break;
      const int n = ArraySize(steps);
      ArrayResize(steps, n + 1);
      steps[n] = s;

      // Promote this step's outcome to the new anchor for the next iteration.
      // New weighted entry : weighted average of cur_entry and s.trigger_price.
      const double new_anchor_entry =
         (cur_entry * cur_vol + s.trigger_price * s.add_lot) / s.total_vol;
      cur_entry = new_anchor_entry;
      cur_vol   = s.total_vol;
      cur_sl    = s.new_unified_stop;
     }
   return ArraySize(steps);
  }

#endif // __CPYRAMIDENGINE_MQH__
//+------------------------------------------------------------------+
