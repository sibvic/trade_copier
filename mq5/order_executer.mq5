#property version   "1.1"
#property description "Developed by Profit Robots: info@profitrobots.com"
#property copyright "ProfitRobots"
#property link "http://profitrobots.com"
#property strict

enum ServerType
{
   //ProfitRobots = 0, // ProfitRobots.com
   SelfHosted = 1, // Self-hosted
   Test1 = 2, // Localhost 54512
   Test2 = 3, // Localhost 65282
   WSS = 4, // ProfitRobots.com (secured)
};

input string Key = ""; // Storage Key
input int Slippage = 3; // Slippage
input int MagicNumber = 42; // Magic Number
input ServerType Server = WSS; // Server

// AdvancedNotificationsLib.dll could be downloaded here: http://profitrobots.com/Home/TelegramNotificationsMT4

#define LISTENER_STATUS_DISCONNECTED 0
#define LISTENER_STATUS_CONNECTING 1
#define LISTENER_STATUS_CONNECTED 2
#import "AdvancedNotificationsLib.dll"
void AdvancedAlert(string key, string text, string instrument, string timeframe);
bool StartListener(string key, int serverType);
bool StopListener();
int ListenerStatus();
string GetNextMessage();
string PopLogMessage();
#import

#import "CommandExecuter.dll"
int ParseCommand(string commandText);
void DeleteCommand(const int commandId);
string GetCommandSymbol(const int commandId);
#define ORDER_SIDE_LONG 0
#define ORDER_SIDE_SHORT 1
#define ORDER_SIDE_NOT_SET 2
int GetCommandOrderSide(const int commandId);
string GetCommandOrderId(const int commandId);

#define AMOUNT_CONTRACTS 0
#define AMOUNT_PERCENT_OF_EQUITY 1
#define AMOUNT_NOT_SET 2
#define AMOUNT_RISK_PERCENT_OF_EQUITY 3
double GetCommandAmount(const int commandId);
int GetCommandAmountType(const int commandId);

#define COMMAND_ACTION_CREATE 0
#define COMMAND_ACTION_CHANGE 1
#define COMMAND_ACTION_CLOSE 2
int GetCommandAction(const int commandId);

#define SL_NONE 0
#define SL_ABOSOLUTE 1
#define SL_PIPS 2

int GetCommandStopLossType(const int commandId);
double GetCommandStopLossValue(const int commandId);

#define BREAKEVEN_DISABLED 0
#define BREAKEVEN_ENABLED 1
int GetCommandBreakevenType(const int commandId);
double GetCommandBreakevenWhen(const int commandId);
double GetCommandBreakevenTo(const int commandId);

#define TRAILING_NONE 0
#define TRAILING_DELAYED 1
int GetCommandTrailingType(const int commandId);
double GetCommandTrailingWhen(const int commandId);
double GetCommandTrailingStep(const int commandId);

int GetCommandTakeProfitType(const int commandId);
double GetCommandTakeProfitValue(const int commandId);

int GetCommandLifetime(const int commandId);

#define ORDER_TYPE_MARKET 0
#define ORDER_TYPE_LIMIT 1
#define ORDER_TYPE_STOP 2
int GetCommandOrderType(const int commandId);

int GetCommandCancelAfter(const int commandId);

double GetCommandRate(const int commandId);
#define RATE_TYPE_NONE 0
#define RATE_TYPE_ABSOLUTE 1
#define RATE_TYPE_PIPS 2
int GetCommandRateType(const int commandId);

string GetLastCommandError();
#import

enum TrailingType
{
   TrailingDontUse, // No trailing
   TrailingPips, // Use trailing in pips
   TrailingPercent // Use trailing in % of stop
#ifdef USE_ATR_TRAILLING
   ,TrailingATR // Use ATR trailing
#endif
};

#import "AdvancedNotificationsLib.dll"
void AdvancedAlert(string key, string text, string instrument, string timeframe);
#import

#include <InstrumentInfo.mq5>
#include <MarketOrderBuilder.mq5>
#include <TradesIterator.mq5>
#include <TradingCommands.mq5>
#include <TradingCalculator.mq5>
#include <MoneyManagement/MoneyManagementStrategy.mq5>
#include <MoneyManagement/DefaultLotsProvider.mq5>
#include <MoneyManagement/PositionSizeRiskStopLossAndAmountStrategy.mq5>
#include <MoneyManagement/DefaultStopLossAndAmountStrategy.mq5>
#include <MoneyManagement/DefaultTakeProfitStrategy.mq5>
#include <MoneyManagement/RiskToRewardTakeProfitStrategy.mq5>
#include <MoneyManagement/ATRTakeProfitStrategy.mq5>
#include <MoneyManagement/MoneyManagementFunctions.mq5>
#include <BreakevenController.mq5>
#include <TrailingController.mq5>
#include <Logic/ActionOnConditionLogic.mq5>

//BreakevenController _breakeven;
//TrailingLogic* _trailing;

//TODO: ActionOnConditionController from mq4

void ExecuteCommand(const int id)
{
   int action = GetCommandAction(id);
   if (action < 0)
   {
      return;
   }

   if (action == COMMAND_ACTION_CREATE)
   {
      ExecuteOpenCommand(id);
   }
   else if (action == COMMAND_ACTION_CHANGE)
   {
      ExecuteChangeCommand(id);
   }
   else if (action == COMMAND_ACTION_CLOSE)
   {
      ExecuteCloseCommand(id);
   }
}

void ClosePositions(TradesIterator &it, const double amountToClose)
{
   double remainingToClose = amountToClose;
   while (remainingToClose > 0 && it.Next())
   {
      double positionAmount = it.GetLots();
      if (remainingToClose >= positionAmount)
      {
         string error;
         if (TradingCommands::CloseTrade(it.GetTicket(), error))
            remainingToClose -= positionAmount;
         else
            Print("Failed to close a position: " + error);
      }
      else
      {
         Print("Partial close is not implemented yet");
         //TODO: partial close
      }
   }
}

void ExecuteCloseCommand(const int id)
{
   TradesIterator it();
   string symbol = GetCommandSymbolEx(id);
   if (symbol != "")
      it.WhenSymbol(symbol);
   int orderSide = GetCommandOrderSide(id);
   if (orderSide != ORDER_SIDE_NOT_SET)
      it.WhenSide(orderSide == ORDER_SIDE_LONG ? BuySide : SellSide);
   if (GetCommandAmountType(id) == AMOUNT_NOT_SET)
      TradingCommands::CloseTrades(it);
   else
   {
      switch (GetAmountType(id))
      {
         case PositionSizeContract:
            ClosePositions(it, GetCommandAmount(id));
            break;
         default:
            Print("Not supported amount type for closing a position");
            break;
      }
   }
}

PositionSizeType GetAmountType(const int id)
{
   int type = GetCommandAmountType(id);
   if (type == AMOUNT_CONTRACTS)
      return PositionSizeContract;
   if (type == AMOUNT_PERCENT_OF_EQUITY)
      return PositionSizeEquity;
   if (type == AMOUNT_RISK_PERCENT_OF_EQUITY)
      return PositionSizeRisk;
   if (type == AMOUNT_NOT_SET)
      Print("Error: No amount is set!");
   return PositionSizeContract;
}

string GetCommandSymbolEx(const int id)
{
   string symbol = GetCommandSymbol(id);
   if (symbol == "")
      return "";
   
   StringReplace(symbol, "/", "");
   StringToUpper(symbol);
   return symbol;
}

StopLossType ToStopLossType(int type)
{
   switch (type)
   {
      case SL_NONE:
         return SLDoNotUse;
      case SL_ABOSOLUTE:
         return SLAbsolute;
      case SL_PIPS:
         return SLPips;
   }
   Print("Unknown stop loss type");
   return SLDoNotUse;
}

TakeProfitType ToTakeProfitType(int type)
{
   switch (type)
   {
      case SL_NONE:
         return TPDoNotUse;
      case SL_ABOSOLUTE:
         return TPAbsolute;
      case SL_PIPS:
         return TPPips;
   }
   Print("Unknown take profit type");
   return TPDoNotUse;
}

void ExecuteOpenCommand(const int id)
{
   string symbol = GetCommandSymbolEx(id);
   if (symbol == "")
      return;
   int side = GetCommandOrderSide(id);
   if (side < 0)
      return;
      
   TradingCalculator *calc = TradingCalculator::Create(symbol);
   if (calc == NULL)
   {
      Print("Failed to execute a command: Unknown symbol");
      return;
   }
   bool isBuy = side == 0;
   IMoneyManagementStrategy *moneyManagement = CreateMoneyManagementStrategy(calc, symbol, (ENUM_TIMEFRAMES)_Period, isBuy
      , GetAmountType(id), GetCommandAmount(id)
      , ToStopLossType(GetCommandStopLossType(id)), GetCommandStopLossValue(id)
      , ToTakeProfitType(GetCommandTakeProfitType(id)), GetCommandTakeProfitValue(id), 0);

   double entryPrice = isBuy ? calc.GetSymbolInfo().GetAsk() : calc.GetSymbolInfo().GetBid();
   double amount;
   double stopLoss;
   double takeProfit;
   moneyManagement.Get(0, entryPrice, amount, stopLoss, takeProfit);
   delete moneyManagement;
   if (amount == 0.0)
   {
      delete calc;
      return;
   }

   string orderId = GetCommandOrderId(id);
   
   MarketOrderBuilder *orderBuilder = new MarketOrderBuilder(actions);
   orderBuilder
      .SetSide(isBuy ? BuySide : SellSide)
      .SetInstrument(symbol)
      .SetAmount(amount)
      .SetSlippage(Slippage)
      .SetMagicNumber(MagicNumber)
      .SetStopLoss(stopLoss)
      .SetTakeProfit(takeProfit)
      .SetComment(orderId);

   string error;
   ulong order = orderBuilder.Execute(error);
   if (order > 0)
   {
      //TODO:
      // if (GetCommandBreakevenType(id) == BREAKEVEN_ENABLED)
      //    _breakeven.CreateBreakeven(order, 0, StopLimitPips, GetCommandBreakevenWhen(id), GetCommandBreakevenTo(id));
      // if (GetCommandTrailingType(id) == TRAILING_DELAYED)
      // {
      //    double trailingWhen = GetCommandTrailingWhen(id);
      //    double trailingStep = GetCommandTrailingStep(id);
      //    double stopDistance = MathAbs(OrderOpenPrice() - stopLoss) / calc.GetPipSize() + trailingWhen;
      //    _trailing.Create(order, stopDistance, TrailingPips, trailingStep);
      // }
   }
   else
   {
      Print("Failed to open trade: " + error);
   }
   delete calc;
   delete orderBuilder;
}

void ExecuteChangeCommand(const int id)
{
   string orderId = GetCommandOrderId(id);
   TradesIterator it;
   ulong ticketId = it.WhenComment(orderId).First();
   if (ticketId == 0)
   {
      Print("Order with id " + orderId + " not found");
      return;
   }

   double amount = it.GetLots();
   double entryPrice = it.GetOpenPrice();
   bool isBuy = it.IsBuyOrder();
   double initialStopLoss = it.GetStopLoss();
   double initialTakeProfit = it.GetTakeProfit();
   TradingCalculator *calc = TradingCalculator::Create(it.GetSymbol());
   if (calc == NULL)
   {
      Print("Failed to execute a command: Unknown symbol");
      return;
   }
   StopLossType stopLossType = ToStopLossType(GetCommandStopLossType(id));
   TakeProfitType takeProfitType = ToTakeProfitType(GetCommandTakeProfitType(id));
   
   IMoneyManagementStrategy *moneyManagement = CreateMoneyManagementStrategy(calc, it.GetSymbol(), (ENUM_TIMEFRAMES)_Period, isBuy
      , PositionSizeContract, amount
      , stopLossType, GetCommandStopLossValue(id)
      , takeProfitType, GetCommandTakeProfitValue(id), 0);

   double _;
   double stopLoss;
   double takeProfit;
   moneyManagement.Get(0, entryPrice, _, stopLoss, takeProfit);
   delete moneyManagement;
   delete calc;

   if (stopLossType == SLDoNotUse)
      stopLoss = initialStopLoss;
   if (takeProfitType == TPDoNotUse)
      takeProfit = initialTakeProfit;
   
   string error;
   if (!TradingCommands::MoveSLTP(ticketId, stopLoss, takeProfit, error))
   {
      Print(error);
   }
}

void UpdateConnectionStatus()
{
   switch (ListenerStatus())
   {
      case LISTENER_STATUS_DISCONNECTED:
         Comment("Disconnected");
         break;
      case LISTENER_STATUS_CONNECTING:
         Comment("Connecting");
         break;
      case LISTENER_STATUS_CONNECTED:
         Comment("Connected");
         break;
   }
}

void ExecuteCommands()
{
   actions.DoLogic(0, 0);
   if (!connect_sent && ListenerStatus() == LISTENER_STATUS_DISCONNECTED)
   {
      DoConnect();
      return;
   }
   
   string logMessage = PopLogMessage();
   while (logMessage != "")
   {
      Print(logMessage);
      logMessage = PopLogMessage();
   }
   UpdateConnectionStatus();
   string command = GetNextMessage();
   while (command != "")
   {
      Print("New commnad: " + command);
      int commandId = ParseCommand(command);
      if (commandId >= 0)
      {
         ExecuteCommand(commandId);
         DeleteCommand(commandId);
      }
      else
         Print("Failed to parse command: " + command + " Error: " + GetLastCommandError());

      command = GetNextMessage();
   }
}

ActionOnConditionLogic* actions;

bool connect_sent = false;

void DoConnect()
{
   StartListener(Key, Server);
   connect_sent = true;
}

int OnInit()
{
   actions = new ActionOnConditionLogic();
   EventSetTimer(1);
   if (ListenerStatus() == LISTENER_STATUS_DISCONNECTED)
   {
      DoConnect();
   }
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   EventKillTimer();
   StopListener();
   connect_sent = false;
   delete actions;
   actions = NULL;
}

void OnTimer()
{
   ExecuteCommands();
}

void OnTick()
{
   ExecuteCommands();
}
