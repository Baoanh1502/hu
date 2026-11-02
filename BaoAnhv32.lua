--[[
	bảo anh Script – Menu Roblox và các chức năng Fake an Egg
	Các tác vụ game cần đúng dữ liệu, remote và API tương thích; xem Cài Đặt → Chẩn Đoán.
	Roblox/VNG chính thức không cung cấp API executor để chạy các tác vụ này.
	Mỗi tab ở thanh bên trái là MỘT TRANG RIÊNG: Tổng Quan (chỉ có phần Thông Tin), Farm,
	Tự Động, Player, ESP, Cài Đặt. Bấm tab nào thì chỉ hiện nội dung của tab đó.
	ESP: bật ESP Khung / ESP Line trong tab ESP. Khung và line dùng GUI Roblox, không cần Drawing.
	ESP Trứng Giả: mũi tên đỏ và chữ “điếm chó” phía trên trứng có dấu hiệu giả dạng.
	Mặc định ESP giới hạn 30 FPS và tắt Hiệu Ứng Đẹp để giảm tải điện thoại; có thể chỉnh trong menu.
	Phím RightShift: ẩn / hiện menu. Kéo thanh tiêu đề để di chuyển.
	Tab vuông bên trái màn hình: bấm để ẩn / hiện menu chính, kéo để đổi vị trí.
	Player: thay đổi phía client; God Mode / Full Health / Tàn Hình không vượt được quyền kiểm tra của server.
	Nút – chỉ ẩn menu; nút ✕ dừng script, dọn ESP và khôi phục nhân vật.
Chỉnh cỡ menu: W, H (khung), SIDE_W (thanh bên), ROW_H (độ cao mỗi chức năng).
Chỉnh cỡ chữ menu chính: TEXT_SCALE (đang là 3 = to gấp 3 lần cỡ gốc; Roblox giới hạn tối đa 100).
Fake an Egg (chuyển từ Fake an Egg Hub): tab Farm, Steal, Rebirth, Shops, Sell. Cần executor có fireproximityprompt, chỉ dùng trong game Fake an Egg.
Thanh bên có 10 tab nên có thể cuộn dọc.
Hiệu ứng màu bật / tắt tại Cài Đặt → Hiệu Ứng Đẹp.
]]

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

local ADMIN_LABEL = "admin bảo anh"
local Preferences = { sound = true, notifications = true }
local Runtime = { connections = {}, cleanups = {}, closed = false }
function Runtime.connect(event, callback)
	local connection = event:Connect(function(...)
		if not Runtime.closed then return callback(...) end
	end)
	table.insert(Runtime.connections, connection)
	return connection
end
function Runtime.shutdown()
	if Runtime.closed then return end
	Runtime.closed = true
	for _, connection in ipairs(Runtime.connections) do connection:Disconnect() end
	table.clear(Runtime.connections)
	for _, cleanup in ipairs(Runtime.cleanups) do
		local ok, err = pcall(cleanup)
		if not ok then warn("[bảo anh] Dọn tác vụ: " .. tostring(err)) end
	end
	table.clear(Runtime.cleanups)
end
do
	local previous = _G.__BaoAnhRuntime
	if type(previous) == "table" and type(previous.shutdown) == "function" then pcall(previous.shutdown) end
	_G.__BaoAnhRuntime = Runtime
end

local player = Players.LocalPlayer
do
	local playerGui = player:FindFirstChildOfClass("PlayerGui")
	if playerGui then
		for _, previousGui in ipairs(playerGui:GetChildren()) do
			if previousGui.Name == "BaoAnhScriptUI" then previousGui:Destroy() end
		end
	end
end

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
local appliedHumanoids = {}

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
	if appliedHumanoids.god ~= hum then
		baseMaxHealth = hum.MaxHealth
		appliedHumanoids.deadEnabled = hum:GetStateEnabled(Enum.HumanoidStateType.Dead)
		appliedHumanoids.god = hum
	end
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
	hum = appliedHumanoids.god
	appliedHumanoids.god = nil
	if hum and hum.Parent then
		local ff = hum.Parent:FindFirstChild("BaoAnhGodFF")
		if ff then ff:Destroy() end
		hum:SetStateEnabled(Enum.HumanoidStateType.Dead, appliedHumanoids.deadEnabled ~= false)
		hum.MaxHealth = baseMaxHealth
		hum.Health = math.min(hum.Health, baseMaxHealth)
	end
end

local function startSpeed(hum)
	if speedConn then speedConn:Disconnect() end
	if appliedHumanoids.speed ~= hum then
		baseWalkSpeed = hum.WalkSpeed
		appliedHumanoids.speed = hum
	end
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
	hum = appliedHumanoids.speed
	appliedHumanoids.speed = nil
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
	if appliedHumanoids.jump ~= hum then
		baseUseJump, baseJumpPower, baseJumpHeight = hum.UseJumpPower, hum.JumpPower, hum.JumpHeight
		appliedHumanoids.jump = hum
	end
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
	hum = appliedHumanoids.jump
	appliedHumanoids.jump = nil
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

local stopInvis
local function startInvis(char, hum)
	if appliedHumanoids.invisCharacter ~= char then
		stopInvis()
		appliedHumanoids.invisCharacter = char
		for _, descendant in ipairs(char:GetDescendants()) do hideInvisPart(descendant) end
		table.insert(invisConns, char.DescendantAdded:Connect(function(descendant)
			if invisOn and not Runtime.closed then hideInvisPart(descendant) end
		end))
	end
	if hum and appliedHumanoids.invis ~= hum then
		appliedHumanoids.invis = hum
		baseDisplayDist = hum.DisplayDistanceType
		hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None -- ẩn tên + thanh máu
	end
end

stopInvis = function(hum)
	clearInvisConns() -- ngắt kết nối trước rồi mới trả lại giá trị gốc
	for inst, t in pairs(invisOrig) do
		if inst.Parent then inst.Transparency = t end
	end
	table.clear(invisOrig)
	hum = appliedHumanoids.invis
	appliedHumanoids.invis, appliedHumanoids.invisCharacter = nil, nil
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

local function resetCharacter()
	stopGod()
	stopSpeed()
	stopJump()
	stopFull()
	stopInvis()
	stopNoclip()
end
table.insert(Runtime.cleanups, function()
	godOn, speedOn, jumpOn, fullOn, invisOn, noclipOn = false, false, false, false, false, false
	resetCharacter()
end)

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
local ESP_FRAME_RATES = { ["20 FPS"] = 20, ["30 FPS"] = 30, ["60 FPS"] = 60 }
local espInterval = 1 / 30
local espRefresh, espShutdown
do
	local tracked, visuals, connections = {}, {}, {}
	local overlay, renderConnection
	local elapsed, drawElapsed, clock, disposed = 0, 0, 0, false
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
		elapsed, drawElapsed, clock = 0, 0, 0
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

	local function screenBounds(visual, root, currentCamera)
		local viewport = currentCamera.ViewportSize
		if viewport.X <= 4 or viewport.Y <= 4 then return end
		if not visual.boundsOffset or visual.boundsRoot ~= root or clock >= visual.boundsAt then
			local boundsFrame, boundsSize = visual.character:GetBoundingBox()
			visual.boundsOffset = root.CFrame:ToObjectSpace(boundsFrame)
			visual.boundsSize, visual.boundsRoot, visual.boundsAt = boundsSize, root, clock + 0.25
		end
		local boundsFrame, boundsSize = root.CFrame * visual.boundsOffset, visual.boundsSize
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

	local function updateGeometry(visual, root, currentCamera)
		local left, top, right, bottom
		if currentCamera and (espBox or espLine) then
			left, top, right, bottom = screenBounds(visual, root, currentCamera)
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
		local delta = deltaTime or 0
		clock, elapsed, drawElapsed = clock + delta, elapsed + delta, drawElapsed + delta
		local interval = (espBox or espLine) and espInterval or 0.1
		if not force and drawElapsed + 0.000001 < interval then return end
		drawElapsed = force and 0 or math.max(0, drawElapsed - interval) % interval
		local updateInfo = force or elapsed + 0.000001 >= 0.1
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
				if force or created then
					visual.boxColor.Color = espColor
					visual.lineColor.BackgroundColor3 = espColor
					visual.text.TextColor3 = espColor
					if visual.highlight then visual.highlight.FillColor = espColor end
				end
				if updateInfo or created then
					if showInfo then
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
						local text = table.concat(lines, "\n")
						if visual.text.Text ~= text then visual.text.Text = text end
					end
				end
				updateGeometry(visual, root, currentCamera)
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

table.insert(Runtime.cleanups, espShutdown)

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
table.insert(Runtime.cleanups, function()
	chestOn = false
	chestStop()
end)
Runtime.connect(player.CharacterRemoving, resetCharacter)
Runtime.connect(player.CharacterAdded, function(char)
	local hum = char:WaitForChild("Humanoid", 10)
	if not hum or Runtime.closed or player.Character ~= char then return end
	if godOn then startGod(hum) end
	if speedOn then startSpeed(hum) end
	if jumpOn then startJump(hum) end
	if fullOn then startFull(hum) end
	if invisOn then startInvis(char, hum) end
	if noclipOn then startNoclip() end
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
local Farm = { ui = {}, errors = {} }
Farm.notify = function() end -- được gán = setStatus ngay sau khi thanh trạng thái được tạo
Farm.PRICE_NAMES = { "1M", "10M", "100M", "1B", "10B", "100B", "1T" }
Farm.PRICE_CAPS = {
	["1M"] = 1e6, ["10M"] = 1e7, ["100M"] = 1e8, ["1B"] = 1e9, ["10B"] = 1e10, ["100B"] = 1e11, ["1T"] = 1e12,
}
Farm.WEIGHTS = { 0, 100, 500, 1000, 2500, 5000, 10000, 25000, 50000, 100000 } -- mức cân nặng tối thiểu khi trộm
Farm.SHOP_CAPS = { 1e5, 1e6, 5e6, 25e6, 1e8, 5e8, 2.5e9 } -- mức giá tối đa mỗi lần mua ở Shops
Farm.SELL_UNDER = { 0, 100, 500, 1000, 5000, 10000, 50000, 100000 } -- 0 = không giới hạn cân nặng

function Farm.short(n) -- 2500000 → "2.5M"
	n = tonumber(n) or 0
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
	_G.__BaoAnhFarmGen = (_G.__BaoAnhFarmGen or 0) + 1
	local generation, disposed = _G.__BaoAnhFarmGen, false
	local function active()
		return not disposed and not Runtime.closed and _G.__BaoAnhFarmGen == generation
	end

	local cfg = {
		-- Farm
		farm = false,
		skipFake = true, -- chỉ mua trứng thật (bỏ qua trứng giả có người chơi trốn bên trong)
		autoHatch = false,
		fakeEggESP = false,
		instantCollect = false,
		equipBest = false,
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
	local hatchPrompts = setmetatable({}, { __mode = "k" })
	local buyBlocked = setmetatable({}, { __mode = "k" })
	local prompts, promptConnections = {}, {}
	local indexStarted, indexReady = false, false
	local loading = { Eggs = true, Animals = true }
	local Remotes, Eggs, Animals, Rebirth, Scanners, Food -- dữ liệu của game, tải ngầm ngay bên dưới
	local moduleNames = { "Eggs", "Animals", "Rebirth", "Scanners", "Food" }
	local loadedModules, loadingModules, errorTimes = {}, {}, {}

	Farm.cfg, Farm.stats, Farm.state = cfg, stats, state
	Farm.fmt = nil -- gán bên dưới

	function Farm.reportError(feature, message, showNotice)
		local detail = tostring(message)
		Farm.errors[feature] = detail
		state.lastError = feature .. ": " .. detail
		if active() and os.clock() >= (errorTimes[feature] or 0) then
			errorTimes[feature] = os.clock() + 5
			warn("[bảo anh] " .. state.lastError)
			showNotice = true
		end
		if active() and showNotice then Farm.notify(state.lastError, true) end
	end

	local function assignModule(name, data)
		if name == "Eggs" then Eggs = data
		elseif name == "Animals" then Animals = data
		elseif name == "Rebirth" then Rebirth = data
		elseif name == "Scanners" then Scanners = data
		else Food = data end
	end

	local function loadModule(name, module)
		if not active() or loadingModules[name] or loadedModules[name] == module and module ~= nil then return end
		if not module or not module:IsA("ModuleScript") then
			loading[name], loadedModules[name] = nil, nil
			assignModule(name, nil)
			Farm.errors[name] = "Thiếu ModuleScript ReplicatedStorage." .. name
			return
		end
		loading[name], loadingModules[name] = true, module
		local ok, result = pcall(require, module)
		loading[name], loadingModules[name] = nil, nil
		if not active() then return end
		if module.Parent ~= ReplicatedStorage then return end
		if ok and type(result) == "table" then
			assignModule(name, result)
			loadedModules[name], Farm.errors[name] = module, nil
		else
			assignModule(name, nil)
			Farm.reportError(name, ok and "Module không trả về bảng dữ liệu" or result)
		end
	end

	function Farm.refreshDependencies()
		if not active() then return end
		for _, name in ipairs(moduleNames) do
			local module = ReplicatedStorage:FindFirstChild(name)
			if module or not loading[name] then task.spawn(loadModule, name, module) end
		end
	end

	for _, name in ipairs(moduleNames) do
		loading[name] = true
		task.spawn(function()
			loadModule(name, ReplicatedStorage:WaitForChild(name, 20))
		end)
	end

	local function addPrompt(instance)
		if active() and instance:IsA("ProximityPrompt") and instance:IsDescendantOf(workspace) then
			prompts[instance] = true
		end
	end

	local function ensurePromptIndex()
		if indexStarted or not active() then return indexReady end
		indexStarted = true
		table.insert(promptConnections, workspace.DescendantAdded:Connect(addPrompt))
		table.insert(promptConnections, workspace.DescendantRemoving:Connect(function(instance)
			prompts[instance], buyBlocked[instance] = nil, nil
		end))
		task.spawn(function()
			local queue, readIndex, writeIndex = { workspace }, 1, 1
			while readIndex <= writeIndex and active() do
				local instance = queue[readIndex]
				queue[readIndex] = nil
				if instance == workspace or instance:IsDescendantOf(workspace) then
					addPrompt(instance)
					for _, child in ipairs(instance:GetChildren()) do
						writeIndex += 1
						queue[writeIndex] = child
					end
				end
				if readIndex % 250 == 0 then task.wait() end
				readIndex += 1
			end
			if active() then indexReady = true end
		end)
		return indexReady
	end

	local function fmt(n) -- 1234567 → "1,234,567"
		local s = string.format("%.0f", tonumber(n) or 0)
		return (s:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", ""))
	end
	Farm.fmt = fmt

	local function remote(name)
		Remotes = ReplicatedStorage:FindFirstChild("RemoteEvents")
		local event = Remotes and Remotes:FindFirstChild(name)
		return event and event:IsA("RemoteEvent") and event or nil
	end

	---------------- hàm phụ trợ ----------------
	local function rootPart()
		local char = LocalPlayer.Character
		if char and char.Parent then
			local humanoid = char:FindFirstChildOfClass("Humanoid")
			local root = char:FindFirstChild("HumanoidRootPart")
			if humanoid and humanoid.Health > 0 and root and root:IsA("BasePart") then return root end
		end
		return nil
	end

	local function actionValid(root, setting)
		return active() and cfg[setting] and root and root == rootPart()
	end

	local function teleport(position)
		local hrp = rootPart()
		if not active() or not hrp or typeof(position) ~= "Vector3" then
			return false
		end
		local destination = position + Vector3.new(0, 3, 0)
		if (hrp.Position - destination).Magnitude > 1.5 then hrp.CFrame = CFrame.new(destination) end
		return hrp
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
		if not active() or type(fireproximityprompt) ~= "function" or not prompt
			or not prompt.Parent or not prompt.Enabled or not prompt:IsDescendantOf(workspace) then return false end
		local ok, reason = pcall(function()
			fireproximityprompt(prompt)
		end)
		if not ok then Farm.reportError("ProximityPrompt", reason) end
		return ok
	end

	local function cleanName(value)
		return (tostring(value or ""):gsub("<[^>]*>", ""):match("^%s*(.-)%s*$") or ""):lower()
	end

	local function ownerMatches(owner)
		if owner == nil or owner == "" then return false end
		if tonumber(owner) == LocalPlayer.UserId then return true end
		local name = cleanName(owner)
		if name == LocalPlayer.Name:lower() or name == "@" .. LocalPlayer.Name:lower() then return true end
		if name ~= cleanName(LocalPlayer.DisplayName) then return false end
		for _, candidate in ipairs(Players:GetPlayers()) do
			if candidate ~= LocalPlayer and cleanName(candidate.DisplayName) == name then return false end
		end
		return true
	end

	local function baseLabel(base)
		local current = base
		for _, name in ipairs({ "Sign", "Display", "BaseDisplayGui", "Frame", "Info", "PlayerName" }) do
			current = current and current:FindFirstChild(name)
		end
		return current and current:IsA("TextLabel") and current.Text or nil
	end

	local function myBase()
		local bases = workspace:FindFirstChild("Bases")
		if not bases then return nil end
		local index = LocalPlayer:GetAttribute("Base")
		local indexed = index ~= nil and bases:FindFirstChild(tostring(index))
		if indexed and (indexed:GetAttribute("Owner") == nil or ownerMatches(indexed:GetAttribute("Owner"))) then
			return indexed
		end
		local owned, signed
		local signMatches = 0
		for _, base in ipairs(bases:GetChildren()) do
			local owner = base:GetAttribute("Owner")
			if ownerMatches(owner) then
				if owned then return nil end
				owned = base
			elseif (owner == nil or owner == "") and ownerMatches(baseLabel(base)) then
				signMatches += 1
				signed = base
			end
		end
		return owned or signMatches == 1 and signed or nil
	end

	local function leaderstat(name)
		local ls = LocalPlayer:FindFirstChild("leaderstats")
		local value = ls and ls:FindFirstChild(name)
		return value and tonumber(value.Value) or 0
	end
	local function cash() return leaderstat("Cash") end
	local function rebirths() return leaderstat("Rebirths") end

	local function bestOwnWeight()
		local best = 0
		local folder = LocalPlayer:FindFirstChild("Slots")
		if folder then
			for _, slot in ipairs(folder:GetChildren()) do
				local weight = tonumber(slot:GetAttribute("Weight")) or 0
				if weight > best then best = weight end
			end
		end
		return best
	end

	local function petWeight(name)
		local animal = name and Animals and Animals[name]
		return type(animal) == "table" and tonumber(animal.weight) or 0
	end

	local function freeNest()
		local base = myBase()
		if not base then return nil, "Chưa nhận diện được nhà của bạn" end
		local slots = LocalPlayer:FindFirstChild("Nests")
		local nests = base:FindFirstChild("Nests")
		if not nests then return nil, "Thiếu dữ liệu ổ (Nests)" end
		local known = false
		for _, nest in ipairs(nests:GetChildren()) do
			local slot = slots and slots:FindFirstChild(nest.Name) or nest
			local owned = slot:GetAttribute("Owned")
			if owned ~= nil then known = true end
			if owned and not slot:GetAttribute("Egg") and nest:IsA("PVInstance") then
				return nest
			end
		end
		return nil, known and "Hết ổ trống" or "Thiếu dữ liệu ổ (Nests)"
	end

	local function deliveryPosition()
		local nest, reason = freeNest()
		if nest then return nest:GetPivot().Position end
		local base = myBase()
		local part = base and base:FindFirstChild("Part")
		if reason ~= "Hết ổ trống" and part and part:IsA("BasePart") then return part.Position end
		return nil, reason
	end

	-- trứng thật có thể mua: là model trứng, đã bay tới, và không có người chơi trốn bên trong
	local function isRealEgg(model)
		if not model or not model.Parent then return false end
		if model:GetAttribute("Owner") ~= nil then return false end
		if not model:GetAttribute("IsEgg") or not model:GetAttribute("BaseName") then return false end
		if not model:GetAttribute("CountdownEnd") then return false end
		return not model:FindFirstChildWhichIsA("Humanoid", true) and not model:FindFirstChildWhichIsA("Player", true)
	end

	local function eggModel(prompt)
		local ancestor = prompt.Parent
		while ancestor and ancestor ~= workspace do
			if (ancestor:IsA("Model") or ancestor:IsA("BasePart")) and ancestor:GetAttribute("BaseName") then
				return ancestor
			end
			ancestor = ancestor.Parent
		end
		return nil
	end

	local fakeEggMarkers = {}

	local function clearFakeEggMarker(model)
		local marker = fakeEggMarkers[model]
		if marker then marker.gui:Destroy(); fakeEggMarkers[model] = nil end
	end

	local function isFakeEgg(model, hasBuyPrompt, bases, nestEggs)
		if not model.Parent or not model:IsDescendantOf(workspace) then return false end
		if not model:GetAttribute("BaseName") and model:GetAttribute("IsEgg") ~= true then return false end
		if not hasBuyPrompt and model:GetAttribute("IsEgg") ~= true then return false end
		local character = LocalPlayer.Character
		if character and (model == character or model:IsDescendantOf(character)) then return false end
		if model:FindFirstAncestorOfClass("Tool") then return false end
		local humanoid = model:FindFirstChildWhichIsA("Humanoid", true)
		if humanoid then return humanoid.Health > 0 end
		if model:FindFirstChildWhichIsA("Player", true) then return true end
		if bases and model:IsDescendantOf(bases) or nestEggs and model:IsDescendantOf(nestEggs) then return false end
		local owner = model:GetAttribute("Owner")
		return hasBuyPrompt and (type(owner) == "number" and owner > 0
			or type(owner) == "string" and owner ~= "" and owner ~= "0")
	end

	local function updateFakeEggESP()
		if not active() or not cfg.fakeEggESP then return end
		local candidates, wanted = {}, {}
		local bases, nestEggs = workspace:FindFirstChild("Bases"), workspace:FindFirstChild("NestEggs")
		for prompt in pairs(prompts) do
			if prompt.Parent and prompt.Enabled and (prompt.ActionText == "Buy" or prompt.Name == "BuyPrompt") then
				local model = eggModel(prompt)
				if model then candidates[model] = true end
			end
		end
		for _, target in ipairs(Players:GetPlayers()) do
			local character = target.Character
			if target ~= LocalPlayer and character and character:GetAttribute("IsEgg") == true then
				candidates[character] = candidates[character] or false
			end
		end
		for model, hasBuyPrompt in pairs(candidates) do
			if isFakeEgg(model, hasBuyPrompt, bases, nestEggs) then
				local part = model:IsA("BasePart") and model or model.PrimaryPart
				if not part or part ~= model and not part:IsDescendantOf(model) then
					part = model:FindFirstChildWhichIsA("BasePart", true)
				end
				if part then wanted[model] = part end
			end
		end
		for model in pairs(wanted) do
			local ancestor = model.Parent
			while ancestor and ancestor ~= workspace do
				if wanted[ancestor] then wanted[model] = nil; break end
				ancestor = ancestor.Parent
			end
		end
		for model, marker in pairs(fakeEggMarkers) do
			if wanted[model] ~= marker.part or not marker.gui.Parent then clearFakeEggMarker(model) end
		end
		local now = os.clock()
		for model, part in pairs(wanted) do
			local marker = fakeEggMarkers[model]
			if not marker then
				local billboard = Instance.new("BillboardGui")
				billboard.Name, billboard.Adornee = "BaoAnhFakeEggESP", part
				billboard.AlwaysOnTop, billboard.LightInfluence = true, 0
				billboard.Size, billboard.SizeOffset = UDim2.fromOffset(180, 72), Vector2.new(0, 0.5)
				for _, properties in ipairs({
					{ Name = "FakeEggLabel", Text = "điếm chó", TextSize = 23, TextColor3 = Color3.new(1, 1, 1),
						Position = UDim2.fromOffset(0, 0), Size = UDim2.new(1, 0, 0, 32) },
					{ Name = "FakeEggArrow", Text = "▼", TextSize = 36, TextColor3 = Color3.fromRGB(255, 60, 60),
						Position = UDim2.fromOffset(0, 30), Size = UDim2.new(1, 0, 0, 42) },
				}) do
					local text = Instance.new("TextLabel")
					text.BackgroundTransparency, text.Font = 1, Enum.Font.SourceSansBold
					text.TextStrokeColor3, text.TextStrokeTransparency = Color3.new(0, 0, 0), 0
					for property, value in pairs(properties) do text[property] = value end
					text.Parent = billboard
				end
				billboard.Parent = part
				marker = { gui = billboard, part = part, boundsAt = 0 }
				fakeEggMarkers[model] = marker
			end
			if now >= marker.boundsAt then
				local top = part.Position.Y + part.Size.Y * 0.5
				if model:IsA("Model") then
					local bounds, size = model:GetBoundingBox()
					top = bounds.Position.Y + size.Y * 0.5
				end
				marker.gui.StudsOffsetWorldSpace = Vector3.new(0, math.max(1, top - part.Position.Y + 0.75), 0)
				marker.boundsAt = now + 1
			end
		end
	end

	function Farm.setFakeEggESP(enabled)
		if not active() then return false, "Script đã dừng" end
		cfg.fakeEggESP = enabled
		if enabled then
			ensurePromptIndex()
			updateFakeEggESP()
		else
			for model in pairs(fakeEggMarkers) do clearFakeEggMarker(model) end
		end
		return true
	end

	local collection, collectPromptConnection, collectRelay, collectListener
	local lastCarrying, equipCooldown = false, 0

	local function queueCollection()
		if not active() or not cfg.instantCollect or collection or cfg.farm or cfg.rebirthFarm or cfg.steal then return end
		local root = rootPart()
		if not root then return end
		collection = { root = root, readyAt = os.clock() + 1, phase = "deliver" }
	end

	local function installCollectHook()
		local folder = ReplicatedStorage:FindFirstChild("EggRemotes")
		local event = folder and folder:FindFirstChild("EggEvent")
		if not event or not (event:IsA("RemoteEvent") or event:IsA("RemoteFunction")) then return false end
		local relay = _G.__BaoAnhCollectHook
		if type(relay) ~= "table" or not relay.installed then
			if type(hookmetamethod) ~= "function" or type(getnamecallmethod) ~= "function" then return false end
			relay = {}
			local originalNamecall
			local function intercept(instance, ...)
				local listener = relay.listener
				if not listener or instance ~= relay.remote or (...) ~= "Buy" then return originalNamecall(instance, ...) end
				local method = getnamecallmethod()
				if method ~= "FireServer" and method ~= "InvokeServer" then return originalNamecall(instance, ...) end
				local results = table.pack(originalNamecall(instance, ...))
				if relay.listener == listener then pcall(listener) end
				return table.unpack(results, 1, results.n)
			end
			local ok, result = pcall(function()
				return hookmetamethod(game, "__namecall", type(newcclosure) == "function" and newcclosure(intercept) or intercept)
			end)
			if not ok or type(result) ~= "function" then
				Farm.reportError("Instant Collect", ok and "Hook không trả về hàm gốc" or result)
				return false
			end
			originalNamecall, relay.installed = result, true
			_G.__BaoAnhCollectHook = relay
		end
		relay.remote, relay.listener = event, collectListener
		collectRelay = relay
		return true
	end

	local function setCollectEnabled(enabled)
		collection, lastCarrying = nil, false
		if collectRelay and collectRelay.listener == collectListener then collectRelay.listener = nil end
		collectListener = nil
		if collectPromptConnection then collectPromptConnection:Disconnect(); collectPromptConnection = nil end
		if not enabled then return end
		collectListener = function() queueCollection() end
		state.collectMode = installCollectHook() and "EggEvent + Carrying/Prompt" or "Carrying/Prompt (không có hook)"
		local ok, service = pcall(game.GetService, game, "ProximityPromptService")
		if ok then
			collectPromptConnection = service.PromptTriggered:Connect(function(prompt, actor)
				if (actor == nil or actor == LocalPlayer) and prompt and prompt:IsA("ProximityPrompt")
					and (prompt.ActionText == "Buy" or prompt.Name == "BuyPrompt") and eggModel(prompt) then
					queueCollection()
				end
			end)
		end
	end

	local function collectStep()
		if not cfg.instantCollect or cfg.farm or cfg.rebirthFarm or cfg.steal then
			collection = nil
			return false
		end
		if not collection then return false end
		if not actionValid(collection.root, "instantCollect") then collection = nil; return false end
		if os.clock() < collection.readyAt then return true end
		if collection.phase == "deliver" then
			local base = myBase()
			local part = base and base:FindFirstChild("Part")
			local position, reason = deliveryPosition()
			if part and part:IsA("BasePart") then position = part.Position end
			if not position then
				collection = nil
				Farm.reportError("Instant Collect", reason)
				return false
			end
			collection.origin = collection.root.CFrame
			teleport(position)
			collection.destination = collection.root.Position
			collection.phase, collection.readyAt = "return", os.clock() + 1
			state.text = "Instant Collect: đang giao trứng"
		else
			if (collection.root.Position - collection.destination).Magnitude <= 8 then
				collection.root.CFrame = collection.origin
			end
			collection = nil
			state.text = "Instant Collect: hoàn tất lượt giao"
		end
		return true
	end

	local function equipStep()
		if not cfg.equipBest or os.clock() < equipCooldown then return end
		equipCooldown = os.clock() + 2
		local event = remote("EquipBestEvent")
		if not event then Farm.reportError("Equip Best", "Thiếu RemoteEvents.EquipBestEvent"); return end
		event:FireServer()
	end

	-- trứng mà lần rebirth tiếp theo yêu cầu ấp ra
	local function rebirthAnimal()
		if not Rebirth then return nil end
		local ok, data = pcall(Rebirth.getNext, rebirths())
		if not ok then Farm.reportError("Yêu cầu Rebirth", data) end
		if ok and type(data) == "table" then return data.animal end
		return nil
	end

	---------------- danh sách cho các ô chọn ----------------
	local function uniqueSorted(source, field)
		local out, seen = {}, {}
		if type(source) == "table" then
			for _, info in pairs(source) do
				local v = type(info) == "table" and info[field]
				if type(v) == "string" and not seen[v] then
					seen[v] = true
					table.insert(out, v)
				end
			end
		end
		table.sort(out)
		return out
	end
	function Farm.eggNames()
		local names = {}
		if Eggs and type(Eggs.ByName) == "table" then
			for name, info in pairs(Eggs.ByName) do
				if type(name) == "string" and type(info) == "table" then table.insert(names, name) end
			end
		end
		table.sort(names)
		return names
	end
	function Farm.eggRarities() return uniqueSorted(Eggs and Eggs.ByName, "rarityType") end

	local function itemNameList(module)
		local out = {}
		if module and type(module.List) == "table" then
			for _, item in ipairs(module.List) do
				if type(item) == "table" and type(item.name) == "string" then table.insert(out, item.name) end
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
				if type(info) == "table" and info.weight and type(info.rarityType) == "string" and not seen[info.rarityType] then
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
		if not (Eggs and type(Eggs.ByName) == "table" and Animals) then return nil end
		local rebirthMode = mode == "rebirth"
		local wanted = rebirthMode and rebirthAnimal() or nil
		if rebirthMode and not wanted then return nil end -- không có yêu cầu rebirth thì không mua gì
		local best, bestScore = nil, -1
		local money = cash()
		local bestWeight = cfg.onlyBetter and bestOwnWeight() or 0
		local now = os.clock()
		local names, rarities = cfg.eggNames, cfg.eggRarities
		local namesOn, raritiesOn = next(names) ~= nil, next(rarities) ~= nil
		local realOnly = rebirthMode or cfg.skipFake -- farm rebirth luôn bỏ qua trứng giả

		for prompt in pairs(prompts) do
			if (prompt.ActionText == "Buy" or prompt.Name == "BuyPrompt") and prompt.Parent and prompt.Enabled then
				local model = eggModel(prompt)
				local eggName = model and model:GetAttribute("BaseName")
				local info = eggName and Eggs.ByName[eggName]
				local price = type(info) == "table" and tonumber(info.price)
				local blockedUntil = buyBlocked[prompt]
				if price and price >= 0 and price <= money
					and (not cfg.maxPriceEnabled or price <= cfg.maxPrice)
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
							local score = tonumber(info.rarity) or 0
							if score > bestScore then
								best, bestScore = { prompt = prompt, info = info, weight = weight, price = price }, score
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
			local owner = model:GetAttribute("Owner")
			if model:IsA("PVInstance") and (owner == nil or ownerMatches(owner)) and (hatchCooldown[model] or 0) < now then
				local cached = hatchPrompts[model]
				local prompt = cached and cached.prompt
				if prompt and (not prompt:IsDescendantOf(model) or prompt.Name ~= "HatchPrompt" and prompt.ActionText ~= "Hatch") then prompt = nil end
				if not prompt and (not cached or now >= cached.retryAt) then
					prompt = model:FindFirstChild("HatchPrompt", true)
					if not prompt or not prompt:IsA("ProximityPrompt") then
						prompt = nil
						for _, child in ipairs(model:GetDescendants()) do
							if child:IsA("ProximityPrompt") and child.ActionText == "Hatch" then
								prompt = child
								break
							end
						end
					end
					hatchPrompts[model] = { prompt = prompt, retryAt = now + 1 }
				end
				if prompt and prompt.Enabled then
					hatchCooldown[model] = now + 2
					local actionRoot = teleport(model:GetPivot().Position + Vector3.new(0, -1, 3))
					if actionRoot then
						task.wait(0.12)
						if not actionValid(actionRoot, "autoHatch") or LocalPlayer:GetAttribute("Carrying")
							or state.pendingPrompt then return true end
						if firePrompt(prompt) then
							state.text = "Đang ấp trứng"
							stats.hatched += 1
							Farm.notify("Đã gửi lệnh ấp: " .. tostring(model:GetAttribute("BaseName")))
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
		local setting = rebirthMode and "rebirthFarm" or "farm"
		if not active() or not cfg[setting] then return end

		if LocalPlayer:GetAttribute("Carrying") then -- đang cầm trứng → mang về ổ trống
			local position, reason = deliveryPosition()
			if position then
				teleport(position)
				state.text = rebirthMode and "Đang farm cho rebirth" or "Đang mang trứng về ổ"
			else
				state.text = reason
			end
			return
		end

		-- đang chờ lệnh mua trước đó có hiệu lực
		if state.pendingPrompt then
			state.text = "Đang chờ xác nhận mua"
			if os.clock() - state.pendingAt > 3 then
				buyBlocked[state.pendingPrompt] = os.clock() + 20 -- mua không được → tạm bỏ qua trứng này 20 giây
				state.pendingPrompt = nil
				state.text = "Mua chưa được xác nhận, thử trứng khác"
			end
			return
		end

		if not (Eggs and type(Eggs.ByName) == "table" and Animals) then
			state.text = (loading.Eggs or loading.Animals) and "Đang tải dữ liệu trứng" or "Không tìm thấy dữ liệu Fake an Egg"
			return
		end
		local destination, reason = deliveryPosition()
		if not destination then
			state.text = reason
			return
		end
		if type(fireproximityprompt) ~= "function" then
			state.text = "Thiếu fireproximityprompt"
			return
		end
		if not ensurePromptIndex() then
			state.text = "Đang tìm trứng trong map"
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
		local actionRoot = position and teleport(position)
		if actionRoot then
			task.wait(0.15)
			if not actionValid(actionRoot, setting) or LocalPlayer:GetAttribute("Carrying") or not deliveryPosition() then return end
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
		local ownBase = myBase()
		local bases = workspace:FindFirstChild("Bases")
		if not bases then return nil end
		for _, base in ipairs(bases:GetChildren()) do
			local owner = base:GetAttribute("Owner")
			if base ~= ownBase and owner and not ownerMatches(owner) then
				for _, pet in ipairs(base:GetChildren()) do
					local weight = petWeight(pet.Name)
					if pet:IsA("Model") and weight > bestWeight then
						for _, child in ipairs(pet:GetDescendants()) do
							if child:IsA("ProximityPrompt") and child.Enabled and (child.ActionText == "Steal" or child.Name == "StealPrompt") then
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
			local position, reason = deliveryPosition()
			if position then
				teleport(position)
				state.text = "Đang mang pet về ổ"
			else
				state.text = reason
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
		local actionRoot = position and teleport(position)
		if actionRoot then
			task.wait(0.2)
			if not actionValid(actionRoot, "steal") or LocalPlayer:GetAttribute("Carrying") then return end
			local fired = firePrompt(target.prompt)
			if not fired then -- bấm prompt không được thì gửi thẳng lệnh trộm lên server
				local owner = target.base:GetAttribute("Owner")
				local victim
				for _, candidate in ipairs(Players:GetPlayers()) do
					if candidate.UserId == tonumber(owner) or candidate.Name == tostring(owner) then victim = candidate; break end
				end
				local ev = remote("StealEvent")
				if victim and ev then
					fired = pcall(function() ev:FireServer(victim.UserId, target.pet.Name) end)
				end
			end
			if fired then
				stats.stolen += 1
				stealCooldown = now + 1.5
				Farm.notify("Đã gửi lệnh trộm " .. target.name .. " (nặng " .. fmt(target.weight) .. ")")
				if cfg.returnHome then
					local base = myBase()
					local spawnPart = base and (base:FindFirstChild("Spawn") or base:FindFirstChild("Part"))
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
		if not active() or not (cfg.rebirth or cfg.rebirthFarm) or not Rebirth then return end
		local now = os.clock()
		if now < rebirthCooldown then return end
		local ok, can = pcall(Rebirth.CanRebirth, LocalPlayer)
		if not ok then Farm.reportError("Điều kiện Rebirth", can) end
		local ev = remote("RebirthEvent")
		if ok and can and ev then
			rebirthCooldown = now + 3
			local before = rebirths()
			ev:FireServer()
			Farm.notify("Đã gửi yêu cầu rebirth (trước đó: " .. tostring(before) .. ")")
		end
	end

	---------------- 4. SHOPS: tự mua scanner / thức ăn ----------------
	local scannerCooldown, foodCooldown = 0, 0
	local shopPending = { scanner = nil, food = nil }

	local function shopPosition(name)
		local map = workspace:FindFirstChild("Map")
		local model = map and map:FindFirstChild(name)
		return model and model:IsA("PVInstance") and model:GetPivot().Position or nil
	end

	local function shopStock(kind, name)
		local module = kind == "scanner" and Scanners or Food
		if not module then return 0 end
		local ok, stock = pcall(module.stock, LocalPlayer, name)
		if ok and type(stock) == "number" then return stock end
		if not ok and type(module.stock) == "function" then Farm.reportError("Tồn kho " .. kind, stock) end
		local prefix = kind == "scanner" and "Stock" or "FoodStock"
		return tonumber(LocalPlayer:GetAttribute(prefix .. name)) or 0
	end

	-- món tốt nhất đã chọn, còn hàng, đã mở khóa và đủ tiền
	local function bestShopItem(kind)
		local module = kind == "scanner" and Scanners or Food
		if not (module and type(module.List) == "table") then return nil, 0 end
		local chosen = kind == "scanner" and cfg.scannerTypes or cfg.foodTypes
		local filterOn = next(chosen) ~= nil
		local money = cash()
		local best, bestRank, bestStock = nil, -1, 0
		for _, item in ipairs(module.List) do
			local price = type(item) == "table" and tonumber(item.price)
			if price and price >= 0 and type(item.name) == "string" then
				local stock = shopStock(kind, item.name)
				local unlocked = rebirths() >= (tonumber(item.rebirth) or 0)
				local allowed = not filterOn or chosen[item.name] == true
				if allowed and unlocked and stock > 0 and price <= money and price <= cfg.shopMax then
					local rank = tonumber(item.rank) or 0
					if rank > bestRank then
						best, bestRank, bestStock = item, rank, stock
					end
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
		if not ev or not position then return false end
		local actionRoot = teleport(position + Vector3.new(0, 2, 5))
		if not actionRoot then return false end

		task.wait(0.15)
		if not actionValid(actionRoot, kind == "scanner" and "buyScanners" or "buyFood")
			or LocalPlayer:GetAttribute("Carrying") or state.pendingPrompt then return true end
		local ok, reason = pcall(function() ev:FireServer("Buy", item.name) end)
		if not ok then Farm.reportError("Mua " .. kind, reason); return false end

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
		if ok and type(animal) == "table" then return key, pet, animal end
		if not ok then Farm.reportError("Đọc Inventory", key) end
		return nil
	end

	local function bestInventoryWeight()
		local inventory = LocalPlayer:FindFirstChild("Inventory")
		local best = 0
		if not (inventory and Animals) then return best end
		for attr, count in pairs(inventory:GetAttributes()) do
			if type(count) == "number" and count > 0
				and not (attr:match("_Size$") or attr:match("_Weight$") or attr:match("_Mood$")) then
				local _, _, animal = parseInventoryPet(attr)
				local weight = animal and tonumber(animal.weight) or 0
				if weight > best then
					best = weight
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
					local weight = tonumber(animal.weight) or 0
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
		if not ev or not position then return false end
		local actionRoot = teleport(position + Vector3.new(0, 2, 5))
		if not actionRoot then return false end

		task.wait(0.12)
		if not actionValid(actionRoot, "autoSell") or LocalPlayer:GetAttribute("Carrying") or state.pendingPrompt then return true end
		local ok, reason = pcall(function() ev:FireServer(key) end)
		if not ok then Farm.reportError("Bán pet", reason); return false end

		sellCooldown = os.clock() + math.max(0.5, cfg.sellEvery or 2)
		sellPending = { attr = attr, count = count, pet = pet, weight = weight, at = os.clock() }
		state.sell = tostring(pet)
		return true
	end

	---------------- vòng lặp chính ----------------
	local function runStep(feature, callback, ...)
		local ok, result = pcall(callback, ...)
		if not ok then Farm.reportError(feature, result); return false end
		return result
	end

	local function tick()
		if not active() then return end
		runStep("Equip Best", equipStep)
		confirmBuy()
		confirmShopPurchase("scanner")
		confirmShopPurchase("food")
		confirmSale()

		if not (cfg.farm or cfg.rebirthFarm) then state.pendingPrompt = nil end
		local carrying = not not LocalPlayer:GetAttribute("Carrying")
		if carrying and not lastCarrying then queueCollection() end
		lastCarrying = carrying
		if runStep("Instant Collect", collectStep) then return end
		if not rootPart() then state.text = "Đang chờ nhân vật"; return end
		if LocalPlayer:GetAttribute("Carrying") then
			if cfg.farm or cfg.rebirthFarm then
				farmStep(cfg.rebirthFarm and "rebirth" or "normal")
			elseif cfg.steal then
				stealStep()
			else
				state.text = "Đang cầm vật phẩm"
			end
			return
		end
		if state.pendingPrompt then
			farmStep(cfg.rebirthFarm and "rebirth" or "normal")
			return
		end

		if cfg.autoHatch and runStep("Auto Hatch", hatchReady) then return end

		local did = false
		if cfg.buyScanners then did = runStep("Auto Mua Scanner", shopStep, "scanner") end
		if not did and cfg.buyFood then did = runStep("Auto Mua Thức Ăn", shopStep, "food") end
		if not did and cfg.autoSell then did = runStep("Auto Sell", sellStep) end
		if did then return end

		if cfg.rebirthFarm then
			runStep("Farm Trứng Theo Rebirth", farmStep, "rebirth")
		elseif cfg.farm then
			runStep("Auto Farm", farmStep, "normal")
		elseif cfg.steal then
			runStep("Auto Steal", stealStep)
		else
			state.text = "Đang chờ"
		end

		if not state.pendingPrompt and not LocalPlayer:GetAttribute("Carrying") then runStep("Auto Rebirth", rebirthStep) end
	end

	---------------- giao diện gọi vào ----------------
	function Farm.checkExecutor()
		if type(fireproximityprompt) ~= "function" then
			return false, "Thiếu fireproximityprompt; Roblox/VNG chính thức không cung cấp API này"
		end
		return true
	end

	local function dependencyError(name)
		return loading[name] and ("Đang tải " .. name .. ", hãy thử lại")
			or Farm.errors[name] or ("Dữ liệu " .. name .. " không tương thích")
	end

	function Farm.setEnabled(setting, enabled)
		if not active() then return false, "Script đã dừng" end
		if enabled then
			if setting == "farm" or setting == "rebirthFarm" or setting == "autoHatch" or setting == "steal" then
				local supported, reason = Farm.checkExecutor()
				if not supported then return false, reason end
			end
			if setting == "farm" or setting == "rebirthFarm" then
				if not (Eggs and type(Eggs.ByName) == "table") then return false, dependencyError("Eggs") end
				if not Animals then return false, dependencyError("Animals") end
				local destination, reason = deliveryPosition()
				if not destination then return false, reason end
			end
			if setting == "rebirth" or setting == "rebirthFarm" then
				if not (Rebirth and type(Rebirth.CanRebirth) == "function")
					or setting == "rebirthFarm" and type(Rebirth.getNext) ~= "function" then
					return false, dependencyError("Rebirth")
				end
				if not remote("RebirthEvent") then return false, "Thiếu RemoteEvents.RebirthEvent" end
			end
			if setting == "steal" and not Animals then return false, dependencyError("Animals") end
			if setting == "buyScanners" or setting == "buyFood" then
				local module = setting == "buyScanners" and Scanners or Food
				local name = setting == "buyScanners" and "Scanners" or "Food"
				if not module or type(module.List) ~= "table" then return false, dependencyError(name) end
				local eventName = setting == "buyScanners" and "ScannerEvent" or "FoodEvent"
				if not remote(eventName) then return false, "Thiếu RemoteEvents." .. eventName end
				if not shopPosition(name) then return false, "Không tìm thấy Map." .. name end
			end
			if setting == "autoSell" then
				if not Animals or type(Animals.decodeAttr) ~= "function" or type(Animals.parseSlot) ~= "function" then
					return false, dependencyError("Animals")
				end
				if not LocalPlayer:FindFirstChild("Inventory") then return false, "Thiếu Inventory của người chơi" end
				if not remote("SellEvent") then return false, "Thiếu RemoteEvents.SellEvent" end
				if not shopPosition("Sell") then return false, "Không tìm thấy Map.Sell" end
			end
			if setting == "equipBest" and not remote("EquipBestEvent") then return false, "Thiếu RemoteEvents.EquipBestEvent" end
			if setting == "instantCollect" then
				local base = myBase()
				local part = base and base:FindFirstChild("Part")
				if not (part and part:IsA("BasePart")) and not deliveryPosition() then
					return false, "Chưa tìm thấy nhà / điểm giao trứng"
				end
			end
		end
		cfg[setting] = enabled
		if setting == "instantCollect" then setCollectEnabled(enabled) end
		if setting == "equipBest" then equipCooldown = 0 end
		if setting == "farm" or setting == "rebirthFarm" or setting == "steal" then collection = nil end
		if not cfg.farm and not cfg.rebirthFarm then state.pendingPrompt = nil end
		return true
	end

	function Farm.diagnose()
		Farm.refreshDependencies()
		local schemas = {
			Eggs = Eggs and type(Eggs.ByName) == "table",
			Animals = Animals and type(Animals.decodeAttr) == "function" and type(Animals.parseSlot) == "function",
			Rebirth = Rebirth and type(Rebirth.getNext) == "function" and type(Rebirth.CanRebirth) == "function",
			Scanners = Scanners and type(Scanners.List) == "table",
			Food = Food and type(Food.List) == "table",
		}
		local base = myBase()
		local destination, reason = deliveryPosition()
		local report = {
			ADMIN_LABEL .. " | PlaceId: " .. tostring(game.PlaceId),
			"Nhân vật: " .. (rootPart() and "sẵn sàng" or "chưa sẵn sàng"),
			"Nhà: " .. (base and base.Name or "không nhận diện được"),
			"Giao trứng: " .. (destination and "có điểm giao" or tostring(reason)),
			"fireproximityprompt: " .. type(fireproximityprompt),
			"Instant Collect: " .. (state.collectMode or "chưa bật; có dự phòng Carrying/Prompt"),
		}
		for _, name in ipairs(moduleNames) do
			local status = loadedModules[name] and (schemas[name] and "đã tải" or "đã tải nhưng sai cấu trúc dữ liệu")
				or dependencyError(name)
			table.insert(report, name .. ": " .. status)
		end
		local eggFolder = ReplicatedStorage:FindFirstChild("EggRemotes")
		local eggEvent = eggFolder and eggFolder:FindFirstChild("EggEvent")
		table.insert(report, "EggRemotes.EggEvent: " .. (eggEvent and eggEvent.ClassName or "thiếu"))
		for _, name in ipairs({ "EquipBestEvent", "RebirthEvent", "ScannerEvent", "FoodEvent", "SellEvent", "StealEvent" }) do
			table.insert(report, name .. ": " .. (remote(name) and "có" or "thiếu / sai loại"))
		end
		table.insert(report, "Gần nhất: " .. tostring(state.lastError or "chưa ghi nhận lỗi Lua"))
		table.insert(report, "Chỉ xác nhận dữ liệu/API phía client, không xác nhận server chấp nhận lệnh.")
		return table.concat(report, "\n")
	end

	function Farm.refreshInfo()
		if not active() then return end
		local ui = {}
		for key, label in pairs(Farm.ui) do
			local ancestor = label
			while ancestor and ancestor.Parent do
				if ancestor:IsA("GuiObject") and not ancestor.Visible then break end
				if ancestor:IsA("ScreenGui") then
					if ancestor.Enabled then ui[key] = label end
					break
				end
				ancestor = ancestor.Parent
			end
		end
		if not next(ui) then return end
		local function set(label, text)
			if label and label.Parent and label.Text ~= text then label.Text = text end
		end
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
			or cfg.buyScanners or cfg.buyFood or cfg.autoSell or cfg.instantCollect or cfg.equipBest
	end

	function Farm.shutdown()
		disposed = true
		cfg.fakeEggESP = false
		for model in pairs(fakeEggMarkers) do clearFakeEggMarker(model) end
		setCollectEnabled(false)
		state.pendingPrompt = nil
		Farm.notify = function() end
		for _, connection in ipairs(promptConnections) do connection:Disconnect() end
		table.clear(promptConnections)
		table.clear(prompts)
		table.clear(hatchPrompts)
		table.clear(hatchCooldown)
		table.clear(buyBlocked)
	end

	task.spawn(function()
		local nextRefreshAt = 0
		while active() do
			task.wait(0.35)
			if not active() then break end
			local ok, err = xpcall(function()
				if os.clock() >= nextRefreshAt then
					nextRefreshAt = os.clock() + 5
					Farm.refreshDependencies()
					if cfg.instantCollect and installCollectHook() then state.collectMode = "EggEvent + Carrying/Prompt" end
				end
				if cfg.fakeEggESP then updateFakeEggESP() end
				if anyOn() then tick() end
				Farm.refreshInfo()
			end, debug.traceback)
			if not ok then Farm.reportError("Vòng lặp", err) end
		end
		Farm.shutdown()
	end)
end

table.insert(Runtime.cleanups, Farm.shutdown)

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
	["Player ESP"] = function(on)
		espBox, espLine = on, on
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
	["ESP Trứng Giả"] = function(on) return Farm.setFakeEggESP(on) end,
	["Auto Farm"] = function(on)
		return Farm.setEnabled("farm", on)
	end,
	["Chỉ Trứng Thật"] = function(on)
		Farm.cfg.skipFake = on
		if not on then Farm.notify("Cảnh báo: trứng giả sẽ lấy tiền của bạn!") end
	end,
	["Auto Hatch"] = function(on)
		return Farm.setEnabled("autoHatch", on)
	end,
	["Instant Collect"] = function(on) return Farm.setEnabled("instantCollect", on) end,
	["Equip Best"] = function(on) return Farm.setEnabled("equipBest", on) end,
	["Chỉ Mua Trứng Tốt Hơn"] = function(on) Farm.cfg.onlyBetter = on end,
	["Giới Hạn Giá Trứng"] = function(on) Farm.cfg.maxPriceEnabled = on end,
	["Auto Steal"] = function(on)
		return Farm.setEnabled("steal", on)
	end,
	["Về Nhà Sau Khi Trộm"] = function(on) Farm.cfg.returnHome = on end,
	["Farm Trứng Theo Rebirth"] = function(on)
		return Farm.setEnabled("rebirthFarm", on)
	end,
	["Auto Rebirth"] = function(on) return Farm.setEnabled("rebirth", on) end,
	["Auto Mua Scanner"] = function(on) return Farm.setEnabled("buyScanners", on) end,
	["Auto Mua Thức Ăn"] = function(on) return Farm.setEnabled("buyFood", on) end,
	["Auto Sell Pets"] = function(on) return Farm.setEnabled("autoSell", on) end,
	["Auto Sell"] = function(on) return Farm.setEnabled("autoSell", on) end,
	["Giữ Lại Pet Mạnh Nhất"] = function(on) Farm.cfg.keepBest = on end,
	["Âm Thanh"] = function(on) Preferences.sound = on end,
	["Hiển Thị Thông Báo"] = function(on)
		Preferences.notifications = on
		if not on and Preferences.clearNotice then Preferences.clearNotice() end
	end,
	-- ["Auto Farm"] = function(on) print("Auto Farm:", on) end,
	-- ["Support"] = function() print("admin bảo anh") end,
}
local State = {} -- State["Auto Farm"] = true/false
local Groups = {} -- Groups["Farm"] = { "Auto Farm", "Auto Collect" } (gom công tắc theo nhóm)
local Controls = { painters = {}, busy = {} }

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

local VisualEffects = { enabled = false, visible = true, running = false, tweens = {} }
function VisualEffects.add(tween)
	table.insert(VisualEffects.tweens, tween)
	if VisualEffects.running then tween:Play() end
end
function VisualEffects.sync()
	local running = VisualEffects.enabled and VisualEffects.visible and not VisualEffects.disposed
	if running == VisualEffects.running then return end
	VisualEffects.running = running
	for _, tween in ipairs(VisualEffects.tweens) do
		if running then tween:Play() else tween:Pause() end
	end
	if VisualEffects.changed then VisualEffects.changed(running) end
end
function VisualEffects.setEnabled(enabled)
	VisualEffects.enabled = enabled
	VisualEffects.sync()
end
function VisualEffects.shutdown()
	VisualEffects.disposed = true
	VisualEffects.sync()
	for _, tween in ipairs(VisualEffects.tweens) do tween:Cancel() end
	table.clear(VisualEffects.tweens)
	VisualEffects.changed = nil
end
Callbacks["Hiệu Ứng Đẹp"] = VisualEffects.setEnabled
table.insert(Runtime.cleanups, VisualEffects.shutdown)

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

local guiParent = player:WaitForChild("PlayerGui")
if Runtime.closed then return end
local gui = new("ScreenGui", {
	Name = "BaoAnhScriptUI", ResetOnSpawn = false, IgnoreGuiInset = true,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling, DisplayOrder = 100,
}, guiParent)
Runtime.connect(gui.Destroying, Runtime.shutdown)
table.insert(Runtime.cleanups, function()
	if gui.Parent then gui:Destroy() end
end)

local main = new("Frame", {
	Name = "Main", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromOffset(W, H), BackgroundColor3 = Color3.new(1, 1, 1),
}, gui)
function VisualEffects.updateVisibility()
	VisualEffects.visible = main.Visible and gui.Enabled
	VisualEffects.sync()
end
main:GetPropertyChangedSignal("Visible"):Connect(VisualEffects.updateVisibility)
gui:GetPropertyChangedSignal("Enabled"):Connect(VisualEffects.updateVisibility)
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
VisualEffects.add(TweenService:Create(mainGradient, TweenInfo.new(4, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut, -1), { Rotation = 360 }))
VisualEffects.add(TweenService:Create(mainStroke, TweenInfo.new(0.7, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Transparency = 0 }))

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
VisualEffects.add(TweenService:Create(tabGradient, SPIN, { Rotation = 360 }))
VisualEffects.add(TweenService:Create(haloGradient, SPIN, { Rotation = 360 }))
VisualEffects.add(TweenService:Create(tabStroke, PULSE, { Transparency = 0 }))
VisualEffects.add(TweenService:Create(haloStroke, PULSE, { Transparency = 0.35, Thickness = 5 }))

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
	if v then Farm.refreshInfo() end
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
Runtime.connect(UserInputService.InputChanged, function(input)
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
Runtime.connect(UserInputService.InputBegan, function(input, processed)
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

local function headerBtn(text, x, callback)
	local b = new("TextButton", {
		Text = text, TextSize = ts(36), Font = F_BOLD, BackgroundTransparency = 1,
		Position = UDim2.new(1, -x, 0, 45), Size = UDim2.fromOffset(110, 110),
	}, header)
	themed(function() b.TextColor3 = theme.accent2 end)
	b.Activated:Connect(callback)
end
headerBtn("–", 300, function() setOpen(false) end)
headerBtn("✕", 160, Runtime.shutdown)

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
Runtime.connect(UserInputService.InputChanged, function(input)
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
Preferences.audio = new("Sound", { Name = "BaoAnhClick", SoundId = "rbxasset://sounds/electronicpingshort.wav", Volume = 0.25 }, gui)
local function renderStatus()
	local escaped = tostring(statusText):gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;")
	statusLabel.Text = 'Trạng thái: <font color="#' .. theme.accent2:ToHex() .. '">' .. escaped .. "</font>"
	tagline.TextColor3 = theme.accent2
end
themed(renderStatus)

function Preferences.clearNotice()
	if Runtime.closed then return end
	statusToken += 1
	statusText = "Đã sẵn sàng"
	renderStatus()
end

local function setStatus(text, important)
	if Runtime.closed or not Preferences.notifications and not important then return end
	statusToken += 1
	local token = statusToken
	statusText = text
	renderStatus()
	task.delay(important and 6 or 1.8, function()
		if statusToken == token then Preferences.clearNotice() end
	end)
end

Farm.notify = setStatus -- logic Farm báo trạng thái lên thanh dưới menu

function Controls.commit(text, enabled, animate)
	local function update(name, value)
		State[name] = value
		local paint = Controls.painters[name]
		if paint then paint(animate) end
	end
	update(text, enabled)
	if text == "Auto Sell" then update("Auto Sell Pets", enabled)
	elseif text == "Auto Sell Pets" then update("Auto Sell", enabled)
	elseif text == "Player ESP" then
		update("ESP Khung", enabled)
		update("ESP Line", enabled)
	end
	if text == "ESP Khung" or text == "ESP Line" then
		update("Player ESP", State["ESP Khung"] == true and State["ESP Line"] == true)
	end
end

function Controls.change(text, enabled, quiet)
	if Runtime.closed or Controls.busy[text] then return false end
	Controls.busy[text] = true
	local previous = State[text] == true
	local callback = Callbacks[text]
	local ok, result, reason = false, nil, "Nút chưa được gắn logic"
	if type(callback) == "function" then ok, result, reason = pcall(callback, enabled) end
	Controls.busy[text] = nil
	if Runtime.closed then return false end
	if not ok or result == false then
		if type(callback) == "function" then
			local restored, accepted = pcall(callback, previous)
			if not restored or accepted == false then pcall(callback, false); previous = false end
		end
		Controls.commit(text, previous, false)
		Farm.reportError("Nút " .. text, not ok and result or reason or "Không thể áp dụng", true)
		return false
	end
	Controls.commit(text, enabled, not quiet)
	if not quiet then
		setStatus((enabled and "Đã bật: " or "Đã tắt: ") .. text)
		if Preferences.sound then pcall(function() Preferences.audio:Play() end) end
	end
	return true
end

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
	State[text] = false
	if group then
		Groups[group] = Groups[group] or {}
		table.insert(Groups[group], text)
	end
	local sw = new("TextButton", {
		Name = text,
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
	Controls.painters[text] = paint
	themed(function() paint(false) end)
	Controls.change(text, default, true)

	sw.Activated:Connect(function()
		Controls.change(text, not State[text])
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
	Runtime.connect(UserInputService.InputChanged, function(input)
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

	local selected, count, buttons, built = {}, 0, {}, nil
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
	local function build()
		local opts = getOptions()
		local unchanged = built ~= nil and #opts == #built
		if unchanged then
			for index, name in ipairs(opts) do
				if built[index] ~= name then unchanged = false; break end
			end
		end
		if unchanged then return end
		built = table.clone(opts)
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
	Farm.refreshInfo()
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
	toggle(farmCard, 11, "📥", "Instant Collect", false, "Farm")
	toggle(farmCard, 12, "🏆", "Equip Best", false, "Farm")

	local statusCard = card(pages["Farm"], 2, "📊", 'Trạng Thái <font size="' .. SMALL .. '">(Farm)</font>', "Cập nhật trực tiếp khi đang chạy", Color3.fromRGB(56, 189, 248))
	Farm.ui.state = Farm.infoRow(statusCard, 1, "📡", "Trạng Thái", 900)
	Farm.ui.cash = Farm.infoRow(statusCard, 2, "💵", "Tiền", 640)
	Farm.ui.best = Farm.infoRow(statusCard, 3, "🏆", "Pet Mạnh Nhất", 640)
	Farm.ui.bought = Farm.infoRow(statusCard, 4, "🛒", "Trứng Đã Mua", 640)
	Farm.ui.hatched = Farm.infoRow(statusCard, 5, "🐣", "Lượt Gửi Lệnh Ấp", 640)
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
	Farm.ui.stStolen = Farm.infoRow(s, 2, "🥷", "Lượt Gửi Lệnh Trộm", 640)
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
toggle(autoCard, 2, "💲", "Auto Sell", false, "Tự Động")

-- Tab: Player
local playerCard = card(newPage("Player"), 1, "👤", 'Player <font size="' .. SMALL .. '">(Nhân Vật)</font>', "Chỉ thay đổi client; server có thể từ chối / đặt lại", Color3.fromRGB(34, 211, 160))
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
toggle(espCard, 10, "🔲", "Player ESP", false, "ESP")
toggle(espCard, 11, "▼", "ESP Trứng Giả", false, "ESP")
dropdown(espCard, 8, "🎨", "Màu ESP", ESP_COLOR_NAMES, "Đỏ", function(name)
	espColor = ESP_COLORS[name] or espColor
	espRefresh()
	setStatus("Màu ESP: " .. name)
end)
dropdown(espCard, 9, "⚡", "FPS ESP", { "20 FPS", "30 FPS", "60 FPS" }, "30 FPS", function(name)
	espInterval = 1 / (ESP_FRAME_RATES[name] or 30)
	espRefresh()
	setStatus("ESP: " .. name)
end)

-- Tab: Cài Đặt
local setCard = card(newPage("Cài Đặt"), 1, "🎚️", "Cài Đặt", "Tùy chỉnh giao diện & chức năng", Color3.fromRGB(234, 179, 8))
toggle(setCard, 1, "✨", "Hiệu Ứng Đẹp", false, "Cài Đặt")
toggle(setCard, 2, "🔊", "Âm Thanh", true, "Cài Đặt")
toggle(setCard, 3, "🔔", "Hiển Thị Thông Báo", true, "Cài Đặt")
dropdown(setCard, 4, "🎨", "Giao Diện Màu", THEME_NAMES, "Xanh Dương", function(name)
	applyTheme(name)
	setStatus("Đổi giao diện: " .. name)
end)

do
	local diagnosticRow = row(setCard, 5, "🩺", "Chẩn Đoán", 480)
	local button = new("TextButton", {
		Name = "Diagnose", Text = "Kiểm tra", TextSize = ts(24), Font = F_MED, TextColor3 = TEXT,
		BackgroundColor3 = OFF, AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -24, 0.5, 0), Size = UDim2.fromOffset(420, 104),
	}, diagnosticRow)
	corner(button, 22)
	local report = new("TextBox", {
		Name = "BaoAnhDiagnostics", Visible = false, Text = "", ClearTextOnFocus = false, MultiLine = true,
		TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top,
		TextSize = ts(17), Font = F_REG, TextColor3 = TEXT, BackgroundColor3 = ROW,
		LayoutOrder = 6, Size = UDim2.new(1, 0, 0, 1500),
	}, setCard)
	pad(report, 20, 20, 20, 20)
	button.Activated:Connect(function()
		local ok, result = pcall(Farm.diagnose)
		if not ok then Farm.reportError("Chẩn Đoán", result) end
		report.Text, report.Visible = tostring(result), true
		print("[bảo anh] " .. tostring(result))
		setStatus("Đã tạo chẩn đoán; sao chép khung bên dưới để báo lỗi", true)
	end)
end

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
-- CHỮ 7 MÀU: chỉ chạy khi bật Hiệu Ứng Đẹp và menu đang hiện.
----------------------------------------------------------------
do
	local colors = {
		Color3.fromRGB(255, 70, 70), Color3.fromRGB(255, 150, 40), Color3.fromRGB(255, 230, 60),
		Color3.fromRGB(60, 230, 90), Color3.fromRGB(50, 170, 255), Color3.fromRGB(125, 115, 255),
		Color3.fromRGB(200, 100, 255),
	}
	local texts = {}
	local beat, addConnection, removeConnection
	local function colorAt(phase)
		local position = (phase % 1) * 7
		local index = math.floor(position)
		return colors[index + 1]:Lerp(colors[(index + 1) % 7 + 1], position - index)
	end

	local function track(text)
		if text:IsA("TextLabel") or text:IsA("TextButton") or text:IsA("TextBox") then
			texts[text] = {
				color = text.TextColor3, stroke = text.TextStrokeColor3, transparency = text.TextStrokeTransparency,
			}
		end
	end
	local function visible(text)
		local ancestor = text
		while ancestor and ancestor ~= gui do
			if ancestor:IsA("GuiObject") and not ancestor.Visible then return false end
			ancestor = ancestor.Parent
		end
		return ancestor == gui
	end

	VisualEffects.changed = function(running)
		if beat then beat:Disconnect(); beat = nil end
		if addConnection then addConnection:Disconnect(); addConnection = nil end
		if removeConnection then removeConnection:Disconnect(); removeConnection = nil end
		if not running then
			for text, original in pairs(texts) do
				if text.Parent then
					text.TextColor3 = original.color
					text.TextStrokeColor3 = original.stroke
					text.TextStrokeTransparency = original.transparency
				end
			end
			table.clear(texts)
			for _, repaint in ipairs(themeFns) do repaint() end
			return
		end
		for _, descendant in ipairs(gui:GetDescendants()) do track(descendant) end
		addConnection = gui.DescendantAdded:Connect(track)
		removeConnection = gui.DescendantRemoving:Connect(function(text) texts[text] = nil end)

		local elapsed = 0
		beat = RunService.Heartbeat:Connect(function(delta)
			elapsed += delta
			if elapsed + 0.000001 < 0.1 then return end
			elapsed = math.max(0, elapsed - 0.1) % 0.1
			local phase = os.clock() * 0.15
			local viewport = gui.AbsoluteSize
			local width, height = math.max(viewport.X, 1), math.max(viewport.Y, 1)
			for text, original in pairs(texts) do
				if visible(text) then
					if not original.decorated then
						text.TextStrokeColor3 = Color3.new(0, 0, 0)
						text.TextStrokeTransparency = 0.55
						original.decorated = true
					end
					local position = text.AbsolutePosition
					text.TextColor3 = colorAt(phase - (position.X / width) * 0.3 - (position.Y / height) * 0.4)
				end
			end
		end)
	end
end
