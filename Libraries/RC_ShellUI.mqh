//+------------------------------------------------------------------+
//| RC_ShellUI.mqh - RiskCockpit v3 shell (lot 1 : rail + navbar).    |
//|                                                                   |
//| Space architecture ported from StrategyDeck v2 (SDDeckUI.mqh) :   |
//|  - a 36px RAIL glued to the RIGHT edge, centred band ~60% of the   |
//|    chart height, ONE cell per functional domain, each showing a    |
//|    LIVE micro-state. At rest the tool eats 36px of chart, nothing  |
//|    more (the legacy panel was 620x668).                            |
//|  - a 340px PANEL that opens ON DEMAND in front of the clicked      |
//|    cell and closes on a click elsewhere (VS Code contract : the    |
//|    same cell toggles).                                             |
//|  - a dedicated header band with a chevron = full sidebar.          |
//|  - a centred NAVBAR (750x34) for session state.                    |
//|  - optional floating surfaces (copy-lot, tooltip).                 |
//|                                                                   |
//| Hard rules kept from the playbook :                                |
//|  - SCANLINE capsules only (no RoundFill for pills).                |
//|  - the canvas is OPAQUE : every "translucent" tone is PRE-BLENDED  |
//|    through Mix() - otherwise the chart shows through.              |
//|  - font sizes in POINTS (the kit passes -size*10 to FontSet).      |
//|  - ONE render path : RenderAll() = ZReset + each surface + ONE     |
//|    ChartRedraw per frame. Never draw outside this pipeline.        |
//|  - hit-testing 100% CHARTEVENT_CLICK on anchor-relative zones,     |
//|    zero OBJ_BUTTON ; containment per surface ; anchor clamp        |
//|    everywhere (degrade, never overflow).                           |
//|                                                                   |
//| The shell is a VIEW : it never computes risk and never touches a   |
//| trade. The host fills RCDeckData from its own live functions.      |
//+------------------------------------------------------------------+
#ifndef __RC_SHELL_UI_MQH__
#define __RC_SHELL_UI_MQH__

#include <..\Libraries\JR_CanvasUI.mqh>

//--- 6 themes = 3 palettes x 2 modes (exact playbook hexes) ------------------
struct RCTheme {
   string name;
   color  accent, accent2, bg, surface, text, dim;
   color  ok, warn, red;      // semantic, palette-independent (dark/light variant)
};
void RC_ThemeGet(const int idx, RCTheme &t) {
   int i = ((idx % 6) + 6) % 6;
   switch(i) {
      case 0: t.name="EMER D"; t.accent=C'45,212,191';  t.accent2=C'13,148,136'; t.bg=C'7,20,16';    t.surface=C'16,36,28';   t.text=C'236,253,245'; t.dim=C'107,155,138'; break;
      case 1: t.name="EMER L"; t.accent=C'13,148,136';  t.accent2=C'15,118,110'; t.bg=C'240,253,250';t.surface=C'255,255,255';t.text=C'4,47,42';     t.dim=C'94,122,115';  break;
      case 2: t.name="INDI D"; t.accent=C'129,140,248'; t.accent2=C'99,102,241'; t.bg=C'11,15,30';   t.surface=C'23,27,51';   t.text=C'238,240,255'; t.dim=C'154,160,192'; break;
      case 3: t.name="INDI L"; t.accent=C'79,70,229';   t.accent2=C'67,56,202';  t.bg=C'238,240,250';t.surface=C'255,255,255';t.text=C'30,27,75';    t.dim=C'107,112,149'; break;
      case 4: t.name="ARDO D"; t.accent=C'212,212,216'; t.accent2=C'161,161,170';t.bg=C'10,10,11';   t.surface=C'24,24,27';   t.text=C'250,250,250'; t.dim=C'161,161,170'; break;
      default:t.name="ARDO L"; t.accent=C'63,63,70';    t.accent2=C'39,39,42';   t.bg=C'244,244,245';t.surface=C'255,255,255';t.text=C'24,24,27';    t.dim=C'113,113,122'; break;
   }
   const bool light = (i % 2 == 1);
   if(light) { t.ok = C'5,150,105';  t.warn = C'217,119,6';  t.red = C'220,38,38'; }
   else      { t.ok = C'52,211,153'; t.warn = C'251,191,36'; t.red = C'248,113,113'; }
}

//--- LIVE snapshot filled by the host (RiskCockpit BuildDeckData) ------------
struct RCDeckData {
   // session / account
   int    verdict;          // 0 = SAFE, 1 = WATCH, 2 = BREACH
   int    score;            // account health 0..100
   string verdictWord;      // localized SAIN / PRUDENCE / DANGER
   double equity, balance;
   string sym, tf;          // chart symbol + timeframe label
   string planTag, sizeTag; // "INST" / "2K"
   int    splitPct;
   bool   riskTools;        // the prop toolkit is ON (Personal can switch it off)
   // limits (cell LIM)
   double limRatio;         // 0..1 : worst consumption among the ACTIVE limits
   double roomMoney;        // $ to the nearest active limit (-1 = no limit applies)
   double floorMoney;       // trailing floor $ (0 when not applicable)
   bool   trailing;         // FN Instant style trailing max-loss
   double marginPct, marginCap, riskPct, riskCap;
   double dailyPct, dailyCap, overallPct, overallCap;
   bool   dailyApplies, overallApplies;
   // positions (cell POS)
   int    posCount, posWorst;   // posWorst : 0 ok, 1 watch, 2 breach, 3 n/a
   double posPnl;
   bool   posNoSl;              // at least one open position without a stop
   // lot advisor (cell LOT)
   double sugLot;
   int    lotDigits;
   bool   lotCapped, lotZero;   // capped by the 80% survival guard / no room left
   double budgetPct, freeMarginPct;
   // news (cell NEWS)
   bool   newsHasEvt, newsHigh, newsActive, newsFF;
   int    newsMins;
   // discipline (cell DISC)
   bool   discLocked, discTilt, slGuard;
   int    tradesToday, tradesCap;
   // clocks
   string clockSrv, clockGmt, clockLoc;
   // --- lot 2 : section detail -----------------------------------------
   // positions (up to 8 rows shown ; posCount keeps the true total)
   int    posN;
   string posSym[8], posSide[8];
   double posVol[8], posRowPnl[8];
   int    posAge[8], posStat[8];        // age in seconds ; status 0..3
   bool   posHasSl[8];
   // lot advisor detail
   int    nPlanned;
   double budgetMoney, spreadPts, commPerLot;
   // news detail (next groups, rule + vigilance)
   int    newsN, newsWinMin;
   double newsSharePct;                 // FN : share of a winning news-window profit
   string newsWhen[6], newsCcy[6];
   bool   newsRestr[6];
   // discipline detail
   int    lockMinsLeft, tiltWinMin, tiltN, tiltTrades;
   string slGuardSym;
   double slGuardPrice;
   bool   selfLock;
   // --- lot 2b : account card + config toggles --------------------------
   string planLabel, phaseLabel, acctTypeLabel, addonsLabel, cycleLabel, sizeLabelFull;
   long   login;
   int    minDays, minDaysDone;
   bool   cfgNewsHigh, cfgNewsMed, cfgSound, cfgTelegram, cfgComfort, cfgDiscipline;
   int    lang;                         // 0 EN, 1 FR, 2 ES
   string version;
   // --- v3.01 parity : the legacy rule rows the shell was still missing ---
   double maxLot;                       // largest openable lot (-1 = unavailable)
   int    maxLotDigits;
   double maxLotPct;                    // the binding cap, in %
   string maxLotTag;                    // "marg" | "room" | "free"
   double targetPct, targetCap;         // profit target / payout eligibility
   double qsPct, qsCap;                 // quick-strike ratio
   int    msgsToday, msgsCap;           // server messages (orders touched)
   int    newsTrades;                   // trades opened inside a news window
   double newsPnl, newsEligible;        // their P&L and the eligible share
   double newsMeterPct;                 // news-window meter fill 0..100
   // --- v3.02 : the host fills the CURRENT settings tab and the cascade ---
   int    stepN;                        // rows in the active settings tab (0..10)
   string stepLabel[10], stepValue[10];
   int    casN;                         // plan cascade rows (broker/type/phase/size/type)
   string casLabel[5], casValue[5];
};

//--- click-zone ids. Ranges used in arithmetic stay CONTIGUOUS ; new ids are
//--- appended AT THE END (playbook rule).
enum ERCZone {
   RZ_NONE = 0,
   // rail cells - contiguous block, logical order (see CellY)
   RZ_RAIL_LIM, RZ_RAIL_POS, RZ_RAIL_LOT, RZ_RAIL_NEWS,
   RZ_RAIL_DISC, RZ_RAIL_CPT, RZ_RAIL_CFG, RZ_RAIL_HELP,
   RZ_RAIL_CHEVRON,
   // panel chrome
   RZ_PANEL_CLOSE, RZ_PANEL_PIN,
   // navbar
   RZ_NAV_LOGO, RZ_NAV_SYM, RZ_NAV_TF, RZ_NAV_VITALS, RZ_NAV_HEALTH,
   RZ_NAV_PALETTE, RZ_NAV_MODE, RZ_NAV_CLOCK, RZ_NAV_KILL,
   // hover-only info zones (click = swallowed no-op, never collapses a section)
   RZ_TIP_LIM_ROOM, RZ_TIP_LIM_FLOOR, RZ_TIP_LIM_M0, RZ_TIP_LIM_M1,
   RZ_TIP_LIM_M2, RZ_TIP_LIM_M3,
   // --- lot 2 : appended AT THE END, existing ranges stay contiguous ----
   RZ_POS_ROW0, RZ_POS_ROW1, RZ_POS_ROW2, RZ_POS_ROW3,
   RZ_POS_ROW4, RZ_POS_ROW5, RZ_POS_ROW6, RZ_POS_ROW7,
   RZ_TIP_LOT_BUD, RZ_TIP_LOT_FREE, RZ_TIP_LOT_CAP,
   RZ_TIP_NEWS_SRC, RZ_TIP_NEWS_RULE, RZ_TIP_NEWS_LIST,
   RZ_TIP_DISC_LOCK, RZ_TIP_DISC_SL, RZ_TIP_DISC_TILT,
   RZ_BAND,                                    // blocking banner (info : swallows its clicks)
   // --- lot 2b : dropdown items (contiguous : index = id - RZ_MENU_0) ---
   RZ_MENU_0, RZ_MENU_1, RZ_MENU_2, RZ_MENU_3, RZ_MENU_4, RZ_MENU_5,
   RZ_MENU_6, RZ_MENU_7, RZ_MENU_8, RZ_MENU_9, RZ_MENU_10, RZ_MENU_11,
   // --- lot 2b : config toggles (contiguous : the host maps the offset) --
   RZ_CFG_PAL, RZ_CFG_MODE, RZ_CFG_LANG, RZ_CFG_NEWSH, RZ_CFG_NEWSM,
   RZ_CFG_SOUND, RZ_CFG_TG, RZ_CFG_COMFORT, RZ_CFG_DISC, RZ_CFG_RTOOLS,
   RZ_TIP_CPT, RZ_TIP_HELP, RZ_TIP_LIM_QS, RZ_TIP_MAXLOT, RZ_TIP_TARGET, RZ_TIP_MSGS, RZ_TIP_NEWSTR,
   RZ_LOT_EDIT,                                // copy-lot native edit : click = no-op (never collapses)
   // --- floating positions table (appears as soon as a trade is open) ---
   RZ_FLT_GRIP, RZ_FLT_HIDE,
   RZ_FLT_ROW0, RZ_FLT_ROW1, RZ_FLT_ROW2, RZ_FLT_ROW3,
   RZ_FLT_ROW4, RZ_FLT_ROW5, RZ_FLT_ROW6, RZ_FLT_ROW7,
   // --- v3.02 : settings tabs + steppers + plan cascade -----------------
   RZ_CFG_TAB0, RZ_CFG_TAB1, RZ_CFG_TAB2, RZ_CFG_TAB3,
   RZ_STEP_DEC0, RZ_STEP_DEC1, RZ_STEP_DEC2, RZ_STEP_DEC3, RZ_STEP_DEC4,
   RZ_STEP_DEC5, RZ_STEP_DEC6, RZ_STEP_DEC7, RZ_STEP_DEC8, RZ_STEP_DEC9,
   RZ_STEP_INC0, RZ_STEP_INC1, RZ_STEP_INC2, RZ_STEP_INC3, RZ_STEP_INC4,
   RZ_STEP_INC5, RZ_STEP_INC6, RZ_STEP_INC7, RZ_STEP_INC8, RZ_STEP_INC9,
   RZ_CAS_PREV0, RZ_CAS_PREV1, RZ_CAS_PREV2, RZ_CAS_PREV3, RZ_CAS_PREV4,
   RZ_CAS_NEXT0, RZ_CAS_NEXT1, RZ_CAS_NEXT2, RZ_CAS_NEXT3, RZ_CAS_NEXT4
};
//--- label slots : the shell ships FR defaults ; the host overrides them with
//--- its own i18n (Tr) so one translation table serves the whole product.
#define RCS_L_MAX 64
#define RCS_TIP_MAX 96      // tooltip slots, indexed by zone id (see ERCZone)
enum ERCLabel {
   RCL_SEC_LIM = 0, RCL_SEC_POS, RCL_SEC_LOT, RCL_SEC_NEWS, RCL_SEC_DISC,
   RCL_SEC_CPT, RCL_SEC_CFG, RCL_SEC_HELP,
   RCL_LIM_HEAD, RCL_LIM_MARGIN, RCL_LIM_RISK, RCL_LIM_DAILY, RCL_LIM_OVERALL,
   RCL_SURV_HEAD, RCL_ROOM, RCL_BUDGET80, RCL_FLOOR, RCL_FLOOR_WARN, RCL_NOLIMIT,
   RCL_POS_NONE, RCL_POS_PNL, RCL_POS_MORE, RCL_NOSL, RCL_MIN,
   RCL_LOT_FROM, RCL_LOT_BUDGET, RCL_LOT_N, RCL_LOT_FREE, RCL_LOT_COST,
   RCL_SPREAD, RCL_COMM, RCL_LOT_CAP, RCL_LOT_ZERO,
   RCL_NEWS_SRC, RCL_NEWS_STATE, RCL_NEWS_WIN, RCL_NEWS_NEXT, RCL_NEWS_NONE,
   RCL_NEWS_ACTIVE, RCL_NEWS_IN, RCL_NEWS_RULE, RCL_NEWS_CHECK,
   RCL_DISC_STATE, RCL_DISC_LOCKED, RCL_DISC_SLG, RCL_DISC_TILTED, RCL_DISC_OK,
   RCL_DISC_SELF, RCL_DISC_DAILY, RCL_DISC_RAISE, RCL_DISC_GOAL, RCL_DISC_DAY,
   RCL_DISC_TRADES, RCL_DISC_TILTWIN,
   RCL_BAND_LOCK, RCL_BAND_SL, RCL_BAND_TILT, RCL_LEFT, RCL_MAX,
   RCL_CPT_PLAN, RCL_CPT_PHASE, RCL_CPT_SIZE, RCL_CPT_TYPE, RCL_CPT_ADDONS,
   RCL_CPT_SPLIT, RCL_CPT_DAYS, RCL_LOT_COPY,
   RCL_LIM_QS, RCL_LOT_MAX, RCL_TARGET, RCL_MSGS, RCL_NEWSTRADES,
   RCL_PAYOUT, RCL_HYPER, RCL_ELIG, RCL_TAG_MARG, RCL_TAG_ROOM, RCL_TAG_FREE,
   RCL_CPT_PROFILE, RCL_TAB_RISK, RCL_TAB_DISC, RCL_TAB_ADV, RCL_TAB_DISP
};
struct RCZone { int x, y, w, h, id; };

//--- geometry ---------------------------------------------------------------
#define RCS_RAIL_W      36
#define RCS_CELLS_TOT  402      // 74+46+50+52+48+48+44+40 (see CellH)
#define RCS_RAIL_HEAD   44      // pad 4 + chevron band 22 + 18 breathing
#define RCS_RAIL_MING    4      // gap floor before degrading
#define RCS_NAV_W      750
#define RCS_NAV_MINW   330      // floor = the MANDATORY controls (logo+sym+tf+pal+D/L+X)
#define RCS_NAV_H       34
#define RCS_SIDE_W     340
#define RCS_SIDE_SECH  480
#define RCS_SIDE_TALLH 620      // sections with controls (settings / account)
#define RCS_SIDE_FULLH 740
#define RCS_TIP_W      236
#define RCS_TIP_H       44
#define RCS_MENU_W     120
#define RCS_BAND_H      26      // full-width blocking banner (hard lock / SL guard / tilt)
#define RCS_FLT_W      256      // floating positions table (shown while trades are open)
#define RCS_FLT_HEAD    24
#define RCS_FLT_ROW     30

//--- font scale (POINTS) ----------------------------------------------------
#define RCS_F_TITLE 10
#define RCS_F_BODY   9
#define RCS_F_LABEL  8
#define RCS_F_SMALL  7
#define RCS_F_NUM    9
#define RCS_F_BIG   16
#define RCS_F_BTN   11

//+------------------------------------------------------------------+
//| RCShellUI                                                        |
//+------------------------------------------------------------------+
class RCShellUI {
private:
   CCanvasKit m_nav, m_rail, m_side, m_float, m_menu, m_band, m_tip;   // creation order = z-order
   RCDeckData m_d;
   RCTheme    m_t;
   string     m_pfx;
   bool       m_created, m_haveData;
   int        m_themeIdx;        // 0..5 (palette*2 + light)
   int        m_state;           // 0 = rail only, 1 = one section, 2 = full sidebar
   int        m_sec;             // active section = its RZ_RAIL_* id
   int        m_chW, m_chH;
   int        m_railX, m_railY, m_railH, m_railGap;
   int        m_navX, m_navW, m_navY;
   bool       m_bandOn;          // a blocking alert owns the top band
   // copy-lot : the shell RESERVES the rect, the host owns the native OBJ_EDIT
   bool       m_lotEditOn;
   int        m_lotEditX, m_lotEditY, m_lotEditW, m_lotEditH;
   // floating positions table : draggable, position persisted by the host
   int        m_fltX, m_fltY, m_fltW, m_fltH;
   bool       m_fltOn, m_fltHidden, m_drag;
   int        m_dragOffX, m_dragOffY;
   int        m_sideX, m_sideY, m_sideH;
   RCZone     m_z[96];
   int        m_zn;
   bool       m_pendKill;        // host consumes : remove the indicator
   int        m_pendCfg;         // host consumes : a config toggle was clicked (RZ_CFG_* id, 0 = none)
   int        m_cfgTab;          // settings sub-tab : 0 risk, 1 discipline, 2 advanced, 3 display
   int        m_pendStepRow, m_pendStepDir;   // host consumes : stepper row + direction
   int        m_pendCas;         // host consumes : cascade row * 10 + (0 prev / 1 next), -1 = none
   string     m_L[RCS_L_MAX];    // i18n slots (empty = the built-in FR default is used)
   string     m_tipT[RCS_TIP_MAX], m_tipD[RCS_TIP_MAX];   // translated tooltips, indexed by zone id
   // dropdown menu (symbol / timeframe)
   bool       m_menuOpen;
   int        m_menuMode;        // 0 = timeframe, 1 = symbol
   int        m_menuX, m_menuY, m_menuH, m_menuN;
   string     m_menuItem[12];
   // tooltip machinery (hover intent)
   int        m_tipZone, m_tipPendZone, m_tipDelayMs;
   int        m_tipPX, m_tipPY, m_tipPW, m_tipPH;
   uint       m_tipDue;
   bool       m_tipsOn;
   int        m_lastMx, m_lastMy;

   uint  A(const color c, const uchar a = 0xFF) const { return ColorToARGB(c, a); }
   uint  Mix(const color c1, const color c2, const double t) const {
      const int r = (int)((c1 & 0xFF)         * (1.0 - t) + (c2 & 0xFF)         * t);
      const int g = (int)(((c1 >> 8) & 0xFF)  * (1.0 - t) + ((c2 >> 8) & 0xFF)  * t);
      const int b = (int)(((c1 >> 16) & 0xFF) * (1.0 - t) + ((c2 >> 16) & 0xFF) * t);
      return ColorToARGB((color)((b << 16) | (g << 8) | r), 0xFF);
   }
   color MixC(const color c1, const color c2, const double t) const {
      const int r = (int)((c1 & 0xFF)         * (1.0 - t) + (c2 & 0xFF)         * t);
      const int g = (int)(((c1 >> 8) & 0xFF)  * (1.0 - t) + ((c2 >> 8) & 0xFF)  * t);
      const int b = (int)(((c1 >> 16) & 0xFF) * (1.0 - t) + ((c2 >> 16) & 0xFF) * t);
      return (color)((b << 16) | (g << 8) | r);
   }
   color LineC(void)  const { return MixC(m_t.surface, m_t.text, 0.16); }
   color TrackC(void) const { return MixC(m_t.bg, clrBlack, 0.35); }
   color VerdictC(void) const {
      if(m_d.verdict >= 2) return m_t.red;
      if(m_d.verdict == 1) return m_t.warn;
      return m_t.ok;
   }
   color StatC(const int s) const {   // 0 ok, 1 watch, 2 breach, 3 n/a
      if(s >= 3) return m_t.dim;
      if(s == 2) return m_t.red;
      if(s == 1) return m_t.warn;
      return m_t.ok;
   }
   //--- i18n : the host's translation wins, the FR default is the fallback --
   string L(const int i, const string def) const {
      if(i >= 0 && i < RCS_L_MAX && StringLen(m_L[i]) > 0) return m_L[i];
      return def;
   }
   void ZReset(void) { m_zn = 0; }
   void ZAdd(const int x, const int y, const int w, const int h, const int id) {
      if(m_zn >= 96) return;
      m_z[m_zn].x = x; m_z[m_zn].y = y; m_z[m_zn].w = w; m_z[m_zn].h = h; m_z[m_zn].id = id; m_zn++;
   }

   //--- ONE source of cell geometry (local Y, dynamic gaps) -----------------
   int CellH(const int sec) const {
      switch(sec) {
         case RZ_RAIL_LIM:  return 74;
         case RZ_RAIL_POS:  return 46;
         case RZ_RAIL_LOT:  return 50;
         case RZ_RAIL_NEWS: return 52;
         case RZ_RAIL_DISC: return 48;
         case RZ_RAIL_CPT:  return 48;
         case RZ_RAIL_CFG:  return 44;
         case RZ_RAIL_HELP: return 40;
      }
      return 46;
   }
   // survival first, then execution, then context, then config.
   int CellY(const int sec) const {
      int order[8];
      order[0] = RZ_RAIL_LIM;  order[1] = RZ_RAIL_POS;  order[2] = RZ_RAIL_LOT;  order[3] = RZ_RAIL_NEWS;
      order[4] = RZ_RAIL_DISC; order[5] = RZ_RAIL_CPT;  order[6] = RZ_RAIL_CFG;  order[7] = RZ_RAIL_HELP;
      int y = RCS_RAIL_HEAD - 12;                       // 32 = pad + chevron band
      for(int i = 0; i < 8; i++) {
         if(order[i] == sec) return y;
         y += CellH(order[i]) + m_railGap;
      }
      return 12;
   }

   void ReadChart(void) {
      m_chW = (int)ChartGetInteger(0, CHART_WIDTH_IN_PIXELS);
      m_chH = (int)ChartGetInteger(0, CHART_HEIGHT_IN_PIXELS);
      if(m_chW < 400) m_chW = 400;
      if(m_chH < 300) m_chH = 300;
      // ANCHOR CLAMP : every surface hugs its edge, never leaves the screen.
      m_railX = m_chW - RCS_RAIL_W;
      m_railH = (int)(m_chH * 0.60);                    // centred band ~60% (20% air top+bottom)
      const int minh = RCS_RAIL_HEAD + RCS_CELLS_TOT + 7 * RCS_RAIL_MING;
      if(m_railH < minh) m_railH = minh;
      m_railGap = (m_railH - RCS_RAIL_HEAD - RCS_CELLS_TOT) / 7;
      if(m_railGap < RCS_RAIL_MING) m_railGap = RCS_RAIL_MING;
      m_railH = RCS_RAIL_HEAD + RCS_CELLS_TOT + 7 * m_railGap;
      if(m_railH > m_chH - 16) {                        // small chart : degrade the gaps to 0 -
         m_railGap = (m_chH - 16 - RCS_RAIL_HEAD - RCS_CELLS_TOT) / 7;   // the floor must never push
         if(m_railGap < 0) m_railGap = 0;               // the rail off-chart
         m_railH = RCS_RAIL_HEAD + RCS_CELLS_TOT + 7 * m_railGap;
         if(m_railH > m_chH - 8) m_railH = m_chH - 8;   // last clamp (content clips INSIDE the canvas)
      }
      m_railY = (m_chH - m_railH) / 2;
      if(m_railY < 8) m_railY = 8;
      // navbar : responsive width (a narrow chart must not push chips off-screen)
      m_navW = RCS_NAV_W;
      int navAvail = m_railX - 8;
      if(navAvail < RCS_NAV_MINW) navAvail = RCS_NAV_MINW;
      if(m_navW > navAvail) m_navW = navAvail;
      m_navX = (m_chW - m_navW) / 2;
      if(m_navX + m_navW > m_railX - 4) m_navX = m_railX - 4 - m_navW;
      if(m_navX < 0) m_navX = 0;
      // SAFETY : a hard lock / SL breach owns a full-width band at the very top ;
      // the navbar slides UNDER it (the alert is never the thing that gets hidden).
      m_bandOn = (m_d.discLocked || m_d.slGuard || m_d.discTilt);
      m_navY   = (m_bandOn ? RCS_BAND_H + 2 : 0);
      // floating positions table : sized on the rows it holds, clamped in-chart
      const int fltRows = (m_d.posN > 8 ? 8 : m_d.posN);
      m_fltOn = (!m_fltHidden && m_d.posCount > 0 && fltRows > 0);
      m_fltW  = RCS_FLT_W;
      m_fltH  = RCS_FLT_HEAD + 6 + fltRows * RCS_FLT_ROW + (m_d.posCount > m_d.posN ? 16 : 0) + 6;
      if(m_fltX <= 0 && m_fltY <= 0) { m_fltX = 12; m_fltY = m_navY + RCS_NAV_H + 12; }   // first run
      if(m_fltX > m_chW - m_fltW) m_fltX = m_chW - m_fltW;
      if(m_fltX < 0) m_fltX = 0;
      if(m_fltY > m_chH - m_fltH) m_fltY = m_chH - m_fltH;
      if(m_fltY < 0) m_fltY = 0;
      // dropdown : under the chip that opened it, clamped inside the chart
      m_menuH = 8 + MathMax(1, m_menuN) * 26 + 8;   // 26 px pitch (menu theme)
      m_menuX = m_navX + (m_menuMode == 0 ? 122 : 40);
      if(m_menuX + RCS_MENU_W > m_chW) m_menuX = m_chW - RCS_MENU_W;
      if(m_menuX < 0) m_menuX = 0;
      m_menuY = m_navY + RCS_NAV_H + 2;
      if(m_menuY + m_menuH > m_chH - 4) m_menuY = MathMax(0, m_chH - 4 - m_menuH);
      // deployed panel : anchored IN FRONT of its cell, clamped inside the chart
      // the settings and account sections carry steppers / cyclers : they need
      // more room than a reading section, exactly like StrategyDeck's copilot.
      m_sideH = (m_state == 2 ? RCS_SIDE_FULLH
                 : ((m_state == 1 && (m_sec == RZ_RAIL_CFG || m_sec == RZ_RAIL_CPT))
                    ? RCS_SIDE_TALLH : RCS_SIDE_SECH));
      if(m_sideH > m_chH - 24) m_sideH = m_chH - 24;
      if(m_state == 2) m_sideY = (m_chH - m_sideH) / 2;
      else {
         m_sideY = m_railY + CellY(m_sec) - 6;
         if(m_sideY + m_sideH > m_chH) m_sideY = m_chH - m_sideH;
         if(m_sideY < 0) m_sideY = 0;
      }
      m_sideX = m_railX - RCS_SIDE_W - 8;
      if(m_sideX < 0) m_sideX = 0;
   }

   //================= NAVBAR (session state - top centre) ==================
   void RenderNavbar(void) {
      if(!m_nav.Ready()) return;
      m_nav.Begin();
      const int W = m_navW, H = RCS_NAV_H;
      m_nav.SoftShadow(2, 2, W - 4, H - 4, 10, clrBlack, 5, 55);
      m_nav.Card(0, 0, W, H, 10, MixC(m_t.surface, clrWhite, 0.04), m_t.surface, LineC());
      // --- left cluster : wordmark + symbol + timeframe -------------------
      m_nav.Text(12, 9, "RC", A(m_t.accent), RCS_F_TITLE, "Segoe UI", TA_LEFT | TA_TOP, FW_BOLD);
      ZAdd(m_navX, m_navY, 34, H, RZ_NAV_LOGO);
      m_nav.CapsuleStroke(40, 7, 78, 20, Mix(m_t.surface, m_t.dim, 0.40), Mix(m_t.surface, clrBlack, 0.10));
      m_nav.Text(79, 11, m_d.sym, A(m_t.text), RCS_F_BODY, "Consolas", TA_CENTER | TA_TOP, FW_BOLD);
      ZAdd(m_navX + 40, m_navY + 7, 78, 20, RZ_NAV_SYM);
      m_nav.CapsuleStroke(122, 7, 44, 20, Mix(m_t.surface, m_t.dim, 0.40), Mix(m_t.surface, clrBlack, 0.10));
      m_nav.Text(144, 11, m_d.tf, A(m_t.accent), RCS_F_BODY, "Consolas", TA_CENTER | TA_TOP, FW_BOLD);
      ZAdd(m_navX + 122, m_navY + 7, 44, 20, RZ_NAV_TF);
      // --- right cluster : palette / mode / clock / remove ----------------
      const int killX = W - 28, clkX = W - 96, modeX = W - 130, palX = W - 172;
      m_nav.Text(killX + 9, 9, ShortToString((ushort)0x00D7), A(m_t.dim), RCS_F_BTN, "Segoe UI", TA_CENTER | TA_TOP);
      ZAdd(m_navX + killX, m_navY + 4, 22, 26, RZ_NAV_KILL);
      m_nav.Text(clkX + 30, 11, m_d.clockSrv, A(m_t.dim), RCS_F_NUM, "Consolas", TA_CENTER | TA_TOP);
      ZAdd(m_navX + clkX, m_navY + 4, 62, 26, RZ_NAV_CLOCK);
      m_nav.CapsuleStroke(modeX, 7, 30, 20, Mix(m_t.surface, m_t.dim, 0.40), Mix(m_t.surface, clrBlack, 0.10));
      m_nav.Text(modeX + 15, 11, (m_themeIdx % 2 == 1 ? "L" : "D"), A(m_t.text), RCS_F_LABEL, "Segoe UI", TA_CENTER | TA_TOP, FW_BOLD);
      ZAdd(m_navX + modeX, m_navY + 7, 30, 20, RZ_NAV_MODE);
      m_nav.CapsuleGradient(palX, 7, 38, 20, A(m_t.accent), A(m_t.accent2));
      m_nav.Text(palX + 19, 11, StringSubstr(m_t.name, 0, 4), Mix(m_t.bg, clrBlack, 0.35), RCS_F_SMALL, "Segoe UI", TA_CENTER | TA_TOP, FW_BOLD);
      ZAdd(m_navX + palX, m_navY + 7, 38, 20, RZ_NAV_PALETTE);
      // --- middle : health badge + vitals, dropped first on a narrow chart -
      const int midX = 174, midW = palX - 8 - midX;
      if(midW >= 150) {
         const color vc = VerdictC();
         m_nav.Capsule(midX, 7, 104, 20, Mix(m_t.surface, vc, 0.30));
         string hb = m_d.verdictWord + " " + IntegerToString(m_d.score) + "/100";
         m_nav.Text(midX + 52, 11, hb, A(vc), RCS_F_LABEL, "Segoe UI", TA_CENTER | TA_TOP, FW_BOLD);
         ZAdd(m_navX + midX, m_navY + 7, 104, 20, RZ_NAV_HEALTH);
         if(midW >= 260) {
            string vit = "$" + DoubleToString(m_d.equity, 2) + "  " +
                         IntegerToString(m_d.posCount) + " pos";
            m_nav.Text(midX + 116, 11, vit, A(m_t.dim), RCS_F_NUM, "Consolas", TA_LEFT | TA_TOP);
            ZAdd(m_navX + midX + 116, m_navY + 7, midW - 116, 20, RZ_NAV_VITALS);
         }
      }
      m_nav.Commit();
   }

   //================= RAIL (the only permanent surface) ====================
   void CellBG(const int y, const int h, const int sec) {
      if(!(m_state != 0 && m_sec == sec)) return;
      m_rail.RoundFill(4, y - 2, RCS_RAIL_W - 8, h, 9, Mix(m_t.surface, m_t.accent, 0.14));
   }
   void RenderRail(void) {
      if(!m_rail.Ready()) return;
      m_rail.Begin();
      const int W = RCS_RAIL_W, H = m_railH;
      m_rail.Card(1, 1, W - 2, H - 2, 12, MixC(m_t.surface, clrWhite, 0.03), m_t.surface, LineC());
      const color vc = VerdictC();
      m_rail.Capsule(W - 6, 32, 3, H - 42, Mix(m_t.surface, vc, 0.45));   // passive verdict echo
      // --- header band : chevron = full sidebar --------------------------
      m_rail.CapsuleGradient(6, 6, W - 12, 18, A(m_t.accent), A(m_t.accent2));
      m_rail.Text(W / 2, 8, (m_state == 2 ? ">" : "<"), Mix(m_t.bg, clrBlack, 0.5), RCS_F_BODY, "Segoe UI", TA_CENTER | TA_TOP, FW_BOLD);
      ZAdd(m_railX, m_railY + 4, W, 22, RZ_RAIL_CHEVRON);
      int cy, ch;
      // --- LIM : vertical gauge = worst consumption of the ACTIVE limits --
      cy = CellY(RZ_RAIL_LIM); ch = CellH(RZ_RAIL_LIM);
      CellBG(cy, ch, RZ_RAIL_LIM);
      double ratio = m_d.limRatio;
      if(ratio < 0.0) ratio = 0.0;
      if(ratio > 1.0) ratio = 1.0;
      const color rc = (ratio >= 1.0 ? m_t.red : (ratio >= 0.80 ? m_t.warn : m_t.ok));
      const int mx = W / 2 - 3, mh = 46;
      m_rail.Capsule(mx, cy + 2, 6, mh, A(TrackC()));
      const int fh = (int)(mh * ratio);
      if(fh > 1) m_rail.CapsuleGradient(mx, cy + 2 + (mh - fh), 6, fh, A(rc), Mix(rc, clrBlack, 0.25));
      // 80% survival marker (the v2.13 guard threshold)
      m_rail.Capsule(mx - 2, cy + 2 + (int)(mh * 0.20), 10, 2, Mix(TrackC(), m_t.text, 0.45));
      m_rail.Text(W / 2, cy + mh + 6, IntegerToString((int)(ratio * 100.0)) + "%", A(rc), RCS_F_NUM, "Consolas", TA_CENTER | TA_TOP, FW_BOLD);
      ZAdd(m_railX, m_railY + cy, W, ch, RZ_RAIL_LIM);
      // --- POS : open count + worst row status ---------------------------
      cy = CellY(RZ_RAIL_POS); ch = CellH(RZ_RAIL_POS);
      CellBG(cy, ch, RZ_RAIL_POS);
      const color pc = (m_d.posCount == 0 ? m_t.dim : StatC(m_d.posWorst));
      m_rail.Text(W / 2, cy + 2, IntegerToString(m_d.posCount), A(pc), RCS_F_BIG, "Consolas", TA_CENTER | TA_TOP, FW_BOLD);
      m_rail.Text(W / 2, cy + 28, "POS", A(m_t.dim), RCS_F_SMALL, "Segoe UI", TA_CENTER | TA_TOP, FW_BOLD);
      ZAdd(m_railX, m_railY + cy, W, ch, RZ_RAIL_POS);
      // --- LOT : the advisor lot (amber = capped, red = no room left) -----
      cy = CellY(RZ_RAIL_LOT); ch = CellH(RZ_RAIL_LOT);
      CellBG(cy, ch, RZ_RAIL_LOT);
      const color lc = (m_d.lotZero ? m_t.red : (m_d.lotCapped ? m_t.warn : m_t.accent));
      const string ls = (m_d.sugLot > 0.0 ? DoubleToString(m_d.sugLot, m_d.lotDigits) : "--");
      m_rail.Text(W / 2, cy + 6, ls, A(lc), RCS_F_BODY, "Consolas", TA_CENTER | TA_TOP, FW_BOLD);
      m_rail.Text(W / 2, cy + 28, "LOT", A(m_t.dim), RCS_F_SMALL, "Segoe UI", TA_CENTER | TA_TOP, FW_BOLD);
      ZAdd(m_railX, m_railY + cy, W, ch, RZ_RAIL_LOT);
      // --- NEWS : minutes to the next RESTRICTED event + source tick ------
      cy = CellY(RZ_RAIL_NEWS); ch = CellH(RZ_RAIL_NEWS);
      CellBG(cy, ch, RZ_RAIL_NEWS);
      if(m_d.newsHasEvt) {
         const color nc = (m_d.newsHigh ? m_t.red : m_t.warn);
         const string nm = (m_d.newsActive ? "ON" : IntegerToString(m_d.newsMins));
         m_rail.Text(W / 2, cy + 2, nm, A(nc), RCS_F_BIG, "Consolas", TA_CENTER | TA_TOP, FW_BOLD);
         m_rail.Text(W / 2, cy + 30, (m_d.newsActive ? "NEWS" : "MIN"), A(m_t.dim), RCS_F_SMALL, "Segoe UI", TA_CENTER | TA_TOP, FW_BOLD);
      } else {
         m_rail.CapsuleStroke(W / 2 - 5, cy + 8, 10, 10, Mix(m_t.surface, m_t.dim, 0.45), Mix(m_t.surface, clrBlack, 0.06));
         m_rail.Text(W / 2, cy + 30, "NEWS", A(m_t.dim), RCS_F_SMALL, "Segoe UI", TA_CENTER | TA_TOP, FW_BOLD);
      }
      m_rail.Text(W / 2, cy + 42, (m_d.newsFF ? "FF" : "MT"), A(m_d.newsFF ? m_t.accent : m_t.dim), RCS_F_SMALL, "Segoe UI", TA_CENTER | TA_TOP);
      ZAdd(m_railX, m_railY + cy, W, ch, RZ_RAIL_NEWS);
      // --- DISC : lock / SL guard / tilt / trades today -------------------
      cy = CellY(RZ_RAIL_DISC); ch = CellH(RZ_RAIL_DISC);
      CellBG(cy, ch, RZ_RAIL_DISC);
      if(m_d.discLocked) {
         m_rail.CapsuleGradient(W / 2 - 8, cy + 4, 16, 14, A(m_t.red), Mix(m_t.red, clrBlack, 0.30));
         m_rail.Text(W / 2, cy + 22, "LOCK", A(m_t.red), RCS_F_SMALL, "Segoe UI", TA_CENTER | TA_TOP, FW_BOLD);
      } else if(m_d.slGuard) {
         m_rail.CapsuleStroke(W / 2 - 8, cy + 4, 16, 14, A(m_t.red), Mix(m_t.surface, m_t.red, 0.20));
         m_rail.Text(W / 2, cy + 22, "SL!", A(m_t.red), RCS_F_SMALL, "Segoe UI", TA_CENTER | TA_TOP, FW_BOLD);
      } else if(m_d.discTilt) {
         m_rail.CapsuleStroke(W / 2 - 8, cy + 4, 16, 14, A(m_t.warn), Mix(m_t.surface, m_t.warn, 0.18));
         m_rail.Text(W / 2, cy + 22, "TILT", A(m_t.warn), RCS_F_SMALL, "Segoe UI", TA_CENTER | TA_TOP, FW_BOLD);
      } else {
         m_rail.CapsuleStroke(W / 2 - 8, cy + 4, 16, 14, Mix(m_t.surface, m_t.dim, 0.50), Mix(m_t.surface, clrBlack, 0.06));
         m_rail.Text(W / 2, cy + 22, IntegerToString(m_d.tradesToday) + "t", A(m_t.dim), RCS_F_SMALL, "Consolas", TA_CENTER | TA_TOP, FW_BOLD);
      }
      m_rail.Text(W / 2, cy + 34, "DISC", A(m_t.dim), RCS_F_SMALL, "Segoe UI", TA_CENTER | TA_TOP);
      ZAdd(m_railX, m_railY + cy, W, ch, RZ_RAIL_DISC);
      // --- CPT : account size + plan tag ---------------------------------
      cy = CellY(RZ_RAIL_CPT); ch = CellH(RZ_RAIL_CPT);
      CellBG(cy, ch, RZ_RAIL_CPT);
      m_rail.Text(W / 2, cy + 4, m_d.sizeTag, A(m_t.text), RCS_F_BODY, "Consolas", TA_CENTER | TA_TOP, FW_BOLD);
      m_rail.Text(W / 2, cy + 22, m_d.planTag, A(m_t.accent), RCS_F_SMALL, "Segoe UI", TA_CENTER | TA_TOP, FW_BOLD);
      m_rail.Text(W / 2, cy + 34, "CPT", A(m_t.dim), RCS_F_SMALL, "Segoe UI", TA_CENTER | TA_TOP);
      ZAdd(m_railX, m_railY + cy, W, ch, RZ_RAIL_CPT);
      // --- CFG -----------------------------------------------------------
      cy = CellY(RZ_RAIL_CFG); ch = CellH(RZ_RAIL_CFG);
      CellBG(cy, ch, RZ_RAIL_CFG);
      m_rail.Text(W / 2, cy + 4, ShortToString((ushort)0x2699), A(m_t.dim), RCS_F_BTN, "Segoe UI Symbol", TA_CENTER | TA_TOP);
      m_rail.Text(W / 2, cy + 26, "CFG", A(m_t.dim), RCS_F_SMALL, "Segoe UI", TA_CENTER | TA_TOP, FW_BOLD);
      ZAdd(m_railX, m_railY + cy, W, ch, RZ_RAIL_CFG);
      // --- HELP ----------------------------------------------------------
      cy = CellY(RZ_RAIL_HELP); ch = CellH(RZ_RAIL_HELP);
      CellBG(cy, ch, RZ_RAIL_HELP);
      m_rail.Text(W / 2, cy + 2, "?", A(m_t.dim), RCS_F_BTN, "Segoe UI", TA_CENTER | TA_TOP, FW_BOLD);
      m_rail.Text(W / 2, cy + 24, "AIDE", A(m_t.dim), RCS_F_SMALL, "Segoe UI", TA_CENTER | TA_TOP, FW_BOLD);
      ZAdd(m_railX, m_railY + cy, W, ch, RZ_RAIL_HELP);
      m_rail.Commit();
   }

   //================= DEPLOYED PANEL =======================================
   string SectionTitle(const int sec) const {
      switch(sec) {
         case RZ_RAIL_LIM:  return "LIMITES";
         case RZ_RAIL_POS:  return "POSITIONS";
         case RZ_RAIL_LOT:  return "LOT CONSEILLE";
         case RZ_RAIL_NEWS: return "NEWS";
         case RZ_RAIL_DISC: return "DISCIPLINE";
         case RZ_RAIL_CPT:  return "COMPTE";
         case RZ_RAIL_CFG:  return "REGLAGES";
         case RZ_RAIL_HELP: return "AIDE";
      }
      return "";
   }
   void SecHead(const string s, int &y) {
      m_side.Text(18, y, s, A(m_t.accent), RCS_F_LABEL, "Segoe UI", TA_LEFT | TA_TOP, FW_BOLD);
      y += 15;
      m_side.Hairline(18, y, RCS_SIDE_W - 18, LineC());
      y += 9;
   }
   //--- one metered rule row : label, bar, value, status dot ---------------
   int LimRow(int y, const string k, const double v, const double cap, const bool applies, const int zid) {
      const double ratio = (applies && cap > 0.0 ? v / cap : 0.0);
      const color st = (!applies ? m_t.dim : (ratio >= 1.0 ? m_t.red : (ratio >= 0.80 ? m_t.warn : m_t.ok)));
      m_side.Text(18, y, k, A(m_t.text), RCS_F_BODY, "Segoe UI", TA_LEFT | TA_TOP);
      const string val = (applies ? DoubleToString(v, 2) + " / " + DoubleToString(cap, 1) + "%" : "N/A");
      m_side.Text(RCS_SIDE_W - 18, y, val, A(applies ? m_t.text : m_t.dim), RCS_F_NUM, "Consolas", TA_RIGHT | TA_TOP);
      y += 17;
      m_side.Meter(18, y, RCS_SIDE_W - 36, 8, (ratio > 1.0 ? 1.0 : ratio), TrackC(), st, MixC(st, clrBlack, 0.25));
      ZAdd(m_sideX + 18, m_sideY + y - 17, RCS_SIDE_W - 36, 26, zid);
      y += 18;
      return y;
   }
   int SecLimits(int y) {
      SecHead(L(RCL_LIM_HEAD, "CONSOMMATION DES LIMITES"), y);
      y = LimRow(y, L(RCL_LIM_MARGIN, "Marge cumulee"),  m_d.marginPct,  m_d.marginCap,  true,                 RZ_TIP_LIM_M0);
      y = LimRow(y, L(RCL_LIM_RISK, "Risque ouvert"),  m_d.riskPct,    m_d.riskCap,    m_d.riskCap > 0.0,    RZ_TIP_LIM_M1);
      y = LimRow(y, L(RCL_LIM_DAILY, "DD journalier"),  m_d.dailyPct,   m_d.dailyCap,   m_d.dailyApplies,     RZ_TIP_LIM_M2);
      y = LimRow(y, L(RCL_LIM_OVERALL, "DD total"),       m_d.overallPct, m_d.overallCap, m_d.overallApplies,   RZ_TIP_LIM_M3);
      // v3.01 parity : Quick Strike is a RULE too - it belongs with the meters.
      if(m_d.qsCap > 0.0)
         y = LimRow(y, L(RCL_LIM_QS, "Quick Strike"), m_d.qsPct, m_d.qsCap, true, RZ_TIP_LIM_QS);
      y += 6;
      SecHead(L(RCL_SURV_HEAD, "MARGE DE SURVIE"), y);
      if(m_d.roomMoney >= 0.0) {
         const color rcol = (m_d.limRatio >= 1.0 ? m_t.red : (m_d.limRatio >= 0.80 ? m_t.warn : m_t.ok));
         m_side.Text(18, y, L(RCL_ROOM, "Marge avant limite"), A(m_t.dim), RCS_F_BODY, "Segoe UI", TA_LEFT | TA_TOP);
         m_side.Text(RCS_SIDE_W - 18, y - 3, DoubleToString(m_d.roomMoney, 2) + " $", A(rcol), RCS_F_TITLE, "Consolas", TA_RIGHT | TA_TOP, FW_BOLD);
         ZAdd(m_sideX + 18, m_sideY + y - 4, RCS_SIDE_W - 36, 22, RZ_TIP_LIM_ROOM);
         y += 22;
         m_side.Text(18, y, L(RCL_BUDGET80, "Budget d'un trade (80%)"), A(m_t.dim), RCS_F_LABEL, "Segoe UI", TA_LEFT | TA_TOP);
         m_side.Text(RCS_SIDE_W - 18, y, DoubleToString(0.80 * m_d.roomMoney, 2) + " $", A(m_t.text), RCS_F_NUM, "Consolas", TA_RIGHT | TA_TOP);
         y += 18;
      } else {
         m_side.Text(18, y, L(RCL_NOLIMIT, "Aucune limite active sur ce profil."), A(m_t.dim), RCS_F_BODY, "Segoe UI", TA_LEFT | TA_TOP);
         y += 20;
      }
      if(m_d.trailing) {
         m_side.Text(18, y, L(RCL_FLOOR, "Plancher (trailing)"), A(m_t.dim), RCS_F_BODY, "Segoe UI", TA_LEFT | TA_TOP);
         m_side.Text(RCS_SIDE_W - 18, y, DoubleToString(m_d.floorMoney, 2) + " $", A(m_t.text), RCS_F_NUM, "Consolas", TA_RIGHT | TA_TOP);
         ZAdd(m_sideX + 18, m_sideY + y - 2, RCS_SIDE_W - 36, 20, RZ_TIP_LIM_FLOOR);
         y += 18;
         m_side.Text(18, y, "Equity sous ce niveau = compte perdu.", A(m_t.dim), RCS_F_SMALL, "Segoe UI", TA_LEFT | TA_TOP);
         y += 16;
      }
      return y;
   }
   //--- POSITIONS : one row per open trade, honest truncation past 8 ---------
   int SecPositions(int y) {
      SecHead(L(RCL_SEC_POS, "POSITIONS OUVERTES"), y);
      if(m_d.posCount <= 0) {
         m_side.Text(18, y, L(RCL_POS_NONE, "Aucune position ouverte."), A(m_t.dim), RCS_F_BODY, "Segoe UI", TA_LEFT | TA_TOP);
         return y + 20;
      }
      for(int i = 0; i < m_d.posN && i < 8; i++) {
         const color st = StatC(m_d.posStat[i]);
         m_side.Capsule(18, y + 5, 6, 6, A(st));
         m_side.Text(30, y, m_d.posSym[i] + " " + m_d.posSide[i] + " " + DoubleToString(m_d.posVol[i], 2),
                     A(m_t.text), RCS_F_BODY, "Consolas", TA_LEFT | TA_TOP);
         const color pnlc = (m_d.posRowPnl[i] >= 0.0 ? m_t.ok : m_t.red);
         m_side.Text(RCS_SIDE_W - 18, y, (m_d.posRowPnl[i] >= 0.0 ? "+" : "") + DoubleToString(m_d.posRowPnl[i], 2),
                     A(pnlc), RCS_F_NUM, "Consolas", TA_RIGHT | TA_TOP);
         y += 15;
         string sub = IntegerToString(m_d.posAge[i] / 60) + " min";
         if(!m_d.posHasSl[i]) sub += "   " + L(RCL_NOSL, "SANS SL");
         m_side.Text(30, y, sub, A(m_d.posHasSl[i] ? m_t.dim : m_t.red), RCS_F_SMALL, "Segoe UI", TA_LEFT | TA_TOP);
         ZAdd(m_sideX + 18, m_sideY + y - 15, RCS_SIDE_W - 36, 28, RZ_POS_ROW0 + i);
         y += 16;
      }
      if(m_d.posCount > m_d.posN) {
         m_side.Text(18, y, "+" + IntegerToString(m_d.posCount - m_d.posN) + " autres : agrandis la fenetre",
                     A(m_t.dim), RCS_F_SMALL, "Segoe UI", TA_LEFT | TA_TOP);
         y += 16;
      }
      y += 4;
      m_side.Text(18, y, L(RCL_POS_PNL, "P&L flottant total"), A(m_t.dim), RCS_F_BODY, "Segoe UI", TA_LEFT | TA_TOP);
      m_side.Text(RCS_SIDE_W - 18, y - 2, (m_d.posPnl >= 0.0 ? "+" : "") + DoubleToString(m_d.posPnl, 2) + " $",
                  A(m_d.posPnl >= 0.0 ? m_t.ok : m_t.red), RCS_F_TITLE, "Consolas", TA_RIGHT | TA_TOP, FW_BOLD);
      return y + 22;
   }
   //--- LOT ADVISOR : the number JR copies, and WHY it is that number --------
   int SecLot(int y) {
      SecHead(L(RCL_SEC_LOT, "LOT CONSEILLE"), y);
      const color lc = (m_d.lotZero ? m_t.red : (m_d.lotCapped ? m_t.warn : m_t.accent));
      m_side.Text(18, y, (m_d.sugLot > 0.0 ? DoubleToString(m_d.sugLot, m_d.lotDigits) : "--"),
                  A(lc), RCS_F_BIG, "Consolas", TA_LEFT | TA_TOP, FW_BOLD);
      // COPY-LOT : the value has to be COPYABLE (Ctrl+C into the order ticket),
      // and only a native OBJ_EDIT can be selected. The shell reserves the rect
      // and registers a NO-OP zone on it (a click there must never collapse the
      // section) ; the host creates and fills the control - see LotEditRect().
      m_lotEditOn = (m_d.sugLot > 0.0);
      if(m_lotEditOn) {
         m_lotEditW = 76; m_lotEditH = 20;
         m_lotEditX = m_sideX + RCS_SIDE_W - 18 - m_lotEditW;
         m_lotEditY = m_sideY + y - 2;
         m_side.Text(RCS_SIDE_W - 18 - m_lotEditW - 8, y + 3, L(RCL_LOT_COPY, "copier"),
                     A(m_t.dim), RCS_F_SMALL, "Segoe UI", TA_RIGHT | TA_TOP);
         ZAdd(m_lotEditX - 2, m_lotEditY - 2, m_lotEditW + 4, m_lotEditH + 4, RZ_LOT_EDIT);
      } else {
         m_side.Text(RCS_SIDE_W - 18, y + 6, "lot", A(m_t.dim), RCS_F_SMALL, "Segoe UI", TA_RIGHT | TA_TOP);
      }
      y += 30;
      if(m_d.lotCapped) {
         m_side.Text(18, y, (m_d.lotZero ? "Aucune marge : ne prends pas ce trade."
                                         : "Plafonne a 80% de la marge de survie."),
                     A(m_d.lotZero ? m_t.red : m_t.warn), RCS_F_SMALL, "Segoe UI", TA_LEFT | TA_TOP);
         ZAdd(m_sideX + 18, m_sideY + y - 2, RCS_SIDE_W - 36, 18, RZ_TIP_LOT_CAP);
         y += 18;
      }
      SecHead(L(RCL_LOT_FROM, "D'OU VIENT CE LOT"), y);
      m_side.Text(18, y, L(RCL_LOT_BUDGET, "Budget du trade"), A(m_t.dim), RCS_F_BODY, "Segoe UI", TA_LEFT | TA_TOP);
      m_side.Text(RCS_SIDE_W - 18, y, DoubleToString(m_d.budgetPct, 2) + "%  " +
                  DoubleToString(m_d.budgetMoney, 2) + " $", A(m_t.text), RCS_F_NUM, "Consolas", TA_RIGHT | TA_TOP);
      ZAdd(m_sideX + 18, m_sideY + y - 2, RCS_SIDE_W - 36, 18, RZ_TIP_LOT_BUD);
      y += 18;
      m_side.Text(18, y, L(RCL_LOT_N, "Trades prevus (N)"), A(m_t.dim), RCS_F_BODY, "Segoe UI", TA_LEFT | TA_TOP);
      m_side.Text(RCS_SIDE_W - 18, y, IntegerToString(m_d.nPlanned), A(m_t.text), RCS_F_NUM, "Consolas", TA_RIGHT | TA_TOP);
      y += 18;
      m_side.Text(18, y, L(RCL_LOT_FREE, "Marge libre"), A(m_t.dim), RCS_F_BODY, "Segoe UI", TA_LEFT | TA_TOP);
      m_side.Text(RCS_SIDE_W - 18, y, DoubleToString(m_d.freeMarginPct, 0) + "%", A(m_t.text), RCS_F_NUM, "Consolas", TA_RIGHT | TA_TOP);
      ZAdd(m_sideX + 18, m_sideY + y - 2, RCS_SIDE_W - 36, 18, RZ_TIP_LOT_FREE);
      // v3.01 parity : "Max lot allowed" - the biggest lot the caps still allow,
      // and WHICH cap binds (target margin / cumulative room / broker free margin).
      if(m_d.maxLot >= 0.0) {
         string mx = DoubleToString(m_d.maxLot, m_d.maxLotDigits) + "  @ " +
                     DoubleToString(m_d.maxLotPct, 1) + "% " +
                     (m_d.maxLotTag == "marg" ? L(RCL_TAG_MARG, "marge")
                      : (m_d.maxLotTag == "room" ? L(RCL_TAG_ROOM, "reste") : L(RCL_TAG_FREE, "libre")));
         y = KV(y, L(RCL_LOT_MAX, "Lot max autorise"), mx,
                (m_d.maxLot <= 0.0 ? m_t.warn : m_t.text), RZ_TIP_MAXLOT);
      }
      y += 4;
      SecHead(L(RCL_LOT_COST, "COUT DU SYMBOLE"), y);
      m_side.Text(18, y, L(RCL_SPREAD, "Spread"), A(m_t.dim), RCS_F_BODY, "Segoe UI", TA_LEFT | TA_TOP);
      m_side.Text(RCS_SIDE_W - 18, y, DoubleToString(m_d.spreadPts, 0) + " pts", A(m_t.text), RCS_F_NUM, "Consolas", TA_RIGHT | TA_TOP);
      y += 18;
      m_side.Text(18, y, L(RCL_COMM, "Commission / lot"), A(m_t.dim), RCS_F_BODY, "Segoe UI", TA_LEFT | TA_TOP);
      m_side.Text(RCS_SIDE_W - 18, y, (m_d.commPerLot >= 0.0 ? DoubleToString(m_d.commPerLot, 2) + " $" : "n/a"),
                  A(m_t.text), RCS_F_NUM, "Consolas", TA_RIGHT | TA_TOP);
      return y + 20;
   }
   //--- NEWS : the RULE (red) vs the VIGILANCE (amber), and the source ------
   int SecNews(int y) {
      SecHead(L(RCL_SEC_NEWS, "FENETRE NEWS"), y);
      m_side.Text(18, y, L(RCL_NEWS_SRC, "Source"), A(m_t.dim), RCS_F_BODY, "Segoe UI", TA_LEFT | TA_TOP);
      m_side.Text(RCS_SIDE_W - 18, y, (m_d.newsFF ? "ForexFactory [FF]" : "Calendrier MT5 [MT]"),
                  A(m_d.newsFF ? m_t.accent : m_t.dim), RCS_F_NUM, "Consolas", TA_RIGHT | TA_TOP);
      ZAdd(m_sideX + 18, m_sideY + y - 2, RCS_SIDE_W - 36, 18, RZ_TIP_NEWS_SRC);
      y += 18;
      m_side.Text(18, y, L(RCL_NEWS_STATE, "Etat"), A(m_t.dim), RCS_F_BODY, "Segoe UI", TA_LEFT | TA_TOP);
      string st = "inactive";
      color  sc = m_t.dim;
      if(m_d.newsActive)      { st = "ACTIVE - profit eligible " + DoubleToString(m_d.newsSharePct, 0) + "%"; sc = m_t.red; }
      else if(m_d.newsHasEvt) { st = "dans " + IntegerToString(m_d.newsMins) + " min"; sc = (m_d.newsHigh ? m_t.red : m_t.warn); }
      m_side.Text(RCS_SIDE_W - 18, y, st, A(sc), RCS_F_NUM, "Consolas", TA_RIGHT | TA_TOP);
      ZAdd(m_sideX + 18, m_sideY + y - 2, RCS_SIDE_W - 36, 18, RZ_TIP_NEWS_RULE);
      y += 18;
      m_side.Text(18, y, L(RCL_NEWS_WIN, "Fenetre"), A(m_t.dim), RCS_F_BODY, "Segoe UI", TA_LEFT | TA_TOP);
      m_side.Text(RCS_SIDE_W - 18, y, "+/- " + IntegerToString(m_d.newsWinMin) + " min", A(m_t.text), RCS_F_NUM, "Consolas", TA_RIGHT | TA_TOP);
      y += 20;
      // v3.01 parity : the news-window METER (legacy row 8) - it fills over the
      // hour before the event and sits full while the window is open.
      m_side.Meter(18, y, RCS_SIDE_W - 36, 8, m_d.newsMeterPct / 100.0, TrackC(),
                   (m_d.newsActive ? m_t.red : m_t.warn), MixC((m_d.newsActive ? m_t.red : m_t.warn), clrBlack, 0.25));
      y += 16;
      // v3.01 parity : news-trading stats (legacy row 10)
      y = KV(y, L(RCL_NEWSTRADES, "Trades news"),
             IntegerToString(m_d.newsTrades) + "t  " +
             (m_d.newsPnl >= 0.0 ? "+" : "") + DoubleToString(m_d.newsPnl, 2) + " $  " +
             L(RCL_ELIG, "elig") + " " + (m_d.newsEligible >= 0.0 ? "+" : "") + DoubleToString(m_d.newsEligible, 2),
             m_t.text, RZ_TIP_NEWSTR);
      y += 4;
      SecHead(L(RCL_NEWS_NEXT, "A VENIR"), y);
      if(m_d.newsN <= 0) {
         m_side.Text(18, y, "Rien dans les 24 h.", A(m_t.dim), RCS_F_BODY, "Segoe UI", TA_LEFT | TA_TOP);
         return y + 20;
      }
      for(int i = 0; i < m_d.newsN && i < 6; i++) {
         const color nc = (m_d.newsRestr[i] ? m_t.red : m_t.warn);
         m_side.Text(18, y, ShortToString((ushort)(m_d.newsRestr[i] ? 0x25BC : 0x25C6)), A(nc), RCS_F_SMALL, "Segoe UI", TA_LEFT | TA_TOP);
         m_side.Text(36, y, m_d.newsWhen[i] + "  " + m_d.newsCcy[i], A(m_t.text), RCS_F_NUM, "Consolas", TA_LEFT | TA_TOP);
         m_side.Text(RCS_SIDE_W - 18, y, (m_d.newsRestr[i] ? "regle 40%" : "verifier FN"),
                     A(nc), RCS_F_SMALL, "Segoe UI", TA_RIGHT | TA_TOP);
         y += 17;
      }
      ZAdd(m_sideX + 18, m_sideY + y - 17 * m_d.newsN, RCS_SIDE_W - 36, 17 * m_d.newsN, RZ_TIP_NEWS_LIST);
      return y + 4;
   }
   //--- DISCIPLINE : what is blocking, what is warning, what to do ----------
   int SecDiscipline(int y) {
      SecHead(L(RCL_DISC_STATE, "ETAT"), y);
      string line; color lcol;
      if(m_d.discLocked)   { line = "VERROU ACTIF"; lcol = m_t.red; }
      else if(m_d.slGuard) { line = "GARDE SL DECLENCHEE"; lcol = m_t.red; }
      else if(m_d.discTilt){ line = "TILT DETECTE"; lcol = m_t.warn; }
      else                 { line = "RAS"; lcol = m_t.ok; }
      m_side.Text(18, y, line, A(lcol), RCS_F_TITLE, "Segoe UI", TA_LEFT | TA_TOP, FW_BOLD);
      y += 24;
      if(m_d.discLocked) {
         m_side.Text(18, y, (m_d.selfLock ? "Self-lock (Ulysse)" : "Verrou journalier"), A(m_t.dim), RCS_F_BODY, "Segoe UI", TA_LEFT | TA_TOP);
         m_side.Text(RCS_SIDE_W - 18, y, (m_d.lockMinsLeft > 0 ? IntegerToString(m_d.lockMinsLeft) + " min" : "actif"),
                     A(m_t.red), RCS_F_NUM, "Consolas", TA_RIGHT | TA_TOP);
         ZAdd(m_sideX + 18, m_sideY + y - 2, RCS_SIDE_W - 36, 18, RZ_TIP_DISC_LOCK);
         y += 20;
      }
      if(m_d.slGuard) {
         m_side.Text(18, y, "Remonte la SL", A(m_t.dim), RCS_F_BODY, "Segoe UI", TA_LEFT | TA_TOP);
         m_side.Text(RCS_SIDE_W - 18, y, (m_d.slGuardSym != "" && m_d.slGuardPrice > 0.0
                     ? m_d.slGuardSym + " >= " + DoubleToString(m_d.slGuardPrice, (m_d.slGuardPrice >= 100.0 ? 2 : 5)) : "position sans SL"),
                     A(m_t.red), RCS_F_NUM, "Consolas", TA_RIGHT | TA_TOP);
         ZAdd(m_sideX + 18, m_sideY + y - 2, RCS_SIDE_W - 36, 18, RZ_TIP_DISC_SL);
         y += 18;
         m_side.Text(18, y, "Objectif : garder 20% de marge.", A(m_t.dim), RCS_F_SMALL, "Segoe UI", TA_LEFT | TA_TOP);
         y += 18;
      }
      y += 4;
      SecHead(L(RCL_DISC_DAY, "ACTIVITE DU JOUR"), y);
      m_side.Text(18, y, "Trades", A(m_t.dim), RCS_F_BODY, "Segoe UI", TA_LEFT | TA_TOP);
      m_side.Text(RCS_SIDE_W - 18, y, IntegerToString(m_d.tradesToday) +
                  (m_d.tradesCap > 0 ? " / " + IntegerToString(m_d.tradesCap) : ""),
                  A(m_t.text), RCS_F_NUM, "Consolas", TA_RIGHT | TA_TOP);
      y += 18;
      m_side.Text(18, y, "Fenetre tilt", A(m_t.dim), RCS_F_BODY, "Segoe UI", TA_LEFT | TA_TOP);
      m_side.Text(RCS_SIDE_W - 18, y, IntegerToString(m_d.tiltTrades) + " en " +
                  IntegerToString(m_d.tiltWinMin) + " min" + (m_d.tiltN > 0 ? "  (max " + IntegerToString(m_d.tiltN) + ")" : ""),
                  A(m_d.discTilt ? m_t.warn : m_t.text), RCS_F_NUM, "Consolas", TA_RIGHT | TA_TOP);
      ZAdd(m_sideX + 18, m_sideY + y - 2, RCS_SIDE_W - 36, 18, RZ_TIP_DISC_TILT);
      y += 18;
      // v3.01 parity : hyperactivity + server messages, the two "too much
      // activity" rules the prop firm scores - they belong with discipline.
      if(m_d.tradesCap > 0) {
         const double hy = 100.0 * m_d.tradesToday / m_d.tradesCap;
         y = LimRow(y, L(RCL_HYPER, "Hyperactivite"), hy, 100.0, true, RZ_NONE);
      }
      if(m_d.msgsCap > 0) {
         const double mp = 100.0 * m_d.msgsToday / m_d.msgsCap;
         m_side.Text(18, y, L(RCL_MSGS, "Msgs serveur (ordres)"), A(m_t.dim), RCS_F_BODY, "Segoe UI", TA_LEFT | TA_TOP);
         m_side.Text(RCS_SIDE_W - 18, y, IntegerToString(m_d.msgsToday) + " / " + IntegerToString(m_d.msgsCap),
                     A(mp >= 100.0 ? m_t.red : (mp >= 75.0 ? m_t.warn : m_t.text)), RCS_F_NUM, "Consolas", TA_RIGHT | TA_TOP);
         ZAdd(m_sideX + 18, m_sideY + y - 2, RCS_SIDE_W - 36, 18, RZ_TIP_MSGS);
         y += 18;
      }
      return y + 6;
   }
   //--- one "label ....... value" row (the panel's workhorse) ---------------
   int KV(int y, const string k, const string v, const color vc, const int zid = RZ_NONE) {
      m_side.Text(18, y, k, A(m_t.dim), RCS_F_BODY, "Segoe UI", TA_LEFT | TA_TOP);
      m_side.Text(RCS_SIDE_W - 18, y, v, A(vc), RCS_F_NUM, "Consolas", TA_RIGHT | TA_TOP);
      if(zid != RZ_NONE) ZAdd(m_sideX + 18, m_sideY + y - 2, RCS_SIDE_W - 36, 18, zid);
      return y + 18;
   }
   //--- a clickable ON/OFF row : the pill IS the control --------------------
   int Toggle(int y, const string k, const bool on, const int zid) {
      m_side.Text(18, y, k, A(m_t.text), RCS_F_BODY, "Segoe UI", TA_LEFT | TA_TOP);
      const int px = RCS_SIDE_W - 18 - 34;
      if(on) m_side.CapsuleGradient(px, y, 34, 16, A(m_t.accent), A(m_t.accent2));
      else   m_side.CapsuleStroke(px, y, 34, 16, Mix(m_t.surface, m_t.dim, 0.45), Mix(m_t.surface, clrBlack, 0.10));
      m_side.Capsule(on ? px + 20 : px + 3, y + 3, 10, 10, A(on ? m_t.bg : m_t.dim));
      ZAdd(m_sideX + 18, m_sideY + y - 2, RCS_SIDE_W - 36, 20, zid);
      return y + 22;
   }
   //--- [-] value [+] : the shell only ASKS, the host owns every setting -----
   int Stepper(int y, const string k, const string v, const int row) {
      m_side.Text(18, y + 3, k, A(m_t.text), RCS_F_BODY, "Segoe UI", TA_LEFT | TA_TOP);
      const int bw = 22, vx = RCS_SIDE_W - 18 - bw, dx = RCS_SIDE_W - 18 - bw - 66 - bw;
      m_side.CapsuleStroke(dx, y, bw, 20, Mix(m_t.surface, m_t.dim, 0.40), Mix(m_t.surface, clrBlack, 0.08));
      m_side.Text(dx + bw / 2, y + 3, "-", A(m_t.text), RCS_F_BODY, "Segoe UI", TA_CENTER | TA_TOP, FW_BOLD);
      ZAdd(m_sideX + dx, m_sideY + y, bw, 20, RZ_STEP_DEC0 + row);
      m_side.Text(dx + bw + 33, y + 3, v, A(m_t.accent), RCS_F_NUM, "Consolas", TA_CENTER | TA_TOP, FW_BOLD);
      m_side.CapsuleStroke(vx, y, bw, 20, Mix(m_t.surface, m_t.dim, 0.40), Mix(m_t.surface, clrBlack, 0.08));
      m_side.Text(vx + bw / 2, y + 3, "+", A(m_t.text), RCS_F_BODY, "Segoe UI", TA_CENTER | TA_TOP, FW_BOLD);
      ZAdd(m_sideX + vx, m_sideY + y, bw, 20, RZ_STEP_INC0 + row);
      return y + 24;
   }
   //--- < value > : one step of the plan cascade ----------------------------
   int Cycler(int y, const string k, const string v, const int row) {
      m_side.Text(18, y + 3, k, A(m_t.text), RCS_F_BODY, "Segoe UI", TA_LEFT | TA_TOP);
      const int bw = 20, nx = RCS_SIDE_W - 18 - bw, px = 150;
      m_side.CapsuleStroke(px, y, bw, 20, Mix(m_t.surface, m_t.dim, 0.40), Mix(m_t.surface, clrBlack, 0.08));
      m_side.Text(px + bw / 2, y + 3, "<", A(m_t.text), RCS_F_BODY, "Segoe UI", TA_CENTER | TA_TOP, FW_BOLD);
      ZAdd(m_sideX + px, m_sideY + y, bw, 20, RZ_CAS_PREV0 + row);
      string vv = v;
      if(StringLen(vv) > 14) vv = StringSubstr(vv, 0, 13) + "..";
      m_side.Text((px + bw + nx) / 2, y + 3, vv, A(m_t.accent), RCS_F_LABEL, "Segoe UI", TA_CENTER | TA_TOP, FW_BOLD);
      m_side.CapsuleStroke(nx, y, bw, 20, Mix(m_t.surface, m_t.dim, 0.40), Mix(m_t.surface, clrBlack, 0.08));
      m_side.Text(nx + bw / 2, y + 3, ">", A(m_t.text), RCS_F_BODY, "Segoe UI", TA_CENTER | TA_TOP, FW_BOLD);
      ZAdd(m_sideX + nx, m_sideY + y, bw, 20, RZ_CAS_NEXT0 + row);
      return y + 24;
   }

   //--- COMPTE : the profile the whole risk model is resolved from ----------
   int SecAccount(int y) {
      // v3.02 : the CASCADE is editable here - broker -> type -> phase -> size
      // -> account type. Every limit in the product is resolved from it, so it
      // sits at the TOP of the section and drives a full re-resolve on click.
      SecHead(L(RCL_CPT_PROFILE, "PROFIL"), y);
      for(int i = 0; i < m_d.casN && i < 5; i++)
         y = Cycler(y, m_d.casLabel[i], m_d.casValue[i], i);
      y += 6;
      SecHead(L(RCL_SEC_CPT, "COMPTE"), y);
      y = KV(y, L(RCL_CPT_SPLIT, "Split"), IntegerToString(m_d.splitPct) + "%", m_t.text, RZ_TIP_CPT);
      if(m_d.minDays > 0)
         y = KV(y, L(RCL_CPT_DAYS, "Jours mini"),
                IntegerToString(m_d.minDaysDone) + " / " + IntegerToString(m_d.minDays),
                (m_d.minDaysDone >= m_d.minDays ? m_t.ok : m_t.warn));
      y = KV(y, "Compte", IntegerToString((int)m_d.login), m_t.dim);
      // v3.01 parity : profit target - on a trailing (Instant) profile it is the
      // PAYOUT eligibility threshold, not a challenge target to pass.
      if(m_d.targetCap > 0.0) {
         const double tr = m_d.targetPct / m_d.targetCap;
         y += 4;
         m_side.Text(18, y, L(m_d.trailing ? RCL_PAYOUT : RCL_TARGET,
                              m_d.trailing ? "Eligibilite payout" : "Objectif profit"),
                     A(m_t.dim), RCS_F_BODY, "Segoe UI", TA_LEFT | TA_TOP);
         m_side.Text(RCS_SIDE_W - 18, y, DoubleToString(m_d.targetPct, 2) + " / " +
                     DoubleToString(m_d.targetCap, 1) + "%",
                     A(tr >= 1.0 ? m_t.ok : m_t.text), RCS_F_NUM, "Consolas", TA_RIGHT | TA_TOP);
         ZAdd(m_sideX + 18, m_sideY + y - 2, RCS_SIDE_W - 36, 18, RZ_TIP_TARGET);
         y += 17;
         m_side.Meter(18, y, RCS_SIDE_W - 36, 8, (tr > 1.0 ? 1.0 : tr), TrackC(),
                      (tr >= 1.0 ? m_t.ok : m_t.accent), MixC(tr >= 1.0 ? m_t.ok : m_t.accent, clrBlack, 0.25));
         y += 16;
      }
      y += 6;
      SecHead(L(RCL_CPT_ADDONS, "ADD-ONS"), y);
      m_side.Text(18, y, (StringLen(m_d.addonsLabel) > 0 ? m_d.addonsLabel : "-"),
                  A(m_t.text), RCS_F_SMALL, "Segoe UI", TA_LEFT | TA_TOP);
      y += 18;
      if(StringLen(m_d.cycleLabel) > 0) y = KV(y, "Cycle", m_d.cycleLabel, m_t.dim);
      return y + 6;
   }
   //--- REGLAGES : the toggles that matter day to day ----------------------
   int SecConfig(int y) {
      // v3.02 : four sub-tabs so the 18 tunables fit without scrolling. The
      // shell only draws them : the host owns the keys, the steps and the
      // persistence (the same ones the legacy modal writes).
      {
         const int tw = (RCS_SIDE_W - 36) / 4;
         string tabs[4]; tabs[0] = L(RCL_TAB_RISK, "RISQUE"); tabs[1] = L(RCL_TAB_DISC, "DISCIPLINE");
         tabs[2] = L(RCL_TAB_ADV, "AVANCE");  tabs[3] = L(RCL_TAB_DISP, "AFFICHAGE");
         m_side.CapsuleStroke(18, y, RCS_SIDE_W - 36, 22, A(LineC()), Mix(m_t.surface, clrBlack, 0.06));
         for(int t = 0; t < 4; t++) {
            const bool on = (m_cfgTab == t);
            if(on) m_side.CapsuleGradient(20 + t * tw, y + 2, tw - 4, 18, A(m_t.accent), A(m_t.accent2));
            m_side.Text(20 + t * tw + tw / 2, y + 4, tabs[t],
                        (on ? Mix(m_t.bg, clrBlack, 0.5) : A(m_t.dim)), RCS_F_SMALL, "Segoe UI",
                        TA_CENTER | TA_TOP, FW_BOLD);
            ZAdd(m_sideX + 20 + t * tw, m_sideY + y, tw - 4, 20, RZ_CFG_TAB0 + t);
         }
         y += 30;
      }
      for(int i = 0; i < m_d.stepN && i < 10; i++)
         y = Stepper(y, m_d.stepLabel[i], m_d.stepValue[i], i);
      if(m_cfgTab != 3) return y + 6;            // toggles live on the display tab
      y += 4;
      y = KV(y, "Theme", m_t.name, m_t.accent, RZ_CFG_PAL);
      y = KV(y, "Mode", (m_themeIdx % 2 == 1 ? "clair" : "sombre"), m_t.text, RZ_CFG_MODE);
      y = KV(y, "Langue", (m_d.lang == 0 ? "EN" : (m_d.lang == 2 ? "ES" : "FR")), m_t.text, RZ_CFG_LANG);
      y += 8;
      SecHead("NEWS", y);
      y = Toggle(y, "News HIGH", m_d.cfgNewsHigh, RZ_CFG_NEWSH);
      y = Toggle(y, "News MEDIUM", m_d.cfgNewsMed, RZ_CFG_NEWSM);
      y += 4;
      SecHead("ALERTES", y);
      y = Toggle(y, "Son", m_d.cfgSound, RZ_CFG_SOUND);
      y = Toggle(y, "Telegram", m_d.cfgTelegram, RZ_CFG_TG);
      y += 4;
      SecHead("CONFORT", y);
      y = Toggle(y, "Echelle confort", m_d.cfgComfort, RZ_CFG_COMFORT);
      y = Toggle(y, "Verrou discipline", m_d.cfgDiscipline, RZ_CFG_DISC);
      y = Toggle(y, "Outils de risque", m_d.riskTools, RZ_CFG_RTOOLS);
      return y + 6;
   }
   //--- AIDE : the legend, and what this tool is (and is not) --------------
   int SecHelp(int y) {
      SecHead(L(RCL_SEC_HELP, "LEGENDE"), y);
      m_side.Capsule(18, y + 4, 8, 8, A(m_t.ok));
      m_side.Text(34, y, "SAFE - sous 80% de la limite", A(m_t.text), RCS_F_SMALL, "Segoe UI", TA_LEFT | TA_TOP);
      y += 17;
      m_side.Capsule(18, y + 4, 8, 8, A(m_t.warn));
      m_side.Text(34, y, "WATCH - 80% consomme, prudence", A(m_t.text), RCS_F_SMALL, "Segoe UI", TA_LEFT | TA_TOP);
      y += 17;
      m_side.Capsule(18, y + 4, 8, 8, A(m_t.red));
      m_side.Text(34, y, "BREACH - limite atteinte", A(m_t.text), RCS_F_SMALL, "Segoe UI", TA_LEFT | TA_TOP);
      y += 22;
      SecHead("REGLE 40%", y);
      m_side.Text(18, y, "Fenetre news : seuls " + DoubleToString(m_d.newsSharePct, 0) + "% du",
                  A(m_t.text), RCS_F_SMALL, "Segoe UI", TA_LEFT | TA_TOP);
      y += 14;
      m_side.Text(18, y, "profit comptent ; les pertes comptent 100%.", A(m_t.text), RCS_F_SMALL, "Segoe UI", TA_LEFT | TA_TOP);
      y += 22;
      SecHead("MARGE DE SURVIE", y);
      m_side.Text(18, y, "Un trade ne risque jamais plus de 80% de", A(m_t.text), RCS_F_SMALL, "Segoe UI", TA_LEFT | TA_TOP);
      y += 14;
      m_side.Text(18, y, "la marge : 20% restent pour survivre.", A(m_t.text), RCS_F_SMALL, "Segoe UI", TA_LEFT | TA_TOP);
      y += 22;
      SecHead("A PROPOS", y);
      y = KV(y, "Version", m_d.version, m_t.dim, RZ_TIP_HELP);
      y = KV(y, "Source news", (m_d.newsFF ? "ForexFactory" : "MT5"), m_t.dim);
      m_side.Text(18, y, "Outil de SUIVI : il n'ouvre, ne modifie et", A(m_t.dim), RCS_F_SMALL, "Segoe UI", TA_LEFT | TA_TOP);
      y += 14;
      m_side.Text(18, y, "ne ferme AUCUN trade. Aucun signal.", A(m_t.dim), RCS_F_SMALL, "Segoe UI", TA_LEFT | TA_TOP);
      return y + 18;
   }
   //--- kept for any section not yet detailed ------------------------------
   int SecSoon(int y, const string title, const string live) {
      SecHead(title, y);
      m_side.Text(18, y, live, A(m_t.text), RCS_F_BODY, "Consolas", TA_LEFT | TA_TOP);
      y += 22;
      m_side.Text(18, y, "Detail de la section : lot 2.", A(m_t.dim), RCS_F_SMALL, "Segoe UI", TA_LEFT | TA_TOP);
      y += 18;
      return y;
   }
   int SecBody(const int sec, int y) {
      switch(sec) {
         case RZ_RAIL_LIM:  return SecLimits(y);
         case RZ_RAIL_POS:  return SecPositions(y);
         case RZ_RAIL_LOT:  return SecLot(y);
         case RZ_RAIL_NEWS: return SecNews(y);
         case RZ_RAIL_DISC: return SecDiscipline(y);
         case RZ_RAIL_CPT:  return SecAccount(y);
         case RZ_RAIL_CFG:  return SecConfig(y);
         case RZ_RAIL_HELP: return SecHelp(y);
      }
      return y;
   }
   void RenderSide(void) {
      if(!m_side.Ready()) return;
      m_side.Begin();
      m_lotEditOn = false;                                 // re-armed by SecLot when it draws
      if(m_state == 0) { m_side.Commit(); return; }        // closed = transparent bitmap
      const int W = RCS_SIDE_W, H = m_sideH;
      m_side.SoftShadow(4, 4, W - 8, H - 8, 14, clrBlack, 7, 80);
      m_side.Card(0, 0, W, H, 14, MixC(m_t.surface, clrWhite, 0.04), m_t.surface, LineC());
      m_side.GradientVFill(1, 1, W - 2, 34, 13,
                           Mix(m_t.surface, m_t.accent, 0.14), Mix(m_t.surface, clrBlack, 0.06));
      // header : title + pin (full sidebar) + close
      m_side.Text(18, 10, (m_state == 2 ? "RISKCOCKPIT" : SectionTitle(m_sec)),
                  A(m_t.accent), RCS_F_TITLE, "Segoe UI", TA_LEFT | TA_TOP, FW_BOLD);
      m_side.Text(W - 52, 10, (m_state == 2 ? ">" : "<"), A(m_t.dim), RCS_F_BODY, "Segoe UI", TA_CENTER | TA_TOP, FW_BOLD);
      ZAdd(m_sideX + W - 64, m_sideY + 4, 24, 26, RZ_PANEL_PIN);
      m_side.Text(W - 22, 9, ShortToString((ushort)0x00D7), A(m_t.dim), RCS_F_BTN, "Segoe UI", TA_CENTER | TA_TOP);
      ZAdd(m_sideX + W - 34, m_sideY + 4, 24, 26, RZ_PANEL_CLOSE);
      int y = 46;
      if(m_state == 2) {                                   // full sidebar : every section stacked
         int order[8];
         order[0] = RZ_RAIL_LIM;  order[1] = RZ_RAIL_POS;  order[2] = RZ_RAIL_LOT;  order[3] = RZ_RAIL_NEWS;
         order[4] = RZ_RAIL_DISC; order[5] = RZ_RAIL_CPT;  order[6] = RZ_RAIL_CFG;  order[7] = RZ_RAIL_HELP;
         int shown = 0;
         for(int i = 0; i < 8; i++) {
            if(y > H - 60) {                               // honest truncation, never overflow
               m_side.Text(18, y, "+" + IntegerToString(8 - shown) + " sections : agrandis la fenetre",
                           A(m_t.dim), RCS_F_SMALL, "Segoe UI", TA_LEFT | TA_TOP);
               break;
            }
            y = SecBody(order[i], y) + 8;
            shown++;
         }
      } else {
         y = SecBody(m_sec, y);
      }
      if(!m_d.riskTools) {
         m_side.Text(18, H - 26, "Outils de risque OFF (compte perso).", A(m_t.dim), RCS_F_SMALL, "Segoe UI", TA_LEFT | TA_TOP);
      }
      m_side.Commit();
   }

   //================= TOOLTIP (hover intent) ===============================
   bool TipText(const int id, string &t, string &d) const {
      // i18n first : the host pushes translated bubbles through SetTip() ; the FR
      // defaults below are the fallback (and the reference wording).
      if(id >= 0 && id < RCS_TIP_MAX && StringLen(m_tipT[id]) > 0) {
         t = m_tipT[id]; d = m_tipD[id];
         return true;
      }
      switch(id) {
         case RZ_RAIL_LIM:   t = "Limites";      d = "Conso de la limite la plus proche. Repere = 80%."; return true;
         case RZ_RAIL_POS:   t = "Positions";    d = "Positions ouvertes + pire statut de ligne.";       return true;
         case RZ_RAIL_LOT:   t = "Lot conseille";d = "Lot advisor. Ambre = plafonne 80%, rouge = 0.";    return true;
         case RZ_RAIL_NEWS:  t = "News";         d = "Minutes avant le prochain event soumis a la regle."; return true;
         case RZ_RAIL_DISC:  t = "Discipline";   d = "Verrou, tilt, garde SL, trades du jour.";          return true;
         case RZ_RAIL_CPT:   t = "Compte";       d = "Plan, taille, phase, add-ons, split.";             return true;
         case RZ_RAIL_CFG:   t = "Reglages";     d = "Affichage, alertes, avance.";                      return true;
         case RZ_RAIL_HELP:  t = "Aide";         d = "Regles, legende des couleurs, version.";           return true;
         case RZ_RAIL_CHEVRON: t = "Sidebar";    d = "Ouvre toutes les sections empilees.";              return true;
         case RZ_PANEL_CLOSE:t = "Fermer";       d = "Referme le panneau (le rail reste).";              return true;
         case RZ_PANEL_PIN:  t = "Sidebar";      d = "Bascule section unique / sidebar complete.";       return true;
         case RZ_NAV_LOGO:   t = "RiskCockpit";  d = "Ouvre la sidebar complete.";                       return true;
         case RZ_NAV_SYM:    t = "Symbole";      d = "Symbole du graphique (selection : lot 2).";        return true;
         case RZ_NAV_TF:     t = "Unite de temps"; d = "TF du graphique (selection : lot 2).";           return true;
         case RZ_NAV_HEALTH: t = "Sante";        d = "Score de sante du compte sur 100 (100 = sur).";    return true;
         case RZ_NAV_VITALS: t = "Vitals";       d = "Equity courante et nombre de positions.";          return true;
         case RZ_NAV_PALETTE:t = "Theme";        d = "Emeraude / Indigo / Ardoise.";                     return true;
         case RZ_NAV_MODE:   t = "Mode";         d = "Sombre / clair.";                                  return true;
         case RZ_NAV_CLOCK:  t = "Horloge";      d = "Heure serveur du broker.";                         return true;
         case RZ_NAV_KILL:   t = "Retirer";      d = "Retire RiskCockpit de ce graphique.";              return true;
         case RZ_TIP_LIM_ROOM:  t = "Marge";     d = "Dollars avant la limite active la plus proche.";   return true;
         case RZ_TIP_LIM_FLOOR: t = "Plancher";  d = "Equity sous ce niveau = compte perdu.";            return true;
         case RZ_TIP_LIM_M0: t = "Marge cumulee";  d = "Marge engagee / plafond du plan.";               return true;
         case RZ_TIP_LIM_M1: t = "Risque ouvert";  d = "Somme des risques aux SL / plafond.";            return true;
         case RZ_TIP_LIM_M2: t = "DD journalier";  d = "Perte du jour / limite journaliere.";            return true;
         case RZ_TIP_LIM_M3: t = "DD total";       d = "Perte totale / limite max du plan.";             return true;
         case RZ_TIP_LOT_BUD:  t = "Budget";      d = "Ce que ce trade a le droit de perdre a sa SL.";    return true;
         case RZ_TIP_LOT_FREE: t = "Marge libre"; d = "Marge broker disponible / balance initiale.";      return true;
         case RZ_TIP_LOT_CAP:  t = "Plafond 80%"; d = "Le lot est reduit pour garder 20% de reserve.";    return true;
         case RZ_TIP_NEWS_SRC: t = "Source news"; d = "FF = flux ForexFactory (aligne FN). MT = secours."; return true;
         case RZ_TIP_NEWS_RULE:t = "Regle news";  d = "Rouge = regle 40%. Ambre = a verifier sur FN.";    return true;
         case RZ_TIP_NEWS_LIST:t = "A venir";     d = "Prochains groupes (heure, devise, niveau).";       return true;
         case RZ_TIP_DISC_LOCK:t = "Verrou";      d = "Temps restant avant deverrouillage.";              return true;
         case RZ_TIP_DISC_SL:  t = "Garde SL";    d = "Prix de SL qui laisse 20% de marge de survie.";    return true;
         case RZ_TIP_DISC_TILT:t = "Tilt";        d = "Trades dans la fenetre / seuil configure.";        return true;
         case RZ_BAND:         t = "Alerte";      d = "Etat bloquant : lis la ligne, agis, elle part.";   return true;
         case RZ_TIP_CPT:      t = "Profil";     d = "Le plan dont TOUTES les limites sont deduites.";   return true;
         case RZ_CFG_TAB0:     t = "Risque";     d = "SL, TP, marge et risque par trade, trades prevus."; return true;
         case RZ_CFG_TAB1:     t = "Discipline"; d = "Tilt, cooldown, duree du self-lock.";              return true;
         case RZ_CFG_TAB2:     t = "Avance";     d = "Confort, rafraichissement, caps apres violation."; return true;
         case RZ_CFG_TAB3:     t = "Affichage";  d = "Theme, langue, news, alertes.";                    return true;
         case RZ_TIP_HELP:     t = "Version";    d = "Build en cours + source des news active.";         return true;
         case RZ_CFG_PAL:      t = "Palette";    d = "Emeraude / Indigo / Ardoise.";                     return true;
         case RZ_CFG_MODE:     t = "Mode";       d = "Sombre / clair.";                                  return true;
         case RZ_CFG_LANG:     t = "Langue";     d = "EN / FR / ES (persistee).";                        return true;
         case RZ_CFG_NEWSH:    t = "News HIGH";  d = "Events soumis a la regle 40%.";                    return true;
         case RZ_CFG_NEWSM:    t = "News MEDIUM";d = "Vigilance : a verifier sur FN, pas de regle.";     return true;
         case RZ_CFG_SOUND:    t = "Son";        d = "Alerte sonore aux changements de statut.";         return true;
         case RZ_CFG_TG:       t = "Telegram";   d = "Envoi des alertes (token dans les Inputs).";       return true;
         case RZ_CFG_COMFORT:  t = "Confort";    d = "Marge verticale du graphique.";                    return true;
         case RZ_CFG_DISC:     t = "Discipline"; d = "Verrou journalier + detection de tilt.";           return true;
         case RZ_CFG_RTOOLS:   t = "Outils";     d = "Toute la boite a outils prop (compte perso).";     return true;
      }
      if(id >= RZ_POS_ROW0 && id <= RZ_POS_ROW7) {
         t = "Position"; d = "Symbole, sens, volume, P&L, age, presence de SL.";
         return true;
      }
      return false;
   }
   void RenderTip(void) {
      if(!m_tip.Ready()) return;
      m_tip.Begin();                                       // empty = transparent = invisible
      string ti = "", ds = "";
      if(m_tipsOn && m_tipZone != RZ_NONE && TipText(m_tipZone, ti, ds)) {
         m_tip.SoftShadow(4, 4, RCS_TIP_W - 8, RCS_TIP_H - 8, 10, clrBlack, 4, 60);
         m_tip.Card(1, 1, RCS_TIP_W - 2, RCS_TIP_H - 2, 9, MixC(m_t.surface, clrWhite, 0.06), m_t.surface, MixC(m_t.surface, m_t.accent, 0.35));
         m_tip.Text(12, 7, ti, A(m_t.accent), RCS_F_LABEL, "Segoe UI", TA_LEFT | TA_TOP, FW_BOLD);
         m_tip.Text(12, 23, ds, A(m_t.text, 235), RCS_F_SMALL, "Segoe UI");
      }
      m_tip.Commit();
   }
   void TipShowRect(const int zx, const int zy, const int zw, const int zh) {
      int tx = zx - RCS_TIP_W - 10;                         // prefer the LEFT (rail/panels sit right)
      if(tx < 4) tx = zx + zw + 10;
      if(tx + RCS_TIP_W > m_chW - 4) tx = m_chW - RCS_TIP_W - 4;
      if(tx < 4) tx = 4;
      int ty = zy + zh / 2 - RCS_TIP_H / 2;
      if(ty + RCS_TIP_H > m_chH - 4) ty = m_chH - RCS_TIP_H - 4;
      if(ty < 4) ty = 4;
      ObjectSetInteger(0, m_pfx + "tip", OBJPROP_XDISTANCE, tx);
      ObjectSetInteger(0, m_pfx + "tip", OBJPROP_YDISTANCE, ty);
      RenderTip();
      ChartRedraw();
   }
   void TipPendCheck(void) {
      if(m_tipPendZone == RZ_NONE || !m_tipsOn) return;
      if((int)(GetTickCount() - m_tipDue) < 0) return;      // uint arithmetic : safe across the 49d wrap
      if(!(m_lastMx >= m_tipPX && m_lastMx <= m_tipPX + m_tipPW &&
           m_lastMy >= m_tipPY && m_lastMy <= m_tipPY + m_tipPH)) { m_tipPendZone = RZ_NONE; return; }
      m_tipZone = m_tipPendZone; m_tipPendZone = RZ_NONE;
      TipShowRect(m_tipPX, m_tipPY, m_tipPW, m_tipPH);
   }

   //================= DROPDOWN (symbol / timeframe) =========================
   //--- The shell reads Market Watch / the TF list itself and applies the
   //--- change with ChartSetSymbolPeriod - the same thing the legacy TF bar
   //--- did. No trade action is ever taken from here.
   void MenuFill(void) {
      m_menuN = 0;
      if(m_menuMode == 0) {                                // timeframes
         string tf[9] = {"M1","M5","M15","M30","H1","H4","D1","W1","MN"};
         for(int i = 0; i < 9; i++) { m_menuItem[i] = tf[i]; }
         m_menuN = 9;
      } else {                                             // Market Watch symbols
         const int tot = SymbolsTotal(true);
         for(int i = 0; i < tot && m_menuN < 12; i++) {
            const string s = SymbolName(i, true);
            if(StringLen(s) == 0) continue;
            m_menuItem[m_menuN] = s;
            m_menuN++;
         }
         if(m_menuN == 0) { m_menuItem[0] = _Symbol; m_menuN = 1; }
      }
   }
   ENUM_TIMEFRAMES MenuTf(const int idx) const {
      switch(idx) {
         case 0: return PERIOD_M1;  case 1: return PERIOD_M5;  case 2: return PERIOD_M15;
         case 3: return PERIOD_M30; case 4: return PERIOD_H1;  case 5: return PERIOD_H4;
         case 6: return PERIOD_D1;  case 7: return PERIOD_W1;  case 8: return PERIOD_MN1;
      }
      return (ENUM_TIMEFRAMES)ChartPeriod(0);
   }
   //--- Menu THEME (aligned on the StrategyDeck v2 dropdown) : 1px-inset card
   //--- + soft shadow, 26px item pitch, and the SELECTED item as a full
   //--- accent->accent2 GRADIENT capsule carrying DARK text - the exact same
   //--- language as the rail chevron and the active segment. A flat tinted
   //--- highlight (what the first pass drew) reads as a different control.
   void RenderMenu(void) {
      if(!m_menu.Ready()) return;
      m_menu.Begin();
      if(!m_menuOpen) { m_menu.Commit(); return; }         // closed = transparent
      const int W = RCS_MENU_W, H = m_menuH;
      m_menu.SoftShadow(4, 4, W - 8, H - 8, 10, clrBlack, 4, 60);
      m_menu.Card(1, 1, W - 2, H - 2, 10, MixC(m_t.surface, clrWhite, 0.04), m_t.surface, LineC());
      const string cur = (m_menuMode == 0 ? m_d.tf : m_d.sym);
      for(int i = 0; i < m_menuN && i < 12; i++) {
         const int iy = 8 + i * 26;
         const bool on = (m_menuItem[i] == cur);
         if(on) m_menu.CapsuleGradient(8, iy, W - 16, 22, A(m_t.accent), A(m_t.accent2));
         string lbl = m_menuItem[i];
         if(StringLen(lbl) > 12) lbl = StringSubstr(lbl, 0, 11) + "..";   // long symbols never overflow
         m_menu.Text(W / 2, iy + 4, lbl, (on ? Mix(m_t.bg, clrBlack, 0.5) : A(m_t.text)),
                     (m_menuMode == 0 ? RCS_F_BODY : RCS_F_LABEL),
                     (m_menuMode == 0 ? "Segoe UI" : "Consolas"), TA_CENTER | TA_TOP, FW_BOLD);
         ZAdd(m_menuX + 8, m_menuY + iy, W - 16, 22, RZ_MENU_0 + i);
      }
      m_menu.Commit();
   }

   //================= FLOATING POSITIONS TABLE ==============================
   //--- Appears BY ITSELF as soon as a trade is open and disappears when the
   //--- last one closes : while you hold something, the numbers that decide
   //--- what you do next must be on screen without opening anything. Draggable
   //--- by its header, clamped inside the chart, hideable for the session.
   void RenderFloat(void) {
      if(!m_float.Ready()) return;
      m_float.Begin();
      if(!m_fltOn) { m_float.Commit(); return; }         // no trade open = invisible
      const int W = m_fltW, H = m_fltH;
      m_float.SoftShadow(4, 4, W - 8, H - 8, 12, clrBlack, 6, 75);
      m_float.Card(0, 0, W, H, 12, MixC(m_t.surface, clrWhite, 0.05), m_t.surface, LineC());
      // header : grip + count + total P&L + hide
      m_float.GradientVFill(1, 1, W - 2, RCS_FLT_HEAD, 11,
                            Mix(m_t.surface, m_t.accent, 0.16), Mix(m_t.surface, clrBlack, 0.05));
      m_float.Text(12, 5, ShortToString((ushort)0x2261), A(m_t.dim), RCS_F_BODY, "Segoe UI", TA_LEFT | TA_TOP);
      m_float.Text(28, 5, IntegerToString(m_d.posCount) + " " + L(RCL_SEC_POS, "POSITIONS"),
                   A(m_t.accent), RCS_F_LABEL, "Segoe UI", TA_LEFT | TA_TOP, FW_BOLD);
      const color tc = (m_d.posPnl >= 0.0 ? m_t.ok : m_t.red);
      m_float.Text(W - 30, 5, (m_d.posPnl >= 0.0 ? "+" : "") + DoubleToString(m_d.posPnl, 2),
                   A(tc), RCS_F_NUM, "Consolas", TA_RIGHT | TA_TOP, FW_BOLD);
      m_float.Text(W - 13, 4, ShortToString((ushort)0x00D7), A(m_t.dim), RCS_F_BODY, "Segoe UI", TA_CENTER | TA_TOP);
      ZAdd(m_fltX, m_fltY, W - 24, RCS_FLT_HEAD, RZ_FLT_GRIP);      // drag surface
      ZAdd(m_fltX + W - 24, m_fltY, 24, RCS_FLT_HEAD, RZ_FLT_HIDE);
      // rows : symbol / side / volume, then P&L, age and the SL flag
      int y = RCS_FLT_HEAD + 6;
      for(int i = 0; i < m_d.posN && i < 8; i++) {
         const color st = StatC(m_d.posStat[i]);
         m_float.Capsule(10, y + 5, 5, 5, A(st));
         m_float.Text(22, y, m_d.posSym[i] + "  " + m_d.posSide[i] + " " + DoubleToString(m_d.posVol[i], 2),
                      A(m_t.text), RCS_F_BODY, "Consolas", TA_LEFT | TA_TOP);
         const color pc = (m_d.posRowPnl[i] >= 0.0 ? m_t.ok : m_t.red);
         m_float.Text(W - 12, y, (m_d.posRowPnl[i] >= 0.0 ? "+" : "") + DoubleToString(m_d.posRowPnl[i], 2),
                      A(pc), RCS_F_NUM, "Consolas", TA_RIGHT | TA_TOP, FW_BOLD);
         y += 14;
         string sub = IntegerToString(m_d.posAge[i] / 60) + " min";
         if(!m_d.posHasSl[i]) sub += "   " + L(RCL_NOSL, "SANS SL");
         m_float.Text(22, y, sub, A(m_d.posHasSl[i] ? m_t.dim : m_t.red), RCS_F_SMALL, "Segoe UI", TA_LEFT | TA_TOP);
         ZAdd(m_fltX + 8, m_fltY + y - 14, W - 16, RCS_FLT_ROW - 4, RZ_FLT_ROW0 + i);
         y += 16;
      }
      if(m_d.posCount > m_d.posN)
         m_float.Text(12, y, "+" + IntegerToString(m_d.posCount - m_d.posN) + " " + L(RCL_POS_MORE, "autres"),
                      A(m_t.dim), RCS_F_SMALL, "Segoe UI", TA_LEFT | TA_TOP);
      m_float.Commit();
   }

   //================= SAFETY BAND (hard lock / SL guard / tilt) =============
   //--- Full-width, top of the chart, ABOVE the navbar : the one surface the
   //--- user cannot lose track of. The shell is read-only, so this is a WARNING
   //--- band, not a trade block - it must therefore be impossible to miss.
   void RenderBand(void) {
      if(!m_band.Ready()) return;
      m_band.Begin();
      if(!m_bandOn) { m_band.Commit(); return; }          // empty = transparent
      const bool hard = (m_d.discLocked || m_d.slGuard);
      const color bc  = (hard ? m_t.red : m_t.warn);
      const int   W   = m_chW;
      m_band.CapsuleGradient(0, 0, W, RCS_BAND_H, A(bc), Mix(bc, clrBlack, 0.35));
      string msg;
      if(m_d.discLocked)
         msg = "VERROU DISCIPLINE ACTIF" + (m_d.lockMinsLeft > 0
               ? "  -  " + IntegerToString(m_d.lockMinsLeft) + " min restantes" : "");
      else if(m_d.slGuard)
         msg = "SL TROP BAS - risque de breche" + (m_d.slGuardSym != "" && m_d.slGuardPrice > 0.0
               ? "  -  remonte " + m_d.slGuardSym + " a >= " +
                 DoubleToString(m_d.slGuardPrice, (m_d.slGuardPrice >= 100.0 ? 2 : 5)) : "");
      else
         msg = "TILT - " + IntegerToString(m_d.tiltTrades) + " trades en " +
               IntegerToString(m_d.tiltWinMin) + " min : ralentis";
      m_band.Text(W / 2, 6, msg, Mix(m_t.bg, clrBlack, 0.25), RCS_F_BODY, "Segoe UI", TA_CENTER | TA_TOP, FW_BOLD);
      ZAdd(0, 0, W, RCS_BAND_H, RZ_BAND);
      m_band.Commit();
   }

   void CreateSurfaces(void) {
      m_nav.Create(m_pfx + "nav", m_navX, m_navY, m_navW, RCS_NAV_H);
      m_rail.Create(m_pfx + "rail", m_railX, m_railY, RCS_RAIL_W, m_railH);
      m_side.Create(m_pfx + "side", m_sideX, m_sideY, RCS_SIDE_W, m_sideH);
      // lot 2/3 surfaces : created NOW so the z-order is locked, but erased to
      // fully transparent right away (a fresh bitmap is not blank - an unpainted
      // 8x8 canvas would sit as a dark square in the chart corner).
      m_float.Create(m_pfx + "flt", m_fltX, m_fltY, m_fltW, m_fltH);   // floating positions table
      m_float.Begin(); m_float.Commit();
      m_menu.Create(m_pfx + "menu", m_menuX, m_menuY, RCS_MENU_W, m_menuH); // symbol / TF dropdown
      m_menu.Begin(); m_menu.Commit();
      m_band.Create(m_pfx + "band", 0, 0, m_chW, RCS_BAND_H); // safety band : above the UI
      m_band.Begin(); m_band.Commit();
      m_tip.Create(m_pfx + "tip", 0, 0, RCS_TIP_W, RCS_TIP_H); // created LAST = above everything
   }

public:
   void Init(void) {
      m_created = false; m_haveData = false; m_pfx = "";
      m_themeIdx = 0; m_state = 0; m_sec = RZ_RAIL_LIM;
      m_zn = 0; m_pendKill = false;
      m_chW = 1200; m_chH = 800;
      m_railX = 0; m_railY = 0; m_railH = 0; m_railGap = RCS_RAIL_MING;
      m_navX = 0; m_navW = RCS_NAV_W;
      m_sideX = 0; m_sideY = 0; m_sideH = RCS_SIDE_SECH;
      m_tipZone = RZ_NONE; m_tipPendZone = RZ_NONE; m_tipDelayMs = 600; m_tipDue = 0;
      m_tipPX = 0; m_tipPY = 0; m_tipPW = 0; m_tipPH = 0; m_tipsOn = true;
      m_lastMx = -1; m_lastMy = -1;
      // safe defaults before the first SetData
      m_d.verdict = 0; m_d.score = 100; m_d.verdictWord = "--";
      m_d.equity = 0.0; m_d.balance = 0.0; m_d.sym = _Symbol; m_d.tf = "";
      m_d.planTag = "--"; m_d.sizeTag = "--"; m_d.splitPct = 0; m_d.riskTools = true;
      m_d.limRatio = 0.0; m_d.roomMoney = -1.0; m_d.floorMoney = 0.0; m_d.trailing = false;
      m_d.marginPct = 0.0; m_d.marginCap = 0.0; m_d.riskPct = 0.0; m_d.riskCap = 0.0;
      m_d.dailyPct = 0.0; m_d.dailyCap = 0.0; m_d.overallPct = 0.0; m_d.overallCap = 0.0;
      m_d.dailyApplies = false; m_d.overallApplies = false;
      m_d.posCount = 0; m_d.posWorst = 3; m_d.posPnl = 0.0; m_d.posNoSl = false;
      m_d.sugLot = 0.0; m_d.lotDigits = 2; m_d.lotCapped = false; m_d.lotZero = false;
      m_d.budgetPct = 0.0; m_d.freeMarginPct = 0.0;
      m_d.newsHasEvt = false; m_d.newsHigh = false; m_d.newsActive = false; m_d.newsFF = false; m_d.newsMins = 0;
      m_d.discLocked = false; m_d.discTilt = false; m_d.slGuard = false;
      m_d.tradesToday = 0; m_d.tradesCap = 0;
      m_d.clockSrv = ""; m_d.clockGmt = ""; m_d.clockLoc = "";
      m_d.posN = 0; m_d.nPlanned = 0; m_d.budgetMoney = 0.0; m_d.spreadPts = 0.0; m_d.commPerLot = -1.0;
      m_d.newsN = 0; m_d.newsWinMin = 5; m_d.newsSharePct = 40.0;
      m_d.lockMinsLeft = 0; m_d.tiltWinMin = 0; m_d.tiltN = 0; m_d.tiltTrades = 0;
      m_d.slGuardSym = ""; m_d.slGuardPrice = 0.0; m_d.selfLock = false;
      for(int p = 0; p < 8; p++) {
         m_d.posSym[p] = ""; m_d.posSide[p] = ""; m_d.posVol[p] = 0.0; m_d.posRowPnl[p] = 0.0;
         m_d.posAge[p] = 0; m_d.posStat[p] = 3; m_d.posHasSl[p] = true;
      }
      for(int q = 0; q < 6; q++) { m_d.newsWhen[q] = ""; m_d.newsCcy[q] = ""; m_d.newsRestr[q] = false; }
      m_navY = 0; m_bandOn = false;
      m_lotEditOn = false; m_lotEditX = 0; m_lotEditY = 0; m_lotEditW = 0; m_lotEditH = 0;
      m_fltX = 0; m_fltY = 0; m_fltW = RCS_FLT_W; m_fltH = RCS_FLT_HEAD + 40;
      m_fltOn = false; m_fltHidden = false; m_drag = false; m_dragOffX = 0; m_dragOffY = 0;
      m_pendCfg = 0; m_cfgTab = 0; m_pendStepRow = -1; m_pendStepDir = 0; m_pendCas = -1;
      m_d.stepN = 0; m_d.casN = 0;
      for(int si = 0; si < 10; si++) { m_d.stepLabel[si] = ""; m_d.stepValue[si] = ""; }
      for(int ci = 0; ci < 5; ci++)  { m_d.casLabel[ci] = "";  m_d.casValue[ci] = ""; }
      m_menuOpen = false; m_menuMode = 0; m_menuX = 0; m_menuY = 0; m_menuH = 40; m_menuN = 0;
      for(int mi = 0; mi < 12; mi++) m_menuItem[mi] = "";
      for(int li = 0; li < RCS_L_MAX; li++) m_L[li] = "";
      for(int ti = 0; ti < RCS_TIP_MAX; ti++) { m_tipT[ti] = ""; m_tipD[ti] = ""; }
      m_d.planLabel = "--"; m_d.phaseLabel = "--"; m_d.acctTypeLabel = "--";
      m_d.addonsLabel = ""; m_d.cycleLabel = ""; m_d.sizeLabelFull = "--";
      m_d.login = 0; m_d.minDays = 0; m_d.minDaysDone = 0;
      m_d.cfgNewsHigh = true; m_d.cfgNewsMed = true; m_d.cfgSound = true;
      m_d.cfgTelegram = false; m_d.cfgComfort = true; m_d.cfgDiscipline = true;
      m_d.lang = 1; m_d.version = "";
      m_nav.Init(); m_rail.Init(); m_side.Init(); m_float.Init(); m_menu.Init(); m_band.Init(); m_tip.Init();
   }
   bool Created(void) const { return m_created; }
   int  ThemeIdx(void) const { return m_themeIdx; }
   void SetThemeIdx(const int idx) { m_themeIdx = ((idx % 6) + 6) % 6; RC_ThemeGet(m_themeIdx, m_t); }
   void SetTipsEnabled(const bool on) { m_tipsOn = on; if(!on) { m_tipZone = RZ_NONE; m_tipPendZone = RZ_NONE; if(m_created) RenderTip(); } }
   void SetTipDelay(const int ms) { m_tipDelayMs = (ms < 0 ? 0 : (ms > 5000 ? 5000 : ms)); }
   bool PendKillTake(void) { const bool r = m_pendKill; m_pendKill = false; return r; }
   int  PendCfgTake(void)  { const int  r = m_pendCfg;  m_pendCfg  = 0;     return r; }
   int  CfgTab(void) const { return m_cfgTab; }
   //--- a stepper was clicked : row + direction (-1 / +1). false = nothing.
   bool PendStepTake(int &row, int &dir) {
      if(m_pendStepRow < 0) return false;
      row = m_pendStepRow; dir = m_pendStepDir; m_pendStepRow = -1; return true;
   }
   //--- a cascade cycler was clicked : row + direction. false = nothing.
   bool PendCasTake(int &row, int &dir) {
      if(m_pendCas < 0) return false;
      row = m_pendCas / 10; dir = ((m_pendCas % 10) == 1 ? 1 : -1); m_pendCas = -1; return true;
   }
   //--- i18n : slot ids are ERCLabel ; empty string = keep the FR default ---
   void SetLabel(const int id, const string s) { if(id >= 0 && id < RCS_L_MAX) m_L[id] = s; }
   //--- translated tooltip for a zone id ("title|description" packed by the host)
   void SetTip(const int zid, const string packed) {
      if(zid < 0 || zid >= RCS_TIP_MAX) return;
      const int bar = StringFind(packed, "|");
      if(bar <= 0) { m_tipT[zid] = packed; m_tipD[zid] = ""; return; }
      m_tipT[zid] = StringSubstr(packed, 0, bar);
      m_tipD[zid] = StringSubstr(packed, bar + 1);
   }
   //--- zone ids the host needs to address its tooltips (no enum leak needed) --
   int ZidRail(const int i)  const { return RZ_RAIL_LIM + i; }        // 0..7 = the 8 cells
   int ZidChevron(void) const { return RZ_RAIL_CHEVRON; }
   int ZidNav(const int i)   const { return RZ_NAV_LOGO + i; }        // 0..7 navbar chips
   int ZidPanel(const int i) const { return RZ_PANEL_CLOSE + i; }     // 0 close, 1 pin
   int ZidLimTip(const int i) const { return RZ_TIP_LIM_ROOM + i; }   // 0..5 limits rows
   int ZidLotTip(const int i) const { return RZ_TIP_LOT_BUD + i; }    // 0..2
   int ZidNewsTip(const int i) const { return RZ_TIP_NEWS_SRC + i; }  // 0..2
   int ZidDiscTip(const int i) const { return RZ_TIP_DISC_LOCK + i; } // 0..2
   int ZidBand(void) const { return RZ_BAND; }
   int ZidPosRow(void) const { return RZ_POS_ROW0; }
   int ZidCfg(const int i)   const { return RZ_CFG_PAL + i; }         // 0..9
   int ZidCptTip(void) const { return RZ_TIP_CPT; }
   int ZidHelpTip(void) const { return RZ_TIP_HELP; }
   //--- copy-lot : true + rect when the host must show its native edit box ----
   bool LotEditRect(int &x, int &y, int &w, int &h) const {
      if(!m_lotEditOn) return false;
      x = m_lotEditX; y = m_lotEditY; w = m_lotEditW; h = m_lotEditH;
      return true;
   }
   color EditTextColor(void) const { return m_t.text; }
   color EditBackColor(void) const { return MixC(m_t.surface, m_t.accent, 0.10); }
   color EditLineColor(void) const { return LineC(); }
   //--- config toggle ids, so the host can map them without knowing the enum
   int  CfgIdNewsHigh(void) const { return RZ_CFG_NEWSH; }
   int  CfgIdNewsMed(void)  const { return RZ_CFG_NEWSM; }
   int  CfgIdSound(void)    const { return RZ_CFG_SOUND; }
   int  CfgIdTelegram(void) const { return RZ_CFG_TG; }
   int  CfgIdComfort(void)  const { return RZ_CFG_COMFORT; }
   int  CfgIdDiscipline(void) const { return RZ_CFG_DISC; }
   int  CfgIdRiskTools(void) const { return RZ_CFG_RTOOLS; }
   int  CfgIdLang(void)     const { return RZ_CFG_LANG; }

   bool Create(const string pfx) {
      m_pfx = pfx;
      RC_ThemeGet(m_themeIdx, m_t);
      ReadChart();
      CreateSurfaces();
      m_created = true;
      RenderAll();
      return true;
   }
   void Destroy(void) {
      if(!m_created || StringLen(m_pfx) == 0) return;      // guard : NEVER ObjectsDeleteAll("")
      ChartSetInteger(0, CHART_MOUSE_SCROLL, true);        // restore whatever we may have taken
      m_nav.Destroy(); m_rail.Destroy(); m_side.Destroy();
      m_float.Destroy(); m_menu.Destroy(); m_band.Destroy(); m_tip.Destroy();
      ObjectsDeleteAll(0, m_pfx);
      m_created = false;
   }
   void SetData(const RCDeckData &d) { m_d = d; m_haveData = true; }

   //--- THE single render path -------------------------------------------
   void RenderAll(void) {
      if(!m_created) return;
      ZReset();
      RenderNavbar();
      RenderRail();
      RenderSide();
      RenderFloat();
      RenderMenu();
      RenderBand();
      RenderTip();
      ChartRedraw();                                       // ONE redraw per frame
   }
   void Tick(void) {
      if(!m_created) return;
      // the safety band changes the navbar anchor : re-layout when it appears
      // or disappears, otherwise the navbar would sit under it.
      const bool wantBand = (m_d.discLocked || m_d.slGuard || m_d.discTilt);
      if(wantBand != m_bandOn) { OnChartChange(); return; }
      ZReset();
      RenderNavbar(); RenderRail(); RenderSide(); RenderFloat(); RenderMenu(); RenderBand(); RenderTip();
      TipPendCheck();                                      // idle cursor : the 1 Hz tick promotes it
      ChartRedraw();
   }
   void OnChartChange(void) {
      if(!m_created) return;
      ReadChart();
      m_tipZone = RZ_NONE; m_tipPendZone = RZ_NONE;        // zones moved : re-evaluate on next hover
      m_nav.Destroy(); m_rail.Destroy(); m_side.Destroy();
      m_float.Destroy(); m_menu.Destroy(); m_band.Destroy(); m_tip.Destroy();
      CreateSurfaces();
      RenderAll();
   }

   //--- CHARTEVENT_CLICK dispatch (anchor-relative zones) -----------------
   bool OnClick(const int px, const int py) {
      if(!m_created) return false;
      // containment : the surface ON TOP intercepts. In a surface rect, ONLY its
      // own zones count (else a hidden zone underneath steals the click).
      const bool inMenu = (m_menuOpen && px >= m_menuX && px <= m_menuX + RCS_MENU_W &&
                           py >= m_menuY && py <= m_menuY + m_menuH);
      const bool inFlt  = (m_fltOn && !inMenu && px >= m_fltX && px <= m_fltX + m_fltW &&
                           py >= m_fltY && py <= m_fltY + m_fltH);
      const bool inRail = (!inMenu && !inFlt && px >= m_railX && py >= m_railY && py <= m_railY + m_railH);
      const bool inSide = (m_state != 0 && !inMenu && !inFlt && !inRail &&
                           px >= m_sideX && px <= m_sideX + RCS_SIDE_W &&
                           py >= m_sideY && py <= m_sideY + m_sideH);
      int hit = RZ_NONE;
      for(int i = 0; i < m_zn; i++) {
         const int id = m_z[i].id;
         if(inMenu && !(id >= RZ_MENU_0 && id <= RZ_MENU_11)) continue;
         if(inFlt  && !(id >= RZ_FLT_GRIP && id <= RZ_FLT_ROW7)) continue;
         if(inRail && !(id >= RZ_RAIL_LIM && id <= RZ_RAIL_CHEVRON)) continue;
         // x full-rect + y TOP-only : a panel zone overflowing at the bottom on a
         // small chart stays clickable, navbar chips (y < m_sideY-4) stay excluded.
         if(inSide && !(m_z[i].x >= m_sideX - 4 && m_z[i].x + m_z[i].w <= m_sideX + RCS_SIDE_W + 4 &&
                        m_z[i].y >= m_sideY - 4 && m_z[i].y <= m_sideY + m_sideH)) continue;
         if(px >= m_z[i].x && px <= m_z[i].x + m_z[i].w && py >= m_z[i].y && py <= m_z[i].y + m_z[i].h)
            { hit = id; break; }
      }
      if(hit == RZ_NONE) {
         if(inFlt)  return true;                                            // inside the floating table
         if(inMenu) return true;                                            // inside the menu, off an item
         if(m_menuOpen) { m_menuOpen = false; OnChartChange(); return false; } // click away closes it
         if(m_state == 1) { m_state = 0; OnChartChange(); return false; }   // auto-collapse
         return false;
      }
      // dropdown item : apply the chart change, the rebuild follows on CHART_CHANGE
      if(hit >= RZ_MENU_0 && hit <= RZ_MENU_11) {
         const int idx = hit - RZ_MENU_0;
         if(idx < m_menuN) {
            m_menuOpen = false;
            if(m_menuMode == 0) ChartSetSymbolPeriod(0, _Symbol, MenuTf(idx));
            else                ChartSetSymbolPeriod(0, m_menuItem[idx], (ENUM_TIMEFRAMES)ChartPeriod(0));
         }
         return true;
      }
      // config toggles : the SHELL never mutates the model - the host applies it
      if(hit >= RZ_CFG_PAL && hit <= RZ_CFG_RTOOLS) {
         if(hit == RZ_CFG_PAL) {                            // theme + mode are view-only
            const int pal2 = m_themeIdx / 2, lgt2 = m_themeIdx % 2;
            m_themeIdx = (((pal2 + 1) % 3) * 2) + lgt2;
            RC_ThemeGet(m_themeIdx, m_t); RenderAll(); return true;
         }
         if(hit == RZ_CFG_MODE) {
            m_themeIdx = (m_themeIdx % 2 == 0 ? m_themeIdx + 1 : m_themeIdx - 1);
            RC_ThemeGet(m_themeIdx, m_t); RenderAll(); return true;
         }
         m_pendCfg = hit;                                   // host consumes on its next refresh
         return true;
      }
      // hover-only info zones : swallow the click, never collapse the section
      if(hit >= RZ_TIP_LIM_ROOM && hit <= RZ_TIP_LIM_M3) return true;
      if(hit >= RZ_POS_ROW0 && hit <= RZ_BAND) return true;   // info rows + safety band
      if(hit == RZ_TIP_CPT || hit == RZ_TIP_HELP) return true;
      if(hit == RZ_LOT_EDIT) return true;      // native edit sits here : NEVER collapse the section
      if(hit >= RZ_CFG_TAB0 && hit <= RZ_CFG_TAB3) {          // settings sub-tab
         m_cfgTab = hit - RZ_CFG_TAB0; RenderAll(); return true;
      }
      if(hit >= RZ_STEP_DEC0 && hit <= RZ_STEP_DEC9) {        // stepper : the HOST applies
         m_pendStepRow = hit - RZ_STEP_DEC0; m_pendStepDir = -1; return true;
      }
      if(hit >= RZ_STEP_INC0 && hit <= RZ_STEP_INC9) {
         m_pendStepRow = hit - RZ_STEP_INC0; m_pendStepDir = 1;  return true;
      }
      if(hit >= RZ_CAS_PREV0 && hit <= RZ_CAS_PREV4) {        // cascade : the HOST re-resolves
         m_pendCas = (hit - RZ_CAS_PREV0) * 10 + 0; return true;
      }
      if(hit >= RZ_CAS_NEXT0 && hit <= RZ_CAS_NEXT4) {
         m_pendCas = (hit - RZ_CAS_NEXT0) * 10 + 1; return true;
      }
      if(hit >= RZ_FLT_ROW0 && hit <= RZ_FLT_ROW7) return true;   // position rows : read-only
      if(hit == RZ_FLT_HIDE) { m_fltHidden = true; OnChartChange(); return true; }
      if(hit == RZ_FLT_GRIP) return true;      // the drag itself runs on mouse-move
      switch(hit) {
         case RZ_RAIL_LIM: case RZ_RAIL_POS: case RZ_RAIL_LOT: case RZ_RAIL_NEWS:
         case RZ_RAIL_DISC: case RZ_RAIL_CPT: case RZ_RAIL_CFG: case RZ_RAIL_HELP:
            if(m_state == 1 && m_sec == hit) m_state = 0;   // toggle (VS Code contract)
            else { m_state = 1; m_sec = hit; }
            OnChartChange();
            return true;
         case RZ_RAIL_CHEVRON:
         case RZ_PANEL_PIN:
            m_state = (m_state == 2 ? 0 : 2);
            OnChartChange(); return true;
         case RZ_NAV_LOGO:
            m_state = 2; OnChartChange(); return true;
         case RZ_PANEL_CLOSE:
            m_state = 0; OnChartChange(); return true;
         case RZ_NAV_PALETTE: {
            const int pal = m_themeIdx / 2, lgt = m_themeIdx % 2;
            m_themeIdx = (((pal + 1) % 3) * 2) + lgt;
            RC_ThemeGet(m_themeIdx, m_t); RenderAll(); return true;
         }
         case RZ_NAV_MODE:
            m_themeIdx = (m_themeIdx % 2 == 0 ? m_themeIdx + 1 : m_themeIdx - 1);
            RC_ThemeGet(m_themeIdx, m_t); RenderAll(); return true;
         case RZ_NAV_KILL:
            m_pendKill = true; return true;                 // the host removes the indicator
         case RZ_NAV_TF: case RZ_NAV_SYM: {                  // chips open their dropdown
            const int want = (hit == RZ_NAV_TF ? 0 : 1);
            if(m_menuOpen && m_menuMode == want) m_menuOpen = false;   // same chip toggles
            else { m_menuMode = want; MenuFill(); m_menuOpen = true; }
            OnChartChange();                                 // the menu surface is resized
            return true;
         }
         case RZ_NAV_HEALTH: case RZ_NAV_VITALS: case RZ_NAV_CLOCK:
            return true;                                     // info chips
      }
      return true;
   }

   //--- drag of the floating table : press on the header, move, release. The
   //--- host feeds mouse state ; the table stays clamped inside the chart.
   void OnMouseDrag(const int mx, const int my, const bool leftDown) {
      if(!m_created) return;
      if(!leftDown) {
         if(m_drag) { m_drag = false; OnChartChange(); }   // dropped : re-anchor the surfaces
         return;
      }
      if(!m_drag) {
         if(!m_fltOn) return;
         if(!(mx >= m_fltX && mx <= m_fltX + m_fltW - 24 && my >= m_fltY && my <= m_fltY + RCS_FLT_HEAD))
            return;                                        // press started outside the header
         m_drag = true; m_dragOffX = mx - m_fltX; m_dragOffY = my - m_fltY;
         m_tipZone = RZ_NONE; m_tipPendZone = RZ_NONE;     // a drag cancels any pending tooltip
         return;
      }
      m_fltX = mx - m_dragOffX;
      m_fltY = my - m_dragOffY;
      if(m_fltX > m_chW - m_fltW) m_fltX = m_chW - m_fltW;
      if(m_fltX < 0) m_fltX = 0;
      if(m_fltY > m_chH - m_fltH) m_fltY = m_chH - m_fltH;
      if(m_fltY < 0) m_fltY = 0;
      ObjectSetInteger(0, m_pfx + "flt", OBJPROP_XDISTANCE, m_fltX);
      ObjectSetInteger(0, m_pfx + "flt", OBJPROP_YDISTANCE, m_fltY);
      ChartRedraw();
   }
   bool Dragging(void) const { return m_drag; }
   void FloatPos(int &x, int &y) const { x = m_fltX; y = m_fltY; }
   void SetFloatPos(const int x, const int y) { if(x > 0 || y > 0) { m_fltX = x; m_fltY = y; } }
   bool FloatHidden(void) const { return m_fltHidden; }
   void SetFloatHidden(const bool h) { m_fltHidden = h; }

   //--- hover : tooltip intent (no render unless the zone changes) --------
   void OnMouseMove(const int mx, const int my) {
      if(!m_created || !m_tipsOn) return;
      if(m_drag) return;                                   // dragging : no tooltip work
      m_lastMx = mx; m_lastMy = my;
      int zid = RZ_NONE, zx = 0, zy = 0, zw = 0, zh = 0;
      for(int i = 0; i < m_zn; i++) {
         if(mx >= m_z[i].x && mx <= m_z[i].x + m_z[i].w && my >= m_z[i].y && my <= m_z[i].y + m_z[i].h) {
            zid = m_z[i].id; zx = m_z[i].x; zy = m_z[i].y; zw = m_z[i].w; zh = m_z[i].h; break;
         }
      }
      if(zid == m_tipZone) return;                          // same zone : nothing to do
      if(zid == RZ_NONE) {                                  // left every zone : hide
         m_tipPendZone = RZ_NONE;
         if(m_tipZone != RZ_NONE) { m_tipZone = RZ_NONE; RenderTip(); ChartRedraw(); }
         return;
      }
      string t = "", d = "";
      if(!TipText(zid, t, d)) {                             // zone without help : hide
         m_tipPendZone = RZ_NONE;
         if(m_tipZone != RZ_NONE) { m_tipZone = RZ_NONE; RenderTip(); ChartRedraw(); }
         return;
      }
      if(m_tipZone != RZ_NONE) { m_tipZone = RZ_NONE; RenderTip(); ChartRedraw(); }
      m_tipPendZone = zid;                                  // hover intent : wait m_tipDelayMs
      m_tipPX = zx; m_tipPY = zy; m_tipPW = zw; m_tipPH = zh;
      m_tipDue = GetTickCount() + (uint)m_tipDelayMs;
   }
};

#endif // __RC_SHELL_UI_MQH__
