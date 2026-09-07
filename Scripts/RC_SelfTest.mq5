//+------------------------------------------------------------------+
//| RC_SelfTest.mq5 - exercises the PURE math RiskCockpit runs on.   |
//|                                                                  |
//| Attach it to any chart : it needs no account, no symbol and no    |
//| open position, and it changes nothing. Results go to the Experts  |
//| journal, one line per case, and a final PASS / FAIL count.        |
//|                                                                  |
//| It includes the SAME RC_Math.mqh the indicator includes, so what  |
//| is tested is the code that actually ships - not a copy of it. A   |
//| check that does not cross the language boundary verifies nothing. |
//+------------------------------------------------------------------+
#property copyright "JR Trading - 2026 - javadrazavi.fr"
#property link      "https://javadrazavi.fr"
#property version   "1.00"
#property script_show_inputs
#property strict

#include <..\Libraries\RC_Math.mqh>

int g_pass = 0, g_fail = 0;

void Check(const string name, const bool ok, const string got = "") {
    if (ok) { g_pass++; Print("  PASS  ", name); }
    else    { g_fail++; Print("  FAIL  ", name, (got == "" ? "" : "   -> " + got)); }
}
void CheckD(const string name, const double got, const double want, const double tol = 0.005) {
    Check(name, MathAbs(got - want) <= tol,
          StringFormat("obtenu %.4f, attendu %.4f", got, want));
}

void OnStart() {
    Print("=== RiskCockpit self-test : pure math ===");

    // --- TRAILING FLOOR : the level at which a funded account is lost -----
    // FundedNext oracle (Instant 2K) : peak 2003.28, 6% of 2000 = 120 permitted.
    CheckD("plancher : oracle FN Instant 2K",
           RC_TrailingFloor(2003.28, 2000.0, 6.0), 1883.28);
    // never above the initial balance : the break-even lock caps it
    CheckD("plancher : plafonne a la balance initiale",
           RC_TrailingFloor(5000.0, 2000.0, 6.0), 2000.0);
    // a peak still under the initial balance : the floor follows the peak
    CheckD("plancher : pic sous la balance initiale",
           RC_TrailingFloor(1950.0, 2000.0, 6.0), 1830.0);
    // day one : peak == initial
    CheckD("plancher : premier jour", RC_TrailingFloor(2000.0, 2000.0, 6.0), 1880.0);
    // Losses never lower the floor - only the PEAK moves it. The first version
    // of this case passed the SAME call on both sides of the comparison : it
    // could not fail. A test that cannot say no proves nothing.
    CheckD("plancher : suit le pic, pas la balance courante",
           RC_TrailingFloor(2100.0, 2000.0, 6.0), 1980.0);
    // guards : nothing configured yet must not produce a bogus level
    CheckD("plancher : balance initiale nulle", RC_TrailingFloor(2000.0, 0.0, 6.0), 0.0);
    CheckD("plancher : pourcentage nul", RC_TrailingFloor(2000.0, 2000.0, 0.0), 0.0);
    // a 10% add-on account
    CheckD("plancher : add-on 10% DD", RC_TrailingFloor(10500.0, 10000.0, 10.0), 9500.0);

    // --- STATUS THRESHOLDS : the same 80% / 100% everywhere ---------------
    Check("statut : 0 sur 100 = OK",    ComputeRangeStatus(0.0, 100.0, 0.80, 1.00) == RC_STATUS_OK);
    Check("statut : 79 sur 100 = OK",   ComputeRangeStatus(79.0, 100.0, 0.80, 1.00) == RC_STATUS_OK);
    Check("statut : 80 sur 100 = WARN", ComputeRangeStatus(80.0, 100.0, 0.80, 1.00) == RC_STATUS_WARN);
    Check("statut : 99 sur 100 = WARN", ComputeRangeStatus(99.0, 100.0, 0.80, 1.00) == RC_STATUS_WARN);
    Check("statut : 100 sur 100 = RED", ComputeRangeStatus(100.0, 100.0, 0.80, 1.00) == RC_STATUS_RED);
    Check("statut : au-dela = RED",     ComputeRangeStatus(140.0, 100.0, 0.80, 1.00) == RC_STATUS_RED);
    Check("statut : plafond nul = N/A", ComputeRangeStatus(5.0, 0.0, 0.80, 1.00) == RC_STATUS_NA);

    // --- CYCLE DATES : they drive the trading-days counter ----------------
    Check("date : ISO -> YMD", (int)IsoToYmd("2026-05-09") == 20260509);
    Check("date : YMD -> ISO", YmdToIso(20260509.0) == "2026-05-09");
    Check("date : aller-retour", YmdToIso(IsoToYmd("2026-12-31")) == "2026-12-31");
    Check("date : meme jour = 0",   DaysBetweenIso("2026-05-09", "2026-05-09") == 0);
    Check("date : un jour",         DaysBetweenIso("2026-05-09", "2026-05-10") == 1);
    Check("date : bascule de mois", DaysBetweenIso("2026-01-31", "2026-02-01") == 1);
    Check("date : bascule d'annee", DaysBetweenIso("2025-12-31", "2026-01-01") == 1);
    Check("date : fevrier 2028 (bissextile)", DaysInMonth(2028, 2) == 29);
    Check("date : fevrier 2026", DaysInMonth(2026, 2) == 28);
    Check("date : avril = 30",   DaysInMonth(2026, 4) == 30);
    Check("date : decembre = 31", DaysInMonth(2026, 12) == 31);

    // --- NEWS TIMESTAMPS : a wrong parse shifts every news window ---------
    const datetime t = FFParseIso8601Utc("2026-09-04T14:30:00-04:00");
    Check("news : ISO8601 avec decalage -04:00",
          t == D'2026.09.04 18:30:00', TimeToString(t, TIME_DATE | TIME_SECONDS));
    const datetime z = FFParseIso8601Utc("2026-09-04T18:30:00Z");
    Check("news : ISO8601 en Z", z == D'2026.09.04 18:30:00',
          TimeToString(z, TIME_DATE | TIME_SECONDS));
    Check("news : les deux formes donnent la meme heure", t == z);

    // --- FORMATTING : what the trader reads --------------------------------
    Check("format : pourcentage", FormatPct(12.345) != "");
    Check("format : montant", FormatMoney(1234.5) != "");

    PrintFormat("=== self-test : %d PASS, %d FAIL ===", g_pass, g_fail);
    if (g_fail > 0)
        Alert("RiskCockpit self-test : ", g_fail, " cas en echec - voir le journal.");
}
