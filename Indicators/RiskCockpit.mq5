//+------------------------------------------------------------------+
//|                                          RiskCockpit.mq5   |
//|                                                JR Trading - 2026 |
//|                                          https://javadrazavi.fr  |
//|                                                                  |
//|  RiskCockpit Indicator                                     |
//|  ---------------------------                                     |
//|  Real-time rule-monitoring panel for prop-firm traders on        |
//|  FundedNext (Stellar 1-Step / 2-Step / Lite / Instant).          |
//|  No auto-actions: this is an ADVISOR. Trades stay in the user's  |
//|  hands. The companion EA (V2) executes auto-fixes.               |
//|                                                                  |
//|  T6 (this commit): UI skeleton + panel rendering.                |
//|  T7 (next commit): live rule evaluation hooked to MQL5 trade     |
//|                    APIs and OnTradeTransaction events.           |
//|                                                                  |
//|  Color literals MUST use the hex form ((color)0x00BBGGRR) - the  |
//|  clang-format auto-formatter on this workspace breaks the        |
//|  C'r,g,b' apostrophe syntax (lesson learned on FFD Pro).         |
//+------------------------------------------------------------------+
#property copyright "JR Trading - 2026 - javadrazavi.fr"
#property link "https://javadrazavi.fr"
#property version "1.40"
#property icon "RiskCockpit.ico"   // v1.4.1 : shown in the Navigator + the indicator properties dialog (embedded in the .ex5)
#property description "RiskCockpit - real-time risk-monitoring dashboard for prop-firm traders. Compatible FundedNext / FTMO / E8 / The5ers / MyFundedFX challenges."
#property strict
#property indicator_chart_window
#property indicator_plots 0
#property indicator_buffers 0

#include <..\Libraries\CChallengeProfileCatalog.mqh>
#include <..\Libraries\CPyramidEngine.mqh>
#include <Canvas\Canvas.mqh>            // v1.4 : CCanvas FX overlay (risk-breach glow ring)
#include <..\Libraries\JR_CanvasUI.mqh> // v1.4 : reusable modern-UI canvas kit (brand design language)

// V1.29 : EMBED the header logo so BUYERS see it. A Market product ships only the
// .ex5 - an external MQL5\Images\ file is NOT delivered, so the runtime path load
// showed a blank/"RC" placeholder for buyers. The bmp is copied next to this .mq5
// and embedded as a resource (referenced at runtime via "::RiskCockpit_logo.bmp").
#resource "RiskCockpit_logo.bmp"

//+------------------------------------------------------------------+
//| Compatibility shim for non-MQL5 parsers (Antigravity / VS Code   |
//| / clang). MetaEditor pre-defines __MQL5__ when building .mq5     |
//| files, so this block is invisible to the real compiler. Without  |
//| it clang misparses `input <type> ... = <enum>;` and downstream   |
//| comparisons like `if (InpTheme == RC_THEME_GLASS_DARK)` raise   |
//| "pointer-and-integer" false positives.                           |
//+------------------------------------------------------------------+
#ifndef __MQL5__
#define input
#endif

//+------------------------------------------------------------------+
//| User-facing enums for inputs (the user picks a single value)     |
//+------------------------------------------------------------------+
enum ENUM_RC_THEME {
    RC_THEME_GLASS_DARK = 0, // glass dark (default)
    RC_THEME_GLASS_LIGHT = 1 // glass light
};

//+------------------------------------------------------------------+
//| LOT 4 : UI language - EN / FR / ES. Picked via InpLang input ;    |
//| a future Settings popup (LOT 5) will offer an in-panel switch.    |
//+------------------------------------------------------------------+
enum ENUM_RC_LANG {
    RC_LANG_EN = 0, // English
    RC_LANG_FR = 1, // Francais
    RC_LANG_ES = 2  // Espanol
};

//+------------------------------------------------------------------+
//| FIX 5 (V1.0.1) : preset account sizes -> no more free-form entry  |
//| (no typos). The enum VALUE is the balance in USD, so (double)Inp..|
//| yields the balance directly. MT5 inputs cannot cascade-filter one |
//| dropdown by another at the property dialog, so this is the union  |
//| of every plan's sizes; the valid per-plan subset is :             |
//|   1-Step / 2-Step : 6 / 15 / 25 / 50 / 100 / 200 K                |
//|   Lite            : 5 / 25 / 50 / 100 / 200 K                      |
//|   Instant         : <= 50 K (exact tiers to confirm)              |
//|   Free Trial      : 6 -> 200 K                                    |
//|   Free Competition: single size, varies per monthly event         |
//+------------------------------------------------------------------+
enum ENUM_FN_ACCT_SIZE {
    FN_SIZE_5K   = 5000,   // 5 000  (Lite)
    FN_SIZE_6K   = 6000,   // 6 000  (1-Step / 2-Step / Free Trial)
    FN_SIZE_10K  = 10000,  // 10 000 (B-AVATRADE-PROFILE : demo perso AvaTrade)
    FN_SIZE_15K  = 15000,  // 15 000
    FN_SIZE_25K  = 25000,  // 25 000
    FN_SIZE_50K  = 50000,  // 50 000
    FN_SIZE_100K = 100000, // 100 000
    FN_SIZE_200K = 200000  // 200 000
};

//+------------------------------------------------------------------+
//| Inputs                                                           |
//|                                                                  |
//| The `// clang-format off` block keeps `input group "..."` on its |
//| own line. Without it the clang formatter collapses it onto the   |
//| next input declaration, which the Antigravity IDE then parses as |
//| a function pointer comparison and flags as an error.             |
//+------------------------------------------------------------------+
// clang-format off

#ifdef __MQL5__
input group "1 - ACCOUNT PROFILE"
#endif
input ENUM_FN_PLAN         InpPlan        = FN_PLAN_STELLAR_LITE; // Prop-firm plan (Stellar 1-Step / 2-Step / Lite / Instant / Free)
input ENUM_FN_PHASE        InpPhase       = FN_PHASE_FUNDED;      // Phase : Challenge P1/P2 or Funded (drives which rules apply)
input ENUM_FN_ACCT_SIZE    InpAccountSize = FN_SIZE_25K;          // Account balance (USD ; preset dropdown, no typos)
input ENUM_FN_ACCOUNT_TYPE InpAccountType = FN_ACCOUNT_SWAP;      // Account type (Swap / Swap-Free / Raw ...)

#ifdef __MQL5__
input group "2 - ADD-ONS (toggle what you purchased)"
#endif
input bool InpAddon_Lifetime95 = true;   // Lifetime Payout 95% add-on
input bool InpAddon_NoMinDays  = true;   // No Minimum Trading Days add-on
input bool InpAddon_SwapFree   = false;  // Swap-Free add-on
input bool InpAddon_10PctDD    = false;  // 10% Total Loss Limit (Lite only)
input bool InpAddon_DoubleUp   = false;  // Double Up add-on
input bool InpAddon_BiWeekly   = false;  // Bi-Weekly Reward add-on

#ifdef __MQL5__
input group "3 - STRATEGY (your trading plan)"
#endif
input int    InpMaxParallelPositions = 5;    // Max parallel positions you plan to open (count)
input double InpSlPricePct           = 1.0;  // SL distance (% of price ; V1 locked 1.0 = safest)
input double InpTpPricePct           = 0.1;  // TP distance (% of price ; scalping default)
input double InpMaxMarginPerTradePct = 25.0; // Max margin per single trade (% ; FN rec 20-30)
input double InpMaxRiskPerTradePct   = 1.0;  // Max risk per single trade (% ; ceiling = min(cap/N, this))
input bool   InpEnablePyramidSafe    = false;// Safe pyramiding advisor (decreasing-lot + unified stop)
input double InpPyramidLotRatio      = 0.66; // Pyramid lot ratio (V_next = V_cur x ratio ; < 1 = decreasing)
input double InpPyramidSafetyPct     = 10.0; // Pyramid safety (% of initial R kept beyond breakeven)

#ifdef __MQL5__
input group "4 - POST-VIOLATION CAPS (FN 2nd-strike)"
#endif
input bool   InpMarginViolationActive = false; // Had a margin violation -> tighten cumulative margin cap
input bool   InpRiskViolationActive   = false; // Had a risk violation   -> tighten cumulative risk cap
input double InpMarginCapViolated     = 30.0;  // Tightened cumulative margin cap (% ; FN 2nd strike = 30)
input double InpRiskCapViolated       = 1.0;   // Tightened cumulative risk cap   (% ; FN 2nd strike = 1)

#ifdef __MQL5__
input group "5 - ALERTS"
#endif
input bool   InpEnableSound      = true;          // Sound alert on warn/red transitions
input string InpSoundOK          = "alert.wav";   // Sound file : back to OK
input string InpSoundWarn        = "alert2.wav";  // Sound file : warning
input string InpSoundRed         = "stops.wav";   // Sound file : breach / red
input bool   InpEnableTelegram   = false;         // Telegram alerts (V2)
input string InpTelegramBotToken = "";            // Telegram bot token
input string InpTelegramChatId   = "";            // Telegram chat id

#ifdef __MQL5__
input group "6 - TRADING-DAYS COUNTER"
#endif
input string InpCycleStartIso = "2026-05-09";     // Cycle start (YYYY-MM-DD ; 'Days traded' counter only)

#ifdef __MQL5__
input group "7 - DISPLAY & PANEL"
#endif
input bool          InpShowNews              = true;                // Show economic-calendar news on the chart
input ENUM_RC_THEME InpTheme                 = RC_THEME_GLASS_DARK; // Panel theme (Glass Dark / Glass Light)
input ENUM_RC_LANG  InpLang                  = RC_LANG_EN;          // UI language (EN / FR / ES)
input int           InpAnchorX               = 20;                  // Panel X offset from chart top-left (px)
input int           InpAnchorY               = 100;                 // Panel Y offset (px ; clears MT5 one-click panel)
input int           InpPanelWidth            = 620;                 // Panel width (px)
input int           InpRowHeight             = 22;                  // Panel row height (px)
input int           InpRefreshMs             = 500;                 // Panel refresh interval (ms)
input bool          InpComfortScale          = true;                // Keep padding above/below candles (never glued)
input double        InpComfortMarginPct      = 15.0;                // Comfort padding (% of visible range, top & bottom)
input bool          InpDisciplineLockEnabled = true;                // Master switch : discipline lock (DD + tilt + cooldown + self-lock)

#ifdef __MQL5__
input group "8 - DISCIPLINE LOCK (anti-tilt, advisory)"
#endif
input int InpTiltTradesN    = 5;   // Tilt : more than this many trades in the window = warn (count)
input int InpTiltWindowMin  = 15;  // Tilt : rapid-trade window (minutes)
input int InpCooldownLosses = 3;   // Cooldown : consecutive losing trades that trigger it (count)
input int InpCooldownMin    = 30;  // Cooldown : minutes to wait after the streak
input int InpSelfLockHours  = 2;   // Self-lock : default duration of the "Lock me" button (hours)

// clang-format on

//+------------------------------------------------------------------+
//| Theme colors - PREMIUM restyle (v1.4). Values set in InitTheme    |
//| with C'r,g,b' literals (slate + cyan + semantic risk). The new    |
//| surface/gradient tokens feed the P1 CCanvas backdrop ; the legacy |
//| fields (bg / bg_section / border / accent / text / ok / warn /    |
//| red / bar_bg) keep every existing draw call working unchanged.    |
//+------------------------------------------------------------------+
struct ThemeColors {
    // --- base surface stack (deep -> lifted ; premium slate) ---
    color bg_deep;    // deepest shade : drop-shadow, gradient bottom, edit fields
    color bg;         // panel base background (gradient bottom band)
    color bg_lift;    // lifted base (gradient top band)
    color bg_section; // section header background
    color surface;    // bento card fill
    color surface_hi; // raised / hover card fill
    // --- lines ---
    color border;     // card + outer border
    color border_hi;  // brighter border (hover / focus)
    // --- accents & text ---
    color accent;     // primary accent (cyan)
    color accent2;    // secondary accent (indigo)
    color text;       // main text
    color label;      // muted label text (between text and text_dim)
    color text_dim;   // dimmest text
    // --- semantic risk (gauge : safe -> warn -> breach) ---
    color ok;         // green  (safe)
    color warn;       // amber  (warning)
    color red;        // red    (breach)
    color bar_bg;     // empty meter-bar track
};

ThemeColors g_theme;

// PREMIUM (v1.4) : CCanvas FX overlay. A soft glow ring around the panel that
// pulses RED when a risk / margin / DD rule is breaching. The bitmap's CENTER
// is fully transparent, so it never covers panel content (draw + click safe) ;
// its opaque glow lives in a margin band around the panel edge (over the chart).
// Named "RC_fx" -> dragged by MovePanelBy, cleared by DestroyAllObjects, and the
// GPU resource is freed in OnDeinit / before every re-create.
CCanvas g_fx;
bool    g_fx_on = false;
bool    g_fx_was_breach = false;   // gate idle GPU updates (only redraw while breaching / on clear)
int     g_fx_w  = 0;
int     g_fx_h  = 0;
#define RC_FX_MARGIN 12

// v1.4 MODERN : the panel body is drawn in ONE CCanvasKit bitmap (rounded card,
// soft gradient, drop shadow, hairline dividers, rounded-end meters + pills).
// It sits UNDER the text (OBJ_LABEL) and controls, and under g_fx (the glow).
CCanvasKit g_kit;
#define RC_KIT_MARGIN 16   // shadow / rounding room around the panel
#define RC_R_PANEL    13   // panel corner radius
#define RC_R_CARD     10   // inner card corner radius
// v1.4 dev : optional BUILD tag in the title bar (per modern phase during dev :
// "R1", "R2"...). EMPTY = clean release (no tag drawn). NOT the Market version.
#define RC_BUILD_TAG  "R3"

void InitTheme(void) {
    // G3 : route through EffectiveTheme so the settings popup can switch
    // dark/light at runtime without re-opening MT5 Inputs.
    if (EffectiveTheme() == RC_THEME_GLASS_DARK) {
        // PREMIUM slate + cyan + semantic (aligned with StrategyDeck for a
        // coherent product family). C'r,g,b' = plain RGB, easier to reason about.
        g_theme.bg_deep    = C'10,14,22';    // deepest (shadow, gradient bottom, edits)
        g_theme.bg         = C'15,23,42';    // base
        g_theme.bg_lift    = C'22,32,56';    // gradient top
        g_theme.bg_section = C'20,28,48';    // section header
        g_theme.surface    = C'30,41,59';    // bento card
        g_theme.surface_hi = C'34,46,69';    // raised / hover
        g_theme.border     = C'51,65,85';    // border
        g_theme.border_hi  = C'61,79,110';   // border hover
        g_theme.accent     = C'56,189,248';  // cyan
        g_theme.accent2    = C'129,140,248'; // indigo
        g_theme.text       = C'232,238,247'; // near-white
        g_theme.label      = C'159,176,200'; // muted label
        g_theme.text_dim   = C'100,116,139'; // dim
        g_theme.ok         = C'52,211,153';  // green  (safe)
        g_theme.warn       = C'251,191,36';  // amber  (warn)
        g_theme.red        = C'248,113,113'; // red    (breach)
        g_theme.bar_bg     = C'22,32,56';    // meter track
    } else // GLASS_LIGHT
    {
        g_theme.bg_deep    = C'226,232,240';
        g_theme.bg         = C'241,245,249';
        g_theme.bg_lift    = C'248,250,252';
        g_theme.bg_section = C'226,232,240';
        g_theme.surface    = C'255,255,255';
        g_theme.surface_hi = C'241,245,249';
        g_theme.border     = C'203,213,225';
        g_theme.border_hi  = C'148,163,184';
        g_theme.accent     = C'2,132,199';   // cyan-700 (readable on light)
        g_theme.accent2    = C'79,70,229';   // indigo-600
        g_theme.text       = C'15,23,42';
        g_theme.label      = C'71,85,105';
        g_theme.text_dim   = C'100,116,139';
        g_theme.ok         = C'22,163,74';   // green-600
        g_theme.warn       = C'202,138,4';   // amber-600
        g_theme.red        = C'220,38,38';   // red-600
        g_theme.bar_bg     = C'226,232,240';
    }
}

//+------------------------------------------------------------------+
//| Layout constants                                                 |
//+------------------------------------------------------------------+
#define RC_PREFIX "RC_"
#define RC_PAD 10
#define RC_TITLE_HEIGHT 30
#define RC_TITLE_CLOCK_W 120 // FIX 7 : reserved right zone for the clock (news/weekend/LIVE) so it never overlaps the balance
#define RC_LOGO_FILE "RiskCockpit_logo.bmp" // fixed header logo asset under MQL5\Images\ (not a user input)
#define RC_SECTION_HEIGHT 22
#define RC_FONT "Consolas"                  // numeric / tabular data (right-aligned)
#define RC_FONT_NUM "Consolas"               // alias : numbers
#define RC_FONT_UI "Segoe UI"                // labels / body (premium restyle P2)
#define RC_FONT_UI_SB "Segoe UI Semibold"    // titles / emphasis
#define RC_FONT_SIZE 9
#define RC_FONT_SIZE_TITLE 11
#define RC_FONT_SIZE_LABEL 8                 // small muted labels
#define RC_MAX_POSITIONS 10

//+------------------------------------------------------------------+
//| Status enumeration (rule status)                                 |
//+------------------------------------------------------------------+
enum ENUM_RC_STATUS {
    RC_STATUS_NA = 0,
    RC_STATUS_OK = 1,
    RC_STATUS_WARN = 2,
    RC_STATUS_RED = 3
};

//+------------------------------------------------------------------+
//| Rule row definition                                              |
//+------------------------------------------------------------------+
struct RuleRow {
    string key;        // internal id  (also used in object names)
    string label;      // displayed left
    double value_pct;  // 0..100 (or 0 if N/A)
    double max_pct;    // upper bound for the bar
    string value_text; // free-form ("35% / 70%" or "N/A")
    ENUM_RC_STATUS status;
    bool applies; // false -> shown greyed
};

#define RC_RULE_COUNT 11
RuleRow g_rows[RC_RULE_COUNT];

void DefineRules(void) {
    g_rows[0].key = "rule_margin_cum";
    g_rows[0].label = "Cumulative Margin";
    g_rows[1].key = "rule_margin_pt";
    g_rows[1].label = "Max lot allowed"; // 1.1 : was "Per-Trade Margin" (bar hidden in indicator)
    g_rows[2].key = "rule_risk_cum";
    g_rows[2].label = "Cumulative Open Risk";
    g_rows[3].key = "rule_daily_dd";
    g_rows[3].label = "Daily DD";
    g_rows[4].key = "rule_overall_dd";
    g_rows[4].label = "Overall DD";
    g_rows[5].key = "rule_target";
    g_rows[5].label = "Profit Target";
    g_rows[6].key = "rule_qs";
    g_rows[6].label = "Quick Strike Ratio";
    g_rows[7].key = "rule_hyper";
    g_rows[7].label = "Hyperactivity (trades)";
    g_rows[8].key = "rule_news";
    g_rows[8].label = "News Window";
    g_rows[9].key = "rule_msgs";
    g_rows[9].label = "Server msgs (orders)";
    g_rows[10].key = "rule_newsstats";          // V1.24 G2 : text-only News-Trading stats row
    g_rows[10].label = "News Trades";
    for (int i = 0; i < RC_RULE_COUNT; ++i) {
        g_rows[i].value_pct = 0.0;
        g_rows[i].max_pct = 100.0;
        g_rows[i].value_text = "--";
        g_rows[i].status = RC_STATUS_NA;
        g_rows[i].applies = true;
    }
}

//+------------------------------------------------------------------+
//| Profile + catalog (module state)                                 |
//+------------------------------------------------------------------+
CChallengeProfileCatalog g_catalog;
ChallengeProfile g_profile;
bool g_profile_ok = false;
int g_addons_mask = FN_ADDON_NONE;

// Pyramid Safe advisor (D, art. 22187). Engine is read-only -- it computes
// the plan, never sends orders. Activated by InpEnablePyramidSafe.
CPyramidEngine g_pyramid_engine;

// Live-state caches (T7)
datetime g_day_start = 0;
double g_peak_equity = 0.0;
ENUM_RC_STATUS g_last_status[RC_RULE_COUNT];

// Last-seen position ticket list (used to detect open/close and refresh SL lines)
ulong g_last_tickets[];

// Suppress sound alerts during the very first refresh (OnInit, timeframe switch).
bool g_alerts_armed = false;

// Telegram per-rule rate limiter : last alert timestamp per rule index.
// 15-second cooldown per rule prevents spam on flapping transitions.
datetime g_last_telegram_alert[RC_RULE_COUNT];
#define RC_TELEGRAM_COOLDOWN_SEC 15

// Post-violation tightening (B7). Runtime-mutable via clickable checkboxes
// in front of the Margin / Risk rows; persisted across reattach via
// GlobalVariable. When active, the EFFECTIVE cumulative cap drops to the
// tightened value (FN 2nd-strike : margin 30 %, risk 1 %).
bool g_margin_violation_active = false;
bool g_risk_violation_active   = false;

// M1b : throttle for the max-lot margin debug Print (avoid Experts-log spam).
datetime g_maxlot_dbg_last = 0;
// FIX (LOT 1) : caches throttlent les scans lourds dans OnTimer pour eviter que
// OBJECT_CLICK ne soit affame (le panel update mais les boutons ne repondent plus).
datetime g_realised_today_scan  = 0;     // CachedRealisedToday throttle (2 s)
double   g_realised_today_cache = 0.0;
datetime g_days_scan            = 0;     // Live_TradingDaysCount throttle (30 s)
int      g_days_cache           = 0;
datetime g_news_last_refresh    = 0;     // RefreshNewsZones throttle (30 s)
// FIX (LOT 2) : QuickStrike cache - QS only changes when a trade closes (rare),
// throttle 5 s to spare the full history scan + nested matching loop.
datetime g_qs_scan  = 0;
double   g_qs_cache = 0.0;
// FIX (LOT 2) : "locked risk" map = ticket -> initial SL (the SL posed at opening,
// the value FundedNext locks the 3 % rule against). Tightening the SL later does
// NOT reduce the locked risk. Entries persist while the position is open and are
// dropped on the fly when the position closes.
struct PositionInitialSl {
    ulong  ticket;
    double initial_sl;
};
PositionInitialSl g_initial_sls[];
// LOT 4 : current UI language (initialised from InpLang in OnInit ; a future
// in-panel switcher in LOT 5 will let the user change it without re-opening
// the Inputs dialog, persisted via GlobalVariable).
int g_lang = 0;
// LOT 4 : i18n string table (parallel arrays, dynamic-init in OnInit to keep
// MQL5 string-array initialiser portable across builds). Add an entry below +
// initialise its row in InitI18n().
string g_i18n_keys[];
string g_i18n_en[];
string g_i18n_fr[];
string g_i18n_es[];
// LOT 5 : breakeven lines toggle. Click "BE" on the TF bar -> draws an OBJ_HLINE
// at each open position's price_open on the current chart symbol ; lines are
// SELECTABLE so the user can drag them by hand (the companion EA V2 executes
// the actual move-to-BE on the broker).
bool g_be_visible = false;
// M1c : debug breadcrumbs filled by MarginPerLot (path = ocm/ocm_retry/mi/calcmode/fail).
string g_maxlot_path = "none";
string g_maxlot_dbg2 = ""; // FIX 2 : fallback diagnostics (mccy/fx/tv/ts/cs) for the debug line
// FIX 6 : the padded vertical scale we last applied (to tell our scale from a manual zoom).
double g_cs_min = 0.0;
double g_cs_max = 0.0;
double g_maxlot_m1   = 0.0;
int    g_maxlot_err  = 0;
// B-SPREAD-COMM : commission per lot for the active symbol, derived from the
// most recent closed deal (no universal symbol-property exists). Cached + a
// 60 s throttle so the history scan never runs on the 500 ms refresh path.
double   g_comm_per_lot = -1.0;  // -1 = unknown (no recent deal on this symbol)
datetime g_comm_scan    = 0;
string   g_comm_sym      = "";
// V1.24 G3 B-COPY : raw lot numbers exposed in read-only OBJ_EDIT fields so the
// trader can click + Ctrl+C them into the native order panel (no clipboard DLL).
double   g_maxlot_copy  = 0.0;   // broker max lot for the active symbol
int      g_maxlot_digits = 2;    // display digits derived from SYMBOL_VOLUME_STEP
double   g_suglot_copy  = 0.0;   // suggested lot
double MarginPerLot(const string sym);
double MaxLotAllowed(const string sym, double cap_pct, double balance);

// B-LOTPRECISION : derive the number of lot-display decimals from
// SYMBOL_VOLUME_STEP. Crypto on AvaTrade/Binance can have step=0.00001 ;
// printing such a lot with "%.2f" yields "0.00" which is unreadable and
// makes the suggested-lot row look broken. step=0.01 -> 2, 0.001 -> 3,
// 0.00001 -> 5, 1.0 -> 0. Fallback : 2 decimals (forex/indices default).
int LotDigits(const double step) {
    if (step <= 0.0) return 2;
    int d = 0;
    double s = step;
    while (s < 0.9999999 && d < 8) { s *= 10.0; ++d; }
    return d;
}
int LotDigits(const string sym) {
    return LotDigits(SymbolInfoDouble(sym, SYMBOL_VOLUME_STEP));
}

// G3 : EffectivePlan / EffectiveTheme route the resolution between the input
// default and the runtime override coming from the settings popup. The popup
// writes the override + a GV so the choice survives reattach.
ENUM_FN_PLAN EffectivePlan(void) {
    if (g_active_plan_idx < 0) return InpPlan;
    return (ENUM_FN_PLAN)g_active_plan_idx;
}
ENUM_RC_THEME EffectiveTheme(void) {
    if (g_active_theme_idx < 0) return InpTheme;
    return (ENUM_RC_THEME)g_active_theme_idx;
}

// G2 : seed the runtime-mutable shadow settings from the inputs, then let any
// persisted GlobalVariable (written by a previous settings-popup change) win.
// Called once in OnInit, AFTER BuildAddonsMask() (so the RC_addons override
// lands on the already-built mask).
void InitEffectiveSettings(void) {
    g_eff_size          = (double)InpAccountSize;
    g_eff_acct_type     = (int)InpAccountType;
    g_eff_phase         = (int)InpPhase;
    g_eff_sl_pct        = InpSlPricePct;
    g_eff_tp_pct        = InpTpPricePct;
    g_eff_max_margin_pt = InpMaxMarginPerTradePct;
    g_eff_max_risk_pt   = InpMaxRiskPerTradePct;
    g_eff_show_news     = InpShowNews;
    g_eff_news_high     = true; // V1.29 R : levels default ON (no input ; GV-persisted)
    g_eff_news_med      = true;
    g_eff_comfort       = InpComfortScale;
    g_eff_discipline    = InpDisciplineLockEnabled;
    g_eff_sound         = InpEnableSound;
    g_eff_telegram      = InpEnableTelegram;
    g_eff_tilt_n        = InpTiltTradesN;
    g_eff_tilt_win      = InpTiltWindowMin;
    g_eff_cooldown_n    = InpCooldownLosses;
    g_eff_cooldown_m    = InpCooldownMin;
    g_eff_selflock_h    = InpSelfLockHours;
    g_eff_comfort_pct   = InpComfortMarginPct;
    // V1.29 J : risk-tools master switch defaults OFF on a Personal account.
    // V1.29 M : risk-tools is PERSONAL-ONLY. Prop accounts are ALWAYS ON (the
    // toolkit cannot be disabled) ; Personal defaults OFF and its RC_risktools
    // toggle decides. Resolved here (seed + GV folded) so a Personal "OFF" GV
    // can never leak onto a prop account.
    if (PlanIsPersonal()) {
        g_eff_risktools = false;
        if (GlobalVariableCheck("RC_risktools"))
            g_eff_risktools = (GlobalVariableGet("RC_risktools") != 0.0);
    } else {
        g_eff_risktools = true; // PROP : always ON, ignores input + GV
    }
    // V1.29 I : Personal type auto-detected (Demo if the broker account is a demo).
    g_eff_personal_demo = (AccountInfoInteger(ACCOUNT_TRADE_MODE) == ACCOUNT_TRADE_MODE_DEMO) ? 1 : 0;
    if (GlobalVariableCheck("RC_size"))       g_eff_size          = GlobalVariableGet("RC_size");
    if (GlobalVariableCheck("RC_acct_type"))  g_eff_acct_type     = (int)GlobalVariableGet("RC_acct_type");
    if (GlobalVariableCheck("RC_phase"))      g_eff_phase         = (int)GlobalVariableGet("RC_phase");
    if (GlobalVariableCheck("RC_sl_pct"))     g_eff_sl_pct        = GlobalVariableGet("RC_sl_pct");
    if (GlobalVariableCheck("RC_tp_pct"))     g_eff_tp_pct        = GlobalVariableGet("RC_tp_pct");
    if (GlobalVariableCheck("RC_mm_pt"))      g_eff_max_margin_pt = GlobalVariableGet("RC_mm_pt");
    if (GlobalVariableCheck("RC_mr_pt"))      g_eff_max_risk_pt   = GlobalVariableGet("RC_mr_pt");
    if (GlobalVariableCheck("RC_show_news"))  g_eff_show_news     = (GlobalVariableGet("RC_show_news")  != 0.0);
    if (GlobalVariableCheck("RC_news_high"))  g_eff_news_high     = (GlobalVariableGet("RC_news_high")  != 0.0);
    if (GlobalVariableCheck("RC_news_med"))   g_eff_news_med      = (GlobalVariableGet("RC_news_med")   != 0.0);
    if (GlobalVariableCheck("RC_comfort"))    g_eff_comfort       = (GlobalVariableGet("RC_comfort")    != 0.0);
    if (GlobalVariableCheck("RC_discipline")) g_eff_discipline    = (GlobalVariableGet("RC_discipline") != 0.0);
    if (GlobalVariableCheck("RC_sound"))      g_eff_sound         = (GlobalVariableGet("RC_sound")      != 0.0);
    if (GlobalVariableCheck("RC_telegram"))   g_eff_telegram      = (GlobalVariableGet("RC_telegram")   != 0.0);
    if (GlobalVariableCheck("RC_perso_demo")) g_eff_personal_demo = (int)GlobalVariableGet("RC_perso_demo");     // V1.29 I
    if (GlobalVariableCheck("RC_addons"))     g_addons_mask       = (int)GlobalVariableGet("RC_addons");
    // V1.24 G1 : restore an active self-lock so it survives reattach / VPS reboot.
    if (GlobalVariableCheck("RC_selflock_until")) g_selflock_until = (datetime)GlobalVariableGet("RC_selflock_until");
    if (GlobalVariableCheck("RC_tilt_n"))     g_eff_tilt_n      = (int)GlobalVariableGet("RC_tilt_n");
    if (GlobalVariableCheck("RC_tilt_win"))   g_eff_tilt_win    = (int)GlobalVariableGet("RC_tilt_win");
    if (GlobalVariableCheck("RC_cool_n"))     g_eff_cooldown_n  = (int)GlobalVariableGet("RC_cool_n");
    if (GlobalVariableCheck("RC_cool_m"))     g_eff_cooldown_m  = (int)GlobalVariableGet("RC_cool_m");
    if (GlobalVariableCheck("RC_selflock_h")) g_eff_selflock_h  = (int)GlobalVariableGet("RC_selflock_h");
    if (GlobalVariableCheck("RC_comfort_pct"))g_eff_comfort_pct = GlobalVariableGet("RC_comfort_pct");
    // V1.27 seeds : profit-split override, cycle date, post-violation caps, refresh.
    g_eff_margin_cap_viol = InpMarginCapViolated;
    g_eff_risk_cap_viol   = InpRiskCapViolated;
    g_eff_refresh_ms      = InpRefreshMs;
    g_eff_cycle_ymd       = IsoToYmd(InpCycleStartIso); // 0 if parse fails -> falls back to the Inp string
    if (GlobalVariableCheck("RC_split"))      g_eff_split           = GlobalVariableGet("RC_split");
    if (GlobalVariableCheck("RC_cycle_ymd"))  g_eff_cycle_ymd       = GlobalVariableGet("RC_cycle_ymd");
    if (GlobalVariableCheck("RC_mcap_viol"))  g_eff_margin_cap_viol = GlobalVariableGet("RC_mcap_viol");
    if (GlobalVariableCheck("RC_rcap_viol"))  g_eff_risk_cap_viol   = GlobalVariableGet("RC_rcap_viol");
    if (GlobalVariableCheck("RC_refresh_ms")) g_eff_refresh_ms      = (int)GlobalVariableGet("RC_refresh_ms");
}

void BuildAddonsMask(void) {
    g_addons_mask = FN_ADDON_NONE;
    if (InpAddon_Lifetime95)
        g_addons_mask |= FN_ADDON_LIFETIME_95;
    if (InpAddon_NoMinDays)
        g_addons_mask |= FN_ADDON_NO_MIN_DAYS;
    if (InpAddon_SwapFree)
        g_addons_mask |= FN_ADDON_SWAP_FREE;
    if (InpAddon_10PctDD)
        g_addons_mask |= FN_ADDON_10PCT_DD;
    if (InpAddon_DoubleUp)
        g_addons_mask |= FN_ADDON_DOUBLE_UP;
    if (InpAddon_BiWeekly)
        g_addons_mask |= FN_ADDON_BI_WEEKLY;
}

//+------------------------------------------------------------------+
//| Forward declarations                                             |
//+------------------------------------------------------------------+
void DestroyAllObjects(void);
void BuildPanel(void);
void RefreshPanel(void);
void DrawTitleBar(int x, int y, int w);
bool RiskIsBreaching(void);                        // v1.4 FX overlay
void RenderFx(void);                               // v1.4 FX overlay
void CreateFxCanvas(int x, int y, int w, int h);   // v1.4 FX overlay
void RepaintCanvas(int x, int y, int w);           // v1.4 modern body canvas
void RiskFillColors(const ENUM_RC_STATUS s, color &a, color &b); // v1.4 modern body canvas
void DrawAccountStrip(int x, int y, int w);
void DrawSectionHeader(const string id, int x, int y, int w, const string title, color accent);
void   DrawTimeframeBar(int x, int y, int w);   // LOT 4 : M1/M5/M15/M30/H1/H4/D1 quick-switch
void   InitI18n(void);                          // LOT 4 : populate g_i18n_* tables once
string Tr(const string key);                    // LOT 4 : translate by key + g_lang
void   DrawBreakevenLines(void);                // LOT 5 : BE lines on open positions
void   DrawSetButton(const string id, int x, int y, int w, int h, const string text); // G3
void   HighlightSetButton(const string id, bool active);                              // G3
void   DrawSettingsOverlay(int panel_x, int panel_y, int panel_w);                    // G3
void   ApplySettingsChange(void);                                                     // G3
void   ClearBreakevenLines(void);               // LOT 5 : remove all BE lines
// LOT 6 : single-glance verdict badge + safety score (replaces the LIVE blinker
// in the title bar's clock zone when no weekend / news countdown is active).
struct VerdictResult { string text; color clr; int score; };
void   ComputeVerdict(VerdictResult &out);
void   PersistBE(void);
void   PersistLang(void);
int DrawRulesSection(int x, int y, int w);
int DrawPositionsSection(int x, int y, int w);
void DrawFooter(int x, int y, int w);
void DrawRuleRow(const string key_prefix, int idx,
                 int x, int y, int w, int h,
                 const string label, const string value_text,
                 double pct, double max_pct,
                 ENUM_RC_STATUS status, bool applies);
void DrawStatusChip(const string id, int x, int y, int w, int h, ENUM_RC_STATUS status);
void DrawProgressBar(const string id, int x, int y, int w, int h,
                     double pct, double max_pct, ENUM_RC_STATUS status);
void DrawRect(const string id, int x, int y, int w, int h, color bg, color border, int width = 1);
void DrawLabel(const string id, int x, int y, const string text, color clr,
               int font_size = RC_FONT_SIZE, const string font = RC_FONT);
string StatusLabel(ENUM_RC_STATUS s);
color StatusColor(ENUM_RC_STATUS s);
color GradientColor(double r);                                        // LOT E color-graded bars
bool  UpdateDisciplineOverlay(double daily_dd_pct, double daily_cap); // V1.24 : true if hard-locked
void  DrawTiltBanner(void);                                           // V1.24 : soft tilt banner
string FormatMoney(double v);
string FormatPct(double v);
int DaysBetweenIso(const string iso_a, const string iso_b);
void UpdateClockBlinker(void);
void ApplyComfortScale(bool force); // FIX 6
void ApplyComfortScaleToChart(long chart_id, const string sym);     // LOT D B-RESIZE-ALL
void ApplyComfortScaleAllCharts(void);                              // LOT D B-RESIZE-ALL
bool ComputeBasketBreakeven(const string symbol, double &out_be_price,
                            bool &out_is_hedged_flat, double &out_flat_pnl,
                            string &out_reason); // LOT D B-BE-UNIFIED
void UpdateRow(int idx, double pct, double max_pct, const string value_text,
               ENUM_RC_STATUS status, bool applies);
ENUM_RC_STATUS ComputeRangeStatus(double v, double max_v, double warn_ratio, double red_ratio);
ENUM_RC_STATUS ComputeBandStatus(double v, double lo, double hi);
void RefreshPositionsList(void);
void RefreshAccountStrip(void);

// Live computation helpers (T7)
double Live_CumulativeMarginPct(void);
double Live_PerTradeMarginPct(void);
double Live_CumulativeRiskPct(void);
double Live_LockedRiskPct(void);   // FIX (LOT 2) : sum of risks at INITIAL SLs (FN-locked)
double Live_DailyDdPct(void);
double Live_OverallDdPct(void);
double Live_ProfitTargetPct(void);
double Live_QuickStrikeRatioPct(void);
int Live_TradesToday(void);
int Live_OrdersToday(void);
bool Live_InNewsWindow(void);
datetime Live_NextNewsEvt(void);
int Live_OpenPositionsCount(void);

// T7 state + helpers
void UpdatePeakEquity(void);
double ComputePositionRiskMoney(const string sym, const int type,
                                const double price_open, const double sl,
                                const double vol);
void RefreshSlLines(void);
void RefreshNewsZones(void);
string FormatAge(int seconds);
string PositionStatusLabel(ENUM_RC_STATUS s, int age, bool sl_missing);
void TryFireSoundAlert(int idx, ENUM_RC_STATUS new_status);
bool PositionListChanged(void);
void SnapshotPositionList(void);

// Telegram (B1) - alert dispatcher + low-level sender
string EscapeJson(const string s);
bool SendTelegramMessage(const string text);

// Safe Pyramiding advisor (D, art. 22187)
void RefreshPyramidLine(void);

// Post-violation tightening (B7)
double EffectiveMarginCap(void);
double EffectiveRiskCap(void);
bool   ProfileCanBeRestricted(void);
void PersistViolationFlags(void);
void DrawViolationToggle(const string key, int x, int y, int h, bool active);

// V2 (this revision) - profit metrics + suggested lot + editable max parallel
double SumClosedDealsPnL(const datetime from, const datetime to);
double SumFloatingPnL(void);
double Live_TodayProfit(void);
double CachedRealisedToday(void); // FIX (LOT 1) : throttled SumClosedDealsPnL(today, now)
double Live_TotalProfit(void);
double Live_TotalProfitPct(void);
int Live_TradingDaysCount(void);
double Live_AvgDailyProfit(void);
double Live_SuggestedLot(void);
double Live_PerTradeBudgetPct(int n_for_share);
double Live_NextTradeBudgetPct(void);
double Live_DailyRiskBonus(void);
double Live_PerTradeCap(void);
void RefreshFooterMetrics(void);
void DrawMaxParallelControl(int x, int y);
void PersistMaxParallel(void);
void RefreshSlLinesForChart(const long chart_id);
void RefreshNewsZonesForChart(const long chart_id);
string NewsAbbrev(const string name); // N10 : short code for top news caption
int g_max_parallel = 5; // runtime-mutable; init from InpMaxParallelPositions

// B8 : recent-symbols quick-switch bar (FIFO, max 4, most-recent-first).
// Rebuilt from open positions + recent deals (history persists -> no need to
// store strings in GlobalVariable, which only holds doubles anyway).
#define RC_MAX_RECENT_SYMS 4
string g_recent_syms[];   // up to 4 symbols, most-recent first
string g_pos_sym[RC_MAX_POSITIONS]; // V1.27 : per-row symbol so a position row is click-to-switch
int    g_recbar_y = 0;    // y-coordinate of the bar (set in BuildPanel)
int    g_tfbar_y  = 0;    // P4 : y of the TF/control bar (copy-lot fields live here)
int    g_footer_y = 0;    // P1 : y of the footer block (coloured info segments)
void UpdateRecentSymbols(void);
void DrawRecentSymbolsBar(int x, int y, int w);

// B2 : drag-to-move panel. g_anchor_x/y = live panel origin (init from
// InpAnchorX/Y, restored from GlobalVariable, persisted on drop).
int  g_anchor_x = 20;
int  g_anchor_y = 100;

// v1.4.1 R3 : HIT-TESTING for canvas-drawn ROUNDED controls (an OBJ_BUTTON is
// opaque + square). Each drawn control registers a zone + action string ; the
// CHARTEVENT_CLICK handler routes clicks by coordinate. Zones are stored RELATIVE
// to the panel anchor (g_anchor_x/y) so a DRAG never invalidates them : MovePanelBy
// shifts the objects, the anchor tracks the drag, and the relative offset is fixed.
struct RCHit { int x1, y1, x2, y2; string act; int idx; };
RCHit g_hits[]; int g_nhits = 0;
void HitReset(void) { g_nhits = 0; }
void HitAdd(const int x1, const int y1, const int x2, const int y2, const string act, const int idx = -1) {
    if (g_nhits >= ArraySize(g_hits)) ArrayResize(g_hits, g_nhits + 32);
    g_hits[g_nhits].x1 = x1 - g_anchor_x; g_hits[g_nhits].y1 = y1 - g_anchor_y; // store RELATIVE
    g_hits[g_nhits].x2 = x2 - g_anchor_x; g_hits[g_nhits].y2 = y2 - g_anchor_y;
    g_hits[g_nhits].act = act; g_hits[g_nhits].idx = idx; g_nhits++;
}
bool HitTest(const int mx, const int my, string &act, int &idx) {
    const int rx = mx - g_anchor_x, ry = my - g_anchor_y; // click -> panel-relative (drag-proof)
    for (int i = g_nhits - 1; i >= 0; --i)  // last-registered (top-most) wins
        if (rx >= g_hits[i].x1 && rx <= g_hits[i].x2 && ry >= g_hits[i].y1 && ry <= g_hits[i].y2) {
            act = g_hits[i].act; idx = g_hits[i].idx; return true;
        }
    return false;
}
// AUDIT 2026-06-07 fix #5 : hoisted from BuildPanel so the discipline-lock
// overlay can cover the FULL panel (was ~title+1 row = ~8 % of the panel).
int  g_panel_height = 0;
// V1.20 G3 settings popup : runtime overrides (persisted in GV) so the user
// can change language / theme / prop preset without re-opening MT5's Inputs
// dialog. -1 = use the Input as-is.
int  g_active_plan_idx  = -1;   // -1 = InpPlan, else cast to ENUM_FN_PLAN
int  g_active_theme_idx = -1;   // -1 = InpTheme, else 0 = DARK, 1 = LIGHT
bool g_settings_open    = false;
int  g_settings_tab     = 0;    // 0=Account 1=Risk 2=Display 3=Alerts
// G2 B-SETTINGS-FULL : runtime-mutable shadows of the editable inputs. MQL5
// `input` variables are READ-ONLY at runtime, so the in-panel settings centre
// works on these instead. Initialised from the Inp* defaults in OnInit (a
// persisted GlobalVariable wins so a popup change survives reattach / VPS).
// Read everywhere via the g_eff_* name instead of the Inp* it shadows.
double g_eff_size          = 25000.0; // ENUM_FN_ACCT_SIZE value (USD)
int    g_eff_acct_type     = 0;       // ENUM_FN_ACCOUNT_TYPE
int    g_eff_phase         = 2;       // ENUM_FN_PHASE (FN_PHASE_FUNDED)
double g_eff_sl_pct        = 1.0;
double g_eff_tp_pct        = 0.1;
double g_eff_max_margin_pt = 25.0;
double g_eff_max_risk_pt   = 1.0;
bool   g_eff_show_news     = true;
bool   g_eff_news_high     = true; // V1.29 R : show HIGH-impact news (bars + counter)
bool   g_eff_news_med      = true; // V1.29 R : show MEDIUM-impact news (FN counts these too)
bool   g_eff_comfort       = true;
bool   g_eff_discipline    = true;
bool   g_eff_sound         = true;
bool   g_eff_telegram      = false;
bool   g_eff_risktools     = true; // V1.29 J : master ON/OFF for the prop risk toolkit
int    g_eff_personal_demo = 0;    // V1.29 I : Personal account type (0 = Real, 1 = Demo) - labeling only
// V1.26 : Advanced-tab tunables (discipline + comfort), runtime-editable.
int    g_eff_tilt_n      = 5;
int    g_eff_tilt_win    = 15;
int    g_eff_cooldown_n  = 3;
int    g_eff_cooldown_m  = 30;
int    g_eff_selflock_h  = 2;
double g_eff_comfort_pct = 15.0;
// V1.27 : cascade + extra exposed tunables (all runtime-editable, GV-persisted).
double g_eff_split           = -1.0;  // profit-split % override ; <0 = use catalog profit_split_pct ("Auto")
double g_eff_cycle_ymd       = 0.0;   // cycle start as YYYYMMDD double ; 0 = use InpCycleStartIso
double g_eff_margin_cap_viol = 30.0;  // tightened cumulative margin cap (post-violation)
double g_eff_risk_cap_viol   = 1.0;   // tightened cumulative risk cap (post-violation)
int    g_eff_refresh_ms      = 500;   // panel refresh period (ms) ; re-arms the timer on change
bool g_dragging = false;
int  g_drag_last_x = 0;
int  g_drag_last_y = 0;
void MovePanelBy(int dx, int dy);
void PersistAnchor(void);

// SuggestedLot breakdown so the panel can show why a lot was/wasn't suggested
struct SuggestedLot {
    bool ok;
    double math_lot;   // pure math, no clipping
    double broker_lot; // floored to step / clipped to min/max
    bool below_min;    // math < broker minimum
    bool over_budget;  // broker_lot risk > intended budget_pct
    double price;
    double sl_distance_price; // 10 % of current price
    double money_per_lot_at_sl;
    double risk_budget_money;
    double budget_pct;
    double vol_min;
    double vol_max;
    double vol_step;
    double tick_size;
    double tick_value;
    // B9 display fields (cap/N budget, live)
    int    n_planned;             // = g_max_parallel
    double dd_per_trade_pct;      // = EffectiveRiskCap() / N (cap/N pure, pre-clamp)
    double risk_cap;              // = EffectiveRiskCap() (3% or 1%)
    double used_risk_pct;         // cumulative open risk already engaged
    bool   reduce_flag;           // remaining cumulative budget < cap/N -> tighten
    double sl_level_buy;          // example SL price for a BUY (price - 1%)
    double next_trade_margin_pct; // margin the proposed lot would consume
    double margin_cap_per_trade;  // = g_eff_max_margin_pt (runtime shadow of InpMaxMarginPerTradePct)
    double total_margin_pct;      // open margin + proposed-trade margin
    double margin_cap_total;      // = EffectiveMarginCap() (70% or 30%)
    // FIX 8 (V1.0.2) : real broker free-margin awareness
    double free_margin_money;     // = ACCOUNT_MARGIN_FREE (nets out trades already open)
    double free_margin_pct;       // = 100 * free / balance
    bool   margin_bound;          // real free margin is the TIGHTEST constraint on the lot
    bool   margin_insufficient;   // free margin can't cover even the broker min lot
};

bool Live_ComputeSuggestedLot(SuggestedLot& out);

//+------------------------------------------------------------------+
//| OnInit                                                           |
//+------------------------------------------------------------------+
int OnInit(void) {
    // V1.28 : fixed short name so the title-bar X button can remove THIS instance
    // via ChartIndicatorDelete (no need to open the Indicators List).
    IndicatorSetString(INDICATOR_SHORTNAME, "RiskCockpit");
    // G3 : load settings-popup overrides BEFORE InitTheme + before catalog
    // Resolve so the persisted theme/plan choice survives reattach.
    if (GlobalVariableCheck("RC_plan_override"))
        g_active_plan_idx = (int)GlobalVariableGet("RC_plan_override");
    // V1.27 : a stale non-MT5 Futures plan restored from GV isn't in the cascade
    // -> normalise it to FundedNext's first type so broker/type steppers stay sane.
    if (g_active_plan_idx == (int)FN_PLAN_FUTURES_BOLT ||
        g_active_plan_idx == (int)FN_PLAN_FUTURES_RAPID ||
        g_active_plan_idx == (int)FN_PLAN_FUTURES_LEGACY) {
        ENUM_FN_PLAN vp[];
        PlansForVendor(0, vp);
        g_active_plan_idx = (int)vp[0];
        GlobalVariableSet("RC_plan_override", (double)g_active_plan_idx);
    }
    if (GlobalVariableCheck("RC_theme_override"))
        g_active_theme_idx = (int)GlobalVariableGet("RC_theme_override");
    InitTheme();
    DefineRules();
    BuildAddonsMask();
    InitEffectiveSettings(); // G2 : seed runtime-mutable settings (must be after BuildAddonsMask)
    // V1.28 : reconcile a persisted size/phase against the effective plan, in case
    // the plan came from InpPlan (not the cascade) while RC_size holds a value that
    // is illegal for it (e.g. Personal "Auto"=0 then a prop InpPlan -> 0 balance).
    SnapSizeToPlan(EffectivePlan());
    SnapPhaseToPlan(EffectivePlan());

    // Mutable copy of the user's planned-parallel input. If a previous
    // session persisted a value via PersistMaxParallel(), restore it so a
    // symbol/timeframe switch doesn't reset the user's manual choice.
    if (GlobalVariableCheck("RC_max_parallel"))
        g_max_parallel = MathMax(1, (int)GlobalVariableGet("RC_max_parallel"));
    else
        g_max_parallel = MathMax(1, InpMaxParallelPositions);

    // Post-violation flags (B7) : input is the default, GlobalVariable (set by
    // a previous click) wins so the tightened caps survive a reattach.
    g_margin_violation_active = InpMarginViolationActive;
    g_risk_violation_active   = InpRiskViolationActive;
    if (GlobalVariableCheck("RC_margin_violation"))
        g_margin_violation_active = (GlobalVariableGet("RC_margin_violation") != 0.0);
    if (GlobalVariableCheck("RC_risk_violation"))
        g_risk_violation_active = (GlobalVariableGet("RC_risk_violation") != 0.0);

    // B2 : restore panel anchor (drag position) ; default to inputs. Enable
    // mouse-move events so the title bar can be dragged.
    g_anchor_x = (int)InpAnchorX;
    g_anchor_y = (int)InpAnchorY;
    if (GlobalVariableCheck("RC_anchor_x")) g_anchor_x = (int)GlobalVariableGet("RC_anchor_x");
    if (GlobalVariableCheck("RC_anchor_y")) g_anchor_y = (int)GlobalVariableGet("RC_anchor_y");
    ChartSetInteger(0, CHART_EVENT_MOUSE_MOVE, true);

    // Free-account detection note (Server 3 / demo = free/competition heuristic).
    // No silent override: the user picks Free Trial / Free Competition in InpPlan.
    {
        const string srv = AccountInfoString(ACCOUNT_SERVER);
        const string co  = AccountInfoString(ACCOUNT_COMPANY);
        if ((StringFind(srv, "Server 3") >= 0 || StringFind(srv, "Demo") >= 0) &&
            InpPlan != FN_PLAN_FREE_TRIAL && InpPlan != FN_PLAN_FREE_COMPETITION &&
            StringFind(srv, "AvaTrade") < 0 && StringFind(co, "AvaTrade") < 0)
            Print("RiskCockpit : free/competition server detected ('", srv,
                  "'). If this is a Free Trial or Free Competition, select it in InpPlan.");
        // B-AVATRADE-PROFILE : suggest the Personal plan on broker-perso servers
        // (AvaTrade and any non-prop broker) so the panel runs without imposing
        // fake FundedNext rules. No silent override : JR picks the right plan.
        const bool is_personal_broker = (StringFind(srv, "AvaTrade") >= 0
                                      || StringFind(srv, "Ava-")    >= 0
                                      || StringFind(co,  "AvaTrade") >= 0
                                      || StringFind(co,  "Ava ")    >= 0);
        if (is_personal_broker && InpPlan != FN_PLAN_PERSONAL)
            Print("RiskCockpit : personal-broker server detected ('", srv,
                  "' / '", co, "'). Recommended : set InpPlan = FN_PLAN_PERSONAL to disable prop rules.");
        // LOT C : suggest the matching multi-firm preset (FTMO / E8 / The5ers /
        // SeacrestFunded) based on server pattern. Per Agent A+B research.
        if (StringFind(srv, "FTMO-") == 0 && InpPlan != FN_PLAN_FTMO_2STEP)
            Print("RiskCockpit : FTMO server detected ('", srv,
                  "'). Recommended : set InpPlan = FN_PLAN_FTMO_2STEP.");
        if (StringFind(srv, "FivePercentOnline") >= 0 && InpPlan != FN_PLAN_THE5ERS_HIGH)
            Print("RiskCockpit : The5ers server detected ('", srv,
                  "'). Recommended : set InpPlan = FN_PLAN_THE5ERS_HIGH.");
        if ((StringFind(srv, "E8Markets") >= 0 || StringFind(co, "E8 Markets") >= 0
          || StringFind(co, "E8 Funding") >= 0) && InpPlan != FN_PLAN_E8_8PCT)
            Print("RiskCockpit : E8 Markets server detected ('", srv,
                  "' / '", co, "'). Recommended : set InpPlan = FN_PLAN_E8_8PCT.");
        if ((StringFind(srv, "SeacrestMarkets") >= 0 || StringFind(srv, "MyFundedFX") >= 0
          || StringFind(co,  "Seacrest") >= 0 || StringFind(co, "MyFundedFX") >= 0)
          && InpPlan != FN_PLAN_MFF_RAPID)
            Print("RiskCockpit : SeacrestFunded server detected ('", srv,
                  "' / '", co, "'). Recommended : set InpPlan = FN_PLAN_MFF_RAPID.");
    }

    g_catalog.Init();
    g_profile_ok = g_catalog.Resolve(EffectivePlan(), (ENUM_FN_PHASE)g_eff_phase, g_eff_size,
                                     (ENUM_FN_ACCOUNT_TYPE)g_eff_acct_type, g_addons_mask, g_profile);
    if (g_eff_split >= 0.0) g_profile.profit_split_pct = g_eff_split; // V1.27 : manual split override
    if (EffectivePlan() == FN_PLAN_PERSONAL && g_eff_size <= 0.0)
        g_profile.initial_balance = DetectStartingBalance(); // V1.28 : Personal "Auto" -> real balance

    // Configure pyramid engine with user-tunable inputs.
    {
        PyramidEngineConfig pcfg;
        pcfg.lot_ratio = (InpPyramidLotRatio > 0.0 && InpPyramidLotRatio < 1.0)
                             ? InpPyramidLotRatio
                             : 0.66;
        pcfg.trigger_ratio = 1.00;
        pcfg.safety_margin_ratio = MathMax(0.0, InpPyramidSafetyPct / 100.0);
        pcfg.max_steps = 3;
        g_pyramid_engine.SetConfig(pcfg);
    }
    if (!g_profile_ok)
        Print("RiskCockpit: combination not in catalog - using fallback profile ",
              g_profile.profile_id);

    // FIX 4 (V1.0.1) : challenge / free profiles have no 2nd-strike restriction
    // concept. Never let a flag persisted by a previous FUNDED/Instant session
    // silently tighten their caps - force the violation flags off here (now that
    // the profile is resolved). Funded / Instant keep whatever was set above.
    if (!ProfileCanBeRestricted()) {
        g_margin_violation_active = false;
        g_risk_violation_active   = false;
    }

    // Live-state baseline
    g_peak_equity = AccountInfoDouble(ACCOUNT_EQUITY);
    MqlDateTime mdt;
    TimeToStruct(TimeCurrent(), mdt);
    mdt.hour = 0;
    mdt.min = 0;
    mdt.sec = 0;
    g_day_start = StructToTime(mdt);
    ArrayResize(g_last_tickets, 0);
    for (int i = 0; i < RC_RULE_COUNT; ++i) {
        g_last_status[i] = RC_STATUS_NA;
        g_last_telegram_alert[i] = 0;
    }

    // Telegram setup hint (B1) - cheap one-time message at attach time.
    if (g_eff_telegram) {
        if (InpTelegramBotToken == "" || InpTelegramChatId == "") {
            Print("RiskCockpit : Telegram enabled but bot token / chat id empty - alerts will not fire.");
        } else {
            Print("RiskCockpit : Telegram alerts ON. ",
                  "If first alert fails with err=4014, allow https://api.telegram.org in Tools > Options > Expert Advisors > WebRequest.");
        }
    }

    // LOT 4 : i18n + UI language before BuildPanel (section headers use Tr()).
    g_lang = (int)InpLang;
    // LOT 6 : persisted lang + BE state override the input default (so a runtime
    // switch survives chart change / re-attach / VPS reboot).
    if (GlobalVariableCheck("RC_lang"))
        g_lang = (int)GlobalVariableGet("RC_lang");
    g_be_visible = false;
    if (GlobalVariableCheck("RC_be_visible"))
        g_be_visible = (GlobalVariableGet("RC_be_visible") != 0.0);
    InitI18n();

    DestroyAllObjects();
    BuildPanel();

    // First refresh silently - we don't want a sound burst on init or
    // timeframe switch. Alerts arm only after the panel reflects current state.
    g_alerts_armed = false;
    RefreshPanel();
    RefreshSlLines();
    // AUDIT 2026-06-07 fix #3 : after re-attach / TF switch / restart, the
    // persisted RC_be_visible flag turns the BE button back ON but the line
    // is only drawn on the next trade-transaction. Force a redraw now so the
    // basket-breakeven HLine is visible from the first frame.
    if (g_be_visible) DrawBreakevenLines();
    g_alerts_armed = true;

    ApplyComfortScale(true); // FIX 6 : comfortable padded scale on attach (and on symbol switch via re-init)
    EventSetMillisecondTimer(g_eff_refresh_ms); // V1.27 : honor the persisted refresh period
    ChartRedraw(0);
    return (INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| OnDeinit                                                         |
//+------------------------------------------------------------------+
void OnDeinit(const int reason) {
    EventKillTimer();
    if (g_fx_on) { g_fx.Destroy(); g_fx_on = false; } // v1.4 : free the FX bitmap resource
    g_kit.Destroy();                                   // v1.4 : free the modern body canvas
    // FIX 6 : restore native auto-scale on removal, but only if the comfort scale we
    // applied is still the active one (don't clobber the user's manual zoom).
    if (g_eff_comfort && g_cs_max > g_cs_min) {
        const double cmn = ChartGetDouble(0, CHART_FIXED_MIN);
        const double cmx = ChartGetDouble(0, CHART_FIXED_MAX);
        const double tol = (g_cs_max - g_cs_min) * 1e-3;
        if (MathAbs(cmn - g_cs_min) < tol && MathAbs(cmx - g_cs_max) < tol)
            ChartSetInteger(0, CHART_SCALEFIX, false);
    }
    DestroyAllObjects();
    // Clean SL / TP / NEWS / BE objects we may have drawn on ANY open chart.
    long cid = ChartFirst();
    while (cid >= 0) {
        ObjectsDeleteAll(cid, "RC_SL_");
        ObjectsDeleteAll(cid, "RC_TP_");
        ObjectsDeleteAll(cid, "RC_NEWS_");
        ObjectsDeleteAll(cid, "RC_BE_"); // LOT 5
        ChartRedraw(cid);
        cid = ChartNext(cid);
    }
    ChartRedraw(0);
}

//+------------------------------------------------------------------+
//| OnTimer - refresh panel                                          |
//+------------------------------------------------------------------+
void OnTimer(void) {
    // R1 (V1.23) : while the settings modal is open, do NOT refresh the panel.
    // RefreshPanel -> UpdateRow does ObjectsDeleteAll + DrawProgressBar/Chip every
    // tick, RE-CREATING the bar/chip objects. MT5 draws foreground objects in
    // CREATION order (OBJPROP_ZORDER governs CLICK priority only, NOT draw order),
    // so freshly-recreated bars re-stack ON TOP of the opaque modal -> that was
    // the %-bar bleed-through. The overlay is static between clicks (a click
    // rebuilds it via ApplySettingsChange), so we just skip the refresh.
    if (g_settings_open) { ChartRedraw(0); return; }
    RefreshPanel();
    RepaintCanvas(g_anchor_x, g_anchor_y, InpPanelWidth); // v1.4 : redraw modern body with fresh values
    RenderFx();            // v1.4 : refresh the breach-glow pulse
    UpdateClockBlinker();
    // FIX (LOT 1) : calendar scan is HEAVY (CalendarValueHistory + per-chart loop) ;
    // news change hourly at most, so throttle the chart-side refresh to every 30 s.
    // Was the n#1 freeze cause - the panel kept updating but the event queue
    // starved while this held the thread, and OBJECT_CLICK never fired.
    if (TimeCurrent() - g_news_last_refresh >= 30) {
        RefreshNewsZones();
        g_news_last_refresh = TimeCurrent();
    }
    ApplyComfortScale(false); // FIX 6 : re-pad if native/glued or our band was breached (never fights a manual zoom)
    ChartRedraw(0);
}

//+------------------------------------------------------------------+
//| OnCalculate - minimal, work happens in OnTimer                   |
//+------------------------------------------------------------------+
int OnCalculate(const int rates_total,
                const int prev_calculated,
                const datetime& time[],
                const double& open[],
                const double& high[],
                const double& low[],
                const double& close[],
                const long& tick_volume[],
                const long& volume[],
                const int& spread[]) {
    // V1.29 : in the Strategy Tester an indicator is driven by OnCalculate, NOT by
    // OnTimer -> drive the panel from here so the Market DEMO (tester-only) actually
    // renders + updates for prospective buyers in Visual Mode. On a live chart this
    // is a no-op (OnTimer handles the refresh there).
    if (MQLInfoInteger(MQL_TESTER))
        OnTimer();
    return (rates_total);
}

//+------------------------------------------------------------------+
//| OnChartEvent - reserved for future drag-to-move                  |
//+------------------------------------------------------------------+
//+------------------------------------------------------------------+
//| v1.4.1 R3 : route a hit-tested (canvas-drawn) control to the same |
//| logic its OBJ_BUTTON used. Extended per phase (tf now ; toggles,  |
//| buttons, positions, settings modal next).                        |
//+------------------------------------------------------------------+
void DispatchHit(const string act, const int idx) {
    if (act == "tf") {
        ENUM_TIMEFRAMES tfv[9] = {PERIOD_M1, PERIOD_M5, PERIOD_M15, PERIOD_M30,
                                  PERIOD_H1, PERIOD_H4, PERIOD_D1, PERIOD_W1, PERIOD_MN1};
        if (idx >= 0 && idx < 9) ChartSetSymbolPeriod(0, _Symbol, tfv[idx]);
    }
}

void OnChartEvent(const int id, const long& lparam, const double& dparam, const string& sparam) {
    // V1.29 V : on any chart change (resize / TF switch / scroll / zoom), re-pin the
    // bottom news icons to the CURRENT visible price floor IMMEDIATELY - no calendar
    // re-query, no lag. VLINEs are time-anchored (native, fine) ; SL/TP labels are
    // price-anchored (stay) -> only the OBJ_TEXT news flags need re-pinning. The
    // per-lane stagger is re-applied on the next full RefreshNewsZones (timer).
    if (id == CHARTEVENT_CHART_CHANGE) {
        const double pmin = ChartGetDouble(0, CHART_PRICE_MIN);
        const double pmax = ChartGetDouble(0, CHART_PRICE_MAX);
        const double rng = pmax - pmin;
        const int total = ObjectsTotal(0);
        for (int i = 0; i < total; ++i) {
            const string nm = ObjectName(0, i);
            if (StringFind(nm, "RC_NEWS_FLAG_") != 0) continue; // bottom news icons only
            // V1.29 W-fix (Coordinator) : name = RC_NEWS_FLAG_<lane>_<id> -> re-apply the
            // per-lane vertical stagger so SIMULTANEOUS news stay separated after a
            // scroll/resize. The old handler flattened every flag to lane 0 -> overlap.
            string parts[];
            const int np = StringSplit(nm, '_', parts);          // RC,NEWS,FLAG,<lane>,<id>
            const int lane = (np >= 5 ? (int)StringToInteger(parts[3]) : 0);
            ObjectSetDouble(0, nm, OBJPROP_PRICE, pmin + rng * (0.04 + 0.018 * lane)); // keep OBJPROP_TIME (x follows natively)
        }
        ChartRedraw(0);
        return;
    }
    // B2 : drag-to-move via the title bar (CHARTEVENT_MOUSE_MOVE).
    // lparam = mouse X (px), dparam = mouse Y (px), sparam = "1" if left button down.
    if (id == CHARTEVENT_MOUSE_MOVE) {
        const int mx = (int)lparam;
        const int my = (int)dparam;
        const bool ldown = (sparam == "1");
        if (ldown && !g_dragging) {
            // start a drag only if the press lands on the title bar
            if (mx >= g_anchor_x && mx <= g_anchor_x + InpPanelWidth &&
                my >= g_anchor_y && my <= g_anchor_y + RC_TITLE_HEIGHT) {
                g_dragging = true;
                g_drag_last_x = mx;
                g_drag_last_y = my;
                ChartSetInteger(0, CHART_MOUSE_SCROLL, false); // freeze chart scroll while dragging
            }
        } else if (ldown && g_dragging) {
            MovePanelBy(mx - g_drag_last_x, my - g_drag_last_y);
            g_drag_last_x = mx;
            g_drag_last_y = my;
            ChartRedraw(0);
        } else if (!ldown && g_dragging) {
            g_dragging = false;
            ChartSetInteger(0, CHART_MOUSE_SCROLL, true);
            PersistAnchor();
            ChartRedraw(0);
        }
        return;
    }
    // v1.4.1 R3 : canvas-drawn (rounded) controls are routed by CLICK coordinates.
    // (An OBJ_BUTTON is opaque + square ; rounded controls are painted, not buttons.)
    if (id == CHARTEVENT_CLICK) {
        const int mx = (int)lparam, my = (int)dparam;
        string act; int hidx;
        const bool hit = HitTest(mx, my, act, hidx);
        PrintFormat("RC click (%d,%d) -> %s", mx, my, (hit ? act + "[" + IntegerToString(hidx) + "]" : "(no zone)"));
        if (hit) { DispatchHit(act, hidx); return; }
    }

    // CHARTEVENT_OBJECT_CLICK : +/- on max-parallel control (now OBJ_BUTTON)
    if (id == CHARTEVENT_OBJECT_CLICK) {
        if (sparam == RC_PREFIX + "mp_minus") {
            ObjectSetInteger(0, sparam, OBJPROP_STATE, false); // un-press
            if (g_max_parallel > 1) {
                g_max_parallel--;
                PersistMaxParallel();
                ObjectSetString(0, RC_PREFIX + "mp_value", OBJPROP_TEXT,
                                IntegerToString(g_max_parallel));
                RefreshFooterMetrics();
                RefreshSlLines();
                ChartRedraw(0);
            }
        } else if (sparam == RC_PREFIX + "mp_plus") {
            ObjectSetInteger(0, sparam, OBJPROP_STATE, false); // un-press
            if (g_max_parallel < 50) {
                g_max_parallel++;
                PersistMaxParallel();
                ObjectSetString(0, RC_PREFIX + "mp_value", OBJPROP_TEXT,
                                IntegerToString(g_max_parallel));
                RefreshFooterMetrics();
                RefreshSlLines();
                ChartRedraw(0);
            }
        } else if (sparam == RC_PREFIX + "set") {
            // G3 : open/close the settings overlay.
            ObjectSetInteger(0, sparam, OBJPROP_STATE, false);
            g_settings_open = !g_settings_open;
            ApplySettingsChange();
        } else if (sparam == RC_PREFIX + "kill") {
            // V1.28 : remove THIS indicator instance from the chart. Clean up our
            // objects first, then ChartIndicatorDelete by the fixed short name.
            ObjectSetInteger(0, sparam, OBJPROP_STATE, false);
            int kwin = ChartWindowFind();
            if (kwin < 0) kwin = 0; // main chart
            ObjectsDeleteAll(0, RC_PREFIX);
            ChartIndicatorDelete(0, kwin, "RiskCockpit");
            ChartRedraw(0);
            return;
        } else if (sparam == RC_PREFIX + "set_close") {
            ObjectSetInteger(0, sparam, OBJPROP_STATE, false);
            g_settings_open = false;
            ApplySettingsChange();
        } else if (sparam == RC_PREFIX + "set_lang_en" ||
                   sparam == RC_PREFIX + "set_lang_fr" ||
                   sparam == RC_PREFIX + "set_lang_es") {
            ObjectSetInteger(0, sparam, OBJPROP_STATE, false);
            if      (sparam == RC_PREFIX + "set_lang_en") g_lang = 0;
            else if (sparam == RC_PREFIX + "set_lang_fr") g_lang = 1;
            else                                          g_lang = 2;
            GlobalVariableSet("RC_lang", (double)g_lang);
            ApplySettingsChange();
        } else if (sparam == RC_PREFIX + "set_theme_dark" ||
                   sparam == RC_PREFIX + "set_theme_light") {
            ObjectSetInteger(0, sparam, OBJPROP_STATE, false);
            g_active_theme_idx = (sparam == RC_PREFIX + "set_theme_dark" ? 0 : 1);
            GlobalVariableSet("RC_theme_override", (double)g_active_theme_idx);
            ApplySettingsChange();
        } else if (sparam == RC_PREFIX + "set_vendor_prev" ||
                   sparam == RC_PREFIX + "set_vendor_next") {
            // V1.27 CASCADE step 1 : pick the BROKER. Snap the type to that
            // vendor's first plan and the size to that plan's first legal size.
            ObjectSetInteger(0, sparam, OBJPROP_STATE, false);
            const int delta = (sparam == RC_PREFIX + "set_vendor_next" ? 1 : -1);
            int v = VendorOfPlan(EffectivePlan());
            v = ((v + delta) % 6 + 6) % 6; // 6 vendors
            ENUM_FN_PLAN vplans[];
            const int vn = PlansForVendor(v, vplans);
            if (vn > 0) {
                g_active_plan_idx = (int)vplans[0];
                GlobalVariableSet("RC_plan_override", (double)g_active_plan_idx);
                SnapSizeToPlan((ENUM_FN_PLAN)g_active_plan_idx);
                SnapPhaseToPlan((ENUM_FN_PLAN)g_active_plan_idx);
            }
            ApplySettingsChange();
        } else if (sparam == RC_PREFIX + "set_plan_prev" ||
                   sparam == RC_PREFIX + "set_plan_next") {
            // V1.27 CASCADE step 2 : pick the TYPE, constrained to the current
            // vendor's plans only (so e.g. FTMO never offers Stellar types).
            ObjectSetInteger(0, sparam, OBJPROP_STATE, false);
            const int delta = (sparam == RC_PREFIX + "set_plan_next" ? 1 : -1);
            const int v = VendorOfPlan(EffectivePlan());
            ENUM_FN_PLAN plans[];
            const int np = PlansForVendor(v, plans);
            const int cur = (int)EffectivePlan();
            int pidx = 0;
            for (int i = 0; i < np; ++i) if ((int)plans[i] == cur) { pidx = i; break; }
            if (np > 0) {
                pidx = ((pidx + delta) % np + np) % np;
                g_active_plan_idx = (int)plans[pidx];
                GlobalVariableSet("RC_plan_override", (double)g_active_plan_idx);
                SnapSizeToPlan((ENUM_FN_PLAN)g_active_plan_idx);
                SnapPhaseToPlan((ENUM_FN_PLAN)g_active_plan_idx);
            }
            ApplySettingsChange();
        } else if (sparam == RC_PREFIX + "set_tab_acct"  || sparam == RC_PREFIX + "set_tab_risk" ||
                   sparam == RC_PREFIX + "set_tab_disp"  || sparam == RC_PREFIX + "set_tab_alert" ||
                   sparam == RC_PREFIX + "set_tab_adv") {
            // G2 : switch settings tab.
            ObjectSetInteger(0, sparam, OBJPROP_STATE, false);
            if      (sparam == RC_PREFIX + "set_tab_acct")  g_settings_tab = 0;
            else if (sparam == RC_PREFIX + "set_tab_risk")  g_settings_tab = 1;
            else if (sparam == RC_PREFIX + "set_tab_disp")  g_settings_tab = 2;
            else if (sparam == RC_PREFIX + "set_tab_alert") g_settings_tab = 3;
            else                                            g_settings_tab = 4;
            ApplySettingsChange();
        } else if (sparam == RC_PREFIX + "set_phase_prev" || sparam == RC_PREFIX + "set_phase_next") {
            ObjectSetInteger(0, sparam, OBJPROP_STATE, false);
            const int d = (sparam == RC_PREFIX + "set_phase_next" ? 1 : -1);
            g_eff_phase = ((g_eff_phase + d) % 4 + 4) % 4; // ENUM_FN_PHASE 0..3
            SnapPhaseToPlan(EffectivePlan()); // V1.27 : don't let a non-Instant plan land on INSTANT
            GlobalVariableSet("RC_phase", (double)g_eff_phase);
            ApplySettingsChange();
        } else if (sparam == RC_PREFIX + "set_size_prev" || sparam == RC_PREFIX + "set_size_next") {
            // V1.27 CASCADE step 3 : step only the sizes legal for the current plan.
            ObjectSetInteger(0, sparam, OBJPROP_STATE, false);
            double sizes[];
            const int ns = ValidSizesForPlan(EffectivePlan(), sizes);
            int idx = 0;
            for (int si = 0; si < ns; ++si)
                if ((int)MathRound(g_eff_size) == (int)MathRound(sizes[si])) { idx = si; break; }
            const int d = (sparam == RC_PREFIX + "set_size_next" ? 1 : -1);
            if (ns > 0) {
                idx = ((idx + d) % ns + ns) % ns;
                g_eff_size = sizes[idx];
                GlobalVariableSet("RC_size", g_eff_size);
            }
            ApplySettingsChange();
        } else if (sparam == RC_PREFIX + "set_acct_type") {
            ObjectSetInteger(0, sparam, OBJPROP_STATE, false);
            g_eff_acct_type = (g_eff_acct_type == 0 ? 1 : 0);
            GlobalVariableSet("RC_acct_type", (double)g_eff_acct_type);
            ApplySettingsChange();
        } else if (sparam == RC_PREFIX + "set_perso_type") {
            // V1.29 I : toggle Personal Real <-> Demo (labeling only ; catalogue untouched).
            ObjectSetInteger(0, sparam, OBJPROP_STATE, false);
            g_eff_personal_demo = (g_eff_personal_demo == 0 ? 1 : 0);
            GlobalVariableSet("RC_perso_demo", (double)g_eff_personal_demo);
            ApplySettingsChange();
        } else if (StringFind(sparam, RC_PREFIX + "set_addon_") == 0) {
            ObjectSetInteger(0, sparam, OBJPROP_STATE, false);
            const int flag = (int)StringToInteger(StringSubstr(sparam, StringLen(RC_PREFIX + "set_addon_")));
            if ((g_addons_mask & flag) != 0) g_addons_mask &= ~flag;
            else                             g_addons_mask |=  flag;
            GlobalVariableSet("RC_addons", (double)g_addons_mask);
            ApplySettingsChange();
        } else if (StringFind(sparam, RC_PREFIX + "set_n_") == 0) {
            ObjectSetInteger(0, sparam, OBJPROP_STATE, false);
            const int d = (StringFind(sparam, "_up") >= 0 ? 1 : -1);
            g_max_parallel = (int)MathMax(1.0, MathMin(50.0, (double)g_max_parallel + d));
            PersistMaxParallel();
            ApplySettingsChange();
        } else if (StringFind(sparam, RC_PREFIX + "set_sl_") == 0) {
            ObjectSetInteger(0, sparam, OBJPROP_STATE, false);
            const double d = (StringFind(sparam, "_up") >= 0 ? 0.1 : -0.1);
            g_eff_sl_pct = MathMax(0.1, MathMin(10.0, MathRound((g_eff_sl_pct + d) * 100.0) / 100.0));
            GlobalVariableSet("RC_sl_pct", g_eff_sl_pct);
            ApplySettingsChange();
        } else if (StringFind(sparam, RC_PREFIX + "set_tp_") == 0) {
            ObjectSetInteger(0, sparam, OBJPROP_STATE, false);
            const double d = (StringFind(sparam, "_up") >= 0 ? 0.1 : -0.1);
            g_eff_tp_pct = MathMax(0.05, MathMin(10.0, MathRound((g_eff_tp_pct + d) * 100.0) / 100.0));
            GlobalVariableSet("RC_tp_pct", g_eff_tp_pct);
            ApplySettingsChange();
        } else if (StringFind(sparam, RC_PREFIX + "set_mm_") == 0) {
            ObjectSetInteger(0, sparam, OBJPROP_STATE, false);
            const double d = (StringFind(sparam, "_up") >= 0 ? 1.0 : -1.0);
            g_eff_max_margin_pt = MathMax(1.0, MathMin(100.0, MathRound(g_eff_max_margin_pt + d)));
            GlobalVariableSet("RC_mm_pt", g_eff_max_margin_pt);
            ApplySettingsChange();
        } else if (StringFind(sparam, RC_PREFIX + "set_mr_") == 0) {
            ObjectSetInteger(0, sparam, OBJPROP_STATE, false);
            const double d = (StringFind(sparam, "_up") >= 0 ? 0.1 : -0.1);
            g_eff_max_risk_pt = MathMax(0.1, MathMin(5.0, MathRound((g_eff_max_risk_pt + d) * 100.0) / 100.0));
            GlobalVariableSet("RC_mr_pt", g_eff_max_risk_pt);
            ApplySettingsChange();
        } else if (StringFind(sparam, RC_PREFIX + "set_tn_") == 0) { // V1.26 Advanced steppers
            ObjectSetInteger(0, sparam, OBJPROP_STATE, false);
            const int d = (StringFind(sparam, "_up") >= 0 ? 1 : -1);
            g_eff_tilt_n = (int)MathMax(0.0, MathMin(50.0, (double)g_eff_tilt_n + d));
            GlobalVariableSet("RC_tilt_n", (double)g_eff_tilt_n);
            ApplySettingsChange();
        } else if (StringFind(sparam, RC_PREFIX + "set_tw_") == 0) {
            ObjectSetInteger(0, sparam, OBJPROP_STATE, false);
            const int d = (StringFind(sparam, "_up") >= 0 ? 1 : -1);
            g_eff_tilt_win = (int)MathMax(1.0, MathMin(240.0, (double)g_eff_tilt_win + d));
            GlobalVariableSet("RC_tilt_win", (double)g_eff_tilt_win);
            ApplySettingsChange();
        } else if (StringFind(sparam, RC_PREFIX + "set_cn_") == 0) {
            ObjectSetInteger(0, sparam, OBJPROP_STATE, false);
            const int d = (StringFind(sparam, "_up") >= 0 ? 1 : -1);
            g_eff_cooldown_n = (int)MathMax(0.0, MathMin(20.0, (double)g_eff_cooldown_n + d));
            GlobalVariableSet("RC_cool_n", (double)g_eff_cooldown_n);
            ApplySettingsChange();
        } else if (StringFind(sparam, RC_PREFIX + "set_cm_") == 0) {
            ObjectSetInteger(0, sparam, OBJPROP_STATE, false);
            const int d = (StringFind(sparam, "_up") >= 0 ? 5 : -5);
            g_eff_cooldown_m = (int)MathMax(0.0, MathMin(480.0, (double)g_eff_cooldown_m + d));
            GlobalVariableSet("RC_cool_m", (double)g_eff_cooldown_m);
            ApplySettingsChange();
        } else if (StringFind(sparam, RC_PREFIX + "set_sh_") == 0) {
            ObjectSetInteger(0, sparam, OBJPROP_STATE, false);
            const int d = (StringFind(sparam, "_up") >= 0 ? 1 : -1);
            g_eff_selflock_h = (int)MathMax(1.0, MathMin(72.0, (double)g_eff_selflock_h + d));
            GlobalVariableSet("RC_selflock_h", (double)g_eff_selflock_h);
            ApplySettingsChange();
        } else if (StringFind(sparam, RC_PREFIX + "set_cp_") == 0) {
            ObjectSetInteger(0, sparam, OBJPROP_STATE, false);
            const double d = (StringFind(sparam, "_up") >= 0 ? 1.0 : -1.0);
            g_eff_comfort_pct = MathMax(1.0, MathMin(50.0, MathRound(g_eff_comfort_pct + d)));
            GlobalVariableSet("RC_comfort_pct", g_eff_comfort_pct);
            ApplySettingsChange();
        } else if (StringFind(sparam, RC_PREFIX + "set_split_") == 0) {
            // V1.27 : profit-split override. Cycles Auto(-1) -> 70 -> 80 -> 90 -> 95 -> Auto.
            ObjectSetInteger(0, sparam, OBJPROP_STATE, false);
            const int d = (StringFind(sparam, "_up") >= 0 ? 1 : -1);
            double opts[5]; opts[0]=-1.0; opts[1]=70.0; opts[2]=80.0; opts[3]=90.0; opts[4]=95.0;
            int oi = 0;
            for (int i = 0; i < 5; ++i) if ((int)MathRound(opts[i]) == (int)MathRound(g_eff_split)) { oi = i; break; }
            oi = ((oi + d) % 5 + 5) % 5;
            g_eff_split = opts[oi];
            GlobalVariableSet("RC_split", g_eff_split);
            ApplySettingsChange();
        } else if (StringFind(sparam, RC_PREFIX + "set_cyy_") == 0) {
            // V1.27 : cycle-start YEAR stepper (YYYYMMDD double).
            ObjectSetInteger(0, sparam, OBJPROP_STATE, false);
            const int d = (StringFind(sparam, "_up") >= 0 ? 1 : -1);
            if (g_eff_cycle_ymd <= 0) g_eff_cycle_ymd = IsoToYmd(InpCycleStartIso);
            int y = (int)g_eff_cycle_ymd / 10000, m = ((int)g_eff_cycle_ymd / 100) % 100, dd = (int)g_eff_cycle_ymd % 100;
            y = (int)MathMax(2020, MathMin(2035, y + d));
            if (dd > DaysInMonth(y, m)) dd = DaysInMonth(y, m); // Feb 29 -> 28 in a non-leap year
            g_eff_cycle_ymd = (double)(y * 10000 + m * 100 + dd);
            GlobalVariableSet("RC_cycle_ymd", g_eff_cycle_ymd);
            ApplySettingsChange();
        } else if (StringFind(sparam, RC_PREFIX + "set_cmm_") == 0) {
            ObjectSetInteger(0, sparam, OBJPROP_STATE, false);
            const int d = (StringFind(sparam, "_up") >= 0 ? 1 : -1);
            if (g_eff_cycle_ymd <= 0) g_eff_cycle_ymd = IsoToYmd(InpCycleStartIso);
            int y = (int)g_eff_cycle_ymd / 10000, m = ((int)g_eff_cycle_ymd / 100) % 100, dd = (int)g_eff_cycle_ymd % 100;
            m = ((m - 1 + d) % 12 + 12) % 12 + 1;
            if (dd > DaysInMonth(y, m)) dd = DaysInMonth(y, m); // clamp to the new month's length
            g_eff_cycle_ymd = (double)(y * 10000 + m * 100 + dd);
            GlobalVariableSet("RC_cycle_ymd", g_eff_cycle_ymd);
            ApplySettingsChange();
        } else if (StringFind(sparam, RC_PREFIX + "set_cdd_") == 0) {
            ObjectSetInteger(0, sparam, OBJPROP_STATE, false);
            const int d = (StringFind(sparam, "_up") >= 0 ? 1 : -1);
            if (g_eff_cycle_ymd <= 0) g_eff_cycle_ymd = IsoToYmd(InpCycleStartIso);
            int y = (int)g_eff_cycle_ymd / 10000, m = ((int)g_eff_cycle_ymd / 100) % 100, dd = (int)g_eff_cycle_ymd % 100;
            const int dim = DaysInMonth(y, m);
            if (dd > dim) dd = dim;
            dd = ((dd - 1 + d) % dim + dim) % dim + 1; // 1..days-in-month (calendar-aware)
            g_eff_cycle_ymd = (double)(y * 10000 + m * 100 + dd);
            GlobalVariableSet("RC_cycle_ymd", g_eff_cycle_ymd);
            ApplySettingsChange();
        } else if (StringFind(sparam, RC_PREFIX + "set_mcv_") == 0) {
            // V1.27 : post-violation MARGIN cap (%) stepper.
            ObjectSetInteger(0, sparam, OBJPROP_STATE, false);
            const double d = (StringFind(sparam, "_up") >= 0 ? 5.0 : -5.0);
            g_eff_margin_cap_viol = MathMax(5.0, MathMin(100.0, MathRound(g_eff_margin_cap_viol + d)));
            GlobalVariableSet("RC_mcap_viol", g_eff_margin_cap_viol);
            ApplySettingsChange();
        } else if (StringFind(sparam, RC_PREFIX + "set_rcv_") == 0) {
            // V1.27 : post-violation RISK cap (%) stepper.
            ObjectSetInteger(0, sparam, OBJPROP_STATE, false);
            const double d = (StringFind(sparam, "_up") >= 0 ? 0.1 : -0.1);
            g_eff_risk_cap_viol = MathMax(0.1, MathMin(5.0, MathRound((g_eff_risk_cap_viol + d) * 100.0) / 100.0));
            GlobalVariableSet("RC_rcap_viol", g_eff_risk_cap_viol);
            ApplySettingsChange();
        } else if (StringFind(sparam, RC_PREFIX + "set_rm_") == 0) {
            // V1.27 : refresh period (ms) stepper ; re-arm the timer immediately.
            ObjectSetInteger(0, sparam, OBJPROP_STATE, false);
            const int d = (StringFind(sparam, "_up") >= 0 ? 100 : -100);
            g_eff_refresh_ms = (int)MathMax(100.0, MathMin(2000.0, (double)g_eff_refresh_ms + d));
            GlobalVariableSet("RC_refresh_ms", (double)g_eff_refresh_ms);
            EventKillTimer();
            EventSetMillisecondTimer(g_eff_refresh_ms);
            ApplySettingsChange();
        } else if (sparam == RC_PREFIX + "set_mviol") {
            // V1.27 : mirror of the on-chart margin-violation toggle (same shadow + GV).
            ObjectSetInteger(0, sparam, OBJPROP_STATE, false);
            g_margin_violation_active = !g_margin_violation_active;
            GlobalVariableSet("RC_margin_violation", g_margin_violation_active ? 1.0 : 0.0);
            ApplySettingsChange();
        } else if (sparam == RC_PREFIX + "set_rviol") {
            ObjectSetInteger(0, sparam, OBJPROP_STATE, false);
            g_risk_violation_active = !g_risk_violation_active;
            GlobalVariableSet("RC_risk_violation", g_risk_violation_active ? 1.0 : 0.0);
            ApplySettingsChange();
        } else if (sparam == RC_PREFIX + "set_news") {
            ObjectSetInteger(0, sparam, OBJPROP_STATE, false);
            g_eff_show_news = !g_eff_show_news;
            GlobalVariableSet("RC_show_news", g_eff_show_news ? 1.0 : 0.0);
            ApplySettingsChange();
        } else if (sparam == RC_PREFIX + "set_news_high") {
            ObjectSetInteger(0, sparam, OBJPROP_STATE, false);
            g_eff_news_high = !g_eff_news_high; // V1.29 R
            GlobalVariableSet("RC_news_high", g_eff_news_high ? 1.0 : 0.0);
            ApplySettingsChange();
        } else if (sparam == RC_PREFIX + "set_news_med") {
            ObjectSetInteger(0, sparam, OBJPROP_STATE, false);
            g_eff_news_med = !g_eff_news_med; // V1.29 R
            GlobalVariableSet("RC_news_med", g_eff_news_med ? 1.0 : 0.0);
            ApplySettingsChange();
        } else if (sparam == RC_PREFIX + "set_comfort") {
            ObjectSetInteger(0, sparam, OBJPROP_STATE, false);
            g_eff_comfort = !g_eff_comfort;
            GlobalVariableSet("RC_comfort", g_eff_comfort ? 1.0 : 0.0);
            ApplySettingsChange();
        } else if (sparam == RC_PREFIX + "set_discipline") {
            ObjectSetInteger(0, sparam, OBJPROP_STATE, false);
            g_eff_discipline = !g_eff_discipline;
            GlobalVariableSet("RC_discipline", g_eff_discipline ? 1.0 : 0.0);
            ApplySettingsChange();
        } else if (sparam == RC_PREFIX + "set_risktools") {
            // V1.29 J : master risk-tools ON/OFF (explicit choice persists, beats the Personal default).
            ObjectSetInteger(0, sparam, OBJPROP_STATE, false);
            g_eff_risktools = !g_eff_risktools;
            GlobalVariableSet("RC_risktools", g_eff_risktools ? 1.0 : 0.0);
            ApplySettingsChange();
        } else if (sparam == RC_PREFIX + "set_sound") {
            ObjectSetInteger(0, sparam, OBJPROP_STATE, false);
            g_eff_sound = !g_eff_sound;
            GlobalVariableSet("RC_sound", g_eff_sound ? 1.0 : 0.0);
            ApplySettingsChange();
        } else if (sparam == RC_PREFIX + "set_telegram") {
            ObjectSetInteger(0, sparam, OBJPROP_STATE, false);
            g_eff_telegram = !g_eff_telegram;
            GlobalVariableSet("RC_telegram", g_eff_telegram ? 1.0 : 0.0);
            ApplySettingsChange();
        } else if (sparam == RC_PREFIX + "set_selflock") {
            // V1.24 G1 : arm the self-lock for InpSelfLockHours, persist, close the
            // popup so the full-panel STOP shows immediately.
            ObjectSetInteger(0, sparam, OBJPROP_STATE, false);
            g_selflock_until = TimeCurrent() + (datetime)MathMax(1, g_eff_selflock_h) * 3600;
            GlobalVariableSet("RC_selflock_until", (double)g_selflock_until);
            g_unlock_arm = 0;
            g_settings_open = false;
            ApplySettingsChange();
        } else if (sparam == RC_PREFIX + "disc_unlock") {
            // V1.24 G1 : Ulysses-pact unlock = double-confirm within 5 s.
            ObjectSetInteger(0, sparam, OBJPROP_STATE, false);
            const datetime nowu = TimeCurrent();
            if (g_unlock_arm > 0 && nowu - g_unlock_arm <= 5) {
                g_selflock_until = 0;
                g_unlock_arm = 0;
                GlobalVariableSet("RC_selflock_until", 0.0);
            } else {
                g_unlock_arm = nowu; // arm ; a 2nd click within 5 s confirms
            }
            RefreshPanel();
            ChartRedraw(0);
        } else if (sparam == RC_PREFIX + "rule_margin_cum_viol") {
            // B7 : toggle margin violation -> tighten cumulative margin cap.
            g_margin_violation_active = !g_margin_violation_active;
            PersistViolationFlags();
            ObjectSetString(0, sparam, OBJPROP_TEXT, (g_margin_violation_active ? "X" : " "));
            ObjectSetInteger(0, sparam, OBJPROP_BGCOLOR,
                             (g_margin_violation_active ? g_theme.red : g_theme.bg_section));
            ObjectSetInteger(0, sparam, OBJPROP_COLOR,
                             (g_margin_violation_active ? g_theme.bg : g_theme.text_dim));
            ObjectSetInteger(0, sparam, OBJPROP_STATE, false);
            RefreshPanel();
            ChartRedraw(0);
        } else if (sparam == RC_PREFIX + "rule_risk_cum_viol") {
            // B7 : toggle risk violation -> tighten cumulative risk cap.
            g_risk_violation_active = !g_risk_violation_active;
            PersistViolationFlags();
            ObjectSetString(0, sparam, OBJPROP_TEXT, (g_risk_violation_active ? "X" : " "));
            ObjectSetInteger(0, sparam, OBJPROP_BGCOLOR,
                             (g_risk_violation_active ? g_theme.red : g_theme.bg_section));
            ObjectSetInteger(0, sparam, OBJPROP_COLOR,
                             (g_risk_violation_active ? g_theme.bg : g_theme.text_dim));
            ObjectSetInteger(0, sparam, OBJPROP_STATE, false);
            RefreshPanel();
            ChartRedraw(0);
        } else if (StringFind(sparam, RC_PREFIX + "recsym_") == 0) {
            // B8 : quick-switch the Helper chart to the clicked recent symbol.
            const int ridx = (int)StringToInteger(StringSubstr(sparam, StringLen(RC_PREFIX + "recsym_")));
            if (ridx >= 0 && ridx < ArraySize(g_recent_syms))
                ChartSetSymbolPeriod(0, g_recent_syms[ridx], (ENUM_TIMEFRAMES)ChartPeriod(0));
            ObjectSetInteger(0, sparam, OBJPROP_STATE, false);
        } else if (StringFind(sparam, RC_PREFIX + "pos_row_") == 0) {
            // V1.27 : click an open-position row -> switch the chart to its symbol.
            const int pidx = (int)StringToInteger(StringSubstr(sparam, StringLen(RC_PREFIX + "pos_row_")));
            if (pidx >= 0 && pidx < RC_MAX_POSITIONS && StringLen(g_pos_sym[pidx]) > 0)
                ChartSetSymbolPeriod(0, g_pos_sym[pidx], (ENUM_TIMEFRAMES)ChartPeriod(0));
            ObjectSetInteger(0, sparam, OBJPROP_STATE, false);
        } else if (sparam == RC_PREFIX + "autosl") {
            // B10 : disabled toggle - indicator can't place SL. No-op (reset state).
            ObjectSetInteger(0, sparam, OBJPROP_STATE, false);
        } else if (sparam == RC_PREFIX + "recenter") {
            // FIX 6 + LOT D B-RESIZE-ALL : re-apply the comfort padded scale on
            // EVERY open chart (not just the active one). User-explicit gesture
            // -> overriding any in-progress zoom is intended.
            ApplyComfortScaleAllCharts();
            ObjectSetInteger(0, sparam, OBJPROP_STATE, false);
            ChartRedraw(0);
        } else if (sparam == RC_PREFIX + "be") {
            // LOT 5 : toggle breakeven lines on the active chart.
            g_be_visible = !g_be_visible;
            PersistBE(); // LOT 6 : survive re-attach
            DrawBreakevenLines();
            // re-tint the BE button in-place (no full panel rebuild).
            ObjectSetInteger(0, sparam, OBJPROP_BGCOLOR, g_be_visible ? g_theme.accent2 : g_theme.surface_hi);
            ObjectSetInteger(0, sparam, OBJPROP_COLOR,   g_be_visible ? g_theme.bg      : g_theme.text);
            ObjectSetInteger(0, sparam, OBJPROP_STATE, false);
            ChartRedraw(0);
        } else if (StringFind(sparam, RC_PREFIX + "tf_") == 0) {
            // LOT 4 : timeframe quick-switch on the active chart.
            const string tf_code = StringSubstr(sparam, StringLen(RC_PREFIX + "tf_"));
            ENUM_TIMEFRAMES new_tf = PERIOD_CURRENT;
            if      (tf_code == "M1")  new_tf = PERIOD_M1;
            else if (tf_code == "M5")  new_tf = PERIOD_M5;
            else if (tf_code == "M15") new_tf = PERIOD_M15;
            else if (tf_code == "M30") new_tf = PERIOD_M30;
            else if (tf_code == "H1")  new_tf = PERIOD_H1;
            else if (tf_code == "H4")  new_tf = PERIOD_H4;
            else if (tf_code == "D1")  new_tf = PERIOD_D1;
            else if (tf_code == "W1")  new_tf = PERIOD_W1;
            else if (tf_code == "MN1") new_tf = PERIOD_MN1;
            if (new_tf != PERIOD_CURRENT)
                ChartSetSymbolPeriod(0, _Symbol, new_tf);
            ObjectSetInteger(0, sparam, OBJPROP_STATE, false);
        }
    }
}

//+------------------------------------------------------------------+
//| OnTradeTransaction - instant SL-line + position-list refresh     |
//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction& trans,
                        const MqlTradeRequest& request,
                        const MqlTradeResult& result) {
    // R1 (V1.23) : don't redraw panel objects while the settings modal is open -
    // they would re-stack over it. The next OnTimer RefreshPanel (which also
    // refreshes the positions list) catches up the instant the popup closes.
    if (g_settings_open) return;
    if (trans.type == TRADE_TRANSACTION_POSITION || trans.type == TRADE_TRANSACTION_DEAL_ADD || trans.type == TRADE_TRANSACTION_DEAL_UPDATE || trans.type == TRADE_TRANSACTION_DEAL_DELETE || trans.type == TRADE_TRANSACTION_HISTORY_ADD) {
        RefreshPositionsList(); // sets chip status first
        RefreshSlLines();       // may override chip to "SL>REC" if user SL too wide
        SnapshotPositionList();
        UpdateRecentSymbols();                                       // B8 : refresh recent list
        DrawRecentSymbolsBar(g_anchor_x, g_recbar_y, InpPanelWidth); // B8 : redraw quick-switch bar
        if (g_be_visible) DrawBreakevenLines();                       // LOT 5 : sync BE lines after position change
        ChartRedraw(0);
    }
}

//+------------------------------------------------------------------+
//| Object lifecycle                                                 |
//+------------------------------------------------------------------+
// V1.24 fix (JR test 2026-06-07) : a full-panel rectangle overlay (settings
// modal OR discipline lock) CANNOT cover MT5 control objects - OBJ_BUTTON /
// OBJ_EDIT / OBJ_BITMAP_LABEL are always rendered ON TOP of rectangle labels,
// regardless of ZORDER or creation order. So while an overlay is up we HIDE
// those controls via OBJPROP_TIMEFRAMES = OBJ_NO_PERIODS, keeping only the ones
// whose name starts with `keep`. Guarded on transition (no per-tick enumeration).
int    g_ctrl_hidden = -1;  // -1 unknown, 0 shown, 1 hidden
string g_ctrl_keep   = "";
void SetPanelControlsHidden(bool hide, const string keep) {
    if (g_ctrl_hidden == (hide ? 1 : 0) && g_ctrl_keep == keep) return;
    g_ctrl_hidden = hide ? 1 : 0; g_ctrl_keep = keep;
    const int total = ObjectsTotal(0);
    for (int i = 0; i < total; ++i) {
        const string nm = ObjectName(0, i);
        if (StringFind(nm, RC_PREFIX) != 0) continue;
        const long t = ObjectGetInteger(0, nm, OBJPROP_TYPE);
        if (t != OBJ_BUTTON && t != OBJ_EDIT && t != OBJ_BITMAP_LABEL) continue;
        const bool keep_this = (keep != "" && StringFind(nm, RC_PREFIX + keep) == 0);
        ObjectSetInteger(0, nm, OBJPROP_TIMEFRAMES,
                         (hide && !keep_this) ? OBJ_NO_PERIODS : OBJ_ALL_PERIODS);
    }
}

void DestroyAllObjects(void) {
    ObjectsDeleteAll(0, RC_PREFIX);
    g_ctrl_hidden = -1; // controls recreated visible on next build -> force re-apply
}

//+------------------------------------------------------------------+
//| v1.4 FX overlay : is any breach-critical rule at RED right now ?  |
//| (cumulative margin / cumulative risk / daily DD / overall DD)     |
//+------------------------------------------------------------------+
bool RiskIsBreaching(void) {
    for (int i = 0; i < RC_RULE_COUNT; ++i) {
        if (!g_rows[i].applies) continue;
        if (g_rows[i].status != RC_STATUS_RED) continue;
        const string k = g_rows[i].key;
        if (k == "rule_margin_cum" || k == "rule_risk_cum" ||
            k == "rule_daily_dd"   || k == "rule_overall_dd")
            return true;
    }
    return false;
}

//+------------------------------------------------------------------+
//| v1.4 FX overlay : redraw the glow into the RC_fx bitmap. Clear    |
//| everywhere except a fading RED halo in the outer margin band that |
//| breathes via GetTickCount. No breach -> the bitmap stays empty.   |
//+------------------------------------------------------------------+
void RenderFx(void) {
    if (!g_fx_on) return;
    const bool breach = RiskIsBreaching();
    if (!breach && !g_fx_was_breach) return; // already clear -> skip the GPU update
    g_fx_was_breach = breach;
    g_fx.Erase(ColorToARGB(clrBlack, 0)); // fully transparent
    if (breach) {
        const uint   ms   = GetTickCount();
        const double ph   = (double)(ms % 1600) / 1600.0;          // 1.6 s cycle
        const double s    = 0.5 - 0.5 * MathCos(ph * 2.0 * M_PI);  // 0..1 smooth breath
        const int    peak = (int)(80.0 + 150.0 * s);               // 80..230 alpha near the edge
        const int    m    = RC_FX_MARGIN;
        // Concentric 1px outlines inside the margin band : brightest next to the
        // panel edge (i = m-1), fading to nothing at the bitmap edge (i = 0). The
        // panel body occupies the centre and is never painted -> content stays clear.
        for (int i = 0; i < m; ++i) {
            const int a = (int)(peak * (double)(i + 1) / (double)m);
            g_fx.Rectangle(i, i, g_fx_w - 1 - i, g_fx_h - 1 - i, ColorToARGB(g_theme.red, (uchar)a));
        }
    }
    g_fx.Update(true);
}

//+------------------------------------------------------------------+
//| v1.4 FX overlay : (re)create the RC_fx bitmap around the panel.   |
//| Freed + recreated on every BuildPanel so it tracks size + anchor. |
//+------------------------------------------------------------------+
void CreateFxCanvas(int x, int y, int w, int h) {
    const int m = RC_FX_MARGIN;
    if (g_fx_on) g_fx.Destroy();   // free the previous GPU resource before re-creating
    g_fx_w = w + 2 * m;
    g_fx_h = h + 2 * m;
    if (!g_fx.CreateBitmapLabel(0, 0, RC_PREFIX + "fx", x - m, y - m, g_fx_w, g_fx_h,
                                COLOR_FORMAT_ARGB_NORMALIZE)) {
        g_fx_on = false;           // canvas unavailable -> silently skip the FX
        return;
    }
    ObjectSetInteger(0, RC_PREFIX + "fx", OBJPROP_BACK, false);
    ObjectSetInteger(0, RC_PREFIX + "fx", OBJPROP_SELECTABLE, false);
    ObjectSetInteger(0, RC_PREFIX + "fx", OBJPROP_HIDDEN, true);
    ObjectSetInteger(0, RC_PREFIX + "fx", OBJPROP_ZORDER, 0); // clicks pass to the controls
    g_fx_on = true;
    RenderFx();
}

//+------------------------------------------------------------------+
//| v1.4 MODERN : per-status meter fill (2-stop gradient, safe->red). |
//+------------------------------------------------------------------+
void RiskFillColors(const ENUM_RC_STATUS s, color &a, color &b) {
    switch (s) {
        case RC_STATUS_RED:  a = C'239,68,68';  b = C'248,113,113'; break;
        case RC_STATUS_WARN: a = C'245,158,11'; b = C'251,191,36';  break;
        case RC_STATUS_OK:   a = C'16,185,129'; b = C'52,211,153';  break;
        default:             a = g_theme.text_dim;   b = g_theme.text_dim; break;
    }
}

//+------------------------------------------------------------------+
//| v1.4 MODERN : repaint the whole panel BODY into g_kit. Mirrors    |
//| BuildPanel's section walk so the canvas meters / pills line up    |
//| with the OBJ_LABEL rows drawn on top. Called on build + refresh.  |
//| Text + controls live ON TOP (created after g_kit) ; the old       |
//| rectangle-label backgrounds sit UNDER it (hidden) - R2 removes.   |
//+------------------------------------------------------------------+
void RepaintCanvas(const int x, const int y, const int w) {
    if (!g_kit.Ready()) return;
    const int M = RC_KIT_MARGIN;
    const int rules_h     = (g_eff_risktools ? RC_RULE_COUNT * InpRowHeight : 0);
    const int positions_h = RC_MAX_POSITIONS * InpRowHeight;
    const int footer_rows = (InpEnablePyramidSafe ? 4 : 3);
    const int total_h = RC_TITLE_HEIGHT + InpRowHeight
                        + (g_eff_risktools ? RC_SECTION_HEIGHT : 0) + rules_h
                        + RC_SECTION_HEIGHT + positions_h
                        + InpRowHeight * footer_rows + InpRowHeight + InpRowHeight;

    g_kit.Begin();
    const int px = M, py = M;                     // panel top-left inside the bitmap
    g_kit.SoftShadow(px, py, w, total_h, RC_R_PANEL, g_theme.bg_deep, 9, 95);
    g_kit.Card(px, py, w, total_h, RC_R_PANEL, g_theme.bg_lift, g_theme.bg, g_theme.border_hi);

    int cy = py;
    // title band + divider under it
    g_kit.RoundFill(px + 1, py + 1, w - 2, RC_TITLE_HEIGHT - 1, RC_R_PANEL - 1,
                    ColorToARGB(g_theme.surface_hi, 235));
    cy += RC_TITLE_HEIGHT;
    g_kit.Hairline(px + 1, cy, px + w - 2, g_theme.border);
    cy += InpRowHeight;                            // account strip
    g_kit.Hairline(px + 1, cy, px + w - 2, g_theme.border);

    if (g_eff_risktools) {
        g_kit.RoundFill(px + 6, cy + 5, 3, RC_SECTION_HEIGHT - 10, 1, ColorToARGB(g_theme.accent, 255));
        cy += RC_SECTION_HEIGHT;
        for (int i = 0; i < RC_RULE_COUNT; ++i) {
            const int ry = cy + i * InpRowHeight;
            const string k = g_rows[i].key;
            if (k == "rule_margin_pt" || k == "rule_newsstats") continue; // text-only rows
            const int bx = px + 360;
            const int bw = w - 360 - 80 - RC_PAD;
            const int bh = 8;
            const int by = ry + (InpRowHeight - bh) / 2;
            if (g_rows[i].applies) {
                const double ratio = (g_rows[i].max_pct > 0.0 ? g_rows[i].value_pct / g_rows[i].max_pct : 0.0);
                color fa, fb; RiskFillColors(g_rows[i].status, fa, fb);
                g_kit.Meter(bx, by, bw, bh, ratio, g_theme.bar_bg, fa, fb);
                g_kit.RoundFill(px + w - 70, ry + 3, 60, InpRowHeight - 6, (InpRowHeight - 6) / 2,
                                ColorToARGB(StatusColor(g_rows[i].status), 255)); // status pill bg
            } else {
                g_kit.Meter(bx, by, bw, bh, 0.0, g_theme.bar_bg, g_theme.text_dim, g_theme.text_dim);
            }
        }
        cy += rules_h;
    }
    // positions header tick + section
    g_kit.RoundFill(px + 6, cy + 5, 3, RC_SECTION_HEIGHT - 10, 1, ColorToARGB(g_theme.accent2, 255));
    cy += RC_SECTION_HEIGHT + positions_h;
    // dividers above footer / tf bar / recent bar
    g_kit.Hairline(px + 1, cy, px + w - 2, g_theme.border);
    cy += InpRowHeight * footer_rows;                       // -> timeframe bar row
    g_kit.Hairline(px + 1, cy, px + w - 2, g_theme.border);
    // v1.4 R2/R3 : segmented TF control - a dark rounded track, then 9 segment
    // faces painted on top (active = cyan). The text labels + click zones live in
    // DrawTimeframeBar. 2px gaps let the dark track show between segments.
    g_kit.RoundFill(px + 28, cy + 3, 322, InpRowHeight - 6, (InpRowHeight - 6) / 2,
                    ColorToARGB(g_theme.bg_deep, 255));
    {
        const ENUM_TIMEFRAMES tfv2[9] = {PERIOD_M1, PERIOD_M5, PERIOD_M15, PERIOD_M30,
                                         PERIOD_H1, PERIOD_H4, PERIOD_D1, PERIOD_W1, PERIOD_MN1};
        const ENUM_TIMEFRAMES curp = (ENUM_TIMEFRAMES)ChartPeriod(0);
        for (int s = 0; s < 9; ++s) {
            const int sx = px + 30 + s * 35;
            const bool act = (tfv2[s] == curp);
            g_kit.RoundFill(sx, cy + 3, 33, InpRowHeight - 6, 5,
                            act ? ColorToARGB(g_theme.accent, 255) : ColorToARGB(g_theme.surface_hi, 255));
        }
    }
    cy += InpRowHeight;
    g_kit.Hairline(px + 1, cy, px + w - 2, g_theme.border);

    g_kit.Commit();
}

//+------------------------------------------------------------------+
//| Build static skeleton (background + section frames)              |
//+------------------------------------------------------------------+
void BuildPanel(void) {
    const int x = g_anchor_x; // B2 : live anchor (drag-updated, persisted)
    const int y = g_anchor_y;
    const int w = InpPanelWidth;
    HitReset(); // v1.4.1 R3 : clear hit-zones ; the section draws below re-register them

    // Estimate height: title + strip + section header + rules + section header + positions + footer
    // Footer is 3 rows by default, 4 when pyramid advisor is enabled.
    const int rules_h = (g_eff_risktools ? RC_RULE_COUNT * InpRowHeight : 0); // V1.29 L : collapse rules section when risk-tools OFF
    const int positions_h = RC_MAX_POSITIONS * InpRowHeight;
    const int footer_rows = (InpEnablePyramidSafe ? 4 : 3);
    const int recbar_h = InpRowHeight; // B8 : recent-symbols quick-switch bar
    const int tfbar_h  = InpRowHeight; // LOT 4 : timeframe quick-switch bar
    const int total_h = RC_TITLE_HEIGHT + InpRowHeight + (g_eff_risktools ? RC_SECTION_HEIGHT : 0) + rules_h + RC_SECTION_HEIGHT + positions_h + InpRowHeight * footer_rows + tfbar_h + recbar_h; // V1.29 L : drop the rules header height too when OFF
    g_panel_height = total_h; // fix #5 : exposed for UpdateDisciplineOverlay

    // Premium (v1.4) : soft drop shadow behind the panel for depth, then the
    // panel body as a deep base with a crisp defined edge - the section bands
    // (surface) sit on top and read as a raised card stack.
    DrawRect(RC_PREFIX + "shadow", x + 5, y + 6, w, total_h, C'6,9,16', C'6,9,16', 0);
    DrawRect(RC_PREFIX + "bg", x, y, w, total_h, g_theme.bg_deep, g_theme.border_hi, 1);
    // v1.4 MODERN : draw the panel body into g_kit, created FIRST so the text
    // (OBJ_LABEL) + controls from the section draws below render ON TOP of it, and
    // the glow (g_fx) above that. The rect backgrounds above are now hidden under
    // the canvas (kept for R1 ; removed in R2).
    g_kit.Create(RC_PREFIX + "ui", x - RC_KIT_MARGIN, y - RC_KIT_MARGIN,
                 w + 2 * RC_KIT_MARGIN, total_h + 2 * RC_KIT_MARGIN);
    RepaintCanvas(x, y, w);
    CreateFxCanvas(x, y, w, total_h); // v1.4 : glow ring around the panel (breach pulse)

    int cy = y;
    DrawTitleBar(x, cy, w);
    cy += RC_TITLE_HEIGHT;
    DrawAccountStrip(x, cy, w);
    cy += InpRowHeight;
    if (g_eff_risktools) cy = DrawRulesSection(x, cy, w); // V1.29 L : skip the whole rules section when OFF (compact panel)
    cy = DrawPositionsSection(x, cy, w);
    DrawFooter(x, cy, w);
    cy += InpRowHeight * footer_rows; // advance past the footer rows
    // LOT 4 : timeframe quick-switch row, just above the recent-symbols bar.
    g_tfbar_y = cy; // P4 : copy-lot fields are placed on this row (left of BE)
    DrawTimeframeBar(x, cy, w);
    cy += InpRowHeight;
    // B8 : recent-symbols quick-switch bar pinned at the very bottom.
    g_recbar_y = cy;
    UpdateRecentSymbols();
    DrawRecentSymbolsBar(x, cy, w);

    // G3 : if the settings popup is open, float it ABOVE everything else.
    if (g_settings_open)
        DrawSettingsOverlay(x, y, w);
}

//+------------------------------------------------------------------+
//| Title bar                                                        |
//+------------------------------------------------------------------+
void DrawTitleBar(int x, int y, int w) {
    DrawRect(RC_PREFIX + "title_bg", x, y, w, RC_TITLE_HEIGHT, g_theme.surface_hi, g_theme.border, 1);

    // R3 : header logo - a FIXED asset (RC_LOGO_FILE), not a user input. MT5
    // renders it via an OBJ_BITMAP_LABEL pointing at MQL5\Images\<file> (shipped
    // 22x22 ; MT5 crops, doesn't scale). If the file is missing MT5 shows nothing.
    const int logo_sz = 22;
    const int logo_x  = x + RC_PAD;
    const int logo_y  = y + 4;
    const string logo_id = RC_PREFIX + "logo";
    if (ObjectFind(0, logo_id) < 0) ObjectCreate(0, logo_id, OBJ_BITMAP_LABEL, 0, 0, 0);
    ObjectSetInteger(0, logo_id, OBJPROP_XDISTANCE, logo_x);
    ObjectSetInteger(0, logo_id, OBJPROP_YDISTANCE, logo_y);
    ObjectSetInteger(0, logo_id, OBJPROP_XSIZE, logo_sz);
    ObjectSetInteger(0, logo_id, OBJPROP_YSIZE, logo_sz);
    ObjectSetInteger(0, logo_id, OBJPROP_CORNER, CORNER_LEFT_UPPER);
    ObjectSetString (0, logo_id, OBJPROP_BMPFILE, "::RiskCockpit_logo.bmp"); // V1.29 : embedded resource (ships with the .ex5 -> buyers see the logo)
    ObjectSetInteger(0, logo_id, OBJPROP_BACK, false);
    ObjectSetInteger(0, logo_id, OBJPROP_SELECTABLE, false);
    ObjectSetInteger(0, logo_id, OBJPROP_HIDDEN, true);
    ObjectSetInteger(0, logo_id, OBJPROP_ZORDER, 110);
    const int title_x = logo_x + logo_sz + 8; // title starts to the right of the logo

    // V1.29 E : bare brand title only. The "- profile unresolved" suffix made the
    // left-anchored title grow right UNDER the gear/X cluster (JR : "X chevauche le
    // titre"). The unresolved state is already shown in the strip below.
    // (Note : the gear/X stay left-anchored here ; right-anchoring them as the spec
    //  suggested would collide with the right-anchored title_model that grows
    //  leftward from x+w-RC_PAD-RC_TITLE_CLOCK_W. Bare title ends well before gear_x.)
    string title = "RISKCOCKPIT";

    DrawLabel(RC_PREFIX + "title_text", title_x, y + 8, title, g_theme.accent, RC_FONT_SIZE_TITLE, RC_FONT_UI_SB);
    // v1.4 : discreet dev build tag just right of the brand (empty in release).
    if (StringLen(RC_BUILD_TAG) > 0)
        DrawLabel(RC_PREFIX + "build", title_x + 104, y + 12, RC_BUILD_TAG, g_theme.text_dim, RC_FONT_SIZE_LABEL, RC_FONT_UI);

    // R2 : settings GEAR button (U+2699) just right of the title. "Segoe UI
    // Symbol" renders the gear reliably on Windows ; the rest of the panel keeps
    // RC_FONT. Click toggles the in-panel SETTINGS modal.
    // V1.29 K : X in the TOP-RIGHT corner, gear just left of it (were left-anchored
    // to the title and overrun by the right-anchored model label).
    const int bw = 22, gap = 4;
    const int kill_x = x + w - RC_PAD - bw;   // X = rightmost
    const int gear_x = kill_x - gap - bw;     // gear left of the X
    DrawSetButton(RC_PREFIX + "set", gear_x, y + 5, 22, 20, ShortToString((ushort)0x2699));
    ObjectSetString (0, RC_PREFIX + "set", OBJPROP_FONT, "Segoe UI Symbol");
    ObjectSetInteger(0, RC_PREFIX + "set", OBJPROP_FONTSIZE, RC_FONT_SIZE + 2);
    ObjectSetString (0, RC_PREFIX + "set", OBJPROP_TOOLTIP,
                    "Settings : account / risk / display / alerts");
    // V1.28 : title-bar X button -> removes THIS indicator from the chart
    // (ChartIndicatorDelete), so no trip to the Indicators List is needed.
    // (kill_x computed above = top-right corner.)
    DrawSetButton(RC_PREFIX + "kill", kill_x, y + 5, 22, 20, "X");
    ObjectSetInteger(0, RC_PREFIX + "kill", OBJPROP_FONTSIZE, RC_FONT_SIZE + 1);
    ObjectSetInteger(0, RC_PREFIX + "kill", OBJPROP_COLOR, g_theme.red);
    ObjectSetInteger(0, RC_PREFIX + "kill", OBJPROP_BORDER_COLOR, g_theme.red);
    ObjectSetString (0, RC_PREFIX + "kill", OBJPROP_TOOLTIP, Tr("kill_tip"));

    // FIX 7 (V1.0.2) : balance ("model | $XXK") and the clock blinker are BOTH
    // right-anchored. The clock (news countdown / "WEEKEND HOLD!" / LIVE) grows
    // LEFTWARD from the right edge and used to overrun the balance (only 70 px were
    // reserved). Reserve a fixed clock zone (RC_TITLE_CLOCK_W = 120) and anchor the
    // balance to the LEFT of it, so the two never overlap whatever the clock shows.
    string right = "";
    if (g_profile_ok || g_profile.is_default_fallback) {
        const int balance_k = (int)MathRound(g_profile.initial_balance / 1000.0);
        right = g_profile.model + "  |  $" + IntegerToString(balance_k) + "K";
    }
    StringReplace(right, " (no prop rules)", ""); // V1.29 K : shorten the Personal label so it clears the gear/X cluster
    // V1.29 K : model sits LEFT of the (left-shifted) clock zone, which sits left of the gear.
    DrawLabel(RC_PREFIX + "title_model", (gear_x - 8) - RC_TITLE_CLOCK_W, y + 8, right, g_theme.text, RC_FONT_SIZE);
    ObjectSetInteger(0, RC_PREFIX + "title_model", OBJPROP_ANCHOR, ANCHOR_RIGHT_UPPER);

    DrawLabel(RC_PREFIX + "title_clock", gear_x - 8, y + 8, Tr("live"), g_theme.accent2, RC_FONT_SIZE);
    ObjectSetInteger(0, RC_PREFIX + "title_clock", OBJPROP_ANCHOR, ANCHOR_RIGHT_UPPER);
}

//+------------------------------------------------------------------+
//| Account strip (cycle, account #, type, days remaining)           |
//+------------------------------------------------------------------+
void DrawAccountStrip(int x, int y, int w) {
    DrawRect(RC_PREFIX + "strip_bg", x, y, w, InpRowHeight, g_theme.surface, g_theme.border, 0);

    const long acc_login = AccountInfoInteger(ACCOUNT_LOGIN);
    const string acc_type_str = (g_profile.swap_charged ? "SWAP" : "SWAP-FREE");

    // G3 : a Personal / broker account has no prop profit-split -> show N/A
    // (like the other prop-only meters) rather than a meaningless "Split 100%".
    const string split_str = (g_profile.plan_id == FN_PLAN_PERSONAL)
                                 ? Tr("split") + " N/A"
                                 : Tr("split") + " " + DoubleToString(g_profile.profit_split_pct, 0) + "%";
    // V1.29 I : a Personal account shows its REAL / DEMO type word (labeling only).
    const string perso_tag = (g_profile.plan_id == FN_PLAN_PERSONAL)
                                 ? (g_eff_personal_demo == 1 ? "DEMO  " : "REAL  ") : "";
    string left;
    StringConcatenate(left, Tr("acc"), " #", acc_login, "  ", perso_tag, acc_type_str, "  ", split_str);
    DrawLabel(RC_PREFIX + "strip_left", x + RC_PAD, y + 4, left, g_theme.text, RC_FONT_SIZE);

    // Right: min-trading-days counter (date-free, computed from trade history).
    // FIX : the Cycle / Payout countdown was removed (too personal + required
    // manually entering cycle/payout dates the trader rarely knows).
    string right = "";
    {
        const int min_days = g_profile.min_trading_days;
        if (min_days <= 0)
            right = Tr("min_days_none");
        else {
            const int done = Live_TradingDaysCount();
            StringConcatenate(right, Tr("days_traded"), " ", done, "/", min_days,
                              (done >= min_days ? "  OK" : ""));
        }
    }
    DrawLabel(RC_PREFIX + "strip_right", x + w - RC_PAD, y + 4, right, g_theme.text_dim, RC_FONT_SIZE);
    ObjectSetInteger(0, RC_PREFIX + "strip_right", OBJPROP_ANCHOR, ANCHOR_RIGHT_UPPER);
}

//+------------------------------------------------------------------+
//| Section header                                                   |
//+------------------------------------------------------------------+
void DrawSectionHeader(const string id, int x, int y, int w, const string title, color accent) {
    DrawRect(RC_PREFIX + id + "_bg", x, y, w, RC_SECTION_HEIGHT, g_theme.surface_hi, g_theme.border, 0);
    // Premium : a cyan accent tick on the left edge of every section header.
    DrawRect(RC_PREFIX + id + "_tick", x, y + 3, 3, RC_SECTION_HEIGHT - 6, accent, accent, 0);
    DrawLabel(RC_PREFIX + id + "_txt", x + RC_PAD, y + 4, title, accent, RC_FONT_SIZE_TITLE - 1, RC_FONT_UI_SB);
}

//+------------------------------------------------------------------+
//| Rules section - returns the y-coordinate after the section       |
//+------------------------------------------------------------------+
int DrawRulesSection(int x, int y, int w) {
    DrawSectionHeader("sec_rules", x, y, w, Tr("rules"), g_theme.accent);
    int cy = y + RC_SECTION_HEIGHT;
    for (int i = 0; i < RC_RULE_COUNT; ++i) {
        DrawRuleRow(g_rows[i].key, i, x, cy, w, InpRowHeight,
                    Tr(g_rows[i].key), g_rows[i].value_text,
                    g_rows[i].value_pct, g_rows[i].max_pct,
                    g_rows[i].status, g_rows[i].applies);
        cy += InpRowHeight;
    }
    return cy;
}

//+------------------------------------------------------------------+
//| Single rule row                                                  |
//+------------------------------------------------------------------+
void DrawRuleRow(const string key_prefix, int idx,
                 int x, int y, int w, int h,
                 const string label, const string value_text,
                 double pct, double max_pct,
                 ENUM_RC_STATUS status, bool applies) {
    const string id = RC_PREFIX + key_prefix;

    // Row background - premium zebra : every row gets a surface fill so the
    // rules area reads as one continuous card (surface / surface_hi alternation).
    {
        const color rowc = ((idx % 2) == 0) ? g_theme.surface : g_theme.surface_hi;
        DrawRect(id + "_rowbg", x + 1, y, w - 2, h, rowc, rowc, 0);
    }

    const color text_clr = applies ? g_theme.text : g_theme.text_dim;

    // B7 : clickable violation toggle in front of Margin (rule_margin_cum) and
    // Risk (rule_risk_cum) rows. Toggling it tightens that cumulative cap to the
    // FN 2nd-strike value. Label shifts right to make room for the checkbox.
    // FIX 4 (V1.0.1) : the toggles tighten caps to FundedNext's 2nd-strike values
    // (margin 30% / risk 1%). Those restrictions only exist on real funded-money
    // accounts (Funded + Instant). On challenge phases you simply fail the
    // objective; Free Trial / Free Competition are demo - so the toggle is hidden.
    const bool has_viol_toggle = ProfileCanBeRestricted() &&
                                 (key_prefix == "rule_margin_cum" || key_prefix == "rule_risk_cum");
    int label_x = x + RC_PAD;
    if (has_viol_toggle) {
        const bool viol_active = (key_prefix == "rule_margin_cum") ? g_margin_violation_active
                                                                   : g_risk_violation_active;
        DrawViolationToggle(key_prefix, x + 2, y + 3, h - 6, viol_active);
        label_x = x + 22;
    }

    // Label (left) - premium UI font (Segoe UI) ; values/numbers stay Consolas
    DrawLabel(id + "_lbl", label_x, y + 4, label, text_clr, RC_FONT_SIZE, RC_FONT_UI);

    // Value text - widened column to fit "ACTIVE cap 40%", "0.0% / 20-30%", etc.
    DrawLabel(id + "_val", x + 170, y + 4, value_text, text_clr, RC_FONT_SIZE);

    // Progress bar starts further right to give the value column 130 px instead of 90 px
    const int bar_x = x + 360; // P6/P4 : wider value column ("locked X%" + 2 decimals)
    const int bar_y = y + 5;
    const int bar_w = w - 360 - 80 - RC_PAD;
    const int bar_h = h - 10;
    // 1.1 : the "Max lot allowed" row (rule_margin_pt) renders TEXT-ONLY in the
    // indicator. The bar + chip drawing is KEPT for the future Helper-EA but
    // skipped here so the value text is not hidden under a bar.
    if (key_prefix != "rule_margin_pt" && key_prefix != "rule_newsstats") {
        if (applies)
            DrawProgressBar(id + "_bar", bar_x, bar_y, bar_w, bar_h, pct, max_pct, status);
        else
            DrawRect(id + "_bar_empty", bar_x, bar_y, bar_w, bar_h, g_theme.bar_bg, g_theme.bar_bg, 0);

        // Status chip (right)
        const int chip_x = x + w - 70;
        DrawStatusChip(id + "_chip", chip_x, y + 3, 60, h - 6, applies ? status : RC_STATUS_NA);
    }
}

//+------------------------------------------------------------------+
//| Progress bar                                                     |
//+------------------------------------------------------------------+
void DrawProgressBar(const string id, int x, int y, int w, int h,
                     double pct, double max_pct, ENUM_RC_STATUS status) {
    DrawRect(id + "_bg", x, y, w, h, g_theme.bar_bg, g_theme.bar_bg, 0);

    double r = (max_pct > 0.0 ? pct / max_pct : 0.0);
    if (r < 0.0)
        r = 0.0;
    if (r > 1.0)
        r = 1.0;
    const int fill_w = (int)MathRound(w * r);

    // LOT E : color-graded fill. NA / inapplicable rows keep the StatusColor
    // (grey) ; everyone else interpolates green -> amber -> red along r so the
    // bar visually fades into danger instead of jumping at status thresholds.
    const color fill = (status == RC_STATUS_NA) ? StatusColor(status) : GradientColor(r);
    if (fill_w > 0)
        DrawRect(id + "_fill", x, y, fill_w, h, fill, fill, 0);
}

//+------------------------------------------------------------------+
//| LOT E : linearly interpolate the bar fill across green -> amber   |
//| -> red according to r (the used / cap ratio). Anchors :           |
//|   r <= 0.0 -> g_theme.ok   (green)                                |
//|   r = 0.7  -> g_theme.warn (amber)                                |
//|   r >= 1.0 -> g_theme.red                                         |
//| MQL5 color packing : R in lowest byte, G in mid, B in high byte.  |
//+------------------------------------------------------------------+
color GradientColor(double r) {
    if (r <= 0.0) return g_theme.ok;
    if (r >= 1.0) return g_theme.red;
    double r0, r1;
    color c0, c1;
    if (r < 0.7) { r0 = 0.0; r1 = 0.7; c0 = g_theme.ok;   c1 = g_theme.warn; }
    else         { r0 = 0.7; r1 = 1.0; c0 = g_theme.warn; c1 = g_theme.red;  }
    const double t = (r - r0) / (r1 - r0);
    const int rA = (int)((((int)c0      ) & 0xFF) * (1.0 - t) + (((int)c1      ) & 0xFF) * t);
    const int gA = (int)((((int)c0 >>  8) & 0xFF) * (1.0 - t) + (((int)c1 >>  8) & 0xFF) * t);
    const int bA = (int)((((int)c0 >> 16) & 0xFF) * (1.0 - t) + (((int)c1 >> 16) & 0xFF) * t);
    return (color)((rA & 0xFF) | ((gA & 0xFF) << 8) | ((bA & 0xFF) << 16));
}

//+------------------------------------------------------------------+
//| V1.24 G1 : DISCIPLINE-LOCK (advisory ; the indicator never blocks |
//| orders - the companion EA V2 will). Priority of states :          |
//|   self-lock (Ulysses pact)  >  daily-DD >= 80% cap  >  cooldown    |
//|   (K consecutive losses)  >  tilt warning (rapid trades OR revenge |
//|   sizing). Hard locks paint the full-panel red STOP ; tilt paints  |
//|   a soft amber banner + sound + Telegram. All gated by             |
//|   InpDisciplineLockEnabled (g_eff_discipline).                     |
//+------------------------------------------------------------------+
datetime g_selflock_until = 0;      // self-lock expiry (persisted GV RC_selflock_until)
datetime g_unlock_arm     = 0;      // unlock double-confirm arm time
datetime g_disc_scan      = 0;      // metric cache stamp (one history scan / 5 s)
int      g_disc_consec     = 0;     // consecutive losing closed trades (newest streak)
datetime g_disc_lastloss   = 0;     // close time of the most recent loss
int      g_disc_trades_win = 0;     // entries within InpTiltWindowMin
bool     g_disc_revenge    = false; // newest open vol > last closed-loss vol
datetime g_disc_last_alert = 0;     // tilt sound/Telegram throttle

// One bounded history scan (cached 5 s) feeding all the discipline metrics, so
// nothing heavy runs on the 500 ms refresh path (LOT 1 freeze lesson).
void ComputeDisciplineMetrics(void) {
    if (g_disc_scan != 0 && TimeCurrent() - g_disc_scan < 5) return;
    g_disc_scan = TimeCurrent();
    g_disc_consec = 0; g_disc_lastloss = 0; g_disc_trades_win = 0; g_disc_revenge = false;
    const datetime now = TimeCurrent();
    const datetime win_from = now - (datetime)MathMax(1, g_eff_tilt_win) * 60;
    if (!HistorySelect(now - 30 * 86400, now)) return;
    const int n = HistoryDealsTotal();
    bool   streak_open = true;
    double last_loss_vol = -1.0;
    for (int i = n - 1; i >= 0; --i) {
        const ulong t = HistoryDealGetTicket(i);
        if (t == 0) continue;
        const long     e  = HistoryDealGetInteger(t, DEAL_ENTRY);
        const datetime dt = (datetime)HistoryDealGetInteger(t, DEAL_TIME);
        if (e == DEAL_ENTRY_IN && dt >= win_from) g_disc_trades_win++;
        if (e == DEAL_ENTRY_OUT || e == DEAL_ENTRY_INOUT) {
            const double pnl = HistoryDealGetDouble(t, DEAL_PROFIT) +
                               HistoryDealGetDouble(t, DEAL_SWAP) +
                               HistoryDealGetDouble(t, DEAL_COMMISSION);
            if (streak_open) {
                if (pnl < 0.0) { g_disc_consec++; if (g_disc_lastloss == 0) g_disc_lastloss = dt; }
                else           { streak_open = false; } // a win/breakeven ends the streak
            }
            if (last_loss_vol < 0.0 && pnl < 0.0) last_loss_vol = HistoryDealGetDouble(t, DEAL_VOLUME);
        }
    }
    // revenge sizing : newest OPEN position bigger than the last closed LOSS
    if (last_loss_vol > 0.0) {
        double newest_vol = 0.0; datetime newest_time = 0;
        const int np = PositionsTotal();
        for (int i = 0; i < np; ++i) {
            const ulong pt = PositionGetTicket(i);
            if (pt == 0 || !PositionSelectByTicket(pt)) continue;
            const datetime ot = (datetime)PositionGetInteger(POSITION_TIME);
            if (ot >= newest_time) { newest_time = ot; newest_vol = PositionGetDouble(POSITION_VOLUME); }
        }
        if (newest_vol > last_loss_vol + 1e-9) g_disc_revenge = true;
    }
}

// Full-panel red STOP overlay used by self-lock / daily-DD / cooldown.
void DrawHardLock(const string msg, bool show_unlock) {
    const string id        = RC_PREFIX + "discipline_overlay";
    const string txt_id    = RC_PREFIX + "discipline_text";
    const string unlock_id = RC_PREFIX + "disc_unlock";
    const int overlay_h = (g_panel_height > 0 ? g_panel_height : RC_TITLE_HEIGHT + InpRowHeight);
    if (ObjectFind(0, id) < 0) ObjectCreate(0, id, OBJ_RECTANGLE_LABEL, 0, 0, 0);
    ObjectSetInteger(0, id, OBJPROP_XDISTANCE, g_anchor_x);
    ObjectSetInteger(0, id, OBJPROP_YDISTANCE, g_anchor_y);
    ObjectSetInteger(0, id, OBJPROP_XSIZE, InpPanelWidth);
    ObjectSetInteger(0, id, OBJPROP_YSIZE, overlay_h);
    ObjectSetInteger(0, id, OBJPROP_BGCOLOR, g_theme.red);
    ObjectSetInteger(0, id, OBJPROP_COLOR, g_theme.red);
    ObjectSetInteger(0, id, OBJPROP_CORNER, CORNER_LEFT_UPPER);
    ObjectSetInteger(0, id, OBJPROP_BACK, false);
    ObjectSetInteger(0, id, OBJPROP_SELECTABLE, false);
    ObjectSetInteger(0, id, OBJPROP_HIDDEN, true);
    ObjectSetInteger(0, id, OBJPROP_ZORDER, 200);
    if (ObjectFind(0, txt_id) < 0) ObjectCreate(0, txt_id, OBJ_LABEL, 0, 0, 0);
    ObjectSetInteger(0, txt_id, OBJPROP_XDISTANCE, g_anchor_x + InpPanelWidth / 2);
    ObjectSetInteger(0, txt_id, OBJPROP_YDISTANCE, g_anchor_y + overlay_h / 2 - 8);
    ObjectSetString(0, txt_id, OBJPROP_TEXT, msg);
    ObjectSetInteger(0, txt_id, OBJPROP_COLOR, (color)0x00FFFFFF); // V1.29 B : white on the red STOP box (was g_theme.bg = black in dark theme)
    ObjectSetInteger(0, txt_id, OBJPROP_FONTSIZE, 11);
    ObjectSetString(0, txt_id, OBJPROP_FONT, RC_FONT_UI);
    ObjectSetInteger(0, txt_id, OBJPROP_ANCHOR, ANCHOR_CENTER);
    ObjectSetInteger(0, txt_id, OBJPROP_CORNER, CORNER_LEFT_UPPER);
    ObjectSetInteger(0, txt_id, OBJPROP_SELECTABLE, false);
    ObjectSetInteger(0, txt_id, OBJPROP_HIDDEN, true);
    ObjectSetInteger(0, txt_id, OBJPROP_ZORDER, 201);
    if (show_unlock) {
        const bool armed = (g_unlock_arm > 0 && TimeCurrent() - g_unlock_arm <= 5);
        if (ObjectFind(0, unlock_id) < 0) ObjectCreate(0, unlock_id, OBJ_BUTTON, 0, 0, 0);
        ObjectSetInteger(0, unlock_id, OBJPROP_XDISTANCE, g_anchor_x + InpPanelWidth / 2 - 80);
        ObjectSetInteger(0, unlock_id, OBJPROP_YDISTANCE, g_anchor_y + overlay_h / 2 + 14);
        ObjectSetInteger(0, unlock_id, OBJPROP_XSIZE, 160);
        ObjectSetInteger(0, unlock_id, OBJPROP_YSIZE, 22);
        ObjectSetString(0, unlock_id, OBJPROP_TEXT, armed ? Tr("disc_unlock_confirm") : Tr("disc_unlock"));
        ObjectSetString(0, unlock_id, OBJPROP_FONT, RC_FONT_UI);
        ObjectSetInteger(0, unlock_id, OBJPROP_FONTSIZE, RC_FONT_SIZE);
        ObjectSetInteger(0, unlock_id, OBJPROP_COLOR, (color)0x00FFFFFF); // V1.29 B : white Unlock label (readable in dark theme)
        ObjectSetInteger(0, unlock_id, OBJPROP_BGCOLOR, armed ? g_theme.warn : g_theme.bg_section);
        ObjectSetInteger(0, unlock_id, OBJPROP_BORDER_COLOR, g_theme.border);
        ObjectSetInteger(0, unlock_id, OBJPROP_CORNER, CORNER_LEFT_UPPER);
        ObjectSetInteger(0, unlock_id, OBJPROP_STATE, false);
        ObjectSetInteger(0, unlock_id, OBJPROP_SELECTABLE, false);
        ObjectSetInteger(0, unlock_id, OBJPROP_HIDDEN, true);
        ObjectSetInteger(0, unlock_id, OBJPROP_ZORDER, 260);
    } else {
        ObjectDelete(0, unlock_id);
    }
    // V1.24 fix : hide every panel control (buttons / OBJ_EDIT / logo bitmap)
    // except the unlock button - a rectangle overlay cannot cover MT5 controls.
    // Also blocks the gear during a lock so it can't be disabled to bypass it.
    SetPanelControlsHidden(true, "disc_unlock");
}

// V1.24 fix (JR test #2) : returns TRUE if a HARD LOCK (self-lock / daily-DD /
// cooldown) is active - it has then drawn the full-panel STOP + hidden the
// controls, and the caller (RefreshPanel) MUST skip its content so the rows /
// bars are not recreated on top of the overlay every tick (MT5 redraws rectangle
// labels in creation order, not ZORDER). Returns FALSE otherwise (red overlay
// cleared, controls shown). The soft TILT banner is handled by DrawTiltBanner().
bool UpdateDisciplineOverlay(double daily_dd_pct, double daily_cap) {
    const string id        = RC_PREFIX + "discipline_overlay";
    const string txt_id    = RC_PREFIX + "discipline_text";
    const string unlock_id = RC_PREFIX + "disc_unlock";
    if (!g_eff_discipline || !g_eff_risktools) { // V1.29 J : risk-tools OFF also clears any lock overlay
        ObjectDelete(0, id); ObjectDelete(0, txt_id); ObjectDelete(0, unlock_id);
        SetPanelControlsHidden(false, "");
        return false;
    }
    ComputeDisciplineMetrics();
    const datetime now = TimeCurrent();

    // --- hard locks, by priority ---
    if (g_selflock_until > now) {
        const int mins = (int)((g_selflock_until - now) / 60) + 1;
        DrawHardLock(Tr("disc_selflock") + "  " + IntegerToString(mins / 60) + "h " +
                     IntegerToString(mins % 60) + "m", true);
        return true;
    }
    if (daily_cap > 0.0 && daily_dd_pct >= 0.80 * daily_cap) {
        DrawHardLock(Tr("stop_trading") + "  (" + DoubleToString(daily_dd_pct, 1) +
                     "% / cap " + DoubleToString(daily_cap, 1) + "%)", false);
        return true;
    }
    if (g_eff_cooldown_n > 0 && g_disc_consec >= g_eff_cooldown_n && g_disc_lastloss > 0) {
        const datetime cd_until = g_disc_lastloss + (datetime)MathMax(0, g_eff_cooldown_m) * 60;
        if (now < cd_until) {
            const int m = (int)((cd_until - now) / 60) + 1;
            DrawHardLock(Tr("disc_cooldown") + "  (" + IntegerToString(g_disc_consec) + "L / " +
                         IntegerToString(m) + "m)", false);
            return true;
        }
    }
    // no hard lock -> clear the red overlay + show the controls again.
    ObjectDelete(0, id); ObjectDelete(0, txt_id); ObjectDelete(0, unlock_id);
    SetPanelControlsHidden(false, "");
    return false;
}

// Soft TILT warning (amber banner over the strip). Drawn at the END of
// RefreshPanel, only when NOT hard-locked. Uses the metrics cached this tick.
void DrawTiltBanner(void) {
    const string tilt_id   = RC_PREFIX + "disc_tilt";
    const string tiltx_id  = RC_PREFIX + "disc_tilt_txt";
    const datetime now = TimeCurrent();
    const bool tilt = (g_eff_discipline &&
                       ((g_eff_tilt_n > 0 && g_disc_trades_win > g_eff_tilt_n) || g_disc_revenge));
    if (!tilt) { ObjectDelete(0, tilt_id); ObjectDelete(0, tiltx_id); return; }
    if (ObjectFind(0, tilt_id) < 0) ObjectCreate(0, tilt_id, OBJ_RECTANGLE_LABEL, 0, 0, 0);
    ObjectSetInteger(0, tilt_id, OBJPROP_XDISTANCE, g_anchor_x);
    ObjectSetInteger(0, tilt_id, OBJPROP_YDISTANCE, g_anchor_y + RC_TITLE_HEIGHT);
    ObjectSetInteger(0, tilt_id, OBJPROP_XSIZE, InpPanelWidth);
    ObjectSetInteger(0, tilt_id, OBJPROP_YSIZE, InpRowHeight);
    ObjectSetInteger(0, tilt_id, OBJPROP_BGCOLOR, g_theme.warn);
    ObjectSetInteger(0, tilt_id, OBJPROP_COLOR, g_theme.warn);
    ObjectSetInteger(0, tilt_id, OBJPROP_CORNER, CORNER_LEFT_UPPER);
    ObjectSetInteger(0, tilt_id, OBJPROP_BACK, false);
    ObjectSetInteger(0, tilt_id, OBJPROP_SELECTABLE, false);
    ObjectSetInteger(0, tilt_id, OBJPROP_HIDDEN, true);
    ObjectSetInteger(0, tilt_id, OBJPROP_ZORDER, 150);
    if (ObjectFind(0, tiltx_id) < 0) ObjectCreate(0, tiltx_id, OBJ_LABEL, 0, 0, 0);
    ObjectSetInteger(0, tiltx_id, OBJPROP_XDISTANCE, g_anchor_x + InpPanelWidth / 2);
    ObjectSetInteger(0, tiltx_id, OBJPROP_YDISTANCE, g_anchor_y + RC_TITLE_HEIGHT + InpRowHeight / 2); // P5 : vertical-center
    ObjectSetString(0, tiltx_id, OBJPROP_TEXT, Tr("disc_tilt") + (g_disc_revenge ? "  (revenge)" : ""));
    ObjectSetInteger(0, tiltx_id, OBJPROP_COLOR, g_theme.bg);
    ObjectSetInteger(0, tiltx_id, OBJPROP_FONTSIZE, RC_FONT_SIZE);
    ObjectSetString(0, tiltx_id, OBJPROP_FONT, RC_FONT_UI);
    ObjectSetInteger(0, tiltx_id, OBJPROP_ANCHOR, ANCHOR_CENTER);
    ObjectSetInteger(0, tiltx_id, OBJPROP_CORNER, CORNER_LEFT_UPPER);
    ObjectSetInteger(0, tiltx_id, OBJPROP_SELECTABLE, false);
    ObjectSetInteger(0, tiltx_id, OBJPROP_HIDDEN, true);
    ObjectSetInteger(0, tiltx_id, OBJPROP_ZORDER, 151);
    if (now - g_disc_last_alert >= 60) {
        g_disc_last_alert = now;
        if (g_eff_sound)    PlaySound(InpSoundWarn);
        if (g_eff_telegram) SendTelegramMessage("[TILT] RiskCockpit : tilt detected - slow down (Acc #" +
                                                 IntegerToString((int)AccountInfoInteger(ACCOUNT_LOGIN)) + ")");
    }
}

//+------------------------------------------------------------------+
//| Status chip                                                      |
//+------------------------------------------------------------------+
void DrawStatusChip(const string id, int x, int y, int w, int h, ENUM_RC_STATUS status) {
    const color clr = StatusColor(status);
    DrawRect(id + "_bg", x, y, w, h, clr, clr, 0);
    // P7 theme fix : chips are always a BRIGHT bg (green/amber/red) -> use a
    // fixed near-black text so it stays readable on BOTH themes (g_theme.bg was
    // light in the light theme = unreadable on a green chip).
    DrawLabel(id + "_txt", x + 6, y + 2, StatusLabel(status), (color)0x00181818, RC_FONT_SIZE - 1);
}

//+------------------------------------------------------------------+
//| Violation toggle (B7) - clickable OBJ_BUTTON checkbox            |
//|                                                                  |
//| Red fill + "X" when active (cap tightened), neutral + blank when |
//| inactive. The button only triggers the click; the boolean flag   |
//| (g_*_violation_active) remains the source of truth. OnChartEvent  |
//| toggles the flag, persists it, and resets OBJPROP_STATE so the    |
//| button never sticks in the pressed look.                         |
//+------------------------------------------------------------------+
void DrawViolationToggle(const string key, int x, int y, int h, bool active) {
    const string id = RC_PREFIX + key + "_viol";
    if (ObjectFind(0, id) < 0)
        ObjectCreate(0, id, OBJ_BUTTON, 0, 0, 0);
    ObjectSetInteger(0, id, OBJPROP_XDISTANCE, x);
    ObjectSetInteger(0, id, OBJPROP_YDISTANCE, y);
    ObjectSetInteger(0, id, OBJPROP_XSIZE, 16);
    ObjectSetInteger(0, id, OBJPROP_YSIZE, h);
    ObjectSetString(0, id, OBJPROP_TEXT, (active ? "X" : " "));
    ObjectSetString(0, id, OBJPROP_FONT, RC_FONT_UI);
    ObjectSetInteger(0, id, OBJPROP_FONTSIZE, RC_FONT_SIZE - 1);
    ObjectSetInteger(0, id, OBJPROP_COLOR, (active ? g_theme.bg : g_theme.text_dim));
    ObjectSetInteger(0, id, OBJPROP_BGCOLOR, (active ? g_theme.red : g_theme.surface_hi));
    ObjectSetInteger(0, id, OBJPROP_BORDER_COLOR, g_theme.border_hi);
    ObjectSetInteger(0, id, OBJPROP_CORNER, CORNER_LEFT_UPPER);
    ObjectSetInteger(0, id, OBJPROP_STATE, false);
    ObjectSetInteger(0, id, OBJPROP_BACK, false);
    ObjectSetInteger(0, id, OBJPROP_SELECTABLE, false);
    ObjectSetInteger(0, id, OBJPROP_HIDDEN, true);
    ObjectSetInteger(0, id, OBJPROP_ZORDER, 100); // LOT B : click target wins
    ObjectSetString(0, id, OBJPROP_TOOLTIP,
                    (key == "rule_margin_cum")
                        ? "Margin violation suffered -> cumulative cap tightens to InpMarginCapViolated"
                        : "Risk violation suffered -> cumulative cap tightens to InpRiskCapViolated");
}

//+------------------------------------------------------------------+
//| Positions section                                                |
//+------------------------------------------------------------------+
int DrawPositionsSection(int x, int y, int w) {
    DrawSectionHeader("sec_pos", x, y, w, Tr("open_pos"), g_theme.accent2);
    int cy = y + RC_SECTION_HEIGHT;
    for (int i = 0; i < RC_MAX_POSITIONS; ++i) {
        const string id = RC_PREFIX + "pos_" + IntegerToString(i);
        DrawRect(id + "_rowbg", x + 1, cy, w - 2, InpRowHeight,
                 ((i % 2) == 0 ? g_theme.surface : g_theme.surface_hi),
                 ((i % 2) == 0 ? g_theme.surface : g_theme.surface_hi), 0);
        DrawLabel(id + "_lbl", x + RC_PAD, cy + 4, "", g_theme.text_dim, RC_FONT_SIZE);
        DrawLabel(id + "_pnl", x + 220, cy + 4, "", g_theme.text_dim, RC_FONT_SIZE);
        DrawLabel(id + "_age", x + 320, cy + 4, "", g_theme.text_dim, RC_FONT_SIZE);
        DrawStatusChip(id + "_chip", x + w - 70, cy + 3, 60, InpRowHeight - 6, RC_STATUS_NA);
        // start every slot empty (no visible chip until a position fills it)
        ObjectSetInteger(0, id + "_chip_bg", OBJPROP_BGCOLOR, ((i % 2) == 0 ? g_theme.surface : g_theme.surface_hi));
        ObjectSetInteger(0, id + "_chip_bg", OBJPROP_COLOR,   ((i % 2) == 0 ? g_theme.surface : g_theme.surface_hi));
        ObjectSetString(0, id + "_chip_txt", OBJPROP_TEXT, " ");
        // V1.27 : the symbol cell is a click-to-switch button (OBJ_BUTTON is the
        // reliable click target in this codebase ; it sits over the _lbl and
        // carries the same text, so clicking it switches the chart symbol).
        const string rowbtn = RC_PREFIX + "pos_row_" + IntegerToString(i);
        const color rbg = ((i % 2) == 0 ? g_theme.surface : g_theme.surface_hi);
        if (ObjectFind(0, rowbtn) < 0) ObjectCreate(0, rowbtn, OBJ_BUTTON, 0, 0, 0);
        ObjectSetInteger(0, rowbtn, OBJPROP_XDISTANCE, x + 1);
        ObjectSetInteger(0, rowbtn, OBJPROP_YDISTANCE, cy);
        ObjectSetInteger(0, rowbtn, OBJPROP_XSIZE, 210);
        ObjectSetInteger(0, rowbtn, OBJPROP_YSIZE, InpRowHeight);
        ObjectSetString(0, rowbtn, OBJPROP_TEXT, " ");
        ObjectSetString(0, rowbtn, OBJPROP_FONT, RC_FONT_UI);
        ObjectSetInteger(0, rowbtn, OBJPROP_FONTSIZE, RC_FONT_SIZE);
        ObjectSetInteger(0, rowbtn, OBJPROP_COLOR, g_theme.text);
        ObjectSetInteger(0, rowbtn, OBJPROP_BGCOLOR, rbg);
        ObjectSetInteger(0, rowbtn, OBJPROP_BORDER_COLOR, rbg);
        ObjectSetInteger(0, rowbtn, OBJPROP_CORNER, CORNER_LEFT_UPPER);
        ObjectSetInteger(0, rowbtn, OBJPROP_STATE, false);
        ObjectSetInteger(0, rowbtn, OBJPROP_SELECTABLE, false);
        ObjectSetInteger(0, rowbtn, OBJPROP_HIDDEN, true);
        ObjectSetInteger(0, rowbtn, OBJPROP_ZORDER, 101);
        ObjectSetString(0, rowbtn, OBJPROP_TOOLTIP, Tr("pos_click_tip"));
        cy += InpRowHeight;
    }
    return cy;
}

//+------------------------------------------------------------------+
//| Footer                                                           |
//+------------------------------------------------------------------+
void DrawFooter(int x, int y, int w) {
    // 3 rows by default; +1 row (L4) when pyramid advisor is enabled.
    const int rows = (InpEnablePyramidSafe ? 4 : 3);
    DrawRect(RC_PREFIX + "footer_bg", x, y, w, InpRowHeight * rows, g_theme.surface, g_theme.border, 0);

    // Row 1 - profit metrics : drawn as individually-coloured segments
    // (RC_ + "fseg_*") by RefreshFooterMetrics (P1). Just record the row y here.
    g_footer_y = y;

    // Row 2 - suggested lot info + interactive max-parallel control
    DrawLabel(RC_PREFIX + "footer_l2", x + RC_PAD, y + 4 + InpRowHeight, " ", g_theme.text, RC_FONT_SIZE);
    DrawMaxParallelControl(x + w - 90, y + 2 + InpRowHeight);

    // Row 3 - add-ons + brand
    string addons_str = g_catalog.DescribeAddons(g_addons_mask);
    string line3;
    StringConcatenate(line3,
                      "Add-ons : ", addons_str,
                      "    Split ", DoubleToString(g_profile.profit_split_pct, 0), "%",
                      "    Min days ", g_profile.min_trading_days,
                      "    -  javadrazavi.fr");
    DrawLabel(RC_PREFIX + "footer_l3", x + RC_PAD, y + 4 + InpRowHeight * 2,
              line3, g_theme.text_dim, RC_FONT_SIZE - 1);

    // Row 4 - Pyramid advisor (visible only when InpEnablePyramidSafe).
    if (InpEnablePyramidSafe) {
        DrawLabel(RC_PREFIX + "footer_l4", x + RC_PAD, y + 4 + InpRowHeight * 3,
                  "Pyramid : initializing...", g_theme.accent, RC_FONT_SIZE);
    }
}

//+------------------------------------------------------------------+
//| RefreshPanel - reads stub values and updates labels/bars          |
//| T7 will replace the Stub_ calls with real implementations.       |
//+------------------------------------------------------------------+
void RefreshPanel(void) {
    if (!g_profile_ok && !g_profile.is_default_fallback)
        return;

    // V1.24 fix : if a discipline HARD LOCK is active, the overlay is drawn here
    // and we SKIP the whole panel refresh - otherwise UpdateRow would recreate
    // the bars/chips every tick on top of the overlay (MT5 redraws rectangle
    // labels in creation order). The lingering rows from the last normal refresh
    // stay UNDER the freshly-created overlay ; controls are hidden by it too.
    if (UpdateDisciplineOverlay(Live_DailyDdPct(), g_profile.daily_loss_pct))
        return;

    // V1.29 J : the whole prop rule-set (live values + rows + bars + chips +
    // sound alerts via UpdateRow) only refreshes when the risk toolkit is ON.
    // When OFF the rule rows stay INERT (drawn by BuildPanel, not updated) ; the
    // account strip + positions below always refresh so basic info stays live.
    if (g_eff_risktools) {
    // === Compute live values (T7) ====================================
    const double margin_cum_pct = Live_CumulativeMarginPct();
    const double margin_pt_pct = Live_PerTradeMarginPct();
    const double risk_cum_pct = Live_CumulativeRiskPct();
    const double daily_dd_pct = Live_DailyDdPct();
    const double overall_dd_pct = Live_OverallDdPct();
    const double target_pct = Live_ProfitTargetPct();
    const double qs_ratio_pct = Live_QuickStrikeRatioPct();
    const int trades_today = Live_TradesToday();

    // === Update rule rows ============================================
    // 0: Cumulative Margin (cap tightens to InpMarginCapViolated if violation active - B7)
    const double margin_cap = EffectiveMarginCap();
    const string margin_suffix = (g_margin_violation_active ? "  VIOL" : "");
    UpdateRow(0, margin_cum_pct, margin_cap,
              FormatPct(margin_cum_pct) + " / " + FormatPct(margin_cap) + margin_suffix,
              ComputeRangeStatus(margin_cum_pct, margin_cap, 0.80, 1.00),
              true);

    // 1: Max lot allowed (1.1) - TEXT-ONLY row (bar hidden in the indicator).
    // Largest lot of the ACTIVE symbol allowed under BOTH the per-trade margin
    // cap (g_eff_max_margin_pt) AND the per-trade risk cap
    // (g_eff_max_risk_pt, SL at g_eff_sl_pct). margin_pt_pct stays computed
    // and passed as the (hidden) bar pct for the future Helper-EA.
    // 1: Max lot allowed (1.1 + M1c) - largest lot of the active symbol under the
    // per-trade margin cap, via the broker-exact MarginPerLot (OrderCalcMargin
    // primary, calc-mode-aware fallback). Text-only row (bar hidden).
    string maxlot_text;
    {
        // FIX (LOT 3) : adaptive Max Lot. Shows the RULE-allowed lot (target % of
        // INITIAL balance) when free margin covers it ; otherwise falls back to
        // "N lots @ X% free (target Y%)" so the user sees both the cap AND what
        // is actually openable RIGHT NOW with the real broker free margin.
        const double m1       = MarginPerLot(_Symbol);
        const double init_bal = g_profile.initial_balance;
        const double tgt_pct  = g_eff_max_margin_pt;
        const double free_m   = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
        // V1.29 A : removed the ungated "RC Max-lot debug" Print (log spam in the
        // client's Experts tab ; the only hot-path Print). Diagnostics stay in the
        // g_maxlot_* globals for an opt-in debug build if ever needed.
        if (m1 <= 0.0 || init_bal <= 0.0) {
            maxlot_text = Tr("maxlot_na") + " err=" + IntegerToString(g_maxlot_err);
        } else {
            // B-MAXLOT-MARGINROOM (audit 2026-06-07) : the largest openable lot is
            // the MIN of THREE caps, not just the per-trade target :
            //   (a) per-trade margin target = g_eff_max_margin_pt % of initial bal
            //   (b) cumulative-cap room left = (EffectiveMarginCap - used) % of init
            //   (c) real broker free margin  = ACCOUNT_MARGIN_FREE
            // The old code did only min(a, c) -> it still showed the 25 % target
            // when e.g. 60 % of the 70 % cumulative cap was already used (only
            // ~10 % room left). Now (b) binds and the row shows the real max.
            const double tgt_money  = (tgt_pct / 100.0) * init_bal;
            const double cum_used   = Live_CumulativeMarginPct();
            const double cum_cap    = EffectiveMarginCap();
            const double room_pct   = MathMax(0.0, cum_cap - cum_used);
            const double room_money = room_pct / 100.0 * init_bal;
            const double avail_pct  = 100.0 * free_m / init_bal;
            const double money_cap  = MathMin(tgt_money, MathMin(room_money, free_m));
            const double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
            const double vmin = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
            const double vmax = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
            double lot = money_cap / m1;
            if (step > 0.0) lot = MathFloor(lot / step) * step;
            if (lot < vmin) lot = 0.0;
            else if (vmax > 0.0 && lot > vmax) lot = vmax;
            const int ld = LotDigits(step);  // B-LOTPRECISION : crypto step=0.00001 -> 5 decimals
            g_maxlot_copy = (lot > 0.0 ? lot : 0.0); g_maxlot_digits = ld; // V1.24 G3 copy
            // Which cap binds ? (tie -> prefer target, then cumulative room, then free)
            string tag; double pct_disp;
            if (tgt_money <= room_money + 1e-6 && tgt_money <= free_m + 1e-6) { tag = "marg"; pct_disp = tgt_pct; }
            else if (room_money <= free_m + 1e-6)                            { tag = "room"; pct_disp = room_pct; }
            else                                                             { tag = "free"; pct_disp = avail_pct; }
            const string tag_disp = (tag == "marg" ? Tr("tag_marg") : tag == "room" ? Tr("tag_room") : Tr("tag_free"));
            if (lot <= 0.0) {
                maxlot_text = Tr("maxlot_belowmin") + " " + DoubleToString(pct_disp, 1) + "% " + tag_disp +
                              "  (" + Tr("tag_free") + " " + DoubleToString(avail_pct, 1) + "%)";
            } else if (tag == "marg") {
                maxlot_text = DoubleToString(lot, ld) + " lots @ " + DoubleToString(tgt_pct, 1) +
                              "% " + tag_disp + "  (" + _Symbol + ")";
            } else {
                maxlot_text = DoubleToString(lot, ld) + " lots @ " + DoubleToString(pct_disp, 1) + "% " + tag_disp +
                              "  (" + Tr("used") + " " + DoubleToString(cum_used, 1) + "/" + DoubleToString(cum_cap, 0) +
                              "% cap)  " + _Symbol;
            }
        }
    }
    UpdateRow(1, margin_pt_pct, g_eff_max_margin_pt, maxlot_text, RC_STATUS_NA, true);

    // 2: Cumulative Open Risk (cap tightens to InpRiskCapViolated if violation active - B7)
    // FIX 1 (V1.0.1) : the open-risk meter must stay LIVE + alert (sound + Telegram)
    // wherever a cap is defined - challenge / free / Instant / funded - not only on
    // funded. The old gate (g_profile.open_risk_rule_applies = funded-only) silenced
    // the alert on every non-funded profile (the 200K challenge/free JR tested
    // included), which is exactly the rule JR breached and the whole reason this
    // panel exists. Excess open risk is dangerous on ANY account; monitor it
    // whenever a cap exists (cap > 0). Only Futures-placeholder (cap 0) shows N/A.
    const double risk_cap = EffectiveRiskCap();
    const bool risk_applies = (risk_cap > 0.0);
    const string risk_suffix = (g_risk_violation_active ? "  VIOL" : "");
    // FIX (LOT 2) : "Locked risk" = the value FundedNext scores against (sum of
    // risks at each position's INITIAL SL, locked at opening). Distinct from the
    // current-market risk : tightening a SL after opening does NOT reduce it.
    const double locked_risk_pct = Live_LockedRiskPct();
    UpdateRow(2, risk_cum_pct, risk_cap,
              risk_applies
                  ? (FormatPct(risk_cum_pct) + " / " + FormatPct(risk_cap) + risk_suffix +
                     (locked_risk_pct > 0.001 ? "  " + Tr("locked") + " " + FormatPct(locked_risk_pct) : ""))
                  : "N/A",
              ComputeRangeStatus(risk_cum_pct, risk_cap, 0.70, 1.00),
              risk_applies);

    // 3: Daily DD
    const bool dd_applies = (g_profile.daily_loss_pct > 0.0);
    // V1.24 fix : the discipline overlay is now drawn LAST (end of RefreshPanel)
    // so it sits on top of every row/footer/position object recreated this tick.
    UpdateRow(3, daily_dd_pct, g_profile.daily_loss_pct,
              dd_applies
                  ? (FormatPct(daily_dd_pct) + " / " + FormatPct(g_profile.daily_loss_pct))
                  : "N/A (Instant)",
              ComputeRangeStatus(daily_dd_pct, g_profile.daily_loss_pct, 0.70, 1.00),
              dd_applies);

    // 4: Overall DD - Personal / no-prop profile has max_loss_pct=0 -> show N/A
    // instead of a meaningless "2.0% / 0.0%".
    const bool max_loss_applies = (g_profile.max_loss_pct > 0.0);
    UpdateRow(4, overall_dd_pct, g_profile.max_loss_pct,
              max_loss_applies
                  ? (FormatPct(overall_dd_pct) + " / " + FormatPct(g_profile.max_loss_pct) +
                     (g_profile.max_loss_trailing ? "  (trailing)" : ""))
                  : "N/A",
              ComputeRangeStatus(overall_dd_pct, g_profile.max_loss_pct, 0.70, 1.00),
              max_loss_applies);

    // 5: Profit Target - PROGRESS meter, NOT a risk meter. FIX 3 (V1.0.1) : the old
    // 2-state mapping (reached = green, else amber) painted the row amber the whole
    // way to target, reading as a warning while you were doing well. Invert to a
    // progress palette for THIS row only: far = neutral/grey, near (>=70%) = amber,
    // reached/exceeded = GREEN. Alerts are suppressed for this row in
    // TryFireSoundAlert (hitting your target is good news, not a warning).
    const bool tgt_applies = (g_profile.profit_target_pct > 0.0);
    ENUM_RC_STATUS tgt_status = RC_STATUS_NA;
    if (tgt_applies) {
        const double tgt_ratio = target_pct / g_profile.profit_target_pct;
        if (tgt_ratio >= 1.0)       tgt_status = RC_STATUS_OK;    // reached/exceeded = GREEN
        else if (tgt_ratio >= 0.70) tgt_status = RC_STATUS_WARN;  // near = amber
        else                        tgt_status = RC_STATUS_NA;    // far = neutral/grey
    }
    UpdateRow(5, target_pct, g_profile.profit_target_pct,
              tgt_applies
                  ? (FormatPct(target_pct) + " / " + FormatPct(g_profile.profit_target_pct))
                  : "-- (funded)",
              tgt_status,
              tgt_applies);

    // 6: Quick Strike Ratio
    UpdateRow(6, qs_ratio_pct, g_profile.quick_strike_violate_pct,
              FormatPct(qs_ratio_pct) + " / " + FormatPct(g_profile.quick_strike_violate_pct),
              ComputeRangeStatus(qs_ratio_pct,
                                 g_profile.quick_strike_violate_pct,
                                 g_profile.quick_strike_warn_pct / g_profile.quick_strike_violate_pct,
                                 1.00),
              true);

    // 7: Hyperactivity
    const double hyper_pct = (g_profile.hyperactivity_trades_per_day > 0
                                  ? 100.0 * trades_today / g_profile.hyperactivity_trades_per_day
                                  : 0.0);
    string hyper_text;
    StringConcatenate(hyper_text, trades_today, " / ", g_profile.hyperactivity_trades_per_day);
    UpdateRow(7, hyper_pct, 100.0, hyper_text,
              ComputeRangeStatus(hyper_pct, 100.0, 0.75, 1.00),
              true);

    // 8: News Window - V1.29 (Coordinator) : the bar FILLS over the hour BEFORE the
    // event, stays ACTIVE through the +/-window (broker rule, e.g. FundedNext +/-5 min),
    // then goes idle. HIGH + MEDIUM (per the level toggles).
    const bool news_applies = g_profile.news_rule_applies;
    const datetime news_evt = Live_NextNewsEvt();
    double news_pct = 0.0; bool news_active = false; int news_mins = 0;
    if (news_evt > 0) {
        const int      nwin = (g_profile.news_window_minutes > 0 ? g_profile.news_window_minutes : 5) * 60;
        const datetime nnow = TimeCurrent();
        const datetime nws  = news_evt - nwin;   // window start
        const datetime nwe  = news_evt + nwin;   // window end
        const int      napp = 3600 - nwin;       // approach span (the hour before the window)
        if (nnow >= nws && nnow <= nwe) { news_active = true; news_pct = 100.0; }
        else if (napp > 0 && nnow < nws && nnow >= news_evt - 3600) {
            news_pct  = 100.0 * (double)(nnow - (news_evt - 3600)) / (double)napp;
            news_mins = (int)((nws - nnow) / 60) + 1;
        }
    }
    string news_text;
    if (!news_applies)
        news_text = "N/A (challenge)";
    else if (news_active)
        news_text = "ACTIVE  eligible " + DoubleToString(g_profile.news_profit_share_pct, 0) + "%"; // FN : a news-window trade keeps only 40 % of profit
    else if (news_pct > 0.0)
        news_text = "in " + IntegerToString(news_mins) + "m";
    else
        news_text = "Inactive";
    UpdateRow(8,
              news_pct,
              100.0,
              news_text,
              !news_applies ? RC_STATUS_NA
                            : ((news_active || news_pct > 0.0) ? RC_STATUS_WARN : RC_STATUS_OK),
              news_applies);

    // 9: Server messages today (orders touched - placed/modified/cancelled/filled)
    const int orders_today = Live_OrdersToday();
    const int msgs_cap = g_profile.hyperactivity_msgs_per_day;
    const double msgs_pct = (msgs_cap > 0 ? 100.0 * orders_today / msgs_cap : 0.0);
    string msgs_text;
    StringConcatenate(msgs_text, orders_today, " / ", msgs_cap);
    UpdateRow(9, msgs_pct, 100.0, msgs_text,
              ComputeRangeStatus(msgs_pct, 100.0, 0.75, 1.00),
              true);

    // 10: News-Trading stats (V1.24 G2) - text-only row mirroring FundedNext's
    // "News Trading" card : # trades opened in a news window + their total P&L +
    // the 40%-eligible profit. Bounded ~30-day scan for the chart symbol, cached.
    ComputeNewsStats();
    string newsstats_text;
    if (!news_applies)
        newsstats_text = "N/A";
    else
        StringConcatenate(newsstats_text,
                          g_news_trades, "t  P&L ", (g_news_pnl >= 0 ? "+$" : "-$"),
                          DoubleToString(MathAbs(g_news_pnl), 2),
                          "  elig ", DoubleToString(g_profile.news_profit_share_pct, 0), "% ",
                          (g_news_eligible >= 0 ? "+$" : "-$"), DoubleToString(MathAbs(g_news_eligible), 2));
    UpdateRow(10, 0.0, 0.0, newsstats_text, RC_STATUS_NA, news_applies);
    } // V1.29 J : end risk-tools gate (rule-set values/rows/bars/alerts)

    RefreshPositionsList(); // basic info : ALWAYS
    RefreshAccountStrip();  // basic info : ALWAYS
    RefreshFooterMetrics(); // V1.29 N : ALWAYS - keeps the 2 footer info lines ; it gates the lot/budget/copy parts internally on g_eff_risktools
    // Always refresh SL/TP recommendation lines AFTER positions so the
    // "SL>REC" chip override stays in sync with current SL state, not just
    // on position add/remove. (Internally a no-op when risk-tools are OFF.)
    RefreshSlLines();
    if (PositionListChanged())
        SnapshotPositionList();
    // V1.24 : soft TILT banner LAST (after the strip is drawn) so it sits on top
    // of the account strip. Hard locks are handled at the TOP of RefreshPanel.
    if (g_eff_risktools)
        DrawTiltBanner();
}

//+------------------------------------------------------------------+
//| UpdateRow - mutate g_rows[idx] then re-render that row in-place   |
//+------------------------------------------------------------------+
void UpdateRow(int idx, double pct, double max_pct, const string value_text,
               ENUM_RC_STATUS status, bool applies) {
    g_rows[idx].value_pct = pct;
    g_rows[idx].max_pct = max_pct;
    g_rows[idx].value_text = value_text;
    g_rows[idx].status = status;
    g_rows[idx].applies = applies;

    TryFireSoundAlert(idx, applies ? status : RC_STATUS_NA);

    const string id = RC_PREFIX + g_rows[idx].key;
    ObjectSetString(0, id + "_val_lbl", OBJPROP_TEXT, " "); // legacy id no-op
    ObjectSetString(0, id + "_val", OBJPROP_TEXT, value_text);
    ObjectSetInteger(0, id + "_val", OBJPROP_COLOR, applies ? g_theme.text : g_theme.text_dim);

    // 1.1 : the "Max lot allowed" row (rule_margin_pt) is text-only in the
    // indicator -> skip bar + chip re-draw (kept for the future Helper-EA).
    if (g_rows[idx].key != "rule_margin_pt" && g_rows[idx].key != "rule_newsstats") {
        // Re-draw progress bar (re-create fill)
        ObjectsDeleteAll(0, id + "_bar");
        const int x = g_anchor_x, w = InpPanelWidth; // B2 : live anchor
        const int bar_x = x + 360; // P6/P4 : matches DrawRuleRow widened column
        const int bar_y = (int)ObjectGetInteger(0, id + "_lbl", OBJPROP_YDISTANCE) + 1;
        const int bar_w = w - 360 - 80 - RC_PAD;
        const int bar_h = InpRowHeight - 10;
        if (applies)
            DrawProgressBar(id + "_bar", bar_x, bar_y, bar_w, bar_h, pct, max_pct, status);
        else
            DrawRect(id + "_bar_empty", bar_x, bar_y, bar_w, bar_h, g_theme.bar_bg, g_theme.bar_bg, 0);

        // Re-draw chip
        ObjectsDeleteAll(0, id + "_chip");
        const int chip_x = x + w - 70;
        const int chip_y = bar_y - 2;
        DrawStatusChip(id + "_chip", chip_x, chip_y, 60, InpRowHeight - 6, applies ? status : RC_STATUS_NA);
    }
}

//+------------------------------------------------------------------+
//| Status helpers                                                   |
//+------------------------------------------------------------------+
ENUM_RC_STATUS ComputeRangeStatus(double v, double max_v, double warn_ratio, double red_ratio) {
    if (max_v <= 0.0)
        return RC_STATUS_NA;
    const double r = v / max_v;
    if (r >= red_ratio)
        return RC_STATUS_RED;
    if (r >= warn_ratio)
        return RC_STATUS_WARN;
    return RC_STATUS_OK;
}

ENUM_RC_STATUS ComputeBandStatus(double v, double lo, double hi) {
    // Per-trade margin recommendation: stay WITHIN [lo, hi]. Below = OK (under-leveraged).
    // Above hi = WARN. Way above (gambling territory > 70 % cumulative handled by row 0) = RED.
    if (v <= 0.0)
        return RC_STATUS_NA;
    if (v <= hi)
        return RC_STATUS_OK;
    if (v <= hi * 1.5)
        return RC_STATUS_WARN;
    return RC_STATUS_RED;
}

string StatusLabel(ENUM_RC_STATUS s) {
    switch (s) {
    case RC_STATUS_OK:
        return Tr("chip_ok");
    case RC_STATUS_WARN:
        return Tr("chip_warn");
    case RC_STATUS_RED:
        return Tr("chip_red");
    }
    return Tr("chip_na");
}

color StatusColor(ENUM_RC_STATUS s) {
    switch (s) {
    case RC_STATUS_OK:
        return g_theme.ok;
    case RC_STATUS_WARN:
        return g_theme.warn;
    case RC_STATUS_RED:
        return g_theme.red;
    }
    return g_theme.bar_bg;
}

//+------------------------------------------------------------------+
//| Position list refresh - live PositionGet* readings               |
//+------------------------------------------------------------------+
void RefreshPositionsList(void) {
    const int n = PositionsTotal();
    for (int i = 0; i < RC_MAX_POSITIONS; ++i) {
        const string id = RC_PREFIX + "pos_" + IntegerToString(i);

        if (i >= n || !PositionSelectByTicket(PositionGetTicket(i))) {
            // Empty slot - clear text AND reset all colors to panel-bg so
            // a previously red/green row doesn't ghost after a close.
            ObjectSetString(0, id + "_lbl", OBJPROP_TEXT, " ");
            ObjectSetInteger(0, id + "_lbl", OBJPROP_COLOR, g_theme.text_dim);
            ObjectSetString(0, id + "_pnl", OBJPROP_TEXT, " ");
            ObjectSetInteger(0, id + "_pnl", OBJPROP_COLOR, g_theme.text_dim);
            ObjectSetString(0, id + "_age", OBJPROP_TEXT, " ");
            ObjectSetInteger(0, id + "_age", OBJPROP_COLOR, g_theme.text_dim);
            ObjectSetInteger(0, id + "_chip_bg", OBJPROP_BGCOLOR, g_theme.surface);
            ObjectSetInteger(0, id + "_chip_bg", OBJPROP_COLOR, g_theme.surface);
            ObjectSetString(0, id + "_chip_txt", OBJPROP_TEXT, " ");
            ObjectSetInteger(0, id + "_chip_txt", OBJPROP_COLOR, g_theme.surface);
            g_pos_sym[i] = ""; // V1.27 : empty slot -> no click target
            ObjectSetString(0, RC_PREFIX + "pos_row_" + IntegerToString(i), OBJPROP_TEXT, " ");
            continue;
        }

        const string sym = PositionGetString(POSITION_SYMBOL);
        g_pos_sym[i] = sym; // V1.27 : remember this row's symbol for click-to-switch
        const int type = (int)PositionGetInteger(POSITION_TYPE);
        const double vol = PositionGetDouble(POSITION_VOLUME);
        const double pnl = PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
        const datetime open_time = (datetime)PositionGetInteger(POSITION_TIME);
        const double sl = PositionGetDouble(POSITION_SL);
        const int age = (int)(TimeCurrent() - open_time);
        const bool sl_miss = (sl <= 0.0);

        const string type_str = (type == POSITION_TYPE_BUY ? "BUY" : "SELL");
        const string sym_short = (StringLen(sym) > 8 ? StringSubstr(sym, 0, 8) : sym);

        string lbl;
        StringConcatenate(lbl, sym_short, " ", type_str, " ", DoubleToString(vol, VolDigits(sym))); // V1.28 : up to 4 dp
        ObjectSetString(0, id + "_lbl", OBJPROP_TEXT, lbl);
        ObjectSetInteger(0, id + "_lbl", OBJPROP_COLOR, g_theme.text);
        ObjectSetString(0, RC_PREFIX + "pos_row_" + IntegerToString(i), OBJPROP_TEXT, lbl); // V1.27 : button mirrors the symbol cell

        string pnl_str;
        StringConcatenate(pnl_str, (pnl >= 0.0 ? "+$" : "-$"), DoubleToString(MathAbs(pnl), 2));
        ObjectSetString(0, id + "_pnl", OBJPROP_TEXT, pnl_str);
        ObjectSetInteger(0, id + "_pnl", OBJPROP_COLOR, (pnl >= 0.0 ? g_theme.ok : g_theme.red));

        string age_str = FormatAge(age);
        color age_color = g_theme.text_dim;
        if (sl_miss && g_profile.mandatory_sl_minutes > 0) {
            const int deadline = g_profile.mandatory_sl_minutes * 60;
            const int remaining = deadline - age;
            if (remaining > 0) {
                age_str = age_str + "  SL " + IntegerToString(remaining) + "s";
                age_color = g_theme.warn; // amber - approaching the deadline
            } else {
                age_str = age_str + "  SL OVERDUE";
                age_color = g_theme.red; // red - 3-min rule breached
            }
        } else if (sl_miss) {
            age_str = age_str + "  no SL";
            age_color = g_theme.warn;
        }
        ObjectSetString(0, id + "_age", OBJPROP_TEXT, age_str);
        ObjectSetInteger(0, id + "_age", OBJPROP_COLOR, age_color);

        // Position status :
        //   - Locked while age < quick_strike_seconds (closing now creates QS trade)
        //   - WARN if SL missing and inside the 3-min grace
        //   - RED  if SL missing AND grace expired (and rule applies)
        //   - else OK
        ENUM_RC_STATUS pos_status = RC_STATUS_OK;
        if (age < g_profile.quick_strike_seconds)
            pos_status = RC_STATUS_RED;
        else if (sl_miss && g_profile.mandatory_sl_minutes > 0) {
            const int deadline = g_profile.mandatory_sl_minutes * 60;
            pos_status = (age < deadline ? RC_STATUS_WARN : RC_STATUS_RED);
        }

        const color chip_clr = StatusColor(pos_status);
        ObjectSetInteger(0, id + "_chip_bg", OBJPROP_BGCOLOR, chip_clr);
        ObjectSetInteger(0, id + "_chip_bg", OBJPROP_COLOR, chip_clr);
        ObjectSetString(0, id + "_chip_txt", OBJPROP_TEXT,
                        PositionStatusLabel(pos_status, age, sl_miss));
        ObjectSetInteger(0, id + "_chip_txt", OBJPROP_COLOR, g_theme.bg);
    }
}

//+------------------------------------------------------------------+
//| Account strip refresh (cycle countdown live)                     |
//+------------------------------------------------------------------+
void RefreshAccountStrip(void) {
    // FIX : Cycle / Payout countdown removed (too personal + required entering
    // dates). Always show the date-free min-trading-days counter.
    string right = "";
    {
        const int min_days = g_profile.min_trading_days;
        if (min_days <= 0)
            right = Tr("min_days_none");
        else {
            const int done = Live_TradingDaysCount();
            StringConcatenate(right, Tr("days_traded"), " ", done, "/", min_days,
                              (done >= min_days ? "  OK" : ""));
        }
    }
    ObjectSetString(0, RC_PREFIX + "strip_right", OBJPROP_TEXT, right);
}

//+------------------------------------------------------------------+
//| B5 : next HIGH-impact news + B4 : weekend-hold warning state      |
//+------------------------------------------------------------------+
datetime g_next_high_time = 0;     // server time of next news event (0 = none)
string   g_next_high_ccy  = "";
datetime g_next_high_scan = 0;     // last calendar scan timestamp
bool     g_next_high_isHigh = false; // V1.29 P : true if the next event is HIGH (else MEDIUM)
bool     g_weekend_warned = false; // weekend alert already fired this window

// B5 : time of the next HIGH-impact event (any currency) within 24h, 0 if none.
// V1.29 P/R : next HIGH **or** MEDIUM news (respecting the level toggles), and
// reports whether it is HIGH via out_high. (Name kept for minimal churn.)
datetime Live_NextHighImpactTime(string &out_ccy, bool &out_high) {
    out_ccy = "";
    out_high = false;
    const datetime now = TimeCurrent();
    MqlCalendarValue values[];
    if (CalendarValueHistory(values, now, now + 24 * 60 * 60, NULL, NULL) <= 0)
        return 0;
    datetime best = 0;
    for (int i = 0; i < ArraySize(values); ++i) {
        if (values[i].time <= now) continue;
        MqlCalendarEvent ev;
        if (!CalendarEventById(values[i].event_id, ev)) continue;
        const bool hi = (ev.importance == CALENDAR_IMPORTANCE_HIGH);
        const bool md = (ev.importance == CALENDAR_IMPORTANCE_MODERATE);
        if (!(hi && g_eff_news_high) && !(md && g_eff_news_med)) continue; // R : level filter
        if (best == 0 || values[i].time < best) {
            best = values[i].time;
            out_high = hi;
            MqlCalendarCountry c;
            if (CalendarCountryById(ev.country_id, c)) out_ccy = c.currency;
        }
    }
    return best;
}

// B4 : weekend-hold risk = weekend hold NOT allowed (funded) + Friday >= 22:00
// UTC + at least one open position.
bool IsWeekendHoldRisk(void) {
    if (g_profile.weekend_hold_allowed) return false;
    if (PositionsTotal() <= 0) return false;
    MqlDateTime g;
    TimeToStruct(TimeGMT(), g);
    return (g.day_of_week == 5 && g.hour >= 22);
}

void FireWeekendAlert(void) {
    if (g_weekend_warned) return;
    g_weekend_warned = true;
    if (g_eff_sound) PlaySound(InpSoundRed);
    if (g_eff_telegram)
        SendTelegramMessage("[RED] RiskCockpit - WEEKEND HOLD risk : Friday 22:00+ UTC with " +
                            IntegerToString(PositionsTotal()) +
                            " open position(s). Funded accounts must flatten before the weekend.");
}

//+------------------------------------------------------------------+
//| Live blinker for the title bar (substitute for popups)           |
//| Priority : weekend-hold warning (B4) > news countdown (B5) > LIVE |
//+------------------------------------------------------------------+
int g_blink_state = 0;
void UpdateClockBlinker(void) {
    g_blink_state = 1 - g_blink_state;
    const string cid = RC_PREFIX + "title_clock";

    // B4 : weekend-hold risk has top priority.
    if (IsWeekendHoldRisk()) {
        ObjectSetString(0, cid, OBJPROP_TEXT, (g_blink_state == 0 ? Tr("weekend_hold") : Tr("flatten")));
        ObjectSetInteger(0, cid, OBJPROP_COLOR, g_theme.red);
        FireWeekendAlert();
        return;
    }
    g_weekend_warned = false; // reset once out of the weekend window

    // B5 : next HIGH-impact news countdown (rescanned every 30 s, ticks down live).
    if (TimeCurrent() - g_next_high_scan >= 30) {
        g_next_high_scan = TimeCurrent();
        g_next_high_time = Live_NextHighImpactTime(g_next_high_ccy, g_next_high_isHigh);
    }
    if (g_next_high_time > TimeCurrent() && g_next_high_ccy != "") {
        const int mn = (int)((g_next_high_time - TimeCurrent()) / 60);
        if (mn <= 60) { // V1.29 P : counter starts only 1h before (was 120) ; includes MEDIUM
            const string lvl = (g_next_high_isHigh ? "HIGH" : "MED");
            ObjectSetString(0, cid, OBJPROP_TEXT, lvl + " " + g_next_high_ccy + " " + IntegerToString(mn) + "m");
            ObjectSetInteger(0, cid, OBJPROP_COLOR, (g_next_high_isHigh ? g_theme.red : g_theme.warn));
            return;
        }
    }
    // LOT 6 : default = single-glance verdict badge (ON TRACK / AT RISK /
    // VIOLATION) + safety score 0-100, computed from the live g_rows ratios.
    // Replaces the old static LIVE blinker.
    VerdictResult v;
    ComputeVerdict(v);
    ObjectSetString(0, cid, OBJPROP_TEXT, v.text);
    ObjectSetInteger(0, cid, OBJPROP_COLOR, v.clr);
}

//+------------------------------------------------------------------+
//| LOT 6 : compute the headline verdict + safety score (0-100) from  |
//| the live rule meters in g_rows. Score = 100 * (1 - max_ratio),    |
//| max_ratio = the worst used/cap across all applicable risk rules.  |
//| The profit-target row is excluded (it's a goal, not a risk).      |
//+------------------------------------------------------------------+
void ComputeVerdict(VerdictResult &out) {
    double max_ratio = 0.0;
    for (int i = 0; i < RC_RULE_COUNT; ++i) {
        if (!g_rows[i].applies)              continue;
        if (g_rows[i].max_pct <= 0.0)        continue;
        if (g_rows[i].key == "rule_target")  continue; // goal, not risk
        const double r = g_rows[i].value_pct / g_rows[i].max_pct;
        if (r > max_ratio) max_ratio = r;
    }
    int score = (int)MathRound(100.0 * (1.0 - max_ratio));
    if (score < 0)   score = 0;
    if (score > 100) score = 100;
    out.score = score;
    if (max_ratio >= 1.0) {
        out.text = Tr("v_violation") + " " + IntegerToString(score);
        out.clr  = g_theme.red;
    } else if (max_ratio >= 0.80) {
        out.text = Tr("v_atrisk") + " " + IntegerToString(score);
        out.clr  = g_theme.warn;
    } else {
        out.text = Tr("v_ontrack") + " " + IntegerToString(score);
        out.clr  = g_theme.ok;
    }
}

//+------------------------------------------------------------------+
//| LOT 6 : persist UI prefs (language + BE toggle) via MT5            |
//| GlobalVariable so they survive re-attach / chart change / VPS.    |
//+------------------------------------------------------------------+
void PersistLang(void) { GlobalVariableSet("RC_lang",        (double)g_lang); }
void PersistBE(void)   { GlobalVariableSet("RC_be_visible",  g_be_visible ? 1.0 : 0.0); }

//+------------------------------------------------------------------+
//| FIX 6 (V1.0.2) : comfort vertical scale - keep ~7% padding above  |
//| and below the visible candles so they are never glued to the edge |
//| (native auto-scale, and a double-click on the price scale, leave  |
//| zero margin). Same mechanism as ProSessionBox (CHART_SCALEFIX +   |
//| CHART_FIXED_MIN/MAX). It only ACTS when the chart is in native    |
//| auto-scale (the glued state, incl. right after a double-click) or |
//| when OUR padded band is breached by new price ; it NEVER overrides|
//| a manual zoom (a fixed scale we did not set). force = attach /    |
//| symbol-switch (re)apply. Restored to auto-scale in OnDeinit.      |
//+------------------------------------------------------------------+
void ApplyComfortScale(bool force) {
    if (!g_eff_comfort)
        return;

    const int total = Bars(_Symbol, PERIOD_CURRENT);
    if (total < 2)
        return;

    // Visible-window high / low from the bar series.
    int first = (int)ChartGetInteger(0, CHART_FIRST_VISIBLE_BAR);
    int vis   = (int)ChartGetInteger(0, CHART_VISIBLE_BARS);
    if (vis < 1) vis = 1;
    int start = first - vis + 1;
    if (start < 0) start = 0;
    int count = first - start + 1;
    if (count < 1) count = 1;
    if (count > total) count = total;

    const int hi_idx = iHighest(_Symbol, PERIOD_CURRENT, MODE_HIGH, count, start);
    const int lo_idx = iLowest(_Symbol, PERIOD_CURRENT, MODE_LOW, count, start);
    if (hi_idx < 0 || lo_idx < 0)
        return;
    const double hi = iHigh(_Symbol, PERIOD_CURRENT, hi_idx);
    const double lo = iLow(_Symbol, PERIOD_CURRENT, lo_idx);
    const double range = hi - lo;
    if (range <= 0.0)
        return;

    double mpct = g_eff_comfort_pct;         // user-tunable (default 15%)
    if (mpct < 1.0)  mpct = 1.0;             // guard against degenerate / zero padding
    if (mpct > 50.0) mpct = 50.0;
    const double margin  = range * (mpct / 100.0); // comfort padding top & bottom
    const double new_min = lo - margin;
    const double new_max = hi + margin;

    if (!force && (bool)ChartGetInteger(0, CHART_SCALEFIX)) {
        // The chart is on a FIXED scale : either the one WE set, or a manual zoom.
        const double cur_min = ChartGetDouble(0, CHART_FIXED_MIN);
        const double cur_max = ChartGetDouble(0, CHART_FIXED_MAX);
        const double tol = range * 1e-3;
        const bool ours = (MathAbs(cur_min - g_cs_min) <= tol &&
                           MathAbs(cur_max - g_cs_max) <= tol);
        if (!ours)
            return; // user's manual zoom -> respect it, never fight
        // Ours : leave it unless the candles drifted too close to an edge (< half the
        // margin = nearly glued) or too far (> 2.5x = wasted space). Keeps a quiet
        // chart stable (no per-tick reset) while still following real price moves.
        const double top_gap = cur_max - hi;
        const double bot_gap = lo - cur_min;
        const bool comfy = (top_gap >= margin * 0.5 && top_gap <= margin * 2.5 &&
                            bot_gap >= margin * 0.5 && bot_gap <= margin * 2.5);
        if (comfy)
            return;
    }
    // force, OR native/glued (SCALEFIX false), OR our band breached -> (re)pad.
    ChartSetInteger(0, CHART_SCALEFIX, true);
    ChartSetDouble(0, CHART_FIXED_MIN, new_min);
    ChartSetDouble(0, CHART_FIXED_MAX, new_max);
    g_cs_min = new_min;
    g_cs_max = new_max;
}

//+------------------------------------------------------------------+
//| LOT D B-RESIZE-ALL : apply the padded scale to ONE specific chart |
//| (helper called by ApplyComfortScaleAllCharts on user-explicit     |
//| Re-center). Always force, no manual-zoom detection : we only run  |
//| this on a user gesture so over-riding any zoom is acceptable.     |
//| Updates g_cs_min/max only for chart 0 (the active one we track).  |
//+------------------------------------------------------------------+
void ApplyComfortScaleToChart(long chart_id, const string sym) {
    // AUDIT 2026-06-07 fix #2 : background charts may be on a different
    // timeframe than the active one. Reading bars at PERIOD_CURRENT here
    // would pull the active TF's high/low and pad the target chart too
    // tight (JR confirmed). Use the target chart's own TF.
    const ENUM_TIMEFRAMES tf = (ENUM_TIMEFRAMES)ChartPeriod(chart_id);
    const int total = Bars(sym, tf);
    if (total < 2) return;
    int first = (int)ChartGetInteger(chart_id, CHART_FIRST_VISIBLE_BAR);
    int vis   = (int)ChartGetInteger(chart_id, CHART_VISIBLE_BARS);
    if (vis < 1) vis = 1;
    int start = first - vis + 1;
    if (start < 0) start = 0;
    int count = first - start + 1;
    if (count < 1) count = 1;
    if (count > total) count = total;
    const int hi_idx = iHighest(sym, tf, MODE_HIGH, count, start);
    const int lo_idx = iLowest(sym, tf, MODE_LOW, count, start);
    if (hi_idx < 0 || lo_idx < 0) return;
    const double hi = iHigh(sym, tf, hi_idx);
    const double lo = iLow(sym, tf, lo_idx);
    const double range = hi - lo;
    if (range <= 0.0) return;
    double mpct = g_eff_comfort_pct;
    if (mpct < 1.0)  mpct = 1.0;
    if (mpct > 50.0) mpct = 50.0;
    const double margin = range * (mpct / 100.0);
    ChartSetInteger(chart_id, CHART_SCALEFIX, true);
    ChartSetDouble(chart_id, CHART_FIXED_MIN, lo - margin);
    ChartSetDouble(chart_id, CHART_FIXED_MAX, hi + margin);
    if (chart_id == 0) { // track for the OnTimer "ours" detection
        g_cs_min = lo - margin;
        g_cs_max = hi + margin;
    }
}

//+------------------------------------------------------------------+
//| LOT D B-RESIZE-ALL : explicit Re-center broadcasts to EVERY open  |
//| chart (not just the active one). Called from the "Re-center"      |
//| button click. OnTimer still operates on chart 0 only - we never   |
//| fight manual zoom on background charts on every timer tick.       |
//+------------------------------------------------------------------+
void ApplyComfortScaleAllCharts(void) {
    if (!g_eff_comfort) return;
    long cid = ChartFirst();
    while (cid >= 0) {
        const string sym = ChartSymbol(cid);
        if (sym != "") ApplyComfortScaleToChart(cid, sym);
        cid = ChartNext(cid);
    }
}

//+------------------------------------------------------------------+
//| Formatting helpers                                               |
//+------------------------------------------------------------------+
string FormatMoney(double v) {
    return "$" + DoubleToString(v, 2);
}

string FormatPct(double v) {
    return DoubleToString(v, 2) + "%"; // P4 : 2 decimals on the rule meters too
}

//+------------------------------------------------------------------+
//| ISO date diff (returns days B - A; 0 on parse error)             |
//+------------------------------------------------------------------+
int DaysBetweenIso(const string iso_a, const string iso_b) {
    string a_norm = iso_a;
    string b_norm = iso_b;
    StringReplace(a_norm, "-", ".");
    StringReplace(b_norm, "-", ".");
    const datetime a = StringToTime(a_norm);
    const datetime b = StringToTime(b_norm);
    if (a == 0 || b == 0)
        return 0;
    return (int)((b - a) / 86400);
}

//+------------------------------------------------------------------+
//| V1.27 : cycle-date <-> YYYYMMDD double (GlobalVariable is double  |
//| only, so the editable cycle start is stored as e.g. 20260509.0). |
//+------------------------------------------------------------------+
double IsoToYmd(const string iso) {
    string norm = iso;
    StringReplace(norm, "-", ".");
    const datetime t = StringToTime(norm);
    if (t == 0) return 0.0;
    MqlDateTime dt;
    TimeToStruct(t, dt);
    return (double)(dt.year * 10000 + dt.mon * 100 + dt.day);
}
string YmdToIso(const double ymd) {
    const int v = (int)ymd;
    return StringFormat("%04d-%02d-%02d", v / 10000, (v / 100) % 100, v % 100);
}

//+------------------------------------------------------------------+
//| Drawing primitives                                               |
//|                                                                  |
//| LOT B (B-LAYER-FIX + B-MULTI-IND) z-order convention :            |
//|  - background rectangles (panel bg, row bg, chip bg, bar bg) ->   |
//|    OBJPROP_ZORDER = 10 (set by DrawRect default below).           |
//|  - click targets (OBJ_BUTTON, the mp_* rectangle "buttons" + their|
//|    overlay text labels) -> OBJPROP_ZORDER = 100 (set explicitly   |
//|    per button creation site).                                     |
//| Rationale : foreign objects (HLine drag-grips, other indicators'  |
//| sub-panels) default to ZORDER=0. Forcing 100 on our click targets |
//| wins the CHARTEVENT_OBJECT_CLICK routing so the user does NOT     |
//| need to drag the panel away to interact. Per spec from F:\...\    |
//| external\riskcockpit_v120\zorder_hittest_spec.md                  |
//+------------------------------------------------------------------+
void DrawRect(const string id, int x, int y, int w, int h, color bg, color border, int width) {
    if (ObjectFind(0, id) < 0)
        ObjectCreate(0, id, OBJ_RECTANGLE_LABEL, 0, 0, 0);
    ObjectSetInteger(0, id, OBJPROP_XDISTANCE, x);
    ObjectSetInteger(0, id, OBJPROP_YDISTANCE, y);
    ObjectSetInteger(0, id, OBJPROP_XSIZE, w);
    ObjectSetInteger(0, id, OBJPROP_YSIZE, h);
    ObjectSetInteger(0, id, OBJPROP_BGCOLOR, bg);
    ObjectSetInteger(0, id, OBJPROP_COLOR, border);
    ObjectSetInteger(0, id, OBJPROP_WIDTH, width);
    ObjectSetInteger(0, id, OBJPROP_BORDER_TYPE, BORDER_FLAT);
    ObjectSetInteger(0, id, OBJPROP_CORNER, CORNER_LEFT_UPPER);
    ObjectSetInteger(0, id, OBJPROP_BACK, false);
    ObjectSetInteger(0, id, OBJPROP_SELECTABLE, false);
    ObjectSetInteger(0, id, OBJPROP_HIDDEN, true);
    ObjectSetInteger(0, id, OBJPROP_ZORDER, 10);   // LOT B : panel bg layer
}

void DrawLabel(const string id, int x, int y, const string text, color clr, int font_size, const string font) {
    if (ObjectFind(0, id) < 0)
        ObjectCreate(0, id, OBJ_LABEL, 0, 0, 0);
    ObjectSetInteger(0, id, OBJPROP_XDISTANCE, x);
    ObjectSetInteger(0, id, OBJPROP_YDISTANCE, y);
    // MT5 quirk: an OBJ_LABEL with truly empty text reverts to displaying
    // the literal word "Label". Substitute a single space so the slot stays
    // visually empty without that default fallback.
    ObjectSetString(0, id, OBJPROP_TEXT, (text == "" ? " " : text));
    ObjectSetInteger(0, id, OBJPROP_COLOR, clr);
    ObjectSetString(0, id, OBJPROP_FONT, font);
    ObjectSetInteger(0, id, OBJPROP_FONTSIZE, font_size);
    ObjectSetInteger(0, id, OBJPROP_CORNER, CORNER_LEFT_UPPER);
    ObjectSetInteger(0, id, OBJPROP_ANCHOR, ANCHOR_LEFT_UPPER);
    ObjectSetInteger(0, id, OBJPROP_BACK, false);
    ObjectSetInteger(0, id, OBJPROP_SELECTABLE, false);
    ObjectSetInteger(0, id, OBJPROP_HIDDEN, true);
}

//+------------------------------------------------------------------+
//| Live computations (T7)                                           |
//+------------------------------------------------------------------+
double Live_CumulativeMarginPct(void) {
    // FIX (LOT 2) : per FundedNext, margin % is calculated on the INITIAL account
    // balance (help.fundednext 10816539 + 10816788), NOT the current balance.
    // More conservative + factually correct (= what FN scores you against).
    if (g_profile.initial_balance <= 0.0)
        return 0.0;
    const double margin = AccountInfoDouble(ACCOUNT_MARGIN);
    return 100.0 * margin / g_profile.initial_balance;
}

double Live_PerTradeMarginPct(void) {
    // FIX (LOT 2) : same as cumulative - margin % is vs INITIAL balance (FN rule).
    if (g_profile.initial_balance <= 0.0)
        return 0.0;
    double max_pct = 0.0;
    const int n = PositionsTotal();
    for (int i = 0; i < n; ++i) {
        const ulong ticket = PositionGetTicket(i);
        if (ticket == 0 || !PositionSelectByTicket(ticket))
            continue;
        const string sym = PositionGetString(POSITION_SYMBOL);
        const double vol = PositionGetDouble(POSITION_VOLUME);
        const int type = (int)PositionGetInteger(POSITION_TYPE);
        const double price = PositionGetDouble(POSITION_PRICE_OPEN);
        double margin = 0.0;
        const ENUM_ORDER_TYPE ot = (type == POSITION_TYPE_BUY) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
        if (!OrderCalcMargin(ot, sym, vol, price, margin))
            continue;
        const double pct = 100.0 * margin / g_profile.initial_balance;
        if (pct > max_pct)
            max_pct = pct;
    }
    return max_pct;
}

double Live_CumulativeRiskPct(void) {
    if (g_profile.initial_balance <= 0.0)
        return 0.0;
    double total_risk_money = 0.0;
    bool any_missing_sl = false;
    const int n = PositionsTotal();
    for (int i = 0; i < n; ++i) {
        const ulong ticket = PositionGetTicket(i);
        if (ticket == 0 || !PositionSelectByTicket(ticket))
            continue;
        const double sl = PositionGetDouble(POSITION_SL);
        if (sl <= 0.0) {
            // Per FundedNext: SL not placed within 3 min -> FULL ACCOUNT BALANCE at risk
            any_missing_sl = true;
            continue;
        }
        const string sym = PositionGetString(POSITION_SYMBOL);
        const double po = PositionGetDouble(POSITION_PRICE_OPEN);
        const double vol = PositionGetDouble(POSITION_VOLUME);
        const int type = (int)PositionGetInteger(POSITION_TYPE);
        total_risk_money += ComputePositionRiskMoney(sym, type, po, sl, vol);
    }
    if (any_missing_sl) {
        // Conservative: if any position is SL-less, the rule treats full
        // account balance as at-risk for that trade. Show 100 %+.
        return 100.0;
    }
    return 100.0 * total_risk_money / g_profile.initial_balance;
}

//+------------------------------------------------------------------+
//| FIX (LOT 2) : Live_LockedRiskPct = sum of risks at each open      |
//| position's INITIAL stop-loss, as % of INITIAL balance. This is    |
//| the value FundedNext scores against (their 3 % rule LOCKS to the  |
//| SL posed at OPENING - moving the SL afterward does NOT change it; |
//| email FundedNext 2026-05-29). The initial SL is the first non-zero|
//| SL we see per ticket ; we persist the mapping in g_initial_sls    |
//| and drop closed entries on the fly.                               |
//+------------------------------------------------------------------+
double Live_LockedRiskPct(void) {
    if (g_profile.initial_balance <= 0.0)
        return 0.0;
    double total_money = 0.0;
    const int n = PositionsTotal();
    for (int i = 0; i < n; ++i) {
        const ulong ticket = PositionGetTicket(i);
        if (ticket == 0 || !PositionSelectByTicket(ticket))
            continue;
        const double cur_sl = PositionGetDouble(POSITION_SL);
        // Look up or store the initial SL (first non-zero SL seen for this ticket).
        double initial_sl = 0.0;
        bool found = false;
        for (int j = 0; j < ArraySize(g_initial_sls); ++j) {
            if (g_initial_sls[j].ticket == ticket) {
                initial_sl = g_initial_sls[j].initial_sl;
                found = true;
                break;
            }
        }
        if (!found && cur_sl > 0.0) {
            const int sz = ArraySize(g_initial_sls);
            ArrayResize(g_initial_sls, sz + 1);
            g_initial_sls[sz].ticket     = ticket;
            g_initial_sls[sz].initial_sl = cur_sl;
            initial_sl = cur_sl;
        }
        if (initial_sl <= 0.0)
            continue; // SL never posed -> handled (as 100 %) by Live_CumulativeRiskPct
        const string sym = PositionGetString(POSITION_SYMBOL);
        const double po  = PositionGetDouble(POSITION_PRICE_OPEN);
        const double vol = PositionGetDouble(POSITION_VOLUME);
        const int    type = (int)PositionGetInteger(POSITION_TYPE);
        total_money += ComputePositionRiskMoney(sym, type, po, initial_sl, vol);
    }
    // Cleanup : drop entries for positions that no longer exist (closed/cancelled).
    for (int i = ArraySize(g_initial_sls) - 1; i >= 0; --i) {
        if (!PositionSelectByTicket(g_initial_sls[i].ticket)) {
            for (int k = i; k < ArraySize(g_initial_sls) - 1; ++k)
                g_initial_sls[k] = g_initial_sls[k + 1];
            ArrayResize(g_initial_sls, ArraySize(g_initial_sls) - 1);
        }
    }
    return 100.0 * total_money / g_profile.initial_balance;
}

double Live_DailyDdPct(void) {
    if (g_profile.initial_balance <= 0.0)
        return 0.0;
    // Reconstruct balance at server-day start from history -> robust to reinit
    // and symbol switches : balance_now - realised_pnl_today.
    // FIX (LOT 1) : routed through CachedRealisedToday (throttled 2 s) so we
    // do NOT run a full history scan every 500 ms timer tick from inside the
    // daily-DD meter. Floating part of the day's P&L is handled by ACCOUNT_EQUITY.
    const double realised_today      = CachedRealisedToday();
    const double balance_day_start   = AccountInfoDouble(ACCOUNT_BALANCE) - realised_today;
    const double cur_eq = AccountInfoDouble(ACCOUNT_EQUITY);
    const double dd = balance_day_start - cur_eq;
    if (dd <= 0.0)
        return 0.0;
    return 100.0 * dd / g_profile.initial_balance;
}

double Live_OverallDdPct(void) {
    UpdatePeakEquity();
    const double cur_eq = AccountInfoDouble(ACCOUNT_EQUITY);
    if (g_profile.max_loss_trailing) {
        if (g_peak_equity <= 0.0)
            return 0.0;
        const double dd = g_peak_equity - cur_eq;
        if (dd <= 0.0)
            return 0.0;
        return 100.0 * dd / g_peak_equity;
    }
    if (g_profile.initial_balance <= 0.0)
        return 0.0;
    const double dd = g_profile.initial_balance - cur_eq;
    if (dd <= 0.0)
        return 0.0;
    return 100.0 * dd / g_profile.initial_balance;
}

double Live_ProfitTargetPct(void) {
    if (g_profile.profit_target_pct <= 0.0)
        return 0.0;
    if (g_profile.initial_balance <= 0.0)
        return 0.0;
    const double cur_eq = AccountInfoDouble(ACCOUNT_EQUITY);
    const double profit = cur_eq - g_profile.initial_balance;
    if (profit <= 0.0)
        return 0.0;
    return 100.0 * profit / g_profile.initial_balance;
}

double Live_QuickStrikeRatioPct(void) {
    // FIX (LOT 2) : full HistoryDealsTotal + nested matching loop. QS ratio only
    // changes when a trade closes, throttle 5 s.
    if (g_qs_scan != 0 && TimeCurrent() - g_qs_scan < 5)
        return g_qs_cache;
    string cs = (g_eff_cycle_ymd > 0 ? YmdToIso(g_eff_cycle_ymd) : InpCycleStartIso); // V1.27 : editable cycle start
    StringReplace(cs, "-", ".");
    datetime from = StringToTime(cs);
    if (from == 0)
        from = TimeCurrent() - 30 * 86400;
    const datetime to = TimeCurrent();
    if (!HistorySelect(from, to))
        return 0.0;

    const int total = HistoryDealsTotal();
    double profit_sum = 0.0;
    double qs_sum = 0.0;
    for (int i = 0; i < total; ++i) {
        const ulong out_ticket = HistoryDealGetTicket(i);
        if (out_ticket == 0)
            continue;
        if ((ENUM_DEAL_ENTRY)HistoryDealGetInteger(out_ticket, DEAL_ENTRY) != DEAL_ENTRY_OUT)
            continue;
        const double pnl = HistoryDealGetDouble(out_ticket, DEAL_PROFIT) + HistoryDealGetDouble(out_ticket, DEAL_SWAP) + HistoryDealGetDouble(out_ticket, DEAL_COMMISSION);
        if (pnl <= 0.0)
            continue;

        const long pos_id = HistoryDealGetInteger(out_ticket, DEAL_POSITION_ID);
        const datetime out_t = (datetime)HistoryDealGetInteger(out_ticket, DEAL_TIME);
        datetime in_t = 0;
        for (int j = 0; j < total; ++j) {
            const ulong in_ticket = HistoryDealGetTicket(j);
            if (in_ticket == 0)
                continue;
            if ((ENUM_DEAL_ENTRY)HistoryDealGetInteger(in_ticket, DEAL_ENTRY) != DEAL_ENTRY_IN)
                continue;
            if (HistoryDealGetInteger(in_ticket, DEAL_POSITION_ID) == pos_id) {
                in_t = (datetime)HistoryDealGetInteger(in_ticket, DEAL_TIME);
                break;
            }
        }
        profit_sum += pnl;
        if (in_t != 0 && (int)(out_t - in_t) < g_profile.quick_strike_seconds)
            qs_sum += pnl;
    }
    if (profit_sum <= 0.0) {
        g_qs_cache = 0.0;
        g_qs_scan  = TimeCurrent();
        return 0.0;
    }
    g_qs_cache = 100.0 * qs_sum / profit_sum;
    g_qs_scan  = TimeCurrent();
    return g_qs_cache;
}

int Live_TradesToday(void) {
    MqlDateTime mdt;
    TimeToStruct(TimeCurrent(), mdt);
    mdt.hour = 0;
    mdt.min = 0;
    mdt.sec = 0;
    const datetime today_start = StructToTime(mdt);
    if (!HistorySelect(today_start, TimeCurrent()))
        return 0;
    int count = 0;
    const int n = HistoryDealsTotal();
    for (int i = 0; i < n; ++i) {
        const ulong t = HistoryDealGetTicket(i);
        if (t == 0)
            continue;
        if ((ENUM_DEAL_ENTRY)HistoryDealGetInteger(t, DEAL_ENTRY) == DEAL_ENTRY_IN)
            count++;
    }
    return count;
}

// Proxy for the FundedNext "server messages" counter: every order touched
// today (placed, modified, cancelled, filled) counts as one server interaction.
int Live_OrdersToday(void) {
    MqlDateTime mdt;
    TimeToStruct(TimeCurrent(), mdt);
    mdt.hour = 0;
    mdt.min = 0;
    mdt.sec = 0;
    const datetime today_start = StructToTime(mdt);
    if (!HistorySelect(today_start, TimeCurrent()))
        return 0;
    return HistoryOrdersTotal();
}

bool Live_InNewsWindow(void) {
    // MQL5 Calendar API. Requires the terminal to have Calendar access on the
    // selected market watch symbols. We check + windows of profile.news_window_minutes.
    if (!g_profile.news_rule_applies)
        return false;
    if (g_profile.news_window_minutes <= 0)
        return false;

    const int win_sec = g_profile.news_window_minutes * 60;
    const datetime t_from = TimeCurrent() - win_sec;
    const datetime t_to = TimeCurrent() + win_sec;

    MqlCalendarValue values[];
    if (!CalendarValueHistory(values, t_from, t_to, NULL, NULL))
        return false;

    const string base = SymbolInfoString(_Symbol, SYMBOL_CURRENCY_BASE);
    const string quote = SymbolInfoString(_Symbol, SYMBOL_CURRENCY_PROFIT);

    for (int i = 0; i < ArraySize(values); ++i) {
        MqlCalendarEvent ev;
        if (!CalendarEventById(values[i].event_id, ev))
            continue;
        // V1.29 (Coordinator) : treat MEDIUM like HIGH for the news-window rule meter
        // (FundedNext counts medium news too) ; respect the level toggles like the bars.
        const bool is_high = (ev.importance == CALENDAR_IMPORTANCE_HIGH);
        const bool is_med  = (ev.importance == CALENDAR_IMPORTANCE_MODERATE);
        if (!is_high && !is_med) continue;          // skip LOW only
        if (is_high && !g_eff_news_high) continue;
        if (is_med  && !g_eff_news_med)  continue;

        MqlCalendarCountry country;
        if (!CalendarCountryById(ev.country_id, country))
            continue;
        if (country.currency == base || country.currency == quote)
            return true;
    }
    return false;
}

// V1.29 (Coordinator) : nearest relevant news event (HIGH/MEDIUM per the level toggles,
// currency-matched) that we are APPROACHING (within the hour before) or INSIDE its
// window. Drives the news-row fill : ramp over the hour before, ACTIVE in the +/-window.
datetime Live_NextNewsEvt(void) {
    if (!g_profile.news_rule_applies)
        return 0;
    const int win_sec = (g_profile.news_window_minutes > 0 ? g_profile.news_window_minutes : 5) * 60;
    const datetime now = TimeCurrent();
    MqlCalendarValue values[];
    if (!CalendarValueHistory(values, now - win_sec, now + 3600 + win_sec, NULL, NULL))
        return 0;
    // V1.29 FN fix (BUG 1) : NO currency filter here - the "News window" row must
    // match the on-chart news VLINEs, which show ALL currencies. The old symbol
    // base/quote filter broke the row on indices (US30 : base/quote != the news
    // currencies shown) -> the row never filled/activated.
    datetime best = 0;
    for (int i = 0; i < ArraySize(values); ++i) {
        MqlCalendarEvent ev;
        if (!CalendarEventById(values[i].event_id, ev))
            continue;
        const bool is_high = (ev.importance == CALENDAR_IMPORTANCE_HIGH);
        const bool is_med  = (ev.importance == CALENDAR_IMPORTANCE_MODERATE);
        if (!is_high && !is_med) continue;
        if (is_high && !g_eff_news_high) continue;
        if (is_med  && !g_eff_news_med)  continue;
        const datetime te = values[i].time;
        if (now >= te - 3600 && now <= te + win_sec) {
            if (best == 0 || te < best) best = te;
        }
    }
    return best;
}

int Live_OpenPositionsCount(void) {
    return PositionsTotal();
}

//+------------------------------------------------------------------+
//| FN news relevance : does news in currency `ccy` affect `sym` ?    |
//| Official FundedNext mapping (help article 10701447) :             |
//|  - FX pairs : news currency = base or quote of the pair           |
//|  - Indices  : US30/NDX100/SPX500/US2000/USDX/USOIL -> USD ;       |
//|               GER30/FRA40/EUSTX50 -> EUR ; UK100/UKOIL -> GBP ;   |
//|               JPN225 -> JPY ; AUS200 -> AUD                       |
//|  - Metals   : XAUUSD -> USD + AUD + CAD ; XAGUSD -> USD           |
//|  - Crypto   : BTCUSD / ETHUSD -> USD                              |
//| Broker symbol names vary (JP225/JPN225, GER30/DE40...) -> match   |
//| on normalized name roots, after the plain currency-pair path.     |
//+------------------------------------------------------------------+
bool NewsCcyAffectsSymbol(const string sym, const string ccy) {
    // 1) currency-pair path : base / profit currency match (covers all FX)
    const string b = SymbolInfoString(sym, SYMBOL_CURRENCY_BASE);
    const string q = SymbolInfoString(sym, SYMBOL_CURRENCY_PROFIT);
    if ((b != "" && ccy == b) || (q != "" && ccy == q)) return true;
    // 2) index / commodity / crypto path : FN's official per-instrument table
    string s = sym; StringToUpper(s);
    bool usd = false, eur = false, gbp = false, jpy = false, aud = false, cad = false;
    if (StringFind(s, "JP225") >= 0 || StringFind(s, "JPN225") >= 0 || StringFind(s, "NIKKEI") >= 0) jpy = true;
    if (StringFind(s, "US30") >= 0 || StringFind(s, "DJ30") >= 0 || StringFind(s, "DOW") >= 0 ||
        StringFind(s, "NAS") >= 0 || StringFind(s, "NDX") >= 0 || StringFind(s, "USTEC") >= 0 || StringFind(s, "US100") >= 0 ||
        StringFind(s, "SPX") >= 0 || StringFind(s, "US500") >= 0 || StringFind(s, "SP500") >= 0 ||
        StringFind(s, "US2000") >= 0 || StringFind(s, "RUSSELL") >= 0 ||
        StringFind(s, "USDX") >= 0 || StringFind(s, "DXY") >= 0 ||
        StringFind(s, "USOIL") >= 0 || StringFind(s, "USOUSD") >= 0 || StringFind(s, "WTI") >= 0 ||
        StringFind(s, "BTC") >= 0 || StringFind(s, "ETH") >= 0) usd = true;
    if (StringFind(s, "GER") >= 0 || StringFind(s, "DE30") >= 0 || StringFind(s, "DE40") >= 0 || StringFind(s, "DAX") >= 0 ||
        StringFind(s, "FRA40") >= 0 || StringFind(s, "CAC") >= 0 ||
        StringFind(s, "EUSTX") >= 0 || StringFind(s, "STOXX") >= 0 || StringFind(s, "EU50") >= 0) eur = true;
    if (StringFind(s, "UK100") >= 0 || StringFind(s, "FTSE") >= 0 ||
        StringFind(s, "UKOIL") >= 0 || StringFind(s, "UKOUSD") >= 0 || StringFind(s, "BRENT") >= 0) gbp = true;
    if (StringFind(s, "AUS200") >= 0 || StringFind(s, "AU200") >= 0 || StringFind(s, "ASX") >= 0) aud = true;
    if (StringFind(s, "XAU") >= 0 || StringFind(s, "GOLD") >= 0) { usd = true; aud = true; cad = true; } // FN lists XAUUSD under USD + AUD + CAD
    if (StringFind(s, "XAG") >= 0 || StringFind(s, "SILVER") >= 0) usd = true;
    if (usd && ccy == "USD") return true;
    if (eur && ccy == "EUR") return true;
    if (gbp && ccy == "GBP") return true;
    if (jpy && ccy == "JPY") return true;
    if (aud && ccy == "AUD") return true;
    if (cad && ccy == "CAD") return true;
    return false;
}

//+------------------------------------------------------------------+
//| V1.24 G2 : News-Trading stats (mirror of FundedNext's card).      |
//| V1.30 final (FN-support-confirmed) : ACCOUNT-wide (any symbol,     |
//| like the FN dashboard) over the funded cycle (30-day perf cap) :   |
//| a position counts as a news-trade when ANY of its deals (entry OR  |
//| exit, incl. SL/TP) falls inside +/- news_window_minutes of a       |
//| HIGH/MEDIUM event mapped to the deal's instrument per FN's         |
//| official table (NewsCcyAffectsSymbol). Reports the WINNING ones    |
//| + their 40%-eligible profit (losses count 100%, not eligible).     |
//| FN's own calendar rates some red events (CB speeches...) that      |
//| MQL5 lists lower or not at all -> conservative ESTIMATE ; the FN   |
//| dashboard stays authoritative. Cached 60 s - the scan is heavy.    |
//+------------------------------------------------------------------+
int    g_news_stats_scan = 0;
int    g_news_trades     = 0;
double g_news_pnl        = 0.0;
double g_news_eligible   = 0.0;

void ComputeNewsStats(void) {
    if (g_news_stats_scan != 0 && TimeCurrent() - g_news_stats_scan < 60) return;
    g_news_stats_scan = (int)TimeCurrent(); // explicit cast (cache stamp) - clears datetime->int warning
    g_news_trades = 0; g_news_pnl = 0.0; g_news_eligible = 0.0;
    if (!g_profile.news_rule_applies || g_profile.news_window_minutes <= 0) return;
    const int win_sec   = g_profile.news_window_minutes * 60;
    const datetime now  = TimeCurrent();
    // V1.29 : scope the news-trade scan to the funded CYCLE (not a flat 30 days) so
    // trades from before the cycle / last payout reset are NOT counted - matches the
    // FundedNext "News Trading" card. 30 days stays as a hard perf cap.
    string cyc = (g_eff_cycle_ymd > 0 ? YmdToIso(g_eff_cycle_ymd) : InpCycleStartIso);
    StringReplace(cyc, "-", ".");
    const datetime cycle_start = StringToTime(cyc);
    datetime from = now - 30 * 86400;
    if (cycle_start > 0 && cycle_start > from) from = cycle_start;
    MqlCalendarValue cv[];
    if (CalendarValueHistory(cv, from - win_sec, now + win_sec, NULL, NULL) <= 0) return;
    // V1.30 FN-confirmed rule (support reply 2026-06-10) : the JP225 flags came
    // from "BOJ Gov Ueda Speaks" 11:30 server - a JPY red-folder event on FN's
    // OWN calendar - mapped per their published instrument table (JPN225<-JPY).
    // MQL5's calendar lists/rates some FN-red events (CB speeches...) lower or
    // not at all, so the card counts HIGH+MEDIUM events gated by the official
    // table : conservative estimate, FN dashboard authoritative. Keep EVERY
    // event (any level) with name/importance for the DIAG journal lines below.
    datetime evt[]; string evtccy[]; string evtname[]; int evtimp[]; int ne = 0;
    for (int i = 0; i < ArraySize(cv); ++i) {
        MqlCalendarEvent ev; if (!CalendarEventById(cv[i].event_id, ev)) continue;
        if (ev.importance == CALENDAR_IMPORTANCE_NONE) continue; // holidays etc.
        MqlCalendarCountry c; if (!CalendarCountryById(ev.country_id, c)) continue;
        ArrayResize(evt, ne + 1); ArrayResize(evtccy, ne + 1);
        ArrayResize(evtname, ne + 1); ArrayResize(evtimp, ne + 1);
        evt[ne] = cv[i].time; evtccy[ne] = c.currency;
        evtname[ne] = ev.name; evtimp[ne] = (int)ev.importance; ne++;
    }
    if (ne == 0) return;
    if (!HistorySelect(from, now)) return;
    const int n = HistoryDealsTotal();
    // pass 1 : position ids with ANY deal (entry OR exit, incl. SL/TP) inside a
    // relevant news window - FN flags trades OPENED or CLOSED in the window
    // (FN-confirmed : the JP225 2026-06-03 closes, 90 s after the 11:30 "BOJ
    // Gov Ueda Speaks" red event, were flagged while the opens sat outside).
    long posids[]; int npos = 0;
    string posinfo[]; // V1.30 diag : "SYM deal@time ~ evt@time CCY" per matched position (Experts journal)
    string diag[]; int ndiag = 0; // V1.30 diag : one line per deal<->event encounter, ANY importance
    for (int i = 0; i < n; ++i) {
        const ulong t = HistoryDealGetTicket(i); if (t == 0) continue;
        const long e = HistoryDealGetInteger(t, DEAL_ENTRY);
        if (e != DEAL_ENTRY_IN && e != DEAL_ENTRY_OUT && e != DEAL_ENTRY_INOUT) continue;
        const string dsym = HistoryDealGetString(t, DEAL_SYMBOL); if (dsym == "") continue;
        const datetime dt = (datetime)HistoryDealGetInteger(t, DEAL_TIME);
        bool innews = false; string minfo = "";
        for (int k = 0; k < ne; ++k) {
            if (MathAbs((long)dt - (long)evt[k]) > win_sec) continue;
            const bool lvl_ok = (evtimp[k] == (int)CALENDAR_IMPORTANCE_HIGH ||
                                 evtimp[k] == (int)CALENDAR_IMPORTANCE_MODERATE);
            const bool mapped = NewsCcyAffectsSymbol(dsym, evtccy[k]); // official FN instrument<->currency table
            const string impl = (evtimp[k] == (int)CALENDAR_IMPORTANCE_HIGH ? "HIGH" :
                                 (evtimp[k] == (int)CALENDAR_IMPORTANCE_MODERATE ? "MED" : "LOW"));
            ArrayResize(diag, ndiag + 1);
            diag[ndiag++] = dsym + " deal " + TimeToString(dt, TIME_DATE | TIME_SECONDS) +
                            " ~ evt " + TimeToString(evt[k], TIME_DATE | TIME_MINUTES) + " " + evtccy[k] +
                            " " + impl + " '" + evtname[k] + "' (FN-table " + (mapped ? "y" : "n") + ") -> " +
                            (lvl_ok && mapped ? "COUNTED" : (!mapped ? "skipped (not FN-mapped)" : "skipped (LOW)"));
            if (lvl_ok && mapped && !innews) { // count rule : HIGH/MED event mapped per the FN-confirmed table
                innews = true;
                minfo = dsym + " deal " + TimeToString(dt, TIME_DATE | TIME_SECONDS) +
                        " ~ evt " + TimeToString(evt[k], TIME_DATE | TIME_MINUTES) + " " + evtccy[k];
            }
        }
        if (!innews) continue;
        const long pid_in = HistoryDealGetInteger(t, DEAL_POSITION_ID);
        bool dup = false; // V1.29 : dedup (partial fills / multiple exits) -> one count per position
        for (int k = 0; k < npos; ++k) if (posids[k] == pid_in) { dup = true; break; }
        if (dup) continue;
        ArrayResize(posids, npos + 1); ArrayResize(posinfo, npos + 1);
        posinfo[npos] = minfo; posids[npos++] = pid_in;
    }
    // pass 2 : realised P&L per matched position (partials summed). Runs only
    // when something matched ; with npos == 0 the counters stay at 0 and the
    // DIAG block below still reports the deal<->event encounters.
    double pospnl[];
    int    win_n   = 0;
    double win_pnl = 0.0;
    if (npos > 0) {
        ArrayResize(pospnl, npos); ArrayInitialize(pospnl, 0.0);
        for (int i = 0; i < n; ++i) {
            const ulong t = HistoryDealGetTicket(i); if (t == 0) continue;
            const long e = HistoryDealGetInteger(t, DEAL_ENTRY);
            if (e != DEAL_ENTRY_OUT && e != DEAL_ENTRY_INOUT) continue;
            const long pid = HistoryDealGetInteger(t, DEAL_POSITION_ID);
            int idx = -1; for (int k = 0; k < npos; ++k) if (posids[k] == pid) { idx = k; break; }
            if (idx < 0) continue;
            pospnl[idx] += HistoryDealGetDouble(t, DEAL_PROFIT) + HistoryDealGetDouble(t, DEAL_SWAP) +
                           HistoryDealGetDouble(t, DEAL_COMMISSION);
        }
        // V1.29 FN fix (BUG 2) : the 40% news haircut applies ONLY to PROFITABLE
        // news-trades ; losing news-trades count 100% and are NOT part of
        // "eligible". Report the WINNING news-trades + their eligible share,
        // matching the FN dashboard.
        for (int k = 0; k < npos; ++k)
            if (pospnl[k] > 0.0) { win_n++; win_pnl += pospnl[k]; }
    }
    const double share = g_profile.news_profit_share_pct / 100.0; // 0.40
    g_news_trades   = win_n;           // winning news-trades only (matches FN card)
    g_news_pnl      = win_pnl;         // their summed P&L (>= 0)
    g_news_eligible = win_pnl * share; // 40% of winning P&L only (>= 0)
    // V1.30 diag : journal block whenever the scan result CHANGES (no spam) :
    // every deal<->event encounter (any importance, with event name + MQL5
    // level + FN-table relevance) plus the counted set -> any mismatch vs the
    // FN dashboard is diagnosable from the Experts journal alone.
    static double s_news_sig = -1.0;
    const double sig = ndiag * 100000000.0 + npos * 1000000.0 + win_n * 10000.0 + win_pnl;
    if (sig != s_news_sig) {
        s_news_sig = sig;
        PrintFormat("RC news-card : %d matched, %d winning, win-pnl %.2f, eligible %.2f (window +/-%d min, scan from %s, %d deal~event encounters)",
                    npos, win_n, win_pnl, g_news_eligible, g_profile.news_window_minutes, TimeToString(from, TIME_DATE), ndiag);
        for (int k = 0; k < ndiag; ++k)
            Print("RC news-scan : ", diag[k]);
        for (int k = 0; k < npos; ++k)
            PrintFormat("RC news-trade %d/%d : %s  pnl %.2f%s", k + 1, npos, posinfo[k], pospnl[k],
                        (pospnl[k] > 0.0 ? "" : "  (loss/flat -> not in the 40% card)"));
    }
}

//+------------------------------------------------------------------+
//| Position-list change detection (snapshot of tickets)             |
//+------------------------------------------------------------------+
bool PositionListChanged(void) {
    const int now = PositionsTotal();
    if (now != ArraySize(g_last_tickets))
        return true;
    for (int i = 0; i < now; ++i) {
        const ulong t = PositionGetTicket(i);
        if (t == 0 || t != g_last_tickets[i])
            return true;
    }
    return false;
}

void SnapshotPositionList(void) {
    const int now = PositionsTotal();
    ArrayResize(g_last_tickets, now);
    for (int i = 0; i < now; ++i)
        g_last_tickets[i] = PositionGetTicket(i);
}

//+------------------------------------------------------------------+
//| Dynamic recommended-SL lines on chart                            |
//|                                                                  |
//| For each open position on the CURRENT chart symbol, draw a       |
//| horizontal line at the price equivalent to budget_per_pos_pct    |
//| away from entry, where budget_per_pos_pct = 3 % / N_positions.   |
//| Lines for positions on other symbols are skipped (a future       |
//| multi-chart pane will surface them).                             |
//+------------------------------------------------------------------+
// TP scalping distance is now exposed as `InpTpPricePct` in the inputs.

void RefreshSlLines(void) {
    // Enumerate every open chart in the terminal and refresh recommendation
    // lines on each. This lets a single Helper instance manage positions on
    // multiple charts (per user spec : helper runs on one chart but covers
    // all of them).
    long cid = ChartFirst();
    while (cid >= 0) {
        RefreshSlLinesForChart(cid);
        cid = ChartNext(cid);
    }
}

void RefreshSlLinesForChart(const long chart_id) {
    // We delete and rebuild every visible recommendation each call. That
    // covers position closures, SL/TP being placed on existing positions,
    // and InpMaxParallelPositions changes from the panel.
    ObjectsDeleteAll(chart_id, "RC_SL_");
    ObjectsDeleteAll(chart_id, "RC_TP_");
    if (!g_eff_risktools) // V1.29 J : risk-tools OFF -> lines cleared above, draw none (covers all call-sites)
        return;
    if (g_profile.initial_balance <= 0.0)
        return;

    const int n = PositionsTotal();
    if (n <= 0)
        return;

    const string chart_sym = ChartSymbol(chart_id);
    if (chart_sym == "")
        return;

    // SL budget per trade (aligned with B9, 2026-05-21) :
    //   b% = min(EffectiveRiskCap% / N, InpMaxRiskPerTradePct%)
    // N = the planned-trades selector (g_max_parallel), NOT the current open
    // count -> the recommended SL reflects the user's intended split. Recomputed
    // when N changes (panel +/-) or a position opens/closes (OnTradeTransaction).
    // So : 1 trade -> b=1% -> wide SL ; 2 trades -> b=0.5% -> SL twice as tight.
    const int N = MathMax(1, g_max_parallel);
    const double budget_pct = MathMin(EffectiveRiskCap() / N, g_eff_max_risk_pt);
    const double budget_money = g_profile.initial_balance * budget_pct / 100.0;
    // Personal / no-prop profile : EffectiveRiskCap()=0 -> budget_money=0 ->
    // SL would degenerate to entry and every real SL flagged "OVER" red. Skip.
    if (budget_money <= 0.0)
        return;

    color palette[6];
    palette[0] = (color)0x0000AAFF; // amber
    palette[1] = (color)0x00FFAA00; // cyan-ish
    palette[2] = (color)0x00FF66FF; // pink
    palette[3] = (color)0x0066FFFF; // pastel
    palette[4] = (color)0x00FF9966; // peach
    palette[5] = (color)0x00C0FF40; // lime

    const color tp_clr = g_theme.ok;
    const ENUM_TIMEFRAMES tf = (ENUM_TIMEFRAMES)ChartPeriod(chart_id);
    const int period_seconds = PeriodSeconds(tf);
    // A2 : cap the SL/TP label offset at 4 h so it never lands far off-screen on
    // high timeframes (20 bars × period, but never more than 4 hours ahead).
    const datetime anchor_time = TimeCurrent() + (datetime)MathMin(20 * period_seconds, 4 * 3600);

    int drawn = 0;
    for (int i = 0; i < n; ++i) {
        const ulong ticket = PositionGetTicket(i);
        if (ticket == 0 || !PositionSelectByTicket(ticket))
            continue;
        const string sym = PositionGetString(POSITION_SYMBOL);
        if (sym != chart_sym)
            continue;

        const double entry = PositionGetDouble(POSITION_PRICE_OPEN);
        const double vol = PositionGetDouble(POSITION_VOLUME);
        const int type = (int)PositionGetInteger(POSITION_TYPE);
        const double existing_sl = PositionGetDouble(POSITION_SL);
        const double existing_tp = PositionGetDouble(POSITION_TP);

        const double tick_size = SymbolInfoDouble(sym, SYMBOL_TRADE_TICK_SIZE);
        const double tick_value = SymbolInfoDouble(sym, SYMBOL_TRADE_TICK_VALUE);
        if (tick_size <= 0.0 || tick_value <= 0.0 || vol <= 0.0)
            continue;

        const color line_clr = palette[drawn % 6];
        const string type_str = (type == POSITION_TYPE_BUY ? "BUY" : "SELL");

        // --- Recommended SL ---
        const double money_per_tick = tick_value * vol;
        if (money_per_tick > 0.0) {
            const double ticks = budget_money / money_per_tick;
            const double proposed_dist = ticks * tick_size;
            const double sl_price =
                (type == POSITION_TYPE_BUY ? entry - proposed_dist : entry + proposed_dist);

            const double user_dist = (existing_sl > 0.0 ? MathAbs(entry - existing_sl) : 0.0);
            const bool has_user_sl = (existing_sl > 0.0);
            const bool user_over_budget = (has_user_sl && user_dist > proposed_dist);
            const bool draw_line = (!has_user_sl || user_over_budget);

            if (draw_line) {
                const color final_line_clr = (user_over_budget ? g_theme.red : line_clr);
                const string status_suffix = (user_over_budget ? "  " + Tr("over") : "");

                const string line_id = "RC_SL_LINE_" + IntegerToString((int)ticket);
                ObjectCreate(chart_id, line_id, OBJ_HLINE, 0, 0, sl_price);
                ObjectSetDouble(chart_id, line_id, OBJPROP_PRICE, sl_price);
                ObjectSetInteger(chart_id, line_id, OBJPROP_COLOR, final_line_clr);
                ObjectSetInteger(chart_id, line_id, OBJPROP_STYLE, STYLE_DASHDOT);
                ObjectSetInteger(chart_id, line_id, OBJPROP_WIDTH, (user_over_budget ? 2 : 1));
                ObjectSetInteger(chart_id, line_id, OBJPROP_BACK, true);
                ObjectSetInteger(chart_id, line_id, OBJPROP_SELECTABLE, false);
                ObjectSetInteger(chart_id, line_id, OBJPROP_HIDDEN, true);
                ObjectSetString(chart_id, line_id, OBJPROP_TEXT,
                                Tr("sl_rec") + " " + DoubleToString(budget_pct, 2) +
                                    "% - " + sym + " " + type_str + " #" +
                                    IntegerToString((int)ticket) + status_suffix);

                const string txt_id = "RC_SL_TXT_" + IntegerToString((int)ticket);
                ObjectCreate(chart_id, txt_id, OBJ_TEXT, 0, anchor_time, sl_price);
                ObjectSetInteger(chart_id, txt_id, OBJPROP_TIME, anchor_time);
                ObjectSetDouble(chart_id, txt_id, OBJPROP_PRICE, sl_price);
                ObjectSetString(chart_id, txt_id, OBJPROP_TEXT,
                                "SL " + DoubleToString(budget_pct, 2) + "% rec  " +
                                    type_str + " " + DoubleToString(vol, 2) + "  #" +
                                    IntegerToString((int)ticket) + status_suffix);
                ObjectSetInteger(chart_id, txt_id, OBJPROP_COLOR, final_line_clr);
                ObjectSetInteger(chart_id, txt_id, OBJPROP_FONTSIZE, 8);
                ObjectSetString(chart_id, txt_id, OBJPROP_FONT, "Consolas");
                ObjectSetInteger(chart_id, txt_id, OBJPROP_ANCHOR, ANCHOR_LEFT);
                ObjectSetInteger(chart_id, txt_id, OBJPROP_BACK, false);
                ObjectSetInteger(chart_id, txt_id, OBJPROP_SELECTABLE, false);
                ObjectSetInteger(chart_id, txt_id, OBJPROP_HIDDEN, true);
            }

            // Panel-side chip override (HOST chart only).
            if (user_over_budget) {
                const string row_id = RC_PREFIX + "pos_" + IntegerToString(i);
                ObjectSetInteger(0, row_id + "_chip_bg", OBJPROP_BGCOLOR, g_theme.red);
                ObjectSetInteger(0, row_id + "_chip_bg", OBJPROP_COLOR, g_theme.red);
                ObjectSetString(0, row_id + "_chip_txt", OBJPROP_TEXT, Tr("sl_over_chip"));
            }
        }

        // --- Recommended TP : scalping default, skip if user placed one ---
        if (existing_tp <= 0.0) {
            const double tp_distance_price = entry * g_eff_tp_pct / 100.0;
            const double tp_price =
                (type == POSITION_TYPE_BUY ? entry + tp_distance_price : entry - tp_distance_price);

            const string tp_line_id = "RC_TP_LINE_" + IntegerToString((int)ticket);
            ObjectCreate(chart_id, tp_line_id, OBJ_HLINE, 0, 0, tp_price);
            ObjectSetDouble(chart_id, tp_line_id, OBJPROP_PRICE, tp_price);
            ObjectSetInteger(chart_id, tp_line_id, OBJPROP_COLOR, tp_clr);
            ObjectSetInteger(chart_id, tp_line_id, OBJPROP_STYLE, STYLE_DOT);
            ObjectSetInteger(chart_id, tp_line_id, OBJPROP_WIDTH, 1);
            ObjectSetInteger(chart_id, tp_line_id, OBJPROP_BACK, true);
            ObjectSetInteger(chart_id, tp_line_id, OBJPROP_SELECTABLE, false);
            ObjectSetInteger(chart_id, tp_line_id, OBJPROP_HIDDEN, true);
            ObjectSetString(chart_id, tp_line_id, OBJPROP_TEXT,
                            Tr("tp_rec") + " " + DoubleToString(g_eff_tp_pct, 2) +
                                "% - " + sym + " " + type_str + " #" +
                                IntegerToString((int)ticket));

            const string tp_txt_id = "RC_TP_TXT_" + IntegerToString((int)ticket);
            ObjectCreate(chart_id, tp_txt_id, OBJ_TEXT, 0, anchor_time, tp_price);
            ObjectSetInteger(chart_id, tp_txt_id, OBJPROP_TIME, anchor_time);
            ObjectSetDouble(chart_id, tp_txt_id, OBJPROP_PRICE, tp_price);
            ObjectSetString(chart_id, tp_txt_id, OBJPROP_TEXT,
                            "TP " + DoubleToString(g_eff_tp_pct, 2) + "%  " +
                                type_str + " " + DoubleToString(vol, 2) + "  #" +
                                IntegerToString((int)ticket));
            ObjectSetInteger(chart_id, tp_txt_id, OBJPROP_COLOR, tp_clr);
            ObjectSetInteger(chart_id, tp_txt_id, OBJPROP_FONTSIZE, 8);
            ObjectSetString(chart_id, tp_txt_id, OBJPROP_FONT, "Consolas");
            ObjectSetInteger(chart_id, tp_txt_id, OBJPROP_ANCHOR, ANCHOR_LEFT);
            ObjectSetInteger(chart_id, tp_txt_id, OBJPROP_BACK, false);
            ObjectSetInteger(chart_id, tp_txt_id, OBJPROP_SELECTABLE, false);
            ObjectSetInteger(chart_id, tp_txt_id, OBJPROP_HIDDEN, true);
        }

        drawn++;
    }
    ChartRedraw(chart_id);
}

//+------------------------------------------------------------------+
//| ComputePositionRiskMoney - balance lost if SL hits               |
//+------------------------------------------------------------------+
double ComputePositionRiskMoney(const string sym, const int type,
                                const double price_open, const double sl,
                                const double vol) {
    if (sl <= 0.0 || vol <= 0.0)
        return 0.0;
    const double tick_size = SymbolInfoDouble(sym, SYMBOL_TRADE_TICK_SIZE);
    const double tick_value = SymbolInfoDouble(sym, SYMBOL_TRADE_TICK_VALUE);
    if (tick_size <= 0.0 || tick_value <= 0.0)
        return 0.0;
    const double dist = MathAbs(price_open - sl);
    const double ticks = dist / tick_size;
    return ticks * tick_value * vol;
}

// A1 : UpdateDayStartEquity + g_equity_at_day_start removed (dead code - the
// daily-DD figure is reconstructed live via SumClosedDealsPnL, never from these).

void UpdatePeakEquity(void) {
    const double eq = AccountInfoDouble(ACCOUNT_EQUITY);
    if (eq > g_peak_equity)
        g_peak_equity = eq;
}

//+------------------------------------------------------------------+
//| Position-list formatting helpers                                 |
//+------------------------------------------------------------------+
string FormatAge(int seconds) {
    if (seconds < 0)
        seconds = 0;
    if (seconds < 60)
        return IntegerToString(seconds) + "s";
    if (seconds < 3600) {
        const int m = seconds / 60;
        const int s = seconds % 60;
        return IntegerToString(m) + "m" + IntegerToString(s) + "s";
    }
    const int h = seconds / 3600;
    const int m = (seconds % 3600) / 60;
    return IntegerToString(h) + "h" + IntegerToString(m) + "m";
}

string PositionStatusLabel(ENUM_RC_STATUS s, int age, bool sl_missing) {
    if (s == RC_STATUS_RED && age < g_profile.quick_strike_seconds)
        return Tr("pos_lock") + " " + IntegerToString(g_profile.quick_strike_seconds - age) + "s";
    if (s == RC_STATUS_RED && sl_missing)
        return Tr("pos_nosl");
    if (s == RC_STATUS_RED)
        return Tr("chip_red");
    if (s == RC_STATUS_WARN)
        return Tr("chip_warn");
    return Tr("chip_ok");
}

//+------------------------------------------------------------------+
//| Alert dispatcher on status transitions (sound + Telegram, B1)    |
//+------------------------------------------------------------------+
void TryFireSoundAlert(int idx, ENUM_RC_STATUS new_status) {
    if (idx < 0 || idx >= RC_RULE_COUNT)
        return;
    // FIX 3 (V1.0.1) : the Profit Target row is a PROGRESS meter - its amber/green
    // transitions are informational (you're doing well), never warnings. Cache the
    // status so the chip colour still updates, but never fire sound / Telegram.
    if (g_rows[idx].key == "rule_target") {
        g_last_status[idx] = new_status;
        return;
    }
    const ENUM_RC_STATUS prev = g_last_status[idx];
    g_last_status[idx] = new_status;
    if (!g_alerts_armed) // first refresh after OnInit / timeframe switch
        return;
    if (new_status == prev)
        return;

    // --- Sound (local) ---
    if (g_eff_sound) {
        if (new_status == RC_STATUS_WARN && prev != RC_STATUS_RED)
            PlaySound(InpSoundWarn);
        if (new_status == RC_STATUS_RED)
            PlaySound(InpSoundRed);
    }

    // --- Telegram (remote, rate-limited per rule) ---
    if (g_eff_telegram && (new_status == RC_STATUS_WARN || new_status == RC_STATUS_RED)) {
        const datetime now = TimeCurrent();
        if (now - g_last_telegram_alert[idx] >= RC_TELEGRAM_COOLDOWN_SEC) {
            g_last_telegram_alert[idx] = now;
            const string tag = (new_status == RC_STATUS_RED ? "[RED]" : "[WARN]");
            string msg;
            StringConcatenate(msg, tag, " RiskCockpit - ", g_rows[idx].label,
                              " : ", g_rows[idx].value_text,
                              "  (Acc #", AccountInfoInteger(ACCOUNT_LOGIN), ")");
            SendTelegramMessage(msg);
        }
    }
}

//+------------------------------------------------------------------+
//| Minimal JSON string escaper (handles \, ", \n, \r, \t)           |
//+------------------------------------------------------------------+
string EscapeJson(const string s) {
    string r = s;
    StringReplace(r, "\\", "\\\\");
    StringReplace(r, "\"", "\\\"");
    StringReplace(r, "\n", "\\n");
    StringReplace(r, "\r", "\\r");
    StringReplace(r, "\t", "\\t");
    return r;
}

//+------------------------------------------------------------------+
//| Send a Telegram bot message via WebRequest.                      |
//| Requires : Tools > Options > Expert Advisors > Allow WebRequest  |
//|   to include https://api.telegram.org                            |
//| Returns true on HTTP 2xx, false otherwise (token / URL / net).   |
//+------------------------------------------------------------------+
bool SendTelegramMessage(const string text) {
    if (!g_eff_telegram)
        return false;
    if (InpTelegramBotToken == "" || InpTelegramChatId == "")
        return false;

    const string url = "https://api.telegram.org/bot" + InpTelegramBotToken + "/sendMessage";
    string body;
    StringConcatenate(body,
                      "{\"chat_id\":\"", InpTelegramChatId,
                      "\",\"text\":\"", EscapeJson(text), "\"}");

    char post[], result[];
    string result_headers = "";
    const string headers = "Content-Type: application/json\r\n";

    const int body_len = StringLen(body);
    ArrayResize(post, body_len);
    StringToCharArray(body, post, 0, body_len, CP_UTF8);

    ResetLastError();
    const int res = WebRequest("POST", url, headers, 5000, post, result, result_headers);
    if (res == -1) {
        const int err = GetLastError();
        if (err == 4014) {
            Print("RiskCockpit : Telegram disabled - URL not whitelisted. ",
                  "Add 'https://api.telegram.org' in Tools > Options > Expert Advisors.");
        } else {
            Print("RiskCockpit : Telegram WebRequest failed err=", err);
        }
        return false;
    }
    return (res >= 200 && res < 300);
}

//+------------------------------------------------------------------+
//| Profit metrics                                                   |
//+------------------------------------------------------------------+
//+------------------------------------------------------------------+
//| Sum of closed-deal P&L (DEAL_PROFIT + SWAP + COMMISSION) over    |
//| a time range. Used by both Today/Total so numbers survive symbol |
//| changes and reinit (no in-memory baseline).                      |
//+------------------------------------------------------------------+
double SumClosedDealsPnL(const datetime from, const datetime to) {
    if (!HistorySelect(from, to))
        return 0.0;
    double sum = 0.0;
    const int n = HistoryDealsTotal();
    for (int i = 0; i < n; ++i) {
        const ulong t = HistoryDealGetTicket(i);
        if (t == 0)
            continue;
        const long entry = HistoryDealGetInteger(t, DEAL_ENTRY);
        if (entry != DEAL_ENTRY_OUT && entry != DEAL_ENTRY_INOUT)
            continue;
        sum += HistoryDealGetDouble(t, DEAL_PROFIT) + HistoryDealGetDouble(t, DEAL_SWAP) + HistoryDealGetDouble(t, DEAL_COMMISSION);
    }
    return sum;
}

double SumFloatingPnL(void) {
    double f = 0.0;
    const int n = PositionsTotal();
    for (int i = 0; i < n; ++i) {
        const ulong t = PositionGetTicket(i);
        if (t == 0 || !PositionSelectByTicket(t))
            continue;
        f += PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
    }
    return f;
}

//+------------------------------------------------------------------+
//| FIX (LOT 1) : cached realised-today P&L (throttled 2 s). Used by  |
//| Live_TodayProfit + Live_DailyDdPct to avoid running a full        |
//| HistorySelect scan every 500 ms timer tick (was a major freeze    |
//| cause - panel kept updating but OBJECT_CLICK starved). Floating   |
//| P&L is NOT cached (SumFloatingPnL is cheap, recomputed live).     |
//+------------------------------------------------------------------+
double CachedRealisedToday(void) {
    if (g_realised_today_scan == 0 || TimeCurrent() - g_realised_today_scan >= 2) {
        MqlDateTime mdt;
        TimeToStruct(TimeCurrent(), mdt);
        mdt.hour = 0; mdt.min = 0; mdt.sec = 0;
        const datetime today_start = StructToTime(mdt);
        g_realised_today_cache = SumClosedDealsPnL(today_start, TimeCurrent());
        g_realised_today_scan  = TimeCurrent();
    }
    return g_realised_today_cache;
}

double Live_TodayProfit(void) {
    return CachedRealisedToday() + SumFloatingPnL();
}

double Live_TotalProfit(void) {
    // Total realised P&L = current balance - starting size. This reflects EVERY
    // balance change (trades, swaps, commissions, AND prop-firm balance operations
    // such as a violation deduction or a payout), so it always reconciles with the
    // "Bal $X" shown against the account size. The previous version summed only
    // CLOSING DEALS since InpCycleStartIso, which (a) depended on a date the user
    // rarely sets and (b) silently missed balance operations -> the figure did not
    // match the real balance. Floating is shown in "Today" and the positions list.
    if (g_profile.initial_balance <= 0.0)
        return 0.0;
    return AccountInfoDouble(ACCOUNT_BALANCE) - g_profile.initial_balance;
}

double Live_TotalProfitPct(void) {
    if (g_profile.initial_balance <= 0.0)
        return 0.0;
    return 100.0 * Live_TotalProfit() / g_profile.initial_balance;
}

int Live_TradingDaysCount(void) {
    // FIX (LOT 1) : HistorySelect + O(n^2) day-uniqueness was running every
    // 500 ms timer tick ; the count changes at most once per server-day, so
    // cache 30 s. Was the n#2 freeze cause on long-history accounts.
    if (g_days_scan != 0 && TimeCurrent() - g_days_scan < 30)
        return g_days_cache;
    // Count unique server-days with at least one DEAL_ENTRY_IN since cycle start.
    string cs = (g_eff_cycle_ymd > 0 ? YmdToIso(g_eff_cycle_ymd) : InpCycleStartIso); // V1.27 : editable cycle start
    StringReplace(cs, "-", ".");
    datetime from = StringToTime(cs);
    if (from == 0)
        from = TimeCurrent() - 30 * 86400;
    if (!HistorySelect(from, TimeCurrent()))
        return 0;
    const int n = HistoryDealsTotal();
    datetime days[];
    ArrayResize(days, 0);
    for (int i = 0; i < n; ++i) {
        const ulong t = HistoryDealGetTicket(i);
        if (t == 0)
            continue;
        if ((ENUM_DEAL_ENTRY)HistoryDealGetInteger(t, DEAL_ENTRY) != DEAL_ENTRY_IN)
            continue;
        const datetime dt = (datetime)HistoryDealGetInteger(t, DEAL_TIME);
        MqlDateTime mdt;
        TimeToStruct(dt, mdt);
        mdt.hour = 0;
        mdt.min = 0;
        mdt.sec = 0;
        const datetime day = StructToTime(mdt);
        bool exists = false;
        for (int j = 0; j < ArraySize(days); ++j) {
            if (days[j] == day) {
                exists = true;
                break;
            }
        }
        if (!exists) {
            const int sz = ArraySize(days);
            ArrayResize(days, sz + 1);
            days[sz] = day;
        }
    }
    g_days_cache = ArraySize(days);
    g_days_scan  = TimeCurrent();
    return g_days_cache;
}

double Live_AvgDailyProfit(void) {
    const int days = Live_TradingDaysCount();
    if (days <= 0)
        return 0.0;
    return Live_TotalProfit() / (double)days;
}

//+------------------------------------------------------------------+
//| Suggested lot - per user (2026-05-11) :                          |
//|   - SL at scalping default = 10 % of current price               |
//|   - 1 % of balance per trade, capped by 3 % / N_planned          |
//|   - clipped to symbol VOLUME_STEP / MIN / MAX                    |
//|   - capped by 70 % margin budget split across N_planned          |
//|                                                                  |
//| Lot = budget_money / (sl_distance_price / tick_size * tick_value)|
//+------------------------------------------------------------------+
//+------------------------------------------------------------------+
//| Daily risk bonus :                                               |
//|   - If today's P&L exceeds +1 % of initial balance, add +0.5 %   |
//|     to the per-trade risk cap. Resets when today rolls over.     |
//|     Cumulative cap (FundedNext hard 3 %) stays unchanged.        |
//+------------------------------------------------------------------+
double Live_DailyRiskBonus(void) {
    if (g_profile.initial_balance <= 0.0)
        return 0.0;
    const double today_pct = 100.0 * Live_TodayProfit() / g_profile.initial_balance;
    return (today_pct >= 1.0 ? 0.5 : 0.0);
}

double Live_PerTradeCap(void) {
    return 1.0 + Live_DailyRiskBonus();
}

//+------------------------------------------------------------------+
//| Live_PerTradeBudgetPct : SL-line allocation for an EXISTING      |
//| position. Splits cumulative cap evenly across n_for_share open   |
//| positions, clamped by per-trade cap (with daily bonus).          |
//+------------------------------------------------------------------+
double Live_PerTradeBudgetPct(int n_for_share) {
    const int eff = MathMax(1, n_for_share);
    const double per_trade_cap = Live_PerTradeCap();
    const double cumulative_cap = EffectiveRiskCap(); // B7 : tightened cap if violation active
    return MathMin(per_trade_cap, cumulative_cap / eff);
}

//+------------------------------------------------------------------+
//| Live_NextTradeBudgetPct : budget for the NEXT-to-be-opened trade.|
//|                                                                  |
//| Per user rule (2026-05-11) : "1 % per trade as long as cumulative|
//| has room". Translates to :                                       |
//|                                                                  |
//|     budget = min(per_trade_cap, cumulative_cap - already_used)   |
//|                                                                  |
//| So with 3 % cap + 1 % per-trade :                                |
//|   used = 0   -> 1 %  (1st trade)                                 |
//|   used = 1   -> 1 %  (2nd trade : still room for full 1 %)       |
//|   used = 2   -> 1 %  (3rd trade : exactly fills cumulative)      |
//|   used = 2.5 -> 0.5 % (4th trade : only 0.5 % cumulative left)   |
//|   used = 3   -> 0 %  (no more room)                              |
//|                                                                  |
//| g_max_parallel doesn't shrink THIS trade's budget; it only       |
//| informs the panel display "you plan N total". Budget is paced by |
//| ACTUAL cumulative usage, not by planned slots.                   |
//+------------------------------------------------------------------+
double Live_NextTradeBudgetPct(void) {
    // B9 (calibrated 2026-05-20) : DD/trade budget = EffectiveRiskCap() / N,
    // pure cap/N with NO extra ceiling. Then clamp by the cumulative budget
    // still available (cap - already-engaged risk), so trades already taken
    // shrink what the next one may use.
    if (g_profile.initial_balance <= 0.0)
        return 0.0;
    const double cap = EffectiveRiskCap();          // 3% normal, 1% if violation (B7)
    const int    N   = MathMax(1, g_max_parallel);
    // B9 (calib 2026-05-20) : cap/N capped by the per-trade strategy ceiling.
    const double dd_per_trade = MathMin(cap / N, g_eff_max_risk_pt);
    const double used = Live_CumulativeRiskPct();
    const double remaining = MathMax(0.0, cap - used);
    return MathMin(dd_per_trade, remaining);
}

bool Live_ComputeSuggestedLot(SuggestedLot& out) {
    out.ok = false;
    out.math_lot = 0.0;
    out.broker_lot = 0.0;
    out.below_min = false;
    out.over_budget = false;
    out.price = 0.0;
    out.sl_distance_price = 0.0;
    out.money_per_lot_at_sl = 0.0;
    out.risk_budget_money = 0.0;
    out.budget_pct = 0.0;
    out.vol_min = 0.0;
    out.vol_max = 0.0;
    out.vol_step = 0.0;
    out.tick_size = 0.0;
    out.tick_value = 0.0;
    out.free_margin_money = 0.0;
    out.free_margin_pct = 0.0;
    out.margin_bound = false;
    out.margin_insufficient = false;

    if (g_profile.initial_balance <= 0.0)
        return false;
    const string sym = _Symbol;
    const double price = SymbolInfoDouble(sym, SYMBOL_BID);
    if (price <= 0.0)
        return false;
    const double tick_size = SymbolInfoDouble(sym, SYMBOL_TRADE_TICK_SIZE);
    const double tick_value = SymbolInfoDouble(sym, SYMBOL_TRADE_TICK_VALUE);
    if (tick_size <= 0.0 || tick_value <= 0.0)
        return false;

    out.price = price;
    out.tick_size = tick_size;
    out.tick_value = tick_value;

    // SL distance in PRICE-percent of current price - input-tunable so the
    // user can try 10 -> 2 -> 1.5 -> 1 etc. and pick the value that suits
    // their setup. The footer LABEL still speaks in DD-percent.
    out.sl_distance_price = price * g_eff_sl_pct / 100.0;
    out.money_per_lot_at_sl = (out.sl_distance_price / tick_size) * tick_value;
    if (out.money_per_lot_at_sl <= 0.0)
        return false;

    // ====== Risk budget (cumulative-aware + daily-bonus aware) =========
    // Live_NextTradeBudgetPct accounts for ALREADY-USED cumulative risk
    // from open positions, splits the REMAINING budget across the
    // REMAINING planned slots, and clamps to per-trade cap (1 % base,
    // +0.5 % once today's P&L exceeds +1 % of initial balance).
    out.budget_pct = Live_NextTradeBudgetPct();
    out.risk_budget_money = g_profile.initial_balance * out.budget_pct / 100.0;
    const double lots_by_risk = out.risk_budget_money / out.money_per_lot_at_sl;

    // ====== Margin budget (M2) : native OrderCalcMargin (incl. leverage) ====
    // Lot clamped by (a) the per-trade margin cap, (b) the REMAINING cumulative
    // margin room = cap_total% x balance - ACCOUNT_MARGIN already used, and
    // (c) FIX 8 : the broker's REAL free margin (ACCOUNT_MARGIN_FREE). (a)+(b) are
    // FundedNext-rule budgets ; (c) is what the broker will actually let you open
    // right now given the trades you ALREADY have on. The proposal must respect all
    // three so the lot stays EXECUTABLE. Uses ASK (BUY side) like the live trade.
    const double ask = SymbolInfoDouble(sym, SYMBOL_ASK);
    double margin_for_1lot = 0.0;
    if (!OrderCalcMargin(ORDER_TYPE_BUY, sym, 1.0, (ask > 0.0 ? ask : price), margin_for_1lot))
        margin_for_1lot = 0.0;

    // FIX (LOT 2) : per-trade cap (a) AND cumulative room (b) are vs INITIAL
    // balance now (FN rule, help.fundednext 10816539/10816788). (c) free margin
    // is the live broker free, unchanged.
    const double init_bal    = g_profile.initial_balance;
    const double free_margin = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
    out.free_margin_money = free_margin;
    out.free_margin_pct   = (init_bal > 0.0 ? 100.0 * free_margin / init_bal : 0.0);

    double lots_by_margin = lots_by_risk; // fallback if margin data unavailable
    if (margin_for_1lot > 0.0) {
        const double margin_used = AccountInfoDouble(ACCOUNT_MARGIN);
        // (a) per-trade margin cap
        const double pt_margin_money   = init_bal * g_eff_max_margin_pt / 100.0;
        const double lots_by_pt_margin = pt_margin_money / margin_for_1lot;
        // (b) remaining cumulative margin room (FN 70%/30% rule vs used margin)
        const double margin_room  = MathMax(0.0, init_bal * EffectiveMarginCap() / 100.0 - margin_used);
        const double lots_by_room = margin_room / margin_for_1lot;
        // (c) FIX 8 : real broker free margin (already nets out the open trades)
        const double lots_by_free = free_margin / margin_for_1lot;
        lots_by_margin = MathMin(lots_by_pt_margin, MathMin(lots_by_room, lots_by_free));
        // Is the REAL free margin the tightest of all constraints ? (info chip)
        out.margin_bound = (lots_by_free <= lots_by_risk + 1e-9 &&
                            lots_by_free <= lots_by_pt_margin + 1e-9 &&
                            lots_by_free <= lots_by_room + 1e-9);
    }

    out.math_lot = MathMin(lots_by_risk, lots_by_margin);

    out.vol_step = SymbolInfoDouble(sym, SYMBOL_VOLUME_STEP);
    out.vol_min = SymbolInfoDouble(sym, SYMBOL_VOLUME_MIN);
    out.vol_max = SymbolInfoDouble(sym, SYMBOL_VOLUME_MAX);

    // Floor to step; clip to broker's min/max. Below min -> still propose the
    // minimum lot (user wants a usable suggestion) but flag over_budget.
    double broker = out.math_lot;
    if (out.vol_step > 0.0)
        broker = MathFloor(broker / out.vol_step) * out.vol_step;
    if (out.vol_min > 0.0 && broker < out.vol_min) {
        broker = out.vol_min;
        out.below_min = true;
    }
    if (out.vol_max > 0.0 && broker > out.vol_max)
        broker = out.vol_max;
    out.broker_lot = broker;

    // Does the clipped broker lot blow our intended risk budget ?
    const double actual_risk_money = broker * out.money_per_lot_at_sl;
    if (actual_risk_money > out.risk_budget_money * 1.05) // 5 % tolerance
        out.over_budget = true;

    // FIX 8 : can the REAL free margin even afford the broker minimum lot ? If not,
    // no executable trade is possible right now -> hard red flag.
    if (margin_for_1lot > 0.0 && out.vol_min > 0.0 &&
        out.vol_min * margin_for_1lot > out.free_margin_money)
        out.margin_insufficient = true;

    // ====== B9 display fields ===========================================
    const double cap_b9      = EffectiveRiskCap();
    out.n_planned            = MathMax(1, g_max_parallel);
    out.dd_per_trade_pct     = MathMin(cap_b9 / out.n_planned, g_eff_max_risk_pt); // B9 : cap/N capped by per-trade ceiling
    out.risk_cap             = cap_b9;
    out.used_risk_pct        = Live_CumulativeRiskPct();
    // reduce flag : the cumulative-remaining clamp pulled the budget below cap/N
    out.reduce_flag          = (out.budget_pct < out.dd_per_trade_pct - 0.0001);
    out.sl_level_buy         = price - out.sl_distance_price;   // example SL level for a BUY
    out.margin_cap_per_trade = g_eff_max_margin_pt;
    out.margin_cap_total     = EffectiveMarginCap();
    out.next_trade_margin_pct = (margin_for_1lot > 0.0
                                 ? 100.0 * (broker * margin_for_1lot) / g_profile.initial_balance
                                 : 0.0);
    out.total_margin_pct      = Live_CumulativeMarginPct() + out.next_trade_margin_pct;

    out.ok = true;
    return true;
}

double Live_SuggestedLot(void) {
    SuggestedLot s;
    if (Live_ComputeSuggestedLot(s))
        return s.broker_lot;
    return 0.0;
}

//+------------------------------------------------------------------+
//| News calendar -> vertical zones on chart                         |
//|                                                                  |
//| For every HIGH-importance event in the next/last 30 min that     |
//| affects the chart symbol's currencies, draw a translucent vertical|
//| rectangle spanning event_time +/- news_window_minutes.            |
//+------------------------------------------------------------------+
void RefreshNewsZones(void) {
    // N8 : news are rendered ONLY on the chart the Helper is attached to.
    // Clean any leftovers on OTHER charts (from the old multi-chart behaviour),
    // then draw on the current chart only.
    long cid = ChartFirst();
    while (cid >= 0) {
        if (cid != ChartID())
            ObjectsDeleteAll(cid, "RC_NEWS_");
        cid = ChartNext(cid);
    }
    RefreshNewsZonesForChart(ChartID());
}

//+------------------------------------------------------------------+
//| N10 : map a calendar event name to a short, readable code.       |
//+------------------------------------------------------------------+
string NewsAbbrev(const string name) {
    string u = name;
    StringToUpper(u);
    if (StringFind(u, "NON-FARM") >= 0 || StringFind(u, "NONFARM") >= 0 || StringFind(u, "PAYROLL") >= 0) return "NFP";
    if (StringFind(u, "CONSUMER PRICE") >= 0 || StringFind(u, "CPI") >= 0) return "CPI";
    if (StringFind(u, "PRODUCER PRICE") >= 0 || StringFind(u, "PPI") >= 0) return "PPI";
    if (StringFind(u, "FOMC") >= 0 || StringFind(u, "FEDERAL FUNDS") >= 0 || StringFind(u, "INTEREST RATE") >= 0 || StringFind(u, "RATE DECISION") >= 0 || StringFind(u, "RATE STATEMENT") >= 0 || StringFind(u, "MONETARY POLICY") >= 0) return "RATE";
    if (StringFind(u, "GROSS DOMESTIC") >= 0 || StringFind(u, "GDP") >= 0) return "GDP";
    if (StringFind(u, "PMI") >= 0 || StringFind(u, "PURCHASING MANAGER") >= 0) return "PMI";
    if (StringFind(u, "UNEMPLOY") >= 0) return "UNEMP";
    if (StringFind(u, "RETAIL SALES") >= 0) return "RETAIL";
    if (StringFind(u, "SPEAK") >= 0 || StringFind(u, "SPEECH") >= 0 || StringFind(u, "POWELL") >= 0 || StringFind(u, "LAGARDE") >= 0 || StringFind(u, "TESTIMONY") >= 0) return "SPEECH";
    if (StringFind(u, "EMPLOYMENT") >= 0 || StringFind(u, "JOBLESS") >= 0 || StringFind(u, "JOBS") >= 0) return "JOBS";
    if (StringFind(u, "ISM") >= 0) return "ISM";
    if (StringFind(u, "TRADE BALANCE") >= 0) return "TRADE";
    string r = name;
    if (StringLen(r) > 12)
        r = StringSubstr(r, 0, 12);
    return r;
}

void RefreshNewsZonesForChart(const long chart_id) {
    ObjectsDeleteAll(chart_id, "RC_NEWS_");
    if (!g_eff_show_news)                   // N1 : master toggle
        return;
    // V1.29 T : VISUAL news (VLINE + icons) shows on ALL profiles - Personal,
    // challenges AND funded. Only the master toggle (above) + the level toggles
    // (R) gate it. (The prop news RULE - rule-meter row 8 / ComputeNewsStats /
    // Live_InNewsWindow - stays gated on news_rule_applies elsewhere, untouched.)
    // Profiles with no configured news window fall back to a 15-min band.
    int win_min = (g_profile.news_window_minutes > 0 ? g_profile.news_window_minutes : 15);
    const int win_sec = win_min * 60;

    // Query window : today_start -> +24 h ahead.
    MqlDateTime mdt;
    TimeToStruct(TimeCurrent(), mdt);
    mdt.hour = 0;
    mdt.min = 0;
    mdt.sec = 0;
    const datetime t_from = StructToTime(mdt);
    const datetime t_to = TimeCurrent() + 24 * 60 * 60;

    MqlCalendarValue values[];
    if (CalendarValueHistory(values, t_from, t_to, NULL, NULL) <= 0)
        return;

    const string chart_sym = ChartSymbol(chart_id);
    if (chart_sym == "")
        return;

    const double price_hi = ChartGetDouble(chart_id, CHART_PRICE_MAX);
    const double price_lo = ChartGetDouble(chart_id, CHART_PRICE_MIN);
    if (price_hi <= price_lo)
        return;
    const double range = price_hi - price_lo;
    const double flag_price = price_lo + range * 0.04;

    const datetime now = TimeCurrent();
    // N2/N7 : anti-collision. Events whose time falls within collision_sec of
    // the previous drawn one are pushed into stacked vertical "lanes" so the
    // labels + bottom icons never overlap (scales with the chart timeframe).
    // AUDIT 2026-06-07 fix #6 : LOT E1 added MEDIUM (~2x density). The old
    // `PeriodSeconds*12` collision window = 12 h on H1 / 2 days on H4 and the
    // lane++ counter had no cap -> flags spilled OFF-CHART on the most-used
    // timeframes. Cap collision at 2 bars (still avoids label overlap) AND
    // wrap lanes at 5 (5 lanes is the panel's vertical news budget).
    const int collision_sec = MathMax(15 * 60,
                                      (int)PeriodSeconds((ENUM_TIMEFRAMES)ChartPeriod(chart_id)) * 2);
    datetime last_t = 0;
    int lane = 0;

    int drawn = 0;
    for (int i = 0; i < ArraySize(values); ++i) {
        MqlCalendarEvent ev;
        if (!CalendarEventById(values[i].event_id, ev))
            continue;
        // LOT E B-NEWS-MEDHIGH : show MEDIUM + HIGH impact (drop LOW only). The
        // visual distinction (HIGH = red triangle, MEDIUM = amber diamond) is
        // already wired below ; the bottom-line stats / countdown still gate
        // on HIGH only.
        const bool ev_high = (ev.importance == CALENDAR_IMPORTANCE_HIGH);
        const bool ev_med  = (ev.importance == CALENDAR_IMPORTANCE_MODERATE);
        if (!ev_high && !ev_med) continue;         // drop LOW
        if (ev_high && !g_eff_news_high) continue; // V1.29 R : level toggles
        if (ev_med  && !g_eff_news_med)  continue;
        MqlCalendarCountry country;
        if (!CalendarCountryById(ev.country_id, country))
            continue;

        const datetime t_evt = values[i].time;
        const string id_suffix = IntegerToString((int)values[i].id);
        const bool upcoming = (t_evt + win_sec >= now);

        // N2/N7 : lane assignment (events come time-sorted from the calendar).
        // fix #6 : wrap lanes at 5 so news clusters can't push flags off-chart.
        if (last_t != 0 && (t_evt - last_t) < collision_sec)
            lane = (lane + 1) % 5;
        else
            lane = 0;
        last_t = t_evt;

        // Impact icon (HIGH = down triangle red, MEDIUM = diamond amber).
        string flag_glyph;
        color flag_color;
        if (ev.importance == CALENDAR_IMPORTANCE_HIGH) {
            flag_glyph = ShortToString((ushort)0x25BC);
            flag_color = g_theme.red;
        } else {
            flag_glyph = ShortToString((ushort)0x25C6);
            flag_color = g_theme.warn;
        }

        // --- Bottom FLAG (icon + TIME + currency). N4 : time ONLY here.
        //     N6 : bigger font. N7 : staggered up by lane to avoid overlap. ---
        const double flag_y = flag_price + range * 0.018 * lane; // N9 : compact stacking
        // V1.29 W : encode the lane in the name (RC_NEWS_FLAG_<lane>_<id>) so the
        // CHARTEVENT_CHART_CHANGE reposition can re-apply the per-lane stagger.
        const string flag_id = "RC_NEWS_FLAG_" + IntegerToString(lane) + "_" + id_suffix;
        ObjectCreate(chart_id, flag_id, OBJ_TEXT, 0, t_evt, flag_y);
        ObjectSetInteger(chart_id, flag_id, OBJPROP_TIME, t_evt);
        ObjectSetDouble(chart_id, flag_id, OBJPROP_PRICE, flag_y);
        ObjectSetString(chart_id, flag_id, OBJPROP_TEXT,
                        flag_glyph + " " + TimeToString(t_evt, TIME_MINUTES) + " " +
                        country.currency + " " + NewsAbbrev(ev.name));
        ObjectSetInteger(chart_id, flag_id, OBJPROP_COLOR, flag_color);
        ObjectSetInteger(chart_id, flag_id, OBJPROP_FONTSIZE, 10); // N6
        ObjectSetString(chart_id, flag_id, OBJPROP_FONT, "Consolas");
        ObjectSetInteger(chart_id, flag_id, OBJPROP_ANCHOR, ANCHOR_LEFT_LOWER);
        ObjectSetInteger(chart_id, flag_id, OBJPROP_BACK, false);
        ObjectSetInteger(chart_id, flag_id, OBJPROP_SELECTABLE, false);
        ObjectSetInteger(chart_id, flag_id, OBJPROP_HIDDEN, true);
        // Tooltip (2026-05-21) : FULL event text on mouse hover -> replaces the
        // permanent top caption. country + full name + time.
        ObjectSetString(chart_id, flag_id, OBJPROP_TOOLTIP,
                        country.currency + " " + ev.name + "  @ " + TimeToString(t_evt, TIME_MINUTES));

        // --- V1.29 U : TWO full-height VLINEs marking the START and END of the
        //     news window (t_evt -/+ win_sec), for upcoming HIGH AND MEDIUM events.
        //     The bottom icon (at t_evt) sits between the two lines. Visible at any
        //     TF/zoom. HIGH = red solid w2 ; MEDIUM = amber dotted w1.
        //     N5 : past events keep the icon only (no lines).
        if (upcoming) {
            const color  vl_clr   = (ev_high ? g_theme.red : g_theme.warn);
            const int    vl_width = (ev_high ? 2 : 1);
            const int    vl_style = (ev_high ? STYLE_SOLID : STYLE_DOT);
            const string vl_tip   = country.currency + " " + ev.name + "  @ " + TimeToString(t_evt, TIME_MINUTES);
            datetime vl_t[2];  vl_t[0] = t_evt - win_sec;                 vl_t[1] = t_evt + win_sec;
            string   vl_id[2]; vl_id[0] = "RC_NEWS_VLN_S_" + id_suffix;   vl_id[1] = "RC_NEWS_VLN_E_" + id_suffix;
            for (int v = 0; v < 2; ++v) {
                ObjectCreate(chart_id, vl_id[v], OBJ_VLINE, 0, vl_t[v], 0);
                ObjectSetInteger(chart_id, vl_id[v], OBJPROP_TIME, vl_t[v]);
                ObjectSetInteger(chart_id, vl_id[v], OBJPROP_COLOR, vl_clr);
                ObjectSetInteger(chart_id, vl_id[v], OBJPROP_WIDTH, vl_width);
                ObjectSetInteger(chart_id, vl_id[v], OBJPROP_STYLE, vl_style);
                ObjectSetInteger(chart_id, vl_id[v], OBJPROP_BACK, true);
                ObjectSetInteger(chart_id, vl_id[v], OBJPROP_SELECTABLE, false);
                ObjectSetInteger(chart_id, vl_id[v], OBJPROP_HIDDEN, true);
                ObjectSetString(chart_id, vl_id[v], OBJPROP_TOOLTIP, vl_tip);
            }
        }

        // --- Vertical BAND + top caption : ONLY upcoming HIGH-impact events.
        //     N5 : PAST events keep ONLY the bottom icon (no band, no caption)
        //     to avoid clutter. ---
        if (upcoming && ev.importance == CALENDAR_IMPORTANCE_HIGH) {
            const datetime t1 = t_evt - win_sec;
            const datetime t2 = t_evt + win_sec;

            const string band_id = "RC_NEWS_BAND_" + id_suffix;
            ObjectCreate(chart_id, band_id, OBJ_RECTANGLE, 0, t1, price_hi, t2, price_lo);
            // N13 : attenuated band - OUTLINE ONLY (no opaque fill) in a muted
            // amber. Marks the news window with soft vertical edges, far less
            // aggressive on the eyes than a solid block.
            ObjectSetInteger(chart_id, band_id, OBJPROP_COLOR, (color)0x000088CC);
            ObjectSetInteger(chart_id, band_id, OBJPROP_BGCOLOR, (color)0x000088CC);
            ObjectSetInteger(chart_id, band_id, OBJPROP_FILL, false);
            ObjectSetInteger(chart_id, band_id, OBJPROP_BACK, true);
            ObjectSetInteger(chart_id, band_id, OBJPROP_STYLE, STYLE_SOLID);
            ObjectSetInteger(chart_id, band_id, OBJPROP_WIDTH, 1);
            ObjectSetInteger(chart_id, band_id, OBJPROP_SELECTABLE, false);
            ObjectSetInteger(chart_id, band_id, OBJPROP_HIDDEN, true);

            // 2026-05-21 : the top text caption is REMOVED. The full event text
            // now lives in the bottom icon's tooltip (OBJPROP_TOOLTIP, on hover).
            // The band rectangle above stays exactly as-is.
        }

        drawn++;
        if (drawn >= 60) // cap (all-currency coverage)
            break;
    }
    ChartRedraw(chart_id);
}

//+------------------------------------------------------------------+
//| B-SPREAD-COMM : commission charged per lot on `sym`, read from the |
//| most recent closed deal (MT5 has no universal per-symbol fee).     |
//| Cached + 60 s throttle (history scan bounded to the last 30 days)  |
//| so it never runs heavy on the 500 ms refresh path. Returns -1 if   |
//| no recent deal carried a commission (e.g. commission-free broker). |
//+------------------------------------------------------------------+
double CommissionPerLot(const string sym) {
    if (g_comm_sym == sym && g_comm_scan != 0 && TimeCurrent() - g_comm_scan < 60)
        return g_comm_per_lot;
    g_comm_scan    = TimeCurrent();
    g_comm_sym     = sym;
    g_comm_per_lot = -1.0;
    if (HistorySelect(TimeCurrent() - 30 * 24 * 3600, TimeCurrent())) {
        const int n = HistoryDealsTotal();
        for (int i = n - 1; i >= 0; --i) {     // newest first
            const ulong t = HistoryDealGetTicket(i);
            if (t == 0) continue;
            if (HistoryDealGetString(t, DEAL_SYMBOL) != sym) continue;
            const double vol = HistoryDealGetDouble(t, DEAL_VOLUME);
            const double cm  = HistoryDealGetDouble(t, DEAL_COMMISSION);
            if (vol > 0.0 && cm != 0.0) { g_comm_per_lot = MathAbs(cm) / vol; break; }
        }
    }
    return g_comm_per_lot;
}

//+------------------------------------------------------------------+
//| V1.24 G3 B-COPY : a read-only OBJ_EDIT holding the raw lot number. |
//| MT5 lets the user click into it + Ctrl+C the value (no DLL / no    |
//| clipboard API). We overwrite the text each refresh ; READONLY      |
//| means user edits never stick.                                     |
//+------------------------------------------------------------------+
void DrawCopyEdit(const string id, int x, int y, int w, int h, const string text, const string tip) {
    const bool fresh = (ObjectFind(0, id) < 0);
    if (fresh) ObjectCreate(0, id, OBJ_EDIT, 0, 0, 0);
    ObjectSetInteger(0, id, OBJPROP_XDISTANCE, x);
    ObjectSetInteger(0, id, OBJPROP_YDISTANCE, y);
    ObjectSetInteger(0, id, OBJPROP_XSIZE, w);
    ObjectSetInteger(0, id, OBJPROP_YSIZE, h);
    // P4 : only rewrite the text when it actually changed, so re-typing the value
    // every 500 ms doesn't wipe the user's selection mid-copy.
    if (fresh || ObjectGetString(0, id, OBJPROP_TEXT) != text)
        ObjectSetString(0, id, OBJPROP_TEXT, text);
    ObjectSetString (0, id, OBJPROP_FONT, RC_FONT_UI);
    ObjectSetInteger(0, id, OBJPROP_FONTSIZE, RC_FONT_SIZE);
    ObjectSetInteger(0, id, OBJPROP_COLOR, g_theme.accent);
    ObjectSetInteger(0, id, OBJPROP_BGCOLOR, g_theme.bg_section);
    ObjectSetInteger(0, id, OBJPROP_BORDER_COLOR, g_theme.border);
    // P4 : NOT read-only -> MT5 only lets you select + Ctrl+C an EDITABLE field.
    // Typing is harmless (overwritten on the next value change).
    ObjectSetInteger(0, id, OBJPROP_READONLY, false);
    ObjectSetInteger(0, id, OBJPROP_ALIGN, ALIGN_CENTER);
    ObjectSetInteger(0, id, OBJPROP_CORNER, CORNER_LEFT_UPPER);
    ObjectSetInteger(0, id, OBJPROP_SELECTABLE, false);
    ObjectSetInteger(0, id, OBJPROP_HIDDEN, true);
    ObjectSetInteger(0, id, OBJPROP_ZORDER, 120);
    ObjectSetString (0, id, OBJPROP_TOOLTIP, tip);
}

// P1 : sign colour (green >= 0, red < 0) for an individually-coloured value.
color SignColor(double v) { return (v >= 0.0 ? g_theme.ok : g_theme.red); }

// P1 : draw a row of individually-coloured text segments left-to-right, each
// measured with TextGetSize so nothing overlaps and the line never runs off the
// panel edge (the previous single label was clipped + one colour for everything).
void DrawColoredSegments(const string idbase, int x, int y, string &txt[], color &clr[], int fsize) {
    TextSetFont(RC_FONT, -fsize * 10);
    int cx = x;
    const int n = ArraySize(txt);
    for (int i = 0; i < n; ++i) {
        const string id = idbase + IntegerToString(i);
        DrawLabel(id, cx, y, txt[i], clr[i], fsize);
        uint tw = 0, th = 0;
        TextGetSize(txt[i], tw, th);
        cx += (int)tw;
    }
    for (int i = n; i < 24; ++i) { // clear any leftover segments from a longer render
        const string id = idbase + IntegerToString(i);
        if (ObjectFind(0, id) >= 0) ObjectDelete(0, id);
    }
}

void DrawCopyFields(void) {
    // P4 : copy-lot fields on the TF/control bar, LEFT of the BE button - no more
    // overlap with Re-center / Auto-SL (which live on the recent-symbols bar).
    const int x = g_anchor_x, w = InpPanelWidth;
    const int y = g_tfbar_y;
    const int h = InpRowHeight - 6;
    const int bw = 60; // box width (wide enough for big lot numbers)
    // V1.29 F : visible caption (Sug / Max) before each box + localized tooltips
    // (the two boxes used to be indistinguishable - only an EN-hardcoded tooltip).
    // Reads "Sug [0.50]  Max [1.20]  BE". Leftmost caption (x+w-242 = x+378 @620)
    // stays right of the TF buttons (~x+345).
    const int box_max_x = x + w - 118; // just left of the BE button (x+w-52)
    const int cap_max_x = x + w - 146;
    const int box_sug_x = x + w - 214;
    const int cap_sug_x = x + w - 242;
    DrawLabel(RC_PREFIX + "cap_sug", cap_sug_x, y + 5, Tr("cap_sug"), g_theme.text_dim, RC_FONT_SIZE);
    DrawCopyEdit(RC_PREFIX + "copy_sug", box_sug_x, y + 3, bw, h,
                 DoubleToString(g_suglot_copy, g_maxlot_digits), Tr("copy_sug_tip"));
    DrawLabel(RC_PREFIX + "cap_max", cap_max_x, y + 5, Tr("cap_max"), g_theme.text_dim, RC_FONT_SIZE);
    DrawCopyEdit(RC_PREFIX + "copy_max", box_max_x, y + 3, bw, h,
                 DoubleToString(g_maxlot_copy, g_maxlot_digits), Tr("copy_max_tip"));
}

//+------------------------------------------------------------------+
//| Footer refresh - profit metrics + suggested lot                  |
//+------------------------------------------------------------------+
void RefreshFooterMetrics(void) {
    const double total_pct = Live_TotalProfitPct();     // total P&L as % of account size
    const int    days      = Live_TradingDaysCount();   // distinct days with >=1 trade
    const double floating  = SumFloatingPnL();          // P&L of OPEN positions (JR's "Profit")
    const double today_p   = Live_TodayProfit();        // FIX (LOT 3) : day P&L (cached realised + live floating)
    const double today_pct = (g_profile.initial_balance > 0.0
                                  ? 100.0 * today_p / g_profile.initial_balance
                                  : 0.0);
    const double per_cap = Live_PerTradeCap();  // 1.0 or 1.5
    const double risk_cap_eff = EffectiveRiskCap();     // B7 : tightened cap if violation active
    const double margin_cap_eff = EffectiveMarginCap(); // B7
    const double used_risk = Live_CumulativeRiskPct();
    const double used_margin = Live_CumulativeMarginPct();

    // Row 1 (P1 + P2) : Bal | P&L% | Today $ (%) | days | Profit | Spread | Comm,
    // EACH value coloured by its own sign (green >= 0, red < 0), full precision
    // (2 decimals on money + %), laid out with TextGetSize so the line never
    // clips. Slightly smaller font (RC_FONT_SIZE-1) to fit the extra precision.
    // Row 1 = ACCOUNT stats only (Bal / P&L / Today / days / Profit). Spread +
    // commission are SYMBOL info -> moved to the lot line (row 2) below.
    string fseg[5]; color fclr[5];
    fseg[0] = Tr("f_bal") + " $" + DoubleToString(AccountInfoDouble(ACCOUNT_BALANCE), 2) + "   ";
    fclr[0] = g_theme.text;
    fseg[1] = "P&L " + (total_pct >= 0 ? "+" : "") + DoubleToString(total_pct, 2) + "%   ";
    fclr[1] = SignColor(total_pct);
    fseg[2] = Tr("f_today") + " " + (today_p >= 0 ? "+$" : "-$") + DoubleToString(MathAbs(today_p), 2) +
              " (" + (today_pct >= 0 ? "+" : "") + DoubleToString(today_pct, 2) + "%)   ";
    fclr[2] = SignColor(today_p);
    fseg[3] = IntegerToString(days) + "d   ";
    fclr[3] = g_theme.text_dim;
    fseg[4] = Tr("f_profit") + " " + (floating >= 0 ? "+$" : "-$") + DoubleToString(MathAbs(floating), 2);
    fclr[4] = SignColor(floating);
    DrawColoredSegments(RC_PREFIX + "fseg_", g_anchor_x + RC_PAD, g_footer_y + 5, fseg, fclr, RC_FONT_SIZE - 1);

    // Row 3 : per-trade cap + risk / margin "left" indicators (was static
    // brand line before - now dynamic with budget info AND add-ons summary).
    // Cascade (2026-05-20) : show only the add-ons VALID for the selected plan;
    // flag any ticked-but-invalid ones as ignored (MT5 can't grey out inputs).
    const int valid_addons   = g_addons_mask & g_catalog.ValidAddonsMask(EffectivePlan());
    const int ignored_addons = g_addons_mask & (~g_catalog.ValidAddonsMask(EffectivePlan()));
    // V1.28 : clearer + non-clipping. Show "Add-ons: X" (localized "none"),
    // and move the cryptic "[+N ign]" detail into the hover tooltip.
    string addons_disp = Tr("addons_lbl") + " " +
        (valid_addons == 0 ? Tr("addons_none") : g_catalog.DescribeAddons(valid_addons));
    int nign = 0;
    for (int b = 0; b < 16; ++b) if ((ignored_addons & (1 << b)) != 0) nign++;
    string budget_line;
    if (g_eff_risktools) {
        StringConcatenate(budget_line,
                          Tr("f_cap"), " ", DoubleToString(per_cap, 2), "%",
                          "  ", Tr("f_risk"), " ", DoubleToString(used_risk, 2),
                          "/", DoubleToString(risk_cap_eff, 1), "%",
                          (g_risk_violation_active ? "!" : ""),
                          "  ", Tr("f_margin"), " ", DoubleToString(used_margin, 2),
                          "/", DoubleToString(margin_cap_eff, 1), "%",
                          (g_margin_violation_active ? "!" : ""),
                          " | ", addons_disp); // V1.29 D : tighter separator
    } else {
        budget_line = addons_disp; // V1.29 N : risk-tools OFF -> add-ons summary only (no Cap/Risk/Margin)
    }
    ObjectSetString(0, RC_PREFIX + "footer_l3", OBJPROP_TEXT, budget_line);
    // P3 : explain this line on hover ; flag any ignored (input-enabled but
    // plan-invalid) add-ons here instead of cluttering the visible line.
    string l3_tip = "Cap = max risk per trade % | Risk = cumulative open risk used/cap | Margin = cumulative margin used/cap | active add-ons";
    if (nign > 0)
        l3_tip = l3_tip + "   (" + IntegerToString(nign) + " enabled add-on(s) ignored: not valid for this plan)";
    ObjectSetString(0, RC_PREFIX + "footer_l3", OBJPROP_TOOLTIP, l3_tip);
    color budget_clr = g_theme.text_dim;
    if (used_risk >= risk_cap_eff * 0.9 || used_margin >= margin_cap_eff * 0.9)
        budget_clr = g_theme.warn;
    ObjectSetInteger(0, RC_PREFIX + "footer_l3", OBJPROP_COLOR, budget_clr);

    // Pyramid advisor (D, art. 22187) - footer row 4, only when enabled.
    if (InpEnablePyramidSafe)
        RefreshPyramidLine();

    // Row 2 : suggested-lot (P1, minimal). "Lot 0.18 | N6 0.50%/tr". Risk
    // cumulative lives in the top bars; margin detail in the "Max lot allowed"
    // row. The SL level is read off the chart line.
    SuggestedLot s;
    string sug_line = "";
    if (g_eff_risktools) { // V1.29 N : the lot proposal is a risk-tool -> only when ON
        if (Live_ComputeSuggestedLot(s)) {
            const int sld = LotDigits(s.vol_step);  // B-LOTPRECISION
            g_suglot_copy = s.broker_lot;           // V1.24 G3 copy
            StringConcatenate(sug_line,
                              Tr("f_lot"), " ", DoubleToString(s.broker_lot, sld),
                              " | N", s.n_planned, " ", DoubleToString(s.dd_per_trade_pct, 2), "%/tr",
                              "  ", Tr("f_free"), " ", DoubleToString(s.free_margin_pct, 0), "%");
            // FIX 8 : free-margin awareness. Priority : insufficient (red, unexecutable)
            // > risk-budget reduce > below-min > lot capped by free margin (info).
            color l2_clr = g_theme.text;
            string l2_flag = ""; // V1.29 D : the long [..] flag goes to the tooltip, not the clipping line
            if (s.margin_insufficient) {
                l2_flag = Tr("f_insuf");
                l2_clr = g_theme.red;
            } else if (s.reduce_flag) {
                l2_flag = Tr("f_reduce");
                l2_clr = g_theme.warn;
            } else if (s.below_min) {
                l2_flag = Tr("f_belowmin");
                l2_clr = g_theme.warn;
            } else if (s.margin_bound) {
                l2_flag = Tr("f_marginbound");
            }
            ObjectSetInteger(0, RC_PREFIX + "footer_l2", OBJPROP_COLOR, l2_clr);
            ObjectSetString(0, RC_PREFIX + "footer_l2", OBJPROP_TOOLTIP, l2_flag);
        } else {
            sug_line = Tr("lot_unavail");
            g_suglot_copy = 0.0;
            ObjectSetInteger(0, RC_PREFIX + "footer_l2", OBJPROP_COLOR, g_theme.text_dim);
            ObjectSetString(0, RC_PREFIX + "footer_l2", OBJPROP_TOOLTIP, "");
        }
    } else {
        // V1.29 N : risk-tools OFF -> no lot proposal, just symbol spread + comm below.
        g_suglot_copy = 0.0;
        ObjectSetInteger(0, RC_PREFIX + "footer_l2", OBJPROP_COLOR, g_theme.text_dim);
        ObjectSetString(0, RC_PREFIX + "footer_l2", OBJPROP_TOOLTIP, "");
    }
    // P-D : spread + commission belong to the SYMBOL -> always shown on row 2.
    const long   spr_pts = (long)SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
    const double comm_pl = CommissionPerLot(_Symbol);
    const string symline = Tr("spread") + " " + IntegerToString((int)spr_pts) +
               "  " + Tr("comm") + " " + (comm_pl >= 0.0 ? "$" + DoubleToString(comm_pl, 2) : "n/a"); // V1.29 D : drop "/lot"
    sug_line = (StringLen(sug_line) > 0 ? sug_line + "   " : "") + symline; // no leading gap when OFF
    ObjectSetString(0, RC_PREFIX + "footer_l2", OBJPROP_TEXT, sug_line);
    if (g_eff_risktools)
        DrawCopyFields(); // V1.29 N : copy-lot boxes only when risk-tools ON
}

//+------------------------------------------------------------------+
//| Persist user's max-parallel choice across symbol/timeframe       |
//| changes via MT5 GlobalVariable.                                  |
//+------------------------------------------------------------------+
//+------------------------------------------------------------------+
//| FIX 2 (V1.0.1) : convert 1 unit of `ccy` into the account deposit |
//| currency. Used to currency-correct the MANUAL margin fallback     |
//| (OrderCalcMargin already returns the deposit currency natively).  |
//| For a USD-margin symbol on a USD account the rate is 1.0 (no-op), |
//| so US30 / NDX100 stay untouched; a JPY-margin index (JP225) is    |
//| divided by USDJPY instead of being ~150x overstated (1.57 lot).   |
//| Returns 1.0 when currencies match or no pair exists (never invent)|
//+------------------------------------------------------------------+
double CcyToDepositRate(const string ccy) {
    const string acct = AccountInfoString(ACCOUNT_CURRENCY);
    if (ccy == "" || ccy == acct)
        return 1.0;
    double bid = 0.0;
    const string direct = ccy + acct;   // e.g. EURUSD : 1 ccy = bid acct ccy
    if (SymbolSelect(direct, true)) {
        bid = SymbolInfoDouble(direct, SYMBOL_BID);
        if (bid > 0.0) return bid;
    }
    const string inverse = acct + ccy;  // e.g. USDJPY : 1 ccy = 1/bid acct ccy
    if (SymbolSelect(inverse, true)) {
        bid = SymbolInfoDouble(inverse, SYMBOL_BID);
        if (bid > 0.0) return 1.0 / bid;
    }
    return 1.0;                         // unknown pair -> no conversion, never invent
}

//+------------------------------------------------------------------+
//| M1c : broker-EXACT margin per 1.0 lot (Coordinator reference,    |
//| margin-calculation.md). OrderCalcMargin is primary (reads the    |
//| broker engine, all calc-modes). Fallback BRANCHES on             |
//| SYMBOL_TRADE_CALC_MODE - indices = CFDINDEX cs*px*(tv/ts)*ri,    |
//| NOT the leverage formula. Returns 0.0 only if all paths fail.    |
//+------------------------------------------------------------------+
double MarginPerLot(const string sym) {
    g_maxlot_path = "none";
    g_maxlot_m1 = 0.0;
    g_maxlot_err = 0;
    g_maxlot_dbg2 = ""; // stays empty on the OCM path (already in deposit ccy)
    SymbolSelect(sym, true); // (1) load into Market Watch (cause #1 of OCM fail)

    MqlTick t;
    double px = 0.0; // (2) valid price : tick.ask -> ASK -> BID -> LAST
    if (SymbolInfoTick(sym, t) && t.ask > 0.0) px = t.ask;
    if (px <= 0.0) px = SymbolInfoDouble(sym, SYMBOL_ASK);
    if (px <= 0.0) px = SymbolInfoDouble(sym, SYMBOL_BID);
    if (px <= 0.0) px = SymbolInfoDouble(sym, SYMBOL_LAST);
    if (px <= 0.0) { g_maxlot_path = "no_price"; return 0.0; }

    double m = 0.0; // (3) PRIMARY = OrderCalcMargin (the broker truth)
    ResetLastError();
    if (OrderCalcMargin(ORDER_TYPE_BUY, sym, 1.0, px, m) && m > 0.0) {
        g_maxlot_path = "ocm"; g_maxlot_m1 = m; return m;
    }
    g_maxlot_err = GetLastError();
    SymbolSelect(sym, true); // retry once after a fresh select
    ResetLastError();
    if (OrderCalcMargin(ORDER_TYPE_BUY, sym, 1.0, px, m) && m > 0.0) {
        g_maxlot_path = "ocm_retry"; g_maxlot_m1 = m; return m;
    }
    g_maxlot_err = GetLastError();

    // (4) FALLBACK only if OCM fails : branch on calc-mode.
    const ENUM_SYMBOL_CALC_MODE mode = (ENUM_SYMBOL_CALC_MODE)SymbolInfoInteger(sym, SYMBOL_TRADE_CALC_MODE);
    const double cs  = SymbolInfoDouble(sym, SYMBOL_TRADE_CONTRACT_SIZE);
    const double tv  = SymbolInfoDouble(sym, SYMBOL_TRADE_TICK_VALUE);
    const double ts  = SymbolInfoDouble(sym, SYMBOL_TRADE_TICK_SIZE);
    const long   lev = AccountInfoInteger(ACCOUNT_LEVERAGE);
    const double mi  = SymbolInfoDouble(sym, SYMBOL_MARGIN_INITIAL);
    double ri = 1.0, rm = 1.0;
    SymbolInfoMarginRate(sym, ORDER_TYPE_BUY, ri, rm);
    if (ri <= 0.0) ri = 1.0;

    // FIX 2 (V1.0.1) : the manual formulas below yield a value in the symbol's
    // MARGIN currency. OCM converts to the deposit currency for us; the fallback
    // does not, so a JPY-margin index (JP225) came out ~USDJPY x too high -> max lot
    // far too small (1.57 instead of the real, much larger cap). Convert. For a
    // USD-margin symbol on a USD account fx = 1.0, so US30 / NDX100 are unchanged.
    const string mccy = SymbolInfoString(sym, SYMBOL_CURRENCY_MARGIN);
    const double fx   = CcyToDepositRate(mccy);
    g_maxlot_dbg2 = "mccy=" + mccy + " fx=" + DoubleToString(fx, 5) +
                    " tv=" + DoubleToString(tv, 5) + " ts=" + DoubleToString(ts, 5) +
                    " cs=" + DoubleToString(cs, 2) + " ri=" + DoubleToString(ri, 4);

    if (mi > 0.0) { g_maxlot_path = "margin_initial"; g_maxlot_m1 = mi * ri * fx; return g_maxlot_m1; }

    double r = 0.0;
    switch (mode) {
        case SYMBOL_CALC_MODE_FOREX:             r = (lev > 0) ? (cs / lev) * ri : 0.0; break;
        case SYMBOL_CALC_MODE_FOREX_NO_LEVERAGE: r = cs * ri; break;
        case SYMBOL_CALC_MODE_CFD:               r = cs * px * ri; break;
        case SYMBOL_CALC_MODE_CFDLEVERAGE:       r = (lev > 0) ? (cs * px / lev) * ri : 0.0; break;
        case SYMBOL_CALC_MODE_CFDINDEX:          r = (ts > 0) ? cs * px * (tv / ts) * ri : 0.0; break; // US30/NDX100
        case SYMBOL_CALC_MODE_FUTURES:
        case SYMBOL_CALC_MODE_EXCH_FUTURES:      r = (mi > 0) ? mi * ri : 0.0; break;
        case SYMBOL_CALC_MODE_EXCH_STOCKS:       r = cs * px * ri; break;
        default:                                 r = 0.0; break; // unknown -> n/a, never invent
    }
    r *= fx; // FIX 2 : margin-currency -> deposit currency (no-op when fx = 1.0)
    g_maxlot_path = (r > 0.0 ? "calcmode" : "fail");
    g_maxlot_m1 = r;
    return r;
}

double MaxLotAllowed(const string sym, double cap_pct, double balance) {
    const double m1 = MarginPerLot(sym);
    if (m1 <= 0.0) return -1.0; // -1 => display "n/a"
    double lot = (cap_pct / 100.0) * balance / m1;
    const double step = SymbolInfoDouble(sym, SYMBOL_VOLUME_STEP);
    const double vmin = SymbolInfoDouble(sym, SYMBOL_VOLUME_MIN);
    const double vmax = SymbolInfoDouble(sym, SYMBOL_VOLUME_MAX);
    if (step > 0.0) lot = MathFloor(lot / step) * step;
    if (lot < vmin) return 0.0; // even the broker minimum is unaffordable under the cap
    if (vmax > 0.0 && lot > vmax) lot = vmax;
    return lot;
}

void PersistMaxParallel(void) {
    GlobalVariableSet("RC_max_parallel", (double)g_max_parallel);
}

//+------------------------------------------------------------------+
//| B2 : drag-to-move helpers. MovePanelBy shifts ALL panel objects   |
//| (RECTANGLE_LABEL / LABEL / BUTTON, screen-anchored) by a delta;   |
//| chart price lines (SL/TP/NEWS) are left untouched.                |
//+------------------------------------------------------------------+
void MovePanelBy(int dx, int dy) {
    if (dx == 0 && dy == 0)
        return;
    const int total = ObjectsTotal(0);
    for (int i = 0; i < total; ++i) {
        const string nm = ObjectName(0, i);
        if (StringFind(nm, RC_PREFIX) != 0) continue;   // panel objects only
        if (StringFind(nm, "RC_SL_") == 0) continue;    // chart price lines - skip
        if (StringFind(nm, "RC_TP_") == 0) continue;
        if (StringFind(nm, "RC_NEWS_") == 0) continue;
        const long ot = ObjectGetInteger(0, nm, OBJPROP_TYPE);
        // P2 : include the logo bitmap + the copy OBJ_EDITs so they drag with the panel.
        if (ot != OBJ_RECTANGLE_LABEL && ot != OBJ_LABEL && ot != OBJ_BUTTON &&
            ot != OBJ_BITMAP_LABEL && ot != OBJ_EDIT) continue;
        const int ox = (int)ObjectGetInteger(0, nm, OBJPROP_XDISTANCE);
        const int oy = (int)ObjectGetInteger(0, nm, OBJPROP_YDISTANCE);
        ObjectSetInteger(0, nm, OBJPROP_XDISTANCE, ox + dx);
        ObjectSetInteger(0, nm, OBJPROP_YDISTANCE, oy + dy);
    }
    g_anchor_x += dx;
    g_anchor_y += dy;
    // P2 fix : keep ALL stored layout-Y globals in sync with the drag, else the
    // next refresh tick redraws these rows at a stale Y (X tracks via g_anchor_x,
    // but Y snapped back). g_recbar_y was already handled ; g_tfbar_y drives the
    // copy-lot boxes and g_footer_y drives the coloured info line.
    g_recbar_y += dy;
    g_tfbar_y  += dy;
    g_footer_y += dy;
}

void PersistAnchor(void) {
    GlobalVariableSet("RC_anchor_x", (double)g_anchor_x);
    GlobalVariableSet("RC_anchor_y", (double)g_anchor_y);
}

//+------------------------------------------------------------------+
//| B8 : recent-symbols quick-switch bar                             |
//|                                                                  |
//| List = up to 4 most-recently-traded symbols, rebuilt from open   |
//| positions + recent closed deals (newest first). The trade        |
//| history is the persistent source, so a fresh 5th symbol pushes   |
//| the oldest out automatically (FIFO). No GlobalVariable needed.   |
//+------------------------------------------------------------------+
void UpdateRecentSymbols(void) {
    string col[];
    ArrayResize(col, 0);
    // 1. Open positions first (currently active = most relevant).
    const int np = PositionsTotal();
    for (int i = np - 1; i >= 0 && ArraySize(col) < RC_MAX_RECENT_SYMS; --i) {
        const ulong t = PositionGetTicket(i);
        if (t == 0 || !PositionSelectByTicket(t)) continue;
        const string s = PositionGetString(POSITION_SYMBOL);
        bool dup = false;
        for (int k = 0; k < ArraySize(col); ++k) if (col[k] == s) { dup = true; break; }
        if (!dup) { const int n = ArraySize(col); ArrayResize(col, n + 1); col[n] = s; }
    }
    // 2. Recent closed deals (last 30 days), newest first, until 4 unique.
    if (HistorySelect(TimeCurrent() - 30 * 86400, TimeCurrent())) {
        const int nd = HistoryDealsTotal();
        for (int i = nd - 1; i >= 0 && ArraySize(col) < RC_MAX_RECENT_SYMS; --i) {
            const ulong t = HistoryDealGetTicket(i);
            if (t == 0) continue;
            if ((ENUM_DEAL_ENTRY)HistoryDealGetInteger(t, DEAL_ENTRY) != DEAL_ENTRY_IN) continue;
            const string s = HistoryDealGetString(t, DEAL_SYMBOL);
            if (s == "") continue;
            bool dup = false;
            for (int k = 0; k < ArraySize(col); ++k) if (col[k] == s) { dup = true; break; }
            if (!dup) { const int n = ArraySize(col); ArrayResize(col, n + 1); col[n] = s; }
        }
    }
    const int keep = MathMin(ArraySize(col), RC_MAX_RECENT_SYMS);
    ArrayResize(g_recent_syms, keep);
    for (int i = 0; i < keep; ++i) g_recent_syms[i] = col[i];
}

//+------------------------------------------------------------------+
//| LOT 4 : i18n table init + Tr() lookup. Parallel string arrays so   |
//| we don't depend on MQL5's struct-array-literal init quirks. Add a  |
//| new key here + an entry in each language array to extend coverage. |
//+------------------------------------------------------------------+
// G4 : append one translation row (EN / FR / ES). ASCII only - the existing
// table deliberately drops accents (REGLES, not REGLES with grave) to stay
// codepage-safe in MetaEditor, matching the clang/Antigravity ASCII rule.
void AddTr(const string k, const string en, const string fr, const string es) {
    const int n = ArraySize(g_i18n_keys);
    ArrayResize(g_i18n_keys, n + 1);
    ArrayResize(g_i18n_en,   n + 1);
    ArrayResize(g_i18n_fr,   n + 1);
    ArrayResize(g_i18n_es,   n + 1);
    g_i18n_keys[n] = k; g_i18n_en[n] = en; g_i18n_fr[n] = fr; g_i18n_es[n] = es;
}

void InitI18n(void) {
    ArrayResize(g_i18n_keys, 0);
    ArrayResize(g_i18n_en,   0);
    ArrayResize(g_i18n_fr,   0);
    ArrayResize(g_i18n_es,   0);
    // --- section headers ---
    AddTr("rules",    "RULES",          "RÈGLES",             "REGLAS");
    AddTr("open_pos", "OPEN POSITIONS", "POSITIONS OUVERTES", "POSICIONES ABIERTAS");
    // --- generic ---
    AddTr("on",  "ON",  "ON",  "ON");
    AddTr("off", "OFF", "OFF", "OFF");
    // --- settings popup ---
    AddTr("settings",    "SETTINGS",   "RÉGLAGES",  "AJUSTES");
    AddTr("tab_account", "Account",    "Compte",    "Cuenta");
    AddTr("tab_risk",    "Risk",       "Risque",    "Riesgo");
    AddTr("tab_display", "Display",    "Affichage", "Pantalla");
    AddTr("tab_alerts",  "Alerts",     "Alertes",   "Alertas");
    AddTr("set_phase",     "Phase :",              "Phase :",                "Fase :");
    AddTr("set_size",      "Size :",               "Taille :",               "Tamaño :");
    AddTr("set_acct_type", "Account type :",       "Type de compte :",       "Tipo de cuenta :");
    AddTr("set_addons",    "Add-ons :",            "Options :",              "Extras :");
    AddTr("set_personal_note", "Personal account - prop rules off.",
                               "Compte perso - règles prop off.",
                               "Cuenta personal - reglas prop off.");
    AddTr("set_maxparallel", "Max parallel :",        "Trades max :",          "Trades max :");
    AddTr("set_sl",          "SL distance % :",       "Distance SL % :",       "Distancia SL % :");
    AddTr("set_tp",          "TP distance % :",       "Distance TP % :",       "Distancia TP % :");
    AddTr("set_maxmargin",   "Max margin/trade % :",  "Marge max/trade % :",   "Margen máx/op % :");
    AddTr("set_maxrisk",     "Max risk/trade % :",    "Risque max/trade % :",  "Riesgo máx/op % :");
    // v1.4 : hover tooltips - explain each key param (unit + what it does).
    AddTr("tip_maxparallel",
          "How many trades you plan to hold at once. The SL budget is split across this count.",
          "Combien de trades tu comptes tenir en même temps. Le budget SL est réparti sur ce nombre.",
          "Cuántas operaciones prevés mantener a la vez. El presupuesto SL se reparte entre ellas.");
    AddTr("tip_sl",
          "Stop-loss distance, % of price. 1.0 = safest (locked in V1).",
          "Distance du stop-loss, % du prix. 1.0 = le plus sûr (verrouillé en V1).",
          "Distancia del stop-loss, % del precio. 1.0 = lo más seguro (fijo en V1).");
    AddTr("tip_tp",
          "Take-profit distance, % of price. 0.1 = scalping default.",
          "Distance du take-profit, % du prix. 0.1 = défaut scalping.",
          "Distancia del take-profit, % del precio. 0.1 = por defecto scalping.");
    AddTr("tip_maxmargin",
          "Max margin one trade may use, % of balance. FundedNext recommends 20-30%.",
          "Marge max qu'un seul trade peut utiliser, % du solde. FundedNext recommande 20-30%.",
          "Margen máx que una operación puede usar, % del saldo. FundedNext recomienda 20-30%.");
    AddTr("tip_maxrisk",
          "Max one trade may lose, % of balance. Your discipline ceiling.",
          "Perte max sur un seul trade, % du solde. Ton plafond de discipline.",
          "Pérdida máx en una operación, % del saldo. Tu límite de disciplina.");
    AddTr("tip_mviol",
          "Turn on after a margin violation : tightens the cumulative margin cap (2nd strike).",
          "À activer après une violation de marge : resserre le plafond de marge cumulée (2e sanction).",
          "Activar tras una violación de margen : ajusta el límite de margen acumulado (2ª sanción).");
    AddTr("tip_mcapviol",
          "Tightened cumulative margin cap after a violation (FundedNext 2nd strike = 30%).",
          "Plafond de marge cumulée resserré après violation (FundedNext 2e sanction = 30%).",
          "Límite de margen acumulado ajustado tras violación (FundedNext 2ª sanción = 30%).");
    AddTr("tip_rviol",
          "Turn on after a risk violation : tightens the cumulative risk cap (2nd strike).",
          "À activer après une violation de risque : resserre le plafond de risque cumulé (2e sanction).",
          "Activar tras una violación de riesgo : ajusta el límite de riesgo acumulado (2ª sanción).");
    AddTr("tip_rcapviol",
          "Tightened cumulative risk cap after a violation (FundedNext 2nd strike = 1%).",
          "Plafond de risque cumulé resserré après violation (FundedNext 2e sanction = 1%).",
          "Límite de riesgo acumulado ajustado tras violación (FundedNext 2ª sanción = 1%).");
    AddTr("tip_news_high",
          "Show HIGH-impact news on the chart (bars + countdown).",
          "Afficher les news HIGH sur le graphique (barres + compte à rebours).",
          "Mostrar noticias de ALTO impacto en el gráfico (barras + cuenta atrás).");
    AddTr("tip_news_med",
          "Also show MEDIUM-impact news (your prop firm may count these in its news window).",
          "Afficher aussi les news MOYEN (ta prop firm peut les compter dans sa fenêtre news).",
          "Mostrar también noticias de impacto MEDIO (tu prop firm puede contarlas en su ventana).");
    AddTr("set_theme",       "Theme :",               "Thème :",               "Tema :");
    AddTr("set_language",    "Language :",            "Langue :",              "Idioma :");
    AddTr("set_news",        "News on chart :",       "News graphique :",      "Noticias graf :");
    AddTr("set_news_high",   "News HIGH :",           "News HIGH :",           "Noticias ALTA :");
    AddTr("set_news_med",    "News MEDIUM :",         "News MOYEN :",          "Noticias MEDIA :");
    AddTr("set_comfort",     "Comfort scale :",       "Échelle confort :",     "Escala confort :");
    AddTr("set_discipline",  "Discipline lock :",     "Verrou discipline :",   "Bloqueo disciplina :");
    AddTr("set_sound",       "Sound alerts :",        "Alertes son :",         "Alertas sonido :");
    AddTr("set_telegram",    "Telegram alerts :",     "Alertes Telegram :",    "Alertas Telegram :");
    AddTr("set_strings_note","Token / chat / .wav : in Inputs.",
                             "Token / chat / .wav : dans Inputs.",
                             "Token / chat / .wav : en Inputs.");
    AddTr("set_note",   "Applies now + survives restart.",
                        "Applique de suite + persiste.",
                        "Se aplica ya + persiste.");
    AddTr("set_broker", "Broker (auto) :", "Courtier (auto) :", "Broker (auto) :");
    // --- account strip ---
    AddTr("acc",   "Acc",   "Cpt",   "Cta");
    AddTr("split", "Split", "Partage", "Reparto");
    AddTr("min_days_none", "Min days: 0 (No Min Days)", "Jours min: 0 (aucun)", "Días mín: 0 (ninguno)");
    AddTr("days_traded",   "Days traded",               "Jours tradés",         "Días operados");
    // --- spread / commission ---
    AddTr("spread", "Spr", "Spr", "Spr");
    AddTr("comm",   "Com", "Com", "Com");
    // --- rule row labels (keyed by g_rows[].key) ---
    AddTr("rule_margin_cum", "Cumulative Margin",      "Marge cumulée",       "Margen acumulado");
    AddTr("rule_margin_pt",  "Max lot allowed",        "Lot max autorisé",    "Lote máx permitido");
    AddTr("rule_risk_cum",   "Cumulative Open Risk",   "Risque ouvert cumulé","Riesgo abierto acum.");
    AddTr("rule_daily_dd",   "Daily DD",               "DD journalier",       "DD diario");
    AddTr("rule_overall_dd", "Overall DD",             "DD total",            "DD total");
    AddTr("rule_target",     "Profit Target",          "Objectif profit",     "Objetivo benef.");
    AddTr("rule_qs",         "Quick Strike Ratio",     "Ratio Quick Strike",  "Ratio Quick Strike");
    AddTr("rule_hyper",      "Hyperactivity (trades)", "Hyperactivité (trades)","Hiperactividad (ops)");
    AddTr("rule_news",       "News Window",            "Fenêtre news",        "Ventana noticias");
    AddTr("rule_newsstats",  "News Trades",            "Trades news",         "Ops noticias");
    AddTr("rule_msgs",       "Server msgs (orders)",   "Msgs serveur (ordres)","Msgs servidor (órdenes)");
    // --- verdict badge + clock ---
    AddTr("v_ontrack",   "ON TRACK",      "EN VOIE",        "EN RUMBO");
    AddTr("v_atrisk",    "AT RISK",       "À RISQUE",       "EN RIESGO");
    AddTr("v_violation", "VIOLATION",     "VIOLATION",      "VIOLACIÓN");
    AddTr("live",        "* LIVE",        "* LIVE",         "* LIVE");
    AddTr("weekend_hold","WEEKEND HOLD!", "TENUE WEEKEND!", "RETENER FINDE!");
    AddTr("flatten",     "  FLATTEN!",    "  FERMER!",      "  CERRAR!");
    // --- status chips ---
    AddTr("chip_ok",   "OK",   "OK",     "OK");
    AddTr("chip_warn", "WARN", "ALERTE", "ALERTA");
    AddTr("chip_red",  "RED",  "ROUGE",  "ROJO");
    AddTr("chip_na",   "--",   "--",     "--");
    // --- TF / recent bar ---
    AddTr("tf",       "TF:",       "TF:",       "TF:");
    AddTr("recent",   "Recent:",   "Récent:",   "Reciente:");
    AddTr("recenter", "Re-center", "Recentrer", "Recentrar");
    // --- discipline overlay ---
    AddTr("stop_trading", "STOP TRADING -- daily limit reached",
                          "STOP TRADING -- limite du jour atteinte",
                          "PARAR -- límite diario alcanzado");
    // --- footer descriptive words ---
    AddTr("f_bal",    "Bal",    "Solde",  "Saldo");
    AddTr("f_today",  "Today",  "Auj",    "Hoy");
    AddTr("f_profit", "Profit", "Profit", "Benef");
    AddTr("f_lot",    "Lot",    "Lot",    "Lote");
    AddTr("f_free",   "free",   "libre",  "libre");
    AddTr("f_cap",    "Cap",    "Cap",    "Cap");
    AddTr("f_risk",   "Risk",   "Risque", "Riesgo");
    AddTr("f_margin", "Margin", "Marge",  "Margen");
    // --- R4 : remaining panel-visible dynamic text ---
    AddTr("pos_lock", "LOCK",  "VERR",   "BLOQ");
    AddTr("pos_nosl", "NO SL", "SANS SL","SIN SL");
    AddTr("f_insuf",       "[insufficient margin]",       "[marge insuffisante]",        "[margen insuficiente]");
    AddTr("f_reduce",      "[reduce lot / tighten SL]",   "[réduire lot / resserrer SL]","[reducir lote / ajustar SL]");
    AddTr("f_belowmin",    "[below min]",                 "[sous min]",                  "[bajo min]");
    AddTr("f_marginbound", "[lot limited by free margin]","[lot limité par marge libre]","[lote limitado por margen libre]");
    AddTr("lot_unavail",   "Lot : symbol info unavailable","Lot : infos symbole indispo","Lote : info símbolo no disp.");
    AddTr("maxlot_na",      "n/a (margin unavailable)",     "n/a (marge indisponible)",    "n/a (margen no disponible)");
    AddTr("maxlot_belowmin","< broker min lot @",          "< lot min courtier @",        "< lote min broker @");
    AddTr("tag_marg", "marg", "marge", "margen");
    AddTr("tag_room", "room", "reste", "resto");
    AddTr("tag_free", "free", "libre", "libre");
    AddTr("used",     "used", "util",  "usado");
    AddTr("locked",   "locked","verr", "bloq");
    // --- V1.24 G1 discipline-lock ---
    AddTr("disc_selflock", "SELF-LOCKED -- left",        "AUTO-VERROU -- reste",       "AUTO-BLOQUEO -- queda");
    AddTr("disc_cooldown", "COOLDOWN -- losing streak",  "PAUSE -- série perdante",    "ENFRIAR -- racha perdedora");
    AddTr("disc_tilt",     "TILT : slow down",           "TILT : ralentis",            "TILT : frena");
    AddTr("disc_unlock",   "Unlock",                     "Déverrouiller",              "Desbloquear");
    AddTr("disc_unlock_confirm", "Click again to confirm","Reclique pour confirmer",   "Clic otra vez para confirmar");
    AddTr("set_selflock",  "Self-lock",                  "Auto-verrou",                "Auto-bloqueo");
    // --- V1.25 G4 : on-chart SL/TP recommendation annotations ---
    AddTr("sl_rec",        "SL rec",                     "SL reco",                    "SL reco");
    AddTr("tp_rec",        "TP rec",                     "TP reco",                    "TP reco");
    AddTr("sl_over_chip",  "SL>REC",                     "SL>REC",                     "SL>REC");
    AddTr("over",          "OVER",                       "DÉPASSE",                    "EXCEDE");
    // --- V1.26 G4 : Advanced (discipline) settings tab ---
    AddTr("tab_advanced",  "Advanced",                   "Avancé",                     "Avanzado");
    AddTr("set_tiltn",     "Tilt trades :",              "Trades tilt :",              "Trades tilt :");
    AddTr("set_tiltwin",   "Tilt window :",              "Fenêtre tilt :",             "Ventana tilt :");
    AddTr("set_cooldownn", "Cooldown losses :",          "Pertes pause :",             "Perdidas pausa :");
    AddTr("set_cooldownm", "Cooldown delay :",           "Délai pause :",              "Retraso pausa :");
    AddTr("set_selflockh", "Self-lock hours :",          "Heures auto-verrou :",       "Horas auto-bloqueo :");
    AddTr("set_comfortpct","Comfort pad :",              "Marge confort :",            "Margen confort :");
    // --- V1.27 : cascade (broker/type/split), violation caps, cycle date, refresh ---
    AddTr("set_broker_sel","Broker :",                   "Courtier :",                 "Broker :");
    AddTr("set_type",      "Type :",                     "Type :",                     "Tipo :");
    AddTr("set_split_sel", "Profit split :",             "Partage gains :",            "Reparto :");
    AddTr("set_mviol",     "Margin violation :",         "Violation marge :",          "Violación margen :");
    AddTr("set_mcapviol",  "Margin cap (viol.) :",       "Plafond marge (viol.) :",    "Tope margen (viol.) :");
    AddTr("set_rviol",     "Risk violation :",           "Violation risque :",         "Violación riesgo :");
    AddTr("set_rcapviol",  "Risk cap (viol.) :",         "Plafond risque (viol.) :",   "Tope riesgo (viol.) :");
    AddTr("set_cycyear",   "Cycle year :",               "Année cycle :",              "Año ciclo :");
    AddTr("set_cycmonth",  "Cycle month :",              "Mois cycle :",               "Mes ciclo :");
    AddTr("set_cycday",    "Cycle day :",                "Jour cycle :",               "Dia ciclo :");
    AddTr("set_refreshms", "Refresh (ms) :",             "Rafraîchir (ms) :",          "Refresco (ms) :");
    AddTr("pos_click_tip", "Click to switch chart to this symbol",
                           "Cliquer pour afficher ce symbole",
                           "Clic para cambiar a este símbolo");
    // --- V1.28 : footer add-ons label + cycle-date header ---
    AddTr("addons_lbl",    "Add-ons:",                   "Options:",                   "Extras:");
    AddTr("addons_none",   "none",                       "aucune",                     "ninguna");
    AddTr("set_cycle",     "Cycle start :",              "Début cycle :",              "Inicio ciclo :");
    AddTr("kill_tip",      "Remove RiskCockpit from this chart",
                           "Retirer RiskCockpit du graphique",
                           "Quitar RiskCockpit del gráfico");
    // --- V1.29 F : copy-lot captions + localized tooltips ---
    AddTr("cap_sug",       "Sug",  "Sug",  "Sug");
    AddTr("cap_max",       "Max",  "Max",  "Max");
    AddTr("copy_sug_tip",  "Suggested lot - click + Ctrl+C",
                           "Lot suggéré - cliquer + Ctrl+C",
                           "Lote sugerido - clic + Ctrl+C");
    AddTr("copy_max_tip",  "Max lot - click + Ctrl+C",
                           "Lot max - cliquer + Ctrl+C",
                           "Lote máx - clic + Ctrl+C");
    // --- V1.29 H(a) : cross-symbol floating P&L readout ---
    AddTr("be_pl",         "Total P&L",  "P&L total",  "P&L total");
    AddTr("be_toflat",     "to flat",    "pour solder","para saldar");
    // --- V1.29 I/J : Personal type + risk-tools master ---
    AddTr("set_personal_type", "Personal type :", "Type perso :",   "Tipo perso :");
    AddTr("set_risktools",     "Risk tools :",    "Outils risque :","Herram. riesgo :");
}

string Tr(const string key) {
    for (int i = 0; i < ArraySize(g_i18n_keys); ++i) {
        if (g_i18n_keys[i] == key) {
            switch (g_lang) {
                case 1: return g_i18n_fr[i];
                case 2: return g_i18n_es[i];
                default: return g_i18n_en[i];
            }
        }
    }
    return key; // fallback : show the raw key if no translation exists yet
}

//+------------------------------------------------------------------+
//| LOT 4 : timeframe quick-switch bar (M1 / M5 / M15 / M30 / H1 /   |
//| H4 / D1). Sits just above the recent-symbols bar. Click ->        |
//| ChartSetSymbolPeriod(0, _Symbol, ...) on the active chart, which  |
//| triggers OnDeinit + OnInit (chart-change re-init) - clean.        |
//+------------------------------------------------------------------+
void DrawTimeframeBar(int x, int y, int w) {
    DrawRect(RC_PREFIX + "tfbar_bg", x, y, w, InpRowHeight, g_theme.surface, g_theme.border, 0);
    DrawLabel(RC_PREFIX + "tfbar_lbl", x + RC_PAD, y + 5, Tr("tf"), g_theme.text_dim, RC_FONT_SIZE - 1);
    string tfs[9];
    tfs[0]="M1"; tfs[1]="M5"; tfs[2]="M15"; tfs[3]="M30"; tfs[4]="H1";
    tfs[5]="H4"; tfs[6]="D1"; tfs[7]="W1";  tfs[8]="MN1";              // P3 : + week + month
    ENUM_TIMEFRAMES tfvals[9];
    tfvals[0]=PERIOD_M1; tfvals[1]=PERIOD_M5; tfvals[2]=PERIOD_M15; tfvals[3]=PERIOD_M30; tfvals[4]=PERIOD_H1;
    tfvals[5]=PERIOD_H4; tfvals[6]=PERIOD_D1; tfvals[7]=PERIOD_W1;  tfvals[8]=PERIOD_MN1;
    const int btn_w = 33; // P3 : compact so 9 timeframes fit
    const int btn_h = InpRowHeight - 6;
    const int x0    = x + 30;
    const ENUM_TIMEFRAMES cur = (ENUM_TIMEFRAMES)ChartPeriod(0);
    for (int i = 0; i < 9; ++i) {
        const int bx = x0 + i * (btn_w + 2);
        const bool active = (tfvals[i] == cur);
        // v1.4.1 R3 : the segment FACE is painted in RepaintCanvas ; here we place the
        // centered text label on top + register the CLICK zone (absolute pixels).
        const string bid = RC_PREFIX + "tf_" + tfs[i];
        if (ObjectFind(0, bid) >= 0) ObjectDelete(0, bid); // drop any pre-R3 OBJ_BUTTON
        const string lid = RC_PREFIX + "tflab_" + tfs[i];
        DrawLabel(lid, bx + btn_w / 2, y + 3 + btn_h / 2, tfs[i],
                  active ? g_theme.bg : g_theme.text, RC_FONT_SIZE - 1, RC_FONT_UI);
        ObjectSetInteger(0, lid, OBJPROP_ANCHOR, ANCHOR_CENTER);
        HitAdd(bx, y + 3, bx + btn_w, y + 3 + btn_h, "tf", i);
    }
    // LOT 5 : "BE" toggle on the right side - show / hide breakeven lines on
    // each open position of the current chart symbol (draggable for manual adjust).
    const string be_id = RC_PREFIX + "be";
    if (ObjectFind(0, be_id) < 0) ObjectCreate(0, be_id, OBJ_BUTTON, 0, 0, 0);
    ObjectSetInteger(0, be_id, OBJPROP_XDISTANCE, x + w - 52);
    ObjectSetInteger(0, be_id, OBJPROP_YDISTANCE, y + 3);
    ObjectSetInteger(0, be_id, OBJPROP_XSIZE, 44);
    ObjectSetInteger(0, be_id, OBJPROP_YSIZE, btn_h);
    ObjectSetString(0, be_id, OBJPROP_TEXT, "BE");
    ObjectSetString(0, be_id, OBJPROP_FONT, RC_FONT_UI);
    ObjectSetInteger(0, be_id, OBJPROP_FONTSIZE, RC_FONT_SIZE - 1);
    ObjectSetInteger(0, be_id, OBJPROP_COLOR,        g_be_visible ? g_theme.bg       : g_theme.text);
    ObjectSetInteger(0, be_id, OBJPROP_BGCOLOR,      g_be_visible ? g_theme.accent2  : g_theme.surface_hi);
    ObjectSetInteger(0, be_id, OBJPROP_BORDER_COLOR, g_theme.accent2);
    ObjectSetInteger(0, be_id, OBJPROP_CORNER, CORNER_LEFT_UPPER);
    ObjectSetInteger(0, be_id, OBJPROP_STATE, false);
    ObjectSetInteger(0, be_id, OBJPROP_SELECTABLE, false);
    ObjectSetInteger(0, be_id, OBJPROP_HIDDEN, true);
    ObjectSetInteger(0, be_id, OBJPROP_ZORDER, 100); // LOT B
    ObjectSetString(0, be_id, OBJPROP_TOOLTIP, "Show / hide breakeven lines (draggable)");
}

//+------------------------------------------------------------------+
//| LOT 5 : Breakeven lines = OBJ_HLINE at each open position's       |
//| price_open on the CURRENT chart symbol. Lines are SELECTABLE so   |
//| the user can drag them manually ; the companion EA (V2) executes  |
//| the actual move-to-BE on the broker side. Named "RC_BE_<ticket>"  |
//| so DestroyAllObjects on deinit catches them.                      |
//+------------------------------------------------------------------+
void ClearBreakevenLines(void) {
    ObjectsDeleteAll(0, "RC_BE_");
}

//+------------------------------------------------------------------+
//| LOT D B-BE-UNIFIED : compute the basket-unified breakeven for     |
//| `symbol`. Per Agent D math spec :                                 |
//|   K = SYMBOL_TRADE_TICK_VALUE / SYMBOL_TRADE_TICK_SIZE            |
//|   Δ = Σ side_i * vol_i      (net signed exposure, lots)           |
//|   W = Σ side_i * vol_i * p_i (signed lot-weighted entry)          |
//|   F = Σ (swap_i + comm_i)   (booked fees, usually negative)       |
//| Δ ≠ 0  ->  BE price P* = (K·W − F) / (K·Δ)                        |
//| Δ ≈ 0  ->  perfectly hedged, P cancels out. Locked P&L = F − K·W. |
//| Tolerance for Δ uses 0.5 * SYMBOL_VOLUME_STEP for FP robustness.  |
//+------------------------------------------------------------------+
bool ComputeBasketBreakeven(const string symbol,
                            double &out_be_price,
                            bool   &out_is_hedged_flat,
                            double &out_flat_pnl,
                            string &out_reason) {
    out_be_price       = 0.0;
    out_is_hedged_flat = false;
    out_flat_pnl       = 0.0;
    out_reason         = "";

    const double tv = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE);
    const double ts = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_SIZE);
    if (tv <= 0.0 || ts <= 0.0) {
        out_reason = "tick_value or tick_size unavailable";
        return false;
    }
    const double K = tv / ts;

    double delta = 0.0; // Σ s_i * v_i
    double W     = 0.0; // Σ s_i * v_i * p_i
    double F     = 0.0; // Σ swap_i + comm_i
    int matched  = 0;

    const int n = PositionsTotal();
    for (int i = 0; i < n; ++i) {
        const ulong ticket = PositionGetTicket(i);
        if (ticket == 0 || !PositionSelectByTicket(ticket)) continue;
        if (PositionGetString(POSITION_SYMBOL) != symbol) continue;
        const double v = PositionGetDouble(POSITION_VOLUME);
        const double p = PositionGetDouble(POSITION_PRICE_OPEN);
        const int type = (int)PositionGetInteger(POSITION_TYPE);
        const double s = (type == POSITION_TYPE_BUY) ? 1.0 : -1.0;
        const double swap = PositionGetDouble(POSITION_SWAP);
        // POSITION_COMMISSION is deprecated and unreliable for open positions.
        // Sum DEAL_COMMISSION from this position's deal history instead.
        double comm = 0.0;
        const long pos_id = PositionGetInteger(POSITION_IDENTIFIER);
        if (HistorySelectByPosition(pos_id)) {
            const int dn = HistoryDealsTotal();
            for (int di = 0; di < dn; ++di) {
                const ulong dt = HistoryDealGetTicket(di);
                if (dt == 0) continue;
                comm += HistoryDealGetDouble(dt, DEAL_COMMISSION);
            }
        }
        delta += s * v;
        W     += s * v * p;
        F     += swap + comm;
        ++matched;
    }
    if (matched == 0) {
        out_reason = "no open positions on " + symbol;
        return false;
    }

    const double step = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);
    const double tol  = (step > 0.0 ? step * 0.5 : 1e-6);
    if (MathAbs(delta) < tol) {
        out_is_hedged_flat = true;
        out_flat_pnl       = F - K * W;
        out_reason         = "perfectly hedged basket";
        return false;
    }
    out_be_price = (K * W - F) / (K * delta);
    return true;
}

//+------------------------------------------------------------------+
//| LOT D : Breakeven now draws ONE basket-unified HLine at the price |
//| where Σ P&L = 0 (was : one HLine per position at price_open).     |
//| Δ = 0 (perfectly hedged) -> no line, a label shows the locked     |
//| P&L instead. Companion EA (V2) will execute the move-to-BE.       |
//+------------------------------------------------------------------+
// V1.29 H(a) : distinct symbols among open positions (a POSITIONS loop, not a
// deals loop -> cheap). >1 means the per-symbol basket BE line below does not
// flatten the whole account.
int CountPositionSymbols(void) {
    string seen[];
    int n = 0;
    const int total = PositionsTotal();
    for (int i = 0; i < total; ++i) {
        const string s = PositionGetSymbol(i);
        if (s == "") continue;
        bool dup = false;
        for (int j = 0; j < n; ++j) if (seen[j] == s) { dup = true; break; }
        if (!dup) { ArrayResize(seen, n + 1); seen[n] = s; n++; }
    }
    return n;
}

void DrawBreakevenLines(void) {
    ClearBreakevenLines();
    if (!g_be_visible)
        return;
    double be_price;
    bool   is_hedged;
    double flat_pnl;
    string reason;
    const bool ok = ComputeBasketBreakeven(_Symbol, be_price, is_hedged, flat_pnl, reason);
    if (ok) {
        const string id = "RC_BE_BASKET";
        if (ObjectFind(0, id) < 0)
            ObjectCreate(0, id, OBJ_HLINE, 0, 0, be_price);
        ObjectSetDouble(0, id, OBJPROP_PRICE, be_price);
        ObjectSetInteger(0, id, OBJPROP_COLOR, g_theme.accent2);
        ObjectSetInteger(0, id, OBJPROP_STYLE, STYLE_DASH);
        ObjectSetInteger(0, id, OBJPROP_WIDTH, 2);
        ObjectSetInteger(0, id, OBJPROP_SELECTABLE, true);
        ObjectSetInteger(0, id, OBJPROP_HIDDEN, true);
        ObjectSetString(0, id, OBJPROP_TOOLTIP,
                        "Basket Breakeven @ " + DoubleToString(be_price, _Digits) +
                        " (close ALL here -> total P&L = 0 incl swap + commission)");
    } else if (is_hedged) {
        const string id = "RC_BE_HEDGED";
        if (ObjectFind(0, id) < 0)
            ObjectCreate(0, id, OBJ_LABEL, 0, 0, 0);
        ObjectSetInteger(0, id, OBJPROP_XDISTANCE, 12);
        ObjectSetInteger(0, id, OBJPROP_YDISTANCE, 30);
        ObjectSetInteger(0, id, OBJPROP_CORNER, CORNER_RIGHT_LOWER);
        ObjectSetString(0, id, OBJPROP_TEXT,
                        "Basket perfectly hedged. Locked P&L : $" + DoubleToString(flat_pnl, 2));
        ObjectSetInteger(0, id, OBJPROP_COLOR, g_theme.warn);
        ObjectSetInteger(0, id, OBJPROP_FONTSIZE, 11);
        ObjectSetString(0, id, OBJPROP_FONT, RC_FONT_UI);
        ObjectSetInteger(0, id, OBJPROP_SELECTABLE, false);
        ObjectSetInteger(0, id, OBJPROP_HIDDEN, true);
    }
    // V1.29 H(a) : cross-symbol readout. When positions span >1 symbol, the
    // per-symbol BE line above does NOT flatten the account -> show the TOTAL
    // floating P&L (profit+swap, all symbols) + the cash to flatten everything.
    // (H(b) = a portfolio BE PRICE line is deferred to the weekly patch.)
    if (CountPositionSymbols() > 1) {
        const double total_float = SumFloatingPnL();
        const string pid = "RC_BE_PORTFOLIO_LBL";
        if (ObjectFind(0, pid) < 0) ObjectCreate(0, pid, OBJ_LABEL, 0, 0, 0);
        ObjectSetInteger(0, pid, OBJPROP_XDISTANCE, 12);
        ObjectSetInteger(0, pid, OBJPROP_YDISTANCE, 48);
        ObjectSetInteger(0, pid, OBJPROP_CORNER, CORNER_RIGHT_LOWER);
        ObjectSetString(0, pid, OBJPROP_TEXT,
                        Tr("be_pl") + " $" + DoubleToString(total_float, 2) + "   $" +
                        DoubleToString(-total_float, 2) + " " + Tr("be_toflat"));
        ObjectSetInteger(0, pid, OBJPROP_COLOR, (total_float >= 0.0 ? g_theme.ok : g_theme.red));
        ObjectSetInteger(0, pid, OBJPROP_FONTSIZE, 10);
        ObjectSetString(0, pid, OBJPROP_FONT, RC_FONT_UI);
        ObjectSetInteger(0, pid, OBJPROP_SELECTABLE, false);
        ObjectSetInteger(0, pid, OBJPROP_HIDDEN, true);
    }
    // else : empty basket -> nothing drawn (no positions on this symbol).
}

void DrawRecentSymbolsBar(int x, int y, int w) {
    DrawRect(RC_PREFIX + "recbar_bg", x, y, w, InpRowHeight, g_theme.surface, g_theme.border, 0);
    DrawLabel(RC_PREFIX + "recbar_lbl", x + RC_PAD, y + 5, Tr("recent"), g_theme.text_dim, RC_FONT_SIZE - 1);
    const int btn_w = (g_eff_comfort ? 72 : 96); // FIX 6 : narrower when the Re-center button is shown
    const int btn_h = InpRowHeight - 6;
    const int x0 = x + 62;
    for (int i = 0; i < RC_MAX_RECENT_SYMS; ++i) {
        const string id = RC_PREFIX + "recsym_" + IntegerToString(i);
        if (i < ArraySize(g_recent_syms)) {
            const int bx = x0 + i * (btn_w + 6);
            if (ObjectFind(0, id) < 0)
                ObjectCreate(0, id, OBJ_BUTTON, 0, 0, 0);
            ObjectSetInteger(0, id, OBJPROP_XDISTANCE, bx);
            ObjectSetInteger(0, id, OBJPROP_YDISTANCE, y + 3);
            ObjectSetInteger(0, id, OBJPROP_XSIZE, btn_w);
            ObjectSetInteger(0, id, OBJPROP_YSIZE, btn_h);
            ObjectSetString(0, id, OBJPROP_TEXT, g_recent_syms[i]);
            ObjectSetString(0, id, OBJPROP_FONT, RC_FONT_UI);
            ObjectSetInteger(0, id, OBJPROP_FONTSIZE, RC_FONT_SIZE - 1);
            ObjectSetInteger(0, id, OBJPROP_COLOR, g_theme.text);
            ObjectSetInteger(0, id, OBJPROP_BGCOLOR, g_theme.surface_hi);
            ObjectSetInteger(0, id, OBJPROP_BORDER_COLOR, g_theme.accent);
            ObjectSetInteger(0, id, OBJPROP_CORNER, CORNER_LEFT_UPPER);
            ObjectSetInteger(0, id, OBJPROP_STATE, false);
            ObjectSetInteger(0, id, OBJPROP_SELECTABLE, false);
            ObjectSetInteger(0, id, OBJPROP_HIDDEN, true);
            ObjectSetInteger(0, id, OBJPROP_ZORDER, 100); // LOT B
            ObjectSetString(0, id, OBJPROP_TOOLTIP, "Switch chart to " + g_recent_syms[i]);
        } else {
            ObjectDelete(0, id); // empty slot
        }
    }
    // FIX 6 : "Re-center" button (shown only with the comfort scale on) - re-applies
    // the padded CHART_FIXED_MIN/MAX on demand. Sits just left of the Auto-SL button.
    const string rc_id = RC_PREFIX + "recenter";
    if (g_eff_comfort) {
        if (ObjectFind(0, rc_id) < 0) ObjectCreate(0, rc_id, OBJ_BUTTON, 0, 0, 0);
        ObjectSetInteger(0, rc_id, OBJPROP_XDISTANCE, x + w - 172);
        ObjectSetInteger(0, rc_id, OBJPROP_YDISTANCE, y + 3);
        ObjectSetInteger(0, rc_id, OBJPROP_XSIZE, 74);
        ObjectSetInteger(0, rc_id, OBJPROP_YSIZE, InpRowHeight - 6);
        ObjectSetString(0, rc_id, OBJPROP_TEXT, Tr("recenter"));
        ObjectSetString(0, rc_id, OBJPROP_FONT, RC_FONT_UI);
        ObjectSetInteger(0, rc_id, OBJPROP_FONTSIZE, RC_FONT_SIZE - 2);
        ObjectSetInteger(0, rc_id, OBJPROP_COLOR, g_theme.text);
        ObjectSetInteger(0, rc_id, OBJPROP_BGCOLOR, g_theme.surface_hi);
        ObjectSetInteger(0, rc_id, OBJPROP_BORDER_COLOR, g_theme.accent);
        ObjectSetInteger(0, rc_id, OBJPROP_STATE, false);
        ObjectSetInteger(0, rc_id, OBJPROP_CORNER, CORNER_LEFT_UPPER);
        ObjectSetInteger(0, rc_id, OBJPROP_SELECTABLE, false);
        ObjectSetInteger(0, rc_id, OBJPROP_HIDDEN, true);
        ObjectSetInteger(0, rc_id, OBJPROP_ZORDER, 100); // LOT B
        ObjectSetString(0, rc_id, OBJPROP_TOOLTIP, "Re-center the chart with comfort padding");
    } else {
        ObjectDelete(0, rc_id);
    }

    // B10 : DISABLED "Auto-SL" toggle. An indicator CANNOT place/modify orders -
    // the real auto-SL ships with the companion RiskCockpit EA. Greyed out,
    // click is a no-op, full reason in the hover tooltip.
    const string asl_id = RC_PREFIX + "autosl";
    if (ObjectFind(0, asl_id) < 0) ObjectCreate(0, asl_id, OBJ_BUTTON, 0, 0, 0);
    ObjectSetInteger(0, asl_id, OBJPROP_XDISTANCE, x + w - 92);
    ObjectSetInteger(0, asl_id, OBJPROP_YDISTANCE, y + 3);
    ObjectSetInteger(0, asl_id, OBJPROP_XSIZE, 84);
    ObjectSetInteger(0, asl_id, OBJPROP_YSIZE, InpRowHeight - 6);
    ObjectSetString(0, asl_id, OBJPROP_TEXT, "Auto-SL OFF");
    ObjectSetString(0, asl_id, OBJPROP_FONT, RC_FONT_UI);
    ObjectSetInteger(0, asl_id, OBJPROP_FONTSIZE, RC_FONT_SIZE - 2);
    ObjectSetInteger(0, asl_id, OBJPROP_COLOR, g_theme.text_dim);
    ObjectSetInteger(0, asl_id, OBJPROP_BGCOLOR, g_theme.bg_section);
    ObjectSetInteger(0, asl_id, OBJPROP_BORDER_COLOR, g_theme.text_dim);
    ObjectSetInteger(0, asl_id, OBJPROP_STATE, false);
    ObjectSetInteger(0, asl_id, OBJPROP_CORNER, CORNER_LEFT_UPPER);
    ObjectSetInteger(0, asl_id, OBJPROP_SELECTABLE, false);
    ObjectSetInteger(0, asl_id, OBJPROP_HIDDEN, true);
    ObjectSetInteger(0, asl_id, OBJPROP_ZORDER, 100); // LOT B
    ObjectSetString(0, asl_id, OBJPROP_TOOLTIP,
                    "Requires RiskCockpit EA (coming soon) - an indicator cannot place orders.");
}

//+------------------------------------------------------------------+
//| Post-violation effective caps (B7)                               |
//|                                                                  |
//| When the corresponding violation flag is active, the cumulative  |
//| cap drops to the tightened value (FN 2nd-strike : margin 30 %,   |
//| risk 1 %). Otherwise the profile's base cap is used. ALL meters, |
//| budgets and SL-line allocations route through these accessors so |
//| toggling a checkbox instantly re-tightens the whole panel.       |
//+------------------------------------------------------------------+
double EffectiveMarginCap(void) {
    if (g_margin_violation_active && g_eff_margin_cap_viol > 0.0)
        return g_eff_margin_cap_viol; // V1.27 : runtime-editable (was InpMarginCapViolated)
    return g_profile.margin_max_cumulative_pct;
}

double EffectiveRiskCap(void) {
    if (g_risk_violation_active && g_eff_risk_cap_viol > 0.0)
        return g_eff_risk_cap_viol; // V1.27 : runtime-editable (was InpRiskCapViolated)
    return g_profile.open_risk_max_cumulative_pct;
}

//+------------------------------------------------------------------+
//| FIX 4 (V1.0.1) : only real funded-money accounts (Funded +        |
//| Instant) carry FundedNext's 2nd-strike restrictions (margin 30 %, |
//| risk 1 %). Challenge phases just fail the objective; Free Trial / |
//| Free Competition are demo. The violation toggles - and any        |
//| tightened cap - are therefore gated to these phases.              |
//+------------------------------------------------------------------+
bool ProfileCanBeRestricted(void) {
    const ENUM_FN_PLAN p = g_profile.plan_id;
    // Stellar Instant is always real funded money -> can be restricted.
    if (p == FN_PLAN_STELLAR_INSTANT)
        return true;
    // 1-Step / 2-Step / Lite carry the 2nd-strike caps only in the FUNDED phase.
    // NOTE : Free Trial / Free Competition reuse phase_id = FN_PHASE_FUNDED but are
    // DEMO accounts, and Futures use the CME model - none of them have FN's CFD
    // 2nd-strike restriction, so they must be excluded by plan (not phase alone).
    if (p == FN_PLAN_STELLAR_1STEP || p == FN_PLAN_STELLAR_2STEP || p == FN_PLAN_STELLAR_LITE)
        return (g_profile.phase_id == FN_PHASE_FUNDED);
    return false; // Futures placeholders + Free Trial + Free Competition
}

void PersistViolationFlags(void) {
    GlobalVariableSet("RC_margin_violation", g_margin_violation_active ? 1.0 : 0.0);
    GlobalVariableSet("RC_risk_violation", g_risk_violation_active ? 1.0 : 0.0);
}

//+------------------------------------------------------------------+
//| G3 settings popup : in-panel switcher for language / theme / prop |
//|                                                                  |
//| Click the [S] button next to the title -> a translucent overlay   |
//| floats on top of the panel with rows of buttons. Changes apply    |
//| immediately + are persisted in GlobalVariable (survive reattach). |
//| Rationale : the user wanted these without re-opening MT5 Inputs.  |
//+------------------------------------------------------------------+
void DrawSetButton(const string id, int x, int y, int w, int h, const string text) {
    if (ObjectFind(0, id) < 0)
        ObjectCreate(0, id, OBJ_BUTTON, 0, 0, 0);
    ObjectSetInteger(0, id, OBJPROP_XDISTANCE, x);
    ObjectSetInteger(0, id, OBJPROP_YDISTANCE, y);
    ObjectSetInteger(0, id, OBJPROP_XSIZE, w);
    ObjectSetInteger(0, id, OBJPROP_YSIZE, h);
    ObjectSetString(0, id, OBJPROP_TEXT, text);
    ObjectSetString(0, id, OBJPROP_FONT, RC_FONT_UI);
    ObjectSetInteger(0, id, OBJPROP_FONTSIZE, RC_FONT_SIZE);
    ObjectSetInteger(0, id, OBJPROP_COLOR, g_theme.text);
    ObjectSetInteger(0, id, OBJPROP_BGCOLOR, g_theme.surface_hi);      // premium (v1.4) : raised control
    ObjectSetInteger(0, id, OBJPROP_BORDER_COLOR, g_theme.border_hi);
    ObjectSetInteger(0, id, OBJPROP_CORNER, CORNER_LEFT_UPPER);
    ObjectSetInteger(0, id, OBJPROP_STATE, false);
    ObjectSetInteger(0, id, OBJPROP_SELECTABLE, false);
    ObjectSetInteger(0, id, OBJPROP_HIDDEN, true);
    // G1 : 260 = above the modal cover (240) + overlay labels (250) so the
    // settings buttons always win click routing while the popup is open.
    ObjectSetInteger(0, id, OBJPROP_ZORDER, 260);
}

void HighlightSetButton(const string id, bool active) {
    ObjectSetInteger(0, id, OBJPROP_BGCOLOR, active ? g_theme.accent : g_theme.surface_hi);
    ObjectSetInteger(0, id, OBJPROP_COLOR,   active ? g_theme.bg     : g_theme.text);
}

// G2/G4 : an overlay label at ZORDER 250 (between the modal cover 240 and the
// buttons 260). Free-standing helper so every row stays one call.
void SetLbl(const string id, int x, int y, const string t, color c) {
    DrawLabel(id, x, y, t, c, RC_FONT_SIZE);
    ObjectSetInteger(0, id, OBJPROP_ZORDER, 250);
}
// A labelled ON/OFF toggle button (60 px). The id encodes the setting.
void SetToggleBtn(const string id, int x, int y, bool on) {
    DrawSetButton(id, x, y, 60, 20, on ? Tr("on") : Tr("off"));
    HighlightSetButton(id, on);
}
// A [-] value [+] stepper. id_base+"_dn" / id_base+"_up" are the click targets.
void SetStepper(const string id_base, int x, int y, const string value_text) {
    DrawSetButton(id_base + "_dn", x, y, 22, 20, "-");
    SetLbl(id_base + "_val", x + 28, y + 3, value_text, g_theme.accent);
    DrawSetButton(id_base + "_up", x + 96, y, 22, 20, "+");
}
// Context-aware helpers : which option groups are relevant for the plan/broker.
bool PlanIsPersonal(void)  { return EffectivePlan() == FN_PLAN_PERSONAL; }
bool PlanIsFundedNext(void) {
    const ENUM_FN_PLAN p = EffectivePlan();
    return (p == FN_PLAN_STELLAR_1STEP || p == FN_PLAN_STELLAR_2STEP ||
            p == FN_PLAN_STELLAR_LITE  || p == FN_PLAN_STELLAR_INSTANT ||
            p == FN_PLAN_FREE_TRIAL    || p == FN_PLAN_FREE_COMPETITION);
}
bool PlanHasPhases(void) {
    const ENUM_FN_PLAN p = EffectivePlan();
    return (p == FN_PLAN_STELLAR_1STEP || p == FN_PLAN_STELLAR_2STEP ||
            p == FN_PLAN_STELLAR_LITE  || p == FN_PLAN_FTMO_2STEP);
}

//+------------------------------------------------------------------+
//| V1.27 CASCADE : broker (vendor) -> type (plan) -> size, valid     |
//| combinations only. Vendor is DERIVED from the plan (no separate   |
//| persistent state), so broker / type steppers can never desync.    |
//| Lives in the .mq5 (not the catalog) to keep the feature self-     |
//| contained and the Coordinator-owned catalog untouched.            |
//+------------------------------------------------------------------+
int VendorOfPlan(const ENUM_FN_PLAN p) {
    switch (p) {
        case FN_PLAN_FTMO_2STEP:   return 1; // FTMO
        case FN_PLAN_E8_8PCT:      return 2; // E8 Markets
        case FN_PLAN_THE5ERS_HIGH: return 3; // The5ers
        case FN_PLAN_MFF_RAPID:    return 4; // SeacrestFunded (ex-MyFundedFX)
        case FN_PLAN_PERSONAL:     return 5; // Personal / Broker
    }
    return 0; // FundedNext (Stellar 1/2-Step/Lite/Instant + Futures + Free*)
}
string VendorName(const int v) {
    switch (v) {
        case 1: return "FTMO";
        case 2: return "E8 Markets";
        case 3: return "The5ers";
        case 4: return "SeacrestFunded";
        case 5: return "Personal / Broker";
    }
    return "FundedNext";
}
// Ordered list of the user-selectable plans (types) for a vendor. The non-MT5
// Futures plans are intentionally excluded from the cascade.
int PlansForVendor(const int v, ENUM_FN_PLAN &out[]) {
    if (v == 1) { ArrayResize(out, 1); out[0] = FN_PLAN_FTMO_2STEP;   return 1; }
    if (v == 2) { ArrayResize(out, 1); out[0] = FN_PLAN_E8_8PCT;      return 1; }
    if (v == 3) { ArrayResize(out, 1); out[0] = FN_PLAN_THE5ERS_HIGH; return 1; }
    if (v == 4) { ArrayResize(out, 1); out[0] = FN_PLAN_MFF_RAPID;    return 1; }
    if (v == 5) { ArrayResize(out, 1); out[0] = FN_PLAN_PERSONAL;     return 1; }
    ArrayResize(out, 6); // FundedNext
    out[0] = FN_PLAN_STELLAR_1STEP; out[1] = FN_PLAN_STELLAR_2STEP;
    out[2] = FN_PLAN_STELLAR_LITE;  out[3] = FN_PLAN_STELLAR_INSTANT;
    out[4] = FN_PLAN_FREE_TRIAL;    out[5] = FN_PLAN_FREE_COMPETITION;
    return 6;
}
// Legal account sizes (USD) per plan. Mirrors each firm's published menu so a
// FundedNext type can show 6K/15K while FTMO/E8/Seacrest start at 10K, etc.
int ValidSizesForPlan(const ENUM_FN_PLAN p, double &out[]) {
    switch (p) {
        case FN_PLAN_STELLAR_1STEP:
        case FN_PLAN_STELLAR_2STEP:
        case FN_PLAN_FREE_TRIAL:
        case FN_PLAN_FREE_COMPETITION:
            ArrayResize(out, 6);
            out[0]=6000; out[1]=15000; out[2]=25000; out[3]=50000; out[4]=100000; out[5]=200000;
            return 6;
        case FN_PLAN_STELLAR_LITE:
            ArrayResize(out, 5);
            out[0]=5000; out[1]=25000; out[2]=50000; out[3]=100000; out[4]=200000;
            return 5;
        case FN_PLAN_STELLAR_INSTANT:
            ArrayResize(out, 4);
            out[0]=5000; out[1]=15000; out[2]=25000; out[3]=50000;
            return 4;
        case FN_PLAN_FTMO_2STEP:
        case FN_PLAN_E8_8PCT:
        case FN_PLAN_MFF_RAPID:
            ArrayResize(out, 5);
            out[0]=10000; out[1]=25000; out[2]=50000; out[3]=100000; out[4]=200000;
            return 5;
        case FN_PLAN_THE5ERS_HIGH:
            ArrayResize(out, 5);
            out[0]=5000; out[1]=10000; out[2]=25000; out[3]=50000; out[4]=100000;
            return 5;
        case FN_PLAN_PERSONAL:
            // Personal/demo : Auto (real balance) + 5K..50K by 5K, then 100K, 200K.
            ArrayResize(out, 13);
            out[0]=0;      // 0 = "Auto" -> use the real account balance (item 7)
            out[1]=5000;   out[2]=10000;  out[3]=15000;  out[4]=20000;  out[5]=25000;
            out[6]=30000;  out[7]=35000;  out[8]=40000;  out[9]=45000;  out[10]=50000;
            out[11]=100000; out[12]=200000;
            return 13;
    }
    // Truly-unknown plan fallback : the standard preset list.
    ArrayResize(out, 8);
    out[0]=5000; out[1]=6000; out[2]=10000; out[3]=15000;
    out[4]=25000; out[5]=50000; out[6]=100000; out[7]=200000;
    return 8;
}
// If the current size isn't legal for the plan, snap it to that plan's first.
void SnapSizeToPlan(const ENUM_FN_PLAN p) {
    double s[];
    const int n = ValidSizesForPlan(p, s);
    for (int i = 0; i < n; ++i)
        if ((int)MathRound(s[i]) == (int)MathRound(g_eff_size)) return; // already valid
    if (n > 0) { g_eff_size = s[0]; GlobalVariableSet("RC_size", g_eff_size); }
}
// V1.27 fix : keep the phase legal for the plan. Only Stellar Instant uses the
// INSTANT phase (3) ; every other plan (esp. FTMO, which has no Instant profile)
// must fold INSTANT -> FUNDED, else Resolve silently falls back to a default
// profile and the panel shows the wrong rule-set with no warning.
void SnapPhaseToPlan(const ENUM_FN_PLAN p) {
    if (p == FN_PLAN_STELLAR_INSTANT)  g_eff_phase = 3; // INSTANT (single-phase)
    else if (g_eff_phase == 3)         g_eff_phase = 2; // INSTANT -> FUNDED
    GlobalVariableSet("RC_phase", (double)g_eff_phase);
}
// V1.28 : size label, with the Personal "Auto" sentinel (g_eff_size <= 0).
string SizeLabel(void) {
    if (g_eff_size <= 0.0) return "Auto";
    return "$" + IntegerToString((int)MathRound(g_eff_size / 1000.0)) + "K";
}
// V1.28 (item 7) : a Personal account has no fixed challenge size -> derive the
// reference balance. Prefer the initial deposit (first balance deal) for a true
// "starting balance", fall back to the current real balance.
double DetectStartingBalance(void) {
    if (HistorySelect(0, TimeCurrent())) {
        const int n = HistoryDealsTotal();
        for (int i = 0; i < n; ++i) {
            const ulong tk = HistoryDealGetTicket(i);
            if (tk == 0) continue;
            if ((ENUM_DEAL_TYPE)HistoryDealGetInteger(tk, DEAL_TYPE) == DEAL_TYPE_BALANCE) {
                const double amt = HistoryDealGetDouble(tk, DEAL_PROFIT);
                if (amt > 0.0) return amt; // earliest deposit = starting balance
            }
        }
    }
    const double bal = AccountInfoDouble(ACCOUNT_BALANCE);
    return (bal > 0.0 ? bal : 1.0);
}
// V1.28 (item 6) : lot decimals from the symbol's volume step (up to 4).
int VolDigits(const string sym) {
    const double step = SymbolInfoDouble(sym, SYMBOL_VOLUME_STEP);
    if (step <= 0.0)   return 2;
    if (step >= 1.0)   return 0;
    if (step >= 0.1)   return 1;
    if (step >= 0.01)  return 2;
    if (step >= 0.001) return 3;
    return 4;
}
// V1.28 (item 4) : short month name for the "chic" cycle-date display.
string MonthShort(const int m) {
    if (m < 1 || m > 12) return "?";
    // V1.29 F3 : localized short month names (was EN-only on the FR/ES date picker).
    string en[12] = {"Jan","Feb","Mar","Apr","May","Jun","Jul","Aug","Sep","Oct","Nov","Dec"};
    string fr[12] = {"Jan","Fév","Mar","Avr","Mai","Jun","Jul","Aoû","Sep","Oct","Nov","Déc"};
    string es[12] = {"Ene","Feb","Mar","Abr","May","Jun","Jul","Ago","Sep","Oct","Nov","Dic"};
    if (g_lang == 1) return fr[m - 1];
    if (g_lang == 2) return es[m - 1];
    return en[m - 1];
}
// V1.28 : days in a month (leap-aware) so the cycle-date picker never produces
// an invalid date like "31 Feb".
int DaysInMonth(const int y, const int m) {
    if (m == 2) return (((y % 4 == 0) && (y % 100 != 0)) || (y % 400 == 0)) ? 29 : 28;
    if (m == 4 || m == 6 || m == 9 || m == 11) return 30;
    return 31;
}
string PhaseLabelLocal(int ph) {
    switch (ph) {
        case 0: return "Challenge P1";
        case 1: return "Challenge P2";
        case 2: return "Funded";
        case 3: return "Instant";
    }
    return "?";
}

//+------------------------------------------------------------------+
//| G1/G2 : the settings centre. A full-panel OPAQUE modal cover at   |
//| ZORDER 240 masks the live panel (no row bleeds through), with a   |
//| tabbed body (Account / Risk / Display / Alerts) on top. Every     |
//| control writes its g_eff_* shadow + a GlobalVariable and triggers |
//| ApplySettingsChange() so the change is live + survives restart.   |
//| Context-aware : prop-only groups hide on a Personal account, and  |
//| only the add-ons valid for the selected firm are shown.           |
//+------------------------------------------------------------------+
// v1.4 : the app must EXPLAIN its elements (JR's father's UX note). Attach an
// "what it does + unit" tooltip (translation key) to a settings control on hover.
// SetTip1 = a single control (toggle / button) ; SetTip3 = a [-] value [+] stepper.
void SetTip1(const string id, const string tipkey) {
    ObjectSetString(0, RC_PREFIX + id, OBJPROP_TOOLTIP, Tr(tipkey));
}
void SetTip3(const string id_base, const string tipkey) {
    const string t = Tr(tipkey);
    ObjectSetString(0, RC_PREFIX + id_base + "_dn",  OBJPROP_TOOLTIP, t);
    ObjectSetString(0, RC_PREFIX + id_base + "_val", OBJPROP_TOOLTIP, t);
    ObjectSetString(0, RC_PREFIX + id_base + "_up",  OBJPROP_TOOLTIP, t);
}

void DrawSettingsOverlay(int panel_x, int panel_y, int panel_w) {
    const int ox = panel_x;
    const int oy = panel_y;
    const int ow = panel_w;
    const int oh = (g_panel_height > 120 ? g_panel_height : 240);

    // Modal cover : opaque, full panel, ZORDER 240 -> masks every panel object
    // (rows are <= 100) AND swallows stray clicks meant for the panel behind.
    const string modal_id = RC_PREFIX + "set_modal";
    DrawRect(modal_id, ox, oy, ow, oh, g_theme.bg, g_theme.border, 2);
    ObjectSetInteger(0, modal_id, OBJPROP_ZORDER, 240);

    // Title + close.
    SetLbl(RC_PREFIX + "set_title", ox + 16, oy + 9, Tr("settings"), g_theme.accent);
    ObjectSetInteger(0, RC_PREFIX + "set_title", OBJPROP_FONTSIZE, RC_FONT_SIZE_TITLE);
    DrawSetButton(RC_PREFIX + "set_close", ox + ow - 32, oy + 6, 24, 20, "X");

    // Tab bar.
    const int ty = oy + 32;
    const int tw = (ow - 24) / 5;
    DrawSetButton(RC_PREFIX + "set_tab_acct",  ox + 12 + tw * 0, ty, tw - 4, 22, Tr("tab_account"));
    DrawSetButton(RC_PREFIX + "set_tab_risk",  ox + 12 + tw * 1, ty, tw - 4, 22, Tr("tab_risk"));
    DrawSetButton(RC_PREFIX + "set_tab_disp",  ox + 12 + tw * 2, ty, tw - 4, 22, Tr("tab_display"));
    DrawSetButton(RC_PREFIX + "set_tab_alert", ox + 12 + tw * 3, ty, tw - 4, 22, Tr("tab_alerts"));
    DrawSetButton(RC_PREFIX + "set_tab_adv",   ox + 12 + tw * 4, ty, tw - 4, 22, Tr("tab_advanced"));
    HighlightSetButton(RC_PREFIX + "set_tab_acct",  g_settings_tab == 0);
    HighlightSetButton(RC_PREFIX + "set_tab_risk",  g_settings_tab == 1);
    HighlightSetButton(RC_PREFIX + "set_tab_disp",  g_settings_tab == 2);
    HighlightSetButton(RC_PREFIX + "set_tab_alert", g_settings_tab == 3);
    HighlightSetButton(RC_PREFIX + "set_tab_adv",   g_settings_tab == 4);

    const int lx = ox + 16;   // label column
    const int cx = ox + 150;  // control column
    int by = oy + 64;         // body cursor
    const int step = 26;

    if (g_settings_tab == 0) {
        // ===== Account ===== (V1.27 cascade : broker -> type -> size)
        SetLbl(RC_PREFIX + "set_br_lbl", lx, by + 3, Tr("set_broker_sel"), g_theme.text);
        DrawSetButton(RC_PREFIX + "set_vendor_prev", cx, by, 24, 20, "<");
        SetLbl(RC_PREFIX + "set_vendor_val", cx + 30, by + 3, VendorName(VendorOfPlan(EffectivePlan())), g_theme.accent);
        DrawSetButton(RC_PREFIX + "set_vendor_next", ox + ow - 40, by, 24, 20, ">");
        by += step;
        SetLbl(RC_PREFIX + "set_pl_lbl", lx, by + 3, Tr("set_type"), g_theme.text);
        DrawSetButton(RC_PREFIX + "set_plan_prev", cx, by, 24, 20, "<");
        SetLbl(RC_PREFIX + "set_plan_val", cx + 30, by + 3, g_catalog.ModelLabel(EffectivePlan()), g_theme.accent);
        DrawSetButton(RC_PREFIX + "set_plan_next", ox + ow - 40, by, 24, 20, ">");
        by += step;

        if (PlanIsPersonal()) {
            SetLbl(RC_PREFIX + "set_personal_note", lx, by + 3, Tr("set_personal_note"), g_theme.text_dim);
            by += step;
            // V1.29 I : Personal account TYPE (Real / Demo). Labeling only - the
            // catalogue profile and the prop rules are unchanged (already off on
            // Personal). Auto-detected from ACCOUNT_TRADE_MODE, override here.
            SetLbl(RC_PREFIX + "set_pt_lbl", lx, by + 3, Tr("set_personal_type"), g_theme.text);
            DrawSetButton(RC_PREFIX + "set_perso_type", cx, by, 110, 20,
                          g_eff_personal_demo == 1 ? "DEMO" : "REAL");
            by += step;
            // V1.29 M : risk-tools master toggle - PERSONAL-ONLY, in the Account
            // tab so it's discoverable in the Personal context (prop = always ON).
            SetLbl(RC_PREFIX + "set_rt_lbl", lx, by + 3, Tr("set_risktools"), g_theme.text);
            SetToggleBtn(RC_PREFIX + "set_risktools", cx, by, g_eff_risktools);
            by += step;
            // V1.28 : Personal can pick a demo size OR "Auto" (= the real account
            // balance, item 7). The size stepper walks the Personal list.
            SetLbl(RC_PREFIX + "set_sz_lbl", lx, by + 3, Tr("set_size"), g_theme.text);
            DrawSetButton(RC_PREFIX + "set_size_prev", cx, by, 24, 20, "<");
            SetLbl(RC_PREFIX + "set_size_val", cx + 30, by + 3, SizeLabel(), g_theme.accent);
            DrawSetButton(RC_PREFIX + "set_size_next", ox + ow - 40, by, 24, 20, ">");
            by += step;
        } else {
            if (PlanHasPhases()) {
                SetLbl(RC_PREFIX + "set_ph_lbl", lx, by + 3, Tr("set_phase"), g_theme.text);
                DrawSetButton(RC_PREFIX + "set_phase_prev", cx, by, 24, 20, "<");
                SetLbl(RC_PREFIX + "set_phase_val", cx + 30, by + 3, PhaseLabelLocal(g_eff_phase), g_theme.accent);
                DrawSetButton(RC_PREFIX + "set_phase_next", ox + ow - 40, by, 24, 20, ">");
                by += step;
            }
            SetLbl(RC_PREFIX + "set_sz_lbl", lx, by + 3, Tr("set_size"), g_theme.text);
            DrawSetButton(RC_PREFIX + "set_size_prev", cx, by, 24, 20, "<");
            SetLbl(RC_PREFIX + "set_size_val", cx + 30, by + 3, SizeLabel(), g_theme.accent);
            DrawSetButton(RC_PREFIX + "set_size_next", ox + ow - 40, by, 24, 20, ">");
            by += step;

            if (PlanIsFundedNext()) {
                SetLbl(RC_PREFIX + "set_at_lbl", lx, by + 3, Tr("set_acct_type"), g_theme.text);
                DrawSetButton(RC_PREFIX + "set_acct_type", cx, by, 110, 20,
                              g_eff_acct_type == 0 ? "SWAP" : "SWAP-FREE");
                by += step;

                // Add-ons : only the ones valid for this firm (context-aware).
                const int valid = g_catalog.ValidAddonsMask(EffectivePlan());
                if (valid != FN_ADDON_NONE) {
                    SetLbl(RC_PREFIX + "set_ad_lbl", lx, by + 3, Tr("set_addons"), g_theme.text);
                    by += step - 4;
                    int flags[7];  string names[7];
                    flags[0] = FN_ADDON_LIFETIME_95; names[0] = "Lifetime 95%";
                    flags[1] = FN_ADDON_NO_MIN_DAYS; names[1] = "No Min Days";
                    flags[2] = FN_ADDON_SWAP_FREE;   names[2] = "Swap-Free";
                    flags[3] = FN_ADDON_10PCT_DD;    names[3] = "10% Total DD";
                    flags[4] = FN_ADDON_DOUBLE_UP;   names[4] = "Double Up";
                    flags[5] = FN_ADDON_BI_WEEKLY;   names[5] = "Bi-Weekly";
                    flags[6] = FN_ADDON_150_REWARD;  names[6] = "150% Reward";
                    for (int a = 0; a < 7; ++a) {
                        if ((valid & flags[a]) == 0) continue;
                        SetLbl(RC_PREFIX + "set_adn_" + IntegerToString(flags[a]), lx + 12, by + 3,
                               names[a], g_theme.text);
                        SetToggleBtn(RC_PREFIX + "set_addon_" + IntegerToString(flags[a]),
                                     ox + ow - 76, by, (g_addons_mask & flags[a]) != 0);
                        by += step - 2;
                    }
                }
            }
            // V1.27 : profit-split override (Auto = the firm's default split).
            SetLbl(RC_PREFIX + "set_sp_lbl", lx, by + 3, Tr("set_split_sel"), g_theme.text);
            SetStepper(RC_PREFIX + "set_split", cx, by,
                       (g_eff_split < 0 ? "Auto" : DoubleToString(g_eff_split, 0) + "%"));
            by += step;
        }
    } else if (g_settings_tab == 1) {
        // ===== Risk =====
        SetLbl(RC_PREFIX + "set_n_lbl", lx, by + 3, Tr("set_maxparallel"), g_theme.text);
        SetStepper(RC_PREFIX + "set_n", cx, by, IntegerToString(g_max_parallel));
        SetTip3("set_n", "tip_maxparallel");
        by += step;
        SetLbl(RC_PREFIX + "set_sl_lbl", lx, by + 3, Tr("set_sl"), g_theme.text);
        SetStepper(RC_PREFIX + "set_sl", cx, by, DoubleToString(g_eff_sl_pct, 2) + "%");
        SetTip3("set_sl", "tip_sl");
        by += step;
        SetLbl(RC_PREFIX + "set_tp_lbl", lx, by + 3, Tr("set_tp"), g_theme.text);
        SetStepper(RC_PREFIX + "set_tp", cx, by, DoubleToString(g_eff_tp_pct, 2) + "%");
        SetTip3("set_tp", "tip_tp");
        by += step;
        SetLbl(RC_PREFIX + "set_mm_lbl", lx, by + 3, Tr("set_maxmargin"), g_theme.text);
        SetStepper(RC_PREFIX + "set_mm", cx, by, DoubleToString(g_eff_max_margin_pt, 1) + "%");
        SetTip3("set_mm", "tip_maxmargin");
        by += step;
        SetLbl(RC_PREFIX + "set_mr_lbl", lx, by + 3, Tr("set_maxrisk"), g_theme.text);
        SetStepper(RC_PREFIX + "set_mr", cx, by, DoubleToString(g_eff_max_risk_pt, 2) + "%");
        SetTip3("set_mr", "tip_maxrisk");
        by += step;
        // V1.27 : post-violation tightening (mirror of the on-chart toggles + the
        // tightened caps that EffectiveMarginCap / EffectiveRiskCap apply). Only
        // relevant for a restrictable (funded prop) profile -> same guard as the
        // on-chart toggles, so they don't snap back on a demo / Personal account.
        if (ProfileCanBeRestricted()) {
            SetLbl(RC_PREFIX + "set_mviol_lbl", lx, by + 3, Tr("set_mviol"), g_theme.text);
            SetToggleBtn(RC_PREFIX + "set_mviol", cx, by, g_margin_violation_active);
            SetTip1("set_mviol", "tip_mviol");
            by += step;
            SetLbl(RC_PREFIX + "set_mcv_lbl", lx, by + 3, Tr("set_mcapviol"), g_theme.text);
            SetStepper(RC_PREFIX + "set_mcv", cx, by, DoubleToString(g_eff_margin_cap_viol, 0) + "%");
            SetTip3("set_mcv", "tip_mcapviol");
            by += step;
            SetLbl(RC_PREFIX + "set_rviol_lbl", lx, by + 3, Tr("set_rviol"), g_theme.text);
            SetToggleBtn(RC_PREFIX + "set_rviol", cx, by, g_risk_violation_active);
            SetTip1("set_rviol", "tip_rviol");
            by += step;
            SetLbl(RC_PREFIX + "set_rcv_lbl", lx, by + 3, Tr("set_rcapviol"), g_theme.text);
            SetStepper(RC_PREFIX + "set_rcv", cx, by, DoubleToString(g_eff_risk_cap_viol, 2) + "%");
            SetTip3("set_rcv", "tip_rcapviol");
            by += step;
        }
    } else if (g_settings_tab == 2) {
        // ===== Display =====
        SetLbl(RC_PREFIX + "set_th_lbl", lx, by + 3, Tr("set_theme"), g_theme.text);
        DrawSetButton(RC_PREFIX + "set_theme_dark",  cx, by, 78, 20, "DARK");
        DrawSetButton(RC_PREFIX + "set_theme_light", cx + 84, by, 78, 20, "LIGHT");
        HighlightSetButton(RC_PREFIX + "set_theme_dark",  EffectiveTheme() == RC_THEME_GLASS_DARK);
        HighlightSetButton(RC_PREFIX + "set_theme_light", EffectiveTheme() == RC_THEME_GLASS_LIGHT);
        by += step;
        SetLbl(RC_PREFIX + "set_lg_lbl", lx, by + 3, Tr("set_language"), g_theme.text);
        DrawSetButton(RC_PREFIX + "set_lang_en", cx,       by, 50, 20, "EN");
        DrawSetButton(RC_PREFIX + "set_lang_fr", cx + 56,  by, 50, 20, "FR");
        DrawSetButton(RC_PREFIX + "set_lang_es", cx + 112, by, 50, 20, "ES");
        HighlightSetButton(RC_PREFIX + "set_lang_en", g_lang == 0);
        HighlightSetButton(RC_PREFIX + "set_lang_fr", g_lang == 1);
        HighlightSetButton(RC_PREFIX + "set_lang_es", g_lang == 2);
        by += step;
        SetLbl(RC_PREFIX + "set_nw_lbl", lx, by + 3, Tr("set_news"), g_theme.text);
        SetToggleBtn(RC_PREFIX + "set_news", cx, by, g_eff_show_news);
        by += step;
        // V1.29 R : news LEVEL selector - HIGH / MEDIUM (both default ON ; FN counts MEDIUM too).
        SetLbl(RC_PREFIX + "set_nh_lbl", lx, by + 3, Tr("set_news_high"), g_theme.text);
        SetToggleBtn(RC_PREFIX + "set_news_high", cx, by, g_eff_news_high);
        SetTip1("set_news_high", "tip_news_high");
        by += step;
        SetLbl(RC_PREFIX + "set_nm_lbl", lx, by + 3, Tr("set_news_med"), g_theme.text);
        SetToggleBtn(RC_PREFIX + "set_news_med", cx, by, g_eff_news_med);
        SetTip1("set_news_med", "tip_news_med");
        by += step;
        SetLbl(RC_PREFIX + "set_cf_lbl", lx, by + 3, Tr("set_comfort"), g_theme.text);
        SetToggleBtn(RC_PREFIX + "set_comfort", cx, by, g_eff_comfort);
        by += step;
        SetLbl(RC_PREFIX + "set_dl_lbl", lx, by + 3, Tr("set_discipline"), g_theme.text);
        SetToggleBtn(RC_PREFIX + "set_discipline", cx, by, g_eff_discipline);
        by += step;
        // V1.29 M : the risk-tools toggle moved to the Account tab (Personal context)
        // - prop accounts are always-ON so it doesn't belong in the global Display tab.
    } else if (g_settings_tab == 3) {
        // ===== Alerts =====
        SetLbl(RC_PREFIX + "set_sd_lbl", lx, by + 3, Tr("set_sound"), g_theme.text);
        SetToggleBtn(RC_PREFIX + "set_sound", cx, by, g_eff_sound);
        by += step;
        SetLbl(RC_PREFIX + "set_tg_lbl", lx, by + 3, Tr("set_telegram"), g_theme.text);
        SetToggleBtn(RC_PREFIX + "set_telegram", cx, by, g_eff_telegram);
        by += step;
        // V1.24 G1 : self-lock (Ulysses pact). One click arms a full-panel STOP
        // for InpSelfLockHours ; unlocking needs a double-confirm on the overlay.
        SetLbl(RC_PREFIX + "set_sl_lbl2", lx, by + 3, Tr("set_selflock"), g_theme.text);
        DrawSetButton(RC_PREFIX + "set_selflock", cx, by, 150, 20,
                      Tr("set_selflock") + " " + IntegerToString(g_eff_selflock_h) + "h");
        by += step;
        SetLbl(RC_PREFIX + "set_strings_note", lx, by + 3, Tr("set_strings_note"), g_theme.text_dim);
        by += step;
    } else {
        // ===== Advanced : discipline + comfort tunables (V1.26) =====
        SetLbl(RC_PREFIX + "set_tn_lbl", lx, by + 3, Tr("set_tiltn"), g_theme.text);
        SetStepper(RC_PREFIX + "set_tn", cx, by, IntegerToString(g_eff_tilt_n));
        by += step;
        SetLbl(RC_PREFIX + "set_tw_lbl", lx, by + 3, Tr("set_tiltwin"), g_theme.text);
        SetStepper(RC_PREFIX + "set_tw", cx, by, IntegerToString(g_eff_tilt_win) + "m");
        by += step;
        SetLbl(RC_PREFIX + "set_cn_lbl", lx, by + 3, Tr("set_cooldownn"), g_theme.text);
        SetStepper(RC_PREFIX + "set_cn", cx, by, IntegerToString(g_eff_cooldown_n));
        by += step;
        SetLbl(RC_PREFIX + "set_cm_lbl", lx, by + 3, Tr("set_cooldownm"), g_theme.text);
        SetStepper(RC_PREFIX + "set_cm", cx, by, IntegerToString(g_eff_cooldown_m) + "m");
        by += step;
        SetLbl(RC_PREFIX + "set_sh_lbl", lx, by + 3, Tr("set_selflockh"), g_theme.text);
        SetStepper(RC_PREFIX + "set_sh", cx, by, IntegerToString(g_eff_selflock_h) + "h");
        by += step;
        SetLbl(RC_PREFIX + "set_cp_lbl", lx, by + 3, Tr("set_comfortpct"), g_theme.text);
        SetStepper(RC_PREFIX + "set_cp", cx, by, DoubleToString(g_eff_comfort_pct, 0) + "%");
        by += step;
        // V1.27 : cycle start date (drives the "Days traded" counter) + refresh.
        // V1.28 (item 4) : "chic" agenda header (assembled date in accent colour)
        // above day / month-name / year steppers.
        const double cyc_ymd = (g_eff_cycle_ymd > 0 ? g_eff_cycle_ymd : IsoToYmd(InpCycleStartIso));
        const int cyc_y = (int)cyc_ymd / 10000, cyc_mo = ((int)cyc_ymd / 100) % 100, cyc_d = (int)cyc_ymd % 100;
        SetLbl(RC_PREFIX + "set_cyc_lbl", lx, by + 3, Tr("set_cycle"), g_theme.text);
        SetLbl(RC_PREFIX + "set_cyc_val", cx + 30, by + 3,
               StringFormat("%02d %s %04d", cyc_d, MonthShort(cyc_mo), cyc_y), g_theme.accent);
        by += step;
        SetLbl(RC_PREFIX + "set_cdd_lbl", lx, by + 3, Tr("set_cycday"), g_theme.text);
        SetStepper(RC_PREFIX + "set_cdd", cx, by, IntegerToString(cyc_d));
        by += step;
        SetLbl(RC_PREFIX + "set_cmm_lbl", lx, by + 3, Tr("set_cycmonth"), g_theme.text);
        SetStepper(RC_PREFIX + "set_cmm", cx, by, MonthShort(cyc_mo));
        by += step;
        SetLbl(RC_PREFIX + "set_cyy_lbl", lx, by + 3, Tr("set_cycyear"), g_theme.text);
        SetStepper(RC_PREFIX + "set_cyy", cx, by, IntegerToString(cyc_y));
        by += step;
        SetLbl(RC_PREFIX + "set_rm_lbl", lx, by + 3, Tr("set_refreshms"), g_theme.text);
        SetStepper(RC_PREFIX + "set_rm", cx, by, IntegerToString(g_eff_refresh_ms) + "ms");
        by += step;
    }

    // Footer note + auto-detected broker (always shown, bottom of the modal).
    SetLbl(RC_PREFIX + "set_note", lx, oy + oh - 40, Tr("set_note"), g_theme.text_dim);
    SetLbl(RC_PREFIX + "set_broker", lx, oy + oh - 22,
           Tr("set_broker") + " " + AccountInfoString(ACCOUNT_SERVER), g_theme.text_dim);
    // V1.24 fix : hide the panel's own controls (TF / BE / N / violation toggles
    // / copy edits / logo) while the modal is up - they'd render on top of the
    // rectangle overlay otherwise. Keep the settings controls (set_*) visible.
    SetPanelControlsHidden(true, "set");
}

// G3 : after a settings popup change, rebuild theme + (optionally) re-resolve
// the profile + redraw the whole panel + restore the popup if it was open.
void ApplySettingsChange(void) {
    InitTheme();
    g_profile_ok = g_catalog.Resolve(EffectivePlan(), (ENUM_FN_PHASE)g_eff_phase, g_eff_size,
                                     (ENUM_FN_ACCOUNT_TYPE)g_eff_acct_type, g_addons_mask, g_profile);
    if (g_eff_split >= 0.0) g_profile.profit_split_pct = g_eff_split; // V1.27 : manual split override
    if (EffectivePlan() == FN_PLAN_PERSONAL && g_eff_size <= 0.0)
        g_profile.initial_balance = DetectStartingBalance(); // V1.28 : Personal "Auto" -> real balance
    if (!ProfileCanBeRestricted()) {
        g_margin_violation_active = false;
        g_risk_violation_active   = false;
    }
    DestroyAllObjects();
    BuildPanel();
    // V1.29 S : CHART elements live on the price area (NOT the panel), so a popup
    // change must reflect on them IMMEDIATELY - refresh them ALWAYS (no modal
    // bleed-through, they're off-panel). Only RefreshPanel (the panel rows) stays
    // gated on !g_settings_open (drawing rows over the open modal = bleed-through).
    RefreshNewsZones();                     // news bars + level toggles : instant
    RefreshSlLines();                       // SL/TP recommendation lines
    if (g_be_visible) DrawBreakevenLines(); // basket BE line
    ApplyComfortScale(false);               // comfort padding (self-guards on g_eff_comfort)
    g_news_stats_scan = 0;                  // V1.29 : bust the news-card 60 s cache -> a cycle-date (or any) popup change recomputes the card instantly
    if (!g_settings_open)
        RefreshPanel();
    ChartRedraw(0);
}

//+------------------------------------------------------------------+
//| Max-parallel control - clickable [-] N [+] near footer line 2    |
//|                                                                  |
//| AUDIT 2026-06-07 fix #4 : mp_minus / mp_plus were OBJ_RECTANGLE_  |
//| LABEL + overlay OBJ_LABEL, which DO NOT emit CHARTEVENT_OBJECT_   |
//| CLICK -> the +/- buttons were silently DEAD. The whole V1.1       |
//| "trader picks N" feature (and the SL-line-per-trade allocation    |
//| that follows from it) was broken. Convert both to OBJ_BUTTON so   |
//| MT5 actually emits the click event, drop the _txt overlays.       |
//+------------------------------------------------------------------+
void DrawMpButton(const string id, int x, int y, int w, int h, const string text) {
    if (ObjectFind(0, id) < 0)
        ObjectCreate(0, id, OBJ_BUTTON, 0, 0, 0);
    ObjectSetInteger(0, id, OBJPROP_XDISTANCE, x);
    ObjectSetInteger(0, id, OBJPROP_YDISTANCE, y);
    ObjectSetInteger(0, id, OBJPROP_XSIZE, w);
    ObjectSetInteger(0, id, OBJPROP_YSIZE, h);
    ObjectSetString(0, id, OBJPROP_TEXT, text);
    ObjectSetString(0, id, OBJPROP_FONT, RC_FONT_UI);
    ObjectSetInteger(0, id, OBJPROP_FONTSIZE, RC_FONT_SIZE);
    ObjectSetInteger(0, id, OBJPROP_COLOR, g_theme.text);
    ObjectSetInteger(0, id, OBJPROP_BGCOLOR, g_theme.bg_section);
    ObjectSetInteger(0, id, OBJPROP_BORDER_COLOR, g_theme.border);
    ObjectSetInteger(0, id, OBJPROP_CORNER, CORNER_LEFT_UPPER);
    ObjectSetInteger(0, id, OBJPROP_STATE, false);
    ObjectSetInteger(0, id, OBJPROP_SELECTABLE, false);
    ObjectSetInteger(0, id, OBJPROP_HIDDEN, true);
    ObjectSetInteger(0, id, OBJPROP_ZORDER, 100); // LOT B : wins click routing
}

void DrawMaxParallelControl(int x, int y) {
    const int btn_w = 20;
    const int btn_h = InpRowHeight - 4;

    DrawMpButton(RC_PREFIX + "mp_minus", x, y, btn_w, btn_h, "-");

    DrawLabel(RC_PREFIX + "mp_value", x + btn_w + 8, y + 2,
              IntegerToString(g_max_parallel), g_theme.accent, RC_FONT_SIZE);

    DrawMpButton(RC_PREFIX + "mp_plus", x + btn_w + 30, y, btn_w, btn_h, "+");
}

//+------------------------------------------------------------------+
//| RefreshPyramidLine -- compute next safe-pyramid step on the      |
//| current chart symbol's basket (weighted entry + cumulative vol)  |
//| and render it in footer row 4. Read-only, no trade actions.      |
//|                                                                  |
//| Anchor selection logic (V1 simple) :                             |
//|   - Iterate open positions on _Symbol.                           |
//|   - Filter to same direction (all-BUY OR all-SELL basket only;   |
//|     mixed direction = "hedged" message, no plan).                |
//|   - Anchor entry = vol-weighted average of all entries.          |
//|   - Anchor vol   = sum of vols.                                  |
//|   - Anchor SL    = the WORST (most-distant) SL among the basket  |
//|                    (= the maximal R, most conservative).         |
//+------------------------------------------------------------------+
void RefreshPyramidLine(void) {
    const string label_id = RC_PREFIX + "footer_l4";
    if (ObjectFind(0, label_id) < 0)
        return; // panel was built with pyramid disabled - nothing to update

    const string sym = _Symbol;
    const int n = PositionsTotal();
    int basket_n = 0;
    double sum_vol = 0.0;
    double sum_entry_x_vol = 0.0;
    int basket_type = -1; // -1 = none yet
    bool mixed = false;
    double worst_sl_dist = 0.0;
    double worst_sl_price = 0.0;
    double worst_anchor_entry = 0.0;
    bool any_missing_sl = false;

    for (int i = 0; i < n; ++i) {
        const ulong t = PositionGetTicket(i);
        if (t == 0 || !PositionSelectByTicket(t))
            continue;
        if (PositionGetString(POSITION_SYMBOL) != sym)
            continue;
        const int type = (int)PositionGetInteger(POSITION_TYPE);
        const double vol = PositionGetDouble(POSITION_VOLUME);
        const double entry = PositionGetDouble(POSITION_PRICE_OPEN);
        const double sl = PositionGetDouble(POSITION_SL);

        if (basket_type < 0)
            basket_type = type;
        else if (basket_type != type) {
            mixed = true;
            break;
        }
        basket_n++;
        sum_vol += vol;
        sum_entry_x_vol += entry * vol;

        if (sl <= 0.0) {
            any_missing_sl = true;
        } else {
            const double dist = MathAbs(entry - sl);
            if (dist > worst_sl_dist) {
                worst_sl_dist = dist;
                worst_sl_price = sl;
                worst_anchor_entry = entry;
            }
        }
    }

    if (basket_n == 0) {
        ObjectSetString(0, label_id, OBJPROP_TEXT,
                        "Pyramid : no position on " + sym);
        ObjectSetInteger(0, label_id, OBJPROP_COLOR, g_theme.text_dim);
        return;
    }
    if (mixed) {
        ObjectSetString(0, label_id, OBJPROP_TEXT,
                        "Pyramid : hedged basket (BUY+SELL) -- not supported");
        ObjectSetInteger(0, label_id, OBJPROP_COLOR, g_theme.warn);
        return;
    }
    if (any_missing_sl || worst_sl_dist <= 0.0) {
        ObjectSetString(0, label_id, OBJPROP_TEXT,
                        "Pyramid : place SL on all positions before planning");
        ObjectSetInteger(0, label_id, OBJPROP_COLOR, g_theme.warn);
        return;
    }
    if (sum_vol <= 0.0) {
        ObjectSetString(0, label_id, OBJPROP_TEXT, "Pyramid : basket vol = 0");
        ObjectSetInteger(0, label_id, OBJPROP_COLOR, g_theme.text_dim);
        return;
    }

    const double anchor_entry = sum_entry_x_vol / sum_vol;
    const bool is_buy = (basket_type == POSITION_TYPE_BUY);

    // Reconstruct anchor SL from the worst SL distance, applied around the
    // weighted anchor. Direction-aware : BUY -> SL below anchor, SELL above.
    const double anchor_sl = (is_buy ? anchor_entry - worst_sl_dist
                                     : anchor_entry + worst_sl_dist);

    PyramidStep step;
    if (!g_pyramid_engine.ComputeNextStep(sym, anchor_entry, sum_vol, anchor_sl,
                                          is_buy, basket_n, step) ||
        !step.ok) {
        ObjectSetString(0, label_id, OBJPROP_TEXT,
                        "Pyramid : " + step.info);
        ObjectSetInteger(0, label_id, OBJPROP_COLOR, g_theme.warn);
        return;
    }

    const int pld = LotDigits(sym);  // B-LOTPRECISION
    string line;
    StringConcatenate(line,
                      "Pyramid: if px ", (is_buy ? ">=" : "<="), " ",
                      DoubleToString(step.trigger_price, _Digits),
                      " add ", DoubleToString(step.add_lot, pld),
                      " lot & move ALL SL -> ", DoubleToString(step.new_unified_stop, _Digits),
                      " = locks ",
                      (step.worst_case_money >= 0.0 ? "risk-free min +$" : "loss -$"),
                      DoubleToString(MathAbs(step.worst_case_money), 2),
                      "  [basket ", DoubleToString(sum_vol, pld),
                      " @", DoubleToString(anchor_entry, _Digits), "]");
    ObjectSetString(0, label_id, OBJPROP_TEXT, line);
    ObjectSetInteger(0, label_id, OBJPROP_COLOR,
                     (step.worst_case_money >= 0.0 ? g_theme.ok : g_theme.warn));
}

//+------------------------------------------------------------------+
