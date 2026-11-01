--[[
	bảo anh Script – Menu giao diện (chỉ UI) cho Roblox Studio
	Cách dùng:
	  1. Studio → StarterGui → Insert Object → LocalScript
	  2. Dán toàn bộ code này vào LocalScript
	  3. Gắn logic game CỦA BẠN vào bảng Callbacks bên dưới
	Mỗi tab ở thanh bên trái là MỘT TRANG RIÊNG: Tổng Quan (chỉ có phần Thông Tin), Farm,
	Tự Động, Player, ESP, Cài Đặt. Bấm tab nào thì chỉ hiện nội dung của tab đó.
	ESP: bật ESP Khung / ESP Line trong tab ESP. Khung và line dùng GUI Roblox, không cần Drawing.
	Phím RightShift: ẩn / hiện menu. Kéo thanh tiêu đề để di chuyển.
	Tab vuông bên trái màn hình: bấm để ẩn / hiện menu chính, kéo để đổi vị trí.
	Player: God Mode, Speed Hack (thanh trượt SPEED_MIN..SPEED_MAX), Jump Power (thanh trượt JUMP_MIN..JUMP_MAX), Full Health, Tàn Hình, Đi Xuyên Tường (Noclip) đã hoạt động.
Chỉnh cỡ menu: W, H (khung), SIDE_W (thanh bên), ROW_H (độ cao mỗi chức năng).
Chỉnh cỡ chữ menu chính: TEXT_SCALE (đang là 3 = to gấp 3 lần cỡ gốc; Roblox giới hạn tối đa 100).
Fake an Egg (chuyển từ Fake an Egg Hub): tab Farm, Steal, Rebirth, Shops, Sell. Cần executor có fireproximityprompt, chỉ dùng trong game Fake an Egg.
Thanh bên có 10 tab nên có thể cuộn dọc.
Chữ trong menu chạy 7 màu cầu vồng (chỉnh / tắt ở khối "CHỮ 7 MÀU" cuối file).
]]

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

local ADMIN_LABEL = "admin bảo anh"

local player = Players.LocalPlayer

----------------------------------------------------------------
-- LOGIC NHÂN VẬT: God Mode (Bất Tử) & Speed Hack (Tốc Độ)
----------------------------------------------------------------
local GOD_HP = 1e9 -- máu "vô hạn" (dùng số lớn thay vì math.huge để thanh máu không bị lỗi NaN)
local SPEED_MIN, SPEED_MAX, SPEED_DEFAULT = 4, 200, 50 -- khoảng tốc độ của thanh trượt (Roblox mặc định là 16)

local godOn, speedOn = false, false
local speedValue = SPEED_DEFAULT
local baseMaxHealth, baseWalkSpeed = 100, 16 -- giá trị gốc của game, dùng để trả lại khi tắt
local godConns, speedConn = {}, nil

local JUMP_MIN, JUMP_MAX, JUMP_DEFAULT = 10, 300, 100 -- khoảng sức nhảy của thanh trượt (Roblox mặc định JumpPower = 50)
local jumpOn, fullOn = false, false
local jumpValue = JUMP_DEFAULT
local baseUseJump, baseJumpPower, baseJumpHeight = true, 50, 7.2 -- giá trị gốc của game
local jumpConns, fullConn = {}, nil

local invisOn = false -- Tàn Hình
local invisConns, invisOrig = {}, {} -- kết nối sự kiện / Transparency gốc của từng phần thân
local baseDisplayDist = Enum.HumanoidDisplayDistanceType.Viewer -- kiểu hiện tên + thanh máu gốc

local noclipOn = false -- Đi Xuyên Tường
local noclipConn = nil -- kết nối Stepped (chạy mỗi khung hình vật lý)
local noclipOrig = setmetatable({}, { __mode = "k" }) -- các phần thân đã bị tắt CanCollide (để trả lại khi tắt)

local function getHumanoid()
	local char = player.Character
	return char and char:FindFirstChildOfClass("Humanoid")
end

local function clearGodConns()
	for _, c in ipairs(godConns) do c:Disconnect() end
	table.clear(godConns)
end

local function startGod(hum)
	clearGodConns()
	if hum.MaxHealth < GOD_HP then baseMaxHealth = hum.MaxHealth end
	hum:SetStateEnabled(Enum.HumanoidStateType.Dead, false) -- không cho nhân vật chết
	if not hum.Parent:FindFirstChild("BaoAnhGodFF") then
		local ff = Instance.new("ForceField") -- chặn sát thương, ẩn hiệu ứng
		ff.Name, ff.Visible = "BaoAnhGodFF", false
		ff.Parent = hum.Parent
	end
	hum.MaxHealth = GOD_HP
	hum.Health = GOD_HP
	table.insert(godConns, hum.HealthChanged:Connect(function(h)
		if godOn and h < hum.MaxHealth then hum.Health = hum.MaxHealth end -- bị trừ máu thì hồi lại ngay
	end))
	table.insert(godConns, hum:GetPropertyChangedSignal("MaxHealth"):Connect(function()
		if godOn and hum.MaxHealth ~= GOD_HP then
			hum.MaxHealth = GOD_HP
			hum.Health = GOD_HP
		end
	end))
end

local function stopGod(hum)
	clearGodConns()
	if hum and hum.Parent then
		local ff = hum.Parent:FindFirstChild("BaoAnhGodFF")
		if ff then ff:Destroy() end
		hum:SetStateEnabled(Enum.HumanoidStateType.Dead, true)
		hum.MaxHealth = baseMaxHealth
		hum.Health = baseMaxHealth
	end
end

local function startSpeed(hum)
	if speedConn then speedConn:Disconnect() end
	baseWalkSpeed = hum.WalkSpeed
	hum.WalkSpeed = speedValue
	speedConn = hum:GetPropertyChangedSignal("WalkSpeed"):Connect(function()
		if speedOn and hum.WalkSpeed ~= speedValue then hum.WalkSpeed = speedValue end -- game đổi tốc độ thì đặt lại
	end)
end

local function stopSpeed(hum)
	if speedConn then
		speedConn:Disconnect()
		speedConn = nil
	end
	if hum and hum.Parent then hum.WalkSpeed = baseWalkSpeed end
end

-- thanh trượt gọi hàm này; đang bật Speed Hack thì áp dụng ngay
local function setSpeedValue(v)
	speedValue = math.clamp(math.floor(v + 0.5), SPEED_MIN, SPEED_MAX)
	if speedOn then
		local hum = getHumanoid()
		if hum then hum.WalkSpeed = speedValue end
	end
end

local function clearJumpConns()
	for _, c in ipairs(jumpConns) do c:Disconnect() end
	table.clear(jumpConns)
end

local function startJump(hum)
	clearJumpConns()
	baseUseJump, baseJumpPower, baseJumpHeight = hum.UseJumpPower, hum.JumpPower, hum.JumpHeight
	hum.UseJumpPower = true -- game dùng JumpHeight thì chuyển sang JumpPower để thanh trượt có tác dụng
	hum.JumpPower = jumpValue
	local function keep() -- game đổi lại thì đặt lại theo thanh trượt
		if not jumpOn then return end
		if not hum.UseJumpPower then hum.UseJumpPower = true end
		if hum.JumpPower ~= jumpValue then hum.JumpPower = jumpValue end
	end
	table.insert(jumpConns, hum:GetPropertyChangedSignal("JumpPower"):Connect(keep))
	table.insert(jumpConns, hum:GetPropertyChangedSignal("UseJumpPower"):Connect(keep))
end

local function stopJump(hum)
	clearJumpConns()
	if hum and hum.Parent then
		hum.UseJumpPower = baseUseJump
		hum.JumpPower = baseJumpPower
		hum.JumpHeight = baseJumpHeight
	end
end

-- thanh trượt gọi hàm này; đang bật Jump Power thì áp dụng ngay
local function setJumpValue(v)
	jumpValue = math.clamp(math.floor(v + 0.5), JUMP_MIN, JUMP_MAX)
	if jumpOn then
		local hum = getHumanoid()
		if hum then hum.JumpPower = jumpValue end
	end
end

local function startFull(hum)
	if fullConn then fullConn:Disconnect() end
	if hum.Health > 0 then hum.Health = hum.MaxHealth end
	fullConn = hum.HealthChanged:Connect(function(h)
		if fullOn and h > 0 and h < hum.MaxHealth then hum.Health = hum.MaxHealth end -- mất máu là hồi đầy ngay
	end)
end

local function stopFull()
	if fullConn then
		fullConn:Disconnect()
		fullConn = nil
	end
end

-- Tàn Hình: đặt Transparency = 1 cho mọi phần thân, phụ kiện, mặt (Decal) và ẩn tên / thanh máu trên đầu.
-- Lưu giá trị gốc để trả lại khi tắt. Đồ mới xuất hiện (phụ kiện, tool cầm lên) cũng tự được ẩn.
-- LƯU Ý: LocalScript chỉ đổi phía người chơi này; muốn người khác cũng không thấy thì cần Script + RemoteEvent phía server.
local function clearInvisConns()
	for _, c in ipairs(invisConns) do c:Disconnect() end
	table.clear(invisConns)
end

local function hideInvisPart(inst)
	if invisOrig[inst] ~= nil then return end -- đã xử lý rồi
	local isPart = inst:IsA("BasePart") and inst.Name ~= "HumanoidRootPart"
	if not (isPart or inst:IsA("Decal")) then return end -- Decal gồm cả Texture / mặt nhân vật
	invisOrig[inst] = inst.Transparency
	inst.Transparency = 1
	table.insert(invisConns, inst:GetPropertyChangedSignal("Transparency"):Connect(function()
		if invisOn and inst.Transparency ~= 1 then inst.Transparency = 1 end -- game đổi lại thì ẩn tiếp
	end))
end

local function startInvis(char, hum)
	clearInvisConns()
	table.clear(invisOrig)
	for _, d in ipairs(char:GetDescendants()) do
		hideInvisPart(d)
	end
	table.insert(invisConns, char.DescendantAdded:Connect(function(d)
		if invisOn then hideInvisPart(d) end
	end))
	if hum then
		baseDisplayDist = hum.DisplayDistanceType
		hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None -- ẩn tên + thanh máu
	end
end

local function stopInvis(hum)
	clearInvisConns() -- ngắt kết nối trước rồi mới trả lại giá trị gốc
	for inst, t in pairs(invisOrig) do
		if inst.Parent then inst.Transparency = t end
	end
	table.clear(invisOrig)
	if hum and hum.Parent then hum.DisplayDistanceType = baseDisplayDist end
end

-- Đi Xuyên Tường (Noclip): tắt CanCollide của mọi phần thân mỗi khung hình vật lý (Humanoid hay tự bật lại
-- nên phải đặt lại liên tục). Chỉ ghi nhớ những phần mà script đã tắt, để trả đúng trạng thái khi tắt.
-- Vòng lặp tự đọc player.Character mỗi lần nên khi hồi sinh vẫn hoạt động, không cần gắn lại.
local function startNoclip()
	if noclipConn then noclipConn:Disconnect() end
	noclipConn = RunService.Stepped:Connect(function()
		local char = player.Character
		if not (noclipOn and char) then return end
		for _, d in ipairs(char:GetDescendants()) do
			if d:IsA("BasePart") and d.CanCollide then
				noclipOrig[d] = true
				d.CanCollide = false
			end
		end
	end)
end

local function stopNoclip()
	if noclipConn then
		noclipConn:Disconnect()
		noclipConn = nil
	end
	for part in pairs(noclipOrig) do
		if part.Parent then part.CanCollide = true end
	end
	table.clear(noclipOrig)
end

----------------------------------------------------------------
-- LOGIC ESP: nhìn thấy người chơi khác xuyên tường
-- (Highlight, khung 2D, đường kẻ, và Tên / Máu / Khoảng cách trên đầu)
-- LƯU Ý: chỉ chạy phía người chơi này. Roblox chỉ vẽ tối đa ~31 Highlight cùng lúc.
----------------------------------------------------------------
local ESP_COLOR_NAMES = { "Đỏ", "Xanh Lá", "Vàng", "Xanh Dương", "Trắng" }
local ESP_COLORS = {
	["Đỏ"] = Color3.fromRGB(255, 60, 60),
	["Xanh Lá"] = Color3.fromRGB(60, 230, 90),
	["Vàng"] = Color3.fromRGB(255, 220, 50),
	["Xanh Dương"] = Color3.fromRGB(50, 170, 255),
	["Trắng"] = Color3.fromRGB(255, 255, 255),
}
local espColor = ESP_COLORS["Đỏ"]

local espHL, espName, espHP, espDist = false, false, false, false
local espBox, espLine = false, false
local espRefresh, espShutdown
do
	local tracked, visuals, connections = {}, {}, {}
	local overlay, renderConnection
	local elapsed, disposed = 0, false
	local corners = {
		Vector3.new(-1, -1, -1), Vector3.new(-1, -1, 1),
		Vector3.new(-1, 1, -1), Vector3.new(-1, 1, 1),
		Vector3.new(1, -1, -1), Vector3.new(1, -1, 1),
		Vector3.new(1, 1, -1), Vector3.new(1, 1, 1),
	}

	local function makeVisual(className, properties, parent)
		local instance = Instance.new(className)
		for propertyName, value in pairs(properties) do instance[propertyName] = value end
		instance.Parent = parent
		return instance
	end

	local function clearTarget(target)
		local visual = visuals[target]
		if not visual then return end
		if visual.highlight then visual.highlight:Destroy() end
		visual.info:Destroy()
		visual.box:Destroy()
		visual.line:Destroy()
		visuals[target] = nil
	end

	local function stopAll()
		if renderConnection then renderConnection:Disconnect(); renderConnection = nil end
		for _, connection in ipairs(connections) do connection:Disconnect() end
		table.clear(connections)
		for target in pairs(visuals) do clearTarget(target) end
		table.clear(tracked)
		if overlay then overlay:Destroy(); overlay = nil end
		elapsed = 0
	end

	local function buildTarget(target, character, adornee)
		local box = makeVisual("Frame", {
			Name = "BaoAnhESPBox_" .. target.UserId, BackgroundTransparency = 1,
			BorderSizePixel = 0, Visible = false, ZIndex = 3,
		}, overlay)
		makeVisual("UIStroke", { Color = Color3.new(0, 0, 0), Thickness = 4 }, box)
		local boxInner = makeVisual("Frame", {
			BackgroundTransparency = 1, BorderSizePixel = 0,
			Size = UDim2.fromScale(1, 1), ZIndex = 4,
		}, box)
		local boxColor = makeVisual("UIStroke", { Color = espColor, Thickness = 2 }, boxInner)
		local line = makeVisual("Frame", {
			Name = "BaoAnhESPLine_" .. target.UserId, BackgroundColor3 = Color3.new(0, 0, 0),
			BorderSizePixel = 0, AnchorPoint = Vector2.new(0.5, 0.5), Visible = false, ZIndex = 1,
		}, overlay)
		local lineColor = makeVisual("Frame", {
			BackgroundColor3 = espColor, BorderSizePixel = 0, AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.new(1, 0, 0, 2), ZIndex = 2,
		}, line)
		local info = makeVisual("BillboardGui", {
			Name = "BaoAnhESPInfo", Adornee = adornee, AlwaysOnTop = true,
			Size = UDim2.fromOffset(240, 78), StudsOffset = Vector3.new(0, 3, 0), Enabled = false,
		}, adornee)
		local text = makeVisual("TextLabel", {
			BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1),
			Font = Enum.Font.SourceSansBold, TextSize = 18, RichText = true,
			TextColor3 = espColor, TextStrokeColor3 = Color3.new(0, 0, 0),
			TextStrokeTransparency = 0.1, Text = "",
		}, info)
		local visual = {
			character = character, adornee = adornee, box = box, boxColor = boxColor,
			line = line, lineColor = lineColor, info = info, text = text,
		}
		visuals[target] = visual
		return visual
	end

	local function screenBounds(character, currentCamera)
		local viewport = currentCamera.ViewportSize
		if viewport.X <= 4 or viewport.Y <= 4 then return end
		local boundsFrame, boundsSize = character:GetBoundingBox()
		local minX, minY, maxX, maxY = math.huge, math.huge, -math.huge, -math.huge
		for _, corner in ipairs(corners) do
			local position = boundsFrame * Vector3.new(
				boundsSize.X * corner.X * 0.5, boundsSize.Y * corner.Y * 0.5, boundsSize.Z * corner.Z * 0.5
			)
			local projected = currentCamera:WorldToViewportPoint(position)
			if projected.Z <= 0.05 or projected.X ~= projected.X or projected.Y ~= projected.Y then return end
			minX, minY = math.min(minX, projected.X), math.min(minY, projected.Y)
			maxX, maxY = math.max(maxX, projected.X), math.max(maxY, projected.Y)
		end
		if maxX <= 0 or maxY <= 0 or minX >= viewport.X or minY >= viewport.Y then return end
		minX, minY = math.clamp(minX - 2, 2, viewport.X - 2), math.clamp(minY - 2, 2, viewport.Y - 2)
		maxX, maxY = math.clamp(maxX + 2, 2, viewport.X - 2), math.clamp(maxY + 2, 2, viewport.Y - 2)
		if maxX <= minX or maxY <= minY then return end
		return minX, minY, maxX, maxY
	end

	local function updateGeometry(visual, character, currentCamera)
		local left, top, right, bottom
		if currentCamera and (espBox or espLine) then
			left, top, right, bottom = screenBounds(character, currentCamera)
		end
		visual.box.Visible = espBox and left ~= nil
		local showLine = false
		if left then
			if espBox then
				visual.box.Position = UDim2.fromOffset(left, top)
				visual.box.Size = UDim2.fromOffset(right - left, bottom - top)
			end
			if espLine then
				local viewport = currentCamera.ViewportSize
				local origin = Vector2.new(viewport.X * 0.5, viewport.Y - 2)
				local destination = Vector2.new((left + right) * 0.5, bottom)
				local direction = destination - origin
				if direction.Magnitude >= 1 then
					local midpoint = (origin + destination) * 0.5
					visual.line.Position = UDim2.fromOffset(midpoint.X, midpoint.Y)
					visual.line.Size = UDim2.fromOffset(direction.Magnitude, 4)
					visual.line.Rotation = math.deg(math.atan2(direction.Y, direction.X))
					showLine = true
				end
			end
		end
		visual.line.Visible = showLine
	end

	local function update(deltaTime, force)
		if not overlay or not overlay.Parent then stopAll(); return end
		elapsed += deltaTime or 0
		local updateInfo = force or elapsed >= 0.1
		if updateInfo then elapsed = 0 end
		local currentCamera = workspace.CurrentCamera
		local myHumanoid = getHumanoid()
		local myRoot = myHumanoid and myHumanoid.RootPart
		local showInfo = espName or espHP or espDist
		for target in pairs(tracked) do
			local character = target.Character
			local humanoid = character and character:FindFirstChildOfClass("Humanoid")
			local root = humanoid and (humanoid.RootPart or character:FindFirstChild("HumanoidRootPart"))
			if not character or not character.Parent or not humanoid or humanoid.Health <= 0
				or not root or not root:IsA("BasePart") or not root:IsDescendantOf(character) then
				clearTarget(target)
			else
				local adornee = character:FindFirstChild("Head")
				if not adornee or not adornee:IsA("BasePart") then adornee = root end
				local visual = visuals[target]
				if visual and (visual.character ~= character or visual.adornee ~= adornee or not visual.info.Parent
					or visual.box.Parent ~= overlay or visual.line.Parent ~= overlay) then
					clearTarget(target)
					visual = nil
				end
				local created = not visual
				if not visual then visual = buildTarget(target, character, adornee) end
				if espHL then
					if not visual.highlight or not visual.highlight.Parent then
						visual.highlight = makeVisual("Highlight", {
							Name = "BaoAnhESP", Adornee = character, FillColor = espColor,
							OutlineColor = Color3.new(1, 1, 1), FillTransparency = 0.6, OutlineTransparency = 0,
							DepthMode = Enum.HighlightDepthMode.AlwaysOnTop, Enabled = true,
						}, character)
					end
				elseif visual.highlight then
					visual.highlight:Destroy()
					visual.highlight = nil
				end
				visual.info.Enabled = showInfo
				if updateInfo or created then
					visual.boxColor.Color = espColor
					visual.lineColor.BackgroundColor3 = espColor
					if visual.highlight then visual.highlight.FillColor = espColor end
					if showInfo then
						visual.text.TextColor3 = espColor
						local lines = {}
						if espName then
							local displayName = target.DisplayName:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;")
							table.insert(lines, displayName)
						end
						if espHP then
							local ratio = humanoid.MaxHealth > 0 and math.clamp(humanoid.Health / humanoid.MaxHealth, 0, 1) or 0
							local healthColor = Color3.fromRGB(255, 60, 60):Lerp(Color3.fromRGB(60, 230, 90), ratio)
							table.insert(lines, '<font color="#' .. healthColor:ToHex() .. '">❤ ' .. math.floor(humanoid.Health) .. "</font>")
						end
						if espDist and myRoot and myRoot.Parent then
							table.insert(lines, math.floor((root.Position - myRoot.Position).Magnitude) .. " studs")
						end
						visual.text.Text = table.concat(lines, "\n")
					end
				end
				updateGeometry(visual, character, currentCamera)
			end
		end
	end

	local function trackTarget(target)
		if target ~= player then tracked[target] = true end
	end

	espRefresh = function()
		if disposed then return end
		if not (espHL or espName or espHP or espDist or espBox or espLine) then stopAll(); return end
		if overlay and not overlay.Parent then stopAll() end
		if not renderConnection then
			local playerGui = player:FindFirstChildOfClass("PlayerGui")
			if not playerGui then return end
			overlay = makeVisual("ScreenGui", {
				Name = "BaoAnhESPOverlay", IgnoreGuiInset = true, ClipToDeviceSafeArea = false,
				ResetOnSpawn = false, ZIndexBehavior = Enum.ZIndexBehavior.Sibling, DisplayOrder = 90,
			}, playerGui)
			overlay.ScreenInsets = Enum.ScreenInsets.None
			table.insert(connections, Players.PlayerAdded:Connect(trackTarget))
			table.insert(connections, Players.PlayerRemoving:Connect(function(target)
				tracked[target] = nil
				clearTarget(target)
			end))
			for _, target in ipairs(Players:GetPlayers()) do trackTarget(target) end
			renderConnection = RunService.RenderStepped:Connect(update)
		end
		update(0, true)
	end

	espShutdown = function()
		disposed = true
		stopAll()
	end
end

----------------------------------------------------------------
-- LOGIC ESP RƯƠNG: đánh dấu TẤT CẢ rương trong map (viền vàng + tên + khoảng cách, xuyên tường)
-- Cách nhận biết: đối tượng (Model / Part) có tên chứa một trong CHEST_KEYWORDS.
-- >>> Rương trong game của bạn tên khác thì sửa CHEST_KEYWORDS cho đúng tên đó. <<<
-- LƯU Ý: nếu game bật StreamingEnabled thì rương ở xa (chưa tải) sẽ chưa hiện cho tới khi lại gần.
----------------------------------------------------------------
local CHEST_KEYWORDS = { "chest", "rương", "ruong" } -- viết thường; tìm theo kiểu "có chứa"
local CHEST_IGNORE = { "plate", "armor", "armour" } -- bỏ qua tên chứa các từ này (vd: ChestPlate = áo giáp)
local CHEST_COLOR = Color3.fromRGB(255, 200, 40)

local chestOn = false
local chestObjs = {} -- chestObjs[inst] = { hl = Highlight, gui = BillboardGui, txt = TextLabel, part = BasePart }
local chestConns = {}
local chestBeat, chestLast = nil, 0

local function chestMatch(name)
	local l = string.lower(name)
	for _, bad in ipairs(CHEST_IGNORE) do
		if string.find(l, bad, 1, true) then return false end
	end
	for _, kw in ipairs(CHEST_KEYWORDS) do
		if string.find(l, kw, 1, true) then return true end
	end
	return false
end

local function chestClear(inst)
	local o = chestObjs[inst]
	if o then
		if o.hl then o.hl:Destroy() end
		if o.gui then o.gui:Destroy() end
		chestObjs[inst] = nil
	end
end

local function chestAdd(inst)
	if chestObjs[inst] then return end
	if not (inst:IsA("Model") or inst:IsA("BasePart")) then return end
	if not chestMatch(inst.Name) then return end
	-- nằm trong một rương đã đánh dấu rồi (vd: nắp rương) thì bỏ qua để khỏi trùng
	local a = inst.Parent
	while a and a ~= workspace do
		if chestObjs[a] then return end
		a = a.Parent
	end
	-- không đánh dấu đồ nằm trên người chơi
	for _, plr in ipairs(Players:GetPlayers()) do
		if plr.Character and inst:IsDescendantOf(plr.Character) then return end
	end
	local part = inst:IsA("BasePart") and inst or inst.PrimaryPart or inst:FindFirstChildWhichIsA("BasePart", true)
	if not part then return end

	local hl = Instance.new("Highlight")
	hl.Name = "BaoAnhMark"
	hl.Adornee = inst
	hl.FillColor, hl.OutlineColor = CHEST_COLOR, Color3.new(1, 1, 1)
	hl.FillTransparency, hl.OutlineTransparency = 0.5, 0
	hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop -- hiện xuyên tường
	hl.Parent = inst

	local gui = Instance.new("BillboardGui")
	gui.Name = "BaoAnhMarkInfo"
	gui.Adornee = part
	gui.AlwaysOnTop = true
	gui.Size = UDim2.fromOffset(200, 50)
	gui.StudsOffset = Vector3.new(0, 3, 0)
	gui.Parent = part

	local txt = Instance.new("TextLabel")
	txt.BackgroundTransparency = 1
	txt.Size = UDim2.fromScale(1, 1)
	txt.Font = Enum.Font.SourceSansBold
	txt.TextSize = 16
	txt.TextColor3 = CHEST_COLOR
	txt.TextStrokeTransparency = 0.3
	txt.Text = "📦 " .. inst.Name
	txt.Parent = gui

	chestObjs[inst] = { hl = hl, gui = gui, txt = txt, part = part }
end

-- cập nhật khoảng cách (~4 lần/giây) và dọn rương đã biến mất
local function chestUpdate()
	local myHum = getHumanoid()
	local myRoot = myHum and myHum.RootPart
	for inst, o in pairs(chestObjs) do
		if inst.Parent and o.part.Parent then
			local t = "📦 " .. inst.Name
			if myRoot then
				t = t .. "\n" .. math.floor((o.part.Position - myRoot.Position).Magnitude) .. " studs"
			end
			o.txt.Text = t
		else
			chestClear(inst)
		end
	end
end

local function chestStop()
	for _, c in ipairs(chestConns) do c:Disconnect() end
	table.clear(chestConns)
	if chestBeat then
		chestBeat:Disconnect()
		chestBeat = nil
	end
	for inst in pairs(chestObjs) do chestClear(inst) end
end

local function chestRefresh()
	if chestOn then
		if chestBeat then return end
		table.insert(chestConns, workspace.DescendantAdded:Connect(function(d)
			if chestOn then chestAdd(d) end
		end))
		table.insert(chestConns, workspace.DescendantRemoving:Connect(function(d)
			if chestObjs[d] then chestClear(d) end
		end))
		chestBeat = RunService.Heartbeat:Connect(function()
			local now = os.clock()
			if now - chestLast < 0.25 then return end
			chestLast = now
			chestUpdate()
		end)
		-- quét toàn bộ map (chia nhỏ để không bị giật)
		task.spawn(function()
			local n = 0
			for _, d in ipairs(workspace:GetDescendants()) do
				if not chestOn then return end
				chestAdd(d)
				n += 1
				if n % 1500 == 0 then task.wait() end
			end
		end)
	else
		chestStop()
	end
end

-- chết / hồi sinh: tự áp dụng lại cho nhân vật mới
player.CharacterAdded:Connect(function(char)
	local hum = char:WaitForChild("Humanoid", 10)
	if not hum then return end
	if godOn then startGod(hum) end
	if speedOn then startSpeed(hum) end
	if jumpOn then startJump(hum) end
	if fullOn then startFull(hum) end
	if invisOn then startInvis(char, hum) end
end)


----------------------------------------------------------------
-- FAKE AN EGG: Farm / Steal / Rebirth / Shops / Sell (chuyển từ "Fake an Egg Hub")
--   Farm    : mua trứng tốt nhất → mang về ổ trống → tự ấp khi hết giờ
--   Steal   : vào chuồng người khác lấy pet nặng nhất
--   Rebirth : chỉ mua đúng trứng mà lần rebirth tiếp theo yêu cầu, tự rebirth khi đủ điều kiện
--   Shops   : tự mua scanner / thức ăn pet tốt nhất đủ tiền
--   Sell    : tự bán pet theo bộ lọc
-- Yêu cầu: chạy bằng executor có fireproximityprompt và chỉ dùng trong game "Fake an Egg".
-- Gom hết vào bảng Farm để không vượt giới hạn 200 biến local của Luau.
----------------------------------------------------------------
local Farm = { ui = {} }
Farm.notify = function() end -- được gán = setStatus ngay sau khi thanh trạng thái được tạo
Farm.PRICE_NAMES = { "1M", "10M", "100M", "1B", "10B", "100B", "1T" }
Farm.PRICE_CAPS = {
	["1M"] = 1e6, ["10M"] = 1e7, ["100M"] = 1e8, ["1B"] = 1e9, ["10B"] = 1e10, ["100B"] = 1e11, ["1T"] = 1e12,
}
Farm.WEIGHTS = { 0, 100, 500, 1000, 2500, 5000, 10000, 25000, 50000, 100000 } -- mức cân nặng tối thiểu khi trộm
Farm.SHOP_CAPS = { 1e5, 1e6, 5e6, 25e6, 1e8, 5e8, 2.5e9 } -- mức giá tối đa mỗi lần mua ở Shops
Farm.SELL_UNDER = { 0, 100, 500, 1000, 5000, 10000, 50000, 100000 } -- 0 = không giới hạn cân nặng

function Farm.short(n) -- 2500000 → "2.5M"
	n = n or 0
	for _, u in ipairs({ { 1e12, "T" }, { 1e9, "B" }, { 1e6, "M" }, { 1e3, "K" } }) do
		if n >= u[1] then
			local v = n / u[1]
			if v == math.floor(v) then return string.format("%.0f", v) .. u[2] end
			return string.format("%.1f", v) .. u[2]
		end
	end
	return string.format("%.0f", n)
end

do
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	local LocalPlayer = player

	local cfg = {
		-- Farm
		farm = false,
		skipFake = true, -- chỉ mua trứng thật (bỏ qua trứng giả có người chơi trốn bên trong)
		autoHatch = true,
		onlyBetter = false, -- chỉ mua trứng cho ra pet nặng hơn pet tốt nhất đang có
		maxPriceEnabled = false,
		maxPrice = 1e12,
		eggNames = {}, -- eggNames["Tên trứng"] = true (rỗng = mọi loại)
		eggRarities = {}, -- eggRarities["Độ hiếm"] = true (rỗng = mọi độ hiếm)
		-- Steal
		steal = false,
		minWeight = 1000,
		returnHome = true,
		-- Rebirth
		rebirthFarm = false,
		rebirth = false, -- công tắc "Auto Rebirth" ở tab Tự Động
		-- Shops
		buyScanners = false,
		buyFood = false,
		scannerTypes = {},
		foodTypes = {},
		shopMax = 5e6,
		-- Sell
		autoSell = false,
		sellNames = {},
		sellRarities = {},
		sellUnder = 0,
		keepBest = true,
		sellEvery = 2,
	}
	local stats = { bought = 0, hatched = 0, stolen = 0, scanners = 0, food = 0, sold = 0 }
	local state = {
		text = "Đang chờ", egg = nil, pendingPrompt = nil, pendingAt = 0,
		shop = { scanner = "hết hàng", food = "hết hàng" },
		sell = "không có gì để bán",
	}
	local hatchCooldown = setmetatable({}, { __mode = "k" })
	local buyBlocked = setmetatable({}, { __mode = "k" })
	local Remotes, Eggs, Animals, Rebirth, Scanners, Food -- dữ liệu của game, tải ngầm ngay bên dưới

	Farm.cfg, Farm.stats, Farm.state = cfg, stats, state
	Farm.fmt = nil -- gán bên dưới

	task.spawn(function()
		Remotes = ReplicatedStorage:WaitForChild("RemoteEvents", 20)
		for _, name in ipairs({ "Eggs", "Animals", "Rebirth", "Scanners", "Food" }) do
			local m = ReplicatedStorage:WaitForChild(name, 20)
			if m and m:IsA("ModuleScript") then
				local ok, res = pcall(require, m)
				if ok and type(res) == "table" then
					if name == "Eggs" then Eggs = res
					elseif name == "Animals" then Animals = res
					elseif name == "Rebirth" then Rebirth = res
					elseif name == "Scanners" then Scanners = res
					else Food = res end
				end
			end
		end
	end)

	local function fmt(n) -- 1234567 → "1,234,567"
		local s = string.format("%.0f", n or 0)
		return (s:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", ""))
	end
	Farm.fmt = fmt

	local function remote(name)
		return Remotes and Remotes:FindFirstChild(name) or nil
	end

	---------------- hàm phụ trợ ----------------
	local function rootPart()
		local char = LocalPlayer.Character
		if char and char.Parent then
			return char:FindFirstChild("HumanoidRootPart")
		end
		return nil
	end

	local function teleport(position)
		local hrp = rootPart()
		if not hrp or typeof(position) ~= "Vector3" then
			return false
		end
		hrp.CFrame = CFrame.new(position + Vector3.new(0, 3, 0))
		return true
	end

	local function promptPosition(prompt)
		local parent = prompt and prompt.Parent
		if not parent then return nil end
		if parent:IsA("Attachment") then return parent.WorldPosition end
		if parent:IsA("BasePart") then return parent.Position end
		if parent:IsA("PVInstance") then return parent:GetPivot().Position end
		return nil
	end

	local function firePrompt(prompt)
		if not prompt or not prompt.Parent then return false end
		local ok = pcall(function()
			if not prompt.Enabled then prompt.Enabled = true end
			fireproximityprompt(prompt)
		end)
		return ok
	end

	local function myBase()
		local index = LocalPlayer:GetAttribute("Base")
		local bases = workspace:FindFirstChild("Bases")
		if not (index and bases) then return nil end
		return bases:FindFirstChild(tostring(index))
	end

	local function leaderstat(name)
		local ls = LocalPlayer:FindFirstChild("leaderstats")
		local value = ls and ls:FindFirstChild(name)
		return value and value.Value or 0
	end
	local function cash() return leaderstat("Cash") end
	local function rebirths() return leaderstat("Rebirths") end

	local function bestOwnWeight()
		local best = 0
		local folder = LocalPlayer:FindFirstChild("Slots")
		if folder then
			for _, slot in ipairs(folder:GetChildren()) do
				local w = slot:GetAttribute("Weight")
				if w and w > best then best = w end
			end
		end
		return best
	end

	local function petWeight(name)
		local animal = name and Animals and Animals[name]
		return animal and animal.weight or 0
	end

	local function freeNest()
		local base = myBase()
		local slots = LocalPlayer:FindFirstChild("Nests")
		if not (base and slots) then return nil end
		local nests = base:FindFirstChild("Nests")
		if not nests then return nil end
		for _, nest in ipairs(nests:GetChildren()) do
			local slot = slots:FindFirstChild(nest.Name)
			if slot and slot:GetAttribute("Owned") and not slot:GetAttribute("Egg") then
				return nest
			end
		end
		return nil
	end

	-- trứng thật có thể mua: là model trứng, đã bay tới, và không có người chơi trốn bên trong
	local function isRealEgg(model)
		if not model or not model.Parent then return false end
		if model:GetAttribute("Owner") ~= nil then return false end
		if not model:GetAttribute("IsEgg") or not model:GetAttribute("BaseName") then return false end
		if not model:GetAttribute("CountdownEnd") then return false end
		for _, child in ipairs(model:GetDescendants()) do
			if child:IsA("Humanoid") or child:IsA("Player") then
				return false
			end
		end
		return true
	end

	-- trứng mà lần rebirth tiếp theo yêu cầu ấp ra
	local function rebirthAnimal()
		if not Rebirth then return nil end
		local ok, data = pcall(Rebirth.getNext, rebirths())
		if ok and type(data) == "table" then return data.animal end
		return nil
	end

	---------------- danh sách cho các ô chọn ----------------
	local function uniqueSorted(source, field)
		local out, seen = {}, {}
		if source then
			for _, info in pairs(source) do
				local v = type(info) == "table" and info[field]
				if v and not seen[v] then
					seen[v] = true
					table.insert(out, v)
				end
			end
		end
		table.sort(out)
		return out
	end
	function Farm.eggNames() return uniqueSorted(Eggs and Eggs.ByName, "name") end
	function Farm.eggRarities() return uniqueSorted(Eggs and Eggs.ByName, "rarityType") end

	local function itemNameList(module)
		local out = {}
		if module and module.List then
			for _, item in ipairs(module.List) do
				table.insert(out, item.name)
			end
		end
		table.sort(out)
		return out
	end
	function Farm.scannerNames() return itemNameList(Scanners) end
	function Farm.foodNames() return itemNameList(Food) end

	function Farm.petNames()
		local out = {}
		if Animals then
			for name, info in pairs(Animals) do
				if type(name) == "string" and type(info) == "table" and info.weight and info.rarityType then
					table.insert(out, name)
				end
			end
		end
		table.sort(out)
		return out
	end

	function Farm.petRarities()
		local out, seen = {}, {}
		if Animals then
			for _, info in pairs(Animals) do
				if type(info) == "table" and info.weight and info.rarityType and not seen[info.rarityType] then
					seen[info.rarityType] = true
					table.insert(out, info.rarityType)
				end
			end
		end
		table.sort(out)
		return out
	end

	---------------- 1. FARM: chọn trứng để mua ----------------
	-- mode = "normal" hoặc "rebirth" (chỉ mua đúng trứng mà lần rebirth tiếp theo cần)
	local function pickEgg(mode)
		if not (Eggs and Animals) then return nil end
		local rebirthMode = mode == "rebirth"
		local wanted = rebirthMode and rebirthAnimal() or nil
		if rebirthMode and not wanted then return nil end -- không có yêu cầu rebirth thì không mua gì
		local best, bestScore = nil, -1
		local money = cash()
		local bestWeight = bestOwnWeight()
		local now = os.clock()
		local names, rarities = cfg.eggNames, cfg.eggRarities
		local namesOn, raritiesOn = next(names) ~= nil, next(rarities) ~= nil
		local realOnly = rebirthMode or cfg.skipFake -- farm rebirth luôn bỏ qua trứng giả

		for _, prompt in ipairs(workspace:GetDescendants()) do
			if prompt:IsA("ProximityPrompt") and prompt.ActionText == "Buy" and prompt.Parent and prompt.Enabled then
				local model = prompt.Parent
				local eggName = model:GetAttribute("BaseName")
				local info = eggName and Eggs.ByName[eggName]
				local blockedUntil = buyBlocked[prompt]
				if info and info.price <= money
					and (not cfg.maxPriceEnabled or info.price <= cfg.maxPrice)
					and not (blockedUntil and blockedUntil > now)
					and (not realOnly or isRealEgg(model)) then
					local petName = info.pet or info.name
					local allowed = true
					if wanted and petName ~= wanted then allowed = false end
					if allowed and namesOn and not names[eggName] then allowed = false end
					if allowed and raritiesOn and not rarities[info.rarityType or "Common"] then allowed = false end
					if allowed then
						local weight = petWeight(petName)
						if rebirthMode or not cfg.onlyBetter or weight > bestWeight then
							local score = info.rarity or 0
							if score > bestScore then
								best, bestScore = { prompt = prompt, info = info, weight = weight, price = info.price }, score
							end
						end
					end
				end
			end
		end
		return best
	end

	-- Mỗi lần gọi ấp 1 trứng đã hết giờ: server kiểm tra khoảng cách nên phải đứng cạnh ổ rồi mới bấm.
	local function hatchReady()
		local now = workspace:GetServerTimeNow()
		local eggs = workspace:FindFirstChild("NestEggs")
		if not eggs then return false end
		for _, model in ipairs(eggs:GetChildren()) do
			if model:GetAttribute("Owner") == LocalPlayer.Name and (hatchCooldown[model] or 0) < now then
				local prompt
				for _, child in ipairs(model:GetDescendants()) do
					if child:IsA("ProximityPrompt") and child.ActionText == "Hatch" then
						prompt = child
						break
					end
				end
				if prompt and prompt.Enabled then
					hatchCooldown[model] = now + 2
					if teleport(model:GetPivot().Position + Vector3.new(0, -1, 3)) then
						task.wait(0.12)
						if firePrompt(prompt) then
							state.text = "Đang ấp trứng"
							stats.hatched += 1
							Farm.notify("Đã ấp: " .. tostring(model:GetAttribute("BaseName")))
						end
					end
					return true
				end
			end
		end
		return false
	end

	local function farmStep(mode)
		local rebirthMode = mode == "rebirth"

		if LocalPlayer:GetAttribute("Carrying") then -- đang cầm trứng → mang về ổ trống
			local nest = freeNest()
			if nest then
				teleport(nest:GetPivot().Position)
				state.text = rebirthMode and "Đang farm cho rebirth" or "Đang mang trứng về ổ"
			else
				state.text = "Hết ổ trống"
			end
			return
		end

		-- không còn ổ trống thì mua cũng chỉ làm rơi trứng xuống đất
		if not freeNest() then
			state.text = "Hết ổ trống"
			return
		end

		-- đang chờ lệnh mua trước đó có hiệu lực
		if state.pendingPrompt then
			if os.clock() - state.pendingAt > 1.5 then
				buyBlocked[state.pendingPrompt] = os.clock() + 20 -- mua không được → tạm bỏ qua trứng này 20 giây
				state.pendingPrompt = nil
				state.text = "Không có trứng phù hợp"
			end
			return
		end

		if not (Eggs and Animals) then
			state.text = "Chỉ chạy trong game Fake an Egg"
			return
		end

		local egg = pickEgg(mode)
		if not egg then
			if rebirthMode then
				state.text = rebirthAnimal() and "Không có trứng phù hợp" or "Không có yêu cầu rebirth"
			else
				state.text = cash() < 100 and "Không đủ tiền" or "Không có trứng phù hợp"
			end
			return
		end

		state.text = rebirthMode and "Đang farm cho rebirth" or "Đang mua trứng"
		local position = promptPosition(egg.prompt)
		if position and teleport(position) then
			task.wait(0.15)
			if firePrompt(egg.prompt) then
				state.pendingPrompt = egg.prompt
				state.pendingAt = os.clock()
				state.egg = egg.info.displayName or egg.info.name
				Farm.notify("Mua " .. tostring(state.egg) .. " ($" .. fmt(egg.price) .. ")")
			end
		end
	end

	local function confirmBuy() -- xác nhận mua thành công khi nhân vật đã cầm trứng
		if state.pendingPrompt and LocalPlayer:GetAttribute("Carrying") then
			state.pendingPrompt = nil
			stats.bought += 1
			Farm.notify("Đã mua: " .. tostring(state.egg))
		end
	end

	---------------- 2. STEAL: trộm pet nặng nhất ở chuồng người khác ----------------
	local stealCooldown = 0

	local function pickStolenPet()
		local best, bestWeight = nil, cfg.minWeight
		local me = LocalPlayer.Name
		local bases = workspace:FindFirstChild("Bases")
		if not bases then return nil end
		for _, base in ipairs(bases:GetChildren()) do
			local owner = base:GetAttribute("Owner")
			if owner and owner ~= me then
				for _, pet in ipairs(base:GetChildren()) do
					local weight = petWeight(pet.Name)
					if pet:IsA("Model") and weight > bestWeight then
						for _, child in ipairs(pet:GetDescendants()) do
							if child:IsA("ProximityPrompt") and child.ActionText == "Steal" then
								best, bestWeight = { prompt = child, pet = pet, base = base, name = pet.Name, weight = weight }, weight
								break
							end
						end
					end
				end
			end
		end
		return best
	end

	local function stealStep()
		local now = os.clock()
		if now < stealCooldown then return end

		if LocalPlayer:GetAttribute("Carrying") then -- đang cầm pet vừa trộm → mang về ổ
			local nest = freeNest()
			if nest then
				teleport(nest:GetPivot().Position)
				state.text = "Đang mang pet về ổ"
			end
			return
		end

		if not Animals then
			state.text = "Chỉ chạy trong game Fake an Egg"
			return
		end

		local target = pickStolenPet()
		if not target then
			state.text = "Không có mục tiêu"
			return
		end

		state.text = "Đang trộm pet"
		local position = promptPosition(target.prompt)
		if position and teleport(position) then
			task.wait(0.2)
			local fired = firePrompt(target.prompt)
			if not fired then -- bấm prompt không được thì gửi thẳng lệnh trộm lên server
				local owner = target.base:GetAttribute("Owner")
				local victim = owner and Players:FindFirstChild(owner)
				local ev = remote("StealEvent")
				if victim and ev then
					pcall(function() ev:FireServer(victim.UserId, target.pet.Name) end)
					fired = true
				end
			end
			if fired then
				stats.stolen += 1
				stealCooldown = now + 1.5
				Farm.notify("Trộm " .. target.name .. " (nặng " .. fmt(target.weight) .. ")")
				if cfg.returnHome then
					local base = myBase()
					local spawnPart = base and base:FindFirstChild("Spawn")
					if spawnPart and spawnPart:IsA("BasePart") then
						teleport(spawnPart.Position)
					end
				end
			end
		end
	end

	---------------- 3. REBIRTH: tự rebirth khi đủ điều kiện ----------------
	local rebirthCooldown = 0
	local function rebirthStep()
		if not (cfg.rebirth or cfg.rebirthFarm) or not Rebirth then return end
		local now = os.clock()
		if now < rebirthCooldown then return end
		local ok, can = pcall(Rebirth.CanRebirth, LocalPlayer)
		local ev = remote("RebirthEvent")
		if ok and can and ev then
			rebirthCooldown = now + 3
			local before = rebirths()
			ev:FireServer()
			Farm.notify("Rebirth! (trước đó: " .. tostring(before) .. ")")
		end
	end

	---------------- 4. SHOPS: tự mua scanner / thức ăn ----------------
	local scannerCooldown, foodCooldown = 0, 0
	local shopPending = { scanner = nil, food = nil }

	local function shopPosition(name)
		local map = workspace:FindFirstChild("Map")
		local model = map and map:FindFirstChild(name)
		return model and model:GetPivot().Position or nil
	end

	local function shopStock(kind, name)
		local module = kind == "scanner" and Scanners or Food
		if not module then return 0 end
		local ok, stock = pcall(module.stock, LocalPlayer, name)
		if ok and type(stock) == "number" then return stock end
		local prefix = kind == "scanner" and "Stock" or "FoodStock"
		return LocalPlayer:GetAttribute(prefix .. name) or 0
	end

	-- món tốt nhất đã chọn, còn hàng, đã mở khóa và đủ tiền
	local function bestShopItem(kind)
		local module = kind == "scanner" and Scanners or Food
		if not (module and module.List) then return nil, 0 end
		local chosen = kind == "scanner" and cfg.scannerTypes or cfg.foodTypes
		local filterOn = next(chosen) ~= nil
		local money = cash()
		local best, bestRank, bestStock = nil, -1, 0
		for _, item in ipairs(module.List) do
			local stock = shopStock(kind, item.name)
			local unlocked = rebirths() >= (item.rebirth or 0)
			local allowed = not filterOn or chosen[item.name] == true
			if allowed and unlocked and stock > 0 and item.price <= money and item.price <= cfg.shopMax then
				local rank = item.rank or 0
				if rank > bestRank then
					best, bestRank, bestStock = item, rank, stock
				end
			end
		end
		return best, bestStock
	end

	local function confirmShopPurchase(kind)
		local pending = shopPending[kind]
		if not pending then return end
		local currentStock = shopStock(kind, pending.item.name)
		if currentStock < pending.stock or cash() < pending.cash then
			if kind == "scanner" then stats.scanners += 1 else stats.food += 1 end
			Farm.notify("Đã mua " .. pending.item.name .. " ($" .. fmt(pending.item.price) .. ")")
			shopPending[kind] = nil
		elseif os.clock() - pending.at > 2 then
			shopPending[kind] = nil
		end
	end

	local function shopStep(kind)
		local now = os.clock()
		if (kind == "scanner" and now < scannerCooldown) or (kind == "food" and now < foodCooldown) then
			return false
		end

		local item, stock = bestShopItem(kind)
		if not item then
			state.shop[kind] = "hết hàng / chưa đủ tiền"
			return false
		end

		local ev = remote(kind == "scanner" and "ScannerEvent" or "FoodEvent")
		local position = shopPosition(kind == "scanner" and "Scanners" or "Food")
		if not ev or not position or not teleport(position + Vector3.new(0, 2, 5)) then
			return false
		end

		task.wait(0.15)
		local ok = pcall(function() ev:FireServer("Buy", item.name) end)
		if not ok then return false end

		if kind == "scanner" then
			scannerCooldown = os.clock() + 2
		else
			foodCooldown = os.clock() + 2
		end
		shopPending[kind] = { item = item, stock = stock, cash = cash(), at = os.clock() }
		state.shop[kind] = item.name
		return true
	end

	---------------- 5. SELL: tự bán pet theo bộ lọc ----------------
	local sellCooldown = 0
	local sellPending = nil

	local function parseInventoryPet(attr)
		local ok, key, pet, animal = pcall(function()
			local decoded = Animals.decodeAttr(attr)
			local name = Animals.parseSlot(decoded)
			return decoded, name, name and Animals[name] or nil
		end)
		if ok then return key, pet, animal end
		return nil
	end

	local function bestInventoryWeight()
		local inventory = LocalPlayer:FindFirstChild("Inventory")
		local best = 0
		if not (inventory and Animals) then return best end
		for attr, count in pairs(inventory:GetAttributes()) do
			if type(count) == "number" and count > 0 then
				local _, _, animal = parseInventoryPet(attr)
				if animal and (animal.weight or 0) > best then
					best = animal.weight
				end
			end
		end
		return best
	end

	-- pet đầu tiên trong túi khớp mọi bộ lọc bán
	local function sellKey()
		local inventory = LocalPlayer:FindFirstChild("Inventory")
		if not (inventory and Animals) then return nil end
		local best = math.max(bestOwnWeight(), bestInventoryWeight())
		local names, rarities = cfg.sellNames, cfg.sellRarities
		local namesOn, raritiesOn = next(names) ~= nil, next(rarities) ~= nil

		for attr, count in pairs(inventory:GetAttributes()) do
			if type(count) == "number" and count > 0
				and not (attr:match("_Size$") or attr:match("_Weight$") or attr:match("_Mood$")) then
				local key, pet, animal = parseInventoryPet(attr)
				if key and animal then
					local weight = animal.weight or 0
					local rarity = animal.rarityType or "Common"
					local allowed = true
					if namesOn and not names[pet] then allowed = false end
					if allowed and raritiesOn and not rarities[rarity] then allowed = false end
					if allowed and cfg.sellUnder > 0 and weight >= cfg.sellUnder then allowed = false end
					-- giữ lại 1 con nặng nhất, kể cả khi chưa trang bị pet nào
					if allowed and cfg.keepBest and weight >= best and count <= 1 then allowed = false end
					if allowed then
						return key, pet, weight, attr, count
					end
				end
			end
		end
		return nil
	end

	local function confirmSale()
		if not sellPending then return end
		local inventory = LocalPlayer:FindFirstChild("Inventory")
		local count = inventory and inventory:GetAttribute(sellPending.attr) or 0
		if type(count) == "number" and count < sellPending.count then
			stats.sold += 1
			Farm.notify("Đã bán " .. tostring(sellPending.pet) .. " (nặng " .. fmt(sellPending.weight) .. ")")
			sellPending = nil
		elseif os.clock() - sellPending.at > 2 then
			sellPending = nil
		end
	end

	local function sellStep()
		local now = os.clock()
		if now < sellCooldown then return false end

		local key, pet, weight, attr, count = sellKey()
		if not key then
			state.sell = "không có gì để bán"
			return false
		end

		local ev = remote("SellEvent")
		local position = shopPosition("Sell")
		if not ev or not position or not teleport(position + Vector3.new(0, 2, 5)) then
			return false
		end

		task.wait(0.12)
		local ok = pcall(function() ev:FireServer(key) end)
		if not ok then return false end

		sellCooldown = os.clock() + math.max(0.5, cfg.sellEvery or 2)
		sellPending = { attr = attr, count = count, pet = pet, weight = weight, at = os.clock() }
		state.sell = tostring(pet)
		return true
	end

	---------------- vòng lặp chính ----------------
	local function tick()
		confirmBuy()
		confirmShopPurchase("scanner")
		confirmShopPurchase("food")
		confirmSale()

		if not (cfg.farm or cfg.rebirthFarm) then state.pendingPrompt = nil end

		-- mỗi nhịp chỉ làm 1 hành động dịch chuyển: ấp trứng → mua shop / bán pet → farm / trộm
		if cfg.autoHatch and hatchReady() then return end

		local did = false
		if cfg.buyScanners then did = shopStep("scanner") end
		if not did and cfg.buyFood then did = shopStep("food") end
		if not did and cfg.autoSell then did = sellStep() end
		if did then return end

		if cfg.rebirthFarm then
			farmStep("rebirth")
		elseif cfg.farm then
			farmStep("normal")
		elseif cfg.steal then
			stealStep()
		else
			state.text = "Đang chờ"
		end

		rebirthStep()
	end

	---------------- giao diện gọi vào ----------------
	function Farm.checkExecutor()
		if type(fireproximityprompt) ~= "function" then
			Farm.notify("Thiếu fireproximityprompt - cần executor hỗ trợ")
		end
	end

	function Farm.refreshInfo()
		local ui = Farm.ui
		local function set(l, text) if l then l.Text = text end end
		-- Farm
		set(ui.state, state.text)
		set(ui.cash, "$" .. fmt(cash()))
		set(ui.best, fmt(bestOwnWeight()))
		set(ui.bought, tostring(stats.bought))
		set(ui.hatched, tostring(stats.hatched))
		-- Steal
		set(ui.stState, state.text)
		set(ui.stStolen, tostring(stats.stolen))
		-- Rebirth
		set(ui.rbNeed, rebirthAnimal() or "không có yêu cầu")
		set(ui.rbState, state.text)
		set(ui.rbCount, tostring(rebirths()))
		-- Shops
		set(ui.shScanner, tostring(state.shop.scanner) .. " · " .. stats.scanners)
		set(ui.shFood, tostring(state.shop.food) .. " · " .. stats.food)
		set(ui.shCash, "$" .. fmt(cash()))
		-- Sell
		set(ui.slState, tostring(state.sell))
		set(ui.slSold, tostring(stats.sold))
	end

	local function anyOn()
		return cfg.farm or cfg.autoHatch or cfg.steal or cfg.rebirthFarm or cfg.rebirth
			or cfg.buyScanners or cfg.buyFood or cfg.autoSell
	end

	-- vòng lặp chính (chạy lại script thì vòng cũ tự dừng)
	_G.__BaoAnhFarmGen = (_G.__BaoAnhFarmGen or 0) + 1
	local gen = _G.__BaoAnhFarmGen
	task.spawn(function()
		while _G.__BaoAnhFarmGen == gen do
			task.wait(0.35)
			if anyOn() then
				local ok, err = xpcall(tick, debug.traceback)
				if not ok then warn("[bảo anh] Fake an Egg lỗi: " .. tostring(err)) end
			end
			Farm.refreshInfo()
		end
	end)
end

----------------------------------------------------------------
-- GẮN LOGIC TẠI ĐÂY (tên = chữ trên nút, on = true/false)
----------------------------------------------------------------
local Callbacks = {
	["Jump Power"] = function(on)
		jumpOn = on
		local hum = getHumanoid()
		if on then
			if hum then startJump(hum) end
		else
			stopJump(hum)
		end
	end,
	["Full Health"] = function(on)
		fullOn = on
		local hum = getHumanoid()
		if on then
			if hum then startFull(hum) end
		else
			stopFull()
		end
	end,
	["God Mode"] = function(on)
		godOn = on
		local hum = getHumanoid()
		if on then
			if hum then startGod(hum) end
		else
			stopGod(hum)
		end
	end,
	["Speed Hack"] = function(on)
		speedOn = on
		local hum = getHumanoid()
		if on then
			if hum then startSpeed(hum) end
		else
			stopSpeed(hum)
		end
	end,
	["Tàn Hình"] = function(on)
		invisOn = on
		local char = player.Character
		if on then
			if char then startInvis(char, getHumanoid()) end
		else
			stopInvis(getHumanoid())
		end
	end,
	["Đi Xuyên Tường"] = function(on)
		noclipOn = on
		if on then
			startNoclip()
		else
			stopNoclip()
		end
	end,
	["ESP Người Chơi"] = function(on)
		espHL = on
		espRefresh()
	end,
	["ESP Khung"] = function(on)
		espBox = on
		espRefresh()
	end,
	["ESP Line"] = function(on)
		espLine = on
		espRefresh()
	end,
	["ESP Tên"] = function(on)
		espName = on
		espRefresh()
	end,
	["ESP Máu"] = function(on)
		espHP = on
		espRefresh()
	end,
	["ESP Khoảng Cách"] = function(on)
		espDist = on
		espRefresh()
	end,
	["ESP Rương"] = function(on)
		chestOn = on
		chestRefresh()
	end,
	["Auto Farm"] = function(on)
		Farm.cfg.farm = on
		if on then
			Farm.checkExecutor()
		else
			Farm.state.pendingPrompt = nil
		end
	end,
	["Chỉ Trứng Thật"] = function(on)
		Farm.cfg.skipFake = on
		if not on then Farm.notify("Cảnh báo: trứng giả sẽ lấy tiền của bạn!") end
	end,
	["Auto Hatch"] = function(on)
		Farm.cfg.autoHatch = on
		if on then Farm.checkExecutor() end
	end,
	["Chỉ Mua Trứng Tốt Hơn"] = function(on) Farm.cfg.onlyBetter = on end,
	["Giới Hạn Giá Trứng"] = function(on) Farm.cfg.maxPriceEnabled = on end,
	["Auto Steal"] = function(on)
		Farm.cfg.steal = on
		if on then Farm.checkExecutor() end
	end,
	["Về Nhà Sau Khi Trộm"] = function(on) Farm.cfg.returnHome = on end,
	["Farm Trứng Theo Rebirth"] = function(on)
		Farm.cfg.rebirthFarm = on
		if on then
			Farm.checkExecutor()
		else
			Farm.state.pendingPrompt = nil
		end
	end,
	["Auto Rebirth"] = function(on) Farm.cfg.rebirth = on end, -- công tắc ở tab Tự Động
	["Auto Mua Scanner"] = function(on) Farm.cfg.buyScanners = on end,
	["Auto Mua Thức Ăn"] = function(on) Farm.cfg.buyFood = on end,
	["Auto Sell Pets"] = function(on) Farm.cfg.autoSell = on end,
	["Giữ Lại Pet Mạnh Nhất"] = function(on) Farm.cfg.keepBest = on end,
	-- ["Auto Farm"] = function(on) print("Auto Farm:", on) end,
	-- ["Support"] = function() print("admin bảo anh") end,
}
local State = {} -- State["Auto Farm"] = true/false
local Groups = {} -- Groups["Farm"] = { "Auto Farm", "Auto Collect" } (gom công tắc theo nhóm)

----------------------------------------------------------------
-- Màu & font
----------------------------------------------------------------
local PANEL = Color3.fromRGB(10, 20, 52)
local ROW = Color3.fromRGB(14, 28, 68)
local ROWLINE = Color3.fromRGB(90, 130, 230)
local OFF = Color3.fromRGB(43, 59, 104)
local TEXT = Color3.fromRGB(232, 240, 255)
local MUTED = Color3.fromRGB(142, 163, 207)
local LINE = Color3.fromRGB(22, 48, 110)

local F_REG, F_MED, F_BOLD = Enum.Font.SourceSans, Enum.Font.SourceSansSemibold, Enum.Font.SourceSansBold

-- Cỡ chữ menu chính: TEXT_SCALE = 3 → mọi chữ trong menu chính to gấp 3 lần cỡ gốc.
-- Roblox giới hạn TextSize tối đa là 100 nên chữ nào có cỡ gốc trên 33 sẽ dừng ở 100.
local TEXT_SCALE = 3
local function ts(n)
	return math.min(100, math.floor(n * TEXT_SCALE + 0.5))
end
local SMALL = ts(22) -- cỡ phần chú thích trong tiêu đề, vd "(Cày)"

local THEME_NAMES = { "Xanh Dương", "Tím", "Xanh Lá", "Hồng" }
local THEMES = {
	["Xanh Dương"] = { Color3.fromRGB(47, 123, 255), Color3.fromRGB(56, 212, 255) },
	["Tím"] = { Color3.fromRGB(139, 92, 246), Color3.fromRGB(196, 181, 253) },
	["Xanh Lá"] = { Color3.fromRGB(34, 197, 94), Color3.fromRGB(134, 239, 172) },
	["Hồng"] = { Color3.fromRGB(236, 72, 153), Color3.fromRGB(249, 168, 212) },
}
local theme = { accent = THEMES["Xanh Dương"][1], accent2 = THEMES["Xanh Dương"][2] }
local themeFns = {}

local function themed(fn)
	fn()
	table.insert(themeFns, fn)
end

local function applyTheme(name)
	local t = THEMES[name]
	theme.accent, theme.accent2 = t[1], t[2]
	for _, fn in ipairs(themeFns) do
		fn()
	end
end

----------------------------------------------------------------
-- Hàm tiện ích
----------------------------------------------------------------
local function new(class, props, parent)
	local o = Instance.new(class)
	for k, v in pairs(props) do
		o[k] = v
	end
	o.Parent = parent
	return o
end

local function corner(o, r)
	return new("UICorner", { CornerRadius = UDim.new(0, r) }, o)
end

local function stroke(o, color, th, trans)
	return new("UIStroke", { Color = color, Thickness = th or 1, Transparency = trans or 0 }, o)
end

local function pad(o, t, r, b, l)
	return new("UIPadding", {
		PaddingTop = UDim.new(0, t), PaddingRight = UDim.new(0, r),
		PaddingBottom = UDim.new(0, b), PaddingLeft = UDim.new(0, l),
	}, o)
end

local function list(o, gap, order)
	return new("UIListLayout", { Padding = UDim.new(0, gap), SortOrder = order or Enum.SortOrder.LayoutOrder }, o)
end

local function label(parent, props, keepSize)
	local p = {
		BackgroundTransparency = 1, Font = F_MED, TextColor3 = TEXT, TextSize = 16,
		TextXAlignment = Enum.TextXAlignment.Left,
	}
	for k, v in pairs(props) do
		p[k] = v
	end
	if not keepSize then
		p.TextSize = ts(p.TextSize) -- nhân cỡ chữ (keepSize = true thì giữ nguyên)
	end
	return new("TextLabel", p, parent)
end

----------------------------------------------------------------
-- Cửa sổ chính
----------------------------------------------------------------
local W, H = 2600, 1640 -- chiều rộng, chiều cao menu chính (đã nới ra cho chữ gấp 3; menu tự thu nhỏ vừa màn hình)
local SIDE_W = 680 -- độ rộng thanh bên
local HEAD, FOOT = 200, 90 -- chiều cao phần đầu / chân menu
local MARG = 24 -- lề giữa các khối
local BODY_TOP, BOT = HEAD + 20, FOOT + 20

local gui = new("ScreenGui", {
	Name = "BaoAnhScriptUI", ResetOnSpawn = false, IgnoreGuiInset = true,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling, DisplayOrder = 100,
}, player:WaitForChild("PlayerGui"))
gui.Destroying:Connect(espShutdown)

local main = new("Frame", {
	Name = "Main", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromOffset(W, H), BackgroundColor3 = Color3.new(1, 1, 1),
}, gui)
corner(main, 44)
new("UIGradient", {
	Rotation = 90,
	Color = ColorSequence.new(Color3.fromRGB(11, 22, 54), Color3.fromRGB(6, 13, 36)),
}, main)

-- 7 sắc cầu vồng: đỏ, cam, vàng, lục, lam, chàm, tím (lặp lại đỏ ở cuối để vòng xoay liền mạch)
local RAINBOW = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 60, 60)),
	ColorSequenceKeypoint.new(1 / 7, Color3.fromRGB(255, 150, 40)),
	ColorSequenceKeypoint.new(2 / 7, Color3.fromRGB(255, 230, 60)),
	ColorSequenceKeypoint.new(3 / 7, Color3.fromRGB(60, 230, 90)),
	ColorSequenceKeypoint.new(4 / 7, Color3.fromRGB(50, 170, 255)),
	ColorSequenceKeypoint.new(5 / 7, Color3.fromRGB(90, 90, 255)),
	ColorSequenceKeypoint.new(6 / 7, Color3.fromRGB(190, 90, 255)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 60, 60)),
})

-- viền menu chính: 7 màu cầu vồng xoay vòng + nhấp nháy
-- (stroke để màu trắng để gradient hiện đúng màu cầu vồng)
local mainStroke = new("UIStroke", {
	Color = Color3.new(1, 1, 1), Thickness = 5, Transparency = 0.55,
	ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
}, main)
local mainGradient = new("UIGradient", { Color = RAINBOW }, mainStroke)
TweenService:Create(mainGradient, TweenInfo.new(4, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut, -1), { Rotation = 360 }):Play()
TweenService:Create(mainStroke, TweenInfo.new(0.7, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Transparency = 0 }):Play()

-- tự thu nhỏ cho vừa màn hình điện thoại
local uiScale = new("UIScale", { Scale = 0.1 }, main)
local function rescale()
	local viewport = gui.AbsoluteSize
	if viewport.X <= 0 or viewport.Y <= 0 then return end
	uiScale.Scale = math.clamp(math.min((viewport.X - 16) / W, (viewport.Y - 16) / H), 0.1, 1)
end
rescale()
gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(rescale)

-- Tab vuông Ẩn / Hiện menu chính (luôn hiển thị, kéo thả được)
local TAB = 56
local TAB_BG = Color3.fromRGB(11, 22, 54)
local toggleTab = new("TextButton", {
	Name = "ToggleTab", Text = "", AutoButtonColor = false, ZIndex = 50,
	Position = UDim2.new(0, 12, 0.5, -TAB / 2), Size = UDim2.fromOffset(TAB, TAB),
	BackgroundColor3 = TAB_BG,
}, gui)
corner(toggleTab, 12)

-- viền mỏng 7 màu (stroke để màu trắng để gradient hiện đúng màu cầu vồng)
local tabStroke = new("UIStroke", {
	Color = Color3.new(1, 1, 1), Thickness = 1.5, Transparency = 0.3,
	ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
}, toggleTab)
local tabGradient = new("UIGradient", { Color = RAINBOW }, tabStroke)

-- quầng sáng cầu vồng bên ngoài viền, nhấp sáng theo nhịp
local halo = new("Frame", {
	Name = "Halo", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.new(1, 4, 1, 4), BackgroundTransparency = 1, ZIndex = 49,
}, toggleTab)
corner(halo, 14)
local haloStroke = new("UIStroke", {
	Color = Color3.new(1, 1, 1), Thickness = 2, Transparency = 0.85,
	ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
}, halo)
local haloGradient = new("UIGradient", { Color = RAINBOW }, haloStroke)

-- hiệu ứng: màu cầu vồng xoay vòng liên tục + viền / quầng sáng nhấp nháy
local SPIN = TweenInfo.new(3, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut, -1)
local PULSE = TweenInfo.new(0.8, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true)
TweenService:Create(tabGradient, SPIN, { Rotation = 360 }):Play()
TweenService:Create(haloGradient, SPIN, { Rotation = 360 }):Play()
TweenService:Create(tabStroke, PULSE, { Transparency = 0 }):Play()
TweenService:Create(haloStroke, PULSE, { Transparency = 0.35, Thickness = 5 }):Play()

label(toggleTab, { Text = "👑", TextSize = 26, Font = F_BOLD, TextXAlignment = Enum.TextXAlignment.Center,
	ZIndex = 51, Position = UDim2.fromOffset(0, 4), Size = UDim2.new(1, 0, 0, 30) }, true) -- true = giữ nguyên cỡ chữ (tab nhỏ không nhân)
local tabText = label(toggleTab, { Text = "ẨN", TextSize = 13, Font = F_BOLD, TextXAlignment = Enum.TextXAlignment.Center,
	ZIndex = 51, Position = UDim2.fromOffset(0, 36), Size = UDim2.new(1, 0, 0, 14) }, true)

local function paintTab()
	local isOpen = main.Visible
	tabText.Text = isOpen and "ẨN" or "HIỆN"
	tabText.TextColor3 = theme.accent2
	toggleTab.BackgroundColor3 = isOpen and theme.accent:Lerp(TAB_BG, 0.7) or TAB_BG
end
themed(paintTab)

local function setOpen(v)
	main.Visible = v
	paintTab()
end

-- giữ tab trong màn hình
local function clampTab(p)
	local v = gui.AbsoluteSize
	toggleTab.Position = UDim2.fromOffset(
		math.clamp(p.X, 0, math.max(0, v.X - TAB)),
		math.clamp(p.Y, 0, math.max(0, v.Y - TAB))
	)
end
gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
	clampTab(toggleTab.AbsolutePosition)
end)

-- kéo thả tab (di chuyển > 6px thì tính là kéo, không tính là bấm)
local tabDrag, tabMoved, tabInputStart, tabPosStart = false, false, nil, nil
toggleTab.InputBegan:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
		tabDrag, tabMoved = true, false
		tabInputStart, tabPosStart = input.Position, toggleTab.AbsolutePosition
		input.Changed:Connect(function()
			if input.UserInputState == Enum.UserInputState.End then tabDrag = false end
		end)
	end
end)
UserInputService.InputChanged:Connect(function(input)
	if tabDrag and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
		local d = input.Position - tabInputStart
		if d.Magnitude > 6 then tabMoved = true end
		if tabMoved then
			clampTab(tabPosStart + Vector2.new(d.X, d.Y))
		end
	end
end)
toggleTab.Activated:Connect(function()
	if tabMoved then
		tabMoved = false
		return
	end
	setOpen(not main.Visible)
end)
UserInputService.InputBegan:Connect(function(input, processed)
	if not processed and input.KeyCode == Enum.KeyCode.RightShift then
		setOpen(not main.Visible)
	end
end)

----------------------------------------------------------------
-- Header
----------------------------------------------------------------
local header = new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, HEAD) }, main)
new("Frame", { BackgroundColor3 = LINE, BorderSizePixel = 0, Position = UDim2.fromOffset(0, HEAD), Size = UDim2.new(1, 0, 0, 3) }, main)

label(header, { Text = "👑", TextSize = 52, Font = F_BOLD, TextXAlignment = Enum.TextXAlignment.Center,
	Position = UDim2.fromOffset(30, 40), Size = UDim2.fromOffset(130, 120) })

local title = label(header, { RichText = true, TextSize = 42, Font = F_BOLD,
	Position = UDim2.fromOffset(176, 12), Size = UDim2.fromOffset(960, 112) })
local subtitle = label(header, { Text = "Chơi Game Thật Dễ - Đỉnh Cao Trải Nghiệm", TextSize = 21,
	Position = UDim2.fromOffset(176, 122), Size = UDim2.fromOffset(1300, 70) })
themed(function()
	title.Text = 'bảo anh <font color="#' .. theme.accent2:ToHex() .. '">Script</font>'
	subtitle.TextColor3 = theme.accent2
end)

local badge = new("Frame", {
	BackgroundColor3 = Color3.fromRGB(47, 123, 255), BackgroundTransparency = 0.85,
	Position = UDim2.new(1, -1030, 0, 25), Size = UDim2.fromOffset(700, 150),
}, header)
corner(badge, 75)
local badgeStroke = stroke(badge, theme.accent, 3, 0)
themed(function() badgeStroke.Color = theme.accent end)
label(badge, { Text = "🚀", TextSize = 30, Font = F_BOLD, TextXAlignment = Enum.TextXAlignment.Center,
	Position = UDim2.fromOffset(20, 0), Size = UDim2.fromOffset(110, 150) })
label(badge, { Text = "Phiên Bản Mới Nhất", TextSize = 19, Font = F_BOLD,
	Position = UDim2.fromOffset(140, 12), Size = UDim2.fromOffset(550, 66) })
label(badge, { Text = "No Key - Free", TextSize = 18, TextColor3 = MUTED,
	Position = UDim2.fromOffset(140, 80), Size = UDim2.fromOffset(550, 62) })

local function headerBtn(text, x)
	local b = new("TextButton", {
		Text = text, TextSize = ts(36), Font = F_BOLD, BackgroundTransparency = 1,
		Position = UDim2.new(1, -x, 0, 45), Size = UDim2.fromOffset(110, 110),
	}, header)
	themed(function() b.TextColor3 = theme.accent2 end)
	b.Activated:Connect(function() setOpen(false) end)
end
headerBtn("–", 300)
headerBtn("✕", 160)

-- kéo thả cửa sổ
local dragging, dragStart, startPos
header.InputBegan:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
		dragging, dragStart, startPos = true, input.Position, main.Position
		input.Changed:Connect(function()
			if input.UserInputState == Enum.UserInputState.End then dragging = false end
		end)
	end
end)
UserInputService.InputChanged:Connect(function(input)
	if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
		local d = (input.Position - dragStart) / uiScale.Scale
		main.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X, startPos.Y.Scale, startPos.Y.Offset + d.Y)
	end
end)

----------------------------------------------------------------
-- Footer + thanh trạng thái
----------------------------------------------------------------
local footer = new("Frame", {
	BackgroundTransparency = 1, AnchorPoint = Vector2.new(0, 1),
	Position = UDim2.fromScale(0, 1), Size = UDim2.new(1, 0, 0, FOOT),
}, main)
new("Frame", { BackgroundColor3 = LINE, BorderSizePixel = 0, Size = UDim2.new(1, 0, 0, 3) }, footer)
local dot = new("Frame", { BackgroundColor3 = Color3.fromRGB(34, 197, 94), Position = UDim2.fromOffset(40, 30), Size = UDim2.fromOffset(30, 30) }, footer)
corner(dot, 15)
local statusLabel = label(footer, { RichText = true, TextSize = 21, TextColor3 = MUTED,
	Position = UDim2.fromOffset(92, 0), Size = UDim2.fromOffset(1540, FOOT) })
local tagline = label(footer, { Text = "Chơi thông minh - Thắng dễ dàng!", TextSize = 21, Font = Enum.Font.SourceSansItalic,
	TextXAlignment = Enum.TextXAlignment.Right, AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(1, -40, 0, 0), Size = UDim2.fromOffset(920, FOOT) })

local statusText, statusToken = "Đã sẵn sàng", 0
local function renderStatus()
	statusLabel.Text = 'Trạng thái: <font color="#' .. theme.accent2:ToHex() .. '">' .. statusText .. "</font>"
	tagline.TextColor3 = theme.accent2
end
themed(renderStatus)

local function setStatus(text)
	statusToken += 1
	local my = statusToken
	statusText = text
	renderStatus()
	task.delay(1.8, function()
		if statusToken == my then
			statusText = "Đã sẵn sàng"
			renderStatus()
		end
	end)
end

Farm.notify = setStatus -- logic Farm báo trạng thái lên thanh dưới menu

----------------------------------------------------------------
-- Thành phần: card, hàng, công tắc, dropdown
----------------------------------------------------------------
local function card(parent, order, icon, titleRich, subtitleText, color, titleColor)
	local c = new("Frame", {
		BackgroundColor3 = PANEL, BackgroundTransparency = 0.1, LayoutOrder = order,
		Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
	}, parent)
	corner(c, 32)
	stroke(c, color, 3, 0.1)
	pad(c, 30, 30, 30, 30)
	list(c, 20)
	local h = new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 180), LayoutOrder = 0 }, c)
	label(h, { Text = icon, TextSize = 40, Font = F_BOLD, TextXAlignment = Enum.TextXAlignment.Center, Size = UDim2.fromOffset(130, 180) })
	label(h, { RichText = true, Text = titleRich, TextSize = 32, Font = F_BOLD, TextColor3 = titleColor or color,
		Position = UDim2.fromOffset(150, 4), Size = UDim2.new(1, -150, 0, 108) })
	label(h, { Text = subtitleText, TextSize = 19, TextColor3 = MUTED, TextTruncate = Enum.TextTruncate.AtEnd,
		Position = UDim2.fromOffset(150, 112), Size = UDim2.new(1, -150, 0, 66) })
	return c
end

local ROW_H = 130 -- chiều cao mỗi hàng chức năng

local function row(parent, order, icon, text, rightWidth)
	local r = new("Frame", { BackgroundColor3 = ROW, BackgroundTransparency = 0.1, LayoutOrder = order, Size = UDim2.new(1, 0, 0, ROW_H) }, parent)
	corner(r, 26)
	stroke(r, ROWLINE, 2, 0.6)
	label(r, { Text = icon, TextSize = 34, Font = F_BOLD, TextXAlignment = Enum.TextXAlignment.Center,
		Position = UDim2.fromOffset(14, 0), Size = UDim2.fromOffset(120, ROW_H) })
	label(r, { Text = text, TextSize = 28, TextTruncate = Enum.TextTruncate.AtEnd,
		Position = UDim2.fromOffset(150, 0), Size = UDim2.new(1, -(150 + rightWidth), 1, 0) })
	return r
end

local function toggle(parent, order, icon, text, default, group)
	local r = row(parent, order, icon, text, 240)
	State[text] = default
	if group then
		Groups[group] = Groups[group] or {}
		table.insert(Groups[group], text)
	end
	local sw = new("TextButton", {
		Text = "", AutoButtonColor = false, AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -32, 0.5, 0), Size = UDim2.fromOffset(180, 96), BackgroundColor3 = OFF,
	}, r)
	corner(sw, 48)
	local knob = new("Frame", { AnchorPoint = Vector2.new(0, 0.5), Size = UDim2.fromOffset(76, 76), BackgroundColor3 = Color3.new(1, 1, 1) }, sw)
	corner(knob, 38)

	local function paint(animate)
		local on = State[text]
		local info = TweenInfo.new(animate and 0.18 or 0)
		TweenService:Create(sw, info, { BackgroundColor3 = on and theme.accent or OFF }):Play()
		TweenService:Create(knob, info, {
			Position = on and UDim2.new(1, -86, 0.5, 0) or UDim2.new(0, 10, 0.5, 0),
			BackgroundColor3 = on and Color3.new(1, 1, 1) or Color3.fromRGB(174, 185, 221),
		}):Play()
	end
	themed(function() paint(false) end)

	sw.Activated:Connect(function()
		State[text] = not State[text]
		paint(true)
		setStatus((State[text] and "Đã bật: " or "Đã tắt: ") .. text)
		local cb = Callbacks[text]
		if cb then task.spawn(cb, State[text]) end
	end)
end

local function dropdown(parent, order, icon, text, options, default, onChange)
	local r = row(parent, order, icon, text, 600)
	local btn = new("TextButton", {
		Text = default .. "  ▾", TextSize = ts(24), Font = F_MED, TextColor3 = TEXT, AutoButtonColor = false,
		BackgroundColor3 = Color3.fromRGB(12, 24, 56), AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -24, 0.5, 0), Size = UDim2.fromOffset(520, 104),
	}, r)
	corner(btn, 22)
	stroke(btn, ROWLINE, 2, 0.5)

	local menu = new("Frame", {
		Visible = false, ZIndex = 20, AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, 0, 0, -8),
		Size = UDim2.fromOffset(520, #options * 104 + 16), BackgroundColor3 = Color3.fromRGB(12, 24, 56),
	}, btn)
	corner(menu, 22)
	local ms = stroke(menu, theme.accent, 2, 0)
	themed(function() ms.Color = theme.accent end)
	pad(menu, 8, 8, 8, 8)
	list(menu, 0)
	for i, o in ipairs(options) do
		local ob = new("TextButton", {
			Text = o, TextSize = ts(24), Font = F_MED, TextColor3 = TEXT, BackgroundTransparency = 1,
			ZIndex = 21, LayoutOrder = i, Size = UDim2.new(1, 0, 0, 104),
		}, menu)
		ob.Activated:Connect(function()
			btn.Text = o .. "  ▾"
			menu.Visible = false
			onChange(o)
		end)
	end
	btn.Activated:Connect(function() menu.Visible = not menu.Visible end)
end

local function slider(parent, order, icon, text, minV, maxV, default, onChange)
	local SH = 260 -- chiều cao hàng: nửa trên = tên + số, nửa dưới = thanh trượt
	local r = new("Frame", { BackgroundColor3 = ROW, BackgroundTransparency = 0.1, LayoutOrder = order, Size = UDim2.new(1, 0, 0, SH) }, parent)
	corner(r, 26)
	stroke(r, ROWLINE, 2, 0.6)
	label(r, { Text = icon, TextSize = 34, Font = F_BOLD, TextXAlignment = Enum.TextXAlignment.Center,
		Position = UDim2.fromOffset(14, 0), Size = UDim2.fromOffset(120, 130) })
	label(r, { Text = text, TextSize = 28, TextTruncate = Enum.TextTruncate.AtEnd,
		Position = UDim2.fromOffset(150, 0), Size = UDim2.new(1, -(150 + 360), 0, 130) })
	local valueLabel = label(r, { Text = tostring(default), TextSize = 30, Font = F_BOLD,
		TextXAlignment = Enum.TextXAlignment.Right, AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -32, 0, 0), Size = UDim2.fromOffset(320, 130) })
	themed(function() valueLabel.TextColor3 = theme.accent2 end)

	local BTN, CY = 110, 195 -- cỡ nút -/+ và tâm dọc của thanh trượt
	local function stepBtn(txt, anchorX, x)
		local b = new("TextButton", {
			Text = txt, TextSize = ts(30), Font = F_BOLD, TextColor3 = TEXT, AutoButtonColor = false,
			BackgroundColor3 = OFF, BorderSizePixel = 0, AnchorPoint = Vector2.new(anchorX, 0.5),
			Position = UDim2.new(anchorX, x, 0, CY), Size = UDim2.fromOffset(BTN, BTN),
		}, r)
		corner(b, 28)
		return b
	end
	local minus = stepBtn("−", 0, 150)
	local plus = stepBtn("+", 1, -32)

	-- vùng chạm (cao hơn thanh để dễ kéo bằng ngón tay)
	local hit = new("TextButton", {
		Text = "", AutoButtonColor = false, BackgroundTransparency = 1, BorderSizePixel = 0, AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 150 + BTN + 50, 0, CY), Size = UDim2.new(1, -(150 + BTN + 50 + 32 + BTN + 50), 0, 130),
	}, r)
	local track = new("Frame", {
		BackgroundColor3 = OFF, BorderSizePixel = 0, AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.fromScale(0, 0.5), Size = UDim2.new(1, 0, 0, 28),
	}, hit)
	corner(track, 14)
	local fill = new("Frame", { BorderSizePixel = 0, Size = UDim2.fromScale(0, 1) }, track)
	corner(fill, 14)
	local knob = new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(72, 72),
		BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0, ZIndex = 2,
	}, track)
	corner(knob, 36)
	themed(function() fill.BackgroundColor3 = theme.accent end)

	local value = math.clamp(default, minV, maxV)
	local function render()
		local a = (value - minV) / (maxV - minV)
		fill.Size = UDim2.fromScale(a, 1)
		knob.Position = UDim2.fromScale(a, 0.5)
		valueLabel.Text = tostring(value)
	end
	local function set(v)
		value = math.clamp(math.floor(v + 0.5), minV, maxV)
		render()
		onChange(value)
	end
	render()

	minus.Activated:Connect(function() set(value - 1) end)
	plus.Activated:Connect(function() set(value + 1) end)

	local function setFromX(x)
		local a = math.clamp((x - track.AbsolutePosition.X) / math.max(track.AbsoluteSize.X, 1), 0, 1)
		set(minV + a * (maxV - minV))
	end
	local sliding = false
	local scroller = parent:FindFirstAncestorOfClass("ScrollingFrame")
	hit.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			sliding = true
			if scroller then scroller.ScrollingEnabled = false end -- đang kéo thì không cuộn trang
			setFromX(input.Position.X)
			input.Changed:Connect(function()
				if input.UserInputState == Enum.UserInputState.End then
					sliding = false
					if scroller then scroller.ScrollingEnabled = true end
				end
			end)
		end
	end)
	UserInputService.InputChanged:Connect(function(input)
		if sliding and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
			setFromX(input.Position.X)
		end
	end)
end

-- Ô chọn NHIỀU mục (bấm hàng để mở danh sách ngay dưới, bấm từng mục để chọn / bỏ chọn; không chọn gì = tất cả)
function Farm.multiPicker(parent, order, icon, text, getOptions, onChange)
	local r = row(parent, order, icon, text, 600)
	local btn = new("TextButton", {
		Text = "Tất cả  ▾", TextSize = ts(24), Font = F_MED, TextColor3 = TEXT, AutoButtonColor = false,
		BackgroundColor3 = Color3.fromRGB(12, 24, 56), AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -24, 0.5, 0), Size = UDim2.fromOffset(520, 104),
	}, r)
	corner(btn, 22)
	stroke(btn, ROWLINE, 2, 0.5)

	local box = new("ScrollingFrame", {
		Visible = false, LayoutOrder = order + 1, BackgroundColor3 = Color3.fromRGB(12, 24, 56),
		BorderSizePixel = 0, ScrollBarThickness = 12, CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y, ScrollingDirection = Enum.ScrollingDirection.Y,
		Size = UDim2.new(1, 0, 0, 104 * 5 + 16),
	}, parent)
	corner(box, 22)
	local boxStroke = stroke(box, theme.accent, 2, 0)
	themed(function() boxStroke.Color = theme.accent end)
	pad(box, 8, 8, 8, 8)
	list(box, 0)

	local selected, count, buttons, built = {}, 0, {}, -1
	local function summary()
		btn.Text = (count == 0 and "Tất cả" or (count .. " đã chọn")) .. "  ▾"
	end
	local function optionButton(order2, txt)
		return new("TextButton", {
			Text = txt, TextSize = ts(24), Font = F_MED, TextColor3 = TEXT, BackgroundTransparency = 1,
			AutoButtonColor = false, TextXAlignment = Enum.TextXAlignment.Left, LayoutOrder = order2,
			Size = UDim2.new(1, -16, 0, 104),
		}, box)
	end
	local function build() -- dựng lại danh sách khi số mục thay đổi (dữ liệu game có thể tải sau menu)
		local opts = getOptions()
		if #opts == built then return end
		built = #opts
		for _, c in ipairs(box:GetChildren()) do
			if c:IsA("TextButton") then c:Destroy() end
		end
		table.clear(buttons)
		if #opts == 0 then
			optionButton(1, "Chưa có dữ liệu (chỉ dùng trong Fake an Egg)").TextColor3 = MUTED
			return
		end
		optionButton(0, "✖  Bỏ chọn tất cả").Activated:Connect(function()
			table.clear(selected)
			count = 0
			for name, b in pairs(buttons) do b.Text = "⬜  " .. name end
			summary()
			onChange(selected)
		end)
		for i, name in ipairs(opts) do
			local b = optionButton(i, (selected[name] and "✅  " or "⬜  ") .. name)
			buttons[name] = b
			b.Activated:Connect(function()
				if selected[name] then
					selected[name] = nil
					count -= 1
				else
					selected[name] = true
					count += 1
				end
				b.Text = (selected[name] and "✅  " or "⬜  ") .. name
				summary()
				onChange(selected)
			end)
		end
	end

	btn.Activated:Connect(function()
		box.Visible = not box.Visible
		if box.Visible then build() end
	end)
end

-- Hàng hiển thị 1 giá trị cập nhật trực tiếp (cột phải); trả về TextLabel để gán Text
function Farm.infoRow(parent, order, icon, text, w)
	local r = row(parent, order, icon, text, w)
	local l = label(r, {
		Text = "", TextSize = 20, Font = F_BOLD, TextXAlignment = Enum.TextXAlignment.Right,
		TextTruncate = Enum.TextTruncate.AtEnd, AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -32, 0.5, 0), Size = UDim2.fromOffset(w - 60, ROW_H),
	})
	themed(function() l.TextColor3 = theme.accent2 end)
	return l
end

-- Hàng chỉnh giá trị theo các mức định sẵn: bấm − / + để đổi mức (không cần menu thả xuống)
function Farm.stepper(parent, order, icon, text, values, default, onChange, fmtFn)
	local r = row(parent, order, icon, text, 640)
	fmtFn = fmtFn or Farm.short
	local idx = 1
	for i, v in ipairs(values) do
		if v == default then idx = i end
	end
	local function stepBtn(txt, x)
		local b = new("TextButton", {
			Text = txt, TextSize = ts(30), Font = F_BOLD, TextColor3 = TEXT, AutoButtonColor = false,
			BackgroundColor3 = OFF, BorderSizePixel = 0, AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, x, 0.5, 0), Size = UDim2.fromOffset(104, 104),
		}, r)
		corner(b, 28)
		return b
	end
	local plus = stepBtn("+", -24)
	local minus = stepBtn("−", -444)
	local valueLabel = label(r, {
		Text = "", TextSize = 22, Font = F_BOLD, TextXAlignment = Enum.TextXAlignment.Center,
		AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -136, 0.5, 0), Size = UDim2.fromOffset(300, ROW_H),
	})
	themed(function() valueLabel.TextColor3 = theme.accent2 end)
	local function render() valueLabel.Text = fmtFn(values[idx]) end
	render()
	local function step(d)
		idx = math.clamp(idx + d, 1, #values)
		render()
		onChange(values[idx])
	end
	minus.Activated:Connect(function() step(-1) end)
	plus.Activated:Connect(function() step(1) end)
end

----------------------------------------------------------------
-- Các trang: MỖI TAB LÀ MỘT TRANG RIÊNG BIỆT
----------------------------------------------------------------
local TABS = {
	{ "🏠", "Tổng Quan" }, { "⚔️", "Farm" }, { "🥷", "Steal" }, { "🔄", "Rebirth" }, { "🛒", "Shops" }, { "💲", "Sell" }, { "⚙️", "Tự Động" },
	{ "👤", "Player" }, { "👁️", "ESP" }, { "🎚️", "Cài Đặt" },
}

local pages, navByName = {}, {}

local function newPage(name)
	local p = new("ScrollingFrame", {
		Name = name, Visible = false, BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 16,
		CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		Position = UDim2.fromOffset(SIDE_W + MARG * 2, BODY_TOP), Size = UDim2.new(1, -(SIDE_W + MARG * 3), 1, -(BODY_TOP + BOT)),
	}, main)
	pad(p, 4, 30, 4, 4)
	list(p, 28)
	pages[name] = p
	return p
end

local function showTab(name)
	for n, p in pairs(pages) do
		p.Visible = (n == name)
	end
	pages[name].CanvasPosition = Vector2.new(0, 0)
	for n, b in pairs(navByName) do
		b.BackgroundTransparency = (n == name) and 0 or 1
	end
end

-- Các tab Fake an Egg (chuyển từ "Fake an Egg Hub"): Farm, Steal, Rebirth, Shops, Sell.
-- Mỗi tab bọc trong do...end để các biến card không chiếm thêm chỗ trong giới hạn 200 biến local của Luau.

-- Tab: Farm (mua trứng → mang về ổ → tự ấp)
do
	local farmCard = card(newPage("Farm"), 1, "⚔️", 'Farm <font size="' .. SMALL .. '">(Cày)</font>', "Mua trứng, mang về ổ & tự ấp (game Fake an Egg)", Color3.fromRGB(77, 141, 255))
	toggle(farmCard, 1, "🥚", "Auto Farm", false, "Farm")
	toggle(farmCard, 2, "🛡️", "Chỉ Trứng Thật", true, "Farm")
	toggle(farmCard, 3, "🐣", "Auto Hatch", true, "Farm")
	toggle(farmCard, 4, "⬆️", "Chỉ Mua Trứng Tốt Hơn", false, "Farm")
	toggle(farmCard, 5, "💰", "Giới Hạn Giá Trứng", false, "Farm")
	dropdown(farmCard, 6, "💲", "Giá Trứng Tối Đa", Farm.PRICE_NAMES, "1T", function(name)
		Farm.cfg.maxPrice = Farm.PRICE_CAPS[name]
		setStatus("Giá trứng tối đa: " .. name)
	end)
	Farm.multiPicker(farmCard, 7, "🥚", "Loại Trứng Cần Mua", Farm.eggNames, function(map)
		Farm.cfg.eggNames = map
	end)
	Farm.multiPicker(farmCard, 9, "💎", "Độ Hiếm Trứng", Farm.eggRarities, function(map)
		Farm.cfg.eggRarities = map
	end)

	local statusCard = card(pages["Farm"], 2, "📊", 'Trạng Thái <font size="' .. SMALL .. '">(Farm)</font>', "Cập nhật trực tiếp khi đang chạy", Color3.fromRGB(56, 189, 248))
	Farm.ui.state = Farm.infoRow(statusCard, 1, "📡", "Trạng Thái", 900)
	Farm.ui.cash = Farm.infoRow(statusCard, 2, "💵", "Tiền", 640)
	Farm.ui.best = Farm.infoRow(statusCard, 3, "🏆", "Pet Mạnh Nhất", 640)
	Farm.ui.bought = Farm.infoRow(statusCard, 4, "🛒", "Trứng Đã Mua", 640)
	Farm.ui.hatched = Farm.infoRow(statusCard, 5, "🐣", "Đã Ấp", 640)
end

-- Tab: Steal (trộm pet nặng nhất ở chuồng người khác)
do
	local c = card(newPage("Steal"), 1, "🥷", 'Steal <font size="' .. SMALL .. '">(Trộm Pet)</font>', "Vào chuồng người khác lấy pet nặng nhất", Color3.fromRGB(244, 114, 182))
	toggle(c, 1, "🥷", "Auto Steal", false, "Steal")
	toggle(c, 2, "🏃", "Về Nhà Sau Khi Trộm", true, "Steal")
	Farm.stepper(c, 3, "⚖️", "Cân Nặng Tối Thiểu", Farm.WEIGHTS, 1000, function(v)
		Farm.cfg.minWeight = v
		setStatus("Chỉ trộm pet nặng hơn: " .. Farm.short(v))
	end)

	local s = card(pages["Steal"], 2, "📊", 'Trạng Thái <font size="' .. SMALL .. '">(Steal)</font>', "Cập nhật trực tiếp khi đang chạy", Color3.fromRGB(56, 189, 248))
	Farm.ui.stState = Farm.infoRow(s, 1, "📡", "Trạng Thái", 900)
	Farm.ui.stStolen = Farm.infoRow(s, 2, "🥷", "Đã Trộm", 640)
end

-- Tab: Rebirth (chỉ mua đúng trứng mà lần rebirth tiếp theo yêu cầu)
do
	local c = card(newPage("Rebirth"), 1, "🔄", 'Rebirth <font size="' .. SMALL .. '">(Farm Trứng)</font>', "Chỉ mua trứng lần rebirth tới cần, tự rebirth khi đủ điều kiện", Color3.fromRGB(56, 189, 248))
	toggle(c, 1, "🔄", "Farm Trứng Theo Rebirth", false, "Rebirth")

	local s = card(pages["Rebirth"], 2, "📊", 'Trạng Thái <font size="' .. SMALL .. '">(Rebirth)</font>', "Cập nhật trực tiếp khi đang chạy", Color3.fromRGB(47, 123, 255))
	Farm.ui.rbNeed = Farm.infoRow(s, 1, "🎯", "Cần Ấp Ra", 900)
	Farm.ui.rbState = Farm.infoRow(s, 2, "📡", "Trạng Thái", 900)
	Farm.ui.rbCount = Farm.infoRow(s, 3, "♻️", "Số Lần Rebirth", 640)
end

-- Tab: Shops (tự mua scanner & thức ăn pet)
do
	local c = card(newPage("Shops"), 1, "🛒", 'Shops <font size="' .. SMALL .. '">(Cửa Hàng)</font>', "Tự mua món tốt nhất còn hàng & đủ tiền", Color3.fromRGB(167, 139, 250))
	toggle(c, 1, "🔍", "Auto Mua Scanner", false, "Shops")
	Farm.multiPicker(c, 2, "🔍", "Loại Scanner", Farm.scannerNames, function(map)
		Farm.cfg.scannerTypes = map
	end)
	toggle(c, 4, "🍖", "Auto Mua Thức Ăn", false, "Shops")
	Farm.multiPicker(c, 5, "🍖", "Loại Thức Ăn", Farm.foodNames, function(map)
		Farm.cfg.foodTypes = map
	end)
	Farm.stepper(c, 7, "💰", "Giá Tối Đa Mỗi Lần Mua", Farm.SHOP_CAPS, 5e6, function(v)
		Farm.cfg.shopMax = v
		setStatus("Giá tối đa mỗi lần mua: " .. Farm.short(v))
	end)

	local s = card(pages["Shops"], 2, "📊", 'Trạng Thái <font size="' .. SMALL .. '">(Shops)</font>', "Món đang mua · số lần đã mua", Color3.fromRGB(56, 189, 248))
	Farm.ui.shScanner = Farm.infoRow(s, 1, "🔍", "Scanner", 900)
	Farm.ui.shFood = Farm.infoRow(s, 2, "🍖", "Thức Ăn", 900)
	Farm.ui.shCash = Farm.infoRow(s, 3, "💵", "Tiền", 640)
end

-- Tab: Sell (tự bán pet theo bộ lọc)
do
	local c = card(newPage("Sell"), 1, "💲", 'Sell <font size="' .. SMALL .. '">(Bán Pet)</font>', "Tự bán pet khớp bộ lọc ở bàn Sell", Color3.fromRGB(34, 211, 160))
	toggle(c, 1, "💲", "Auto Sell Pets", false, "Sell")
	Farm.multiPicker(c, 2, "🐾", "Loại Pet Cần Bán", Farm.petNames, function(map)
		Farm.cfg.sellNames = map
	end)
	Farm.multiPicker(c, 4, "💎", "Độ Hiếm Cần Bán", Farm.petRarities, function(map)
		Farm.cfg.sellRarities = map
	end)
	Farm.stepper(c, 6, "⚖️", "Chỉ Bán Pet Nhẹ Hơn", Farm.SELL_UNDER, 0, function(v)
		Farm.cfg.sellUnder = v
		setStatus(v == 0 and "Bán mọi cân nặng" or ("Chỉ bán pet nhẹ hơn: " .. Farm.short(v)))
	end, function(v) return v == 0 and "Tất cả" or Farm.short(v) end)
	toggle(c, 7, "🏆", "Giữ Lại Pet Mạnh Nhất", true, "Sell")
	slider(c, 8, "⏱️", "Bán Mỗi (Giây)", 1, 60, 2, function(v)
		Farm.cfg.sellEvery = v
		setStatus("Bán mỗi " .. v .. " giây")
	end)

	local s = card(pages["Sell"], 2, "📊", 'Trạng Thái <font size="' .. SMALL .. '">(Sell)</font>', "Cập nhật trực tiếp khi đang chạy", Color3.fromRGB(56, 189, 248))
	Farm.ui.slState = Farm.infoRow(s, 1, "📡", "Đang Bán", 900)
	Farm.ui.slSold = Farm.infoRow(s, 2, "💰", "Đã Bán", 640)
end

-- Tab: Tự Động
local autoCard = card(newPage("Tự Động"), 1, "⚙️", 'Tự Động <font size="' .. SMALL .. '">(Auto)</font>', "Tự động rebirth & bán đồ", Color3.fromRGB(56, 189, 248))
toggle(autoCard, 1, "🔄", "Auto Rebirth", false, "Tự Động")
toggle(autoCard, 2, "💲", "Auto Sell", true, "Tự Động")

-- Tab: Player
local playerCard = card(newPage("Player"), 1, "👤", 'Player <font size="' .. SMALL .. '">(Nhân Vật)</font>', "Tối ưu sức mạnh nhân vật", Color3.fromRGB(34, 211, 160))
toggle(playerCard, 1, "🛡️", "God Mode", false, "Player")
toggle(playerCard, 2, "🏃", "Speed Hack", false, "Player")
slider(playerCard, 3, "⚡", "Tốc Độ Chạy", SPEED_MIN, SPEED_MAX, SPEED_DEFAULT, function(v)
	setSpeedValue(v)
	setStatus("Tốc độ chạy: " .. v)
end)
toggle(playerCard, 4, "⬆️", "Jump Power", false, "Player")
slider(playerCard, 5, "🦘", "Sức Nhảy", JUMP_MIN, JUMP_MAX, JUMP_DEFAULT, function(v)
	setJumpValue(v)
	setStatus("Sức nhảy: " .. v)
end)
toggle(playerCard, 6, "💚", "Full Health", false, "Player")
toggle(playerCard, 7, "👻", "Tàn Hình", false, "Player")
toggle(playerCard, 8, "🧱", "Đi Xuyên Tường", false, "Player")

-- Tab: ESP
local espCard = card(newPage("ESP"), 1, "👁️", 'ESP <font size="' .. SMALL .. '">(Nhìn Xuyên)</font>', "Khung 2D, đường kẻ & thông tin người chơi", Color3.fromRGB(248, 113, 113))
toggle(espCard, 1, "🎯", "ESP Người Chơi", false, "ESP")
toggle(espCard, 2, "🔲", "ESP Khung", false, "ESP")
toggle(espCard, 3, "╱", "ESP Line", false, "ESP")
toggle(espCard, 4, "🏷️", "ESP Tên", false, "ESP")
toggle(espCard, 5, "❤️", "ESP Máu", false, "ESP")
toggle(espCard, 6, "📏", "ESP Khoảng Cách", false, "ESP")
toggle(espCard, 7, "📦", "ESP Rương", false, "ESP")
dropdown(espCard, 8, "🎨", "Màu ESP", ESP_COLOR_NAMES, "Đỏ", function(name)
	espColor = ESP_COLORS[name] or espColor
	espRefresh()
	setStatus("Màu ESP: " .. name)
end)

-- Tab: Cài Đặt
local setCard = card(newPage("Cài Đặt"), 1, "🎚️", "Cài Đặt", "Tùy chỉnh giao diện & chức năng", Color3.fromRGB(234, 179, 8))
toggle(setCard, 1, "✨", "Hiệu Ứng Đẹp", true, "Cài Đặt")
toggle(setCard, 2, "🔊", "Âm Thanh", true, "Cài Đặt")
toggle(setCard, 3, "🔔", "Hiển Thị Thông Báo", true, "Cài Đặt")
dropdown(setCard, 4, "🎨", "Giao Diện Màu", THEME_NAMES, "Xanh Dương", function(name)
	applyTheme(name)
	setStatus("Đổi giao diện: " .. name)
end)

-- Tab: Tổng Quan (trang chủ: chỉ còn mục Thông Tin script)
local homePage = newPage("Tổng Quan")
local function rightLabel(r, text)
	local l = label(r, {
		Text = text or "", TextSize = 27, Font = F_BOLD, TextXAlignment = Enum.TextXAlignment.Right,
		AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -32, 0.5, 0), Size = UDim2.fromOffset(340, ROW_H),
	})
	themed(function() l.TextColor3 = theme.accent2 end)
	return l
end

-- Thông Tin (trang Tổng Quan chỉ còn mục này)
local infoCard = card(homePage, 1, "ℹ️", "Thông Tin", "Bản tùy chỉnh bởi bảo anh", Color3.fromRGB(59, 155, 255))
local box = new("Frame", {
	BackgroundColor3 = Color3.fromRGB(8, 18, 48), LayoutOrder = 1,
	Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
}, infoCard)
corner(box, 26)
local boxStroke = stroke(box, theme.accent, 3, 0.2)
themed(function() boxStroke.Color = theme.accent end)
pad(box, 28, 28, 28, 28)
list(box, 12)
label(box, { Text = "👑  bảo anh Script", TextSize = 30, Font = F_BOLD, LayoutOrder = 0, Size = UDim2.new(1, 0, 0, 108) })
for i, t in ipairs({ "Hoàn toàn miễn phí", "Không cần Key", "An toàn - Ổn định", "Cập nhật thường xuyên" }) do
	label(box, { Text = "✅  " .. t, TextSize = 25, TextColor3 = Color3.fromRGB(205, 217, 245), LayoutOrder = i, Size = UDim2.new(1, 0, 0, 90) })
end
local function showAdmin()
	setStatus(ADMIN_LABEL)
end

local adminRow = row(box, 5, "👤", ADMIN_LABEL, 220)
rightLabel(adminRow, "Xem  ›")
new("TextButton", { Text = "", BackgroundTransparency = 1, ZIndex = 5, Size = UDim2.fromScale(1, 1) }, adminRow)
	.Activated:Connect(showAdmin)

local adminInfoRow = row(box, 6, "👑", ADMIN_LABEL, 220)
rightLabel(adminInfoRow, "Xem  ›")
new("TextButton", { Text = "", BackgroundTransparency = 1, ZIndex = 5, Size = UDim2.fromScale(1, 1) }, adminInfoRow)
	.Activated:Connect(showAdmin)

local cta = new("TextButton", {
	Text = "👑  " .. ADMIN_LABEL, TextSize = ts(23), Font = F_BOLD, TextColor3 = Color3.new(1, 1, 1),
	TextWrapped = true, LayoutOrder = 7, Size = UDim2.new(1, 0, 0, 150),
}, box)
corner(cta, 75)
themed(function() cta.BackgroundColor3 = theme.accent end)
cta.Activated:Connect(function()
	showAdmin()
	local cb = Callbacks["Support"]
	if cb then task.spawn(cb) end
end)

----------------------------------------------------------------
-- Thanh bên (điều hướng): bấm tab nào hiện trang của tab đó
----------------------------------------------------------------
local side = new("Frame", {
	BackgroundColor3 = Color3.fromRGB(8, 16, 40), BackgroundTransparency = 0.3,
	Position = UDim2.fromOffset(MARG, BODY_TOP), Size = UDim2.new(0, SIDE_W, 1, -(BODY_TOP + BOT)),
}, main)
corner(side, 30)
stroke(side, LINE, 2, 0)

local navList = new("ScrollingFrame", {
	BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 8,
	Position = UDim2.fromOffset(14, 14), Size = UDim2.new(1, -28, 1, -28),
	CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y, ScrollingDirection = Enum.ScrollingDirection.Y,
}, side)
list(navList, 12)

for i, t in ipairs(TABS) do
	local b = new("TextButton", {
		Text = t[1] .. "   " .. t[2], TextSize = ts(29), Font = F_MED, TextColor3 = TEXT, AutoButtonColor = false,
		TextXAlignment = Enum.TextXAlignment.Left, LayoutOrder = i, Size = UDim2.new(1, 0, 0, 112),
		BackgroundColor3 = theme.accent, BackgroundTransparency = 1,
	}, navList)
	corner(b, 26)
	pad(b, 0, 0, 0, 36)
	navByName[t[2]] = b
	b.Activated:Connect(function() showTab(t[2]) end)
end
themed(function()
	for _, b in pairs(navByName) do b.BackgroundColor3 = theme.accent end
end)

showTab("Tổng Quan")
setOpen(true)

----------------------------------------------------------------
-- CHỮ 7 MÀU: toàn bộ chữ trong menu chạy qua 7 sắc cầu vồng (đỏ, cam, vàng, lục, lam, chàm, tím).
-- Màu chạy thành làn sóng từ trên xuống / từ trái sang phải. Chỉnh ở 2 dòng dưới:
-- RAINBOW_TEXT = false → trở lại màu chữ gốc của giao diện (cần chạy lại script).
----------------------------------------------------------------
do
	local RAINBOW_TEXT = true
	local RAINBOW_SPEED = 0.15 -- số vòng đủ 7 màu mỗi giây (0.15 ≈ 6,7 giây / vòng)

	if RAINBOW_TEXT then
		local COLORS7 = {
			Color3.fromRGB(255, 70, 70), -- đỏ
			Color3.fromRGB(255, 150, 40), -- cam
			Color3.fromRGB(255, 230, 60), -- vàng
			Color3.fromRGB(60, 230, 90), -- lục
			Color3.fromRGB(50, 170, 255), -- lam
			Color3.fromRGB(125, 115, 255), -- chàm (sáng hơn viền một chút để dễ đọc trên nền tối)
			Color3.fromRGB(200, 100, 255), -- tím
		}
		local function colorAt(p)
			local x = (p % 1) * 7
			local i = math.floor(x)
			return COLORS7[i + 1]:Lerp(COLORS7[(i + 1) % 7 + 1], x - i)
		end

		local texts = {}
		local function track(o)
			if o:IsA("TextLabel") or o:IsA("TextButton") or o:IsA("TextBox") then
				texts[o] = true
				-- viền chữ mờ để chữ vẫn rõ khi gặp nền cùng tông màu (vd: nút admin bảo anh)
				o.TextStrokeColor3 = Color3.new(0, 0, 0)
				o.TextStrokeTransparency = 0.55
			end
		end
		for _, d in ipairs(gui:GetDescendants()) do track(d) end
		local addConn = gui.DescendantAdded:Connect(track) -- cả chữ tạo thêm sau (danh sách thả xuống...)
		local remConn = gui.DescendantRemoving:Connect(function(o) texts[o] = nil end)

		local acc = 0
		local beat
		beat = RunService.Heartbeat:Connect(function(dt)
			acc += dt
			if acc < 1 / 30 then return end -- ~30 lần/giây là đủ mượt
			acc = 0
			local t = os.clock() * RAINBOW_SPEED
			local vp = gui.AbsoluteSize
			local sx, sy = math.max(vp.X, 1), math.max(vp.Y, 1)
			for o in pairs(texts) do
				local pos = o.AbsolutePosition
				o.TextColor3 = colorAt(t - (pos.X / sx) * 0.3 - (pos.Y / sy) * 0.4)
			end
		end)
		gui.Destroying:Connect(function()
			beat:Disconnect()
			addConn:Disconnect()
			remConn:Disconnect()
		end)
	end
end
