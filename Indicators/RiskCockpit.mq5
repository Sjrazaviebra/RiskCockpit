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
#property version "3.11"
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
#include <..\Libraries\RC_ShellUI.mqh> // v3 SHELL (lot 1) : 36px rail + on-demand panel (StrategyDeck v2 space architecture)

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

// v2.02 MULTI-THEMES : brand PALETTE axis, orthogonal to the dark/light MODE
// above (3 palettes x 2 modes = 6 combos). The risk colours SAFE/WATCH/BREACH
// stay green/amber/red in every combo - only the brand tones change.
enum ENUM_RC_PALETTE {
    RC_PAL_EMERALD = 0, // Emeraude Nuit (default)
    RC_PAL_INDIGO  = 1, // Indigo Royal
    RC_PAL_MONO    = 2  // Ardoise Mono
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
//|   Instant         : 2 / 5 / 10 / 15 / 25 K                        |
//|   Free Trial      : 6 -> 200 K                                    |
//|   Free Competition: single size, varies per monthly event         |
//+------------------------------------------------------------------+
enum ENUM_FN_ACCT_SIZE {
    FN_SIZE_2K   = 2000,   // 2 000  (Instant)
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
input ENUM_RC_THEME InpTheme                 = RC_THEME_GLASS_DARK; // Panel mode (Glass Dark / Glass Light)
input ENUM_RC_PALETTE InpPalette             = RC_PAL_EMERALD;      // Brand palette (Emeraude / Indigo / Ardoise) - v2.02
input ENUM_RC_LANG  InpLang                  = RC_LANG_EN;          // UI language (EN / FR / ES)
input int           InpShellTipMs            = 600;                 // v3 SHELL : hover delay before a tooltip shows (ms)
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

input group "9 - DIAGNOSTICS"
input bool InpVerboseLog = false;  // Verbose dev diagnostics to the Experts log (news-card scan) ; OFF for normal use

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
    color accent;      // primary accent (cyan)
    color accent_deep; // deep end of the accent (LOT C : ON-state gradients, mockup --cyan-deep)
    color accent2;     // secondary accent (indigo)
    color raise;       // raised control top (LOT C : mockup --raise button gradient)
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
bool    g_fx_was_breach = false;   // gate idle GPU updates (only redraw while breaching / on clear)
int     g_fx_w  = 0;
int     g_fx_h  = 0;
#define RC_FX_MARGIN 12

// v1.4 MODERN : the panel body is drawn in ONE CCanvasKit bitmap (rounded card,
// soft gradient, drop shadow, hairline dividers, rounded-end meters + pills).
// It sits UNDER the text (OBJ_LABEL) and controls, and under g_fx (the glow).
// v3 SHELL (lot 1) : the new space architecture lives in RC_ShellUI.mqh and is
// v3.06 : the legacy panel is GONE (JR) - this is the only UI there is.
// The shell is a VIEW : BuildDeckData fills its snapshot from the SAME Live_*
// functions the legacy rows use, so there is exactly one risk model.
RCShellUI g_shell;
void BuildDeckData(RCDeckData &d);
void ShellRefresh(void);

// LOT D : the settings modal draws on its OWN canvas - shell (rounded card + shadow +
// glow) AND, since D-FULL step 2, every control face (buttons / pills / steppers).
// DrawSettingsOverlay holds ONE Begin..Commit around the whole build ; the helpers
// (DrawSetButton / SetToggleBtn / SetStepper) paint into the open canvas and register
// hit-zones on the same rects. 100% hit-testing : no native modal OBJ_BUTTON remains.
#define RC_KIT_MARGIN 16   // shadow / rounding room around the panel
#define RC_R_PANEL    15   // panel corner radius (LOT B : mockup .rc radius 15)
#define RC_R_CARD     10   // inner card corner radius
// v1.4 dev : optional BUILD tag in the title bar (per modern phase during dev :
// "R1", "R2"...). EMPTY = clean release (no tag drawn). NOT the Market version.
#define RC_BUILD_TAG  ""   // FINAL : clean release, no dev tag

void InitTheme(void) {
    // G3 : route through EffectiveTheme so the settings popup can switch
    // dark/light at runtime without re-opening MT5 Inputs.
    // v2.02 MULTI-THEMES : palette (brand) x mode (dark/light) = 6 combos. Each
    // palette gives its 6 PRIMARY tokens ; ApplyPaletteTokens derives every
    // secondary token with the SAME relations the historical slate theme used,
    // so films / relief / rings keep working identically in every combo.
    const bool dark = (EffectiveTheme() == RC_THEME_GLASS_DARK);
    switch (EffectivePalette()) {
        case RC_PAL_INDIGO: // Indigo Royal
            // deep end = indigo-500 #6366F1 (NOT the spec's #4F46E5) : active labels are
            // drawn in bg colour on the accent->deep gradient, and #4F46E5 amplified
            // bottomed at ~2.1:1 - indigo-500 keeps the hue at ~4.1:1. 1-line revert.
            if (dark) ApplyPaletteTokens(C'129,140,248', C'99,102,241', C'11,15,30',    C'23,27,51',    C'238,240,255', C'154,160,192', true);
            else      ApplyPaletteTokens(C'79,70,229',   C'67,56,202',  C'238,240,250', C'255,255,255', C'30,27,75',    C'107,112,149', false);
            break;
        case RC_PAL_MONO:   // Ardoise Mono - neutral accent : the risk pills are
                            // the ONLY vivid colours on screen (deliberate focus).
            // dark dim = zinc-400 #A1A1AA (NOT the spec's #71717A) : the derived
            // text_dim off zinc-500 read ~2.6:1 on the near-black bg (NA rows barely
            // visible) - zinc-400 restores ~4:1, same hierarchy as the other darks.
            if (dark) ApplyPaletteTokens(C'212,212,216', C'161,161,170', C'10,10,11',   C'24,24,27',    C'250,250,250', C'161,161,170', true);
            else      ApplyPaletteTokens(C'63,63,70',    C'39,39,42',   C'244,244,245', C'255,255,255', C'24,24,27',    C'113,113,122', false);
            break;
        default:            // RC_PAL_EMERALD - Emeraude Nuit (default)
            if (dark) ApplyPaletteTokens(C'45,212,191',  C'13,148,136', C'7,20,16',     C'16,36,28',    C'236,253,245', C'107,155,138', true);
            else      ApplyPaletteTokens(C'13,148,136',  C'15,118,110', C'240,253,250', C'255,255,255', C'4,47,42',     C'94,122,115', false);
            break;
    }
}

// v2.02 MULTI-THEMES : fill g_theme from a palette's 6 primary tokens (accent /
// accent_deep / bg / surface / text / dim). Secondary tokens are DERIVED with the
// relations fitted on the v2.01 slate values (bg_lift = bg-surface midpoint,
// light bg_deep/raise/bg_section = one slightly-darker tone, etc.) - one rule set
// for every palette. ok/warn/red stay palette-INDEPENDENT (risk = green/amber/red
// everywhere, dark/light variant only - the RiskFillColors ramps match them).
void ApplyPaletteTokens(const color accent, const color accent_deep,
                        const color bg, const color surface,
                        const color text, const color dim, const bool dark) {
    g_theme.accent      = accent;
    g_theme.accent_deep = accent_deep;
    g_theme.bg          = bg;
    g_theme.surface     = surface;
    g_theme.text        = text;
    g_theme.label       = dim;
    g_theme.text_dim    = TintOver(dim, bg, 0.30);                    // dimmer = toward the bg
    g_theme.bg_deep     = TintOver(bg, clrBlack, dark ? 0.35 : 0.06); // shadow / gradient bottom / edits
    g_theme.bg_lift     = TintOver(bg, surface, 0.50);                // gradient top (bg-surface midpoint)
    g_theme.bg_section  = (dark ? TintOver(bg, surface, 0.33) : g_theme.bg_deep);
    g_theme.surface_hi  = (dark ? TintOver(surface, text, 0.05) : bg);
    g_theme.border      = TintOver(surface, dim, dark ? 0.16 : 0.28);
    g_theme.border_hi   = TintOver(g_theme.border, dim, 0.30);
    g_theme.raise       = (dark ? TintOver(surface, accent, 0.12) : g_theme.bg_deep); // control top, brand-tinted in dark
    g_theme.accent2     = accent_deep;                                // secondary accent follows the palette
    g_theme.bar_bg      = (dark ? g_theme.bg_lift : g_theme.bg_deep); // meter track
    if (dark) {
        g_theme.ok   = C'34,197,94';   // 7c VIVID : green-500 #22C55E (token==ramp-end)
        g_theme.warn = C'245,158,11';  // amber-500 #F59E0B
        g_theme.red  = C'239,68,68';   // red-500 #EF4444
    } else {
        g_theme.ok   = C'21,128,61';   // green-700 #15803D (>=4.5:1 on light)
        g_theme.warn = C'161,98,7';    // amber-700 #A16207
        g_theme.red  = C'220,38,38';   // red-600 #DC2626
    }
}

// LOT A/B/C : pre-blend `tint` over `base` at strength t (0..1) and return an OPAQUE
// color. CCanvas draws OVERWRITE pixels (no compositing between draws), so a low-alpha
// fill over the opaque card would show the CHART through - the mockup's rgba() tints
// must therefore be baked against the panel tone and drawn at alpha 255. (Real alpha
// stays valid ONLY in the margin band outside the card : shadow + edge glow.)
color TintOver(const color base, const color tint, const double t) {
    const int r = (int)MathRound((base & 0xFF)         * (1.0 - t) + (tint & 0xFF)         * t);
    const int g = (int)MathRound(((base >> 8) & 0xFF)  * (1.0 - t) + ((tint >> 8) & 0xFF)  * t);
    const int b = (int)MathRound(((base >> 16) & 0xFF) * (1.0 - t) + ((tint >> 16) & 0xFF) * t);
    return (color)((b << 16) | (g << 8) | r);
}

// E8 : theme-aware "film" tint. The mockup's rgba(255,255,255,x) films only LIFT on a
// DARK base ; on the light theme white is invisible. DARK branch stays byte-identical
// (frozen look) ; LIGHT swaps to a slate tint, boosted so it reads on a bright base.
// (EffectiveTheme is defined later - MQL5 resolves globals in two passes.)
color FilmOver(const color base, const double t) {
    if (EffectiveTheme() == RC_THEME_GLASS_DARK) return TintOver(base, C'255,255,255', t);
    return TintOver(base, C'148,163,184', MathMin(1.0, t * 2.4));
}

//+------------------------------------------------------------------+
//| Layout constants                                                 |
//+------------------------------------------------------------------+
#define RC_PREFIX "RC_"
#define RC_PAD 10
#define RC_TITLE_HEIGHT 30
#define RC_TITLE_CLOCK_W 120 // FIX 7 : reserved right zone for the clock (news/weekend/LIVE) so it never overlaps the balance
#define RC_HEADER_GAP    14  // FINESSE 1 : air between the gear cluster and the right-anchored status/clock (was a magic 8, too tight)
#define RC_LOGO_FILE "RiskCockpit_logo.bmp" // fixed header logo asset under MQL5\Images\ (not a user input)
#define RC_SECTION_HEIGHT 22
#define RC_FONT "Consolas"                  // numeric / tabular data (right-aligned)
#define RC_FONT_NUM "Consolas"               // alias : numbers
#define RC_FONT_UI "Segoe UI"                // labels / body (premium restyle P2)
#define RC_FONT_UI_SB "Segoe UI Semibold"    // titles / emphasis
#define RC_FONT_SIZE 9
#define RC_FONT_SIZE_TITLE 11
#define RC_FONT_SIZE_LABEL 8                 // small muted labels
// CAPSULE TEXT : font size proportional to the capsule height (a 16px chip cannot hold
// a 9pt Segoe box) + text-measured width so labels can never overflow their pill,
// whatever the locale or the DPI scale.
int RC_CapFont(const int h) { int pt = h / 2 - 1; if (pt < 7) pt = 7; if (pt > RC_FONT_SIZE) pt = RC_FONT_SIZE; return pt; }
int RC_CapWidth(const string txt, const int h, const string font) {
    uint tw = 0, th = 0;
    TextSetFont(font, -RC_CapFont(h) * 10);
    TextGetSize(txt, tw, th);
    return (int)tw + h + 8; // text + the two rounded caps + padding
}
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
double g_peak_balance = 0.0; // v2.02.05 FIX 1 : REALIZED-balance high-water mark (FN Instant trailing
                             // floor follows the balance, not equity) ; persisted per login (RC_ins_pb_<login>)

// ===== v2.03 F1-F3 : ForexFactory public feed (FairEconomy) = PRIMARY news source =====
// FN classifies news via a ForexFactory feed, and the MT5 calendar under-classes some
// FN-restricted events (central-bank speeches, PPI) -> fetch the public FF JSON, classify
// restricted = FF High OR the FN override list, and fall back to the MT5 calendar when
// the feed is unavailable (FEATURE 3 : never a silent empty screen).
struct FFEvent {
    datetime t_utc;      // event time, EPOCH UTC (the feed's ISO8601 offset parsed out)
    string   ccy;        // FF `country` field = currency code (USD/EUR/GBP/...)
    string   title;      // event title (bucket tooltips)
    bool     restricted; // F2 : FF "High" OR FN override -> the 40% RULE (red)
};
FFEvent  g_ff_events[];       // parsed cache (this-week feed, refreshed 1/60 min)
bool     g_ff_active = false; // feed fetched + parsed OK -> FF drives rule + display
datetime g_ff_last_try = 0;   // fetch throttle (0 = fetch on the first timer tick)

// v2.03 F4 : unified display event (FF or MT5 fallback), SERVER-time for the chart axis.
struct NewsDispItem {
    datetime t_srv;
    string   ccy;
    string   title;
    bool     restricted;
};
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
// v2.02 MULTI-THEMES : same resolution for the brand-palette axis.
ENUM_RC_PALETTE EffectivePalette(void) {
    if (g_active_palette_idx < 0) return InpPalette;
    return (ENUM_RC_PALETTE)g_active_palette_idx;
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
    // v2.13 FEATURE C : account-profile settings load PER LOGIN (legacy global =
    // one-time seed fallback), then re-save under the login so migration sticks.
    double gvv = 0.0;
    if (GVGetLogin("RC_size", gvv))      { g_eff_size      = gvv;      GVSetLogin("RC_size", gvv); }
    if (GVGetLogin("RC_acct_type", gvv)) { g_eff_acct_type = (int)gvv; GVSetLogin("RC_acct_type", gvv); }
    if (GVGetLogin("RC_phase", gvv))     { g_eff_phase     = (int)gvv; GVSetLogin("RC_phase", gvv); }
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
    if (GVGetLogin("RC_perso_demo", gvv)) { g_eff_personal_demo = (int)gvv; GVSetLogin("RC_perso_demo", gvv); } // V1.29 I + v2.13 C
    if (GVGetLogin("RC_addons", gvv))     { g_addons_mask       = (int)gvv; GVSetLogin("RC_addons", gvv); }
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
    if (GVGetLogin("RC_split", gvv))     { g_eff_split     = gvv; GVSetLogin("RC_split", gvv); }     // v2.13 C
    if (GVGetLogin("RC_cycle_ymd", gvv)) { g_eff_cycle_ymd = gvv; GVSetLogin("RC_cycle_ymd", gvv); } // v2.13 C
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
void RefreshPanel(void);
void   InitI18n(void);                          // LOT 4 : populate g_i18n_* tables once
string Tr(const string key);                    // LOT 4 : translate by key + g_lang
void   DrawBreakevenLines(void);                // LOT 5 : BE lines on open positions
void   ApplySettingsChange(void);                                                     // G3
void   ClearBreakevenLines(void);               // LOT 5 : remove all BE lines
// LOT 6 : single-glance verdict badge + safety score (replaces the LIVE blinker
// in the title bar's clock zone when no weekend / news countdown is active).
struct VerdictResult { string text; color clr; int score; };
void   PersistBE(void);
void   PersistLang(void);
void DrawRect(const string id, int x, int y, int w, int h, color bg, color border, int width = 1);
void DrawLabel(const string id, int x, int y, const string text, color clr,
               int font_size = RC_FONT_SIZE, const string font = RC_FONT);
string FormatMoney(double v);
string FormatPct(double v);
int DaysBetweenIso(const string iso_a, const string iso_b);
void ApplyComfortScale(bool force); // FIX 6
void ApplyComfortScaleToChart(long chart_id, const string sym);     // LOT D B-RESIZE-ALL
void ApplyComfortScaleAllCharts(void);                              // LOT D B-RESIZE-ALL
bool ComputeBasketBreakeven(const string symbol, double &out_be_price,
                            bool &out_is_hedged_flat, double &out_flat_pnl,
                            string &out_reason); // LOT D B-BE-UNIFIED
ENUM_RC_STATUS ComputeRangeStatus(double v, double max_v, double warn_ratio, double red_ratio);

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
datetime Live_NextMedNewsEvt(void); // v2.02.05 FIX 2b : MEDIUM vigilance (never the rule)
int Live_OpenPositionsCount(void);

// T7 state + helpers
void UpdatePeakEquity(void);
void LoadOrSeedPeakBalance(void); // v2.02.05 : per-login peak persistence + self-healing seed
// v2.13 FEATURE C : per-login config persistence (account-profile settings)
string LoginKey(const string base);
bool GVGetLogin(const string base, double &v);
void GVSetLogin(const string base, const double v);
// v2.13 FEATURE B : SL-vs-limit guard (20% survival margin)
double Live_NearestLimitRoom(void);
bool Live_SlGuardBreached(string &reco_sym, double &reco_sl);
double ComputePositionRiskMoney(const string sym, const int type,
                                const double price_open, const double sl,
                                const double vol, const double costs = 0.0); // Phase 3.5 : net-of-costs, direction-aware
void RefreshSlLines(void);
void RefreshNewsZones(void);
// v2.03 F1-F2 : ForexFactory feed fetch (throttled) + FF-side rule/vigilance helpers
void FetchFFCalendar(void);
bool FFLoadFromFile(void);           // file bridge (indicator-safe FF path + warm cache)
void FFSaveToFile(const string json);
bool FFRestrictedOverride(const string ccy, const string title);
datetime FFNextEvt(const bool restricted_class);
bool FFInNewsWindow(void);
string FormatAge(int seconds);
string PositionStatusLabel(ENUM_RC_STATUS s, int age, bool sl_missing);
void TryFireSoundAlert(int idx, ENUM_RC_STATUS new_status);
bool PositionListChanged(void);
void SnapshotPositionList(void);

// Telegram (B1) - alert dispatcher + low-level sender
string EscapeJson(const string s);
bool SendTelegramMessage(const string text);

// Safe Pyramiding advisor (D, art. 22187)
bool BuildPyramidLine(string &line, int &stat);

// Post-violation tightening (B7)
double EffectiveMarginCap(void);
double EffectiveRiskCap(void);
bool   ProfileCanBeRestricted(void);
void PersistViolationFlags(void);

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
void PersistMaxParallel(void);
void RefreshSlLinesForChart(const long chart_id);
void RefreshNewsZonesForChart(const long chart_id);
string NewsAbbrev(const string name); // N10 : short code for top news caption
int g_max_parallel = 5; // runtime-mutable; init from InpMaxParallelPositions

// B8 : recent-symbols quick-switch bar (FIFO, max 4, most-recent-first).
// Rebuilt from open positions + recent deals (history persists -> no need to
// store strings in GlobalVariable, which only holds doubles anyway).
#define RC_MAX_RECENT_SYMS 4
// LOT A : per-row LIVE status mirror. RefreshPositionsList (and the SL>REC override in
// RefreshSlLinesForChart) write it ; RepaintCanvas reads it to tint the row's status
// pill on the canvas. OnTimer order (RefreshPanel THEN RepaintCanvas) keeps it fresh.
ENUM_RC_STATUS g_pos_status[RC_MAX_POSITIONS];
// FINAL (mockup .chip) : SWAP / Split chip rects, PANEL-RELATIVE offsets. ONE geometry
// source : DrawAccountStrip computes + stores them (and centers its labels on them) ;
// RepaintCanvas paints the tinted pill faces from the SAME offsets -> drag-proof,
// label/face can never desync (the BE lesson). w == 0 -> chips not drawn.
int g_chip_swap_dx = 0, g_chip_swap_w = 0, g_chip_split_dx = 0, g_chip_split_w = 0;
int    g_tfbar_y  = 0;    // P4 : y of the TF/control bar (copy-lot fields live here)
int    g_footer_y = 0;    // P1 : y of the footer block (coloured info segments)

// B2 : drag-to-move panel. g_anchor_x/y = live panel origin (init from
// InpAnchorX/Y, restored from GlobalVariable, persisted on drop).

// v1.4.1 R3 : HIT-TESTING for canvas-drawn ROUNDED controls (an OBJ_BUTTON is
// opaque + square). Each drawn control registers a zone + action string ; the
// CHARTEVENT_CLICK handler routes clicks by coordinate. Zones are stored RELATIVE
// to the panel anchor (g_anchor_x/y) so a DRAG never invalidates them : MovePanelBy
// shifts the objects, the anchor tracks the drag, and the relative offset is fixed.
// v1.4.1 R3 : a zone's FACE style. The registry is the SINGLE source of a
// control's geometry : hit-testing reads the (relative) rect, and RepaintCanvas
// paints the matching rounded face from the SAME rect (local = relative + margin).
// So faces + click zones can never drift, and both are drag-proof by design.
#define RCF_NONE      0   // no face (label-only / row overlay / tf drawn separately)
#define RCF_BTN       1   // flat rounded button (surface)
#define RCF_BTN_ON    2   // rounded button, accent fill (active)
#define RCF_BTN_RED   3   // rounded button, red edge (X / danger)
#define RCF_PILL_OFF  4   // sliding pill toggle, OFF (knob left)
#define RCF_PILL_ON   5   // sliding pill toggle, ON  (knob right, accent)
#define RCF_BTN_GHOST 6   // E5 : outline-only (ghost) button - 1px ring on the panel bg

struct RCHit { int x1, y1, x2, y2; string act; int idx; int style; };
// D-FULL step 1 : the modal's hit-zones are always registered LAST (DrawSettingsOverlay
// runs after the panel sections). This base index lets DestroySettingsOverlay TRUNCATE
// them cleanly on close/tab-switch without touching the panel zones. -1 = modal closed.
int g_modal_hit_base = -1;
// Drop the (act, idx) zone so PaintFaces paints no ghost face for a control that just
// disappeared on a standalone redraw (e.g. a recent-symbol slot that emptied). Zones
// never overlap, so a swap-with-last removal keeps HitTest correct.
// Paint one control face at LOCAL canvas coords (relative rect + RC_KIT_MARGIN).
// Paint every registered face into g_kit (called from RepaintCanvas, in-frame).
// AUDIT 2026-06-07 fix #5 : hoisted from BuildPanel so the discipline-lock
// overlay can cover the FULL panel (was ~title+1 row = ~8 % of the panel).
// V1.20 G3 settings popup : runtime overrides (persisted in GV) so the user
// can change language / theme / prop preset without re-opening MT5's Inputs
// dialog. -1 = use the Input as-is.
int  g_active_plan_idx  = -1;   // -1 = InpPlan, else cast to ENUM_FN_PLAN
int  g_active_theme_idx = -1;   // -1 = InpTheme, else 0 = DARK, 1 = LIGHT
int  g_active_palette_idx = -1; // v2.02 : -1 = InpPalette, else 0..2 (Emeraude / Indigo / Ardoise)
int  g_settings_tab     = 0;    // 0=Account 1=Risk 2=Display 3=Alerts
// D-FULL step 3 : g_swallow_click REMOVED. It existed because native modal OBJ_BUTTONs
// emitted an OBJECT_CLICK paired with a trailing CHARTEVENT_CLICK that could leak to a
// panel zone. The modal is 100% hit-testing now : one CLICK = one dispatch, and the
// full-modal "set_noop" zone swallows anything that misses a control.
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
bool   g_eff_news_med      = true; // v2.02.05 FIX 2d : MEDIUM = informational VIGILANCE only ; the FN 40%
                                   // rule is HIGH-only, but MQL5 under-classes some FN-high events as
                                   // MEDIUM (central-bank speeches) -> shown as "check FN", never the rule
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
    bool   floor_capped;          // v2.13 B1 : budget capped at 80% of the nearest-limit room (20% survival margin)
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
    { // v2.13 FEATURE C : plan choice follows the LOGIN (legacy global = seed)
        double plan_gv = 0.0;
        if (GVGetLogin("RC_plan_override", plan_gv)) {
            g_active_plan_idx = (int)plan_gv;
            GVSetLogin("RC_plan_override", plan_gv);
        }
    }
    // V1.27 : a stale non-MT5 Futures plan restored from GV isn't in the cascade
    // -> normalise it to FundedNext's first type so broker/type steppers stay sane.
    if (g_active_plan_idx == (int)FN_PLAN_FUTURES_BOLT ||
        g_active_plan_idx == (int)FN_PLAN_FUTURES_RAPID ||
        g_active_plan_idx == (int)FN_PLAN_FUTURES_LEGACY) {
        ENUM_FN_PLAN vp[];
        PlansForVendor(0, vp);
        g_active_plan_idx = (int)vp[0];
        GVSetLogin("RC_plan_override", (double)g_active_plan_idx); // v2.13 C : per-login
    }
    if (GlobalVariableCheck("RC_theme_override"))
        g_active_theme_idx = (int)GlobalVariableGet("RC_theme_override");
    if (GlobalVariableCheck("RC_palette_override")) // v2.02 : restore BEFORE the first InitTheme
        g_active_palette_idx = (int)GlobalVariableGet("RC_palette_override");
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

    // v3 : mouse-move events feed the shell (drag of the floating table +
    // hover-intent tooltips). The legacy panel anchor died with the panel.
    ChartSetInteger(0, CHART_EVENT_MOUSE_MOVE, true);

    // Free-account detection note (Server 3 / demo = free/competition heuristic).
    // No silent override: the user picks Free Trial / Free Competition in InpPlan.
    {
        const string srv = AccountInfoString(ACCOUNT_SERVER);
        const string co  = AccountInfoString(ACCOUNT_COMPANY);
        if ((StringFind(srv, "Server 3") >= 0 || StringFind(srv, "Demo") >= 0) &&
            InpPlan != FN_PLAN_FREE_TRIAL && InpPlan != FN_PLAN_FREE_COMPETITION &&
            StringFind(srv, "AvaTrade") < 0 && StringFind(co, "AvaTrade") < 0 && InpVerboseLog) // LOG CLEANUP : one-time info, gated
            Print("RiskCockpit : free/competition server detected ('", srv,
                  "'). If this is a Free Trial or Free Competition, select it in InpPlan.");
        // B-AVATRADE-PROFILE : suggest the Personal plan on broker-perso servers
        // (AvaTrade and any non-prop broker) so the panel runs without imposing
        // fake FundedNext rules. No silent override : JR picks the right plan.
        const bool is_personal_broker = (StringFind(srv, "AvaTrade") >= 0
                                      || StringFind(srv, "Ava-")    >= 0
                                      || StringFind(co,  "AvaTrade") >= 0
                                      || StringFind(co,  "Ava ")    >= 0);
        if (is_personal_broker && InpPlan != FN_PLAN_PERSONAL && InpVerboseLog)
            Print("RiskCockpit : personal-broker server detected ('", srv,
                  "' / '", co, "'). Recommended : set InpPlan = FN_PLAN_PERSONAL to disable prop rules.");
        // LOT C : suggest the matching multi-firm preset (FTMO / E8 / The5ers /
        // SeacrestFunded) based on server pattern. Per Agent A+B research.
        if (StringFind(srv, "FTMO-") == 0 && InpPlan != FN_PLAN_FTMO_2STEP && InpVerboseLog)
            Print("RiskCockpit : FTMO server detected ('", srv,
                  "'). Recommended : set InpPlan = FN_PLAN_FTMO_2STEP.");
        if (StringFind(srv, "FivePercentOnline") >= 0 && InpPlan != FN_PLAN_THE5ERS_HIGH && InpVerboseLog)
            Print("RiskCockpit : The5ers server detected ('", srv,
                  "'). Recommended : set InpPlan = FN_PLAN_THE5ERS_HIGH.");
        if ((StringFind(srv, "E8Markets") >= 0 || StringFind(co, "E8 Markets") >= 0
          || StringFind(co, "E8 Funding") >= 0) && InpPlan != FN_PLAN_E8_8PCT && InpVerboseLog)
            Print("RiskCockpit : E8 Markets server detected ('", srv,
                  "' / '", co, "'). Recommended : set InpPlan = FN_PLAN_E8_8PCT.");
        if ((StringFind(srv, "SeacrestMarkets") >= 0 || StringFind(srv, "MyFundedFX") >= 0
          || StringFind(co,  "Seacrest") >= 0 || StringFind(co, "MyFundedFX") >= 0)
          && InpPlan != FN_PLAN_MFF_RAPID && InpVerboseLog)
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
    // v2.02.05 FIX 1 : realized-balance high-water mark, persisted PER LOGIN (GV name
    // carries the login, so switching accounts NEVER destroys another login's peak).
    LoadOrSeedPeakBalance();
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
        } else if (InpVerboseLog) { // LOG CLEANUP : one-time info, gated (the empty-token WARNING above stays ungated)
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
    // v3 SHELL : either the legacy panel OR the shell - never both (one UI owns
    // the chart). The shell reads its theme index from the palette/mode inputs so
    // a fresh attach already matches the product's brand language.
    {
        g_shell.Init();
        g_shell.SetThemeIdx((int)InpPalette * 2 + (EffectiveTheme() == RC_THEME_GLASS_DARK ? 0 : 1));
        g_shell.SetTipDelay(InpShellTipMs);
        g_shell.Create(RC_PREFIX + "V3_");
        {   // restore where the floating positions table was left, per login
            double fx = 0.0, fy = 0.0;
            GVGetLogin("RC_v3_fltx", fx);
            GVGetLogin("RC_v3_flty", fy);
            g_shell.SetFloatPos((int)fx, (int)fy);
        }
        ShellPushLabels();   // the shell's chrome speaks the product's language
        ShellRefresh();
    }

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
    g_shell.Destroy();                                 // v3 SHELL : frees its 6 canvases + restores chart flags
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
    // v3.06 : the FX canvas and the legacy repaint are gone with the old panel.
    // The cadence still self-heals when the refresh stepper changes it.
    static int s_timer_ms = 0;
    if (s_timer_ms != g_eff_refresh_ms) {
        EventKillTimer();
        EventSetMillisecondTimer(g_eff_refresh_ms);
        s_timer_ms = g_eff_refresh_ms;
    }
    RefreshPanel();
    // FIX (LOT 1) : calendar scan is HEAVY (CalendarValueHistory + per-chart loop) ;
    // news change hourly at most, so throttle the chart-side refresh to every 30 s.
    // Was the n#1 freeze cause - the panel kept updating but the event queue
    // starved while this held the thread, and OBJECT_CLICK never fired.
    if (TimeCurrent() - g_news_last_refresh >= 30) {
        FetchFFCalendar(); // v2.03 F1 : throttled internally (first tick + 1/60 min, 3 s timeout)
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

void OnChartEvent(const int id, const long& lparam, const double& dparam, const string& sparam) {
    // v3 SHELL : ONE dispatcher. When the shell is on it owns clicks + hover ; the
    // legacy hit registry never sees them (two registries must never consume the
    // same click). CHART_CHANGE still falls through : the chart-side news markers
    // keep their re-pin, and the shell rebuilds its surfaces at the end of it.
    if (g_shell.Created()) {
        if (id == CHARTEVENT_CLICK) {
            g_shell.OnClick((int)lparam, (int)dparam);
            if (g_shell.PendKillTake()) {          // navbar X : remove this instance
                int kwin2 = ChartWindowFind();
                if (kwin2 < 0) kwin2 = 0;
                g_shell.Destroy();
                ObjectsDeleteAll(0, RC_PREFIX);
                ChartIndicatorDelete(0, kwin2, "RiskCockpit");
                ChartRedraw(0);
            }
            return;
        }
        if (id == CHARTEVENT_MOUSE_MOVE) {
            // the floating table is dragged by its header ; sparam == "1" while the
            // left button is held. Drag first : it must win over tooltip intent.
            const bool ldown = (sparam == "1");
            const bool was   = g_shell.Dragging();
            g_shell.OnMouseDrag((int)lparam, (int)dparam, ldown);
            if (g_shell.Dragging()) return;                  // dragging : nothing else to do
            if (was) {                                       // just dropped : remember where
                int fx, fy;
                g_shell.FloatPos(fx, fy);
                GVSetLogin("RC_v3_fltx", (double)fx);
                GVSetLogin("RC_v3_flty", (double)fy);
            }
            g_shell.OnMouseMove((int)lparam, (int)dparam);
            return;
        }
    }
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
            ObjectSetDouble(0, nm, OBJPROP_PRICE, pmin + rng * (0.02 + 0.018 * lane)); // keep OBJPROP_TIME (x follows natively) ; v2.03.05c FIX 4 : baseline synced with RefreshNewsZonesForChart (0.02)
        }
        // v3 SHELL : surfaces are destroyed + recreated (the zones moved) and the
        // hover state is reset - the playbook's OnChartChange rule.
        if (g_shell.Created()) g_shell.OnChartChange();
        ChartRedraw(0);
        return;
    }

    // v3.06 : no native control is left on the chart (the shell is 100 %
    // hit-testing) - CHARTEVENT_OBJECT_CLICK has nothing to route.
}

//+------------------------------------------------------------------+
//| OnTradeTransaction - instant SL-line + position-list refresh     |
//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction& trans,
                        const MqlTradeRequest& request,
                        const MqlTradeResult& result) {
    if (trans.type == TRADE_TRANSACTION_POSITION || trans.type == TRADE_TRANSACTION_DEAL_ADD || trans.type == TRADE_TRANSACTION_DEAL_UPDATE || trans.type == TRADE_TRANSACTION_DEAL_DELETE || trans.type == TRADE_TRANSACTION_HISTORY_ADD) {
        RefreshSlLines();       // SL / TP advisory lines follow the position set
        SnapshotPositionList();
        // all positions closed -> auto-disarm BE so it never lingers "on" with
        // nothing to break-even ; otherwise re-sync the basket line.
        if (g_be_visible && PositionsTotal() == 0) {
            g_be_visible = false; PersistBE(); ClearBreakevenLines();
        } else if (g_be_visible) {
            DrawBreakevenLines();
        }
        RefreshPanel();         // v3.06 : the shell redraws with the new basket
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

void DestroyAllObjects(void) {
    ObjectsDeleteAll(0, RC_PREFIX);
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

// Full-panel red STOP overlay used by self-lock / daily-DD / cooldown.

// V1.24 fix (JR test #2) : returns TRUE if a HARD LOCK (self-lock / daily-DD /
// cooldown) is active - it has then drawn the full-panel STOP + hidden the
// controls, and the caller (RefreshPanel) MUST skip its content so the rows /
// bars are not recreated on top of the overlay every tick (MT5 redraws rectangle
// labels in creation order, not ZORDER). Returns FALSE otherwise (red overlay
// cleared, controls shown). The soft TILT banner is handled by DrawTiltBanner().
// FIX lock-lifecycle : the previous tick's hard-lock state, so RefreshPanel can detect
// the lock -> clear TRANSITION and force ONE full rebuild (during the lock the refresh
// is skipped and the overlay hid/covered objects -> without a rebuild the panel came
// back half-rendered ; a risk tool must always re-display its full state).
bool g_disc_locked_prev = false;

//+------------------------------------------------------------------+
//| RefreshPanel - reads stub values and updates labels/bars          |
//| T7 will replace the Stub_ calls with real implementations.       |
//+------------------------------------------------------------------+
//+------------------------------------------------------------------+
//| v3 SHELL (lot 1) : model -> view bridge.                          |
//|                                                                   |
//| BuildDeckData reads the SAME Live_* functions the legacy rows use  |
//| - ZERO new risk math, so the shell can never disagree with the     |
//| panel it replaces. The shell is a pure VIEW : it decides nothing.  |
//+------------------------------------------------------------------+
string ShellPlanTag(void) {
    switch (EffectivePlan()) {
        case FN_PLAN_STELLAR_1STEP:    return "1STP";
        case FN_PLAN_STELLAR_2STEP:    return "2STP";
        case FN_PLAN_STELLAR_LITE:     return "LITE";
        case FN_PLAN_STELLAR_INSTANT:  return "INST";
        case FN_PLAN_FREE_TRIAL:       return "TRIAL";
        case FN_PLAN_FREE_COMPETITION: return "COMP";
        case FN_PLAN_FTMO_2STEP:       return "FTMO";
        case FN_PLAN_E8_8PCT:          return "E8";
        case FN_PLAN_THE5ERS_HIGH:     return "5ERS";
        case FN_PLAN_MFF_RAPID:        return "MFF";
        case FN_PLAN_PERSONAL:         return "PERSO";
    }
    return "--";
}
void BuildDeckData(RCDeckData &d) {
    const double init = g_profile.initial_balance;
    // --- session / account ---------------------------------------------
    // v3.00 FIX : the health badge used to come from ComputeVerdict(), which
    // reads g_rows[] — and g_rows is filled by RefreshPanel, which the shell
    // SHORT-CIRCUITS. The badge therefore froze on the startup value (a red
    // rail next to a green "SAIN 100/100", seen on JR's capture). It is now
    // computed from the SAME live ratios the rail draws : one source, no stale
    // read. Thresholds unchanged (>=100% breach, >=80% watch), profit target
    // still excluded — it is a goal, not a risk.
    d.equity      = AccountInfoDouble(ACCOUNT_EQUITY);
    d.balance     = AccountInfoDouble(ACCOUNT_BALANCE);
    d.sym         = _Symbol;
    d.tf          = StringSubstr(EnumToString((ENUM_TIMEFRAMES)ChartPeriod(0)), 7);
    d.planTag     = ShellPlanTag();
    d.sizeTag     = SizeLabel();
    StringReplace(d.sizeTag, "$", "");
    d.splitPct    = (int)MathRound(g_profile.profit_split_pct);
    d.riskTools   = g_eff_risktools;
    // --- limits (cell LIM) ----------------------------------------------
    d.marginPct = Live_CumulativeMarginPct(); d.marginCap = EffectiveMarginCap();
    d.riskPct   = Live_CumulativeRiskPct();   d.riskCap   = EffectiveRiskCap();
    d.dailyPct  = Live_DailyDdPct();          d.dailyCap  = g_profile.daily_loss_pct;
    d.overallPct= Live_OverallDdPct();        d.overallCap= g_profile.max_loss_pct;
    d.dailyApplies   = (d.dailyCap > 0.0);
    d.overallApplies = (d.overallCap > 0.0);
    d.trailing       = g_profile.max_loss_trailing;
    double worst = 0.0;
    if (d.marginCap > 0.0)              worst = MathMax(worst, d.marginPct  / d.marginCap);
    if (d.riskCap > 0.0)                worst = MathMax(worst, d.riskPct    / d.riskCap);
    if (d.dailyApplies)                 worst = MathMax(worst, d.dailyPct   / d.dailyCap);
    if (d.overallApplies)               worst = MathMax(worst, d.overallPct / d.overallCap);
    d.limRatio  = worst;
    // verdict + health score, derived from the ratios just computed
    d.score       = (int)MathRound(100.0 * (1.0 - MathMin(1.0, MathMax(0.0, worst))));
    d.verdict     = (worst >= 1.0 ? 2 : (worst >= 0.80 ? 1 : 0));
    d.verdictWord = Tr(d.verdict == 2 ? "v_violation" : (d.verdict == 1 ? "v_atrisk" : "v_ontrack"));
    d.roomMoney = Live_NearestLimitRoom();                 // -1 = no active limit
    d.floorMoney = 0.0;
    if (d.trailing && init > 0.0) {
        const double permitted = (g_profile.max_loss_pct / 100.0) * init;
        d.floorMoney = MathMin(g_peak_balance - permitted, init);
    }
    // --- positions (cell POS + section rows) -----------------------------
    d.posCount = PositionsTotal();
    d.posPnl   = 0.0;
    d.posNoSl  = false;
    d.posN     = 0;
    for (int i = 0; i < d.posCount; ++i) {
        const ulong tk = PositionGetTicket(i);
        if (tk == 0 || !PositionSelectByTicket(tk)) continue;
        const double rp  = PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
        const bool   hsl = (PositionGetDouble(POSITION_SL) > 0.0);
        d.posPnl += rp;
        if (!hsl) d.posNoSl = true;
        if (d.posN < 8) {                                  // 8 rows shown, the rest is announced
            const int k = d.posN;
            d.posSym[k]    = PositionGetString(POSITION_SYMBOL);
            d.posSide[k]   = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY ? "BUY" : "SELL");
            d.posVol[k]    = PositionGetDouble(POSITION_VOLUME);
            d.posRowPnl[k] = rp;
            d.posAge[k]    = (int)(TimeCurrent() - (datetime)PositionGetInteger(POSITION_TIME));
            d.posHasSl[k]  = hsl;
            d.posStat[k]   = (hsl ? (rp >= 0.0 ? 0 : 1) : 2);   // no SL = the only red row state
            d.posN++;
        }
    }
    // --- discipline (cell DISC) + SL guard --------------------------------
    string gsym = ""; double gsl = 0.0;
    d.slGuard    = Live_SlGuardBreached(gsym, gsl);
    d.slGuardSym = gsym;
    d.slGuardPrice = gsl;
    d.discLocked = (g_selflock_until > TimeCurrent());
    d.selfLock   = d.discLocked;
    d.lockMinsLeft = (d.discLocked ? (int)((g_selflock_until - TimeCurrent()) / 60) + 1 : 0);
    d.discTilt   = (g_eff_discipline && ((g_eff_tilt_n > 0 && g_disc_trades_win > g_eff_tilt_n) || g_disc_revenge));
    d.tiltTrades = g_disc_trades_win;
    d.tiltN      = g_eff_tilt_n;
    d.tiltWinMin = g_eff_tilt_win;
    d.tradesToday = Live_TradesToday();
    d.tradesCap   = g_profile.hyperactivity_trades_per_day;
    d.posWorst    = (d.posCount <= 0 ? 3 : (d.posNoSl ? 2 : (d.slGuard ? 1 : 0)));
    d.pyrOn       = BuildPyramidLine(d.pyrText, d.pyrStat);
    // v3.06 : week-end hold. The legacy clock blinked it AND fired the alert ;
    // the shell had neither. The alert keeps its own once-per-window latch.
    d.weekendHold = IsWeekendHoldRisk();
    // v3.11 : say which controls the host will refuse to act on
    d.rtoolsLocked = !PlanIsPersonal();          // prop plan : toolkit forced ON
    d.violLocked   = !ProfileCanBeRestricted();  // the flags would be reset at once
    if (d.weekendHold) FireWeekendAlert(); else g_weekend_warned = false;
    // --- lot advisor (cell LOT) -------------------------------------------
    SuggestedLot s;
    if (Live_ComputeSuggestedLot(s)) {
        d.sugLot        = s.broker_lot;
        d.lotDigits     = LotDigits(s.vol_step);
        d.lotCapped     = s.floor_capped;
        d.lotZero       = (s.floor_capped && s.risk_budget_money <= 0.005);
        d.budgetPct     = s.budget_pct;
        d.budgetMoney   = s.risk_budget_money;
        d.freeMarginPct = s.free_margin_pct;
        d.nPlanned      = s.n_planned;
    } else {
        d.sugLot = 0.0; d.lotDigits = 2; d.lotCapped = false; d.lotZero = false;
        d.budgetPct = 0.0; d.budgetMoney = 0.0; d.freeMarginPct = 0.0; d.nPlanned = 0;
    }
    d.spreadPts  = (double)SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
    d.commPerLot = CommissionPerLot(_Symbol);              // -1 when the broker books none
    // --- v3.01 parity : the legacy rule rows the shell was missing ----------
    {   // largest openable lot + which cap binds (SHARED implementation)
        double mpct = 0.0, avail = 0.0, cused = 0.0, ccap = 0.0;
        string mtag = ""; int mld = 2;
        d.maxLot       = Live_MaxLot(mpct, mtag, mld, avail, cused, ccap);
        d.maxLotDigits = mld;
        d.maxLotPct    = mpct;
        d.maxLotTag    = mtag;
    }
    d.targetPct = Live_ProfitTargetPct();
    d.targetCap = g_profile.profit_target_pct;
    d.qsPct     = Live_QuickStrikeRatioPct();
    d.qsCap     = g_profile.quick_strike_violate_pct;
    d.msgsToday = Live_OrdersToday();
    d.msgsCap   = g_profile.hyperactivity_msgs_per_day;
    ComputeNewsStats();                                    // cached ~60 s inside
    d.newsTrades   = g_news_trades;
    d.newsPnl      = g_news_pnl;
    d.newsEligible = g_news_eligible;
    // --- news (cell NEWS) --------------------------------------------------
    const datetime nevt = Live_NextNewsEvt();              // RULE class (FF restricted / MT5 HIGH)
    d.newsFF     = g_ff_active;
    d.newsActive = Live_InNewsWindow();
    d.newsHasEvt = (nevt > 0);
    d.newsHigh   = d.newsHasEvt;                           // the rule class is the red one
    d.newsMins   = (nevt > 0 ? (int)((nevt - TimeCurrent()) / 60) : 0);
    if (d.newsMins < 0) d.newsMins = 0;
    if (!d.newsHasEvt) {                                   // no rule event : medium vigilance
        const datetime mevt = Live_NextMedNewsEvt();
        if (mevt > 0) {
            d.newsHasEvt = true;
            d.newsHigh   = false;
            d.newsMins   = (int)((mevt - TimeCurrent()) / 60);
            if (d.newsMins < 0) d.newsMins = 0;
        }
    }
    // news-window meter (legacy row 8) : ramps over the hour before the window,
    // full while the window is open, empty otherwise.
    d.newsMeterPct = 0.0;
    if (d.newsActive)        d.newsMeterPct = 100.0;
    else if (d.newsHasEvt) {
        const int win = (g_profile.news_window_minutes > 0 ? g_profile.news_window_minutes : 5);
        const double mins_to_win = (double)d.newsMins - (double)win;
        if (mins_to_win <= 0.0)      d.newsMeterPct = 100.0;
        else if (mins_to_win < 60.0) d.newsMeterPct = 100.0 * (60.0 - mins_to_win) / 60.0;
    }
    // --- news detail : next groups, SAME grouping key as the timeline -------
    // (release time x currency x level) - one row per group, rule + vigilance,
    // ordered by time, capped at 6 (the section states the cap honestly).
    d.newsWinMin   = (g_profile.news_window_minutes > 0 ? g_profile.news_window_minutes : 5);
    d.newsSharePct = g_profile.news_profit_share_pct;
    d.newsN        = 0;
    {
        datetime ct[64]; string cc[64]; bool cr[64];
        int nc = 0;
        const datetime now_s = TimeCurrent(), end_s = now_s + 24 * 60 * 60;
        if (g_ff_active) {
            const int srv_off = (int)(TimeCurrent() - TimeGMT());
            for (int i = 0; i < ArraySize(g_ff_events) && nc < 64; ++i) {
                const datetime ts = g_ff_events[i].t_utc + srv_off;
                if (ts < now_s || ts > end_s) continue;
                if (g_ff_events[i].restricted  && !g_eff_news_high) continue;
                if (!g_ff_events[i].restricted && !g_eff_news_med)  continue;
                ct[nc] = ts; cc[nc] = g_ff_events[i].ccy; cr[nc] = g_ff_events[i].restricted; nc++;
            }
        } else {
            MqlCalendarValue vals[];
            if (CalendarValueHistory(vals, now_s, end_s, NULL, NULL) > 0) {
                for (int i = 0; i < ArraySize(vals) && nc < 64; ++i) {
                    MqlCalendarEvent ev;
                    if (!CalendarEventById(vals[i].event_id, ev)) continue;
                    const bool hi = (ev.importance == CALENDAR_IMPORTANCE_HIGH);
                    const bool md = (ev.importance == CALENDAR_IMPORTANCE_MODERATE);
                    if (!hi && !md) continue;
                    if (hi && !g_eff_news_high) continue;
                    if (md && !g_eff_news_med)  continue;
                    MqlCalendarCountry cy;
                    if (!CalendarCountryById(ev.country_id, cy)) continue;
                    ct[nc] = vals[i].time; cc[nc] = cy.currency; cr[nc] = hi; nc++;
                }
            }
        }
        for (int a = 0; a < nc - 1; ++a)                   // chronological (the feed is not guaranteed sorted)
            for (int b = a + 1; b < nc; ++b)
                if (ct[b] < ct[a]) {
                    const datetime tt = ct[a]; ct[a] = ct[b]; ct[b] = tt;
                    const string   ss = cc[a]; cc[a] = cc[b]; cc[b] = ss;
                    const bool     bb = cr[a]; cr[a] = cr[b]; cr[b] = bb;
                }
        for (int i = 0; i < nc && d.newsN < 6; ++i) {      // one row per group (dedup)
            const string when = TimeToString(ct[i], TIME_MINUTES);
            bool dup = false;
            for (int k = 0; k < d.newsN; ++k)
                if (d.newsWhen[k] == when && d.newsCcy[k] == cc[i] && d.newsRestr[k] == cr[i]) { dup = true; break; }
            if (dup) continue;
            d.newsWhen[d.newsN] = when; d.newsCcy[d.newsN] = cc[i]; d.newsRestr[d.newsN] = cr[i];
            d.newsN++;
        }
    }
    // --- account card + config toggles (sections CPT / CFG / AIDE) ---------
    d.planLabel     = g_catalog.ModelLabel(EffectivePlan());
    d.phaseLabel    = PhaseLabelLocal(g_eff_phase);
    d.sizeLabelFull = SizeLabel();
    d.acctTypeLabel = (EffectivePlan() == FN_PLAN_PERSONAL
                       ? (g_eff_personal_demo == 1 ? "DEMO" : "REAL")
                       : (g_eff_acct_type == 1 ? "SWAP-FREE" : "SWAP"));
    d.login         = AccountInfoInteger(ACCOUNT_LOGIN);
    d.minDays       = g_profile.min_trading_days;
    d.minDaysDone   = 0;                                   // filled by the strip logic when available
    d.cycleLabel    = "";
    d.addonsLabel   = "";
    {   // active add-ons, short list (same mask the footer prints)
        string ad = "";
        if ((g_addons_mask & FN_ADDON_LIFETIME_95) != 0) ad += "95% ";
        if ((g_addons_mask & FN_ADDON_NO_MIN_DAYS) != 0) ad += "NoMinDays ";
        if ((g_addons_mask & FN_ADDON_SWAP_FREE)   != 0) ad += "SwapFree ";
        if ((g_addons_mask & FN_ADDON_10PCT_DD)    != 0) ad += "10%DD ";
        if ((g_addons_mask & FN_ADDON_DOUBLE_UP)   != 0) ad += "DoubleUp ";
        if ((g_addons_mask & FN_ADDON_BI_WEEKLY)   != 0) ad += "BiWeekly ";
        d.addonsLabel = (StringLen(ad) > 0 ? ad : Tr("addons_none"));
    }
    d.cfgNewsHigh   = g_eff_news_high;
    d.cfgNewsMed    = g_eff_news_med;
    d.cfgSound      = g_eff_sound;
    d.cfgTelegram   = g_eff_telegram;
    d.cfgComfort    = g_eff_comfort;
    d.cfgDiscipline = g_eff_discipline;
    d.lang          = g_lang;
    d.version       = "3.02";
    // v3.04 : add-ons VALID for this plan, violation flags, self-lock, cycle date
    {
        int    flags[7]; string names[7];
        flags[0] = FN_ADDON_LIFETIME_95; names[0] = "Lifetime 95%";
        flags[1] = FN_ADDON_NO_MIN_DAYS; names[1] = "No Min Days";
        flags[2] = FN_ADDON_SWAP_FREE;   names[2] = "Swap-Free";
        flags[3] = FN_ADDON_10PCT_DD;    names[3] = "10% Total DD";
        flags[4] = FN_ADDON_DOUBLE_UP;   names[4] = "Double Up";
        flags[5] = FN_ADDON_BI_WEEKLY;   names[5] = "Bi-Weekly";
        flags[6] = FN_ADDON_150_REWARD;  names[6] = "150% Reward";
        const int valid = g_catalog.ValidAddonsMask(EffectivePlan());
        d.addonN = 0;
        for (int i = 0; i < 7; ++i) {
            if ((valid & flags[i]) == 0) continue;          // not purchasable on this plan
            d.addonName[d.addonN] = names[i];
            d.addonOn[d.addonN]   = ((g_addons_mask & flags[i]) != 0);
            d.addonN++;
        }
    }
    d.violMargin = g_margin_violation_active;
    d.violRisk   = g_risk_violation_active;
    d.beLines    = g_be_visible;
    d.selfLockH  = g_eff_selflock_h;
    {
        double ymd = g_eff_cycle_ymd;
        if (ymd <= 0.0) ymd = IsoToYmd(InpCycleStartIso);
        d.cycY = (int)ymd / 10000;
        d.cycM = ((int)ymd / 100) % 100;
        d.cycD = (int)ymd % 100;
    }
    // v3.02 : the settings rows of the ACTIVE tab + the plan cascade
    {
        string lab[], val[];
        d.stepN = ShellStepRows(g_shell.CfgTab(), lab, val);
        for (int i = 0; i < d.stepN && i < 10; ++i) { d.stepLabel[i] = lab[i]; d.stepValue[i] = val[i]; }
        string clab[], cval[];
        d.casN = ShellCascadeRows(clab, cval);
        for (int i = 0; i < d.casN && i < 5; ++i) { d.casLabel[i] = clab[i]; d.casValue[i] = cval[i]; }
    }
    // --- clocks -------------------------------------------------------------
    d.clockSrv = TimeToString(TimeCurrent(), TIME_MINUTES);
    d.clockGmt = TimeToString(TimeGMT(),     TIME_MINUTES);
    d.clockLoc = TimeToString(TimeLocal(),   TIME_MINUTES);
}
// v3 SHELL : push the product's i18n into the shell's label slots. The shell
// ships FR defaults ; whatever we set here wins, so ONE translation table
// (AddTr) serves the legacy panel AND the shell.
void ShellPushLabels(void) {
    g_shell.SetLabel(RCL_SEC_LIM,   Tr("shl_lim"));
    g_shell.SetLabel(RCL_SEC_POS,   Tr("shl_pos"));
    g_shell.SetLabel(RCL_SEC_LOT,   Tr("shl_lot"));
    g_shell.SetLabel(RCL_SEC_NEWS,  Tr("shl_news"));
    g_shell.SetLabel(RCL_SEC_DISC,  Tr("shl_disc"));
    g_shell.SetLabel(RCL_SEC_CPT,   Tr("shl_cpt"));
    g_shell.SetLabel(RCL_SEC_CFG,   Tr("shl_cfg"));
    g_shell.SetLabel(RCL_SEC_HELP,  Tr("shl_help"));
    g_shell.SetLabel(RCL_LIM_HEAD,  Tr("shl_limhead"));
    g_shell.SetLabel(RCL_LIM_MARGIN,Tr("rule_margin_cum"));
    g_shell.SetLabel(RCL_LIM_RISK,  Tr("rule_risk_cum"));
    g_shell.SetLabel(RCL_LIM_DAILY, Tr("rule_daily_dd"));
    g_shell.SetLabel(RCL_LIM_OVERALL, Tr("rule_overall_dd"));
    g_shell.SetLabel(RCL_SURV_HEAD, Tr("shl_survhead"));
    g_shell.SetLabel(RCL_ROOM,      Tr("shl_room"));
    g_shell.SetLabel(RCL_BUDGET80,  Tr("shl_budget80"));
    g_shell.SetLabel(RCL_FLOOR,     Tr("ins_tip_floor"));
    g_shell.SetLabel(RCL_FLOOR_WARN,Tr("ins_tip_floor2"));
    g_shell.SetLabel(RCL_NOLIMIT,   Tr("shl_nolimit"));
    g_shell.SetLabel(RCL_POS_NONE,  Tr("shl_posnone"));
    g_shell.SetLabel(RCL_POS_PNL,   Tr("shl_pospnl"));
    g_shell.SetLabel(RCL_NOSL,      Tr("shl_nosl"));
    g_shell.SetLabel(RCL_LOT_FROM,  Tr("shl_lotfrom"));
    g_shell.SetLabel(RCL_LOT_BUDGET,Tr("shl_lotbudget"));
    g_shell.SetLabel(RCL_LOT_N,     Tr("shl_lotn"));
    g_shell.SetLabel(RCL_LOT_FREE,  Tr("shl_free"));
    g_shell.SetLabel(RCL_LOT_COST,  Tr("shl_lotcost"));
    g_shell.SetLabel(RCL_SPREAD,    Tr("shl_spread"));
    g_shell.SetLabel(RCL_COMM,      Tr("shl_comm"));
    g_shell.SetLabel(RCL_NEWS_SRC,  Tr("shl_newssrc"));
    g_shell.SetLabel(RCL_NEWS_STATE,Tr("shl_newsstate"));
    g_shell.SetLabel(RCL_NEWS_WIN,  Tr("shl_newswin"));
    g_shell.SetLabel(RCL_NEWS_NEXT, Tr("shl_newsnext"));
    g_shell.SetLabel(RCL_DISC_STATE,Tr("shl_discstate"));
    g_shell.SetLabel(RCL_DISC_DAY,  Tr("shl_discday"));
    g_shell.SetLabel(RCL_CPT_PLAN,  Tr("set_type"));   // the catalog calls it the plan TYPE
    g_shell.SetLabel(RCL_CPT_PHASE, Tr("set_phase"));
    g_shell.SetLabel(RCL_CPT_SIZE,  Tr("set_size"));
    g_shell.SetLabel(RCL_CPT_TYPE,  Tr("set_acct_type"));
    g_shell.SetLabel(RCL_CPT_ADDONS,Tr("addons_lbl"));
    g_shell.SetLabel(RCL_CPT_SPLIT, Tr("shl_split"));
    g_shell.SetLabel(RCL_CPT_DAYS,  Tr("shl_mindays"));
    g_shell.SetLabel(RCL_CLOSE_EA,  Tr("shl_closeea"));
    g_shell.SetLabel(RCL_LOCK_RTOOLS, Tr("shl_lockrtools"));
    g_shell.SetLabel(RCL_LOCK_VIOL,   Tr("shl_lockviol"));
    g_shell.SetLabel(RCL_LIM_QS,        Tr("shl_qs"));
    g_shell.SetLabel(RCL_LOT_COPY,      Tr("shl_copy"));
    g_shell.SetLabel(RCL_TAG_MARG,      Tr("shl_tag_marg"));
    g_shell.SetLabel(RCL_TAG_ROOM,      Tr("shl_tag_room"));
    g_shell.SetLabel(RCL_TAG_FREE,      Tr("shl_tag_free"));
    g_shell.SetLabel(RCL_LOT_MAX,       Tr("shl_lotmax"));
    g_shell.SetLabel(RCL_NEWSTRADES,    Tr("shl_newstrades"));
    g_shell.SetLabel(RCL_ELIG,          Tr("shl_elig"));
    g_shell.SetLabel(RCL_DISC_VIOL,     Tr("shl_afterviol"));
    g_shell.SetLabel(RCL_VIOL_M,        Tr("shl_violm"));
    g_shell.SetLabel(RCL_VIOL_R,        Tr("shl_violr"));
    g_shell.SetLabel(RCL_LOCK_ON,       Tr("shl_lockon"));
    g_shell.SetLabel(RCL_LOCK_ASK,      Tr("shl_lockask"));
    g_shell.SetLabel(RCL_LOCK_ARM,      Tr("shl_lockarm"));
    g_shell.SetLabel(RCL_HYPER,         Tr("shl_hyper"));
    g_shell.SetLabel(RCL_MSGS,          Tr("shl_msgs"));
    g_shell.SetLabel(RCL_CPT_PROFILE,   Tr("shl_profile"));
    g_shell.SetLabel(RCL_CYCLE,         Tr("shl_cycle"));
    g_shell.SetLabel(RCL_YEAR,          Tr("shl_year"));
    g_shell.SetLabel(RCL_MONTH,         Tr("shl_month"));
    g_shell.SetLabel(RCL_DAY,           Tr("shl_day"));
    g_shell.SetLabel(RCL_TAB_RISK,      Tr("shl_tabrisk"));
    g_shell.SetLabel(RCL_TAB_DISC,      Tr("shl_tabdisc"));
    g_shell.SetLabel(RCL_TAB_ADV,       Tr("shl_tabadv"));
    g_shell.SetLabel(RCL_TAB_DISP,      Tr("shl_tabdisp"));
    g_shell.SetLabel(RCL_BE,            Tr("shl_belines"));
    g_shell.SetLabel(RCL_POS_MORE,      Tr("shl_more"));
    g_shell.SetLabel(RCL_RAIL_CPT,      Tr("shl_r_cpt"));
    g_shell.SetLabel(RCL_RAIL_HELP,     Tr("shl_r_help"));
    g_shell.SetLabel(RCL_FLOOR_HINT,    Tr("shl_floorhint"));
    g_shell.SetLabel(RCL_MORE_RESIZE,   Tr("shl_moresize"));
    g_shell.SetLabel(RCL_PYRAMID,       Tr("shl_pyramid"));
    g_shell.SetLabel(RCL_LOT_NOROOM,    Tr("shl_lotnoroom"));
    g_shell.SetLabel(RCL_LOT_CAP80,     Tr("shl_lotcap80"));
    g_shell.SetLabel(RCL_SRC_MT,        Tr("shl_srcmt"));
    g_shell.SetLabel(RCL_INACTIVE,      Tr("shl_inactive"));
    g_shell.SetLabel(RCL_NEWS_ACT_EL,   Tr("shl_newsactel"));
    g_shell.SetLabel(RCL_IN_MIN,        Tr("shl_inmin"));
    g_shell.SetLabel(RCL_NEWS_NONE24,   Tr("shl_none24"));
    g_shell.SetLabel(RCL_RULE40,        Tr("shl_rule40"));
    g_shell.SetLabel(RCL_CHECKFN,       Tr("shl_checkfn"));
    g_shell.SetLabel(RCL_SLG_ON,        Tr("shl_slgon"));
    g_shell.SetLabel(RCL_TILT_ON,       Tr("shl_tilton"));
    g_shell.SetLabel(RCL_ALLCLEAR,      Tr("shl_allclear"));
    g_shell.SetLabel(RCL_SELFLOCK_T,    Tr("shl_selflockt"));
    g_shell.SetLabel(RCL_DAILYLOCK,     Tr("shl_dailylock"));
    g_shell.SetLabel(RCL_ON_NOW,        Tr("shl_onnow"));
    g_shell.SetLabel(RCL_RAISE_SL,      Tr("shl_raisesl"));
    g_shell.SetLabel(RCL_NOSL_POS,      Tr("shl_noslpos"));
    g_shell.SetLabel(RCL_KEEP20,        Tr("shl_keep20"));
    g_shell.SetLabel(RCL_TRADES_N,      Tr("shl_tradesn"));
    g_shell.SetLabel(RCL_TILT_WIN,      Tr("shl_tiltwin"));
    g_shell.SetLabel(RCL_ACCOUNT_N,     Tr("shl_accountn"));
    g_shell.SetLabel(RCL_CFG_THEME,     Tr("shl_cfgtheme"));
    g_shell.SetLabel(RCL_CFG_MODE_L,    Tr("shl_cfgmode"));
    g_shell.SetLabel(RCL_LIGHT,         Tr("shl_light"));
    g_shell.SetLabel(RCL_DARK,          Tr("shl_dark"));
    g_shell.SetLabel(RCL_CFG_LANG_L,    Tr("shl_cfglang"));
    g_shell.SetLabel(RCL_ALERTS,        Tr("shl_alerts"));
    g_shell.SetLabel(RCL_SOUND,         Tr("shl_sound"));
    g_shell.SetLabel(RCL_COMFORT_H,     Tr("shl_comforth"));
    g_shell.SetLabel(RCL_COMFORT_S,     Tr("shl_comforts"));
    g_shell.SetLabel(RCL_DISC_LOCK_T,   Tr("shl_disclockt"));
    g_shell.SetLabel(RCL_RTOOLS,        Tr("shl_rtools"));
    g_shell.SetLabel(RCL_HELP_SAFE,     Tr("shl_hsafe"));
    g_shell.SetLabel(RCL_HELP_WATCH,    Tr("shl_hwatch"));
    g_shell.SetLabel(RCL_HELP_BREACH,   Tr("shl_hbreach"));
    g_shell.SetLabel(RCL_HELP_R40,      Tr("shl_hr40"));
    g_shell.SetLabel(RCL_HELP_R40A,     Tr("shl_hr40a"));
    g_shell.SetLabel(RCL_HELP_R40B,     Tr("shl_hr40b"));
    g_shell.SetLabel(RCL_HELP_SURV,     Tr("shl_hsurv"));
    g_shell.SetLabel(RCL_HELP_SURVA,    Tr("shl_hsurva"));
    g_shell.SetLabel(RCL_HELP_SURVB,    Tr("shl_hsurvb"));
    g_shell.SetLabel(RCL_HELP_ABOUT,    Tr("shl_habout"));
    g_shell.SetLabel(RCL_VERSION,       Tr("shl_version"));
    g_shell.SetLabel(RCL_NEWS_SOURCE,   Tr("shl_newssrc"));
    g_shell.SetLabel(RCL_HELP_RO1,      Tr("shl_hro1"));
    g_shell.SetLabel(RCL_HELP_RO2,      Tr("shl_hro2"));
    g_shell.SetLabel(RCL_SECS_RESIZE,   Tr("shl_secsize"));
    g_shell.SetLabel(RCL_RTOOLS_OFF,    Tr("shl_rtoolsoff"));
    g_shell.SetLabel(RCL_BAND_WKND,     Tr("shl_bandwknd"));
    g_shell.SetLabel(RCL_MINS_LEFT,     Tr("shl_minsleft"));
    g_shell.SetLabel(RCL_BAND_RAISE,    Tr("shl_bandraise"));
    g_shell.SetLabel(RCL_BAND_SLLOW,    Tr("shl_bandsllow"));
    g_shell.SetLabel(RCL_BAND_LOCKED,   Tr("shl_bandlocked"));
    g_shell.SetLabel(RCL_BAND_TRADES,   Tr("shl_bandtrades"));
    g_shell.SetLabel(RCL_BAND_SLOW,     Tr("shl_bandslow"));
    g_shell.SetLabel(RCL_NEWS_HI,       Tr("shl_newshi"));
    g_shell.SetLabel(RCL_NEWS_MED,      Tr("shl_newsmed"));
    // --- tooltips : "title|description" packed in ONE i18n entry each --------
    for (int i = 0; i < 8; ++i) g_shell.SetTip(g_shell.ZidRail(i),
        Tr("tipr_" + IntegerToString(i)));
    g_shell.SetTip(g_shell.ZidChevron(), Tr("tipr_chev"));
    for (int i = 0; i < 9; ++i) g_shell.SetTip(g_shell.ZidNav(i),
        Tr("tipn_" + IntegerToString(i)));
    g_shell.SetTip(g_shell.ZidPanel(0), Tr("tipp_close"));
    g_shell.SetTip(g_shell.ZidPanel(1), Tr("tipp_pin"));
    for (int i = 0; i < 6; ++i) g_shell.SetTip(g_shell.ZidLimTip(i),
        Tr("tipl_" + IntegerToString(i)));
    for (int i = 0; i < 3; ++i) g_shell.SetTip(g_shell.ZidLotTip(i),
        Tr("tipo_" + IntegerToString(i)));
    for (int i = 0; i < 3; ++i) g_shell.SetTip(g_shell.ZidNewsTip(i),
        Tr("tipw_" + IntegerToString(i)));
    for (int i = 0; i < 3; ++i) g_shell.SetTip(g_shell.ZidDiscTip(i),
        Tr("tipd_" + IntegerToString(i)));
    for (int i = 0; i < 10; ++i) g_shell.SetTip(g_shell.ZidCfg(i),
        Tr("tipc_" + IntegerToString(i)));
    g_shell.SetTip(g_shell.ZidBand(),    Tr("tip_band"));
    g_shell.SetTip(g_shell.ZidPosRow(),  Tr("tip_posrow"));
    g_shell.SetTip(g_shell.ZidFltClose(), Tr("tip_fltclose"));
    for (int i = 0; i < 3; ++i) g_shell.SetTip(g_shell.ZidFltQuick(i),
        Tr("tipq_" + IntegerToString(i)));
    g_shell.SetTip(g_shell.ZidCptTip(),  Tr("tip_cpt"));
    g_shell.SetTip(g_shell.ZidHelpTip(), Tr("tip_help"));
}
// v3 SHELL : a config toggle was clicked. The SHELL never mutates the model -
// the change lands HERE, on the same globals + persistence the modal uses.
void ShellApplyCfg(const int id) {
    if (id == 0) return;
    if (id == g_shell.CfgIdNewsHigh()) {
        g_eff_news_high = !g_eff_news_high;
        GlobalVariableSet("RC_news_high", g_eff_news_high ? 1.0 : 0.0);
        RefreshNewsZones();
    } else if (id == g_shell.CfgIdNewsMed()) {
        g_eff_news_med = !g_eff_news_med;
        GlobalVariableSet("RC_news_med", g_eff_news_med ? 1.0 : 0.0);
        RefreshNewsZones();
    } else if (id == g_shell.CfgIdSound()) {
        g_eff_sound = !g_eff_sound;
        GlobalVariableSet("RC_sound", g_eff_sound ? 1.0 : 0.0);
    } else if (id == g_shell.CfgIdTelegram()) {
        g_eff_telegram = !g_eff_telegram;
        GlobalVariableSet("RC_telegram", g_eff_telegram ? 1.0 : 0.0);
    } else if (id == g_shell.CfgIdComfort()) {
        g_eff_comfort = !g_eff_comfort;
        GlobalVariableSet("RC_comfort", g_eff_comfort ? 1.0 : 0.0);
        ApplyComfortScale(false);
    } else if (id == g_shell.CfgIdDiscipline()) {
        g_eff_discipline = !g_eff_discipline;
        GlobalVariableSet("RC_discipline", g_eff_discipline ? 1.0 : 0.0);
    } else if (id == g_shell.CfgIdRiskTools()) {
        if (PlanIsPersonal()) {            // prop plans are ALWAYS on : the toolkit is the product
            g_eff_risktools = !g_eff_risktools;
            GlobalVariableSet("RC_risktools", g_eff_risktools ? 1.0 : 0.0);
        }
    } else if (id == g_shell.CfgIdLang()) {
        g_lang = (g_lang + 1) % 3;
        GlobalVariableSet("RC_lang", (double)g_lang);
        ShellPushLabels();                 // the shell's chrome follows the language
    } else if (id == g_shell.CfgIdViolMargin()) {
        g_margin_violation_active = !g_margin_violation_active;
        GlobalVariableSet("RC_margin_violation", g_margin_violation_active ? 1.0 : 0.0);
    } else if (id == g_shell.CfgIdViolRisk()) {
        g_risk_violation_active = !g_risk_violation_active;
        GlobalVariableSet("RC_risk_violation", g_risk_violation_active ? 1.0 : 0.0);
    } else if (id == g_shell.CfgIdBe()) {
        g_be_visible = !g_be_visible;
        PersistBE();
        if (g_be_visible) DrawBreakevenLines();
        else              ObjectsDeleteAll(0, "RC_BE_");     // the lines live on the chart
    }
}
// v3.04 : add-on toggled from the shell. The mask is the SAME one the modal
// writes ; a re-resolve follows because add-ons change the rules themselves
// (95% split, no-min-days, 10% DD...).
void ShellApplyAddon(const int row) {
    if (row < 0) return;
    int    flags[7];
    flags[0] = FN_ADDON_LIFETIME_95; flags[1] = FN_ADDON_NO_MIN_DAYS; flags[2] = FN_ADDON_SWAP_FREE;
    flags[3] = FN_ADDON_10PCT_DD;    flags[4] = FN_ADDON_DOUBLE_UP;   flags[5] = FN_ADDON_BI_WEEKLY;
    flags[6] = FN_ADDON_150_REWARD;
    const int valid = g_catalog.ValidAddonsMask(EffectivePlan());
    int shown = 0;
    for (int i = 0; i < 7; ++i) {
        if ((valid & flags[i]) == 0) continue;
        if (shown == row) {
            if ((g_addons_mask & flags[i]) != 0) g_addons_mask &= ~flags[i];
            else                                 g_addons_mask |=  flags[i];
            GVSetLogin("RC_addons", (double)g_addons_mask);
            ApplySettingsChange();                 // add-ons change the RULES
            return;
        }
        shown++;
    }
}
// v3.04 : cycle start date (year / month / day), clamped to a real date.
void ShellApplyCycle(const int field, const int dir) {
    double ymd = g_eff_cycle_ymd;
    if (ymd <= 0.0) ymd = IsoToYmd(InpCycleStartIso);
    int y = (int)ymd / 10000, m = ((int)ymd / 100) % 100, dd = (int)ymd % 100;
    if (y < 2000) { y = 2026; m = 1; dd = 1; }
    if (field == 0) y = (int)MathMax(2020.0, MathMin(2099.0, (double)y + dir));
    else if (field == 1) m = ((m - 1 + dir) % 12 + 12) % 12 + 1;
    else                 dd = ((dd - 1 + dir) % 31 + 31) % 31 + 1;
    if (m == 2 && dd > 28) dd = 28;                          // never build an impossible date
    if ((m == 4 || m == 6 || m == 9 || m == 11) && dd > 30) dd = 30;
    g_eff_cycle_ymd = (double)(y * 10000 + m * 100 + dd);
    GVSetLogin("RC_cycle_ymd", g_eff_cycle_ymd);
}
// v3.04 : arm the self-lock (the shell already asked for confirmation twice).
void ShellArmSelfLock(void) {
    g_selflock_until = TimeCurrent() + (datetime)MathMax(1, g_eff_selflock_h) * 3600;
    GlobalVariableSet("RC_selflock_until", (double)g_selflock_until);
    g_unlock_arm = 0;
    Print("RiskCockpit : self-lock armed for ", g_eff_selflock_h, "h (until ",
          TimeToString(g_selflock_until, TIME_DATE | TIME_MINUTES), ").");
    ApplySettingsChange();
}
// v3 SHELL : the ONE native control of the shell - a copyable lot box. A canvas
// cannot be selected, so the number the trader pastes into the order ticket has
// to be an OBJ_EDIT. The shell reserves the rect (and a no-op click zone under
// it) ; the host owns the object, so its lifecycle stays with the other
// RC_-prefixed objects and it dies with the shell.
void ShellSyncLotEdit(const double lot, const int digits) {
    const string id = RC_PREFIX + "V3_copylot";
    int x, y, w, h;
    if (!g_shell.LotEditRect(x, y, w, h)) {
        ObjectDelete(0, id);
        return;
    }
    if (ObjectFind(0, id) < 0) {
        ObjectCreate(0, id, OBJ_EDIT, 0, 0, 0);
        ObjectSetInteger(0, id, OBJPROP_CORNER, CORNER_LEFT_UPPER);
        ObjectSetInteger(0, id, OBJPROP_SELECTABLE, false);
        ObjectSetInteger(0, id, OBJPROP_HIDDEN, true);
        ObjectSetInteger(0, id, OBJPROP_ALIGN, ALIGN_CENTER);
        ObjectSetInteger(0, id, OBJPROP_READONLY, false);   // selectable text = copyable
        ObjectSetInteger(0, id, OBJPROP_ZORDER, 300);
        ObjectSetString (0, id, OBJPROP_FONT, RC_FONT);
        ObjectSetInteger(0, id, OBJPROP_FONTSIZE, RC_FONT_SIZE);
        ObjectSetString (0, id, OBJPROP_TOOLTIP, Tr("copy_sug_tip"));
    }
    ObjectSetInteger(0, id, OBJPROP_XDISTANCE, x);
    ObjectSetInteger(0, id, OBJPROP_YDISTANCE, y);
    ObjectSetInteger(0, id, OBJPROP_XSIZE, w);
    ObjectSetInteger(0, id, OBJPROP_YSIZE, h);
    ObjectSetInteger(0, id, OBJPROP_COLOR, g_shell.EditTextColor());
    ObjectSetInteger(0, id, OBJPROP_BGCOLOR, g_shell.EditBackColor());
    ObjectSetInteger(0, id, OBJPROP_BORDER_COLOR, g_shell.EditLineColor());
    ObjectSetString (0, id, OBJPROP_TEXT, DoubleToString(lot, digits));
}
//+------------------------------------------------------------------+
//| v3.02 : the settings MODEL for the shell.                         |
//|                                                                   |
//| One table per sub-tab : label, current value, and the step. The    |
//| shell only draws rows and reports "row N, +1/-1" ; every write     |
//| lands on the SAME globals and the SAME GlobalVariables the legacy  |
//| modal uses, so both UIs configure one product, not two.            |
//+------------------------------------------------------------------+
int ShellStepRows(const int tab, string &lab[], string &val[]) {
    ArrayResize(lab, 10); ArrayResize(val, 10);
    int n = 0;
    if (tab == 0) {          // RISK
        lab[n] = Tr("set_sl");   val[n] = DoubleToString(g_eff_sl_pct, 2) + " %";        n++;
        lab[n] = Tr("set_tp");   val[n] = DoubleToString(g_eff_tp_pct, 2) + " %";        n++;
        lab[n] = Tr("set_maxmargin");val[n] = DoubleToString(g_eff_max_margin_pt, 1) + " %"; n++;
        lab[n] = Tr("set_maxrisk"); val[n] = DoubleToString(g_eff_max_risk_pt, 2) + " %";   n++;
        lab[n] = Tr("set_maxparallel");val[n] = IntegerToString(g_max_parallel);              n++;
        lab[n] = Tr("shl_split");   val[n] = (g_eff_split >= 0.0 ? DoubleToString(g_eff_split, 0) + " %" : "auto"); n++;
    } else if (tab == 1) {   // DISCIPLINE
        lab[n] = Tr("set_tiltn");   val[n] = IntegerToString(g_eff_tilt_n);                 n++;
        lab[n] = Tr("set_tiltwin"); val[n] = IntegerToString(g_eff_tilt_win) + " min";      n++;
        lab[n] = Tr("set_cooldownn");   val[n] = IntegerToString(g_eff_cooldown_n);             n++;
        lab[n] = Tr("set_cooldownm");   val[n] = IntegerToString(g_eff_cooldown_m) + " min";    n++;
        lab[n] = Tr("set_selflockh");val[n] = IntegerToString(g_eff_selflock_h) + " h";      n++;
    } else if (tab == 2) {   // ADVANCED
        lab[n] = Tr("set_comfortpct"); val[n] = DoubleToString(g_eff_comfort_pct, 0) + " %"; n++;
        lab[n] = Tr("set_refreshms");  val[n] = IntegerToString(g_eff_refresh_ms) + " ms";   n++;
        lab[n] = Tr("set_mcapviol");   val[n] = DoubleToString(g_eff_margin_cap_viol, 0) + " %"; n++;
        lab[n] = Tr("set_rcapviol");   val[n] = DoubleToString(g_eff_risk_cap_viol, 2) + " %";   n++;
    }
    return n;                // tab 3 (display) is toggles only
}
// apply one stepper click. Same clamps as the modal ; persistence identical.
void ShellApplyStep(const int tab, const int row, const int dir) {
    const double d = (double)dir;
    if (tab == 0) {
        if (row == 0) { g_eff_sl_pct = MathMax(0.1, MathMin(10.0, MathRound((g_eff_sl_pct + d * 0.1) * 100.0) / 100.0));
                        GlobalVariableSet("RC_sl_pct", g_eff_sl_pct); }
        else if (row == 1) { g_eff_tp_pct = MathMax(0.1, MathMin(50.0, MathRound((g_eff_tp_pct + d * 0.1) * 100.0) / 100.0));
                        GlobalVariableSet("RC_tp_pct", g_eff_tp_pct); }
        else if (row == 2) { g_eff_max_margin_pt = MathMax(1.0, MathMin(100.0, g_eff_max_margin_pt + d));
                        GlobalVariableSet("RC_mm_pt", g_eff_max_margin_pt); }
        else if (row == 3) { g_eff_max_risk_pt = MathMax(0.1, MathMin(10.0, MathRound((g_eff_max_risk_pt + d * 0.1) * 100.0) / 100.0));
                        GlobalVariableSet("RC_mr_pt", g_eff_max_risk_pt); }
        else if (row == 4) { g_max_parallel = (int)MathMax(1.0, MathMin(50.0, (double)g_max_parallel + d));
                        PersistMaxParallel(); }
        else if (row == 5) { g_eff_split = (g_eff_split < 0.0 ? 80.0 : g_eff_split + d * 5.0);
                        if (g_eff_split > 100.0) g_eff_split = 100.0;
                        if (g_eff_split < 0.0)   g_eff_split = -1.0;      // back to the catalog value
                        GVSetLogin("RC_split", g_eff_split); }
    } else if (tab == 1) {
        if (row == 0) { g_eff_tilt_n = (int)MathMax(0.0, MathMin(50.0, (double)g_eff_tilt_n + d));
                        GlobalVariableSet("RC_tilt_n", (double)g_eff_tilt_n); }
        else if (row == 1) { g_eff_tilt_win = (int)MathMax(5.0, MathMin(480.0, (double)g_eff_tilt_win + d * 5.0));
                        GlobalVariableSet("RC_tilt_win", (double)g_eff_tilt_win); }
        else if (row == 2) { g_eff_cooldown_n = (int)MathMax(0.0, MathMin(20.0, (double)g_eff_cooldown_n + d));
                        GlobalVariableSet("RC_cool_n", (double)g_eff_cooldown_n); }
        else if (row == 3) { g_eff_cooldown_m = (int)MathMax(0.0, MathMin(480.0, (double)g_eff_cooldown_m + d * 5.0));
                        GlobalVariableSet("RC_cool_m", (double)g_eff_cooldown_m); }
        else if (row == 4) { g_eff_selflock_h = (int)MathMax(1.0, MathMin(72.0, (double)g_eff_selflock_h + d));
                        GlobalVariableSet("RC_selflock_h", (double)g_eff_selflock_h); }
    } else if (tab == 2) {
        if (row == 0) { g_eff_comfort_pct = MathMax(0.0, MathMin(90.0, g_eff_comfort_pct + d * 5.0));
                        GlobalVariableSet("RC_comfort_pct", g_eff_comfort_pct); ApplyComfortScale(true); }
        else if (row == 1) { g_eff_refresh_ms = (int)MathMax(100.0, MathMin(2000.0, (double)g_eff_refresh_ms + d * 100.0));
                        GlobalVariableSet("RC_refresh_ms", (double)g_eff_refresh_ms);
                        EventKillTimer(); EventSetMillisecondTimer(g_eff_refresh_ms); }
        else if (row == 2) { g_eff_margin_cap_viol = MathMax(1.0, MathMin(100.0, g_eff_margin_cap_viol + d));
                        GlobalVariableSet("RC_mcap_viol", g_eff_margin_cap_viol); }
        else if (row == 3) { g_eff_risk_cap_viol = MathMax(0.1, MathMin(10.0, MathRound((g_eff_risk_cap_viol + d * 0.1) * 100.0) / 100.0));
                        GlobalVariableSet("RC_rcap_viol", g_eff_risk_cap_viol); }
    }
}
// the plan cascade, editable from the shell : broker -> type -> phase -> size
// -> account type. Same snapping rules as the modal (a plan can never end up
// with an illegal size or phase), then a full re-resolve of the profile.
int ShellCascadeRows(string &lab[], string &val[]) {
    ArrayResize(lab, 5); ArrayResize(val, 5);
    lab[0] = Tr("set_broker_sel"); val[0] = VendorName(VendorOfPlan(EffectivePlan()));
    lab[1] = Tr("set_type");       val[1] = g_catalog.ModelLabel(EffectivePlan());
    lab[2] = Tr("set_phase");      val[2] = PhaseLabelLocal(g_eff_phase);
    lab[3] = Tr("set_size");       val[3] = SizeLabel();
    lab[4] = Tr("set_acct_type");  val[4] = (EffectivePlan() == FN_PLAN_PERSONAL
                                             ? (g_eff_personal_demo == 1 ? "DEMO" : "REAL")
                                             : (g_eff_acct_type == 1 ? "SWAP-FREE" : "SWAP"));
    return 5;
}
void ShellApplyCascade(const int row, const int dir) {
    if (row == 0) {                                   // BROKER : snap to its first plan
        ENUM_FN_PLAN vp[];
        int v = VendorOfPlan(EffectivePlan());
        v = ((v + dir) % 6 + 6) % 6;
        if (PlansForVendor(v, vp) > 0) {
            g_active_plan_idx = (int)vp[0];
            GVSetLogin("RC_plan_override", (double)g_active_plan_idx);
            SnapSizeToPlan((ENUM_FN_PLAN)g_active_plan_idx);
            SnapPhaseToPlan((ENUM_FN_PLAN)g_active_plan_idx);
        }
    } else if (row == 1) {                            // TYPE : within the current broker
        ENUM_FN_PLAN plans[];
        const int np = PlansForVendor(VendorOfPlan(EffectivePlan()), plans);
        int pidx = 0;
        for (int i = 0; i < np; ++i) if ((int)plans[i] == (int)EffectivePlan()) { pidx = i; break; }
        if (np > 0) {
            pidx = ((pidx + dir) % np + np) % np;
            g_active_plan_idx = (int)plans[pidx];
            GVSetLogin("RC_plan_override", (double)g_active_plan_idx);
            SnapSizeToPlan((ENUM_FN_PLAN)g_active_plan_idx);
            SnapPhaseToPlan((ENUM_FN_PLAN)g_active_plan_idx);
        }
    } else if (row == 2) {                            // PHASE
        g_eff_phase = ((g_eff_phase + dir) % 4 + 4) % 4;
        SnapPhaseToPlan(EffectivePlan());
        GVSetLogin("RC_phase", (double)g_eff_phase);
    } else if (row == 3) {                            // SIZE : only what the plan allows
        double sizes[];
        const int ns = ValidSizesForPlan(EffectivePlan(), sizes);
        int sidx = 0;
        for (int i = 0; i < ns; ++i)
            if ((int)MathRound(g_eff_size) == (int)MathRound(sizes[i])) { sidx = i; break; }
        if (ns > 0) {
            sidx = ((sidx + dir) % ns + ns) % ns;
            g_eff_size = sizes[sidx];
            GVSetLogin("RC_size", g_eff_size);
        }
    } else if (row == 4) {                            // ACCOUNT TYPE (or Real/Demo on Personal)
        if (EffectivePlan() == FN_PLAN_PERSONAL) {
            g_eff_personal_demo = (g_eff_personal_demo == 0 ? 1 : 0);
            GVSetLogin("RC_perso_demo", (double)g_eff_personal_demo);
        } else {
            g_eff_acct_type = (g_eff_acct_type == 0 ? 1 : 0);
            GVSetLogin("RC_acct_type", (double)g_eff_acct_type);
        }
    }
    ApplySettingsChange();      // re-resolve the profile : every limit follows
}
// v3.04 : the MAX lot gets its own copy box, right under the suggested one.
void ShellSyncMaxEdit(const double lot, const int digits) {
    const string id = RC_PREFIX + "V3_copymax";
    int x, y, w, h;
    if (!g_shell.MaxEditRect(x, y, w, h)) {
        ObjectDelete(0, id);
        return;
    }
    if (ObjectFind(0, id) < 0) {
        ObjectCreate(0, id, OBJ_EDIT, 0, 0, 0);
        ObjectSetInteger(0, id, OBJPROP_CORNER, CORNER_LEFT_UPPER);
        ObjectSetInteger(0, id, OBJPROP_SELECTABLE, false);
        ObjectSetInteger(0, id, OBJPROP_HIDDEN, true);
        ObjectSetInteger(0, id, OBJPROP_ALIGN, ALIGN_CENTER);
        ObjectSetInteger(0, id, OBJPROP_READONLY, false);
        ObjectSetInteger(0, id, OBJPROP_ZORDER, 300);
        ObjectSetString (0, id, OBJPROP_FONT, RC_FONT);
        ObjectSetInteger(0, id, OBJPROP_FONTSIZE, RC_FONT_SIZE);
        ObjectSetString (0, id, OBJPROP_TOOLTIP, Tr("copy_max_tip"));
    }
    ObjectSetInteger(0, id, OBJPROP_XDISTANCE, x);
    ObjectSetInteger(0, id, OBJPROP_YDISTANCE, y);
    ObjectSetInteger(0, id, OBJPROP_XSIZE, w);
    ObjectSetInteger(0, id, OBJPROP_YSIZE, h);
    ObjectSetInteger(0, id, OBJPROP_COLOR, g_shell.EditTextColor());
    ObjectSetInteger(0, id, OBJPROP_BGCOLOR, g_shell.EditBackColor());
    ObjectSetInteger(0, id, OBJPROP_BORDER_COLOR, g_shell.EditLineColor());
    ObjectSetString (0, id, OBJPROP_TEXT, DoubleToString(lot, digits));
}
// v3.06 PARITY : status-change alerts (sound + Telegram) used to ride inside
// UpdateRow, in the legacy refresh the shell short-circuits - so they had gone
// SILENT since the switch to v3, with nothing on screen to say so. They now run
// on the shell's own model, through the SAME registry (g_rows), the same
// thresholds and the same per-rule Telegram cooldown.
void ShellRuleAlerts(const RCDeckData &d) {
    if (!g_eff_risktools) return;
    for (int i = 0; i < RC_RULE_COUNT; ++i) {
        double used = -1.0, cap = 0.0;
        string txt = "";
        const string k = g_rows[i].key;
        if (k == "rule_margin_cum")      { used = d.marginPct; cap = d.marginCap; }
        else if (k == "rule_margin_pt")  { used = Live_PerTradeMarginPct();
                                           cap  = g_profile.margin_recommended_per_trade_max_pct; }
        else if (k == "rule_risk_cum")   { used = d.riskPct;   cap = d.riskCap; }
        else if (k == "rule_daily_dd")   { if (!d.dailyApplies) { g_last_status[i] = RC_STATUS_NA; continue; }
                                           used = d.dailyPct;  cap = d.dailyCap; }
        else if (k == "rule_overall_dd") { if (!d.overallApplies) { g_last_status[i] = RC_STATUS_NA; continue; }
                                           used = d.overallPct; cap = d.overallCap; }
        else if (k == "rule_qs")         { used = d.qsPct;     cap = d.qsCap; }
        else if (k == "rule_hyper")      { used = (double)d.tradesToday; cap = (double)d.tradesCap; }
        else if (k == "rule_msgs")       { used = (double)d.msgsToday;   cap = (double)d.msgsCap; }
        else continue;                   // target / news rows : informational, never alert
        if (used < 0.0 || cap <= 0.0) { g_last_status[i] = RC_STATUS_NA; continue; }
        txt = FormatPct(used) + " / " + FormatPct(cap);
        g_rows[i].value_pct  = used;     // the registry stays the ONE source the
        g_rows[i].max_pct    = cap;      // Telegram message is built from
        g_rows[i].value_text = txt;
        g_rows[i].status     = ComputeRangeStatus(used, cap, 0.80, 1.00);
        TryFireSoundAlert(i, g_rows[i].status);
    }
}

void ShellRefresh(void) {
    ShellApplyCfg(g_shell.PendCfgTake());  // consume a toggle click before rendering
    {   // steppers + cascade : the shell asked, the host writes
        int row = 0, dir = 0;
        if (g_shell.PendStepTake(row, dir)) ShellApplyStep(g_shell.CfgTab(), row, dir);
        if (g_shell.PendCasTake(row, dir))  ShellApplyCascade(row, dir);
        if (g_shell.PendCycTake(row, dir))  ShellApplyCycle(row, dir);
        ShellApplyAddon(g_shell.PendAddonTake());
        if (g_shell.PendSelfLockTake())     ShellArmSelfLock();
    }
    RCDeckData d;
    BuildDeckData(d);
    g_shell.SetData(d);
    RefreshSlLines();                    // chart-side advisory lines stay live under the shell
    if (g_be_visible) DrawBreakevenLines();   // v3.06 : BE lines follow the basket again
    ShellRuleAlerts(d);                  // v3.06 : sound + Telegram were silent under v3
    if (g_shell.Created()) g_shell.Tick();
    ShellSyncLotEdit(d.sugLot, d.lotDigits);   // AFTER the render : the rect is known
    ShellSyncMaxEdit(d.maxLot, d.maxLotDigits);
}

//+------------------------------------------------------------------+
//| RefreshPanel - the ONE refresh path. The legacy canvas panel was  |
//| removed in v3.06 (JR : "supprime l'ancien shell") ; everything it |
//| computed lives in BuildDeckData + the v3 shell, and every side    |
//| effect it carried (alerts, SL lines, BE lines) moved to           |
//| ShellRefresh, which is what this now delegates to.                |
//+------------------------------------------------------------------+
void RefreshPanel(void) {
    ShellRefresh();
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

//+------------------------------------------------------------------+
//| B5 : next HIGH-impact news + B4 : weekend-hold warning state      |
//+------------------------------------------------------------------+
bool     g_weekend_warned = false; // weekend alert already fired this window

// B5 : time of the next HIGH-impact event (any currency) within 24h, 0 if none.
// V1.29 P/R : next HIGH **or** MEDIUM news (respecting the level toggles), and
// reports whether it is HIGH via out_high. (Name kept for minimal churn.)

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
        const double swap = PositionGetDouble(POSITION_SWAP); // Phase 3.5 : net-of-holding-cost boundary
        total_risk_money += ComputePositionRiskMoney(sym, type, po, sl, vol, swap);
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
    UpdatePeakEquity(); // maintains the realized-balance high-water mark (persisted)
    const double cur_eq = AccountInfoDouble(ACCOUNT_EQUITY);
    if (g_profile.max_loss_trailing) {
        // v2.02.05 FIX 1 : FN "Max Loss Limit" EXACTLY as the official FN API defines
        // it : permitted_loss = max_loss_pct% of the INITIAL balance (a FIXED $, 120
        // on 2K - NOT 6% of a growing peak) ; floor = (realized balance high) -
        // permitted, CAPPED at the initial balance (breakeven lock) ; breach when
        // EQUITY crosses the floor ; losses never lower the floor. Live oracle
        // (login 11986032, Instant 2K) : peak 2003.28 -> floor 1883.28, permitted 120.
        const double init = g_profile.initial_balance;
        if (init <= 0.0)
            return 0.0;
        const double permitted = (g_profile.max_loss_pct / 100.0) * init;
        const double floorv    = MathMin(g_peak_balance - permitted, init);
        static bool s_floor_logged = false; // acceptance : must match the FN dashboard
        if (!s_floor_logged) {
            PrintFormat("RiskCockpit Instant floor: floor=%.2f permitted=%.2f peak_bal=%.2f",
                        floorv, permitted, g_peak_balance);
            s_floor_logged = true;
        }
        const double dd_pct = 100.0 * (permitted + floorv - cur_eq) / init; // = max_loss_pct exactly AT the floor
        return MathMax(0.0, dd_pct);
    }
    if (g_profile.initial_balance <= 0.0)
        return 0.0;
    const double dd = g_profile.initial_balance - cur_eq;
    if (dd <= 0.0)
        return 0.0;
    return 100.0 * dd / g_profile.initial_balance;
}

// v2.13 FEATURE B : smallest $ ROOM between the current EQUITY and the nearest
// ACTIVE loss limit. Uses the same dd math the meters run on : room_i =
// (limit_pct_i - dd_pct_i)% of initial - on the trailing (Instant) profile the
// overall-dd formula makes this EXACTLY equity - floor. Applicable limits :
// daily (daily_loss_pct > 0) and overall (max_loss_pct > 0) ; smallest positive
// wins (a breached limit clamps to 0). Returns -1 when NO limit applies
// (Personal without caps) so callers can skip the guard entirely.
double Live_NearestLimitRoom(void) {
    const double init = g_profile.initial_balance;
    if (init <= 0.0)
        return -1.0;
    double room = -1.0;
    if (g_profile.max_loss_pct > 0.0) {
        const double r = MathMax(0.0, (g_profile.max_loss_pct - Live_OverallDdPct()) / 100.0 * init);
        room = r;
    }
    if (g_profile.daily_loss_pct > 0.0) {
        const double r = MathMax(0.0, (g_profile.daily_loss_pct - Live_DailyDdPct()) / 100.0 * init);
        if (room < 0.0 || r < room) room = r;
    }
    return room;
}

// v2.13 FEATURE B2 : TRUE aggregate worst-case loss from the CURRENT equity if
// every open position gets stopped at its CURRENT SL, vs 80% of the nearest-
// limit room (20% must survive the hit). equity_at_SLs = balance - sum(from-open
// risk at current SLs) -> loss-from-now = sum(risk) - floating P&L. A position
// with NO SL = the guard fires unconditionally (unbounded risk). Fills the
// recommended MINIMUM SL for the biggest-risk position (the SL that brings the
// aggregate back to exactly 80% of the room). READ-ONLY advisor : displays the
// fix, never touches a trade.
bool Live_SlGuardBreached(string &reco_sym, double &reco_sl) {
    reco_sym = "";
    reco_sl  = 0.0;
    if (PositionsTotal() == 0)
        return false;
    const double room = Live_NearestLimitRoom();
    if (room < 0.0)
        return false; // no active limit -> nothing to guard
    const double equity  = AccountInfoDouble(ACCOUNT_EQUITY);
    const double balance = AccountInfoDouble(ACCOUNT_BALANCE);
    double total_open = 0.0, worst_risk = 0.0;
    ulong  worst_ticket = 0;
    bool   missing_sl = false;
    string nosl_sym = "";
    const int n = PositionsTotal();
    for (int i = 0; i < n; ++i) {
        const ulong ticket = PositionGetTicket(i);
        if (ticket == 0 || !PositionSelectByTicket(ticket))
            continue;
        const double sl = PositionGetDouble(POSITION_SL);
        if (sl <= 0.0) { // SL-less = unbounded worst case
            missing_sl = true;
            if (nosl_sym == "") nosl_sym = PositionGetString(POSITION_SYMBOL);
            continue;
        }
        const string sym  = PositionGetString(POSITION_SYMBOL);
        const double po   = PositionGetDouble(POSITION_PRICE_OPEN);
        const double vol  = PositionGetDouble(POSITION_VOLUME);
        const int    type = (int)PositionGetInteger(POSITION_TYPE);
        const double swap = PositionGetDouble(POSITION_SWAP);
        const double r = ComputePositionRiskMoney(sym, type, po, sl, vol, swap);
        total_open += r;
        if (r > worst_risk) { worst_risk = r; worst_ticket = ticket; }
    }
    // loss from the CURRENT equity if every SL gets swept :
    //   equity_at_SLs = balance - total_open  ->  loss = equity - equity_at_SLs
    //                                             = total_open + (equity - balance).
    // SIGN MATTERS (verified against the oracle) : floating PROFIT makes the
    // sweep loss BIGGER than the from-open risk (you lose the profit AND the
    // from-open distance) ; floating LOSS makes it smaller (part already paid).
    const double worst_case = (missing_sl ? room + 1.0 // always breached : no SL somewhere
                                          : total_open + (equity - balance));
    if (worst_case <= 0.80 * room)
        return false;
    if (missing_sl) {
        reco_sym = nosl_sym; // no numeric reco : the SL-less position IS the problem
        reco_sl  = 0.0;      // (tightening another SL can never clear the guard)
        return true;
    }
    if (worst_ticket != 0 && PositionSelectByTicket(worst_ticket)) {
        const string sym  = PositionGetString(POSITION_SYMBOL);
        const double po   = PositionGetDouble(POSITION_PRICE_OPEN);
        const double vol  = PositionGetDouble(POSITION_VOLUME);
        const int    type = (int)PositionGetInteger(POSITION_TYPE);
        const double swap = PositionGetDouble(POSITION_SWAP);
        const double ts   = SymbolInfoDouble(sym, SYMBOL_TRADE_TICK_SIZE);
        const double tv   = SymbolInfoDouble(sym, SYMBOL_TRADE_TICK_VALUE);
        if (ts > 0.0 && tv > 0.0 && vol > 0.0) {
            const double others  = total_open - worst_risk;
            // from-open budget left for the worst position so the aggregate sweep
            // loss lands EXACTLY on 0.80*room :
            //   others + allowed + (equity - balance) = 0.80*room
            double allowed = 0.80 * room - (equity - balance) - others;
            if (allowed < 0.0) allowed = 0.0;
            // the risk figure includes the booked swap (ComputePositionRiskMoney
            // adds costs) -> solve the PRICE term for allowed : dist_term = allowed + swap.
            double allowed_price = allowed + swap;
            if (allowed_price < 0.0) allowed_price = 0.0;
            const double dist = allowed_price * ts / (tv * vol);
            reco_sl  = (type == POSITION_TYPE_BUY ? po - dist : po + dist);
            reco_sym = sym;
            reco_sl  = NormalizeDouble(reco_sl, (int)SymbolInfoInteger(sym, SYMBOL_DIGITS));
        }
    }
    return true;
}

// v3.01 : the largest openable lot, extracted from the legacy row so the panel
// and the shell share ONE implementation (two copies of a risk number is how
// they start disagreeing). Returns the lot ; -1 when it cannot be computed.
// Out : the binding cap's percentage + its tag, lot digits, free-margin %, and
// the cumulative used / cap pair the caller displays.
double Live_MaxLot(double &pct_disp, string &tag, int &ld,
                   double &avail_pct, double &cum_used, double &cum_cap) {
    pct_disp = 0.0; tag = ""; ld = 2; avail_pct = 0.0; cum_used = 0.0; cum_cap = 0.0;
    const double m1       = MarginPerLot(_Symbol);
    const double init_bal = g_profile.initial_balance;
    const double tgt_pct  = g_eff_max_margin_pt;
    const double free_m   = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
    if (m1 <= 0.0 || init_bal <= 0.0)
        return -1.0;
    // The largest openable lot is the MIN of THREE caps :
    //   (a) per-trade margin target, (b) remaining cumulative room, (c) real free margin.
    const double tgt_money  = (tgt_pct / 100.0) * init_bal;
    cum_used   = Live_CumulativeMarginPct();
    cum_cap    = EffectiveMarginCap();
    const double room_pct   = MathMax(0.0, cum_cap - cum_used);
    const double room_money = room_pct / 100.0 * init_bal;
    avail_pct  = 100.0 * free_m / init_bal;
    const double money_cap  = MathMin(tgt_money, MathMin(room_money, free_m));
    const double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
    const double vmin = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
    const double vmax = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
    double lot = money_cap / m1;
    if (step > 0.0) lot = MathFloor(lot / step) * step;
    if (lot < vmin) lot = 0.0;
    else if (vmax > 0.0 && lot > vmax) lot = vmax;
    ld = LotDigits(step);
    g_maxlot_copy = (lot > 0.0 ? lot : 0.0); g_maxlot_digits = ld;   // V1.24 G3 copy
    // which cap binds ? (tie -> target, then cumulative room, then free margin)
    if (tgt_money <= room_money + 1e-6 && tgt_money <= free_m + 1e-6) { tag = "marg"; pct_disp = tgt_pct; }
    else if (room_money <= free_m + 1e-6)                            { tag = "room"; pct_disp = room_pct; }
    else                                                             { tag = "free"; pct_disp = avail_pct; }
    return lot;
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
    if (g_ff_active)              // v2.03 : FF feed = primary source (FN-aligned) ;
        return FFInNewsWindow();  // the MT5 calendar below stays the fallback

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
        // v2.02.05 FIX 2a : the FN rule is HIGH-impact ONLY (support-verified, June
        // 2026). MEDIUM never triggers the 40% rule - it only gets the separate
        // "check FN" vigilance display (Live_NextMedNewsEvt).
        if (ev.importance != CALENDAR_IMPORTANCE_HIGH) continue;
        if (!g_eff_news_high) continue;

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
    if (g_ff_active)            // v2.03 : FF feed = primary source. restricted = FF High
        return FFNextEvt(true); // OR FN override -> the RULE ; MT5 calendar = fallback.
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
        // v2.02.05 FIX 2a : the RULE tracks HIGH-impact ONLY (FN : 40% of winning-
        // trade profit in the ±window ; MEDIUM has NO rule -> vigilance helper below).
        if (ev.importance != CALENDAR_IMPORTANCE_HIGH) continue;
        if (!g_eff_news_high) continue;
        const datetime te = values[i].time;
        if (now >= te - 3600 && now <= te + win_sec) {
            if (best == 0 || te < best) best = te;
        }
    }
    return best;
}

// v2.02.05 FIX 2b : nearest MEDIUM event, VIGILANCE display ONLY - never the rule.
// Kept because the FN calendar treats some events as HIGH that MQL5 classes
// MODERATE (central-bank speeches : Ueda, Lagarde...) -> the row shows an amber
// "check FN" hint instead of silently ignoring them. Same scan as Live_NextNewsEvt.
datetime Live_NextMedNewsEvt(void) {
    if (!g_profile.news_rule_applies || !g_eff_news_med)
        return 0;
    if (g_ff_active)             // v2.03 : FF non-restricted (Medium hors override) =
        return FFNextEvt(false); // the amber vigilance class ; MT5 = fallback.
    const int win_sec = (g_profile.news_window_minutes > 0 ? g_profile.news_window_minutes : 5) * 60;
    const datetime now = TimeCurrent();
    MqlCalendarValue values[];
    if (!CalendarValueHistory(values, now - win_sec, now + 3600 + win_sec, NULL, NULL))
        return 0;
    datetime best = 0;
    for (int i = 0; i < ArraySize(values); ++i) {
        MqlCalendarEvent ev;
        if (!CalendarEventById(values[i].event_id, ev))
            continue;
        if (ev.importance != CALENDAR_IMPORTANCE_MODERATE) continue;
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
            const bool lvl_ok = (evtimp[k] == (int)CALENDAR_IMPORTANCE_HIGH); // v2.02.05 FIX 2c : the 40% rule counts HIGH only
            const bool mapped = NewsCcyAffectsSymbol(dsym, evtccy[k]); // official FN instrument<->currency table
            const string impl = (evtimp[k] == (int)CALENDAR_IMPORTANCE_HIGH ? "HIGH" :
                                 (evtimp[k] == (int)CALENDAR_IMPORTANCE_MODERATE ? "MED" : "LOW"));
            ArrayResize(diag, ndiag + 1);
            diag[ndiag++] = dsym + " deal " + TimeToString(dt, TIME_DATE | TIME_SECONDS) +
                            " ~ evt " + TimeToString(evt[k], TIME_DATE | TIME_MINUTES) + " " + evtccy[k] +
                            " " + impl + " '" + evtname[k] + "' (FN-table " + (mapped ? "y" : "n") + ") -> " +
                            (lvl_ok && mapped ? "COUNTED" : (!mapped ? "skipped (not FN-mapped)" : "skipped (not HIGH)"));
            if (lvl_ok && mapped && !innews) { // count rule : HIGH event mapped per the FN-confirmed table (v2.02.05 FIX 2c)
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
    if (InpVerboseLog && sig != s_news_sig) { // BATCH 1 : dev diagnostics gated OFF for the shipped build
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
            // Phase 3.5 : a SL trailed onto the FAVORABLE side (LONG sl>=entry / SHORT
            // sl<=entry) locks profit -> the position has NO downside risk -> never flag it
            // "over budget" / SL>REC, and draw no recommendation line for it.
            const bool sl_locks_profit = has_user_sl &&
                (type == POSITION_TYPE_BUY ? (existing_sl >= entry) : (existing_sl <= entry));
            const bool user_over_budget = (has_user_sl && !sl_locks_profit && user_dist > proposed_dist);
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

            // Panel-side chip override (HOST chart only). LOT A : label-only chip - red
            // semantic text + the canvas pill follows via g_pos_status (bounds-guarded :
            // this loop walks ALL positions, the panel only has RC_MAX_POSITIONS rows).
            if (user_over_budget) {
                const string row_id = RC_PREFIX + "pos_" + IntegerToString(i);
                if (i >= 0 && i < RC_MAX_POSITIONS) g_pos_status[i] = RC_STATUS_RED;
                ObjectSetString(0, row_id + "_chip_txt", OBJPROP_TEXT, Tr("sl_over_chip"));
                ObjectSetInteger(0, row_id + "_chip_txt", OBJPROP_COLOR, g_theme.red);
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
                                const double vol, const double costs) {
    if (sl <= 0.0 || vol <= 0.0)
        return 0.0;
    const double tick_size = SymbolInfoDouble(sym, SYMBOL_TRADE_TICK_SIZE);
    const double tick_value = SymbolInfoDouble(sym, SYMBOL_TRADE_TICK_VALUE);
    if (tick_size <= 0.0 || tick_value <= 0.0)
        return 0.0;
    // Phase 3.5 : direction-aware + net of booked costs. A SL trailed onto the FAVORABLE
    // side (LONG sl>=entry / SHORT sl<=entry) LOCKS profit -> P&L at SL >= 0 -> the
    // position carries NO downside risk -> 0. (The old MathAbs distance wrongly counted a
    // profit-locking SL as risk.) `costs` (swap+commission, usually negative) tightens the
    // breakeven boundary so it is truly net of holding cost.
    const double dir = (type == POSITION_TYPE_BUY) ? 1.0 : -1.0;
    const double pnl_at_sl = dir * (sl - price_open) / tick_size * tick_value * vol + costs;
    return (pnl_at_sl >= 0.0) ? 0.0 : -pnl_at_sl; // profit-locked -> 0 ; else the net loss
}

// A1 : UpdateDayStartEquity + g_equity_at_day_start removed (dead code - the
// daily-DD figure is reconstructed live via SumClosedDealsPnL, never from these).

// v2.02.05 FIX 1 : the FN Instant trailing floor follows the realized BALANCE
// high (floating equity spikes do NOT raise the FN floor). Persist on increase
// only (no GV write per tick). Name kept : caller chain unchanged.
string PeakBalGV(void)  { return "RC_ins_pb_" + IntegerToString(AccountInfoInteger(ACCOUNT_LOGIN)); }
string PeakSeedGV(void) { return "RC_ins_sd_" + IntegerToString(AccountInfoInteger(ACCOUNT_LOGIN)); }
void UpdatePeakEquity(void) {
    const double bal = AccountInfoDouble(ACCOUNT_BALANCE);
    if (bal > g_peak_balance) {
        g_peak_balance = bal;
        GlobalVariableSet(PeakBalGV(), g_peak_balance);
    }
}
// v2.02.05 : load the per-login peak, or seed it at max(initial, balance). The seed
// value is ALSO persisted so a bad first seed can SELF-HEAL : if the stored peak
// never grew past its own seed (poison case : first attach with the default 25K
// size on the 2K account seeded peak=25000) and the profile now yields a SMALLER
// seed, re-seed. A peak that genuinely grew (real balance highs) is never touched.
// Called from OnInit + after every profile re-Resolve (size/plan popup changes).
// v2.13 FEATURE C : ACCOUNT-PROFILE settings are keyed PER LOGIN (same pattern
// as the trailing-floor peak) so each account keeps ITS OWN plan/size/type/
// phase/addons/split/cycle - switching accounts auto-restores the right config
// instead of dragging the last-used one along. The legacy GLOBAL name stays as
// a READ fallback (soft migration : the first load on a login adopts the old
// global value, then saves under the login ; nothing currently configured is
// lost). Preference/display settings (theme, palette, lang, news, alerts,
// SL/TP/margin tunables...) stay global on purpose - they are user habits,
// not account facts.
string LoginKey(const string base) { return base + "_" + IntegerToString(AccountInfoInteger(ACCOUNT_LOGIN)); }
bool GVGetLogin(const string base, double &v) {
    if (GlobalVariableCheck(LoginKey(base))) { v = GlobalVariableGet(LoginKey(base)); return true; }
    if (GlobalVariableCheck(base))           { v = GlobalVariableGet(base);           return true; } // legacy fallback
    return false;
}
void GVSetLogin(const string base, const double v) {
    GlobalVariableSet(LoginKey(base), v); // per-login only : the global stays frozen as the migration seed
}
void LoadOrSeedPeakBalance(void) {
    const string k_pb = PeakBalGV(), k_sd = PeakSeedGV();
    const double seed = MathMax(g_profile.initial_balance, AccountInfoDouble(ACCOUNT_BALANCE));
    if (GlobalVariableCheck(k_pb)) {
        g_peak_balance = GlobalVariableGet(k_pb);
        if (GlobalVariableCheck(k_sd)) {
            const double sd = GlobalVariableGet(k_sd);
            if (g_peak_balance <= sd + 0.005 && seed < sd - 0.005) { // never grew + smaller profile -> heal
                g_peak_balance = seed;
                GlobalVariableSet(k_pb, g_peak_balance);
                GlobalVariableSet(k_sd, seed);
            }
        }
    } else {
        g_peak_balance = seed;
        GlobalVariableSet(k_pb, g_peak_balance);
        GlobalVariableSet(k_sd, seed);
    }
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
        return IntegerToString(m) + "m " + IntegerToString(s) + "s"; // E6 : "2m 14s" (mockup spacing)
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
        return (sl_missing ? Tr("pos_slq") : Tr("chip_warn")); // E6 : SL missing in grace -> amber "SL?"
    return Tr("chip_ok"); // E6 : positions keep OK (mockup)
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
//| v2.03 F1 : ForexFactory public calendar (FairEconomy JSON feed).  |
//| Requires https://nfs.faireconomy.media whitelisted in Tools >     |
//| Options > Expert Advisors > WebRequest (else err 4014).           |
//| Fetch : first timer tick + 1 / 60 min, 3 s timeout (WebRequest    |
//| blocks the UI thread -> short + rare + cached). On ANY failure    |
//| the cache/state is kept and the MT5 calendar remains the honest   |
//| fallback (F3) - never a silent empty screen.                      |
//+------------------------------------------------------------------+
// FN override list - maintained by Coordinator via MCP diff (events FN elevates
// to restricted while ForexFactory classes them lower). Seed verified July 2026.
// TODO : extend via Coordinator when the FN MCP is_restricted diff flags new ones.
bool FFRestrictedOverride(const string ccy, const string title) {
    if (ccy == "USD" && StringFind(title, "PPI m/m") >= 0)      return true; // also matches "Core PPI m/m"
    if (ccy == "USD" && StringFind(title, "Core PPI m/m") >= 0) return true; // explicit seed entry
    return false;
}
// "2026-07-14T08:30:00-04:00" -> epoch UTC (offset parsed out ; trailing 'Z' = UTC).
datetime FFParseIso8601Utc(const string s) {
    if (StringLen(s) < 19) return 0;
    MqlDateTime dt;
    dt.year = (int)StringToInteger(StringSubstr(s, 0, 4));
    dt.mon  = (int)StringToInteger(StringSubstr(s, 5, 2));
    dt.day  = (int)StringToInteger(StringSubstr(s, 8, 2));
    dt.hour = (int)StringToInteger(StringSubstr(s, 11, 2));
    dt.min  = (int)StringToInteger(StringSubstr(s, 14, 2));
    dt.sec  = (int)StringToInteger(StringSubstr(s, 17, 2));
    if (dt.year < 2000 || dt.mon < 1 || dt.mon > 12 || dt.day < 1 || dt.day > 31) return 0;
    datetime t = StructToTime(dt); // naive stamp -> epoch as-if-UTC
    if (StringLen(s) >= 25) {      // +HH:MM / -HH:MM -> local = UTC + off => UTC = local - off
        const ushort sign = StringGetCharacter(s, 19);
        const int off = (int)StringToInteger(StringSubstr(s, 20, 2)) * 3600 +
                        (int)StringToInteger(StringSubstr(s, 23, 2)) * 60;
        if      (sign == '+') t -= off;
        else if (sign == '-') t += off;
    }
    return t;
}
// Minimal string-scan : the JSON string value of `key`, searched forward from `from`
// but NEVER past `until` (the next object's start) - a missing key in one object can
// therefore never grab the NEXT object's field (cross-object desync guard). Advances
// `next_pos` past the value. Escape check counts consecutive backslashes (parity) so
// `\"` (escaped quote) and `\\"` (escaped backslash + real quote) both parse right.
string FFJsonStr(const string json, const string key, const int from, const int until, int &next_pos) {
    next_pos = from;
    const int k = StringFind(json, "\"" + key + "\"", from);
    if (k < 0 || k >= until) return "";
    const int c = StringFind(json, ":", k);
    if (c < 0 || c >= until) return "";
    const int q1 = StringFind(json, "\"", c);
    if (q1 < 0 || q1 >= until) return "";
    int q2 = q1 + 1;
    while (true) {
        q2 = StringFind(json, "\"", q2);
        if (q2 < 0 || q2 >= until) return "";
        int bs = 0;
        while (q2 - 1 - bs >= 0 && StringGetCharacter(json, q2 - 1 - bs) == '\\') bs++;
        if ((bs % 2) == 0) break; // even backslashes before it = a REAL closing quote
        q2++;
    }
    next_pos = q2 + 1;
    string v = StringSubstr(json, q1 + 1, q2 - q1 - 1);
    StringReplace(v, "\\\"", "\"");
    StringReplace(v, "\\/", "/");
    return v;
}
// Parse the flat FF array. Field order in the feed : title, country, date, impact,
// forecast, previous -> a forward sequential scan per object is safe. Keeps High +
// Medium (+ any FN-override event) ; Low/Holiday dropped (display noise, no rule).
int FFParseCalendar(const string json) {
    FFEvent parsed[];
    const int jlen = StringLen(json);
    int n = 0, pos = 0;
    while (true) {
        int p1 = 0, p2 = 0, p3 = 0, p4 = 0;
        const string title = FFJsonStr(json, "title", pos, jlen, p1);
        if (p1 <= pos) break; // no more objects
        // bound the remaining fields to THIS object : never past the next title key
        const int next_obj = StringFind(json, "\"title\"", p1);
        const int bound    = (next_obj > 0 ? next_obj : jlen);
        const string ccy    = FFJsonStr(json, "country", p1, bound, p2);
        const string dates  = FFJsonStr(json, "date",    p2, bound, p3);
        const string impact = FFJsonStr(json, "impact",  p3, bound, p4);
        pos = (p4 > p1 ? p4 : p1);
        if (title == "" || ccy == "" || dates == "") continue;
        const datetime t = FFParseIso8601Utc(dates);
        if (t == 0) continue;
        const bool high = (impact == "High");
        const bool med  = (impact == "Medium");
        const bool ovr  = FFRestrictedOverride(ccy, title);
        if (!high && !med && !ovr) continue;
        ArrayResize(parsed, n + 1);
        parsed[n].t_utc      = t;
        parsed[n].ccy        = ccy;
        parsed[n].title      = title;
        parsed[n].restricted = (high || ovr); // F2 : the 40% RULE class
        n++;
    }
    if (n == 0) return 0; // empty/HTML error page -> caller keeps the old state
    ArrayResize(g_ff_events, n);
    for (int i = 0; i < n; ++i) g_ff_events[i] = parsed[i];
    return n;
}
// FILE BRIDGE : MQL5\Files\ff_calendar_thisweek.json. Two jobs : (a) warm cache
// across indicator re-inits (TF switch re-creates every global -> instant reload,
// no network) ; (b) THE viable FF path when WebRequest is unavailable - MQL5
// FORBIDS WebRequest in INDICATORS (returns -1 / err 4014 even whitelisted ;
// EAs / scripts / services only), so a companion service/EA or any external
// scheduler can drop/refresh this file and the indicator stays FN-aligned.
// Stale guard : a file older than 8 days is ignored (feed = this week).
bool FFLoadFromFile(void) {
    const int h = FileOpen("ff_calendar_thisweek.json", FILE_READ | FILE_BIN | FILE_SHARE_READ | FILE_SHARE_WRITE);
    if (h == INVALID_HANDLE) return false;
    const datetime fmod = (datetime)FileGetInteger(h, FILE_MODIFY_DATE);
    const int sz = (int)FileSize(h);
    if (sz <= 2 || sz > 4 * 1024 * 1024 || (fmod > 0 && TimeCurrent() - fmod > 8 * 24 * 3600)) {
        FileClose(h);
        return false;
    }
    uchar bytes[];
    ArrayResize(bytes, sz);
    const uint rd = FileReadArray(h, bytes, 0, sz);
    FileClose(h);
    if ((int)rd != sz) return false;
    const string json = CharArrayToString(bytes, 0, sz, CP_UTF8);
    const int n = FFParseCalendar(json);
    if (n > 0 && !g_ff_active) {
        g_ff_active = true;
        Print("RiskCockpit : ForexFactory feed ACTIVE via the file bridge (", n,
              " events) - FN-aligned news classification.");
    }
    return (n > 0);
}
void FFSaveToFile(const string json) { // warm cache for the next re-init (best effort)
    const int h = FileOpen("ff_calendar_thisweek.json", FILE_WRITE | FILE_BIN);
    if (h == INVALID_HANDLE) return;
    uchar bytes[];
    const int n = StringToCharArray(json, bytes, 0, WHOLE_ARRAY, CP_UTF8);
    if (n > 1) FileWriteArray(h, bytes, 0, n - 1); // n includes the terminal NUL
    FileClose(h);
}
void FetchFFCalendar(void) {
    // (a) instant, network-free : repopulate the cache from the file bridge after
    // a re-init (TF switch / input change wipes the globals).
    if (ArraySize(g_ff_events) == 0)
        FFLoadFromFile();
    // (b) throttled web attempt : 1 / 60 min, stamp PERSISTED so re-inits do not
    // re-block the UI thread ; 3 s timeout bounds the worst case.
    if (g_ff_last_try == 0 && GlobalVariableCheck("RC_ff_lasttry"))
        g_ff_last_try = (datetime)GlobalVariableGet("RC_ff_lasttry");
    if (g_ff_last_try != 0 && TimeCurrent() - g_ff_last_try < 3600) return;
    g_ff_last_try = TimeCurrent();
    GlobalVariableSet("RC_ff_lasttry", (double)g_ff_last_try);
    const string url = "https://nfs.faireconomy.media/ff_calendar_thisweek.json";
    char post[]; char result[]; string rhdr;
    ResetLastError();
    const int code = WebRequest("GET", url, "", 3000, post, result, rhdr);
    if (code != 200 || ArraySize(result) == 0) {
        const int err = GetLastError();
        static bool s_warned = false;
        if (!s_warned) { // one-shot : keep the cache (if any), MT5 calendar otherwise
            s_warned = true;
            if (code == -1 && err == 4014)
                Print("RiskCockpit : WebRequest unavailable (err 4014). In an INDICATOR, MQL5 forbids ",
                      "WebRequest even when whitelisted (EAs/scripts/services only) - refresh ",
                      "MQL5\\Files\\ff_calendar_thisweek.json via a companion service/EA or a scheduled ",
                      "download instead. If this build ever runs as an EA, also whitelist ",
                      "https://nfs.faireconomy.media. News source now: ",
                      (g_ff_active ? "FF file bridge." : "MT5 calendar fallback."));
            else
                Print("RiskCockpit : FF calendar fetch failed (http=", code, " err=", err,
                      ") - news source now: ", (g_ff_active ? "FF cache/file." : "MT5 calendar fallback."));
        }
        return;
    }
    const string json = CharArrayToString(result, 0, WHOLE_ARRAY, CP_UTF8);
    const int n = FFParseCalendar(json);
    if (n > 0) {
        FFSaveToFile(json); // warm cache for re-inits + offline
        if (!g_ff_active) {
            g_ff_active = true;
            Print("RiskCockpit : ForexFactory feed ACTIVE (", n, " events this week) - FN-aligned news classification.");
        }
    }
}
// F2 rule helpers - all window math in UTC (TimeGMT), returns/contract in SERVER time.
datetime FFNextEvt(const bool restricted_class) {
    // toggle contract identical to the MT5 fallback bodies (v2.02.05) : the HIGH
    // toggle silences the restricted class, the MEDIUM toggle is already checked
    // by the Live_NextMedNewsEvt caller.
    if (restricted_class && !g_eff_news_high) return 0;
    const int win_sec = (g_profile.news_window_minutes > 0 ? g_profile.news_window_minutes : 5) * 60;
    const datetime now_utc = TimeGMT();
    const int srv_off = (int)(TimeCurrent() - TimeGMT());
    datetime best = 0;
    for (int i = 0; i < ArraySize(g_ff_events); ++i) {
        if (g_ff_events[i].restricted != restricted_class) continue;
        // the RULE binds the traded symbol -> official FN currency<->instrument table ;
        // the vigilance class stays symbol-agnostic (informational, like v2.02.05).
        if (restricted_class && !NewsCcyAffectsSymbol(_Symbol, g_ff_events[i].ccy)) continue;
        const datetime te = g_ff_events[i].t_utc;
        if (now_utc >= te - 3600 && now_utc <= te + win_sec) {
            if (best == 0 || te < best) best = te;
        }
    }
    return (best == 0 ? 0 : best + srv_off);
}
bool FFInNewsWindow(void) {
    if (!g_eff_news_high) return false; // same toggle contract as the MT5 fallback body
    const int win_sec = (g_profile.news_window_minutes > 0 ? g_profile.news_window_minutes : 5) * 60;
    const datetime now_utc = TimeGMT();
    for (int i = 0; i < ArraySize(g_ff_events); ++i) {
        if (!g_ff_events[i].restricted) continue;
        if (!NewsCcyAffectsSymbol(_Symbol, g_ff_events[i].ccy)) continue;
        if (now_utc >= g_ff_events[i].t_utc - win_sec && now_utc <= g_ff_events[i].t_utc + win_sec)
            return true;
    }
    return false;
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
    out.floor_capped = false; // v2.13 B1

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
    // v2.13 FEATURE B1 : SL-vs-LIMIT guard - the worst-case loss of THIS trade
    // (at its SL) may never exceed 80% of the room to the nearest active limit :
    // 20% stays in reserve so the account survives the hit. When the configured
    // risk fits under the cap the proposal is unchanged ; otherwise the LOT is
    // reduced so the loss at the recommended SL equals exactly 80% x room.
    out.floor_capped = false;
    {
        const double room = Live_NearestLimitRoom();
        if (room >= 0.0 && out.risk_budget_money > 0.80 * room) {
            out.risk_budget_money = 0.80 * room;
            out.budget_pct = 100.0 * out.risk_budget_money / g_profile.initial_balance;
            out.floor_capped = true;
        }
    }
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

    // v2.03 F4 + v2.03.05c : ONE unified event list (FF feed primary / MT5
    // calendar fallback) feeding TWO surfaces with one colour code :
    //   1. GROUPED icons time-anchored on the axis - one icon per (release time
    //      x currency x level) group, glyph + visible ccy code, titles on the
    //      tooltip ; past groups = dimmed, at their own hour ;
    //   2. window VLINEs + band (upcoming only, unchanged look).
    // NO corner list (JR) : the timeline IS the consolidated news display.

    // v2.13 FEATURE A : hard time window - the timeline keeps 48 h of PAST events
    // (dimmed icons at their own hour) and 24 h of FUTURE ones ; anything beyond
    // either bound is dropped (anti-clutter). Bounds are relative to `now`, so
    // the FF cache filter (server time = t_utc + srv_off) and the MT5 query use
    // the SAME window ; upcoming markers stay <= 24 h by construction.
    const datetime now    = TimeCurrent();
    const datetime t_from = now - 48 * 60 * 60;
    const datetime t_to   = now + 24 * 60 * 60;

    // --- build the unified list ---
    NewsDispItem disp[];
    int nd = 0;
    if (g_ff_active) {
        const int srv_off = (int)(TimeCurrent() - TimeGMT()); // FF times = UTC ; chart axis = SERVER time
        for (int i = 0; i < ArraySize(g_ff_events); ++i) {
            const datetime ts = g_ff_events[i].t_utc + srv_off;
            if (ts < t_from || ts > t_to) continue;
            if (g_ff_events[i].restricted  && !g_eff_news_high) continue; // level toggles
            if (!g_ff_events[i].restricted && !g_eff_news_med)  continue;
            ArrayResize(disp, nd + 1);
            disp[nd].t_srv      = ts;
            disp[nd].ccy        = g_ff_events[i].ccy;
            disp[nd].title      = g_ff_events[i].title;
            disp[nd].restricted = g_ff_events[i].restricted;
            nd++;
        }
    } else {
        MqlCalendarValue values[];
        if (CalendarValueHistory(values, t_from, t_to, NULL, NULL) > 0) {
            for (int i = 0; i < ArraySize(values); ++i) {
                MqlCalendarEvent ev;
                if (!CalendarEventById(values[i].event_id, ev))
                    continue;
                const bool ev_high = (ev.importance == CALENDAR_IMPORTANCE_HIGH);
                const bool ev_med  = (ev.importance == CALENDAR_IMPORTANCE_MODERATE);
                if (!ev_high && !ev_med) continue;         // drop LOW
                if (ev_high && !g_eff_news_high) continue; // V1.29 R : level toggles
                if (ev_med  && !g_eff_news_med)  continue;
                MqlCalendarCountry country;
                if (!CalendarCountryById(ev.country_id, country))
                    continue;
                ArrayResize(disp, nd + 1);
                disp[nd].t_srv      = values[i].time;
                disp[nd].ccy        = country.currency;
                disp[nd].title      = ev.name;
                disp[nd].restricted = ev_high;
                nd++;
            }
        }
    }
    if (nd == 0) { ChartRedraw(chart_id); return; }

    // chart price range : needed for the band rectangle only (VLINEs/labels are
    // time- or pixel-anchored) -> a bad range just skips the bands, never bails.
    const double price_hi = ChartGetDouble(chart_id, CHART_PRICE_MAX);
    const double price_lo = ChartGetDouble(chart_id, CHART_PRICE_MIN);
    const bool   have_price = (price_hi > price_lo);

    // v2.03.05c (JR) : sort chronologically - the (time x ccy x level) grouping
    // and the lane stagger both need time order (the FF feed is usually ordered,
    // the MT5 calendar is ; this makes it a guarantee).
    for (int i = 0; i < nd - 1; ++i)
        for (int j = i + 1; j < nd; ++j)
            if (disp[j].t_srv < disp[i].t_srv) {
                const NewsDispItem tmp = disp[i]; disp[i] = disp[j]; disp[j] = tmp;
            }

    // v2.03.05c FIX 2 (JR) : GROUP the events by (release time x currency x level)
    // - ONE icon per group on the timeline, never one per event. Example : a 04:00
    // CNY drop of 1 high + 3 medium = exactly TWO icons at the 04:00 x (red
    // high-CNY + amber medium-CNY) ; two countries at the same time = separate
    // icons per (ccy x level). The icon shows a VISIBLE currency code ; the
    // group's titles live in the tooltip (FIX 3). NO corner list of any kind
    // (FIX 1) - the timeline IS the consolidated display.
    datetime gr_t[]; string gr_ccy[]; bool gr_restr[]; string gr_titles[]; int gr_cnt[];
    int ng = 0;
    for (int i = 0; i < nd; ++i) {
        int g = -1;
        for (int k = ng - 1; k >= 0; --k) {      // sorted input : candidates sit at the tail
            if (gr_t[k] != disp[i].t_srv) break; // earlier timestamp -> no more matches
            if (gr_ccy[k] == disp[i].ccy && gr_restr[k] == disp[i].restricted) { g = k; break; }
        }
        if (g < 0) {
            ArrayResize(gr_t, ng + 1);     ArrayResize(gr_ccy, ng + 1);
            ArrayResize(gr_restr, ng + 1); ArrayResize(gr_titles, ng + 1);
            ArrayResize(gr_cnt, ng + 1);
            gr_t[ng] = disp[i].t_srv; gr_ccy[ng] = disp[i].ccy;
            gr_restr[ng] = disp[i].restricted; gr_titles[ng] = ""; gr_cnt[ng] = 0;
            g = ng;
            ng++;
        }
        gr_cnt[g]++;
        if (gr_cnt[g] <= 5) // MT5 truncates tooltips : 5 titles + "- +N" below (FIX 3 cap)
            gr_titles[g] = gr_titles[g] + "\n- " + disp[i].title;
    }

    // one icon (+ upcoming window marks) per GROUP. FIX 4 : baseline LOWERED
    // (0.04 -> 0.02 of the range) so the top lane stays clear of the candles -
    // the CHART_CHANGE repin handler uses the SAME constants (kept in sync).
    const double range      = (have_price ? price_hi - price_lo : 0.0);
    const double flag_price = (have_price ? price_lo + range * 0.02 : 0.0);
    const int collision_sec = MathMax(15 * 60,
                                      (int)PeriodSeconds((ENUM_TIMEFRAMES)ChartPeriod(chart_id)) * 2);
    datetime last_t = 0;
    int lane = 0;
    int drawn = 0;
    for (int i = 0; i < ng; ++i) {
        const datetime t_evt = gr_t[i];
        const string id_suffix = IntegerToString(i);
        const bool   ev_past   = (t_evt + win_sec < now);
        // FIX 3 : tooltip = "<ccy> <heure>" header, then one "- <title>" per line.
        string gr_tip = gr_ccy[i] + " " + TimeToString(t_evt, TIME_MINUTES) + gr_titles[i];
        if (gr_cnt[i] > 5)
            gr_tip += "\n- +" + IntegerToString(gr_cnt[i] - 5) + " " + Tr("news_more");

        if (have_price) { // timeline icon : one per group, currency code VISIBLE
            if (last_t != 0 && (t_evt - last_t) < collision_sec) lane = (lane + 1) % 5;
            else lane = 0;
            last_t = t_evt;
            const double flag_y  = flag_price + range * 0.018 * lane; // compact stagger (same-time groups fan out)
            const string flag_id = "RC_NEWS_FLAG_" + IntegerToString(lane) + "_" + id_suffix; // name feeds the CHART_CHANGE repin handler
            ObjectCreate(chart_id, flag_id, OBJ_TEXT, 0, t_evt, flag_y);
            ObjectSetInteger(chart_id, flag_id, OBJPROP_TIME, t_evt);
            ObjectSetDouble (chart_id, flag_id, OBJPROP_PRICE, flag_y);
            ObjectSetString (chart_id, flag_id, OBJPROP_TEXT, // FIX 2 : glyph + ccy code, no hover needed
                             ShortToString((ushort)(gr_restr[i] ? 0x25BC : 0x25C6)) + " " + gr_ccy[i]);
            ObjectSetInteger(chart_id, flag_id, OBJPROP_COLOR,
                             ev_past ? g_theme.text_dim // past = dimmed, AT its own time (shape = level)
                                     : (gr_restr[i] ? g_theme.red : g_theme.warn));
            ObjectSetInteger(chart_id, flag_id, OBJPROP_FONTSIZE, 10);
            ObjectSetString (chart_id, flag_id, OBJPROP_FONT, "Consolas");
            ObjectSetInteger(chart_id, flag_id, OBJPROP_ANCHOR, ANCHOR_LEFT_LOWER);
            ObjectSetInteger(chart_id, flag_id, OBJPROP_BACK, false);
            ObjectSetInteger(chart_id, flag_id, OBJPROP_SELECTABLE, false);
            ObjectSetInteger(chart_id, flag_id, OBJPROP_HIDDEN, true);
            ObjectSetString (chart_id, flag_id, OBJPROP_TOOLTIP, gr_tip);
        }

        if (ev_past) continue; // past : icon only (no window lines)
        const color  vl_clr   = (gr_restr[i] ? g_theme.red : g_theme.warn);
        const int    vl_width = (gr_restr[i] ? 2 : 1);
        const int    vl_style = (gr_restr[i] ? STYLE_SOLID : STYLE_DOT);
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
            ObjectSetString(chart_id, vl_id[v], OBJPROP_TOOLTIP, gr_tip);
        }
        if (gr_restr[i] && have_price) { // band = RULE groups only (N13 outline style kept)
            const string band_id = "RC_NEWS_BAND_" + id_suffix;
            ObjectCreate(chart_id, band_id, OBJ_RECTANGLE, 0, vl_t[0], price_hi, vl_t[1], price_lo);
            ObjectSetInteger(chart_id, band_id, OBJPROP_COLOR, (color)0x000088CC);
            ObjectSetInteger(chart_id, band_id, OBJPROP_BGCOLOR, (color)0x000088CC);
            ObjectSetInteger(chart_id, band_id, OBJPROP_FILL, false);
            ObjectSetInteger(chart_id, band_id, OBJPROP_BACK, true);
            ObjectSetInteger(chart_id, band_id, OBJPROP_STYLE, STYLE_SOLID);
            ObjectSetInteger(chart_id, band_id, OBJPROP_WIDTH, 1);
            ObjectSetInteger(chart_id, band_id, OBJPROP_SELECTABLE, false);
            ObjectSetInteger(chart_id, band_id, OBJPROP_HIDDEN, true);
        }
        drawn++;
        if (drawn >= 60) // cap on UPCOMING window markers (all-currency coverage)
            break;
    }

    // v2.03.05c FIX 1 (JR) : NO corner news list of any kind. The (time x ccy x
    // level) grouping above IS the consolidated display, on the timeline itself.
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
    // v2.02 MULTI-THEMES : palette (brand) axis + dark/light relabelled as MODE ;
    // hover taglines for the 3 palettes.
    AddTr("set_palette",     "Theme :",               "Thème :",               "Tema :");
    AddTr("set_mode",        "Mode :",                "Mode :",                "Modo :");
    AddTr("pal_tip_emerald", "Green momentum, cool head",  "L'élan vert, la tête froide",  "Impulso verde, mente fría");
    AddTr("pal_tip_indigo",  "Depth & composure",          "Profondeur & sang-froid",      "Profundidad y sangre fría");
    AddTr("pal_tip_mono",    "Absolute focus, zero noise", "Focus absolu, zéro bruit",     "Enfoque absoluto, cero ruido");
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
    // --- v2.02.05 : FN Instant (trailing floor) presentation + news vigilance ---
    AddTr("rule_payout",     "Payout eligibility",     "Éligibilité payout",  "Elegibilidad pago");
    AddTr("ins_margin",      "Room",                   "Marge",               "Margen");
    AddTr("ins_locked",      "locked",                 "verrouillé",          "bloqueado"); // short : must fit the _val column with the $ figure
    AddTr("ins_tip_floor",   "Floor:",                 "Plancher :",          "Suelo :");
    AddTr("ins_tip_floor2",  "equity below = account lost",
                             "équity dessous = compte perdu",
                             "equity debajo = cuenta perdida");
    AddTr("ins_tip_permitted","max loss, fixed",       "perte max fixe",      "pérdida máx fija");
    AddTr("ins_tip_lock",    "breakeven lock",         "verrou breakeven",    "bloqueo breakeven");
    AddTr("ins_tip_locked1", "floor LOCKED at",        "plancher VERROUILLÉ à","suelo BLOQUEADO en");
    AddTr("ins_tip_locked2", "- firm capital protected",
                             "- capital firme protégé",
                             "- capital protegido");
    AddTr("news_med_check",  "Medium - check FN",      "Medium - vérifier FN","Medium - verificar FN");
    AddTr("news_more",       "more",                   "autres",              "más"); // v2.03.05c : grouped-icon tooltip cap suffix
    // --- v3 SHELL : the rail/panel chrome goes through the SAME table ---
    AddTr("shl_lim",       "LIMITS",             "LIMITES",              "LÍMITES");
    AddTr("shl_pos",       "OPEN POSITIONS",     "POSITIONS OUVERTES",   "POSICIONES ABIERTAS");
    AddTr("shl_lot",       "SUGGESTED LOT",      "LOT CONSEILLÉ",        "LOTE SUGERIDO");
    AddTr("shl_news",      "NEWS WINDOW",        "FENÊTRE NEWS",         "VENTANA NOTICIAS");
    AddTr("shl_disc",      "DISCIPLINE",         "DISCIPLINE",           "DISCIPLINA");
    AddTr("shl_cpt",       "ACCOUNT",            "COMPTE",               "CUENTA");
    AddTr("shl_cfg",       "SETTINGS",           "RÉGLAGES",             "AJUSTES");
    AddTr("shl_help",      "LEGEND",             "LÉGENDE",              "LEYENDA");
    AddTr("shl_limhead",   "LIMIT USAGE",        "CONSOMMATION DES LIMITES", "USO DE LÍMITES");
    AddTr("shl_survhead",  "SURVIVAL ROOM",      "MARGE DE SURVIE",      "MARGEN DE SUPERVIVENCIA");
    AddTr("shl_room",      "Room to the limit",  "Marge avant limite",   "Margen hasta el límite");
    AddTr("shl_budget80",  "One trade (80%)",    "Budget d'un trade (80%)", "Presupuesto por op. (80%)");
    AddTr("shl_nolimit",   "No active limit on this profile.",
                           "Aucune limite active sur ce profil.",
                           "Sin límite activo en este perfil.");
    AddTr("shl_posnone",   "No open position.",  "Aucune position ouverte.", "Sin posiciones abiertas.");
    AddTr("shl_pospnl",    "Floating P&L",       "P&L flottant total",   "P&L flotante total");
    AddTr("shl_nosl",      "NO SL",              "SANS SL",              "SIN SL");
    AddTr("shl_lotfrom",   "WHERE THIS LOT COMES FROM", "D'OÙ VIENT CE LOT", "DE DONDE SALE ESTE LOTE");
    AddTr("shl_lotbudget", "Trade budget",       "Budget du trade",      "Presupuesto de la op.");
    AddTr("shl_lotn",      "Planned trades (N)", "Trades prévus (N)",    "Ops previstas (N)");
    AddTr("shl_lotcost",   "SYMBOL COST",        "COÛT DU SYMBOLE",      "COSTE DEL SÍMBOLO");
    AddTr("shl_newssrc",   "Source",             "Source",               "Fuente");
    AddTr("shl_newsstate", "State",              "État",                 "Estado");
    AddTr("shl_newswin",   "Window",             "Fenêtre",              "Ventana");
    AddTr("shl_newsnext",  "UPCOMING",           "À VENIR",              "PRÓXIMOS");
    AddTr("shl_discstate", "STATE",              "ÉTAT",                 "ESTADO");
    AddTr("shl_discday",   "TODAY",              "ACTIVITÉ DU JOUR",     "ACTIVIDAD DE HOY");
    AddTr("shl_free",      "Free margin",        "Marge libre",          "Margen libre");
    AddTr("shl_spread",    "Spread",             "Spread",               "Spread");
    AddTr("shl_comm",      "Commission / lot",   "Commission / lot",     "Comisión / lote");
    AddTr("shl_split",     "Split",              "Split",                "Reparto");
    AddTr("shl_mindays",   "Min days",           "Jours mini",           "Días min");
    AddTr("shl_lockrtools",
        "Always on for a prop plan.",
        "Toujours actif sur un plan prop.",
        "Siempre activo en un plan prop.");
    AddTr("shl_lockviol",
        "This profile cannot be restricted.",
        "Ce profil ne peut pas être restreint.",
        "Este perfil no puede restringirse.");
    AddTr("shl_closeea",   "Closing : EA version",
                           "Fermeture : version EA",
                           "Cierre : versión EA");
    AddTr("shl_qs",
        "Quick Strike",
        "Quick Strike",
        "Quick Strike");
    AddTr("shl_copy",
        "copy",
        "copier",
        "copiar");
    AddTr("shl_tag_marg",
        "margin",
        "marge",
        "margen");
    AddTr("shl_tag_room",
        "room",
        "reste",
        "resto");
    AddTr("shl_tag_free",
        "free",
        "libre",
        "libre");
    AddTr("shl_lotmax",
        "Max allowed lot",
        "Lot max autorisé",
        "Lote max permitido");
    AddTr("shl_newstrades",
        "News trades",
        "Trades news",
        "Trades noticias");
    AddTr("shl_elig",
        "elig",
        "elig",
        "eleg");
    AddTr("shl_afterviol",
        "AFTER A VIOLATION",
        "APRÈS VIOLATION",
        "TRAS UNA VIOLACIÓN");
    AddTr("shl_violm",
        "Margin violation",
        "Violation marge",
        "Violación margen");
    AddTr("shl_violr",
        "Risk violation",
        "Violation risque",
        "Violación riesgo");
    AddTr("shl_lockon",
        "LOCK ACTIVE",
        "VERROU ACTIF",
        "BLOQUEO ACTIVO");
    AddTr("shl_lockask",
        "CONFIRM ?",
        "CONFIRMER ?",
        "CONFIRMAR ?");
    AddTr("shl_lockarm",
        "ARM THE LOCK",
        "ARMER LE VERROU",
        "ARMAR EL BLOQUEO");
    AddTr("shl_hyper",
        "Hyperactivity",
        "Hyperactivité",
        "Hiperactividad");
    AddTr("shl_msgs",
        "Server msgs (orders)",
        "Msgs serveur (ordres)",
        "Msgs servidor (órdenes)");
    AddTr("shl_profile",
        "PROFILE",
        "PROFIL",
        "PERFIL");
    AddTr("shl_cycle",
        "CYCLE START",
        "DÉBUT DE CYCLE",
        "INICIO DE CICLO");
    AddTr("shl_year",
        "Year",
        "Année",
        "Año");
    AddTr("shl_month",
        "Month",
        "Mois",
        "Mes");
    AddTr("shl_day",
        "Day",
        "Jour",
        "Día");
    AddTr("shl_tabrisk",
        "RISK",
        "RISQUE",
        "RIESGO");
    AddTr("shl_tabdisc",
        "DISCIPLINE",
        "DISCIPLINE",
        "DISCIPLINA");
    AddTr("shl_tabadv",
        "ADVANCED",
        "AVANCE",
        "AVANZADO");
    AddTr("shl_tabdisp",
        "DISPLAY",
        "AFFICHAGE",
        "PANTALLA");
    AddTr("shl_belines",
        "Break-even lines",
        "Lignes break-even",
        "Líneas break-even");
    AddTr("shl_more",
        "more",
        "autres",
        "más");
    AddTr("shl_r_cpt",
        "ACCT",
        "CPT",
        "CTA");
    AddTr("shl_r_help",
        "HELP",
        "AIDE",
        "AYUDA");
    AddTr("shl_floorhint",
        "Equity below this level = account lost.",
        "Equity sous ce niveau = compte perdu.",
        "Equity bajo este nivel = cuenta perdida.");
    AddTr("shl_moresize",
        "more : enlarge the window",
        "autres : agrandis la fenêtre",
        "más : agranda la ventana");
    AddTr("shl_pyramid",
        "PYRAMID",
        "PYRAMIDE",
        "PIRÁMIDE");
    AddTr("shl_lotnoroom",
        "No room left : do not take this trade.",
        "Aucune marge : ne prends pas ce trade.",
        "Sin margen : no tomes esta operación.");
    AddTr("shl_lotcap80",
        "Capped at 80% of the survival margin.",
        "Plafonné à 80% de la marge de survie.",
        "Limitado al 80% del margen de supervivencia.");
    AddTr("shl_srcmt",
        "MT5 calendar [MT]",
        "Calendrier MT5 [MT]",
        "Calendario MT5 [MT]");
    AddTr("shl_inactive",
        "inactive",
        "inactive",
        "inactiva");
    AddTr("shl_newsactel",
        "ACTIVE - eligible profit ",
        "ACTIVE - profit éligible ",
        "ACTIVA - beneficio elegible ");
    AddTr("shl_inmin",
        "in ",
        "dans ",
        "en ");
    AddTr("shl_none24",
        "Nothing in the next 24 h.",
        "Rien dans les 24 h.",
        "Nada en las próximas 24 h.");
    AddTr("shl_rule40",
        "40% rule",
        "règle 40%",
        "regla 40%");
    AddTr("shl_checkfn",
        "check FN",
        "vérifier FN",
        "revisar FN");
    AddTr("shl_slgon",
        "SL GUARD TRIGGERED",
        "GARDE SL DÉCLENCHÉE",
        "GUARDIA SL ACTIVADA");
    AddTr("shl_tilton",
        "TILT DETECTED",
        "TILT DÉTECTÉ",
        "TILT DETECTADO");
    AddTr("shl_allclear",
        "ALL CLEAR",
        "RAS",
        "TODO OK");
    AddTr("shl_selflockt",
        "Self-lock (Ulysses)",
        "Self-lock (Ulysse)",
        "Auto-bloqueo (Ulises)");
    AddTr("shl_dailylock",
        "Daily lock",
        "Verrou journalier",
        "Bloqueo diario");
    AddTr("shl_onnow",
        "active",
        "actif",
        "activo");
    AddTr("shl_raisesl",
        "Raise the SL",
        "Remonte la SL",
        "Sube el SL");
    AddTr("shl_noslpos",
        "position without SL",
        "position sans SL",
        "posición sin SL");
    AddTr("shl_keep20",
        "Goal : keep 20% of room.",
        "Objectif : garder 20% de marge.",
        "Objetivo : conservar 20% de margen.");
    AddTr("shl_tradesn",
        "Trades",
        "Trades",
        "Operaciones");
    AddTr("shl_tiltwin",
        "Tilt window",
        "Fenêtre tilt",
        "Ventana tilt");
    AddTr("shl_accountn",
        "Account",
        "Compte",
        "Cuenta");
    AddTr("shl_cfgtheme",
        "Theme",
        "Thème",
        "Tema");
    AddTr("shl_cfgmode",
        "Mode",
        "Mode",
        "Modo");
    AddTr("shl_light",
        "light",
        "clair",
        "claro");
    AddTr("shl_dark",
        "dark",
        "sombre",
        "oscuro");
    AddTr("shl_cfglang",
        "Language",
        "Langue",
        "Idioma");
    AddTr("shl_alerts",
        "ALERTS",
        "ALERTES",
        "ALERTAS");
    AddTr("shl_sound",
        "Sound",
        "Son",
        "Sonido");
    AddTr("shl_comforth",
        "COMFORT",
        "CONFORT",
        "CONFORT");
    AddTr("shl_comforts",
        "Comfort scale",
        "Échelle confort",
        "Escala de confort");
    AddTr("shl_disclockt",
        "Discipline lock",
        "Verrou discipline",
        "Bloqueo disciplina");
    AddTr("shl_rtools",
        "Risk toolkit",
        "Outils de risque",
        "Herramientas de riesgo");
    AddTr("shl_hsafe",
        "SAFE - below 80% of the limit",
        "SAFE - sous 80% de la limite",
        "SAFE - por debajo del 80% del límite");
    AddTr("shl_hwatch",
        "WATCH - 80% used, be careful",
        "WATCH - 80% consommé, prudence",
        "WATCH - 80% consumido, prudencia");
    AddTr("shl_hbreach",
        "BREACH - limit reached",
        "BREACH - limite atteinte",
        "BREACH - límite alcanzado");
    AddTr("shl_hr40",
        "40% RULE",
        "RÈGLE 40%",
        "REGLA 40%");
    AddTr("shl_hr40a",
        "News window : only ",
        "Fenêtre news : seuls ",
        "Ventana news : solo ");
    AddTr("shl_hr40b",
        "of the profit counts ; losses count 100%.",
        "du profit comptent ; les pertes comptent 100%.",
        "del beneficio cuenta ; las pérdidas 100%.");
    AddTr("shl_hsurv",
        "SURVIVAL MARGIN",
        "MARGE DE SURVIE",
        "MARGEN DE SUPERVIVENCIA");
    AddTr("shl_hsurva",
        "A trade never risks more than 80% of",
        "Un trade ne risque jamais plus de 80% de",
        "Una operación nunca arriesga más del 80%");
    AddTr("shl_hsurvb",
        "the room : 20% are kept to survive.",
        "la marge : 20% restent pour survivre.",
        "del margen : el 20% queda para sobrevivir.");
    AddTr("shl_habout",
        "ABOUT",
        "À PROPOS",
        "ACERCA DE");
    AddTr("shl_version",
        "Version",
        "Version",
        "Versión");
    AddTr("shl_newssrc",
        "News source",
        "Source news",
        "Fuente noticias");
    AddTr("shl_hro1",
        "MONITORING tool : it never opens, changes",
        "Outil de SUIVI : il n ouvre, ne modifie et",
        "Herramienta de SEGUIMIENTO : no abre, no");
    AddTr("shl_hro2",
        "or closes ANY trade. No signal.",
        "ne ferme AUCUN trade. Aucun signal.",
        "modifica ni cierra NINGUNA operación. Sin señal.");
    AddTr("shl_secsize",
        "sections : enlarge the window",
        "sections : agrandis la fenêtre",
        "secciones : agranda la ventana");
    AddTr("shl_rtoolsoff",
        "Risk toolkit OFF (personal account).",
        "Outils de risque OFF (compte perso).",
        "Herramientas OFF (cuenta personal).");
    AddTr("shl_bandwknd",
        "OPEN POSITIONS INTO THE WEEKLY CLOSE - consider flattening",
        "POSITIONS OUVERTES AVANT LA CLÔTURE HEBDO - envisage de solder",
        "POSICIONES ABIERTAS ANTES DEL CIERRE SEMANAL - considera cerrar");
    AddTr("shl_minsleft",
        "min left",
        "min restantes",
        "min restantes");
    AddTr("shl_bandraise",
        "raise ",
        "remonte ",
        "sube ");
    AddTr("shl_bandsllow",
        "SL TOO LOW - breach risk",
        "SL TROP BAS - risque de brèche",
        "SL DEMASIADO BAJO - riesgo de brecha");
    AddTr("shl_bandlocked",
        "DISCIPLINE LOCK ACTIVE",
        "VERROU DISCIPLINE ACTIF",
        "BLOQUEO DE DISCIPLINA ACTIVO");
    AddTr("shl_bandtrades",
        "trades in",
        "trades en",
        "operaciones en");
    AddTr("shl_bandslow",
        "min : slow down",
        "min : ralentis",
        "min : reduce el ritmo");
    AddTr("shl_newshi",
        "News HIGH",
        "News HIGH",
        "News HIGH");
    AddTr("shl_newsmed",
        "News MEDIUM",
        "News MEDIUM",
        "News MEDIUM");
    // --- v3 SHELL tooltips : ONE entry per bubble, "title|description" -------
    AddTr("tipr_0", "Limits|Usage of the NEAREST active limit. Marker = 80%.",
                    "Limites|Conso de la limite la plus proche. Repère = 80%.",
                    "Límites|Uso del límite más cercano. Marca = 80%.");
    AddTr("tipr_1", "Positions|Open trades and the worst row status.",
                    "Positions|Positions ouvertes et pire statut de ligne.",
                    "Posiciones|Operaciones abiertas y peor estado.");
    AddTr("tipr_2", "Suggested lot|Amber = capped at 80%, red = no room left.",
                    "Lot conseillé|Ambre = plafonné à 80%, rouge = plus de marge.",
                    "Lote sugerido|Ámbar = limitado al 80%, rojo = sin margen.");
    AddTr("tipr_3", "News|Minutes to the next rule-bound event.",
                    "News|Minutes avant le prochain event soumis à la règle.",
                    "Noticias|Minutos hasta el próximo evento con regla.");
    AddTr("tipr_4", "Discipline|Lock, tilt, SL guard, trades today.",
                    "Discipline|Verrou, tilt, garde SL, trades du jour.",
                    "Disciplina|Bloqueo, tilt, guarda SL, ops de hoy.");
    AddTr("tipr_5", "Account|Plan, size, phase, add-ons, split.",
                    "Compte|Plan, taille, phase, add-ons, split.",
                    "Cuenta|Plan, tamaño, fase, extras, reparto.");
    AddTr("tipr_6", "Settings|Display, news, alerts, comfort.",
                    "Réglages|Affichage, news, alertes, confort.",
                    "Ajustes|Pantalla, noticias, alertas, confort.");
    AddTr("tipr_7", "Help|Colour legend, rules, version.",
                    "Aide|Légende des couleurs, règles, version.",
                    "Ayuda|Leyenda de colores, reglas, versión.");
    AddTr("tipr_chev", "Sidebar|Opens every section, stacked.",
                       "Sidebar|Ouvre toutes les sections empilées.",
                       "Barra lateral|Abre todas las secciones apiladas.");
    AddTr("tipn_0", "RiskCockpit|Opens the full sidebar.",
                    "RiskCockpit|Ouvre la sidebar complète.",
                    "RiskCockpit|Abre la barra lateral completa.");
    AddTr("tipn_1", "Symbol|Pick a Market Watch symbol.",
                    "Symbole|Choisir un symbole du Market Watch.",
                    "Símbolo|Elegir un símbolo del Market Watch.");
    AddTr("tipn_2", "Timeframe|Switch the chart timeframe.",
                    "Unité de temps|Changer l'unité de temps du graphique.",
                    "Temporalidad|Cambiar la temporalidad del gráfico.");
    AddTr("tipn_3", "Vitals|Current equity and open positions.",
                    "Vitals|Equity courante et positions ouvertes.",
                    "Vitales|Equity actual y posiciones abiertas.");
    AddTr("tipn_4", "Health|Account health out of 100 (100 = safe).",
                    "Santé|Santé du compte sur 100 (100 = sûr).",
                    "Salud|Salud de la cuenta sobre 100 (100 = seguro).");
    AddTr("tipn_5", "Theme|Emerald / Indigo / Slate.",
                    "Thème|Émeraude / Indigo / Ardoise.",
                    "Tema|Esmeralda / Indigo / Pizarra.");
    AddTr("tipn_6", "Mode|Dark / light.", "Mode|Sombre / clair.", "Modo|Oscuro / claro.");
    AddTr("tipn_7", "Clock|Broker server time.",
                    "Horloge|Heure serveur du broker.",
                    "Reloj|Hora del servidor del broker.");
    AddTr("tipn_8", "Remove|Takes RiskCockpit off this chart.",
                    "Retirer|Retire RiskCockpit de ce graphique.",
                    "Quitar|Quita RiskCockpit de este gráfico.");
    AddTr("tipp_close", "Close|Closes the panel, the rail stays.",
                        "Fermer|Referme le panneau, le rail reste.",
                        "Cerrar|Cierra el panel, el carril queda.");
    AddTr("tipp_pin",   "Sidebar|Single section / full sidebar.",
                        "Sidebar|Section unique / sidebar complète.",
                        "Barra lateral|Sección única / barra completa.");
    AddTr("tipl_0", "Room|Dollars before the nearest active limit.",
                    "Marge|Dollars avant la limite active la plus proche.",
                    "Margen|Dólares antes del límite activo más cercano.");
    AddTr("tipl_1", "Floor|Equity under this level = account lost.",
                    "Plancher|Equity sous ce niveau = compte perdu.",
                    "Suelo|Equity bajo este nivel = cuenta perdida.");
    AddTr("tipl_2", "Cumulative margin|Margin used / plan cap.",
                    "Marge cumulée|Marge engagée / plafond du plan.",
                    "Margen acumulado|Margen usado / tope del plan.");
    AddTr("tipl_3", "Open risk|Sum of risks at the stops / cap.",
                    "Risque ouvert|Somme des risques aux SL / plafond.",
                    "Riesgo abierto|Suma de riesgos en los SL / tope.");
    AddTr("tipl_4", "Daily DD|Today's loss / daily limit.",
                    "DD journalier|Perte du jour / limite journalière.",
                    "DD diario|Pérdida de hoy / límite diario.");
    AddTr("tipl_5", "Overall DD|Total loss / plan maximum.",
                    "DD total|Perte totale / limite max du plan.",
                    "DD total|Pérdida total / máximo del plan.");
    AddTr("tipo_0", "Budget|What this trade may lose at its stop.",
                    "Budget|Ce que ce trade a le droit de perdre à sa SL.",
                    "Presupuesto|Lo que esta op. puede perder en su SL.");
    AddTr("tipo_1", "Free margin|Broker free margin / initial balance.",
                    "Marge libre|Marge broker disponible / balance initiale.",
                    "Margen libre|Margen libre del broker / balance inicial.");
    AddTr("tipo_2", "80% cap|Lot reduced to keep a 20% reserve.",
                    "Plafond 80%|Lot réduit pour garder 20% de réserve.",
                    "Tope 80%|Lote reducido para guardar 20% de reserva.");
    AddTr("tipw_0", "News source|FF = ForexFactory feed (FN-aligned). MT = fallback.",
                    "Source news|FF = flux ForexFactory (aligné FN). MT = secours.",
                    "Fuente noticias|FF = feed ForexFactory (alineado FN). MT = respaldo.");
    AddTr("tipw_1", "News rule|Red = the 40% rule. Amber = check on FN.",
                    "Règle news|Rouge = règle 40%. Ambre = à vérifier sur FN.",
                    "Regla noticias|Rojo = regla 40%. Ámbar = verificar en FN.");
    AddTr("tipw_2", "Upcoming|Next groups (time, currency, level).",
                    "A venir|Prochains groupes (heure, devise, niveau).",
                    "Próximos|Próximos grupos (hora, divisa, nivel).");
    AddTr("tipd_0", "Lock|Time left before it releases.",
                    "Verrou|Temps restant avant déverrouillage.",
                    "Bloqueo|Tiempo restante antes de liberarse.");
    AddTr("tipd_1", "SL guard|Stop price that keeps a 20% survival room.",
                    "Garde SL|Prix de SL qui laisse 20% de marge de survie.",
                    "Guarda SL|Precio de SL que deja 20% de margen.");
    AddTr("tipd_2", "Tilt|Trades in the window / configured threshold.",
                    "Tilt|Trades dans la fenêtre / seuil configuré.",
                    "Tilt|Ops en la ventana / umbral configurado.");
    AddTr("tipc_0", "Palette|Emerald / Indigo / Slate.",
                    "Palette|Émeraude / Indigo / Ardoise.",
                    "Paleta|Esmeralda / Indigo / Pizarra.");
    AddTr("tipc_1", "Mode|Dark / light.", "Mode|Sombre / clair.", "Modo|Oscuro / claro.");
    AddTr("tipc_2", "Language|EN / FR / ES (persisted).",
                    "Langue|EN / FR / ES (persistée).",
                    "Idioma|EN / FR / ES (persistido).");
    AddTr("tipc_3", "News HIGH|Events bound by the 40% rule.",
                    "News HIGH|Events soumis à la règle 40%.",
                    "Noticias ALTA|Eventos sujetos a la regla 40%.");
    AddTr("tipc_4", "News MEDIUM|Watch only : check on FN, no rule.",
                    "News MEDIUM|Vigilance : à vérifier sur FN, pas de règle.",
                    "Noticias MEDIA|Vigilancia : verificar en FN, sin regla.");
    AddTr("tipc_5", "Sound|Audible alert on status changes.",
                    "Son|Alerte sonore aux changements de statut.",
                    "Sonido|Alerta sonora en cambios de estado.");
    AddTr("tipc_6", "Telegram|Sends alerts (token in the Inputs).",
                    "Telegram|Envoi des alertes (token dans les Inputs).",
                    "Telegram|Envía alertas (token en los Inputs).");
    AddTr("tipc_7", "Comfort|Vertical padding of the chart.",
                    "Confort|Marge verticale du graphique.",
                    "Confort|Margen vertical del gráfico.");
    AddTr("tipc_8", "Discipline|Daily lock + tilt detection.",
                    "Discipline|Verrou journalier + détection de tilt.",
                    "Disciplina|Bloqueo diario + detección de tilt.");
    AddTr("tipc_9", "Risk tools|The whole prop toolkit (personal account).",
                    "Outils|Toute la boîte à outils prop (compte perso).",
                    "Herramientas|Todo el kit prop (cuenta personal).");
    AddTr("tip_band",   "Alert|Blocking state : read it, act, it goes away.",
                        "Alerte|État bloquant : lis la ligne, agis, elle part.",
                        "Alerta|Estado bloqueante : lee, actúa, desaparece.");
    AddTr("tip_posrow", "Position|Symbol, side, volume, P&L, age, stop present.",
                        "Position|Symbole, sens, volume, P&L, âge, présence de SL.",
                        "Posición|Símbolo, sentido, volumen, P&L, edad, SL.");
    AddTr("tip_fltclose",
        "Closing|Disabled : an indicator cannot send orders. Closing lives in the EA version.",
        "Fermeture|Désactivé : un indicateur ne passe pas d'ordre. La fermeture est dans la version EA.",
        "Cierre|Desactivado : un indicador no envía órdenes. El cierre está en la versión EA.");
    AddTr("tipq_0",     "Room|Distance in $ to the nearest active limit. Click : the limits.",
                        "Marge|Distance en $ à la limite active la plus proche. Clic : les limites.",
                        "Margen|Distancia en $ al límite activo más cercano. Clic : los límites.");
    AddTr("tipq_1",     "Lot|Advised size for the current risk. Click : the advisor.",
                        "Lot|Taille conseillée pour le risque en cours. Clic : le conseiller.",
                        "Lote|Tamaño aconsejado para el riesgo actual. Clic : el asesor.");
    AddTr("tipq_2",     "News|Minutes to the next binding event. Click : the news.",
                        "News|Minutes avant le prochain événement contraignant. Clic : les news.",
                        "News|Minutos hasta el próximo evento vinculante. Clic : las noticias.");
    AddTr("tip_cpt",    "Profile|The plan EVERY limit is derived from.",
                        "Profil|Le plan dont TOUTES les limites sont déduites.",
                        "Perfil|El plan del que salen TODOS los límites.");
    AddTr("tip_help",   "Version|Current build + active news source.",
                        "Version|Build en cours + source des news active.",
                        "Versión|Build actual + fuente de noticias activa.");
    // --- v2.13 FEATURE B : SL-vs-limit survival guard (20% margin) ---
    AddTr("slguard",
          "SL too low - breach risk : raise the SL to keep a 20% margin",
          "SL trop bas - risque de brèche : remonte la SL pour garder 20% de marge",
          "SL muy bajo - riesgo de brecha : sube el SL para mantener 20% de margen");
    AddTr("f_floorcap",
          "[lot capped : worst-case loss limited to 80% of the room to the nearest limit - 20% survival margin]",
          "[lot plafonné : perte pire-cas limitée à 80% de la marge vers la limite la plus proche - 20% de réserve]",
          "[lote limitado : pérdida máxima al 80% del margen hasta el límite más cercano - 20% de reserva]");
    // --- v2.03 F3 : news source badge (ForexFactory feed vs MT5-calendar fallback) ---
    AddTr("news_src_ff",     "news: FF (ForexFactory feed, FN-aligned)",
                             "news: FF (flux ForexFactory, aligné FN)",
                             "news: FF (feed ForexFactory, alineado FN)");
    AddTr("news_src_mt",     "news: MT (MT5 calendar fallback)",
                             "news: MT (calendrier MT5, secours)",
                             "news: MT (calendario MT5, respaldo)");
    AddTr("news_rule_tip",
          "40% rule = HIGH-impact only (5min +/-, winning-trade profits). Medium = check the FN calendar/Clarity (MQL5 under-classes some central-bank speeches).",
          "Règle 40% = high-impact (5min +/-, profits gagnants). Medium = à vérifier sur le calendrier/Clarity FN (MQL5 sous-classe parfois les discours banques centrales).",
          "Regla 40% = solo high-impact (5min +/-, beneficios ganadores). Medium = verificar en el calendario/Clarity FN (MQL5 subclasifica algunos discursos de bancos centrales).");
    // --- verdict badge + clock ---
    AddTr("v_ontrack",   "HEALTHY",       "SAIN",           "SANO");        // v2.01.03 : health words - the score is account HEALTH /100
    AddTr("v_atrisk",    "CAUTION",       "PRUDENCE",       "PRECAUCIÓN");
    AddTr("v_violation", "DANGER",        "DANGER",         "PELIGRO");
    AddTr("live",        "LIVE",          "LIVE",           "LIVE"); // FINAL : the green dot (U+25CF) is concatenated at the call sites - no more "* " placeholder
    AddTr("weekend_hold","WEEKEND HOLD!", "TENUE WEEKEND!", "RETENER FINDE!");
    AddTr("flatten",     "  FLATTEN!",    "  FERMER!",      "  CERRAR!");
    // --- status chips ---
    AddTr("chip_ok",   "OK",     "OK",        "OK");      // positions keep OK (E6)
    AddTr("chip_safe", "SAFE",   "SUR",       "SEGURO");  // E2 : mockup vocabulary for metered RULES
    AddTr("chip_warn", "WATCH",  "SURVEILLE", "VIGILAR"); // E2 : was WARN
    AddTr("chip_red",  "BREACH", "BRÈCHE",    "BRECHA");  // E2 : was RED
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
    AddTr("pos_slq",  "SL?",   "SL ?",   "SL?"); // E6 : SL missing, still in grace (amber WATCH)
    AddTr("pos_none", "no open positions", "aucune position ouverte", "sin posiciones abiertas"); // FINAL : empty-section hint
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
    AddTr("set_cooldownn", "Cooldown losses :",          "Pertes pause :",             "Pérdidas pausa :");
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
    AddTr("set_cycday",    "Cycle day :",                "Jour cycle :",               "Día ciclo :");
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

// Phase 3 (b) : reflect BE = OFF on its canvas face + label WITHOUT a full rebuild
// (the auto-disarm path fires from OnTradeTransaction, which must stay cheap). Flips the
// registry face style so the next PaintFaces shows it off, recolours the label, repaints.

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
        ObjectSetInteger(0, id, OBJPROP_BACK, true); // POLISH B1 : behind the panel (SL/TP/news lines already are) ; still selectable/draggable
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

// D-FULL step 2 : the ACTIVE state repaints the face in the accent gradient + a dark
// label. Geometry comes from the hit registry (the zone DrawSetButton just added for
// this id) = the same single source, so face/zone/label can never drift.

// G2/G4 : an overlay label at ZORDER 250 (between the modal cover 240 and the
// buttons 260). Free-standing helper so every row stays one call.
// A labelled ON/OFF toggle button (60 px). The id encodes the setting.
// D-FULL step 2 : ON/OFF = a sliding PILL (mockup .sw), state carried by the knob
// position + accent gradient - no more 60px ON/OFF text button.
// E7 : two-cell SEGMENT toggle (A | B) painted into the OPEN modal canvas (no
// Begin/Commit here - the single Commit stays at the END of DrawSettingsOverlay).
// ONE hit-zone over the whole rect : the existing cycle dispatch stays unchanged.
// A [-] value [+] stepper. id_base+"_dn" / id_base+"_up" are the click targets.
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
            // v2.02.04 : real Instant tiers = 2 / 5 / 10 / 15 / 25 K (JR's account is a
            // 2000) - 2K/10K were missing so the size stepper could never reach them and
            // SnapSizeToPlan EJECTED a 2000 to 5000. 50K kept for legacy tolerance.
            ArrayResize(out, 6);
            out[0]=2000; out[1]=5000; out[2]=10000; out[3]=15000; out[4]=25000; out[5]=50000;
            return 6;
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
    if (n > 0) { g_eff_size = s[0]; GVSetLogin("RC_size", g_eff_size); } // v2.13 C : per-login
}
// V1.27 fix : keep the phase legal for the plan. Only Stellar Instant uses the
// INSTANT phase (3) ; every other plan (esp. FTMO, which has no Instant profile)
// must fold INSTANT -> FUNDED, else Resolve silently falls back to a default
// profile and the panel shows the wrong rule-set with no warning.
void SnapPhaseToPlan(const ENUM_FN_PLAN p) {
    if (p == FN_PLAN_STELLAR_INSTANT)  g_eff_phase = 3; // INSTANT (single-phase)
    else if (g_eff_phase == 3)         g_eff_phase = 2; // INSTANT -> FUNDED
    GVSetLogin("RC_phase", (double)g_eff_phase); // v2.13 C : per-login
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
// v2.02 MULTI-THEMES : display name + tooltip key of a brand palette. The names
// are BRAND names (same in every language) ; the taglines go through Tr().

// Phase 4 (B) : remove every settings-modal object (all "RC_set_*") WITHOUT touching the
// base panel or its canvas. The title-bar gear glyph is "RC_gearlbl" (renamed off the
// "set_" prefix), so it is never caught here. Used by the light tab-switch re-render.


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
    LoadOrSeedPeakBalance(); // v2.02.05 : self-heal a poisoned first seed after a size/plan change
    DestroyAllObjects();
    // v3 SHELL : DestroyAllObjects wipes the WHOLE "RC_" namespace - the shell's
    // canvases included (RC_V3_*). Recreate them here or the rail would vanish
    // until the next chart change (seen on the lock -> clear transition).
    if (g_shell.Created()) g_shell.OnChartChange();
    // V1.29 S : CHART elements live on the price area (NOT the panel), so a popup
    // change must reflect on them IMMEDIATELY - refresh them ALWAYS (no modal
    // bleed-through, they're off-panel). Only RefreshPanel (the panel rows) stays
    // gated on !g_settings_open (drawing rows over the open modal = bleed-through).
    RefreshNewsZones();                     // news bars + level toggles : instant
    RefreshSlLines();                       // SL/TP recommendation lines
    if (g_be_visible) DrawBreakevenLines(); // basket BE line
    ApplyComfortScale(false);               // comfort padding (self-guards on g_eff_comfort)
    g_news_stats_scan = 0;                  // V1.29 : bust the news-card 60 s cache -> a cycle-date (or any) popup change recomputes the card instantly
    RefreshPanel();
    ChartRedraw(0);
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
// v3.06 : the advisor is now BUILT (text + status) instead of writing a
// legacy label. Both the shell (POSITIONS section) and the old footer line
// consume the same string : one computation, no drift.
bool BuildPyramidLine(string &line, int &stat) {
    line = ""; stat = 2;

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
        } else if ((type == POSITION_TYPE_BUY && sl >= entry) ||
                   (type != POSITION_TYPE_BUY && sl <= entry)) {
            // Phase 3.5 : this leg's SL locks profit (favorable side) -> zero downside
            // risk -> ignore it when picking the basket's worst loss-side anchor SL, so
            // the planner never advises moving a stop that would UNLOCK locked profit.
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
        line = "Pas de position sur " + sym;
        stat = 2;
        return false;
    }
    if (mixed) {
        line = "Panier couvert (BUY+SELL) : non gere";
        stat = 1;
        return true;
    }
    if (any_missing_sl || worst_sl_dist <= 0.0) {
        // Phase 3.5 : worst_sl_dist==0 with all SLs present = every leg's SL locks profit
        // (risk-free basket) ; only truly-missing SLs warrant the "place SL" warning.
        line = any_missing_sl ? "Place un SL sur toutes les positions avant de planifier"
                   : "Panier sans risque : les SL verrouillent du profit";
        stat = (any_missing_sl ? 1 : 0);
        return true;
    }
    if (sum_vol <= 0.0) {
        line = "Volume du panier = 0";
        stat = 2;
        return false;
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
        line = step.info;
        stat = 1;
        return true;
    }

    const int pld = LotDigits(sym);  // B-LOTPRECISION
    StringConcatenate(line,
                      "Si px ", (is_buy ? ">=" : "<="), " ",
                      DoubleToString(step.trigger_price, _Digits),
                      " add ", DoubleToString(step.add_lot, pld),
                      " lot et deplace TOUS les SL -> ", DoubleToString(step.new_unified_stop, _Digits),
                      " = verrouille ",
                      (step.worst_case_money >= 0.0 ? "min +$" : "perte -$"),
                      DoubleToString(MathAbs(step.worst_case_money), 2),
                      "  [panier ", DoubleToString(sum_vol, pld),
                      " @", DoubleToString(anchor_entry, _Digits), "]");
    stat = (step.worst_case_money >= 0.0 ? 0 : 1);
    return true;
}

//+------------------------------------------------------------------+
