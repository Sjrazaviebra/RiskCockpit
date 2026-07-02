//+------------------------------------------------------------------+
//|                                  CChallengeProfileCatalog.mqh    |
//|                                              JR Trading - 2026   |
//|                                                                  |
//|  Hardcoded FundedNext rule profile catalog for the               |
//|  RiskCockpit Indicator. NO external JSON: every                  |
//|  (plan x phase) combination + add-on modifiers is baked into     |
//|  the .ex5 so the user only picks dropdowns / toggles.            |
//|                                                                  |
//|  Coverage                                                        |
//|  --------                                                        |
//|  CFD (MT5):                                                      |
//|    - Stellar 1-Step    (Challenge + Funded)                      |
//|    - Stellar 2-Step    (P1 + P2 + Funded)                        |
//|    - Stellar Lite      (P1 + P2 + Funded)   <- 2-step variant    |
//|    - Stellar Instant   (single-phase funded, 5% to payout)       |
//|  Futures (NOT MT5, listed but Helper non-operational):           |
//|    - Bolt / Rapid / Legacy                                       |
//|                                                                  |
//|  Add-on modifiers supported (CFD only):                          |
//|    - Lifetime Payout 95 %                                        |
//|    - No Minimum Trading Days                                     |
//|    - Swap-Free                                                   |
//|    - 10 % Total Loss Limit (Stellar Lite only)                   |
//|    - Double Up (allocation cap doubled - no rule-constant impact)|
//|    - Bi-Weekly Reward (first payout 21d -> 14d; Lite confirmed,  |
//|      2-Step UNVERIFIED)                                          |
//|                                                                  |
//|  Sources (catalog snapshot 2026-05-11)                           |
//|  ---------------------------------------                         |
//|    help.fundednext.com/en/articles/8021061   Stellar 1-Step      |
//|    help.fundednext.com/en/articles/8021076   Stellar 2-Step      |
//|    help.fundednext.com/en/articles/9094072   Stellar Lite        |
//|    help.fundednext.com/en/articles/11641614  Stellar Instant     |
//|    help.fundednext.com/en/articles/8020351   Prohibited strats   |
//|    help.fundednext.com/en/articles/10816539  Margin / Gambling   |
//|    help.fundednext.com/en/articles/12840751  3 % Open-Risk Rule  |
//|    help.fundednext.com/en/articles/10256545  1 % Risk escalation |
//|    help.fundednext.com/en/articles/11982271  HFT policy          |
//|    help.fundednext.com/en/articles/11982604  Tick-scalping       |
//|                                                                  |
//|  Color literals MUST use the hex form ((color)0x00BBGGRR) - the  |
//|  clang-format auto-formatter active on this workspace breaks the |
//|  C'r,g,b' apostrophe syntax (lesson learned on FFD Pro).         |
//+------------------------------------------------------------------+
#ifndef __CCHALLENGEPROFILECATALOG_MQH__
#define __CCHALLENGEPROFILECATALOG_MQH__

//+------------------------------------------------------------------+
//| Enums - user-facing input dropdowns                              |
//+------------------------------------------------------------------+
enum ENUM_FN_PLAN
  {
   FN_PLAN_STELLAR_1STEP   = 0,   // Stellar 1-Step CFD
   FN_PLAN_STELLAR_2STEP   = 1,   // Stellar 2-Step CFD
   FN_PLAN_STELLAR_LITE    = 2,   // Stellar Lite CFD (2-step)
   FN_PLAN_STELLAR_INSTANT = 3,   // Stellar Instant CFD (no challenge)
   FN_PLAN_FUTURES_BOLT    = 4,   // Futures Bolt   (NOT MT5)
   FN_PLAN_FUTURES_RAPID   = 5,   // Futures Rapid  (NOT MT5)
   FN_PLAN_FUTURES_LEGACY  = 6,   // Futures Legacy (NOT MT5)
   FN_PLAN_FREE_TRIAL      = 7,   // Free Trial (demo, 6K-200K, 5% target, 14d)
   FN_PLAN_FREE_COMPETITION = 8,  // Free Monthly Competition (demo, leaderboard, ~30d)
   // LOT 5 : multi-firm presets. FTMO 2-Step = full rules (JR's primary
   // external firm). E8 / The5ers / MyFundedFX = stubs (placeholder rules,
   // refinement planned for V1.2 when the in-panel firm switcher ships).
   FN_PLAN_FTMO_2STEP       = 9,  // FTMO Challenge -> Verification -> Funded
   FN_PLAN_E8_8PCT          = 10, // E8 Funding 8% account (stub)
   FN_PLAN_THE5ERS_HIGH     = 11, // The5ers HFT / High-Stakes (stub)
   FN_PLAN_MFF_RAPID        = 12, // MyFundedFX Rapid (stub)
   // B-AVATRADE-PROFILE : compte PERSO (AvaTrade, broker quelconque). Aucune
   // regle prop n'est imposee, les meters s'effacent (N/A ou cap inatteignable).
   // Enabler du test week-end de JR sur demo AvaTrade crypto.
   FN_PLAN_PERSONAL         = 13  // Personal account (no prop rules)
  };

enum ENUM_FN_PHASE
  {
   FN_PHASE_CHALLENGE_P1 = 0,     // 1-Step challenge OR P1 of 2-step
   FN_PHASE_CHALLENGE_P2 = 1,     // P2 of 2-step
   FN_PHASE_FUNDED       = 2,     // post-challenge funded account
   FN_PHASE_INSTANT      = 3      // Stellar Instant direct-funded
  };

enum ENUM_FN_ACCOUNT_TYPE
  {
   FN_ACCOUNT_SWAP      = 0,      // standard swap-charged
   FN_ACCOUNT_SWAP_FREE = 1       // Islamic / swap-free
  };

// Bitmask flags for add-ons (combine via |)
#define FN_ADDON_NONE          0
#define FN_ADDON_LIFETIME_95   (1<<0)
#define FN_ADDON_NO_MIN_DAYS   (1<<1)
#define FN_ADDON_SWAP_FREE     (1<<2)
#define FN_ADDON_10PCT_DD      (1<<3)   // Stellar Lite only per official
#define FN_ADDON_DOUBLE_UP     (1<<4)
#define FN_ADDON_BI_WEEKLY     (1<<5)   // 2-Step + Lite only (NOT 1-Step) - audit 2026-05-20
#define FN_ADDON_150_REWARD    (1<<6)   // 150% Reward : 1-Step + 2-Step only - audit 2026-05-20

//+------------------------------------------------------------------+
//| ChallengeProfile - one resolved rule profile                     |
//|                                                                  |
//| All money fields are derived from initial_balance x pct fields   |
//| at runtime; the catalog only stores pct/seconds/leverage etc.    |
//+------------------------------------------------------------------+
struct ChallengeProfile
  {
   // Identification
   string               profile_id;        // "fundednext.stellar_lite_2step.funded.25k"
   string               vendor;            // "FundedNext"
   string               model;             // "Stellar Lite 2-Step"
   string               phase;             // "challenge_p1" | "challenge_p2" | "funded" | "instant"
   ENUM_FN_PLAN         plan_id;
   ENUM_FN_PHASE        phase_id;
   bool                 supported_on_mt5;  // false for the Futures placeholders

   // Account
   double               initial_balance;   // USD - filled at Resolve() time
   ENUM_FN_ACCOUNT_TYPE account_type;
   bool                 swap_charged;      // false if SWAP_FREE account or SWAP_FREE add-on

   // Targets
   double               profit_target_pct; // 0 = no target (funded phase)

   // Drawdown
   double               daily_loss_pct;        // 0 = no daily-loss rule (Instant)
   bool                 daily_loss_static;     // true = based on initial_balance
   double               max_loss_pct;
   bool                 max_loss_trailing;     // true = EOD trailing (Instant + Futures)

   // Trading days
   int                  min_trading_days;
   int                  min_trades_per_day;

   // Consistency rule (Futures, optional)
   double               consistency_pct;       // 0 = no rule (CFD)

   // Holding rules
   bool                 weekend_hold_allowed;
   bool                 overnight_hold_allowed;

   // News rule
   bool                 news_rule_applies;
   int                  news_window_minutes;
   double               news_profit_share_pct; // 40 = 40 % of profit kept

   // Open-risk + mandatory SL (funded CFD only)
   bool                 open_risk_rule_applies;
   double               open_risk_max_cumulative_pct;
   int                  mandatory_sl_minutes;

   // Margin
   double               margin_max_cumulative_pct;
   double               margin_recommended_per_trade_min_pct;
   double               margin_recommended_per_trade_max_pct;

   // Quick Strike
   int                  quick_strike_seconds;
   double               quick_strike_warn_pct;
   double               quick_strike_violate_pct;

   // Hyperactivity
   int                  hyperactivity_trades_per_day;
   int                  hyperactivity_msgs_per_day;
   int                  hyperactivity_force_disable_msgs;

   // Leverage by asset class
   int                  leverage_fx;
   int                  leverage_metals;
   int                  leverage_indices;
   int                  leverage_energies;
   int                  leverage_crypto;

   // Payout
   double               profit_split_pct;
   int                  first_payout_business_days;
   int                  subsequent_payout_business_days;

   // Diagnostics
   bool                 is_default_fallback;
  };

//+------------------------------------------------------------------+
//| CChallengeProfileCatalog                                         |
//+------------------------------------------------------------------+
class CChallengeProfileCatalog
  {
private:
   ChallengeProfile  m_profiles[];
   bool              m_initialized;

   // Base profile builders
   void              AddProfile(const ChallengeProfile &p);
   void              BuildBaseProfiles(void);
   void              BuildStellar1Step(const ENUM_FN_PHASE phase, ChallengeProfile &p) const;
   void              BuildStellar2Step(const ENUM_FN_PHASE phase, ChallengeProfile &p) const;
   void              BuildStellarLite (const ENUM_FN_PHASE phase, ChallengeProfile &p) const;
   void              BuildStellarInstant(ChallengeProfile &p) const;
   void              BuildFuturesPlaceholder(const ENUM_FN_PLAN plan, ChallengeProfile &p) const;
   void              BuildFreeTrial(ChallengeProfile &p) const;        // demo free trial
   void              BuildFreeCompetition(ChallengeProfile &p) const;  // demo monthly competition
   // LOT 5 : multi-firm presets (FTMO full, others stub).
   void              BuildFTMO2Step(const ENUM_FN_PHASE phase, ChallengeProfile &p) const;
   void              BuildE8(ChallengeProfile &p) const;
   void              BuildThe5ers(ChallengeProfile &p) const;
   void              BuildMyFundedFX(ChallengeProfile &p) const;
   void              BuildPersonal(ChallengeProfile &p) const; // B-AVATRADE-PROFILE : compte perso sans regles prop
   void              FillCommonProhibitedRules(ChallengeProfile &p) const;

   // Resolve helpers
   bool              MatchesBase(const ChallengeProfile &p,
                                 const ENUM_FN_PLAN plan,
                                 const ENUM_FN_PHASE phase) const;
   void              ApplyAddons(ChallengeProfile &p,
                                 const int addons_mask) const;
   string            FormatProfileId(const ENUM_FN_PLAN plan,
                                     const ENUM_FN_PHASE phase,
                                     const double size,
                                     const int addons_mask) const;
   string            PlanSlug (const ENUM_FN_PLAN plan)  const;
   string            PhaseSlug(const ENUM_FN_PHASE phase) const;
   string            SizeSlug (const double size)        const;
   string            PhaseLabel(const ENUM_FN_PHASE phase) const;

public:
   // ModelLabel public : utilisé par le popup reglages (settings overlay) de RiskCockpit.mq5
   string            ModelLabel(const ENUM_FN_PLAN plan) const;
                     CChallengeProfileCatalog(void);
                    ~CChallengeProfileCatalog(void);

   void              Init(void);
   int               Count(void) const { return ArraySize(m_profiles); }

   bool              Resolve(const ENUM_FN_PLAN plan,
                             const ENUM_FN_PHASE phase,
                             const double size,
                             const ENUM_FN_ACCOUNT_TYPE account_type,
                             const int addons_mask,
                             ChallengeProfile &out_profile);

   ChallengeProfile  GetDefault(void) const;

   string            DescribeAddons(const int addons_mask) const;

   // Cascade (audit 2026-05-20) : bitmask of add-ons actually valid for a plan.
   // A type-incompatible add-on the user ticked is dropped at Resolve time.
   int               ValidAddonsMask(const ENUM_FN_PLAN plan) const;
  };

//+------------------------------------------------------------------+
//| Ctor / Dtor                                                      |
//+------------------------------------------------------------------+
CChallengeProfileCatalog::CChallengeProfileCatalog(void) : m_initialized(false)
  {
   ArrayResize(m_profiles, 0);
  }

CChallengeProfileCatalog::~CChallengeProfileCatalog(void)
  {
  }

//+------------------------------------------------------------------+
//| Init                                                             |
//+------------------------------------------------------------------+
void CChallengeProfileCatalog::Init(void)
  {
   if(m_initialized)
      return;
   ArrayResize(m_profiles, 0);
   BuildBaseProfiles();
   m_initialized = true;
  }

void CChallengeProfileCatalog::AddProfile(const ChallengeProfile &p)
  {
   const int n = ArraySize(m_profiles);
   ArrayResize(m_profiles, n + 1);
   m_profiles[n] = p;
  }

void CChallengeProfileCatalog::BuildBaseProfiles(void)
  {
   ChallengeProfile p;

   // ----- Stellar 1-Step -----
   BuildStellar1Step(FN_PHASE_CHALLENGE_P1, p); AddProfile(p);
   BuildStellar1Step(FN_PHASE_FUNDED,       p); AddProfile(p);

   // ----- Stellar 2-Step -----
   BuildStellar2Step(FN_PHASE_CHALLENGE_P1, p); AddProfile(p);
   BuildStellar2Step(FN_PHASE_CHALLENGE_P2, p); AddProfile(p);
   BuildStellar2Step(FN_PHASE_FUNDED,       p); AddProfile(p);

   // ----- Stellar Lite (2-step) -----
   BuildStellarLite (FN_PHASE_CHALLENGE_P1, p); AddProfile(p);
   BuildStellarLite (FN_PHASE_CHALLENGE_P2, p); AddProfile(p);
   BuildStellarLite (FN_PHASE_FUNDED,       p); AddProfile(p);

   // ----- Stellar Instant -----
   BuildStellarInstant(p); AddProfile(p);

   // ----- Free products (demo) -----
   BuildFreeTrial(p);       AddProfile(p);
   BuildFreeCompetition(p); AddProfile(p);

   // ----- Futures placeholders (not MT5-operational) -----
   BuildFuturesPlaceholder(FN_PLAN_FUTURES_BOLT,   p); AddProfile(p);
   BuildFuturesPlaceholder(FN_PLAN_FUTURES_RAPID,  p); AddProfile(p);
   BuildFuturesPlaceholder(FN_PLAN_FUTURES_LEGACY, p); AddProfile(p);

   // LOT 5 : multi-firm presets.
   BuildFTMO2Step(FN_PHASE_CHALLENGE_P1, p); AddProfile(p);
   BuildFTMO2Step(FN_PHASE_CHALLENGE_P2, p); AddProfile(p);
   BuildFTMO2Step(FN_PHASE_FUNDED,       p); AddProfile(p);
   BuildE8(p);          AddProfile(p);
   BuildThe5ers(p);     AddProfile(p);
   BuildMyFundedFX(p);  AddProfile(p);
   // B-AVATRADE-PROFILE : profile generique perso (AvaTrade + autres brokers).
   BuildPersonal(p);    AddProfile(p);
  }

//+------------------------------------------------------------------+
//| Common prohibited-strategy rule values (shared across all CFD)   |
//+------------------------------------------------------------------+
void CChallengeProfileCatalog::FillCommonProhibitedRules(ChallengeProfile &p) const
  {
   // Margin / gambling rule (help.fundednext.com/en/articles/10816539)
   p.margin_max_cumulative_pct            = 70.0;
   p.margin_recommended_per_trade_min_pct = 20.0;
   p.margin_recommended_per_trade_max_pct = 30.0;

   // Quick Strike (help.fundednext.com/en/articles/8020351)
   p.quick_strike_seconds      = 30;
   p.quick_strike_warn_pct     = 20.0;
   p.quick_strike_violate_pct  = 30.0;

   // Hyperactivity thresholds
   p.hyperactivity_trades_per_day       = 200;
   p.hyperactivity_msgs_per_day         = 2000;
   p.hyperactivity_force_disable_msgs   = 15000;
  }

//+------------------------------------------------------------------+
//| Stellar 1-Step                                                   |
//+------------------------------------------------------------------+
void CChallengeProfileCatalog::BuildStellar1Step(const ENUM_FN_PHASE phase, ChallengeProfile &p) const
  {
   // Reset
   p.profile_id            = "fundednext.stellar_1step.base." + PhaseSlug(phase);
   p.vendor                = "FundedNext";
   p.model                 = "Stellar 1-Step";
   p.phase                 = PhaseSlug(phase);
   p.plan_id               = FN_PLAN_STELLAR_1STEP;
   p.phase_id              = (phase == FN_PHASE_CHALLENGE_P2) ? FN_PHASE_CHALLENGE_P1 : phase;
   p.supported_on_mt5      = true;
   p.initial_balance       = 0.0;                       // filled in Resolve()
   p.account_type          = FN_ACCOUNT_SWAP;
   p.swap_charged          = true;
   p.consistency_pct       = 0.0;

   // Drawdown - same across phases for 1-Step
   p.daily_loss_pct        = 3.0;
   p.daily_loss_static     = true;
   p.max_loss_pct          = 6.0;
   p.max_loss_trailing     = false;

   // Phase-dependent rules
   if(phase == FN_PHASE_CHALLENGE_P1)
     {
      p.profit_target_pct          = 10.0;
      p.min_trading_days           = 2;
      p.min_trades_per_day         = 1;
      p.weekend_hold_allowed       = true;
      p.overnight_hold_allowed     = true;
      p.news_rule_applies          = false;            // funded only per official
      p.open_risk_rule_applies     = false;            // funded only
      p.mandatory_sl_minutes       = 0;
     }
   else // FUNDED
     {
      p.profit_target_pct          = 0.0;              // no target on funded
      p.min_trading_days           = 0;
      p.min_trades_per_day         = 0;
      p.weekend_hold_allowed       = false;
      p.overnight_hold_allowed     = true;
      p.news_rule_applies          = true;
      p.open_risk_rule_applies     = true;
      p.mandatory_sl_minutes       = 3;
     }

   p.news_window_minutes               = 5;
   p.news_profit_share_pct             = 40.0;
   p.open_risk_max_cumulative_pct      = 3.0;

   // Leverage (2026 cuts: FX down from 1:100 to 1:30 on 1-Step)
   p.leverage_fx       = 30;
   p.leverage_metals   = 10;
   p.leverage_indices  = 5;
   p.leverage_energies = 5;
   p.leverage_crypto   = 1;

   // Payout - 1-Step is the shortest cadence (5 business days)
   p.profit_split_pct                = 80.0;
   p.first_payout_business_days      = 5;
   p.subsequent_payout_business_days = 5;

   p.is_default_fallback = false;
   FillCommonProhibitedRules(p);
  }

//+------------------------------------------------------------------+
//| Stellar 2-Step                                                   |
//+------------------------------------------------------------------+
void CChallengeProfileCatalog::BuildStellar2Step(const ENUM_FN_PHASE phase, ChallengeProfile &p) const
  {
   p.profile_id            = "fundednext.stellar_2step.base." + PhaseSlug(phase);
   p.vendor                = "FundedNext";
   p.model                 = "Stellar 2-Step";
   p.phase                 = PhaseSlug(phase);
   p.plan_id               = FN_PLAN_STELLAR_2STEP;
   p.phase_id              = phase;
   p.supported_on_mt5      = true;
   p.initial_balance       = 0.0;
   p.account_type          = FN_ACCOUNT_SWAP;
   p.swap_charged          = true;
   p.consistency_pct       = 0.0;

   // Drawdown - same across phases
   p.daily_loss_pct        = 5.0;
   p.daily_loss_static     = true;
   p.max_loss_pct          = 10.0;
   p.max_loss_trailing     = false;

   if(phase == FN_PHASE_CHALLENGE_P1)
     {
      p.profit_target_pct          = 8.0;
      p.min_trading_days           = 5;
      p.min_trades_per_day         = 0;
      p.weekend_hold_allowed       = true;
      p.overnight_hold_allowed     = true;
      p.news_rule_applies          = false;
      p.open_risk_rule_applies     = false;
      p.mandatory_sl_minutes       = 0;
     }
   else if(phase == FN_PHASE_CHALLENGE_P2)
     {
      p.profit_target_pct          = 5.0;
      p.min_trading_days           = 5;
      p.min_trades_per_day         = 0;
      p.weekend_hold_allowed       = true;
      p.overnight_hold_allowed     = true;
      p.news_rule_applies          = false;
      p.open_risk_rule_applies     = false;
      p.mandatory_sl_minutes       = 0;
     }
   else // FUNDED
     {
      p.profit_target_pct          = 0.0;
      p.min_trading_days           = 0;
      p.min_trades_per_day         = 0;
      p.weekend_hold_allowed       = false;
      p.overnight_hold_allowed     = true;
      p.news_rule_applies          = true;
      p.open_risk_rule_applies     = true;
      p.mandatory_sl_minutes       = 3;
     }

   p.news_window_minutes          = 5;
   p.news_profit_share_pct        = 40.0;
   p.open_risk_max_cumulative_pct = 3.0;

   // Leverage (2026 metals cuts on 2-Step: 1:10 since Jan 2026)
   p.leverage_fx       = 100;   // [UNVERIFIED - some sources cite 1:30; default 100 + EA override]
   p.leverage_metals   = 10;
   p.leverage_indices  = 5;     // 1:5 temporary per FundedNext 2026 cuts
   p.leverage_energies = 10;
   p.leverage_crypto   = 1;

   // Payout
   p.profit_split_pct                = 80.0;
   p.first_payout_business_days      = 21;
   p.subsequent_payout_business_days = 14;

   p.is_default_fallback = false;
   FillCommonProhibitedRules(p);
  }

//+------------------------------------------------------------------+
//| Stellar Lite (2-step variant)                                    |
//+------------------------------------------------------------------+
void CChallengeProfileCatalog::BuildStellarLite(const ENUM_FN_PHASE phase, ChallengeProfile &p) const
  {
   p.profile_id            = "fundednext.stellar_lite_2step.base." + PhaseSlug(phase);
   p.vendor                = "FundedNext";
   p.model                 = "Stellar Lite 2-Step";
   p.phase                 = PhaseSlug(phase);
   p.plan_id               = FN_PLAN_STELLAR_LITE;
   p.phase_id              = phase;
   p.supported_on_mt5      = true;
   p.initial_balance       = 0.0;
   p.account_type          = FN_ACCOUNT_SWAP;
   p.swap_charged          = true;
   p.consistency_pct       = 0.0;

   // Drawdown - same across phases
   p.daily_loss_pct        = 4.0;
   p.daily_loss_static     = true;
   p.max_loss_pct          = 8.0;
   p.max_loss_trailing     = false;

   if(phase == FN_PHASE_CHALLENGE_P1)
     {
      p.profit_target_pct          = 8.0;
      p.min_trading_days           = 5;
      p.min_trades_per_day         = 0;
      p.weekend_hold_allowed       = true;
      p.overnight_hold_allowed     = true;
      p.news_rule_applies          = false;
      p.open_risk_rule_applies     = false;
      p.mandatory_sl_minutes       = 0;
     }
   else if(phase == FN_PHASE_CHALLENGE_P2)
     {
      p.profit_target_pct          = 4.0;
      p.min_trading_days           = 5;
      p.min_trades_per_day         = 0;
      p.weekend_hold_allowed       = true;
      p.overnight_hold_allowed     = true;
      p.news_rule_applies          = false;
      p.open_risk_rule_applies     = false;
      p.mandatory_sl_minutes       = 0;
     }
   else // FUNDED  <-- user's active account base sits here
     {
      p.profit_target_pct          = 0.0;
      p.min_trading_days           = 0;
      p.min_trades_per_day         = 0;
      p.weekend_hold_allowed       = false;
      p.overnight_hold_allowed     = true;
      p.news_rule_applies          = true;
      p.open_risk_rule_applies     = true;
      p.mandatory_sl_minutes       = 3;
     }

   p.news_window_minutes          = 5;
   p.news_profit_share_pct        = 40.0;
   p.open_risk_max_cumulative_pct = 3.0;

   // Leverage (Lite keeps better metals 1:30, FX 1:100, energies 1:10)
   p.leverage_fx       = 100;
   p.leverage_metals   = 30;
   p.leverage_indices  = 5;
   p.leverage_energies = 10;
   p.leverage_crypto   = 1;

   // Payout
   p.profit_split_pct                = 80.0;
   p.first_payout_business_days      = 21;
   p.subsequent_payout_business_days = 14;

   p.is_default_fallback = false;
   FillCommonProhibitedRules(p);
  }

//+------------------------------------------------------------------+
//| Stellar Instant (direct-funded, 5% to payout)                    |
//+------------------------------------------------------------------+
void CChallengeProfileCatalog::BuildStellarInstant(ChallengeProfile &p) const
  {
   p.profile_id            = "fundednext.stellar_instant.base.instant";
   p.vendor                = "FundedNext";
   p.model                 = "Stellar Instant";
   p.phase                 = "instant";
   p.plan_id               = FN_PLAN_STELLAR_INSTANT;
   p.phase_id              = FN_PHASE_INSTANT;
   p.supported_on_mt5      = true;
   p.initial_balance       = 0.0;
   p.account_type          = FN_ACCOUNT_SWAP;
   p.swap_charged          = true;
   p.consistency_pct       = 0.0;

   // Targets / drawdown
   p.profit_target_pct     = 5.0;            // to first payout
   p.daily_loss_pct        = 0.0;            // none
   p.daily_loss_static     = false;
   p.max_loss_pct          = 6.0;
   p.max_loss_trailing     = true;           // EOD trailing

   // Trading days
   p.min_trading_days      = 0;
   p.min_trades_per_day    = 0;

   // Holding
   p.weekend_hold_allowed  = true;
   p.overnight_hold_allowed = true;

   // News rule always applies on Instant (40 % profit kept)
   p.news_rule_applies     = true;
   p.news_window_minutes   = 5;
   p.news_profit_share_pct = 40.0;

   // Instant does not enforce the funded-CFD open-risk + 3-min SL rules.
   // The Helper will keep the rule "recommended" rather than blocking.
   p.open_risk_rule_applies       = false;
   p.open_risk_max_cumulative_pct = 3.0;     // recommended
   p.mandatory_sl_minutes         = 0;       // recommended only

   // Leverage (Instant: FX 1:30 to 1:50, metals 1:30, indices 1:5, crypto 1:1)
   p.leverage_fx       = 30;                 // conservative end of advertised range
   p.leverage_metals   = 30;
   p.leverage_indices  = 5;
   p.leverage_energies = 0;                  // n/a
   p.leverage_crypto   = 1;

   // Payout - on-demand 5 % growth or 14 days, then 14
   p.profit_split_pct                = 70.0; // base, scales to 80 with scaling
   p.first_payout_business_days      = 14;
   p.subsequent_payout_business_days = 14;

   p.is_default_fallback = false;
   FillCommonProhibitedRules(p);
  }

//+------------------------------------------------------------------+
//| Free Trial (demo, 6K-200K, 5% target, 14 days) - audit 2026-05-21|
//| Reward = 5% CFD-plan discount coupon, NO funded payout.          |
//+------------------------------------------------------------------+
void CChallengeProfileCatalog::BuildFreeTrial(ChallengeProfile &p) const
  {
   p.profile_id            = "fundednext.free_trial.base.funded";
   p.vendor                = "FundedNext";
   p.model                 = "Free Trial";
   p.phase                 = "funded";
   p.plan_id               = FN_PLAN_FREE_TRIAL;
   p.phase_id              = FN_PHASE_FUNDED;
   p.supported_on_mt5      = true;
   p.initial_balance       = 0.0;
   p.account_type          = FN_ACCOUNT_SWAP;
   p.swap_charged          = false;          // demo
   p.consistency_pct       = 0.0;

   p.profit_target_pct     = 5.0;
   p.daily_loss_pct        = 5.0;
   p.daily_loss_static     = true;
   p.max_loss_pct          = 10.0;
   p.max_loss_trailing     = false;

   p.min_trading_days      = 3;
   p.min_trades_per_day    = 0;

   p.weekend_hold_allowed   = true;
   p.overnight_hold_allowed = true;

   // Demo / evaluation : no prop-firm news, open-risk or 3-min SL rules.
   p.news_rule_applies            = false;
   p.news_window_minutes          = 5;
   p.news_profit_share_pct        = 100.0;
   p.open_risk_rule_applies       = false;
   p.open_risk_max_cumulative_pct = 3.0;     // recommended only
   p.mandatory_sl_minutes         = 0;

   p.leverage_fx       = 100;
   p.leverage_metals   = 30;
   p.leverage_indices  = 30;
   p.leverage_energies = 30;
   p.leverage_crypto   = 1;

   // No payout (reward = discount coupon).
   p.profit_split_pct                = 0.0;
   p.first_payout_business_days      = 0;
   p.subsequent_payout_business_days = 0;

   p.is_default_fallback = false;
   FillCommonProhibitedRules(p);
  }

//+------------------------------------------------------------------+
//| Free Monthly Competition (demo, leaderboard, ~30 days)           |
//| Reward = prizes/lottery (cash + Stellar Instant accounts).       |
//+------------------------------------------------------------------+
void CChallengeProfileCatalog::BuildFreeCompetition(ChallengeProfile &p) const
  {
   p.profile_id            = "fundednext.free_competition.base.funded";
   p.vendor                = "FundedNext";
   p.model                 = "Free Competition";
   p.phase                 = "funded";
   p.plan_id               = FN_PLAN_FREE_COMPETITION;
   p.phase_id              = FN_PHASE_FUNDED;
   p.supported_on_mt5      = true;
   p.initial_balance       = 0.0;
   p.account_type          = FN_ACCOUNT_SWAP;
   p.swap_charged          = false;          // demo
   p.consistency_pct       = 0.0;

   p.profit_target_pct     = 0.0;            // leaderboard - no pass/fail target
   p.daily_loss_pct        = 5.0;            // includes floating loss
   p.daily_loss_static     = true;
   p.max_loss_pct          = 10.0;
   p.max_loss_trailing     = false;

   p.min_trading_days      = 5;
   p.min_trades_per_day    = 0;

   p.weekend_hold_allowed   = true;
   p.overnight_hold_allowed = true;

   p.news_rule_applies            = false;   // news trading allowed in competition
   p.news_window_minutes          = 5;
   p.news_profit_share_pct        = 100.0;
   p.open_risk_rule_applies       = false;
   p.open_risk_max_cumulative_pct = 3.0;     // recommended only
   p.mandatory_sl_minutes         = 0;

   p.leverage_fx       = 100;                // 1:100 FX
   p.leverage_metals   = 30;
   p.leverage_indices  = 30;                 // 1:30 indices/commodities
   p.leverage_energies = 30;
   p.leverage_crypto   = 1;

   p.profit_split_pct                = 0.0;  // prizes, not a profit split
   p.first_payout_business_days      = 0;
   p.subsequent_payout_business_days = 0;

   p.is_default_fallback = false;
   FillCommonProhibitedRules(p);
   // Competition-specific hard caps : max 5 open positions, 50 trades / day.
   p.hyperactivity_trades_per_day = 50;
  }

//+------------------------------------------------------------------+
//| LOT 5 : FTMO 2-Step preset (Challenge -> Verification -> Funded). |
//| Full rules per FTMO website mid-2024 ; verify on dashboard.       |
//| JR's primary external firm. Sizes : $10K / $25K / $50K / $100K /  |
//| $200K (no $5K / $6K like FN).                                     |
//+------------------------------------------------------------------+
void CChallengeProfileCatalog::BuildFTMO2Step(const ENUM_FN_PHASE phase, ChallengeProfile &p) const
  {
   p.profile_id            = "ftmo.2step.base." + PhaseSlug(phase);
   p.vendor                = "FTMO";
   p.model                 = "FTMO 2-Step";
   p.phase                 = PhaseSlug(phase);
   p.plan_id               = FN_PLAN_FTMO_2STEP;
   p.phase_id              = phase;
   p.supported_on_mt5      = true;
   p.initial_balance       = 0.0;
   p.account_type          = FN_ACCOUNT_SWAP;
   p.swap_charged          = true;
   // FTMO funded asks the highest day not to dominate total profit
   // (~50 % guideline ; not always hard-enforced).
   p.consistency_pct       = (phase == FN_PHASE_FUNDED) ? 50.0 : 0.0;

   // Drawdown - same across phases.
   p.daily_loss_pct        = 5.0;
   p.daily_loss_static     = true;
   p.max_loss_pct          = 10.0;
   p.max_loss_trailing     = false;

   if(phase == FN_PHASE_CHALLENGE_P1)
      p.profit_target_pct  = 10.0;
   else if(phase == FN_PHASE_CHALLENGE_P2)
      p.profit_target_pct  = 5.0;
   else // FUNDED
      p.profit_target_pct  = 0.0;

   // LOT C : phase-specific FTMO Standard rules (Agent A research, 2024-2026).
   // Challenge / Verification : weekend + overnight allowed, news unrestricted.
   // Funded Standard : weekend + overnight BANNED, news +/- 2 min restriction
   // with profits VOIDED on the news trade. (Swing variant exempts both rules
   // but is not modelled here ; pick a different preset for Swing.)
   // AUDIT 2026-06-07 : FTMO REMOVED the minimum trading days rule. Older docs
   // listed 4 days on Challenge/Verification ; the current ruleset has it at 0
   // across all phases. Was harassing JR ("Days traded X/4" on the strip).
   p.min_trading_days          = 0;
   p.min_trades_per_day        = 0;
   p.weekend_hold_allowed      = (phase != FN_PHASE_FUNDED);
   p.overnight_hold_allowed    = (phase != FN_PHASE_FUNDED);
   p.news_rule_applies         = (phase == FN_PHASE_FUNDED);
   p.open_risk_rule_applies    = false; // no 3 % rule equivalent
   p.mandatory_sl_minutes      = 0;

   p.news_window_minutes          = (phase == FN_PHASE_FUNDED) ? 2 : 0;
   p.news_profit_share_pct        = 0.0; // funded : news trade profit VOIDED
   p.open_risk_max_cumulative_pct = 0.0;
   // FTMO has no explicit cumulative-margin cap -> 100 % = meter inactive.
   p.margin_max_cumulative_pct    = 100.0;

   p.leverage_fx       = 100;
   p.leverage_metals   = 30;
   p.leverage_indices  = 20;
   p.leverage_energies = 10;
   p.leverage_crypto   = 2;

   p.profit_split_pct                = 80.0;
   p.first_payout_business_days      = 30;
   p.subsequent_payout_business_days = 14;

   p.is_default_fallback = false;
   FillCommonProhibitedRules(p);
  }

//+------------------------------------------------------------------+
//| LOT C : E8 Markets "E8 Pro" preset (1-step funded, 8 % account).  |
//| Signature feature : NO daily loss limit. Consistency 40 % at      |
//| payout (funded only). News +/- 5 min ban on funded = profits      |
//| VOIDED. Per Agent B research (2024-2026, e8markets.com).          |
//+------------------------------------------------------------------+
void CChallengeProfileCatalog::BuildE8(ChallengeProfile &p) const
  {
   p.profile_id            = "e8.pro.1step.funded";
   p.vendor                = "E8 Markets";
   p.model                 = "E8 Pro (1-Step, 8% / no daily loss)";
   p.phase                 = "funded";
   p.plan_id               = FN_PLAN_E8_8PCT;
   p.phase_id              = FN_PHASE_FUNDED;
   p.supported_on_mt5      = true;
   p.initial_balance       = 0.0;
   p.account_type          = FN_ACCOUNT_SWAP;
   p.swap_charged          = true;
   p.consistency_pct       = 40.0; // funded payout gate

   p.daily_loss_pct        = 0.0;  // SIGNATURE : no daily loss on E8 Pro
   p.daily_loss_static     = true;
   p.max_loss_pct          = 8.0;
   p.max_loss_trailing     = false;

   p.profit_target_pct            = 0.0;
   p.min_trading_days             = 0;
   p.min_trades_per_day           = 0;
   p.weekend_hold_allowed         = true;
   p.overnight_hold_allowed       = true;
   p.news_rule_applies            = true;  // +/- 5 min ban on funded
   p.news_window_minutes          = 5;
   p.news_profit_share_pct        = 0.0;   // funded news : profits VOIDED
   p.open_risk_rule_applies       = false;
   p.open_risk_max_cumulative_pct = 0.0;
   p.mandatory_sl_minutes         = 0;
   p.margin_max_cumulative_pct    = 100.0;

   p.leverage_fx       = 30;
   p.leverage_metals   = 15;
   p.leverage_indices  = 15;
   p.leverage_energies = 10;
   p.leverage_crypto   = 2;  // BTC/ETH 1:5 not modelled separately

   p.profit_split_pct                = 80.0;
   p.first_payout_business_days      = 14;
   p.subsequent_payout_business_days = 14;

   p.is_default_fallback = false;
   FillCommonProhibitedRules(p);
  }

//+------------------------------------------------------------------+
//| LOT C : The5ers "High-Stakes" preset (2-step funded). Static max  |
//| loss (NEVER trails), FX leverage 1:100 (differentiator), profit   |
//| cycles every 14 days instead of free payouts. Per Agent B (2024). |
//+------------------------------------------------------------------+
void CChallengeProfileCatalog::BuildThe5ers(ChallengeProfile &p) const
  {
   p.profile_id            = "the5ers.high_stakes.funded";
   p.vendor                = "The5ers";
   p.model                 = "The5ers High-Stakes (2-Step funded)";
   p.phase                 = "funded";
   p.plan_id               = FN_PLAN_THE5ERS_HIGH;
   p.phase_id              = FN_PHASE_FUNDED;
   p.supported_on_mt5      = true;
   p.initial_balance       = 0.0;
   p.account_type          = FN_ACCOUNT_SWAP;
   p.swap_charged          = true;
   p.consistency_pct       = 0.0; // no formal consistency rule

   p.daily_loss_pct        = 5.0;
   p.daily_loss_static     = true;
   p.max_loss_pct          = 10.0;
   p.max_loss_trailing     = false; // STATIC, never trails

   p.profit_target_pct            = 0.0;
   p.min_trading_days             = 0;
   p.min_trades_per_day           = 0;
   p.weekend_hold_allowed         = true;
   p.overnight_hold_allowed       = true;
   p.news_rule_applies            = false; // news allowed
   p.news_window_minutes          = 0;
   p.news_profit_share_pct        = 100.0;
   p.open_risk_rule_applies       = false;
   p.open_risk_max_cumulative_pct = 0.0;
   p.mandatory_sl_minutes         = 0;
   p.margin_max_cumulative_pct    = 100.0;

   p.leverage_fx       = 100; // The5ers differentiator
   p.leverage_metals   = 20;
   p.leverage_indices  = 20;
   p.leverage_energies = 10;
   p.leverage_crypto   = 2;

   p.profit_split_pct                = 80.0;
   p.first_payout_business_days      = 14; // profit cycles every 14d
   p.subsequent_payout_business_days = 14;

   p.is_default_fallback = false;
   FillCommonProhibitedRules(p);
  }

//+------------------------------------------------------------------+
//| LOT C : MyFundedFX rebranded "SeacrestFunded" (2025-02-11).       |
//| 1-Step Standard preset (most common). Daily loss basis =          |
//| start-of-day BALANCE (not equity - key differentiator). Max loss  |
//| STATIC 6 % initially (trails post-+6 % then locks at initial,     |
//| not modelled). EAs PROHIBITED on MT5 (use MatchTrader / DXtrade   |
//| for EAs). News violation on funded = profits voided, account      |
//| survives. Per Agent B research (2024-2025).                       |
//+------------------------------------------------------------------+
void CChallengeProfileCatalog::BuildMyFundedFX(ChallengeProfile &p) const
  {
   p.profile_id            = "seacrest.1step.standard.funded";
   p.vendor                = "SeacrestFunded (ex-MyFundedFX)";
   p.model                 = "SeacrestFunded 1-Step Standard";
   p.phase                 = "funded";
   p.plan_id               = FN_PLAN_MFF_RAPID;
   p.phase_id              = FN_PHASE_FUNDED;
   p.supported_on_mt5      = true;
   p.initial_balance       = 0.0;
   p.account_type          = FN_ACCOUNT_SWAP;
   p.swap_charged          = true;
   p.consistency_pct       = 0.0;

   p.daily_loss_pct        = 4.0;
   p.daily_loss_static     = true; // basis = start-of-day BALANCE (not equity)
   p.max_loss_pct          = 6.0;
   p.max_loss_trailing     = false; // STATIC initially (post-+6 % : locks at initial - not modelled)

   p.profit_target_pct            = 0.0;
   p.min_trading_days             = 0;
   p.min_trades_per_day           = 0;
   p.weekend_hold_allowed         = true;
   p.overnight_hold_allowed       = true;
   p.news_rule_applies            = true;  // funded news = profits voided
   p.news_window_minutes          = 5;
   p.news_profit_share_pct        = 0.0;
   p.open_risk_rule_applies       = false;
   p.open_risk_max_cumulative_pct = 0.0;
   p.mandatory_sl_minutes         = 0;
   p.margin_max_cumulative_pct    = 100.0;

   p.leverage_fx       = 30;
   p.leverage_metals   = 10;
   p.leverage_indices  = 10;
   p.leverage_energies = 10;
   p.leverage_crypto   = 2;

   p.profit_split_pct                = 80.0;
   p.first_payout_business_days      = 14;
   p.subsequent_payout_business_days = 14;

   p.is_default_fallback = false;
   FillCommonProhibitedRules(p);
  }

//+------------------------------------------------------------------+
//| B-AVATRADE-PROFILE : Personal account preset = aucune regle prop. |
//| Enabler du test week-end JR sur demo AvaTrade crypto (et marche   |
//| pour n'importe quel broker perso). Les meters de regles affichent |
//| N/A ou restent inactifs : daily_loss=0 -> dd_applies false,       |
//| max_loss=0 -> ComputeRangeStatus(NA), open_risk_max=0 -> ma logic |
//| LOT 1 risk_applies=(cap>0)=false, news_applies=false, QS/hyper    |
//| caps sur des valeurs inatteignables. Margin cumulative -> 100 %.  |
//| Profit split 100 % (compte perso = tout pour le trader).          |
//+------------------------------------------------------------------+
void CChallengeProfileCatalog::BuildPersonal(ChallengeProfile &p) const
  {
   p.profile_id            = "personal.generic.funded";
   p.vendor                = "Personal / Broker";
   p.model                 = "Personal Account (no prop rules)";
   p.phase                 = "funded";
   p.plan_id               = FN_PLAN_PERSONAL;
   p.phase_id              = FN_PHASE_FUNDED;
   p.supported_on_mt5      = true;
   p.initial_balance       = 0.0;
   p.account_type          = FN_ACCOUNT_SWAP;
   p.swap_charged          = true;
   p.consistency_pct       = 0.0;

   // Drawdown : pas de regle prop -> 0 declenche les branches N/A du panel.
   p.daily_loss_pct        = 0.0;
   p.daily_loss_static     = true;
   p.max_loss_pct          = 0.0;
   p.max_loss_trailing     = false;

   p.profit_target_pct          = 0.0;
   p.min_trading_days           = 0;
   p.min_trades_per_day         = 0;
   p.weekend_hold_allowed       = true;
   p.overnight_hold_allowed     = true;
   p.news_rule_applies          = false;
   p.open_risk_rule_applies     = false;
   p.mandatory_sl_minutes       = 0;

   p.news_window_minutes          = 0;
   p.news_profit_share_pct        = 100.0;
   p.open_risk_max_cumulative_pct = 0.0;   // risk_applies=false -> "N/A"
   p.margin_max_cumulative_pct    = 100.0; // meter actif mais cap inatteignable

   // Leverage par defaut = retail EU (ESMA). Surchargeable via inputs futurs.
   p.leverage_fx       = 30;
   p.leverage_metals   = 20;
   p.leverage_indices  = 20;
   p.leverage_energies = 10;
   p.leverage_crypto   = 2;

   p.profit_split_pct                = 100.0;
   p.first_payout_business_days      = 0;
   p.subsequent_payout_business_days = 0;

   p.is_default_fallback = false;
   FillCommonProhibitedRules(p);
   // Surclasse les caps QS / hyper de FillCommonProhibitedRules : sur compte
   // perso aucune de ces regles ne s'applique -> caps sur des valeurs hautes.
   p.quick_strike_violate_pct      = 100.0;
   p.quick_strike_warn_pct         = 100.0;
   p.hyperactivity_trades_per_day  = 99999;
   p.hyperactivity_msgs_per_day    = 99999;
  }

//+------------------------------------------------------------------+
//| Futures placeholders - listed but NOT operational on MT5         |
//+------------------------------------------------------------------+
void CChallengeProfileCatalog::BuildFuturesPlaceholder(const ENUM_FN_PLAN plan, ChallengeProfile &p) const
  {
   p.vendor                = "FundedNext";
   p.supported_on_mt5      = false;          // <-- key flag
   p.initial_balance       = 0.0;
   p.account_type          = FN_ACCOUNT_SWAP;
   p.swap_charged          = false;          // n/a for futures
   p.phase_id              = FN_PHASE_FUNDED;

   if(plan == FN_PLAN_FUTURES_BOLT)
     {
      p.profile_id     = "fundednext.futures_bolt.base.funded";
      p.model          = "Futures Bolt";
      p.consistency_pct = 40.0;
     }
   else if(plan == FN_PLAN_FUTURES_RAPID)
     {
      p.profile_id     = "fundednext.futures_rapid.base.funded";
      p.model          = "Futures Rapid";
      p.consistency_pct = 40.0;              // funded only; challenge none
     }
   else // LEGACY
     {
      p.profile_id     = "fundednext.futures_legacy.base.funded";
      p.model          = "Futures Legacy";
      p.consistency_pct = 40.0;              // challenge 40 %, removed on funded
     }
   p.plan_id  = plan;
   p.phase    = "funded";

   // Indicative values - the Helper will refuse to compute live metrics
   // and instead render a "Futures platform not supported on MT5" banner.
   p.profit_target_pct          = 6.0;
   p.daily_loss_pct             = 0.0;       // EOD trailing instead
   p.daily_loss_static          = false;
   p.max_loss_pct               = 0.0;       // dollar-based trailing per CME tier
   p.max_loss_trailing          = true;

   p.min_trading_days           = 0;
   p.min_trades_per_day         = 0;

   p.weekend_hold_allowed       = false;     // futures: no weekend hold
   p.overnight_hold_allowed     = false;     // banned (3:10 pm CT cutoff)

   p.news_rule_applies          = false;
   p.news_window_minutes        = 0;
   p.news_profit_share_pct      = 100.0;

   p.open_risk_rule_applies     = false;
   p.open_risk_max_cumulative_pct = 0.0;
   p.mandatory_sl_minutes       = 0;

   p.margin_max_cumulative_pct  = 0.0;       // n/a (CME margin model)
   p.margin_recommended_per_trade_min_pct = 0.0;
   p.margin_recommended_per_trade_max_pct = 0.0;

   p.quick_strike_seconds       = 30;
   p.quick_strike_warn_pct      = 20.0;
   p.quick_strike_violate_pct   = 30.0;

   p.hyperactivity_trades_per_day     = 200;
   p.hyperactivity_msgs_per_day       = 2000;
   p.hyperactivity_force_disable_msgs = 15000;

   p.leverage_fx       = 0;
   p.leverage_metals   = 0;
   p.leverage_indices  = 0;
   p.leverage_energies = 0;
   p.leverage_crypto   = 0;

   p.profit_split_pct                = 80.0;
   p.first_payout_business_days      = 14;
   p.subsequent_payout_business_days = 14;

   p.is_default_fallback = false;
  }

//+------------------------------------------------------------------+
//| Resolve a (plan, phase, size, account_type, addons_mask) tuple   |
//+------------------------------------------------------------------+
bool CChallengeProfileCatalog::Resolve(const ENUM_FN_PLAN plan,
                                       const ENUM_FN_PHASE phase,
                                       const double size,
                                       const ENUM_FN_ACCOUNT_TYPE account_type,
                                       const int addons_mask,
                                       ChallengeProfile &out_profile)
  {
   if(!m_initialized)
      Init();

   // Phase normalisation
   //  - 1-Step has no P2: fold P2 onto P1.
   //  - Instant always uses INSTANT regardless of dropdown.
   ENUM_FN_PHASE eff_phase = phase;
   if(plan == FN_PLAN_STELLAR_INSTANT)
      eff_phase = FN_PHASE_INSTANT;
   else if(plan == FN_PLAN_STELLAR_1STEP && phase == FN_PHASE_CHALLENGE_P2)
      eff_phase = FN_PHASE_CHALLENGE_P1;
   else if(plan == FN_PLAN_FUTURES_BOLT
        || plan == FN_PLAN_FUTURES_RAPID
        || plan == FN_PLAN_FUTURES_LEGACY
        || plan == FN_PLAN_FREE_TRIAL
        || plan == FN_PLAN_FREE_COMPETITION
        || plan == FN_PLAN_E8_8PCT
        || plan == FN_PLAN_THE5ERS_HIGH
        || plan == FN_PLAN_MFF_RAPID    // LOT 5 : single-phase multi-firm stubs
        || plan == FN_PLAN_PERSONAL)    // B-AVATRADE-PROFILE : single-phase
      eff_phase = FN_PHASE_FUNDED;

   const int n = ArraySize(m_profiles);
   for(int i = 0; i < n; ++i)
     {
      if(MatchesBase(m_profiles[i], plan, eff_phase))
        {
         out_profile = m_profiles[i];
         out_profile.initial_balance = size;
         out_profile.account_type    = account_type;
         out_profile.swap_charged    = (account_type == FN_ACCOUNT_SWAP);
         ApplyAddons(out_profile, addons_mask);
         out_profile.profile_id      = FormatProfileId(plan, eff_phase, size, addons_mask);
         out_profile.is_default_fallback = false;
         return true;
        }
     }

   // No base match -> fallback (Stellar 2-Step Funded, most common)
   out_profile = GetDefault();
   out_profile.initial_balance = size;
   out_profile.account_type    = account_type;
   out_profile.swap_charged    = (account_type == FN_ACCOUNT_SWAP);
   ApplyAddons(out_profile, addons_mask);
   out_profile.profile_id      = "fundednext.fallback.stellar_2step.funded." + SizeSlug(size);
   out_profile.is_default_fallback = true;
   return false;
  }

//+------------------------------------------------------------------+
//| GetDefault - sensible fallback (Stellar 2-Step Funded)           |
//+------------------------------------------------------------------+
ChallengeProfile CChallengeProfileCatalog::GetDefault(void) const
  {
   ChallengeProfile p;
   BuildStellar2Step(FN_PHASE_FUNDED, p);
   p.is_default_fallback = true;
   return p;
  }

//+------------------------------------------------------------------+
//| Match: plan + phase identity                                     |
//+------------------------------------------------------------------+
bool CChallengeProfileCatalog::MatchesBase(const ChallengeProfile &p,
                                           const ENUM_FN_PLAN plan,
                                           const ENUM_FN_PHASE phase) const
  {
   return (p.plan_id == plan && p.phase_id == phase);
  }

//+------------------------------------------------------------------+
//| Apply add-on bitmask onto a resolved profile                     |
//+------------------------------------------------------------------+
void CChallengeProfileCatalog::ApplyAddons(ChallengeProfile &p,
                                           const int addons_mask) const
  {
   // Cascade (audit 2026-05-20) : keep ONLY the add-ons valid for THIS plan.
   // Lifetime-95% is FORBIDDEN on Instant (max reward 80%); Bi-Weekly is
   // 2-Step/Lite only; 150%-Reward is 1-Step/2-Step only; 10%-DD is Lite only.
   const int m = addons_mask & ValidAddonsMask(p.plan_id);

   // Lifetime Payout 95 % - profit split from day 1 (1-Step/2-Step/Lite only)
   if((m & FN_ADDON_LIFETIME_95) != 0)
      p.profit_split_pct = 95.0;

   // No Minimum Trading Days
   if((m & FN_ADDON_NO_MIN_DAYS) != 0)
     {
      p.min_trading_days   = 0;
      p.min_trades_per_day = 0;
     }

   // Swap-Free - removes swap, includes triple-Wed
   if((m & FN_ADDON_SWAP_FREE) != 0)
      p.swap_charged = false;

   // 10 % Total Loss Limit - Stellar Lite only (plan-gated via ValidAddonsMask)
   if((m & FN_ADDON_10PCT_DD) != 0)
      p.max_loss_pct = 10.0;

   // Bi-Weekly Reward - first payout 21 -> 14 days (2-Step/Lite only)
   if((m & FN_ADDON_BI_WEEKLY) != 0)
     {
      if(p.first_payout_business_days > 14)
         p.first_payout_business_days = 14;
     }

   // 150% Reward + Double Up - reward / allocation boosts, no risk-constant
   // impact at the profile level (consumed by marketing / pricing). No-op here.
  }

//+------------------------------------------------------------------+
//| ValidAddonsMask - which add-ons are valid for a given plan       |
//| (cascade source of truth, audit 2026-05-20). Futures = none.     |
//+------------------------------------------------------------------+
int CChallengeProfileCatalog::ValidAddonsMask(const ENUM_FN_PLAN plan) const
  {
   switch(plan)
     {
      case FN_PLAN_STELLAR_1STEP:
         return FN_ADDON_LIFETIME_95 | FN_ADDON_NO_MIN_DAYS | FN_ADDON_SWAP_FREE
              | FN_ADDON_150_REWARD | FN_ADDON_DOUBLE_UP;
      case FN_PLAN_STELLAR_2STEP:
         return FN_ADDON_LIFETIME_95 | FN_ADDON_NO_MIN_DAYS | FN_ADDON_SWAP_FREE
              | FN_ADDON_150_REWARD | FN_ADDON_BI_WEEKLY | FN_ADDON_DOUBLE_UP;
      case FN_PLAN_STELLAR_LITE:
         return FN_ADDON_LIFETIME_95 | FN_ADDON_NO_MIN_DAYS | FN_ADDON_SWAP_FREE
              | FN_ADDON_10PCT_DD | FN_ADDON_BI_WEEKLY | FN_ADDON_DOUBLE_UP;
      case FN_PLAN_STELLAR_INSTANT:
         return FN_ADDON_SWAP_FREE | FN_ADDON_DOUBLE_UP; // 95% FORBIDDEN (max reward 80%)
     }
   return FN_ADDON_NONE; // Futures (Bolt/Rapid/Legacy/Flex) : no CFD add-ons
  }

//+------------------------------------------------------------------+
//| profile_id formatter                                             |
//+------------------------------------------------------------------+
string CChallengeProfileCatalog::FormatProfileId(const ENUM_FN_PLAN plan,
                                                 const ENUM_FN_PHASE phase,
                                                 const double size,
                                                 const int addons_mask) const
  {
   string id = "fundednext." + PlanSlug(plan) + "." + PhaseSlug(phase) + "." + SizeSlug(size);
   if(addons_mask != FN_ADDON_NONE)
      id += ".+addons";
   return id;
  }

string CChallengeProfileCatalog::PlanSlug(const ENUM_FN_PLAN plan) const
  {
   switch(plan)
     {
      case FN_PLAN_STELLAR_1STEP:   return "stellar_1step";
      case FN_PLAN_STELLAR_2STEP:   return "stellar_2step";
      case FN_PLAN_STELLAR_LITE:    return "stellar_lite_2step";
      case FN_PLAN_STELLAR_INSTANT: return "stellar_instant";
      case FN_PLAN_FUTURES_BOLT:    return "futures_bolt";
      case FN_PLAN_FUTURES_RAPID:   return "futures_rapid";
      case FN_PLAN_FUTURES_LEGACY:  return "futures_legacy";
      case FN_PLAN_FREE_TRIAL:       return "free_trial";
      case FN_PLAN_FREE_COMPETITION: return "free_competition";
      // LOT 5 : multi-firm presets
      case FN_PLAN_FTMO_2STEP:       return "ftmo_2step";
      case FN_PLAN_E8_8PCT:          return "e8_8pct";
      case FN_PLAN_THE5ERS_HIGH:     return "the5ers_high";
      case FN_PLAN_MFF_RAPID:        return "mff_rapid";
      case FN_PLAN_PERSONAL:         return "personal";
     }
   return "unknown_plan";
  }

string CChallengeProfileCatalog::PhaseSlug(const ENUM_FN_PHASE phase) const
  {
   switch(phase)
     {
      case FN_PHASE_CHALLENGE_P1: return "challenge_p1";
      case FN_PHASE_CHALLENGE_P2: return "challenge_p2";
      case FN_PHASE_FUNDED:       return "funded";
      case FN_PHASE_INSTANT:      return "instant";
     }
   return "unknown_phase";
  }

string CChallengeProfileCatalog::SizeSlug(const double size) const
  {
   const int k = (int)MathRound(size / 1000.0);
   return IntegerToString(k) + "k";
  }

string CChallengeProfileCatalog::ModelLabel(const ENUM_FN_PLAN plan) const
  {
   switch(plan)
     {
      case FN_PLAN_STELLAR_1STEP:   return "Stellar 1-Step";
      case FN_PLAN_STELLAR_2STEP:   return "Stellar 2-Step";
      case FN_PLAN_STELLAR_LITE:    return "Stellar Lite 2-Step";
      case FN_PLAN_STELLAR_INSTANT: return "Stellar Instant";
      case FN_PLAN_FUTURES_BOLT:    return "Futures Bolt";
      case FN_PLAN_FUTURES_RAPID:   return "Futures Rapid";
      case FN_PLAN_FUTURES_LEGACY:  return "Futures Legacy";
      case FN_PLAN_FREE_TRIAL:       return "Free Trial";
      case FN_PLAN_FREE_COMPETITION: return "Free Competition";
      // LOT 5 : multi-firm presets
      case FN_PLAN_FTMO_2STEP:       return "FTMO 2-Step";
      case FN_PLAN_E8_8PCT:          return "E8 Funding (8%)";
      case FN_PLAN_THE5ERS_HIGH:     return "The5ers High-Stakes";
      case FN_PLAN_MFF_RAPID:        return "MyFundedFX Rapid";
      case FN_PLAN_PERSONAL:         return "Personal Account";
     }
   return "Unknown Plan";
  }

string CChallengeProfileCatalog::PhaseLabel(const ENUM_FN_PHASE phase) const
  {
   switch(phase)
     {
      case FN_PHASE_CHALLENGE_P1: return "Challenge P1";
      case FN_PHASE_CHALLENGE_P2: return "Challenge P2";
      case FN_PHASE_FUNDED:       return "Funded";
      case FN_PHASE_INSTANT:      return "Instant";
     }
   return "Unknown Phase";
  }

//+------------------------------------------------------------------+
//| Human-readable add-on summary (for the Helper panel)             |
//+------------------------------------------------------------------+
string CChallengeProfileCatalog::DescribeAddons(const int addons_mask) const
  {
   if(addons_mask == FN_ADDON_NONE)
      return "none";

   string parts[];
   ArrayResize(parts, 0);

   if((addons_mask & FN_ADDON_LIFETIME_95) != 0) { int n = ArraySize(parts); ArrayResize(parts, n + 1); parts[n] = "Lifetime 95%"; }
   if((addons_mask & FN_ADDON_NO_MIN_DAYS) != 0) { int n = ArraySize(parts); ArrayResize(parts, n + 1); parts[n] = "No Min Days"; }
   if((addons_mask & FN_ADDON_SWAP_FREE)   != 0) { int n = ArraySize(parts); ArrayResize(parts, n + 1); parts[n] = "Swap-Free"; }
   if((addons_mask & FN_ADDON_10PCT_DD)    != 0) { int n = ArraySize(parts); ArrayResize(parts, n + 1); parts[n] = "10% Total DD"; }
   if((addons_mask & FN_ADDON_DOUBLE_UP)   != 0) { int n = ArraySize(parts); ArrayResize(parts, n + 1); parts[n] = "Double Up"; }
   if((addons_mask & FN_ADDON_BI_WEEKLY)   != 0) { int n = ArraySize(parts); ArrayResize(parts, n + 1); parts[n] = "Bi-Weekly"; }
   if((addons_mask & FN_ADDON_150_REWARD)  != 0) { int n = ArraySize(parts); ArrayResize(parts, n + 1); parts[n] = "150% Reward"; }

   string out = "";
   for(int i = 0; i < ArraySize(parts); ++i)
     {
      if(i > 0) out += " + ";
      out += parts[i];
     }
   return out;
  }

#endif // __CCHALLENGEPROFILECATALOG_MQH__
//+------------------------------------------------------------------+
