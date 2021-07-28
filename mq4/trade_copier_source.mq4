#property version   "1.0"
#property description "Developed by Profit Robots: info@profitrobots.com"
#property copyright "ProfitRobots"
#property link "http://profitrobots.com"
#property strict

input string   Advanced_Key             = ""; // Key
input string   Comment2                 = "- You can get a key via @profit_robots_bot Telegram Bot. Visit ProfitRobots.com for discord/other platform keys -";

#import "AdvancedNotificationsLib.dll"
void AdvancedAlert(string key, string text, string instrument, string timeframe);
#import

bool initial_start = true;

#include <TradingMonitor.mq4>
#include <OrdersIterator.mq4>
#include <actions/AAction.mq4>

class ClosedTradeAction : public AAction
{
public:
   virtual bool DoAction()
   {
      string command = "quantity=" + DoubleToString(OrderLots()) 
         + " action=close order-id=" + IntegerToString(OrderTicket());
      AdvancedAlert(Advanced_Key, command, "", "");
      return false;
   }
};

class NewTradeAction : public AAction
{
public:
   virtual bool DoAction()
   {
      ulong orderType = OrderType();
      string command = "symbol=" + OrderSymbol()
         + " side=" + (orderType == OP_BUY ? "B" : "S")
         + " order-id=" + IntegerToString(OrderTicket())
         + " quantity=" + DoubleToString(OrderLots());
      double tp = OrderTakeProfit();
      if (tp != 0.0)
         command = command + " take-profit=" + DoubleToString(tp);
      double sl = OrderStopLoss();
      if (sl != 0.0)
         command = command + " stop-loss=" + DoubleToString(sl);
      AdvancedAlert(Advanced_Key, command, "", "");
      return false;
   }
};

class TradeChangedAction : public AAction
{
public:
   virtual bool DoAction()
   {
      string command = "action=change"
         + " order-id=" + IntegerToString(OrderTicket())
         + " take-profit=" + DoubleToString(OrderTakeProfit())
         + " stop-loss=" + DoubleToString(OrderStopLoss());
      AdvancedAlert(Advanced_Key, command, "", "");
      return false;
   }
};

TradingMonitor* monitor;

void ExecuteCommands()
{
   monitor.DoWork();
   if (initial_start)
   {
      ClosedTradeAction* closedTradeAction = new ClosedTradeAction();
      monitor.SetClosedTradeAction(closedTradeAction);
      closedTradeAction.Release();

      NewTradeAction* newTradeAction = new NewTradeAction();
      monitor.SetOnNewTrade(newTradeAction);
      newTradeAction.Release();

      TradeChangedAction* tradeChangedAction = new TradeChangedAction();
      monitor.SetOnTradeChanged(tradeChangedAction);
      tradeChangedAction.Release();
      initial_start = false;
   }
}

string IndicatorName;
string IndicatorObjPrefix;

string GenerateIndicatorName(const string target)
{
   string name = target;
   int try = 2;
   while (WindowFind(name) != -1)
   {
      name = target + " #" + IntegerToString(try++);
   }
   return name;
}

int OnInit()
{
   if (!IsDllsAllowed())
   {
      Print("Error: Dll calls must be allowed!");
      return INIT_FAILED;
   }
   IndicatorName = GenerateIndicatorName("Trade Copy Source");
   IndicatorObjPrefix = "__" + IndicatorName + "__";
   IndicatorShortName(IndicatorName);

   monitor = new TradingMonitor();

   EventSetTimer(1);
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   delete monitor;
   monitor = NULL;
   EventKillTimer();
}

void OnTimer()
{
   ExecuteCommands();
}

void OnTick()
{
   ExecuteCommands();
}
