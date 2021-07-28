#property version   "1.9"
#property description "Developed by Profit Robots: info@profitrobots.com"
#property copyright "ProfitRobots"
#property link "https://profitrobots.com"
#property strict

enum ServerType
{
   //ProfitRobots = 0, // ProfitRobots.com
   SelfHosted = 1, // Self-hosted
   Test1 = 2, // Localhost 54512
   Test2 = 3, // Localhost 65282
   WSS = 4, // ProfitRobots.com (secured)
};

input string Key = ""; // Executer Key
input string Key_desc = "https://profitrobots.com/Notifications"; // You can find how to get an executer key here
input int Slippage = 3; // Slippage
input int MagicNumber = 42; // Magic Number
input ServerType Server = WSS; // Server

// AdvancedNotificationsLib.dll could be downloaded here: https://profitrobots.com/Home/TelegramNotificationsMT4

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

#include <signaler.mq4>
#include <TradingCommands.mq4>
#include <TradingCalculator.mq4>
#include <Logic/ActionOnConditionLogic.mq4>
#include <MoneyManagement/functions.mq4>
#include <MarketOrderBuilder.mq4>
#include <OrderBuilder.mq4>
#include <Order.mq4>
#include <Conditions/HitProfitCondition.mq4>
#include <Conditions/ProfitInRangeCondition.mq4>
#include <Conditions/OrderEOLCondition.mq4>
#include <Actions/MoveToBreakevenAction.mq4>
#include <Actions/TrailingPipsAction.mq4>
#include <Actions/CloseOrderAction.mq4>
#include <Actions/DeletePendingOrderAction.mq4>

void ExecuteCommand(const int id)
{
   int action = GetCommandAction(id);
   if (action < 0)
   {
      return;
   }

   if (action == COMMAND_ACTION_CREATE)
   {
      string error;
      if (!ExecuteOpenCommand(id, error))
      {
         Print("Failed to execute the command: " + error);
      }
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

// Commands

double GetRate(const int id, bool isBuy, TradingCalculator* calc)
{
   switch (GetCommandRateType(id))
   {
      case RATE_TYPE_ABSOLUTE:
         {
            return GetCommandRate(id);
         }
      case RATE_TYPE_PIPS:
         {
            double basePrice = isBuy ? calc.GetAsk() : calc.GetBid();
            return basePrice + GetCommandRate(id) * calc.GetPipSize();
         }
      case RATE_TYPE_NONE:
         {
            return isBuy ? calc.GetAsk() : calc.GetBid();
         }
      default:
         {
            Print("Unknown rate type");
            return 0;
         }
   }
}

bool ExecuteOpenCommand(const int id, string& error)
{
   string symbol = GetCommandSymbolEx(id);
   if (symbol == "")
   {
      error = "Symbol required";
      return false;
   }
   int side = GetCommandOrderSide(id);
   if (side < 0)
   {
      error = "Order side required";
      return false;
   }
      
   TradingCalculator *calc = TradingCalculator::Create(symbol);
   if (calc == NULL)
   {
      error = "Failed to execute a command: Unknown symbol";
      return false;
   }
   bool isBuy = side == 0;
   IMoneyManagementStrategy *moneyManagement = CreateMoneyManagementStrategy(calc, 
      symbol, 
      PERIOD_M1, 
      isBuy,
      GetAmountType(id),
      GetCommandAmount(id),
      ToStopLossType(GetCommandStopLossType(id)), 
      GetCommandStopLossValue(id),
      0,
      ToTakeProfitType(GetCommandTakeProfitType(id)), 
      GetCommandTakeProfitValue(id),
      0);

   double entryPrice = GetRate(id, isBuy, calc);
   double amount, stopLoss, takeProfit;
   moneyManagement.Get(0, entryPrice, amount, stopLoss, takeProfit);
   if (amount == 0.0)
   {
      delete moneyManagement;
      delete calc;
      error = "Invalid amount";
      return false;
   }

   string commandId = GetCommandOrderId(id);
   int orderid;
   CommandOrderType orderType = ToOrderType(GetCommandOrderType(id));
   switch (orderType)
   {
      case OrderTypeUndefined:
      case OrderTypeMarket:
         {
            MarketOrderBuilder *orderBuilder = new MarketOrderBuilder(_actions);
            orderBuilder
               .SetSide(isBuy ? BuySide : SellSide)
               .SetInstrument(symbol)
               .SetAmount(amount)
               .SetSlippage(Slippage)
               .SetMagicNumber(MagicNumber)
               .SetStopLoss(stopLoss)
               .SetTakeProfit(takeProfit)
               .SetComment(commandId);

            orderid = orderBuilder.Execute(error);
            delete orderBuilder;
         }
         break;
      case OrderTypeLimit:
      case OrderTypeStop:
         {
            OrderBuilder *orderBuilder = new OrderBuilder(_actions);
            orderBuilder
               .SetSide(isBuy ? BuySide : SellSide)
               .SetOrderType(isBuy ? (orderType == OrderTypeLimit ? OP_BUYLIMIT : OP_BUYSTOP) : (orderType == OrderTypeLimit ? OP_SELLLIMIT : OP_SELLSTOP))
               .SetRate(entryPrice)
               .SetInstrument(symbol)
               .SetAmount(amount)
               .SetSlippage(Slippage)
               .SetMagicNumber(MagicNumber)
               .SetStopLoss(stopLoss)
               .SetTakeProfit(takeProfit)
               .SetComment(commandId);

            orderid = orderBuilder.Execute(error);
            delete orderBuilder;
         }
         break;
   }
   delete moneyManagement;

   if (orderid > 0 && OrderSelect(orderid, SELECT_BY_TICKET, MODE_TRADES))
   {
      IOrder *order = new OrderByTicketId(orderid);
      if (GetCommandBreakevenType(id) == BREAKEVEN_ENABLED)
      {
         double basePrice = OrderOpenPrice();
         double target = calc.CalculateTakeProfit(isBuy, GetCommandBreakevenTo(id), StopLimitPips, OrderLots(), basePrice);
         double trigger = calc.CalculateTakeProfit(isBuy, GetCommandBreakevenWhen(id), StopLimitPips, OrderLots(), basePrice);
         
         HitProfitCondition* condition = new HitProfitCondition();
         condition.Set(order, trigger);
         IAction* action = new MoveToBreakevenAction(target, "", order);
         _actions.AddActionOnCondition(action, condition);
         condition.Release();
         action.Release();
      }
      if (GetCommandTrailingType(id) == TRAILING_DELAYED)
      {
         double trailingWhen = GetCommandTrailingWhen(id);
         double trailingStep = GetCommandTrailingStep(id);
         double stopDistance = MathAbs(OrderOpenPrice() - stopLoss) / calc.GetPipSize();

         TrailingPipsAction* action = new TrailingPipsAction(order, stopDistance, trailingStep);
         ProfitInRangeCondition* condition = new ProfitInRangeCondition(order, trailingWhen, 100000);
         _actions.AddActionOnCondition(action, condition);
         condition.Release();
         action.Release();
      }
      int lifetime = GetCommandLifetime(id);
      if (lifetime > 0)
      {
         CloseOrderAction* action = new CloseOrderAction(orderid, Slippage);
         OrderEOLCondition* condition = new OrderEOLCondition(order, lifetime);
         _actions.AddActionOnCondition(action, condition);
         condition.Release();
         action.Release();
      }
      int cancelAfter = GetCommandCancelAfter(id);
      if (cancelAfter > 0)
      {
         DeletePendingOrderAction* action = new DeletePendingOrderAction(orderid, Slippage);
         OrderEOLCondition* condition = new OrderEOLCondition(order, cancelAfter);
         _actions.AddActionOnCondition(action, condition);
         condition.Release();
         action.Release();
      }
      order.Release();
   }
   delete calc;
   return orderid > 0;
}

void ExecuteChangeCommand(const int id)
{
   string commandId = GetCommandOrderId(id);
   OrdersIterator it;
   int ticketId = it.WhenComment(commandId).First();
   if (ticketId == -1)
   {
      Print("Order with id " + commandId + " not found");
      return;
   }

   double amount = OrderLots();
   double entryPrice = OrderOpenPrice();
   bool isBuy = TradingCalculator::IsBuyOrder();
   double initialStopLoss = OrderStopLoss();
   double initialTakeProfit = OrderTakeProfit();
   
   TradingCalculator *calc = TradingCalculator::Create(OrderSymbol());
   if (calc == NULL)
   {
      Print("Failed to execute a command: Unknown symbol");
      return;
   }
   StopLossType stopLossType = ToStopLossType(GetCommandStopLossType(id));
   TakeProfitType takeProfitType = ToTakeProfitType(GetCommandTakeProfitType(id));
   IMoneyManagementStrategy *moneyManagement = CreateMoneyManagementStrategy(calc, 
      OrderSymbol(), 
      PERIOD_M1, 
      isBuy,
      PositionSizeContract,
      amount,
      stopLossType, 
      GetCommandStopLossValue(id),
      0,
      takeProfitType, 
      GetCommandTakeProfitValue(id),
      0);
   double _;
   double stopLoss;
   double takeProfit;
   moneyManagement.Get(0, entryPrice, _, stopLoss, takeProfit);
   delete moneyManagement;
   delete calc;

   if (stopLossType == SLDoNotUse)
   {
      stopLoss = initialStopLoss;
   }
   if (takeProfitType == TPDoNotUse)
   {
      takeProfit = initialTakeProfit;
   }
   
   string error;
   if (!TradingCommands::MoveSLTP(ticketId, stopLoss, takeProfit, error))
   {
      Print(error);
   }
}

void ExecuteCloseCommand(const int id)
{
   OrdersIterator it();
   string symbol = GetCommandSymbolEx(id);
   if (symbol != "")
   {
      it.WhenSymbol(symbol);
   }
   int orderSide = GetCommandOrderSide(id);
   if (orderSide != ORDER_SIDE_NOT_SET)
   {
      it.WhenSide(orderSide == ORDER_SIDE_LONG ? BuySide : SellSide);
   }
   if (GetCommandAmountType(id) == AMOUNT_NOT_SET)
   {
      TradingCommands::CloseTrades(it.WhenTrade(), Slippage);
   }
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

// Commands [end]

void ClosePositions(OrdersIterator &it, const double amountToClose)
{
   double remainingToClose = amountToClose;
   while (remainingToClose > 0 && it.Next())
   {
      double positionAmount = OrderLots();
      if (remainingToClose >= positionAmount)
      {
         string error;
         if (TradingCommands::CloseCurrentOrder(Slippage, error))
            remainingToClose -= positionAmount;
         else
            Print("Failed to close a position: " + error);
      }
      else
      {
         //TODO: partial close
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

StopLossType ToStopLossType(const int type)
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

TakeProfitType ToTakeProfitType(const int type)
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

enum CommandOrderType
{
   OrderTypeUndefined,
   OrderTypeMarket,
   OrderTypeLimit,
   OrderTypeStop
};
CommandOrderType ToOrderType(const int type)
{
   switch (type)
   {
      case ORDER_TYPE_MARKET:
         return OrderTypeMarket;
      case ORDER_TYPE_LIMIT:
         return OrderTypeLimit;
      case ORDER_TYPE_STOP:
         return OrderTypeStop;
   }
   return OrderTypeUndefined;
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
   _actions.DoLogic(0, 0);
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

ActionOnConditionLogic* _actions;
bool connect_sent = false;

void DoConnect()
{
   StartListener(Key, Server);
   connect_sent = true;
}

int OnInit()
{
   if (!IsDllsAllowed())
   {
      Alert("Error: Dll calls must be allowed!");
      return INIT_FAILED;
   }

   _actions = new ActionOnConditionLogic();
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
   delete _actions;
   _actions = NULL;
}

void OnTimer()
{
   ExecuteCommands();
}

void OnTick()
{
   ExecuteCommands();
}
