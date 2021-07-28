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

enum OrderSide
{
   BuySide,
   SellSide
};

// Trades monitor v.1.1

#ifndef TradingMonitor_IMP
// Trades iterator v 1.1
#ifndef TradesIterator_IMP
enum CompareType
{
   CompareLessThan
};

class TradesIterator
{
   bool _useMagicNumber;
   int _magicNumber;
   int _orderType;
   bool _useSide;
   bool _isBuySide;
   int _lastIndex;
   bool _useSymbol;
   string _symbol;
   bool _useProfit;
   double _profit;
   CompareType _profitCompare;
public:
   TradesIterator()
   {
      _useMagicNumber = false;
      _useSide = false;
      _lastIndex = INT_MIN;
      _useSymbol = false;
      _useProfit = false;
   }

   void WhenSymbol(const string symbol)
   {
      _useSymbol = true;
      _symbol = symbol;
   }

   void WhenProfit(const double profit, const CompareType compare)
   {
      _useProfit = true;
      _profit = profit;
      _profitCompare = compare;
   }

   void WhenSide(const bool isBuy)
   {
      _useSide = true;
      _isBuySide = isBuy;
   }

   void WhenMagicNumber(const int magicNumber)
   {
      _useMagicNumber = true;
      _magicNumber = magicNumber;
   }
   
   ulong GetTicket() { return PositionGetTicket(_lastIndex); }
   double GetOpenPrice() { return PositionGetDouble(POSITION_PRICE_OPEN); }
   double GetStopLoss() { return PositionGetDouble(POSITION_SL); }
   double GetTakeProfit() { return PositionGetDouble(POSITION_TP); }
   ENUM_POSITION_TYPE GetPositionType() { return (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE); }

   int Count()
   {
      int count = 0;
      for (int i = PositionsTotal() - 1; i >= 0; i--)
      {
         ulong ticket = PositionGetTicket(i);
         if (PositionSelectByTicket(ticket) && PassFilter(i))
         {
            count++;
         }
      }
      return count;
   }

   bool Next()
   {
      if (_lastIndex == INT_MIN)
      {
         _lastIndex = PositionsTotal() - 1;
      }
      else
         _lastIndex = _lastIndex - 1;
      while (_lastIndex >= 0)
      {
         ulong ticket = PositionGetTicket(_lastIndex);
         if (PositionSelectByTicket(ticket) && PassFilter(_lastIndex))
            return true;
         _lastIndex = _lastIndex - 1;
      }
      return false;
   }

   bool Any()
   {
      for (int i = PositionsTotal() - 1; i >= 0; i--)
      {
         ulong ticket = PositionGetTicket(i);
         if (PositionSelectByTicket(ticket) && PassFilter(i))
         {
            return true;
         }
      }
      return false;
   }

private:
   bool PassFilter(const int index)
   {
      if (_useMagicNumber && PositionGetInteger(POSITION_MAGIC) != _magicNumber)
         return false;
      if (_useSymbol && PositionGetSymbol(index) != _symbol)
         return false;
      if (_useProfit)
      {
         switch (_profitCompare)
         {
            case CompareLessThan:
               if (PositionGetDouble(POSITION_PROFIT) >= _profit)
                  return false;
               break;
         }
      }
      if (_useSide)
      {
         ENUM_POSITION_TYPE positionType = GetPositionType();
         if (_isBuySide && positionType != POSITION_TYPE_BUY)
            return false;
         if (!_isBuySide && positionType != POSITION_TYPE_SELL)
            return false;
      }
      return true;
   }
};
#define TradesIterator_IMP
#endif
// Orders iterator v 1.9
#ifndef OrdersIterator_IMP

class OrdersIterator
{
   bool _useMagicNumber;
   int _magicNumber;
   bool _useOrderType;
   ENUM_ORDER_TYPE _orderType;
   bool _useSide;
   bool _isBuySide;
   int _lastIndex;
   bool _useSymbol;
   string _symbol;
   bool _usePendingOrder;
   bool _pendingOrder;
   bool _useComment;
   string _comment;
   CompareType _profitCompare;
public:
   OrdersIterator()
   {
      _useOrderType = false;
      _useMagicNumber = false;
      _usePendingOrder = false;
      _pendingOrder = false;
      _useSide = false;
      _lastIndex = INT_MIN;
      _useSymbol = false;
      _useComment = false;
   }

   OrdersIterator *WhenPendingOrder()
   {
      _usePendingOrder = true;
      _pendingOrder = true;
      return &this;
   }

   OrdersIterator *WhenSymbol(const string symbol)
   {
      _useSymbol = true;
      _symbol = symbol;
      return &this;
   }

   OrdersIterator *WhenSide(const OrderSide side)
   {
      _useSide = true;
      _isBuySide = side == BuySide;
      return &this;
   }

   OrdersIterator *WhenOrderType(const ENUM_ORDER_TYPE orderType)
   {
      _useOrderType = true;
      _orderType = orderType;
      return &this;
   }

   OrdersIterator *WhenMagicNumber(const int magicNumber)
   {
      _useMagicNumber = true;
      _magicNumber = magicNumber;
      return &this;
   }

   OrdersIterator *WhenComment(const string comment)
   {
      _useComment = true;
      _comment = comment;
      return &this;
   }

   long GetMagicNumger() { return OrderGetInteger(ORDER_MAGIC); }
   ENUM_ORDER_TYPE GetType() { return (ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE); }
   string GetSymbol() { return OrderGetString(ORDER_SYMBOL); }
   ulong GetTicket() { return OrderGetTicket(_lastIndex); }
   double GetOpenPrice() { return OrderGetDouble(ORDER_PRICE_OPEN); }
   double GetStopLoss() { return OrderGetDouble(ORDER_SL); }
   double GetTakeProfit() { return OrderGetDouble(ORDER_TP); }

   int Count()
   {
      int count = 0;
      for (int i = OrdersTotal() - 1; i >= 0; i--)
      {
         ulong ticket = OrderGetTicket(i);
         if (OrderSelect(ticket) && PassFilter())
            count++;
      }
      return count;
   }

   bool Next()
   {
      if (_lastIndex == INT_MIN)
         _lastIndex = OrdersTotal() - 1;
      else
         _lastIndex = _lastIndex - 1;
      while (_lastIndex >= 0)
      {
         ulong ticket = OrderGetTicket(_lastIndex);
         if (OrderSelect(ticket) && PassFilter())
            return true;
         _lastIndex = _lastIndex - 1;
      }
      return false;
   }

   bool Any()
   {
      for (int i = OrdersTotal() - 1; i >= 0; i--)
      {
         ulong ticket = OrderGetTicket(i);
         if (OrderSelect(ticket) && PassFilter())
            return true;
      }
      return false;
   }

   ulong First()
   {
      for (int i = OrdersTotal() - 1; i >= 0; i--)
      {
         ulong ticket = OrderGetTicket(i);
         if (OrderSelect(ticket) && PassFilter())
            return ticket;
      }
      return -1;
   }

private:
   bool PassFilter()
   {
      if (_useMagicNumber && GetMagicNumger() != _magicNumber)
         return false;
      if (_useOrderType && GetType() != _orderType)
         return false;
      if (_useSymbol && OrderGetString(ORDER_SYMBOL) != _symbol)
         return false;
      if (_usePendingOrder && !IsPendingOrder())
         return false;
      if (_useComment && OrderGetString(ORDER_COMMENT) != _comment)
         return false;
      return true;
   }

   bool IsPendingOrder()
   {
      switch (GetType())
      {
         case ORDER_TYPE_BUY_LIMIT:
         case ORDER_TYPE_BUY_STOP:
         case ORDER_TYPE_BUY_STOP_LIMIT:
         case ORDER_TYPE_SELL_LIMIT:
         case ORDER_TYPE_SELL_STOP:
         case ORDER_TYPE_SELL_STOP_LIMIT:
            return true;
      }
      return false;
   }
};
#define OrdersIterator_IMP
#endif
// Closed trades iterator v 1.0
#ifndef ClosedTradesIterator_IMP
class ClosedTradesIterator
{
   int _lastIndex;
   int _total;
   ulong _currentTicket;
public:
   ClosedTradesIterator()
   {
      _lastIndex = INT_MIN;
   }
   
   ulong GetTicket() { return _currentTicket; }
   ENUM_ORDER_TYPE GetPositionType() { return (ENUM_ORDER_TYPE)HistoryOrderGetInteger(_currentTicket, ORDER_TYPE); }

   int Count()
   {
      int count = 0;
      for (int i = 0; i < Total(); i--)
      {
         _currentTicket = HistoryDealGetTicket(i);
         if (PassFilter(i))
         {
            count++;
         }
      }
      return count;
   }

   bool Next()
   {
      _total = Total();
      if (_lastIndex == INT_MIN)
         _lastIndex = 0;
      else
         ++_lastIndex;
      while (_lastIndex != _total)
      {
         _total = Total();
         _currentTicket = HistoryDealGetTicket(_lastIndex);
         if (PassFilter(_lastIndex))
            return true;
         ++_lastIndex;
      }
      return false;
   }

   bool Any()
   {
      for (int i = 0; i < Total(); i++)
      {
         _currentTicket = HistoryDealGetTicket(i);
         if (PassFilter(i))
         {
            return true;
         }
      }
      return false;
   }

private:
   int Total()
   {
      bool res = HistorySelect(0, TimeCurrent());
      return HistoryDealsTotal();
   }

   bool PassFilter(const int index)
   {
      long entry = HistoryDealGetInteger(_currentTicket, DEAL_ENTRY);
      if (entry != DEAL_ENTRY_OUT)
         return false;
      return true;
   }
};
#define ClosedTradesIterator_IMP
#endif
// Action v1.0

#ifndef IAction_IMP

interface IAction
{
public:
   virtual void AddRef() = 0;
   virtual void Release() = 0;
   
   virtual bool DoAction() = 0;
};
#define IAction_IMP
#endif

// AAction v1.0

#ifndef AAction_IMP

class AAction : public IAction
{
protected:
   int _references;
   AAction()
   {
      _references = 1;
   }
public:
   void AddRef()
   {
      ++_references;
   }

   void Release()
   {
      --_references;
      if (_references == 0)
         delete &this;
   }
};

#define AAction_IMP

#endif

class ITicketTarget
{
public:
   virtual void SetTicket(ulong ticket) = 0;
};

class TicketTarget : public ITicketTarget
{
   ulong _ticket;
public:
   virtual void SetTicket(ulong ticket)
   {
      _ticket = ticket;
   }
   
   ulong GetTicket()
   {
      return _ticket;
   }   
};

class ClosedTradeAction : public AAction
{
   TicketTarget* _ticket;
public:
   ClosedTradeAction(TicketTarget* ticket)
   {
      _ticket = ticket;
   }
   
   ~ClosedTradeAction()
   {
      delete _ticket;
   }
   
   virtual bool DoAction()
   {
      double volume = HistoryDealGetDouble(_ticket.GetTicket(), DEAL_VOLUME);
      string command = "quantity=" + DoubleToString(volume) 
         + " action=close order-id=" + IntegerToString(_ticket.GetTicket());
      AdvancedAlert(Advanced_Key, command, "", "");
      return false;
   }
};

class NewTradeAction : public AAction
{
public:
   virtual bool DoAction()
   {
      ulong orderType = PositionGetInteger(POSITION_TYPE);
      string command = "symbol=" + PositionGetString(POSITION_SYMBOL) 
         + " side=" + (orderType == POSITION_TYPE_BUY ? "B" : "S")
         + " order-id=" + IntegerToString(PositionGetInteger(POSITION_TICKET))
         + " quantity=" + DoubleToString(PositionGetDouble(POSITION_VOLUME));
      double tp = PositionGetDouble(POSITION_TP);
      if (tp != 0.0)
         command = command + " take-profit=" + DoubleToString(tp);
      double sl = PositionGetDouble(POSITION_SL);
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
         + " order-id=" + IntegerToString(PositionGetInteger(POSITION_TICKET))
         + " take-profit=" + DoubleToString(PositionGetDouble(POSITION_TP))
         + " stop-loss=" + DoubleToString(PositionGetDouble(POSITION_SL));
      AdvancedAlert(Advanced_Key, command, "", "");
      return false;
   }
};

#define TRADING_MONITOR_ORDER 0
#define TRADING_MONITOR_TRADE 1
#define TRADING_MONITOR_CLOSED_TRADE 2

class TradingMonitor
{
   ulong active_ticket[1000];
   double active_type[1000];
   double active_price[1000];
   double active_stoploss[1000];
   double active_takeprofit[1000];
   int active_order_type[1000];
   int active_total;
   IAction* _onClosedTrade;
   IAction* _onNewTrade;
   IAction* _onTradeChanged;
   ITicketTarget* _ticketTarget;
   bool _firstStart;
public:
   TradingMonitor()
   {
      active_total = 0;
      _onClosedTrade = NULL;
      _onNewTrade = NULL;
      _onTradeChanged = NULL;
      _ticketTarget = NULL;
      _firstStart = true;
   }

   ~TradingMonitor()
   {
      if (_onClosedTrade != NULL)
         _onClosedTrade.Release();
      if (_onNewTrade != NULL)
         _onNewTrade.Release();
      if (_onTradeChanged != NULL)
         _onTradeChanged.Release();
   }

   void SetOnClosedTrade(IAction* action, ITicketTarget* ticketTarget)
   {
      if (_onClosedTrade != NULL)
         _onClosedTrade.Release();
      _onClosedTrade = action;
      if (_onClosedTrade != NULL)
         _onClosedTrade.AddRef();
      _ticketTarget = ticketTarget;
   }

   void SetOnNewTrade(IAction* action)
   {
      if (_onNewTrade != NULL)
         _onNewTrade.Release();
      _onNewTrade = action;
      if (_onNewTrade != NULL)
         _onNewTrade.AddRef();
   }

   void SetOnTradeChanged(IAction* action)
   {
      if (_onTradeChanged != NULL)
         _onTradeChanged.Release();
      _onTradeChanged = action;
      if (_onTradeChanged != NULL)
         _onTradeChanged.AddRef();
   }

   void DoWork()
   {
      if (_firstStart)
      {
         updateActiveOrders();
         _firstStart = false;
         return;
      }
      bool changed = false;
      OrdersIterator orders;
      while (orders.Next())
      {
         ulong ticket = orders.GetTicket();
         int index = getOrderCacheIndex(ticket, TRADING_MONITOR_ORDER);
         if (index == -1)
         {
            changed = true;
            OnNewOrder();
         }
         else
         {
            if (orders.GetOpenPrice() != active_price[index] ||
                  orders.GetStopLoss() != active_stoploss[index] ||
                  orders.GetTakeProfit() != active_takeprofit[index] ||
                  orders.GetType() != active_type[index])
            {
               // already active order was changed
               changed = true;
               //messageChangedOrder(index);
            }
         }
      }
      TradesIterator it;
      while (it.Next())
      {
         ulong ticket = it.GetTicket();
         int index = getOrderCacheIndex(ticket, TRADING_MONITOR_TRADE);
         if (index == -1)
         {
            changed = true;
            if (_onNewTrade != NULL)
               // ignore result of DoAction
               _onNewTrade.DoAction();
         }
         else
         {
            if (it.GetStopLoss() != active_stoploss[index] ||
                  it.GetTakeProfit() != active_takeprofit[index])
            {
               if (_onTradeChanged != NULL)
                  // ignore result of DoAction
                  _onTradeChanged.DoAction();
               changed = true;
            }
         }
      }

      ClosedTradesIterator closedTrades;
      while (closedTrades.Next())
      {
         ulong ticket = closedTrades.GetTicket();
         int index = getOrderCacheIndex(ticket, TRADING_MONITOR_CLOSED_TRADE);
         if (index == -1)
         {
            changed = true;
            if (_onClosedTrade != NULL)
            {
               _ticketTarget.SetTicket(ticket);
               // ignore result of DoAction
               _onClosedTrade.DoAction();
            }
         }
      }

      if (changed)
         updateActiveOrders();
   }
private:
   int getOrderCacheIndex(const ulong ticket, int type)
   {
      for (int i = 0; i < active_total; i++)
      {
         if (active_ticket[i] == ticket && active_order_type[i] == type)
            return i;
      }
      return -1;
   }

   void updateActiveOrders()
   {
      active_total = 0;
      OrdersIterator orders;
      while (orders.Next())
      {
         active_ticket[active_total] = orders.GetTicket();
         active_type[active_total] = orders.GetType();
         active_price[active_total] = orders.GetOpenPrice();
         active_stoploss[active_total] = orders.GetStopLoss();
         active_takeprofit[active_total] = orders.GetTakeProfit();
         active_order_type[active_total] = TRADING_MONITOR_ORDER;
         ++active_total;
      }

      TradesIterator trades;
      while (trades.Next())
      {
         active_ticket[active_total] = trades.GetTicket();
         active_stoploss[active_total] = trades.GetStopLoss();
         active_takeprofit[active_total] = trades.GetTakeProfit();
         active_order_type[active_total] = TRADING_MONITOR_TRADE;
         ++active_total;
      }

      ClosedTradesIterator closedTrades;
      while (closedTrades.Next())
      {
         active_ticket[active_total] = closedTrades.GetTicket();
         active_order_type[active_total] = TRADING_MONITOR_CLOSED_TRADE;
         ++active_total;
      }
   }

   void OnNewOrder()
   {
      
   }
};

#define TradingMonitor_IMP

#endif
TradingMonitor* monitor;

void ExecuteCommands()
{
   monitor.DoWork();
}

int OnInit()
{
   IndicatorSetString(INDICATOR_SHORTNAME, "Trade Copy Source");

   monitor = new TradingMonitor();

   TicketTarget* ticketTarget = new TicketTarget();
   ClosedTradeAction* closedTradeAction = new ClosedTradeAction(ticketTarget);
   monitor.SetOnClosedTrade(closedTradeAction, ticketTarget);
   closedTradeAction.Release();

   NewTradeAction* newTradeAction = new NewTradeAction();
   monitor.SetOnNewTrade(newTradeAction);
   newTradeAction.Release();

   TradeChangedAction* tradeChangedAction = new TradeChangedAction();
   monitor.SetOnTradeChanged(tradeChangedAction);
   tradeChangedAction.Release();

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
