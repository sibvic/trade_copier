--+------------------------------------------------------------------+
--|                                          http://profitrobots.com |
--+------------------------------------------------------------------+

-- START OF CUSTOMIZATION SECTION
local STRATEGY_NAME = "Trade Copy Source";
local STRATEGY_VERSION = "2";
-- END OF CUSTOMIZATION SECTION

local Modules = {};
function Init()
    strategy:name(STRATEGY_NAME .. " v" .. STRATEGY_VERSION);
    strategy:description("");
    strategy:type(core.Both);
    strategy:setTag("Version", STRATEGY_VERSION);
    
    strategy.parameters:addString("advanced_alert_key", 
        "Key", 
        "You can get it on ProfitRobots.com", 
        "");
end

local TRADES_UPDATE = 1;
local ORDERS_UPDATE = 2;
local TIMER_ID = 3;
local closing_order_types = {};
function Prepare(name_only)
    for _, module in pairs(Modules) do module:Prepare(nameOnly); end
    instance:name(profile:id());
    if name_only then return ; end
    core.host:execute("subscribeTradeEvents", TRADES_UPDATE, "trades");
    core.host:execute("subscribeTradeEvents", ORDERS_UPDATE, "orders");
    core.host:execute("setTimer", TIMER_ID, 1);
end

function ExtUpdate(id, source, period) for _, module in pairs(Modules) do if module.BlockTrading ~= nil and module:BlockTrading(id, source, period) then return; end end for _, module in pairs(Modules) do if module.ExtUpdate ~= nil then module:ExtUpdate(id, source, period); end end end
function ReleaseInstance() for _, module in pairs(Modules) do if module.ReleaseInstance ~= nil then module:ReleaseInstance(); end end end

function ParseOrder(order)
    local desc = {};
    desc.Rate = order.Rate;
    desc.Instrument = order.Instrument;
    desc.BS = order.BS;
    desc.TrlMinMove = order.TrlMinMove;
    return desc;
end

local orders;
function InitOrders()
    orders = {};
    local enum = core.host:findTable("orders"):enumerator();
    local order = enum:next();
    while (order ~= nil) do
        if order.Type == "SE" or order.Type == "LE" or order.Type == "S" or order.Type == "L" then
            orders[order.OrderID] = ParseOrder(order);
        end
        order = enum:next();
    end
end

function CheckLimitForChange(order)
    if orders[order.OrderID].Rate ~= order.Rate then
        HandleLimitChange(order, "");
    end
end

function CheckStopForChange(order)
    if orders[order.OrderID].Rate ~= order.Rate then
        HandleStopChange(order, "");
        return;
    end
    if orders[order.OrderID].TrlMinMove ~= order.TrlMinMove then
        if order.TrlMinMove == 0 then
            --Trailing removed
        elseif orders[order.OrderID].TrlMinMove ~= 0 then
            -- Trailing changed to " .. order.TrlMinMove
        else
            -- New trailing .. GetTrailingType(order.TrlMinMove)
        end
        orders[order.OrderID].TrlMinMove = order.TrlMinMove;
        if order.PrimaryOrderId == "" then
            -- Stop for the trade %s (%s) has changed."
        else
            -- Stop for the order %s (%s) has changed."
        end
        -- TODO: signaler:Signal(message);
    end
end

function HandleLimitChange(order, fix_status)
    if fix_status == "C" or fix_status == "S" then
        local trade = core.host:findTable("trades"):find("TradeID", order.TradeID);
        if trade ~= nil then
            --local message = string.format("Trade %s %s %s\r\nLimit was deleted.",
            -- TODO: signaler:Signal(message);
        end
    else
        if order.ContingencyType == 3 then
            local trade = core.host:findTable("trades"):find("TradeID", order.TradeID);
            if trade ~= nil then
                HandleTradeLimitChange(trade, order, label);
            elseif order.PrimaryOrderId ~= "" then
                local primary_order = core.host:findTable("orders"):find("OrderID", order.PrimaryOrderId);
                if primary_order ~= nil then
                    HandleOrderLimitChange(primary_order, order, label);
                end
            end
        elseif order.ContingencyType == 0 then
            local trade = core.host:findTable("trades"):find("TradeID", order.TradeID);
            if trade ~= nil then
                HandleTradeLimitChange(trade, order, label);
            end
        end
    end
end

function HandleOrderLimitChange(order, limit_order)
    -- local offer = core.host:findTable("offers"):find("OfferID", limit_order.OfferID);
    -- local message = string.format("Trade %s %s:\r\n%s%s", 
    --     order.OrderID, limit_order.Instrument, label,
    --     FormatLimit(order.BS, order.Rate, limit_order.Rate, offer.PointSize, offer.Digits));
    -- TODO: signaler:Signal(message);
    orders[limit_order.OrderID] = ParseOrder(limit_order);
end

function HandleTradeLimitChange(trade, limit_order)
    local message = "action=change order-id=" .. trade.TradeID .. " take-profit=" .. limit_order.Rate;
    signaler:Signal(message);
    orders[limit_order.OrderID] = ParseOrder(limit_order);
end

function HandleTradeStopChange(trade, stop_order)
    local message = "action=change order-id=" .. trade.TradeID .. " stop-loss=" .. stop_order.Rate;
    signaler:Signal(message);
    orders[stop_order.OrderID] = ParseOrder(stop_order);
end

function HandleOrderStopChange(order, stop_order)
    -- local offer = core.host:findTable("offers"):find("OfferID", stop_order.OfferID);
    -- local message = string.format("Order %s %s:\r\n%s%s", 
    --     order.OrderID, stop_order.Instrument, label,
    --     FormatStop(order.BS, order.Rate, stop_order.Rate, offer.PointSize, offer.Digits));
    -- TODO: signaler:Signal(message);
    orders[stop_order.OrderID] = ParseOrder(stop_order);
end

function HandleStopChange(order, fix_status)
    if fix_status == "C" or fix_status == "S" then
        local trade = core.host:findTable("trades"):find("TradeID", order.TradeID);
        if trade ~= nil then
            --Trade %s %s %s\r\nStop was deleted
            -- TODO: signaler:Signal(message);
        end
    else
        if order.ContingencyType == 3 then
            local trade = core.host:findTable("trades"):find("TradeID", order.TradeID);
            if trade ~= nil then
                HandleTradeStopChange(trade, order);
            elseif order.PrimaryOrderId == "" then
                local primary_order = core.host:findTable("orders"):find("OrderID", order.PrimaryOrderId);
                if primary_order ~= nil then
                    HandleOrderStopChange(primary_order, order);
                end
            end
        elseif order.ContingencyType == 0 then
            local trade = core.host:findTable("trades"):find("TradeID", order.TradeID);
            if trade ~= nil then
                HandleTradeStopChange(trade, order);
            end
        end
    end
end

function HandleDeletedOrder(order)
    -- local side = order.BS == "B" and "Buy" or "Sell";
    -- local message = string.format("Order %s %s %s:\r\nDeleted", 
    --     order.OrderID, side, order.Instrument);
    -- TODO: signaler:Signal(message);
end

function HandleNewEntryOrder(order)
    -- local offer = core.host:findTable("offers"):find("OfferID", order.OfferID);
    -- local side = order.BS == "B" and "Buy" or "Sell";
    -- local message = string.format("New Entry Order\r\nOrder %s %s %s\r\nEntry Price at: %s"
    --     , order.OrderID, side, order.Instrument, win32.formatNumber(order.Rate, false, offer.Digits));
    -- if order.Stop ~= 0 then
    --     message = message .. "\r\n Stop at: " .. FormatStop(order.BS, order.Rate, order.Stop, offer.PointSide, offer.Digits);
    -- end
    -- if order.Limit ~= 0 then
    --     message = message .. "\r\n Limit at: " .. FormatLimit(order.BS, order.Rate, order.Limit, offer.PointSide, offer.Digits);
    -- end
    -- TODO: signaler:Signal(message);
end

function HandleNewTrade(trade_id)
    local trade = core.host:findTable("trades"):find("TradeID", trade_id);
    if trade == nil then
        return;
    end

    local command = string.format("symbol=%s side=%s quantity=%s order-id=%s"
        , trade.Instrument -- s
        , trade.BS == "B" and "buy" or "sell" -- b
        , tostring(trade.AmountK) -- q
        , trade.TradeID
    )
    if trade.Stop ~= 0 then
        command = command .. " stop-loss=" .. trade.Stop;
    end
    if trade.Limit ~= 0 then
        command = command .. " take-profit=" .. trade.Limit;
    end
    signaler:Signal(command);
end

function HandleNewClosedTrade(trade_id)
    local closed_trade = core.host:findTable("closed trades"):find("TradeID", trade_id);
    if closed_trade == nil then
        return;
    end

    local command = string.format("quantity=%s action=close order-id=%s"
        , tostring(closed_trade.AmountK) -- q
        , closed_trade.TradeID
    )
    signaler:Signal(command);
end

function CheckOrderForChange(order)
    if orders[order.OrderID].Rate ~= order.Rate then
        local offer = core.host:findTable("offers"):find("OfferID", order.OfferID);
         -- Order %s %s %s\r\nEntry Price Changed to: %s"
        -- TODO: signaler:Signal(message);
        orders[order.OrderID].Rate = order.Rate;
    end
end

function ExtAsyncOperationFinished(cookie, success, message, message1, message2)
    if cookie == TIMER_ID then
        if orders == nil then
            InitOrders();
        else
            local enum = core.host:findTable("orders"):enumerator();
            local order = enum:next();
            while (order ~= nil) do
                if order.Type == "SE" or order.Type == "LE" then
                    CheckOrderForChange(order);
                elseif order.Type == "S" then
                    CheckStopForChange(order);
                elseif order.Type == "L" then
                    CheckLimitForChange(order);
                end
                order = enum:next();
            end
        end
    elseif cookie == TRADES_UPDATE then
        local trade_id = message;
        local close_trade = success;
        if close_trade then
            HandleNewClosedTrade(trade_id);
        else
            HandleNewTrade(trade_id);
        end
    elseif cookie == ORDERS_UPDATE then
        local order_id = message;
        local order = core.host:findTable("orders"):find("OrderID", order_id);
        local fix_status = message1;
        if order ~= nil then
            if order.Stage == "C" then
                closing_order_types[order.OrderID] = order.Type;
            end
            if order.Type == "SE" or order.Type == "LE" then
                local offer = core.host:findTable("offers"):find("OfferID", order.OfferID);
                if fix_status == "C" or fix_status == "S" then
                    HandleDeletedOrder(order);
                else
                    HandleNewEntryOrder(order);
                end
                orders[order.OrderID] = ParseOrder(order);
            elseif order.Type == "S" then
                HandleStopChange(order, fix_status);
            elseif order.Type == "L" then
                HandleLimitChange(order, fix_status);
            else
            end
        elseif fix_status == "C" then
            local side = orders[order_id].BS == "B" and "Buy" or "Sell";
            -- Order %s %s %s:\r\nDeleted"
            -- TODO: signaler:Signal(message);
        end
    end
    for _, module in pairs(Modules) do if module.AsyncOperationFinished ~= nil then module:AsyncOperationFinished(cookie, success, message, message1, message2); end end
end
dofile(core.app_path() .. "\\strategies\\standard\\include\\helper.lua");

signaler = {};
signaler.Name = "Signaler";
signaler.Debug = false;
signaler.Version = "1.5 modified";

signaler._ids_start = nil;
signaler._advanced_alert_timer = nil;
signaler._alerts = {};

function signaler:trace(str) if not self.Debug then return; end core.host:trace(self.Name .. ": " .. str); end
function signaler:OnNewModule(module) end
function signaler:RegisterModule(modules) for _, module in pairs(modules) do self:OnNewModule(module); module:OnNewModule(self); end modules[#modules + 1] = self; self._ids_start = (#modules) * 100; end

function signaler:ToJSON(item)
    local json = {};
    function json:AddStr(name, value)
        local separator = "";
        if self.str ~= nil then
            separator = ",";
        else
            self.str = "";
        end
        self.str = self.str .. string.format("%s\"%s\":\"%s\"", separator, tostring(name), tostring(value));
    end
    function json:AddNumber(name, value)
        local separator = "";
        if self.str ~= nil then
            separator = ",";
        else
            self.str = "";
        end
        self.str = self.str .. string.format("%s\"%s\":%f", separator, tostring(name), value or 0);
    end
    function json:AddBool(name, value)
        local separator = "";
        if self.str ~= nil then
            separator = ",";
        else
            self.str = "";
        end
        self.str = self.str .. string.format("%s\"%s\":%s", separator, tostring(name), value and "true" or "false");
    end
    function json:ToString()
        return "{" .. (self.str or "") .. "}";
    end
    
    local first = true;
    for idx,t in pairs(item) do
        local stype = type(t)
        if stype == "number" then
            json:AddNumber(idx, t);
        elseif stype == "string" then
            json:AddStr(idx, t);
        elseif stype == "boolean" then
            json:AddBool(idx, t);
        elseif stype == "function" or stype == "table" then
            --do nothing
        else
            core.host:trace(tostring(idx) .. " " .. tostring(stype));
        end
    end
    return json:ToString();
end

function signaler:ArrayToJSON(arr)
    local str = "[";
    for i, t in ipairs(self._alerts) do
        local json = self:ToJSON(t);
        if str == "[" then
            str = str .. json;
        else
            str = str .. "," .. json;
        end
    end
    return str .. "]";
end

function signaler:AsyncOperationFinished(cookie, success, message, message1, message2)
    if cookie == self._advanced_alert_timer and #self._alerts > 0 and (self.last_req == nil or not self.last_req:loading()) then
        if self._advanced_alert_key == nil then
            return;
        end

        local data = self:ArrayToJSON(self._alerts);
        self._alerts = {};
        
        self.last_req = http_lua.createRequest();
        local query = string.format('{"Key":"%s","StrategyName":"%s","Platform":"FXTS2","Notifications":%s}',
            self._advanced_alert_key, string.gsub(self.StrategyName or "", '"', '\\"'), data);
        self.last_req:setRequestHeader("Content-Type", "application/json");
        self.last_req:setRequestHeader("Content-Length", tostring(string.len(query)));

        self.last_req:start("http://profitrobots.com/api/v1/notification", "POST", query);
    end
end

function signaler:Signal(message, source)
    self:AlertTelegram(message, "", "");
end

function signaler:AlertTelegram(message, instrument, timeframe)
    if core.host.Trading:getTradingProperty("isSimulation") then
        return;
    end
    local alert = {};
    alert.Text = message or "";
    alert.Instrument = instrument or "";
    alert.TimeFrame = timeframe or "";
    self._alerts[#self._alerts + 1] = alert;
end

function signaler:Prepare(name_only)
    if name_only then
        return;
    end

    self._advanced_alert_key = instance.parameters.advanced_alert_key;
    require("http_lua");
    self._advanced_alert_timer = self._ids_start + 1;
    core.host:execute("setTimer", self._advanced_alert_timer, 1);
end

signaler:RegisterModule(Modules);