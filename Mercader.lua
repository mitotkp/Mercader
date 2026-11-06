-- Mercader
-- 1) Contador de sesion: oro ganado y gastado, oro por hora, experiencia por
--    hora y tiempo que falta para subir de nivel. Ventana que se puede mover.
-- 2) Al abrir un comerciante vende lo gris y repara el equipo.
-- 3) En el aviso de cada objeto sale lo que paga el vendedor, y en la
--    ventana el valor total de lo que llevas en las bolsas.

local ADDON = ...
local SELL_DELAY = 0.15       -- segundos entre cada objeto vendido

---------------------------------------------------------------------------
-- Utilidades
---------------------------------------------------------------------------
local function Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cff33cc66Mercader:|r " .. msg)
end

local function Money(copper)
    copper = math.floor(copper or 0)
    if GetCoinTextureString then return GetCoinTextureString(copper) end
    local g, s, c = math.floor(copper / 10000), math.floor(copper / 100) % 100, copper % 100
    local out = {}
    if g > 0 then out[#out + 1] = "|cffffd700" .. g .. "o|r" end
    if s > 0 or g > 0 then out[#out + 1] = "|cffc7c7cf" .. s .. "p|r" end
    out[#out + 1] = "|cffeda55f" .. c .. "c|r"
    return table.concat(out, " ")
end

local function Duration(seconds)
    seconds = math.floor(seconds or 0)
    local h, m = math.floor(seconds / 3600), math.floor(seconds / 60) % 60
    if h > 0 then return ("%dh %02dm"):format(h, m) end
    return ("%dm %02ds"):format(m, seconds % 60)
end

local function Number(n)
    local s = tostring(math.floor(n))
    while true do
        local r, k = s:gsub("^(-?%d+)(%d%d%d)", "%1.%2")
        s = r
        if k == 0 then return s end
    end
end

-- Precio de venta de un objeto (por unidad). nil si aun no esta en cache.
local function SellPrice(item)
    if not item then return end
    local getInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
    local name, _, _, _, _, _, _, _, _, _, price = getInfo(item)
    if not name then return end
    return price or 0
end

-- Bolsas (API nueva C_Container o la antigua)
local NUM_BAGS = NUM_BAG_SLOTS or 4

local function NumSlots(bag)
    if C_Container and C_Container.GetContainerNumSlots then return C_Container.GetContainerNumSlots(bag) end
    return GetContainerNumSlots(bag)
end

-- Devuelve link, cantidad, calidad, sinValor de un hueco
local function SlotInfo(bag, slot)
    if C_Container and C_Container.GetContainerItemInfo then
        local info = C_Container.GetContainerItemInfo(bag, slot)
        if not info then return end
        return info.hyperlink, info.stackCount or 1, info.quality, info.hasNoValue
    end
    local _, count, _, quality, _, _, link, _, noValue = GetContainerItemInfo(bag, slot)
    if not link then return end
    return link, count or 1, quality, noValue
end

local function UseSlot(bag, slot)
    if C_Container and C_Container.UseContainerItem then
        C_Container.UseContainerItem(bag, slot)
    else
        UseContainerItem(bag, slot)
    end
end

---------------------------------------------------------------------------
-- Estado
---------------------------------------------------------------------------
local db
local session = {}
local bagValue, grayValue, bagPending = 0, 0, false

local function ResetSession()
    session.start = GetTime()
    session.earned = 0
    session.spent = 0
    session.xp = 0
    session.sold = 0
    session.lastMoney = GetMoney()
    session.lastXP = UnitXP("player")
    session.lastXPMax = UnitXPMax("player")
end

local function UpdateBagValue()
    local total, gray, pending = 0, 0, false
    for bag = 0, NUM_BAGS do
        for slot = 1, NumSlots(bag) or 0 do
            local link, count, quality, noValue = SlotInfo(bag, slot)
            if link and not noValue then
                local price = SellPrice(link)
                if price then
                    total = total + price * count
                    if quality == 0 then gray = gray + price * count end
                else
                    pending = true
                end
            end
        end
    end
    bagValue, grayValue, bagPending = total, gray, pending
end

---------------------------------------------------------------------------
-- Ventana del contador
---------------------------------------------------------------------------
local win, lines = nil, {}
local LABELS = {
    "Tiempo", "Ganado", "Gastado", "Neto por hora",
    "Experiencia", "Exp. por hora", "Para subir",
    "Bolsas (vendedor)", "De eso, gris",
}

local function CreateWindow()
    win = CreateFrame("Frame", "MercaderVentana", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
    win:SetSize(230, 34 + #LABELS * 14)
    win:SetFrameStrata("MEDIUM")
    if win.SetBackdrop then
        win:SetBackdrop({
            bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = true, tileSize = 16, edgeSize = 14,
            insets = { left = 3, right = 3, top = 3, bottom = 3 },
        })
        win:SetBackdropColor(0, 0, 0, 0.75)
        win:SetBackdropBorderColor(0.4, 0.8, 0.5, 1)
    end

    local p = db.pos
    if p then
        win:SetPoint(p[1], UIParent, p[2], p[3], p[4])
    else
        win:SetPoint("LEFT", UIParent, "LEFT", 20, 0)   -- a la izquierda, entre el chat y lo de arriba
    end

    win:EnableMouse(true)
    win:SetMovable(true)
    win:SetClampedToScreen(true)
    win:RegisterForDrag("LeftButton")
    win:SetScript("OnDragStart", function(self) if not db.locked then self:StartMoving() end end)
    win:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local a, _, b, x, y = self:GetPoint()
        db.pos = { a, b, x, y }
    end)

    local title = win:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOP", 0, -8)
    title:SetText("Mercader")

    for i, label in ipairs(LABELS) do
        local l = win:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        l:SetPoint("TOPLEFT", 10, -12 - i * 14)
        l:SetText(label)
        l:SetTextColor(0.75, 0.75, 0.75)
        local v = win:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        v:SetPoint("TOPRIGHT", -10, -12 - i * 14)
        v:SetJustifyH("RIGHT")
        lines[i] = v
    end

    if db.shown then
        Print("contador activo. /merc para ocultarlo, /merc ayuda para ver los comandos.")
    else
        win:Hide()
        Print("la ventana esta oculta. Escribe /merc para verla.")
    end
end

local function MaxLevel()
    local max = (GetMaxPlayerLevel and GetMaxPlayerLevel()) or MAX_PLAYER_LEVEL or 60
    return UnitLevel("player") >= max
end

local function UpdateWindow()
    if not win or not win:IsShown() then return end
    local elapsed = math.max(GetTime() - session.start, 1)
    local hours = elapsed / 3600
    local net = session.earned - session.spent

    lines[1]:SetText(Duration(elapsed))
    lines[2]:SetText(Money(session.earned))
    lines[3]:SetText(Money(session.spent))
    if net >= 0 then
        lines[4]:SetText(Money(net / hours))
    else
        lines[4]:SetText("|cffff5555-|r " .. Money(-net / hours))
    end

    if MaxLevel() then
        lines[5]:SetText("nivel maximo")
        lines[6]:SetText("-")
        lines[7]:SetText("-")
    else
        local perHour = session.xp / hours
        local left = UnitXPMax("player") - UnitXP("player")
        lines[5]:SetText(Number(session.xp))
        lines[6]:SetText(Number(perHour))
        if session.xp > 0 then
            lines[7]:SetText(Duration(left / perHour * 3600) .. " (" .. Number(left) .. ")")
        else
            lines[7]:SetText("? (" .. Number(left) .. ")")
        end
    end

    lines[8]:SetText(Money(bagValue) .. (bagPending and " +" or ""))
    lines[9]:SetText(Money(grayValue))
end

---------------------------------------------------------------------------
-- Comerciante: vender gris y reparar
---------------------------------------------------------------------------
local sellTicker

local function StopSelling()
    if sellTicker then sellTicker:Cancel() sellTicker = nil end
end

local function SellGrays()
    local queue = {}
    for bag = 0, NUM_BAGS do
        for slot = 1, NumSlots(bag) or 0 do
            local link, _, quality, noValue = SlotInfo(bag, slot)
            if link and quality == 0 and not noValue and (SellPrice(link) or 0) > 0 then
                queue[#queue + 1] = { bag, slot, link }
            end
        end
    end
    if #queue == 0 then return end

    local total, i = 0, 0
    StopSelling()
    sellTicker = C_Timer.NewTicker(SELL_DELAY, function()
        i = i + 1
        local q = queue[i]
        if q then
            local link, count, quality = SlotInfo(q[1], q[2])
            -- solo si en ese hueco sigue estando el mismo objeto gris
            if link == q[3] and quality == 0 then
                total = total + (SellPrice(link) or 0) * count
                UseSlot(q[1], q[2])
            end
        end
        if i >= #queue then
            StopSelling()
            if total > 0 then
                session.sold = session.sold + total
                Print("vendido lo gris por " .. Money(total) .. ".")
            end
        end
    end, #queue)
end

local function Repair()
    if not CanMerchantRepair or not CanMerchantRepair() then return end
    local cost, needed = GetRepairAllCost()
    if not needed or cost <= 0 then return end
    if cost > GetMoney() then
        Print("no tienes dinero para reparar (" .. Money(cost) .. ").")
        return
    end
    RepairAllItems()
    Print("reparado por " .. Money(cost) .. ".")
end

---------------------------------------------------------------------------
-- Aviso del objeto: precio de venta
---------------------------------------------------------------------------
local function AddPriceLine(tooltip, link)
    if not db or not db.tooltip or not link then return end
    local price = SellPrice(link)
    if not price then return end
    if price == 0 then
        tooltip:AddLine("No se puede vender", 0.6, 0.6, 0.6)
        return
    end
    local count = 1
    local owner = tooltip.GetOwner and tooltip:GetOwner()
    if owner and type(owner.count) == "number" and owner.count > 1 then count = owner.count end
    if count > 1 then
        tooltip:AddDoubleLine("Vendedor:", Money(price) .. " c/u, " .. Money(price * count) .. " total", 1, 1, 1, 1, 1, 1)
    else
        tooltip:AddDoubleLine("Vendedor:", Money(price), 1, 1, 1, 1, 1, 1)
    end
    tooltip:Show()
end

local function HookTooltips()
    if TooltipDataProcessor and Enum and Enum.TooltipDataType and Enum.TooltipDataType.Item then
        TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tooltip)
            if tooltip ~= GameTooltip and tooltip ~= ItemRefTooltip then return end
            local _, link = tooltip:GetItem()
            AddPriceLine(tooltip, link)
        end)
    else
        local function onItem(tooltip)
            local _, link = tooltip:GetItem()
            AddPriceLine(tooltip, link)
        end
        GameTooltip:HookScript("OnTooltipSetItem", onItem)
        if ItemRefTooltip then ItemRefTooltip:HookScript("OnTooltipSetItem", onItem) end
    end
end

---------------------------------------------------------------------------
-- Eventos
---------------------------------------------------------------------------
local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:RegisterEvent("PLAYER_LOGIN")
f:RegisterEvent("PLAYER_MONEY")
f:RegisterEvent("PLAYER_XP_UPDATE")
f:RegisterEvent("MERCHANT_SHOW")
f:RegisterEvent("MERCHANT_CLOSED")
f:RegisterEvent("BAG_UPDATE_DELAYED")
f:RegisterEvent("GET_ITEM_INFO_RECEIVED")

f:SetScript("OnEvent", function(_, event, ...)
    if event == "ADDON_LOADED" then
        if ... ~= ADDON then return end
        MercaderDB = MercaderDB or {}
        db = MercaderDB
        local defaults = { shown = true, locked = false, sell = true, repair = true, tooltip = true }
        for k, v in pairs(defaults) do if db[k] == nil then db[k] = v end end

    elseif event == "PLAYER_LOGIN" then
        ResetSession()
        CreateWindow()
        HookTooltips()
        UpdateBagValue()

    elseif event == "PLAYER_MONEY" then
        local now = GetMoney()
        local delta = now - session.lastMoney
        if delta > 0 then session.earned = session.earned + delta
        elseif delta < 0 then session.spent = session.spent - delta end
        session.lastMoney = now

    elseif event == "PLAYER_XP_UPDATE" then
        local cur, max = UnitXP("player"), UnitXPMax("player")
        if cur >= session.lastXP then
            session.xp = session.xp + (cur - session.lastXP)
        else
            -- has subido de nivel: lo que faltaba del nivel anterior + lo nuevo
            session.xp = session.xp + (session.lastXPMax - session.lastXP) + cur
        end
        session.lastXP, session.lastXPMax = cur, max

    elseif event == "MERCHANT_SHOW" then
        if db.repair then Repair() end
        if db.sell then SellGrays() end

    elseif event == "MERCHANT_CLOSED" then
        StopSelling()

    elseif event == "BAG_UPDATE_DELAYED" or event == "GET_ITEM_INFO_RECEIVED" then
        if event == "GET_ITEM_INFO_RECEIVED" and not bagPending then return end
        UpdateBagValue()
    end
end)

local acc = 0
f:SetScript("OnUpdate", function(_, dt)
    acc = acc + dt
    if acc < 1 then return end
    acc = 0
    UpdateWindow()
end)

---------------------------------------------------------------------------
-- Comando /mercader
---------------------------------------------------------------------------
local function Toggle(key, on, off)
    db[key] = not db[key]
    Print(db[key] and on or off)
end

SLASH_MERCADER1 = "/mercader"
SLASH_MERCADER2 = "/merc"
SlashCmdList.MERCADER = function(msg)
    msg = (msg or ""):lower():match("^%s*(.-)%s*$")
    if msg == "" or msg == "ventana" then
        db.shown = not db.shown
        if db.shown then
            win:Show() UpdateWindow()
            Print("ventana visible (a la izquierda de la pantalla). /merc otra vez para ocultarla.")
        else
            win:Hide()
            Print("ventana oculta. Escribe /merc para volver a verla.")
        end
    elseif msg == "centrar" then
        db.pos = nil
        db.shown = true
        win:ClearAllPoints()
        win:SetPoint("LEFT", UIParent, "LEFT", 20, 0)
        win:Show() UpdateWindow()
        Print("ventana devuelta a su sitio (a la izquierda de la pantalla).")
    elseif msg == "reset" then
        ResetSession()
        UpdateWindow()
        Print("contador a cero.")
    elseif msg == "bloquear" then
        Toggle("locked", "ventana bloqueada.", "ventana desbloqueada: arrastrala para moverla.")
    elseif msg == "vender" then
        Toggle("sell", "vender lo gris activado.", "vender lo gris desactivado.")
    elseif msg == "reparar" then
        Toggle("repair", "reparar automaticamente activado.", "reparar automaticamente desactivado.")
    elseif msg == "precio" then
        Toggle("tooltip", "precio en el aviso activado.", "precio en el aviso desactivado.")
    else
        Print("/mercader          mostrar u ocultar la ventana")
        Print("/mercader reset    poner el contador a cero")
        Print("/mercader centrar  devolver la ventana a su sitio si no la encuentras")
        Print("/mercader bloquear | vender | reparar | precio   activar o desactivar")
    end
end
