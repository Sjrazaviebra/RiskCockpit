//+------------------------------------------------------------------+
//|                                                 RCNewsFeeder.mq5 |
//|                RiskCockpit companion SERVICE (v2.13 news bridge) |
//|                                                                  |
//| Indicators cannot call WebRequest (MQL5 forbids it : -1/err 4014 |
//| even whitelisted). SERVICES can. This service fetches the public |
//| ForexFactory (FairEconomy) weekly calendar every hour and writes |
//| the RAW response bytes to MQL5\Files\ff_calendar_thisweek.json - |
//| the exact file RiskCockpit's FFLoadFromFile reads (terminal-local,|
//| NOT FILE_COMMON ; binary ; RiskCockpit ignores files older than  |
//| 8 days, so the hourly refresh keeps it warm with huge margin).   |
//| Result : the [FF] badge + FN-aligned news classification light up |
//| in RiskCockpit without touching the indicator.                    |
//+------------------------------------------------------------------+
#property service
#property version   "1.00"
#property copyright "Sjrazaviebra"
#property description "RiskCockpit news feeder : fetches the ForexFactory (FairEconomy) weekly calendar and writes MQL5\\Files\\ff_calendar_thisweek.json for RiskCockpit (indicators cannot WebRequest)."

input int InpRefreshMinutes = 60; // refresh interval (minutes)

void OnStart()
  {
   const string url = "https://nfs.faireconomy.media/ff_calendar_thisweek.json";
   while(!IsStopped())
     {
      char post[]; char result[]; string rhdr;
      ResetLastError();
      const int code = WebRequest("GET", url, "", 5000, post, result, rhdr);
      if(code == 200 && ArraySize(result) > 0)
        {
         const int h = FileOpen("ff_calendar_thisweek.json", FILE_WRITE|FILE_BIN|FILE_SHARE_READ|FILE_SHARE_WRITE);
         if(h != INVALID_HANDLE)
           {
            FileWriteArray(h, result, 0, WHOLE_ARRAY);
            FileClose(h);
            PrintFormat("RCNewsFeeder: wrote %d bytes (HTTP %d).", ArraySize(result), code);
           }
         else
            Print("RCNewsFeeder: FileOpen failed err=", GetLastError());
        }
      else
         PrintFormat("RCNewsFeeder: WebRequest failed HTTP=%d err=%d. If err=4014, whitelist https://nfs.faireconomy.media in Tools>Options>Expert Advisors.", code, GetLastError());

      // sleep by 1 s steps so a Stop is honored promptly
      for(int s = 0; s < InpRefreshMinutes*60 && !IsStopped(); ++s)
         Sleep(1000);
     }
  }
//+------------------------------------------------------------------+
