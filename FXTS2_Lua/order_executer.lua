local STRATEGY_NAME = "ProfitRobots Order Executer";
local STRATEGY_VERSION = "3";

local Modules = {};

function Init()
    strategy:name(STRATEGY_NAME .. " v" .. STRATEGY_VERSION);
    strategy:description("");
    strategy:type(core.Both);
    strategy:setTag("Version", STRATEGY_VERSION);
    strategy:setTag("NonOptimizableParameters", "StartTime,StopTime,ToTime,signaler_ToTime,signaler_show_alert,signaler_play_soundsignaler_sound_file,signaler_recurrent_sound,signaler_send_email,signaler_email,signaler_show_popup,signaler_debug_alert,use_advanced_alert,advanced_alert_key");

    strategy.parameters:addBoolean("allow_trade", "Allow strategy to trade", "", true);
    strategy.parameters:setFlag("allow_trade", core.FLAG_ALLOW_TRADE);
    strategy.parameters:addString("account", "Account to trade on", "", "");
    strategy.parameters:setFlag("account", core.FLAG_ACCOUNT);
    strategy.parameters:addString("key", "Key", "", "");
    strategy.parameters:addInteger("server", "Server", "", 4);
    strategy.parameters:addIntegerAlternative("server", "ProfitRobots.com", "", 4);
    strategy.parameters:addIntegerAlternative("server", "Self-hosted", "", 1);
end
local allow_trade, account;
local TIMER_ID = 1;
local Constants;
local started = false;
function Prepare(name_only)
    for _, module in pairs(Modules) do module:Prepare(nameOnly); end
    account = instance.parameters.account;
    allow_trade = instance.parameters.allow_trade;

    instance:name(profile:id() .. "(" .. instance.bid:name() ..  ")");
    if name_only then return ; end

    core.host:execute("setTimer", TIMER_ID, 1);
    require("AdvancedNotifications");
    require("CommandExecuter");
    Constants = CommandExecuter.Constants();
end

function ExtUpdate(id, source, period) for _, module in pairs(Modules) do if module.ExtUpdate ~= nil then module:ExtUpdate(id, source, period); end end end
function ReleaseInstance() 
    for _, module in pairs(Modules) do if module.ReleaseInstance ~= nil then module:ReleaseInstance(); end end 
    if started then
        AdvancedNotifications.StopListener();
    end
end

function ExecuteCommand(command)
    if command.Action == Constants.ACTION_CREATE then
        ExecuteOpenCommand(command);
    elseif command.Action == Constants.ACTION_CHANGE then
        ExecuteChangeCommand(command);
    elseif command.Action == Constants.ACTION_CLOSE then
        ExecuteCloseCommand(command);
    else
    end
end

function FindOffer(symbol)
    symbol = string.upper(symbol);
    local enum = core.host:findTable("offers"):enumerator();
    local row = enum:next();
    while row ~= nil do
        local instrument = row.Instrument:upper();
        if instrument == symbol then
            return row;
        end
        local index = string.find(instrument, "/");
        if index ~= nil then
            local instrumentAlt = string.gsub(instrument, "/", "");
            if instrumentAlt == symbol then
                return row;
            end
        end
        row = enum:next();
    end
end

function ExecuteCloseCommand(command)
    local offer;
    if command.Symbol ~= nil then
        offer = FindOffer(command.Symbol);
        assert(offer ~= nil, command.Symbol .. " not found");
    end
    local findCommand = trading:FindTrade();
    if offer ~= nil then
        findCommand:WhenInstrument(offer.Instrument);
    end
    if command.OrderSide ~= nil then
        findCommand:WhenSide(command.OrderSide == Constants.ORDER_SIDE_LONG and "B" or "S");
    end

    if command.AmountType == Constants.AMOUNT_NOT_SET then
        findCommand:Do(function (trade) trading:Close(trade) end)
    elseif command.AmountType == Constants.AMOUNT_CONTRACTS then
        local closedAmount = 0;
        findCommand:Do(
            function (trade)
                if closedAmount >= command.Amount then
                    return;
                end
                if trade.AmountK <= (command.Amount - closedAmount) then
                    trading:Close(trade);
                else
                    assert(false, "Partial close is not implemented yet");
                end
                closedAmount = closedAmount + trade.AmountK;
            end
        );
    else
        assert(false, "This amount type is not supported yet");
    end
end

function ExecuteOpenCommand(command)
    local offer = FindOffer(command.Symbol);
    assert(offer ~= nil, command.Symbol .. " not found");

    local openCommand = trading:MarketOrder(offer.Instrument);
    openCommand:SetSide(command.OrderSide == Constants.ORDER_SIDE_LONG and "B" or "S")
        :SetAccountID(account);
    
    assert(command.AmountType == Constants.AMOUNT_CONTRACTS, "Only contracts supported as a position size");
    openCommand:SetAmount(command.Amount);

    if command.StopLossType == Constants.SL_ABOSOLUTE then
        openCommand:SetStop(command.StopLossValue);
    elseif command.StopLossType == Constants.SL_PIPS then
        openCommand:SetPipStop(nil, command.StopLossValue);
    end
    if command.TakeProfitType == Constants.SL_ABOSOLUTE then
        openCommand:SetLimit(command.TakeProfitValue);
    elseif command.TakeProfitType == Constants.SL_PIPS then
        openCommand:SetPipLimit(nil, command.TakeProfitValue);
    end

    if command.OrderId ~= nil then
        openCommand:SetCustomID(command.OrderId);
    end

    local result = openCommand:Execute();
    if result.Finished and not result.Success then
        core.host:trace(result.Error);
    else
        if command.BreakevenType == Constants.BREAKEVEN_ENABLED then
            local controller = breakeven:CreateBreakeven()
                :SetRequestID(result.RequestID)
                :SetWhen(command.BreakevenWhen)
                :SetTo(command.BreakevenTo);
        end

        if command.TrailingType == Constants.TRAILING_DELAYED then
            assert(command.StopLossType == Constants.SL_PIPS, "Only pips stop loss are supported for the trailing");
            local controller = breakeven:CreateBreakeven()
                :SetRequestID(result.RequestID)
                :SetWhen(command.TrailingWhen)
                :SetTo(command.StopLossValue)
                :SetTrailing(command.TrailingStep);
        end
    end
end

function ExecuteChangeCommand(command)
    local trade = trading:FindTrade():WhenCustomID(command.OrderId):First();
    if trade == nil then
        return;
    end

    if command.StopLossType == Constants.SL_ABOSOLUTE then
        trading:MoveStop(trade, command.StopLossValue);
    elseif command.StopLossType == Constants.SL_PIPS then
        local offer = core.host:findTable("offers"):find("Instrument", trade.Instrument);
        local stop;
        if trade.BS == "B" then
            stop = trade.Open - command.StopLossValue * offer.PointSize;
        else
            stop = trade.Open + command.StopLossValue * offer.PointSize;
        end
        trading:MoveStop(trade, stop);
    end

    if command.TakeProfitType == Constants.SL_ABOSOLUTE then
        trading:MoveLimit(trade, command.TakeProfitValue);
    elseif command.TakeProfitType == Constants.SL_PIPS then
        local offer = core.host:findTable("offers"):find("Instrument", trade.Instrument);
        local limit;
        if trade.BS == "B" then
            limit = trade.Open + command.StopLossValue * offer.PointSize;
        else
            limit = trade.Open - command.StopLossValue * offer.PointSize;
        end
        trading:MoveLimit(trade, limit);
    end
end

function ExtAsyncOperationFinished(cookie, success, message, message1, message2)
    for _, module in pairs(Modules) do if module.AsyncOperationFinished ~= nil then module:AsyncOperationFinished(cookie, success, message, message1, message2); end end
    if cookie == TIMER_ID then
        local status = AdvancedNotifications.ListenerStatus();
        if not started then
            if status ~= 0 then
                return;
            end
            local res = AdvancedNotifications.StartListener(instance.parameters.key, instance.parameters.server);
            started = true;
            return;
        end
        if status ~= last_status then
            core.host:trace("status " .. status);
            last_status = status;
        end
        local logMessage = AdvancedNotifications.PopLogMessage();
        while logMessage ~= "" do
            core.host:trace(logMessage);
            logMessage = AdvancedNotifications.PopLogMessage();
        end
        local message = AdvancedNotifications.GetNextMessage();
        while message ~= "" do
            if allow_trade then
                core.host:trace("Executing command: " .. message)
                local success, exception = pcall(function ()
                    local command = CommandExecuter.ParseCommand(message);
                    ExecuteCommand(command);
                end);
                if not success then
                    core.host:trace("Error whiile executing command: " .. exception);
                end
            else
                core.host:trace("Command recieved: " .. message)
            end
            message = AdvancedNotifications.GetNextMessage();
        end
    end
end

dofile(core.app_path() .. "\\strategies\\standard\\include\\helper.lua");

trading = {};
trading.Name = "Trading";
trading.Version = "4.21";
trading.Debug = false;
trading.AddAmountParameter = true;
trading.AddStopParameter = true;
trading.AddLimitParameter = true;
trading.AddBreakevenParameters = true;
trading._ids_start = nil;
trading._signaler = nil;
trading._account = nil;
trading._all_modules = {};
trading._request_id = {};
trading._waiting_requests = {};
trading._used_stop_orders = {};
trading._used_limit_orders = {};
function trading:trace(str) if not self.Debug then return; end core.host:trace(self.Name .. ": " .. str); end
function trading:RegisterModule(modules) for _, module in pairs(modules) do self:OnNewModule(module); module:OnNewModule(self); end modules[#modules + 1] = self; self._ids_start = (#modules) * 100; end

function trading:AddPositionParameters(parameters, id)
    if self.AddAmountParameter then
        parameters:addInteger("amount" .. id, "Trade Amount in Lots", "", 1);
    end
    if CreateStopParameters == nil or not CreateStopParameters(parameters, id) then
        parameters:addString("stop_type" .. id, "Stop Order", "", "no");
        parameters:addStringAlternative("stop_type" .. id, "No stop", "", "no");
        parameters:addStringAlternative("stop_type" .. id, "In Pips", "", "pips");
        parameters:addStringAlternative("stop_type" .. id, "ATR", "", "atr");
        parameters:addDouble("stop" .. id, "Stop Value", "In pips or ATR period", 30);
        parameters:addDouble("atr_stop_mult" .. id, "ATR Stop Multiplicator", "", 2.0);
        parameters:addBoolean("use_trailing" .. id, "Trailing stop order", "", false);
        parameters:addInteger("trailing" .. id, "Trailing in pips", "Use 1 for dynamic and 10 or greater for the fixed trailing", 1);
    end
    if CreateLimitParameters ~= nil then
        CreateLimitParameters(parameters, id);
    else
        parameters:addString("limit_type" .. id, "Limit Order", "", "no");
        parameters:addStringAlternative("limit_type" .. id, "No limit", "", "no");
        parameters:addStringAlternative("limit_type" .. id, "In Pips", "", "pips");
        parameters:addStringAlternative("limit_type" .. id, "ATR", "", "atr");
        parameters:addStringAlternative("limit_type" .. id, "Multiplicator of stop", "", "stop");
        parameters:addDouble("limit" .. id, "Limit Value", "In pips or ATR period", 30);
        parameters:addDouble("atr_limit_mult" .. id, "ATR Limit Multiplicator", "", 2.0);
        parameters:addString("TRAILING_LIMIT_TYPE" .. id, "Trailing Limit", "", "Off");
        parameters:addStringAlternative("TRAILING_LIMIT_TYPE" .. id, "Off", "", "Off");
        parameters:addStringAlternative("TRAILING_LIMIT_TYPE" .. id, "Favorable", "moves limit up for long/buy positions, vice versa for short/sell", "Favorable");
        parameters:addStringAlternative("TRAILING_LIMIT_TYPE" .. id, "Unfavorable", "moves limit down for long/buy positions, vice versa for short/sell", "Unfavorable");
        parameters:addDouble("TRAILING_LIMIT_TRIGGER" .. id, "Trailing Limit Trigger in Pips", "", 0);
        parameters:addDouble("TRAILING_LIMIT_STEP" .. id, "Trailing Limit Step in Pips", "", 10);
    end
    if self.AddBreakevenParameters then
        parameters:addBoolean("use_breakeven" .. id, "Use Breakeven", "", false);
        parameters:addDouble("breakeven_when" .. id, "Breakeven Activation Value, in pips", "", 10);
        parameters:addDouble("breakeven_to" .. id, "Breakeven To, in pips", "", 0);
        parameters:addString("breakeven_trailing" .. id, "Trailing after breakeven", "", "default");
        parameters:addStringAlternative("breakeven_trailing" .. id, "Do not change", "", "default");
        parameters:addStringAlternative("breakeven_trailing" .. id, "Set trailing", "", "set");
        parameters:addBoolean("breakeven_close" .. id, "Partial close on breakeven", "", false);
        parameters:addDouble("breakeven_close_amount" .. id, "Partial close amount, %", "", 50);
    end
end

function trading:Init(parameters, count)
    parameters:addBoolean("allow_trade", "Allow strategy to trade", "", true);
    parameters:setFlag("allow_trade", core.FLAG_ALLOW_TRADE);
    parameters:addString("account", "Account to trade on", "", "");
    parameters:setFlag("account", core.FLAG_ACCOUNT);
    parameters:addString("allow_side", "Allow side", "", "both")
    parameters:addStringAlternative("allow_side", "Both", "", "both")
    parameters:addStringAlternative("allow_side", "Long/buy only", "", "buy")
    parameters:addStringAlternative("allow_side", "Short/sell only", "", "sell")
    parameters:addBoolean("close_on_opposite", "Close on Opposite", "", true);
    if ENFORCE_POSITION_CAP ~= true then
        parameters:addBoolean("position_cap", "Position Cap", "", false);
        parameters:addInteger("no_of_positions", "Max # of open positions", "", 1);
        parameters:addInteger("no_of_buy_position", "Max # of buy positions", "", 1);
        parameters:addInteger("no_of_sell_position", "Max # of sell positions", "", 1);
    end
    
    if count == nil or count == 1 then
        parameters:addGroup("Position");
        self:AddPositionParameters(parameters, "");
    else
        for i = 1, count do
            parameters:addGroup("Position #" .. i);
            parameters:addBoolean("use_position_" .. i, "Open position #" .. i, "", i == 1);
            self:AddPositionParameters(parameters, "_" .. i);
        end
    end
end

function trading:Prepare(name_only)
    if name_only then return; end
end

function trading:ExtUpdate(id, source, period)
end

function trading:OnNewModule(module)
    if module.Name == "Signaler" then self._signaler = module; end
    self._all_modules[#self._all_modules + 1] = module;
end

function trading:AsyncOperationFinished(cookie, success, message, message1, message2)
    local res = self._waiting_requests[cookie];
    if res ~= nil then
        res.Finished = true;
        res.Success = success;
        if not success then
            res.Error = message;
            if self._signaler ~= nil then
                self._signaler:Signal(res.Error);
            else
                self:trace(res.Error);
            end
        elseif res.OnSuccess ~= nil then
            res:OnSuccess();
        end
        self._waiting_requests[cookie] = nil;
    elseif cookie == self._order_update_id then
        for _, order in ipairs(self._monitored_orders) do
            if order.RequestID == message2 then
                order.FixStatus = message1;
            end
        end
    elseif cookie == self._ids_start + 2 then
        if not success then
            if self._signaler ~= nil then
                self._signaler:Signal("Close order failed: " .. message);
            else
                self:trace("Close order failed: " .. message);
            end
        end
    end
end

function trading:getOppositeSide(side) if side == "B" then return "S"; end return "B"; end

function trading:getId()
    for id = self._ids_start, self._ids_start + 100 do
        if self._waiting_requests[id] == nil then return id; end
    end
    return self._ids_start;
end

function trading:CreateStopOrder(trade, stop_rate, trailing)
    local valuemap = core.valuemap();
    valuemap.Command = "CreateOrder";
    valuemap.OfferID = trade.OfferID;
    valuemap.Rate = stop_rate;
    if trade.BS == "B" then
        valuemap.BuySell = "S";
    else
        valuemap.BuySell = "B";
    end

    local can_close = core.host:execute("getTradingProperty", "canCreateMarketClose", trade.Instrument, trade.AccountID);
    if can_close then
        valuemap.OrderType = "S";
        valuemap.AcctID  = trade.AccountID;
        valuemap.TradeID = trade.TradeID;
        valuemap.Quantity = trade.Lot;
        valuemap.TrailUpdatePips = trailing;
    else
        valuemap.OrderType = "SE"
        valuemap.AcctID  = trade.AccountID;
        valuemap.NetQtyFlag = "Y"
    end

    local id = self:getId();
    local success, msg = terminal:execute(id, valuemap);
    if not(success) then
        local message = "Failed create stop " .. msg;
        self:trace(message);
        if self._signaler ~= nil then
            self._signaler:Signal(message);
        end
        local res = {};
        res.Finished = true;
        res.Success = false;
        res.Error = message;
        return res;
    end
    local res = {};
    res.Finished = false;
    res.RequestID = msg;
    self._waiting_requests[id] = res;
    self._request_id[trade.TradeID] = msg;
    return res;
end

function trading:CreateLimitOrder(trade, limit_rate)
    local valuemap = core.valuemap();
    valuemap.Command = "CreateOrder";
    valuemap.OfferID = trade.OfferID;
    valuemap.Rate = limit_rate;
    if trade.BS == "B" then
        valuemap.BuySell = "S";
    else
        valuemap.BuySell = "B";
    end
    local can_close = core.host:execute("getTradingProperty", "canCreateMarketClose", trade.Instrument, trade.AccountID);
    if can_close then
        valuemap.OrderType = "L";
        valuemap.AcctID  = trade.AccountID;
        valuemap.TradeID = trade.TradeID;
        valuemap.Quantity = trade.Lot;
    else
        valuemap.OrderType = "LE"
        valuemap.AcctID  = trade.AccountID;
        valuemap.NetQtyFlag = "Y"
    end
    local success, msg = terminal:execute(200, valuemap);
    if not(success) then
        terminal:alertMessage(trade.Instrument, limit_rate, "Failed create limit " .. msg, core.now());
    else
        self._request_id[trade.TradeID] = msg;
    end
end

function trading:ChangeOrder(order, rate, trailing)
    local min_change = core.host:findTable("offers"):find("Instrument", order.Instrument).PointSize;
    if math.abs(rate - order.Rate) > min_change then
        self:trace(string.format("Changing an order to %s", tostring(rate)));
        -- stop exists
        local valuemap = core.valuemap();
        valuemap.Command = "EditOrder";
        valuemap.AcctID  = order.AccountID;
        valuemap.OrderID = order.OrderID;
        valuemap.TrailUpdatePips = trailing;
        valuemap.Rate = rate;
        local id = self:getId();
        local success, msg = terminal:execute(id, valuemap);
        if not(success) then
            local message = "Failed change order " .. msg;
            self:trace(message);
            if self._signaler ~= nil then
                self._signaler:Signal(message);
            end
            local res = {};
            res.Finished = true;
            res.Success = false;
            res.Error = message;
            return res;
        end
        local res = {};
        res.Finished = false;
        res.RequestID = msg;
        self._waiting_requests[id] = res;
        return res;
    end
    local res = {};
    res.Finished = true;
    res.Success = true;
    return res;
end

function trading:IsLimitOrderType(order_type) return order_type == "L" or order_type == "LE" or order_type == "LT" or order_type == "LTE"; end

function trading:IsStopOrderType(order_type) return order_type == "S" or order_type == "SE" or order_type == "ST" or order_type == "STE"; end

function trading:FindLimitOrder(trade)
    local can_close = core.host:execute("getTradingProperty", "canCreateMarketClose", trade.Instrument, trade.AccountID);
    if can_close then
        local order_id;
        if trade.LimitOrderID ~= nil and trade.LimitOrderID ~= "" then
            order_id = trade.LimitOrderID;
            self:trace("Using limit order id from the trade");
        elseif self._request_id[trade.TradeID] ~= nil then
            self:trace("Searching limit order by request id: " .. tostring(self._request_id[trade.TradeID]));
            local order = core.host:findTable("orders"):find("RequestID", self._request_id[trade.TradeID]);
            if order ~= nil then
                order_id = order.OrderID;
                self._request_id[trade.TradeID] = nil;
            end
        end
        -- Check that order is stil exist
        if order_id ~= nil then return core.host:findTable("orders"):find("OrderID", order_id); end
    else
        local enum = core.host:findTable("orders"):enumerator();
        local row = enum:next();
        while (row ~= nil) do
            if row.ContingencyType == 3 and IsLimitOrderType(row.Type) and self._used_limit_orders[row.OrderID] ~= true then
                self._used_limit_orders[row.OrderID] = true;
                return row;
            end
            row = enum:next();
        end
    end
    return nil;
end

function trading:FindStopOrder(trade)
    local can_close = core.host:execute("getTradingProperty", "canCreateMarketClose", trade.Instrument, trade.AccountID);
    if can_close then
        local order_id;
        if trade.StopOrderID ~= nil and trade.StopOrderID ~= "" then
            order_id = trade.StopOrderID;
            self:trace("Using stop order id from the trade");
        elseif self._request_id[trade.TradeID] ~= nil then
            self:trace("Searching stop order by request id: " .. tostring(self._request_id[trade.TradeID]));
            local order = core.host:findTable("orders"):find("RequestID", self._request_id[trade.TradeID]);
            if order ~= nil then
                order_id = order.OrderID;
                self._request_id[trade.TradeID] = nil;
            end
        end
        -- Check that order is stil exist
        if order_id ~= nil then return core.host:findTable("orders"):find("OrderID", order_id); end
    else
        local enum = core.host:findTable("orders"):enumerator();
        local row = enum:next();
        while (row ~= nil) do
            if row.ContingencyType == 3 and self:IsStopOrderType(row.Type) and self._used_stop_orders[row.OrderID] ~= true then
                self._used_stop_orders[row.OrderID] = true;
                return row;
            end
            row = enum:next();
        end
    end
    return nil;
end

function trading:MoveStop(trade, stop_rate, trailing)
    local order = self:FindStopOrder(trade);
    if order == nil then
        if trailing == 0 then
            trailing = nil;
        end
        return self:CreateStopOrder(trade, stop_rate, trailing);
    else
        if trailing == 0 then
            if order.TrlMinMove ~= 0 then
                trailing = order.TrlMinMove
            else
                trailing = nil;
            end
        end
        return self:ChangeOrder(order, stop_rate, trailing);
    end
end

function trading:MoveLimit(trade, limit_rate)
    self:trace("Searching for a limit");
    local order = self:FindLimitOrder(trade);
    if order == nil then
        self:trace("Limit order not found, creating a new one");
        return self:CreateLimitOrder(trade, limit_rate);
    else
        return self:ChangeOrder(order, limit_rate);
    end
end

function trading:RemoveStop(trade)
    self:trace("Searching for a stop");
    local order = self:FindStopOrder(trade);
    if order == nil then self:trace("No stop"); return nil; end
    self:trace("Deleting order");
    return self:DeleteOrder(order);
end

function trading:RemoveLimit(trade)
    self:trace("Searching for a limit");
    local order = self:FindLimitOrder(trade);
    if order == nil then self:trace("No limit"); return nil; end
    self:trace("Deleting order");
    return self:DeleteOrder(order);
end

function trading:DeleteOrder(order)
    self:trace(string.format("Deleting order %s", order.OrderID));
    local valuemap = core.valuemap();
    valuemap.Command = "DeleteOrder";
    valuemap.OrderID = order.OrderID;

    local id = self:getId();
    local success, msg = terminal:execute(id, valuemap);
    if not(success) then
        local message = "Delete order failed: " .. msg;
        self:trace(message);
        if self._signaler ~= nil then
            self._signaler:Signal(message);
        end
        local res = {};
        res.Finished = true;
        res.Success = false;
        res.Error = message;
        return res;
    end
    local res = {};
    res.Finished = false;
    res.RequestID = msg;
    self._waiting_requests[id] = res;
    return res;
end

function trading:GetCustomID(qtxt)
    if qtxt == nil then
        return nil;
    end
    local metadata = self:GetMetadata(qtxt);
    if metadata == nil then
        return qtxt;
    end
    return metadata.CustomID;
end

function trading:FindOrder()
    local search = {};
    function search:WhenCustomID(custom_id) self.CustomID = custom_id; return self; end
    function search:WhenSide(bs) self.Side = bs; return self; end
    function search:WhenInstrument(instrument) self.Instrument = instrument; return self; end
    function search:WhenAccountID(account_id) self.AccountID = account_id; return self; end
    function search:WhenRate(rate) self.Rate = rate; return self; end
    function search:WhenOrderType(orderType) self.OrderType = orderType; return self; end
    function search:Do(action)
        local enum = core.host:findTable("orders"):enumerator();
        local row = enum:next();
        local count = 0
        while (row ~= nil) do
            if self:PassFilter(row) then
                if action(row) then
                    count = count + 1;
                end
            end
            row = enum:next();
        end
        return count;
    end
    function search:Summ(action)
        local enum = core.host:findTable("orders"):enumerator();
        local row = enum:next();
        local summ = 0
        while (row ~= nil) do
            if self:PassFilter(row) then
                summ = summ + action(row);
            end
            row = enum:next();
        end
        return summ;
    end
    function search:PassFilter(row)
        return (row.Instrument == self.Instrument or not self.Instrument)
            and (row.BS == self.Side or not self.Side)
            and (row.AccountID == self.AccountID or not self.AccountID)
            and (trading:GetCustomID(row.QTXT) == self.CustomID or not self.CustomID)
            and (row.Rate == self.Rate or not self.Rate)
            and (row.Type == self.OrderType or not self.OrderType);
    end
    function search:All()
        local enum = core.host:findTable("orders"):enumerator();
        local row = enum:next();
        local orders = {};
        while (row ~= nil) do
            if self:PassFilter(row) then orders[#orders + 1] = row; end
            row = enum:next();
        end
        return orders;
    end
    function search:First()
        local enum = core.host:findTable("orders"):enumerator();
        local row = enum:next();
        while (row ~= nil) do
            if self:PassFilter(row) then return row; end
            row = enum:next();
        end
        return nil;
    end
    return search;
end

function trading:FindTrade()
    local search = {};
    function search:WhenCustomID(custom_id) self.CustomID = custom_id; return self; end
    function search:WhenSide(bs) self.Side = bs; return self; end
    function search:WhenInstrument(instrument) self.Instrument = instrument; return self; end
    function search:WhenAccountID(account_id) self.AccountID = account_id; return self; end
    function search:WhenOpen(open) self.Open = open; return self; end
    function search:WhenOpenOrderReqID(open_order_req_id) self.OpenOrderReqID = open_order_req_id; return self; end
    function search:Do(action)
        local enum = core.host:findTable("trades"):enumerator();
        local row = enum:next();
        local count = 0
        while (row ~= nil) do
            if self:PassFilter(row) then
                if action(row) then
                    count = count + 1;
                end
            end
            row = enum:next();
        end
        return count;
    end
    function search:Summ(action)
        local enum = core.host:findTable("trades"):enumerator();
        local row = enum:next();
        local summ = 0
        while (row ~= nil) do
            if self:PassFilter(row) then
                summ = summ + action(row);
            end
            row = enum:next();
        end
        return summ;
    end
    function search:PassFilter(row)
        return (row.Instrument == self.Instrument or not self.Instrument)
            and (row.BS == self.Side or not self.Side)
            and (row.AccountID == self.AccountID or not self.AccountID)
            and (trading:GetCustomID(row.QTXT) == self.CustomID or not self.CustomID)
            and (row.Open == self.Open or not self.Open)
            and (row.OpenOrderReqID == self.OpenOrderReqID or not self.OpenOrderReqID);
    end
    function search:All()
        local enum = core.host:findTable("trades"):enumerator();
        local row = enum:next();
        local trades = {};
        while (row ~= nil) do
            if self:PassFilter(row) then trades[#trades + 1] = row; end
            row = enum:next();
        end
        return trades;
    end
    function search:Any()
        local enum = core.host:findTable("trades"):enumerator();
        local row = enum:next();
        while (row ~= nil) do
            if self:PassFilter(row) then 
                return true;
            end
            row = enum:next();
        end
        return false;
    end
    function search:Count()
        local enum = core.host:findTable("trades"):enumerator();
        local row = enum:next();
        local count = 0;
        while (row ~= nil) do
            if self:PassFilter(row) then count = count + 1; end
            row = enum:next();
        end
        return count;
    end
    function search:First()
        local enum = core.host:findTable("trades"):enumerator();
        local row = enum:next();
        while (row ~= nil) do
            if self:PassFilter(row) then return row; end
            row = enum:next();
        end
        return nil;
    end
    return search;
end

function trading:FindClosedTrade()
    local search = {};
    function search:WhenCustomID(custom_id) self.CustomID = custom_id; return self; end
    function search:WhenSide(bs) self.Side = bs; return self; end
    function search:WhenInstrument(instrument) self.Instrument = instrument; return self; end
    function search:WhenAccountID(account_id) self.AccountID = account_id; return self; end
    function search:WhenOpenOrderReqID(open_order_req_id) self.OpenOrderReqID = open_order_req_id; return self; end
    function search:WhenTradeIDRemain(trade_id_remain) self.TradeIDRemain = trade_id_remain; return self; end
    function search:WhenCloseOrderID(close_order_id) self.CloseOrderID = close_order_id; return self; end
    function search:PassFilter(row)
        if self.TradeIDRemain ~= nil and row.TradeIDRemain ~= self.TradeIDRemain then return false; end
        if self.CloseOrderID ~= nil and row.CloseOrderID ~= self.CloseOrderID then return false; end
        return (row.Instrument == self.Instrument or not self.Instrument)
            and (row.BS == self.Side or not self.Side)
            and (row.AccountID == self.AccountID or not self.AccountID)
            and (trading:GetCustomID(row.QTXT) == self.CustomID or not self.CustomID)
            and (row.OpenOrderReqID == self.OpenOrderReqID or not self.OpenOrderReqID);
    end
    function search:Any()
        local enum = core.host:findTable("closed trades"):enumerator();
        local row = enum:next();
        while (row ~= nil) do
            if self:PassFilter(row) then
                return true;
            end
            row = enum:next();
        end
        return false;
    end
    function search:All()
        local enum = core.host:findTable("closed trades"):enumerator();
        local row = enum:next();
        local trades = {};
        while (row ~= nil) do
            if self:PassFilter(row) then trades[#trades + 1] = row; end
            row = enum:next();
        end
        return trades;
    end
    function search:First()
        local enum = core.host:findTable("closed trades"):enumerator();
        local row = enum:next();
        while (row ~= nil) do
            if self:PassFilter(row) then return row; end
            row = enum:next();
        end
        return nil;
    end
    return search;
end

function trading:ParialClose(trade, amount)
    -- not finished
    local account = core.host:findTable("accounts"):find("AccountID", trade.AccountID);
    local id = self:getId();
    if account.Hedging == "Y" then
        local valuemap = core.valuemap();
        valuemap.BuySell = trade.BS == "B" and "S" or "B";
        valuemap.OrderType = "CM";
        valuemap.OfferID = trade.OfferID;
        valuemap.AcctID = trade.AccountID;
        valuemap.TradeID = trade.TradeID;
        valuemap.Quantity = math.min(amount, trade.Lot);
        local success, msg = terminal:execute(id, valuemap);
        if success then
            local res = trading:ClosePartialSuccessResult(msg);
            self._waiting_requests[id] = res;
            return res;
        end
        return trading:ClosePartialFailResult(msg);
    end

    local valuemap = core.valuemap();
    valuemap.OrderType = "OM";
    valuemap.OfferID = trade.OfferID;
    valuemap.AcctID = trade.AccountID;
    valuemap.Quantity = math.min(amount, trade.Lot);
    valuemap.BuySell = trading:getOppositeSide(trade.BS);
    local success, msg = terminal:execute(id, valuemap);
    if success then
        local res = trading:ClosePartialSuccessResult(msg);
        self._waiting_requests[id] = res;
        return res;
    end
    return trading:ClosePartialFailResult(msg);
end

function trading:ClosePartialSuccessResult(msg)
    local res = {};
    if msg ~= nil then res.Finished = false; else res.Finished = true; end
    res.RequestID = msg;
    function res:ToJSON()
        return trading:ObjectToJson(self);
    end
    return res;
end
function trading:ClosePartialFailResult(message)
    local res = {};
    res.Finished = true;
    res.Success = false;
    res.Error = message;
    return res;
end

function trading:Close(trade)
    local valuemap = core.valuemap();
    valuemap.BuySell = trade.BS == "B" and "S" or "B";
    valuemap.OrderType = "CM";
    valuemap.OfferID = trade.OfferID;
    valuemap.AcctID = trade.AccountID;
    valuemap.TradeID = trade.TradeID;
    valuemap.Quantity = trade.Lot;
    local success, msg = terminal:execute(self._ids_start + 3, valuemap);
    if not(success) then
        if self._signaler ~= nil then self._signaler:Signal("Close failed: " .. msg); end
        return false;
    end

    return true;
end

function trading:ObjectToJson(obj)
    local json = {};
    function json:AddStr(name, value)
        local separator = "";
        if self.str ~= nil then separator = ","; else self.str = ""; end
        self.str = self.str .. string.format("%s\"%s\":\"%s\"", separator, tostring(name), tostring(value));
    end
    function json:AddNumber(name, value)
        local separator = "";
        if self.str ~= nil then separator = ","; else self.str = ""; end
        self.str = self.str .. string.format("%s\"%s\":%f", separator, tostring(name), value or 0);
    end
    function json:AddBool(name, value)
        local separator = "";
        if self.str ~= nil then separator = ","; else self.str = ""; end
        self.str = self.str .. string.format("%s\"%s\":%s", separator, tostring(name), value and "true" or "false");
    end
    function json:AddTable(name, value)
        local str = trading:ObjectToJson(value);
        local separator = "";
        if self.str ~= nil then separator = ","; else self.str = ""; end
        self.str = self.str .. string.format("%s\"%s\":%s", separator, tostring(name), tostring(str));
    end
    function json:ToString() return "{" .. (self.str or "") .. "}"; end
    
    local first = true;
    for idx,t in pairs(obj) do
        local stype = type(t)
        if stype == "number" then json:AddNumber(idx, t);
        elseif stype == "string" then json:AddStr(idx, t);
        elseif stype == "boolean" then json:AddBool(idx, t);
        elseif stype == "function" then --do nothing
        elseif stype == "table" then json:AddTable(idx, t);
        else core.host:trace(tostring(idx) .. " " .. tostring(stype));
        end
    end
    return json:ToString();
end

function trading:CreateEntryOrderSuccessResult(msg)
    local res = {};
    if msg ~= nil then res.Finished = false; else res.Finished = true; end
    res.RequestID = msg;
    function res:IsOrderExecuted()
        return self.FixStatus ~= nil and self.FixStatus == "F";
    end
    function res:GetOrder()
        if self._order == nil then
            self._order = core.host:findTable("orders"):find("RequestID", self.RequestID);
            if self._order == nil then return nil; end
        end
        if not self._order:refresh() then return nil; end
        return self._order;
    end
    function res:GetTrade()
        if self._trade == nil then
            self._trade = core.host:findTable("trades"):find("OpenOrderReqID", self.RequestID);
            if self._trade == nil then return nil; end
        end
        if not self._trade:refresh() then return nil; end
        return self._trade;
    end
    function res:GetClosedTrade()
        if self._closed_trade == nil then
            self._closed_trade = core.host:findTable("closed trades"):find("OpenOrderReqID", self.RequestID);
            if self._closed_trade == nil then return nil; end
        end
        if not self._closed_trade:refresh() then return nil; end
        return self._closed_trade;
    end
    function res:ToJSON()
        return trading:ObjectToJson(self);
    end
    return res;
end
function trading:CreateEntryOrderFailResult(message)
    local res = {};
    res.Finished = true;
    res.Success = false;
    res.Error = message;
    function res:GetOrder() return nil; end
    function res:GetTrade() return nil; end
    function res:GetClosedTrade() return nil; end
    function res:IsOrderExecuted() return false; end
    return res;
end

function trading:EntryOrder(instrument)
    local builder = {};
    builder.Offer = core.host:findTable("offers"):find("Instrument", instrument);
    builder.Instrument = instrument;
    builder.Parent = self;
    builder.valuemap = core.valuemap();
    builder.valuemap.Command = "CreateOrder";
    builder.valuemap.OfferID = builder.Offer.OfferID;
    builder.valuemap.AcctID = self._account;
    function builder:_GetBaseUnitSize() if self._base_size == nil then self._base_size = core.host:execute("getTradingProperty", "baseUnitSize", self.Instrument, self.valuemap.AcctID); end return self._base_size; end

    function builder:SetAccountID(accountID) self.valuemap.AcctID = accountID; return self; end
    function builder:SetAmount(amount) self.valuemap.Quantity = amount * self:_GetBaseUnitSize(); return self; end
    function builder:SetPercentOfEquityAmount(percent) self._PercentOfEquityAmount = percent; return self; end
    function builder:UpdateOrderType()
        if self.valuemap.BuySell == nil or self.valuemap.Rate == nil then
            return;
        end
        if self.valuemap.BuySell == "B" then 
            self.valuemap.OrderType = self.Offer.Ask > self.valuemap.Rate and "LE" or "SE"; 
        else 
            self.valuemap.OrderType = self.Offer.Bid > self.valuemap.Rate and "SE" or "LE"; 
        end 
    end
    function builder:SetSide(buy_sell) 
        self.valuemap.BuySell = buy_sell; 
        self:UpdateOrderType();
        return self; 
    end
    function builder:SetRate(rate) 
        self.valuemap.Rate = rate; 
        self:UpdateOrderType();
        return self; 
    end
    function builder:SetPipLimit(limit_type, limit) self.valuemap.PegTypeLimit = limit_type or "M"; self.valuemap.PegPriceOffsetPipsLimit = self.valuemap.BuySell == "B" and limit or -limit; return self; end
    function builder:SetLimit(limit) self.valuemap.RateLimit = limit; return self; end
    function builder:SetPipStop(stop_type, stop, trailing_stop) self.valuemap.PegTypeStop = stop_type or "O"; self.valuemap.PegPriceOffsetPipsStop = self.valuemap.BuySell == "B" and -stop or stop; self.valuemap.TrailStepStop = trailing_stop; return self; end
    function builder:SetStop(stop, trailing_stop) self.valuemap.RateStop = stop; self.valuemap.TrailStepStop = trailing_stop; return self; end
    function builder:UseDefaultCustomId() self.valuemap.CustomID = self.Parent.CustomID; return self; end
    function builder:SetCustomID(custom_id) self.valuemap.CustomID = custom_id; return self; end
    function builder:GetValueMap() return self.valuemap; end
    function builder:AddMetadata(id, val) if self._metadata == nil then self._metadata = {}; end self._metadata[id] = val; return self; end
    function builder:Execute()
        local desc = string.format("Creating %s %s for %s at %f", self.valuemap.BuySell, self.valuemap.OrderType, self.Instrument, self.valuemap.Rate);
        if self._metadata ~= nil then
            self._metadata.CustomID = self.valuemap.CustomID;
            self.valuemap.CustomID = trading:ObjectToJson(self._metadata);
        end
        if self.valuemap.RateStop ~= nil then
            desc = desc .. " stop " .. self.valuemap.RateStop;
        end
        if self.valuemap.RateLimit ~= nil then
            desc = desc .. " limit " .. self.valuemap.RateLimit;
        end
        self.Parent:trace(desc);
        if self._PercentOfEquityAmount ~= nil then
            local equity = core.host:findTable("accounts"):find("AccountID", self.valuemap.AcctID).Equity;
            local affordable_loss = equity * self._PercentOfEquityAmount / 100.0;
            local stop = math.abs(self.valuemap.RateStop - self.valuemap.Rate) / self.Offer.PointSize;
            local possible_loss = self.Offer.PipCost * stop;
            self.valuemap.Quantity = math.floor(affordable_loss / possible_loss) * self:_GetBaseUnitSize();
        end

        for _, module in pairs(self.Parent._all_modules) do
            if module.BlockOrder ~= nil and module:BlockOrder(self.valuemap) then
                self.Parent:trace("Creation of order blocked by " .. module.Name);
                return trading:CreateEntryOrderFailResult("Creation of order blocked by " .. module.Name);
            end
        end
        for _, module in pairs(self.Parent._all_modules) do
            if module.OnOrder ~= nil then module:OnOrder(self.valuemap); end
        end
        local id = self.Parent:getId();
        local success, msg = terminal:execute(id, self.valuemap);
        if not(success) then
            local message = "Open order failed: " .. msg;
            self.Parent:trace(message);
            if self.Parent._signaler ~= nil then self.Parent._signaler:Signal(message); end
            return trading:CreateEntryOrderFailResult(message);
        end
        local res = trading:CreateEntryOrderSuccessResult(msg);
        self.Parent._waiting_requests[id] = res;
        return res;
    end
    return builder;
end

function trading:StoreMarketOrderResults(res)
    local str = "[";
    for i, t in ipairs(res) do
        local json = t:ToJSON();
        if str == "[" then str = str .. json; else str = str .. "," .. json; end
    end
    return str .. "]";
end
function trading:RestoreMarketOrderResults(str)
    local results = {};
    local position = 2;
    local result;
    while (position < str:len()) do
        local ch = string.sub(str, position, position);
        if ch == "{" then
            result = trading:CreateMarketOrderSuccessResult();
            position = position + 1;
        elseif ch == "}" then
            results[#results + 1] = result;
            result = nil;
            position = position + 1;
        elseif ch == "," then
            position = position + 1;
        else
            local name, value = string.match(str, '"([^"]+)":("?[^,}]+"?)', position);
            if value == "false" then
                result[name] = false;
                position = position + name:len() + 8;
            elseif value == "true" then
                result[name] = true;
                position = position + name:len() + 7;
            else
                if string.sub(value, 1, 1) == "\"" then
                    result[name] = value;
                    value:sub(2, value:len() - 1);
                    position = position + name:len() + 3 + value:len();
                else
                    result[name] = tonumber(value);
                    position = position + name:len() + 3 + value:len();
                end
            end
        end
    end
    return results;
end
function trading:CreateMarketOrderSuccessResult(msg)
    local res = {};
    if msg ~= nil then res.Finished = false; else res.Finished = true; end
    res.RequestID = msg;
    function res:GetTrade()
        if self._trade == nil then
            self._trade = core.host:findTable("trades"):find("OpenOrderReqID", self.RequestID);
            if self._trade == nil then return nil; end
        end
        if not self._trade:refresh() then return nil; end
        return self._trade;
    end
    function res:GetClosedTrade()
        if self._closed_trade == nil then
            self._closed_trade = core.host:findTable("closed trades"):find("OpenOrderReqID", self.RequestID);
            if self._closed_trade == nil then return nil; end
        end
        if not self._closed_trade:refresh() then return nil; end
        return self._closed_trade;
    end
    function res:ToJSON()
        local json = {};
        function json:AddStr(name, value)
            local separator = "";
            if self.str ~= nil then separator = ","; else self.str = ""; end
            self.str = self.str .. string.format("%s\"%s\":\"%s\"", separator, tostring(name), tostring(value));
        end
        function json:AddNumber(name, value)
            local separator = "";
            if self.str ~= nil then separator = ","; else self.str = ""; end
            self.str = self.str .. string.format("%s\"%s\":%f", separator, tostring(name), value or 0);
        end
        function json:AddBool(name, value)
            local separator = "";
            if self.str ~= nil then separator = ","; else self.str = ""; end
            self.str = self.str .. string.format("%s\"%s\":%s", separator, tostring(name), value and "true" or "false");
        end
        function json:ToString() return "{" .. (self.str or "") .. "}"; end
        
        local first = true;
        for idx,t in pairs(self) do
            local stype = type(t)
            if stype == "number" then json:AddNumber(idx, t);
            elseif stype == "string" then json:AddStr(idx, t);
            elseif stype == "boolean" then json:AddBool(idx, t);
            elseif stype == "function" or stype == "table" then --do nothing
            else core.host:trace(tostring(idx) .. " " .. tostring(stype));
            end
        end
        return json:ToString();
    end
    return res;
end
function trading:CreateMarketOrderFailResult(message)
    local res = {};
    res.Finished = true;
    res.Success = false;
    res.Error = message;
    function res:GetTrade() return nil; end
    return res;
end

function trading:MarketOrder(instrument)
    local builder = {};
    local offer = core.host:findTable("offers"):find("Instrument", instrument);
    builder.Instrument = instrument;
    builder.Parent = self;
    builder.valuemap = core.valuemap();
    builder.valuemap.Command = "CreateOrder";
    builder.valuemap.OrderType = "OM";
    builder.valuemap.OfferID = offer.OfferID;
    builder.valuemap.AcctID = self._account;
    function builder:SetAccountID(accountID) self.valuemap.AcctID = accountID; return self; end
    function builder:SetAmount(amount) self._amount = amount; return self; end
    function builder:SetSide(buy_sell) self.valuemap.BuySell = buy_sell; return self; end
    function builder:SetPipLimit(limit_type, limit)
        self.valuemap.PegTypeLimit = limit_type or "O";
        self.valuemap.PegPriceOffsetPipsLimit = self.valuemap.BuySell == "B" and limit or -limit;
        return self;
    end
    function builder:SetLimit(limit) self.valuemap.RateLimit = limit; return self; end
    function builder:SetPipStop(stop_type, stop, trailing_stop)
        self.valuemap.PegTypeStop = stop_type or "O";
        self.valuemap.PegPriceOffsetPipsStop = self.valuemap.BuySell == "B" and -stop or stop;
        self.valuemap.TrailStepStop = trailing_stop;
        return self;
    end
    function builder:SetStop(stop, trailing_stop) self.valuemap.RateStop = stop; self.valuemap.TrailStepStop = trailing_stop; return self; end
    function builder:SetCustomID(custom_id) self.valuemap.CustomID = custom_id; return self; end
    function builder:GetValueMap() return self.valuemap; end
    function builder:AddMetadata(id, val) if self._metadata == nil then self._metadata = {}; end self._metadata[id] = val; return self; end
    function builder:FillFields()
        local base_size = core.host:execute("getTradingProperty", "baseUnitSize", self.Instrument, self.valuemap.AcctID);
        self.valuemap.Quantity = self._amount * base_size;
        if self._metadata ~= nil then
            self._metadata.CustomID = self.valuemap.CustomID;
            self.valuemap.CustomID = trading:ObjectToJson(self._metadata);
        end
    end
    function builder:Execute()
        self.Parent:trace(string.format("Creating %s OM for %s", self.valuemap.BuySell, self.Instrument));
        self:FillFields();
        local id = self.Parent:getId();
        local success, msg = terminal:execute(id, self.valuemap);
        if not(success) then
            local message = "Open order failed: " .. msg;
            self.Parent:trace(message);
            if self.Parent._signaler ~= nil then
                self.Parent._signaler:Signal(message);
            end
            return trading:CreateMarketOrderFailResult(message);
        end
        local res = trading:CreateMarketOrderSuccessResult(msg);
        self.Parent._waiting_requests[id] = res;
        return res;
    end
    return builder;
end

function trading:ReadValue(json, position)
    local whaitFor = "";
    local start = position;
    while (position < json:len() + 1) do
        local ch = string.sub(json, position, position);
        position = position + 1;
        if ch == "\"" then
            start = position - 1;
            whaitFor = ch;
            break;
        elseif ch == "{" then
            start = position - 1;
            whaitFor = "}";
            break;
        elseif ch == "," or ch == "}" then
            return string.sub(json, start, position - 2), position - 1;
        end
    end
    while (position < json:len() + 1) do
        local ch = string.sub(json, position, position);
        position = position + 1;
        if ch == whaitFor then
            return string.sub(json, start, position - 1), position;
        end
    end
    return "", position;
end
function trading:JsonToObject(json)
    local position = 1;
    local result;
    local results;
    while (position < json:len() + 1) do
        local ch = string.sub(json, position, position);
        if ch == "{" then
            result = {};
            position = position + 1;
        elseif ch == "}" then
            if results ~= nil then
                position = position + 1;
                results[#results + 1] = result;
            else
                return result;
            end
        elseif ch == "," then
            position = position + 1;
        elseif ch == "[" then
            position = position + 1;
            results = {};
        elseif ch == "]" then
            return results;
        else
            if result == nil then
                return nil;
            end
            local name = string.match(json, '"([^"]+)":', position);
            local value, new_pos = trading:ReadValue(json, position + name:len() + 3);
            position = new_pos;
            if value == "false" then
                result[name] = false;
            elseif value == "true" then
                result[name] = true;
            else
                if string.sub(value, 1, 1) == "\"" then
                    result[name] = value;
                    value:sub(2, value:len() - 1);
                elseif string.sub(value, 1, 1) == "{" then
                    result[name] = trading:JsonToObject(value);
                else
                    result[name] = tonumber(value);
                end
            end
        end
    end
    return nil;
end

function trading:GetMetadata(qtxt)
    if qtxt == "" then
        return nil;
    end
    local position = 1;
    local result;
    while (position < qtxt:len() + 1) do
        local ch = string.sub(qtxt, position, position);
        if ch == "{" then
            result = {};
            position = position + 1;
        elseif ch == "}" then
            return result;
        elseif ch == "," then
            position = position + 1;
        else
            if result == nil then
                return nil;
            end
            local name, value = string.match(qtxt, '"([^"]+)":("?[^,}]+"?)', position);
            if value == "false" then
                result[name] = false;
                position = position + name:len() + 8;
            elseif value == "true" then
                result[name] = true;
                position = position + name:len() + 7;
            else
                if string.sub(value, 1, 1) == "\"" then
                    result[name] = value;
                    value:sub(2, value:len() - 1);
                    position = position + name:len() + 3 + value:len();
                else
                    result[name] = tonumber(value);
                    position = position + name:len() + 3 + value:len();
                end
            end
        end
    end
    return nil;
end

function trading:GetTradeMetadata(trade)
    return self:GetMetadata(trade.QTXT);
end
trading:RegisterModule(Modules);

breakeven = {};
-- public fields
breakeven.Name = "Breakeven";
breakeven.Version = "1.17";
breakeven.Debug = false;
--private fields
breakeven._moved_stops = {};
breakeven._request_id = nil;
breakeven._used_stop_orders = {};
breakeven._ids_start = nil;
breakeven._trading = nil;
breakeven._controllers = {};

function breakeven:trace(str) if not self.Debug then return; end core.host:trace(self.Name .. ": " .. str); end
function breakeven:OnNewModule(module)
    if module.Name == "Trading" then self._trading = module; end
    if module.Name == "Tables monitor" then
        module:ListenCloseTrade(BreakevenOnClosedTrade);
    end
end
function BreakevenOnClosedTrade(closed_trade)
    for _, controller in ipairs(breakeven._controllers) do
        if controller.TradeID == closed_trade.TradeID then
            controller._trade = core.host:findTable("trades"):find("TradeID", closed_trade.TradeIDRemain);
        elseif controller.TradeID == closed_trade.TradeIDRemain then
            controller._executed = true;
            controller._close_percent = nil;
        end
    end
end
function breakeven:RegisterModule(modules) for _, module in pairs(modules) do self:OnNewModule(module); module:OnNewModule(self); end modules[#modules + 1] = self; self._ids_start = (#modules) * 100; end

function breakeven:Init(parameters)
end

function breakeven:Prepare(nameOnly)
end

function breakeven:ExtUpdate(id, source, period)
    for _, controller in ipairs(self._controllers) do
        controller:DoBreakeven();
    end
end

function breakeven:round(num, idp)
    if idp and idp > 0 then
        local mult = 10 ^ idp
        return math.floor(num * mult + 0.5) / mult
    end
    return math.floor(num + 0.5)
end

function breakeven:CreateBaseController()
    local controller = {};
    controller._parent = self;
    controller._executed = false;
    function controller:SetTrade(trade)
        self._trade = trade;
        self.TradeID = trade.TradeID;
        return self;
    end
    function controller:GetOffer()
        if self._offer == nil then
            local order = self:GetOrder();
            if order == nil then
                order = self:GetTrade();
            end
            self._offer = core.host:findTable("offers"):find("Instrument", order.Instrument);
        end
        return self._offer;
    end
    function controller:SetRequestID(trade_request_id)
        self._request_id = trade_request_id;
        return self;
    end
    function controller:GetOrder()
        if self._order == nil then
            self._order = core.host:findTable("orders"):find("RequestID", self._request_id);
        end
        return self._order;
    end
    function controller:GetTrade()
        if self._trade == nil then
            self._trade = core.host:findTable("trades"):find("OpenOrderReqID", self._request_id);
            if self._trade == nil then
                return nil;
            end
            self._initial_limit = self._trade.Limit;
            self._initial_stop = self._trade.Stop;
        end
        return self._trade;
    end
    return controller;
end

function breakeven:CreateMartingale()
    local controller = self:CreateBaseController();
    function controller:SetStep(step)
        self._step = step;
        return self;
    end
    function controller:SetLotSizingValue(martingale_lot_sizing_val)
        self._martingale_lot_sizing_val = martingale_lot_sizing_val;
        return self;
    end
    function controller:SetStop(Stop)
        self._martingale_stop = Stop;
        return self;
    end
    function controller:SetLimit(Limit)
        self._martingale_limit = Limit;
        return self;
    end
    function controller:DoBreakeven()
        if self._executed then
            return false;
        end
        local trade = self:GetTrade();
        if trade == nil then
            return true;
        end
        if not trade:refresh() then
            self._executed = true;
            return false;
        end
        if self._current_lot == nil then
            self._current_lot = trade.AmountK;
        end

        if trade.BS == "B" then
            local movement = (instance.ask[NOW] - trade.Open) / instance.bid:pipSize();
            if movement <= -self._step then
                self._current_lot = self._current_lot * self._martingale_lot_sizing_val;
                local result = trading:MarketOrder(trade.Instrument)
                    :SetSide("S")
                    :SetAccountID(trade.AccountID)
                    :SetAmount(math.floor(self._current_lot + 0.5))
                    :SetCustomID(CustomID)
                    :Execute();
                self._trade = nil;
                self:SetRequestID(result.RequestID);
                Signal("Opening martingale position (S)");
                return true;
            end
        else
            local movement = (trade.Open - instance.bid[NOW]) / instance.bid:pipSize();
            if movement <= -self._step then
                self._current_lot = self._current_lot * self._martingale_lot_sizing_val;
                local result = trading:MarketOrder(trade.Instrument)
                    :SetSide("B")
                    :SetAccountID(trade.AccountID)
                    :SetAmount(math.floor(self._current_lot + 0.5))
                    :SetCustomID(CustomID)
                    :Execute();
                self._trade = nil;
                self:SetRequestID(result.RequestID);
                Signal("Opening martingale position (B)");
                return true;
            end
        end
        self:UpdateStopLimits();
        return true;
    end
    function controller:UpdateStopLimits()
        local trade = self:GetTrade();
        if trade == nil then
            return;
        end
        local offer = self:GetOffer();
        
        local bAmount = 0;
        local bPriceSumm = 0;
        local sAmount = 0;
        local sPriceSumm = 0;
        trading:FindTrade()
            :WhenCustomID(CustomID)
            :Do(function (trade)
                if trade.BS == "B" then
                    bAmount = bAmount + trade.AmountK
                    bPriceSumm = bPriceSumm + trade.Open * trade.AmountK;
                else
                    sAmount = sAmount + trade.AmountK
                    sPriceSumm = sPriceSumm + trade.Open * trade.AmountK;
                end
            end);
        local avgBPrice = bPriceSumm / bAmount;
        local avgSPrice = sPriceSumm / sAmount;
        local totalAmount = bAmount + sAmount;
        local avgPrice = avgBPrice * (bAmount / totalAmount) + avgSPrice * (sAmount / totalAmount);
        local stopPrice, limitPrice;
        if trade.BS == "B" then
            stopPrice = avgPrice - self._martingale_stop * offer.PointSize;
            limitPrice = avgPrice + self._martingale_stop * offer.PointSize;
            if instance.bid[NOW] <= stopPrice or instance.bid[NOW] >= limitPrice then
                local it = trading:FindTrade():WhenCustomID(CustomID)
                it:Do(function (trade) trading:Close(trade); end);
                Signal("Closing all positions");
                self._executed = true;
            end
        else
            stopPrice = avgPrice + self._martingale_stop * offer.PointSize;
            limitPrice = avgPrice - self._martingale_stop * offer.PointSize;
            if instance.ask[NOW] >= stopPrice or instance.ask[NOW] <= limitPrice then
                local it = trading:FindTrade():WhenCustomID(CustomID)
                it:Do(function (trade) trading:Close(trade); end);
                Signal("Closing all positions");
                self._executed = true;
            end
        end
    end
    self._controllers[#self._controllers + 1] = controller;
    return controller;
end

breakeven.STOP_ID = 1;
breakeven.LIMIT_ID = 2;

function breakeven:CreateOrderTrailingController()
    local controller = self:CreateBaseController();
    function controller:SetTrailingTarget(id)
        self._target_id = id;
        return self;
    end
    function controller:MoveUpOnly()
        self._up_only = true;
        return self;
    end
    function controller:SetIndicatorStream(stream, multiplicator, is_distance)
        self._stream = stream;
        self._stream_in_distance = is_distance;
        self._stream_multiplicator = multiplicator;
        return self;
    end
    function controller:SetIndicatorStreamShift(x, y)
        self._stream_x_shift = x;
        self._stream_y_shift = y;
        return self;
    end
    function controller:DoBreakeven()
        if self._executed then
            return false;
        end
        local order = self:GetOrder();
        if order == nil or (self._move_command ~= nil and not self._move_command.Finished) then
            return true;
        end
        if not order:refresh() then
            self._executed = true;
            return false;
        end
        local streamPeriod = NOW;
        if self._stream_x_shift ~= nil then
            streamPeriod = streamPeriod - self._stream_x_shift;
        end
        if not self._stream:hasData(streamPeriod) then
            return true;
        end
        return self:DoOrderTrailing(order, streamPeriod);
    end
    function controller:DoOrderTrailing(order, streamPeriod)
        local new_level;
        local offer = self:GetOffer();
        if self._stream_in_distance then
            local tick = self._stream:tick(streamPeriod) * self._stream_multiplicator;
            if self._stream_y_shift ~= nil then
                tick = tick + self._stream_y_shift * offer.PointSize;
            end
            if order.BS == "B" then
                new_level = breakeven:round(offer.Bid + tick, offer.Digits);
            else
                new_level = breakeven:round(offer.Ask - tick, offer.Digits);
            end
        else
            local tick = self._stream:tick(streamPeriod);
            if self._stream_y_shift ~= nil then
                if order.BS == "B" then
                    tick = tick - self._stream_y_shift * offer.PointSize;
                else
                    tick = tick + self._stream_y_shift * offer.PointSize;
                end
            end
            new_level = breakeven:round(tick, offer.Digits);
        end
        if self._up_only then
            if order.BS == "B" then
                if order.Rate >= new_level then
                    return true;
                end
            else
                if order.Rate <= new_level then
                    return true;
                end
            end
        end
        if self._min_profit ~= nil then
            if order.BS == "B" then
                if (offer.Bid - new_level) / offer.PointSize < self._min_profit then
                    return true;
                end
            else
                if (new_level - offer.Ask) / offer.PointSize < self._min_profit then
                    return true;
                end
            end
        end
        if order.Rate ~= new_level then
            self._move_command = self._parent._trading:ChangeOrder(order, new_level, order.TrlMinMove);
        end
    end
    self._controllers[#self._controllers + 1] = controller;
    return controller;
end

function breakeven:CreateIndicatorTrailingController()
    local controller = self:CreateBaseController();
    function controller:SetTrailingTarget(id)
        self._target_id = id;
        return self;
    end
    function controller:MoveUpOnly()
        self._up_only = true;
        return self;
    end
    function controller:SetMinProfit(min_profit)
        self._min_profit = min_profit;
        return self;
    end
    function controller:SetIndicatorStream(stream, multiplicator, is_distance)
        self._stream = stream;
        self._stream_in_distance = is_distance;
        self._stream_multiplicator = multiplicator;
        return self;
    end
    function controller:SetIndicatorStreamShift(x, y)
        self._stream_x_shift = x;
        self._stream_y_shift = y;
        return self;
    end
    function controller:DoBreakeven()
        if self._executed then
            return false;
        end
        local trade = self:GetTrade();
        if trade == nil or (self._move_command ~= nil and not self._move_command.Finished) then
            return true;
        end
        if not trade:refresh() then
            self._executed = true;
            return false;
        end
        local streamPeriod = NOW;
        if self._stream_x_shift ~= nil then
            streamPeriod = streamPeriod - self._stream_x_shift;
        end
        if not self._stream:hasData(streamPeriod) then
            return true;
        end
        if self._target_id == breakeven.STOP_ID then
            return self:DoStopTrailing(trade, streamPeriod);
        elseif self._target_id == breakeven.LIMIT_ID then
            return self:DoLimitTrailing(trade, streamPeriod);
        end
        return self:DoOrderTrailing(trade, streamPeriod);
    end
    function controller:DoStopTrailing(trade, streamPeriod)
        local new_level;
        local offer = self:GetOffer();
        if self._stream_in_distance then
            local tick = self._stream:tick(streamPeriod) * self._stream_multiplicator;
            if self._stream_y_shift ~= nil then
                tick = tick + self._stream_y_shift * offer.PointSize;
            end
            if trade.BS == "B" then
                new_level = breakeven:round(trade.Open - tick, offer.Digits);
            else
                new_level = breakeven:round(trade.Open + tick, offer.Digits);
            end
        else
            local tick = self._stream:tick(streamPeriod);
            if self._stream_y_shift ~= nil then
                if trade.BS == "B" then
                    tick = tick + self._stream_y_shift * offer.PointSize;
                else
                    tick = tick - self._stream_y_shift * offer.PointSize;
                end
            end
            new_level = breakeven:round(self._stream:tick(streamPeriod), offer.Digits);
        end
        if self._min_profit ~= nil then
            if trade.BS == "B" then
                if (new_level - trade.Open) / offer.PointSize < self._min_profit then
                    return true;
                end
            else
                if (trade.Open - new_level) / offer.PointSize < self._min_profit then
                    return true;
                end
            end
        end
        if self._up_only then
            if trade.BS == "B" then
                if trade.Stop >= new_level then
                    return true;
                end
            else
                if trade.Stop <= new_level then
                    return true;
                end
            end
            return true;
        end
        if trade.Stop ~= new_level then
            self._move_command = self._parent._trading:MoveStop(trade, new_level);
        end
        return true;
    end
    function controller:DoLimitTrailing(trade, streamPeriod)
        assert(self._up_only == nil, "Not implemented!!!");
        local new_level;
        local offer = self:GetOffer();
        if self._stream_in_distance then
            local tick = self._stream:tick(streamPeriod) * self._stream_multiplicator;
            if self._stream_y_shift ~= nil then
                tick = tick + self._stream_y_shift * offer.PointSize;
            end
            if trade.BS == "B" then
                new_level = breakeven:round(trade.Open + tick, offer.Digits);
            else
                new_level = breakeven:round(trade.Open - tick, offer.Digits);
            end
        else
            local tick = self._stream:tick(streamPeriod);
            if self._stream_y_shift ~= nil then
                if trade.BS == "B" then
                    tick = tick - self._stream_y_shift * offer.PointSize;
                else
                    tick = tick + self._stream_y_shift * offer.PointSize;
                end
            end
            new_level = breakeven:round(tick, offer.Digits);
        end
        if self._min_profit ~= nil then
            if trade.BS == "B" then
                if (trade.Open - new_level) / offer.PointSize < self._min_profit then
                    return true;
                end
            else
                if (new_level - trade.Open) / offer.PointSize < self._min_profit then
                    return true;
                end
            end
        end
        if trade.Limit ~= new_level then
            self._move_command = self._parent._trading:MoveLimit(trade, new_level);
        end
    end
    self._controllers[#self._controllers + 1] = controller;
    return controller;
end

function breakeven:CreateTrailingLimitController()
    local controller = self:CreateBaseController();
    function controller:SetDirection(direction)
        self._direction = direction;
        return self;
    end
    function controller:SetTrigger(trigger)
        self._trigger = trigger;
        return self;
    end
    function controller:SetStep(step)
        self._step = step;
        return self;
    end
    function controller:DoBreakeven()
        if self._executed then
            return false;
        end
        local trade = self:GetTrade();
        if trade == nil or (self._move_command ~= nil and not self._move_command.Finished) then
            return true;
        end
        if not trade:refresh() then
            self._executed = true;
            return false;
        end
        if self._direction == 1 then
            if trade.PL >= self._trigger then
                local offer = self:GetOffer();
                local target_limit;
                if trade.BS == "B" then
                    target_limit = self._initial_limit + self._step * offer.PointSize; 
                else
                    target_limit = self._initial_limit - self._step * offer.PointSize; 
                end
                self._initial_limit = target_limit;
                self._trigger = self._trigger + self._step;
                self._move_command = self._parent._trading:MoveLimit(trade, target_limit);
                return true;
            end
        elseif self._direction == -1 then
            if trade.PL <= -self._trigger then
                local offer = self:GetOffer();
                local target_limit;
                if trade.BS == "B" then
                    target_limit = self._initial_limit - self._step * offer.PointSize; 
                else
                    target_limit = self._initial_limit + self._step * offer.PointSize; 
                end
                self._initial_limit = target_limit;
                self._trigger = self._trigger + self._step;
                self._move_command = self._parent._trading:MoveLimit(trade, target_limit);
                return true;
            end
        else
            core.host:trace("No direction is set for the trailing limit");
        end
        return true;
    end
    self._controllers[#self._controllers + 1] = controller;
    return controller;
end

function breakeven:ActionOnTrade(action)
    local controller = self:CreateBaseController();
    controller._action = action;
    function controller:DoBreakeven()
        if self._executed then
            return false;
        end
        local trade = self:GetTrade();
        if trade == nil then
            return true;
        end
        if not trade:refresh() then
            self._executed = true;
            return false;
        end
        self._action(trade, self);
        self._executed = true;
        return true;
    end
    self._controllers[#self._controllers + 1] = controller;
    return controller;
end

function breakeven:CreateController()
    local controller = self:CreateBaseController();
    controller._trailing = 0;
    function controller:SetWhen(when)
        self._when = when;
        return self;
    end
    function controller:SetTo(to)
        self._to = to;
        return self;
    end
    function controller:SetTrailing(trailing)
        self._trailing = trailing
        return self;
    end
    function controller:SetPartialClose(amountPercent)
        self._close_percent = amountPercent;
        return self;
    end
    function controller:getTo()
        local trade = self:GetTrade();
        local offer = self:GetOffer();
        if trade.BS == "B" then
            return offer.Bid - (trade.PL - self._to) * offer.PointSize;
        else
            return offer.Ask + (trade.PL - self._to) * offer.PointSize;
        end
    end
    function controller:DoPartialClose()
        local trade = self:GetTrade();
        if trade == nil then
            return true;
        end
        if not trade:refresh() then
            self._close_percent = nil;
            return false;
        end
        local base_size = core.host:execute("getTradingProperty", "baseUnitSize", trade.Instrument, trade.AccountID);
        local to_close = breakeven:round(trade.Lot * self._close_percent / 100.0 / base_size) * base_size;
        trading:ParialClose(trade, to_close);
        self._close_percent = nil;
        return true;
    end
    function controller:DoBreakeven()
        if self._executed then
            if self._close_percent ~= nil then
                if self._command ~= nil and self._command.Finished or self._command == nil then
                    self._close_percent = nil;
                    return self:DoPartialClose();
                end
            end
            return false;
        end
        local trade = self:GetTrade();
        if trade == nil then
            return true;
        end
        if not trade:refresh() then
            self._executed = true;
            return false;
        end
        if trade.PL >= self._when then
            if self._to ~= nil then
                self._command = self._parent._trading:MoveStop(trade, self:getTo(), self._trailing);
            end
            self._executed = true;
            return false;
        end
        return true;
    end
    self._controllers[#self._controllers + 1] = controller;
    return controller;
end

function breakeven:RestoreTrailingOnProfitController(controller)
    controller._parent = self;
    function controller:SetProfitPercentage(profit_pr, min_profit)
        self._profit_pr = profit_pr;
        self._min_profit = min_profit;
        return self;
    end
    function controller:GetClosedTrade()
        if self._closed_trade == nil then
            self._closed_trade = core.host:findTable("closed trades"):find("OpenOrderReqID", self._request_id);
            if self._closed_trade == nil then return nil; end
        end
        if not self._closed_trade:refresh() then return nil; end
        return self._closed_trade;
    end
    function controller:getStopPips(trade)
        local stop = trading:FindStopOrder(trade);
        if stop == nil then
            return nil;
        end
        local offer = self:GetOffer();
        if trade.BS == "B" then
            return (stop.Rate - trade.Open) / offer.PointSize;
        else
            return (trade.Open - stop.Rate) / offer.PointSize;
        end
    end
    function controller:DoBreakeven()
        if self._executed then
            return false;
        end
        if self._move_command ~= nil and not self._move_command.Finished then
            return true;
        end
        local trade = self:GetTrade();
        if trade == nil then
            if self:GetClosedTrade() ~= nil then
                self._executed = true;
            end
            return true;
        end
        if not trade:refresh() then
            self._executed = true;
            return false;
        end
        if trade.PL < self._min_profit then
            return true;
        end
        local new_stop = trade.PL * (self._profit_pr / 100);
        local current_stop = self:getStopPips(trade);
        if current_stop == nil or current_stop < new_stop then
            local offer = self:GetOffer();
            if trade.BS == "B" then
                if not trailing_mark:hasData(NOW) then
                    trailing_mark[NOW] = trade.Close;
                end
                self._move_command = self._parent._trading:MoveStop(trade, trade.Open + new_stop * offer.PointSize);
                core.host:trace("Moving stop for " .. trade.TradeID .. " to " .. trade.Open + new_stop * offer.PointSize);
            else
                if not trailing_mark:hasData(NOW) then
                    trailing_mark[NOW] = trade.Close;
                end
                self._move_command = self._parent._trading:MoveStop(trade, trade.Open - new_stop * offer.PointSize);
                core.host:trace("Moving stop for " .. trade.TradeID .. " to " .. trade.Open - new_stop * offer.PointSize);
            end
            return true;
        end
        return true;
    end
end

function breakeven:CreateTrailingOnProfitController()
    local controller = self:CreateBaseController();
    controller._trailing = 0;
    self:RestoreTrailingOnProfitController(controller);
    self._controllers[#self._controllers + 1] = controller;
    return controller;
end
breakeven:RegisterModule(Modules);

tables_monitor = {};
tables_monitor.Name = "Tables monitor";
tables_monitor.Version = "1.2";
tables_monitor.Debug = false;
tables_monitor._ids_start = nil;
tables_monitor._new_trade_id = nil;
tables_monitor._trade_listeners = {};
tables_monitor._closed_trade_listeners = {};
tables_monitor._close_order_listeners = {};
tables_monitor.closing_order_types = {};
function tables_monitor:ListenTrade(func)
    self._trade_listeners[#self._trade_listeners + 1] = func;
end
function tables_monitor:ListenCloseTrade(func)
    self._closed_trade_listeners[#self._closed_trade_listeners + 1] = func;
end
function tables_monitor:ListenCloseOrder(func)
    self._close_order_listeners[#self._close_order_listeners + 1] = func;
end
function tables_monitor:trace(str) if not self.Debug then return; end core.host:trace(self.Name .. ": " .. str); end
function tables_monitor:Init(parameters) end
function tables_monitor:Prepare(name_only)
    if name_only then return; end
    self._new_trade_id = self._ids_start;
    self._order_change_id = self._ids_start + 1;
    self._ids_start = self._ids_start + 2;
    core.host:execute("subscribeTradeEvents", self._order_change_id, "orders");
    core.host:execute("subscribeTradeEvents", self._new_trade_id, "trades");
end
function tables_monitor:OnNewModule(module) end
function tables_monitor:RegisterModule(modules) for _, module in pairs(modules) do self:OnNewModule(module); module:OnNewModule(self); end modules[#modules + 1] = self; self._ids_start = (#modules) * 100; end
function tables_monitor:ReleaseInstance() end
function tables_monitor:AsyncOperationFinished(cookie, success, message, message1, message2)
    if cookie == self._new_trade_id then
        local trade_id = message;
        local close_trade = success;
        if close_trade then
            local closed_trade = core.host:findTable("closed trades"):find("TradeID", trade_id);
            if closed_trade ~= nil then
                for _, callback in ipairs(self._closed_trade_listeners) do
                    callback(closed_trade);
                end
            end
        else
            local trade = core.host:findTable("trades"):find("TradeID", message);
            if trade ~= nil then
                for _, callback in ipairs(self._trade_listeners) do
                    callback(trade);
                end
            end
        end
    elseif cookie == self._order_change_id then
        local order_id = message;
        local order = core.host:findTable("orders"):find("OrderID", order_id);
        local fix_status = message1;
        if order ~= nil then
            if order.Stage == "C" then
                self.closing_order_types[order.OrderID] = order.Type;
                for _, callback in ipairs(self._close_order_listeners) do
                    callback(order);
                end
            end
        end
    end
end
function tables_monitor:ExtUpdate(id, source, period) end
function tables_monitor:BlockTrading(id, source, period) return false; end
function tables_monitor:BlockOrder(order_value_map) return false; end
function tables_monitor:OnOrder(order_value_map) end
tables_monitor:RegisterModule(Modules);