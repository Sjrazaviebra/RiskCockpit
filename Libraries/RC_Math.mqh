//+------------------------------------------------------------------+
//| RC_Math.mqh - the PURE part of RiskCockpit                       |
//|                                                                  |
//| No global, no account, no symbol : same inputs, same result. That |
//| is what makes these testable without a live account, and they are |
//| not small print - they carry the cycle dates, the news            |
//| timestamps, the status thresholds and the TRAILING FLOOR, the     |
//| level at which a funded account is lost.                          |
//|                                                                  |
//| Exercised by Scripts/RC_SelfTest.mq5.                            |
//+------------------------------------------------------------------+
#property copyright "JR Trading - 2026 - javadrazavi.fr"
#property link      "https://javadrazavi.fr"

enum ENUM_RC_STATUS {
    RC_STATUS_NA = 0,
    RC_STATUS_OK = 1,
    RC_STATUS_WARN = 2,
    RC_STATUS_RED = 3
};

//+------------------------------------------------------------------+
//| Trailing floor of an instant-funding account.                    |
//|                                                                  |
//| permitted = max_loss_pct % of the INITIAL balance - a FIXED $,    |
//| never a share of a growing peak. The floor follows the realised   |
//| balance high MINUS that amount, and is CAPPED at the initial      |
//| balance (break-even lock) : profits raise it, losses never lower  |
//| it. Equity crossing it = account lost.                            |
//| FundedNext oracle, Instant 2K : peak 2003.28, permitted 120       |
//| -> floor 1883.28.                                                 |
//+------------------------------------------------------------------+
double RC_TrailingFloor(const double peak_balance, const double initial,
                        const double max_loss_pct) {
    if (initial <= 0.0 || max_loss_pct <= 0.0)
        return 0.0;
    const double permitted = (max_loss_pct / 100.0) * initial;
    const double raw = peak_balance - permitted;
    return (raw < initial ? raw : initial);
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
int DaysInMonth(const int y, const int m) {
    if (m == 2) return (((y % 4 == 0) && (y % 100 != 0)) || (y % 400 == 0)) ? 29 : 28;
    if (m == 4 || m == 6 || m == 9 || m == 11) return 30;
    return 31;
}
