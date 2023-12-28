
local MAP = workspace.map
local BOARDS = MAP.Boards

local function calculateSum(list)
	local sum = 0

	for _, value in ipairs(list) do
		sum = sum + value
	end

	return sum
end

local function matrix()

	local m = {}

	for x = 1, 10 do
		m[x] = {}
		for y = 1, 10 do
			m[x][y] = 0
		end
	end

	return m
end


local function extractNumericPart(part)
	return tonumber(string.match(part.Name, "%d+")) or 0
end

local function comparePartsByName(part1, part2)
	return extractNumericPart(part1) < extractNumericPart(part2)
end

local function createTable(board)
	local m = {}
	local index = 1
	
	local boardChildren = board:GetChildren()
	table.sort(boardChildren, comparePartsByName)
	
	for x = 1, 10 do
		m[x] = {}
		for y = 1, 10 do
			boardChildren[index]:SetAttribute('Index', Vector2.new(x, y))
			boardChildren[index]:SetAttribute('IsContained', false)
			m[x][y] = boardChildren[index]
			index += 1
		end
	end
	
	return m
end


local SeaBattle = {}
SeaBattle.__index = SeaBattle

function SeaBattle.NewGame(boards)
	local self = setmetatable({}, SeaBattle)

	self.BoardsTemplate = boards
	self.Boards = self.BoardsTemplate
	self.Bindable = Instance.new('BindableEvent')
	
	self.ConnectedEvents = {}
	
	self.CurrentPlayerIndex = 1

	self:Init()

	return self
end

function SeaBattle:StartBattle()
	print('Start Battle')

	self.Boards[1].remote:FireClient(self.Boards[1].owner, 'Start')
	
	self.Boards[2].remote:FireClient(self.Boards[2].owner, 'Start')
	
	self:ChoosePlayerWhoMoves()
end

function SeaBattle:GameOver(winner)
	self.Boards[1].remote:FireClient(self.Boards[1].owner, 'Over')
	self.Boards[2].remote:FireClient(self.Boards[2].owner, 'Over')
	
	for _, connect in pairs(self.ConnectedEvents) do if connect and connect.Connected then connect:Disconnect() end end
	
	self:Init()
end

function SeaBattle:ChoosePlayerWhoMoves()
	print(self.CurrentPlayerIndex)
	print((self.CurrentPlayerIndex % #self.Boards) + 1)
	self.Boards[self.CurrentPlayerIndex].remote:FireClient(self.Boards[self.CurrentPlayerIndex].owner, 'Attack')
	self.Boards[(self.CurrentPlayerIndex % #self.Boards) + 1].remote:FireClient(self.Boards[(self.CurrentPlayerIndex % #self.Boards) + 1].owner, 'Defence')
	self.CurrentPlayerIndex = (self.CurrentPlayerIndex % #self.Boards) + 1
end

function SeaBattle:Prepare()

	local boards = {
		{owner = nil, mainBoard = nil, mainBoardMatrix = matrix(), fireBoard = nil, fireBoardMatrix = matrix(), shipsQuantity = {4, 3, 2, 1}, remote = nil, infoPanel = nil, prompt = nil, defenceCameraCFrame = nil, attackingCameraCFrame = nil, damage = 0},
		{owner = nil, mainBoard = nil, mainBoardMatrix = matrix(), fireBoard = nil, fireBoardMatrix = matrix(), shipsQuantity = {4, 3, 2, 1}, remote = nil, infoPanel = nil, prompt = nil, defenceCameraCFrame = nil, attackingCameraCFrame = nil, damage = 0}
	}
	
	local sortedBoards = self.Boards.PlayersBoard:GetChildren()
	
	table.sort(sortedBoards, function(a: Model,b: Model)
		return tonumber(a.Name:match('%d')) < tonumber(b.Name:match('%d')) 
	end)
	
	for i, board in pairs(sortedBoards) do
		boards[i].mainBoard = createTable(board.MainBoard)
		boards[i].fireBoard = createTable(board.FireBoard)
		boards[i].infoPanel = board.InfoPanel
		boards[i].prompt = board.Prompt.ProximityPrompt
		boards[i].defenceCameraCFrame = board.MainBoard:GetPivot() * CFrame.new(0,10,0) * CFrame.Angles(math.rad(-90), 0, 0)
		boards[i].attackingCameraCFrame = CFrame.new(board.MainBoard:GetPivot().Position.X, 6, board.MainBoard:GetPivot().Position.Z) * CFrame.Angles(0,math.rad(i == 1 and 180 or 0),0) -- + (i == 1 and -6 or 6)
	end

	self.Boards = boards
	
end


function SeaBattle:Setup()
	for i, board in pairs(self.Boards) do
		board.prompt.Triggered:Connect(function(player)
			board.prompt.Enabled = false
			local clientScript = script.Client:Clone()
			clientScript.Parent = player.Character
			clientScript.Enabled = true

			board.remote = clientScript.RemoteEvent
			board.owner = player

			board.remote:FireClient(player, 'Setup', board)
			self.Bindable:Fire('CheckPlayers')
		end)
	end
end

function SeaBattle:Init()
	self:Prepare()
	self:Setup()
	self:Events()
end

function SeaBattle:Subs()
	for index, board in pairs(self.Boards) do
		if board.remote then 
			self.ConnectedEvents[index] = board.remote.OnServerEvent:Connect(function(player, action, ...)
				print(action)
				if action == 'Check' then
					--print('check server', player)
					local cells = ...
					local canSetup = board.shipsQuantity[#cells] > 0

					for _, cellIndex in pairs(cells) do
						if board.mainBoard[cellIndex.X][cellIndex.Y]:GetAttribute('IsContained') then canSetup = false break end
					end

					if canSetup then
						for _, cellIndex in pairs(cells) do
							board.mainBoard[cellIndex.X][cellIndex.Y]:SetAttribute('IsContained', true)
							for _, nei in pairs(
								{
									{cellIndex.X - 1, cellIndex.Y}, 
									{cellIndex.X + 1, cellIndex.Y}, 
									{cellIndex.X, cellIndex.Y + 1}, 
									{cellIndex.X, cellIndex.Y - 1},
									{cellIndex.X - 1, cellIndex.Y - 1},
									{cellIndex.X - 1, cellIndex.Y + 1},
									{cellIndex.X + 1, cellIndex.Y + 1},
									{cellIndex.X - 1, cellIndex.Y + 1},
								}
								) do
								if nei[1] <= 0 or nei[2] <= 0 or nei[1] > 10 or nei[2] > 10 then continue end
								if board.mainBoard[nei[1]][nei[2]] ~= nil then board.mainBoard[nei[1]][nei[2]]:SetAttribute('IsContained', true) end
							end
						end
						board.shipsQuantity[#cells] -= 1						
					end
					board.remote:FireClient(player, 'SetupShip', canSetup)
					if calculateSum(board.shipsQuantity) == 0 then
						self.Bindable:Fire('ArePlayersReady')
						board.remote:FireClient(player, 'Wait') -- from here i think come wait command two times
					end
				elseif action == 'UpdateMainBoard' then
					for _, matrixIndex in pairs(...) do
						board.mainBoardMatrix[matrixIndex.X][matrixIndex.Y] = 1
					end 
					
				elseif action == 'Attack' then
					local attackedCellIndex = ...
					local attackedCell = self.Boards[(index % #self.Boards) + 1].mainBoardMatrix[attackedCellIndex.X][attackedCellIndex.Y]

					if attackedCell ~= 0 and attackedCell ~= -1 then
						self.Boards[(index % #self.Boards) + 1].remote:FireClient(self.Boards[(index % #self.Boards) + 1].owner, 'UpdateMainBoard', attackedCellIndex)
						self.Boards[(index % #self.Boards) + 1].mainBoardMatrix[attackedCellIndex.X][attackedCellIndex.Y] = -1
						board.damage += 1
						board.remote:FireClient(board.owner, 'ShootResult', true)
						self.Bindable:Fire('CheckOver', board)
					else
						board.remote:FireClient(board.owner, 'ShootResult', false)
						self:ChoosePlayerWhoMoves()
					end
				end

			end)
		end
	end
end

function SeaBattle:Events()
	self.ConnectedEvents['bind'] = self.Bindable.Event:Connect(function(action, ...)
		if action == 'CheckPlayers' then
			if self.Boards[1].owner and self.Boards[2].owner then
				for i, board in pairs(self.Boards) do
					board.remote:FireClient(board.owner, 'Prepare')
				end
				self:Subs()
			end 
		elseif action == 'ArePlayersReady' then
			if calculateSum(self.Boards[1].shipsQuantity) + calculateSum(self.Boards[2].shipsQuantity) == 0 then
				self:StartBattle()
			end
		elseif action == 'CheckOver' then
			local boardOfAttackingPlayer = ...
			if boardOfAttackingPlayer.damage == 20 then self:GameOver(boardOfAttackingPlayer) end 
		end
	end)
end 

for _, board in pairs(BOARDS:GetChildren()) do
	SeaBattle.NewGame(board)
end

