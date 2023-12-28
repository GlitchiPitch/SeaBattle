local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")


script:WaitForChild('RemoteEvent')

local Player = {}
Player.__index = Player

function Player.New()
	local self = setmetatable({}, Player)

	self.Player = game.Players.LocalPlayer
	self.Camera = workspace.CurrentCamera

	self.Mouse = self.Player:GetMouse()

	self.Board = nil

	self.UserInputConnect = nil
	self.RunServiceConnect = nil
	
	self.SubscribedEvents = {}
	
	self.ShipsFolder = Instance.new('Folder', workspace)

	self:Init()

	return self
end

function Player:Setup()
	self.Camera.CameraType = Enum.CameraType.Scriptable
	self.Camera.FieldOfView = 100
	self.Camera.CFrame = self.Board.defenceCameraCFrame
end

function Player:Wait()
	if self.UserInputConnect and self.UserInputConnect.Connected then self.UserInputConnect:Disconnect() end
end

function Player:Prepare()
	local pickedShip, angleOfShip = nil, CFrame.Angles(0,0,0)

	self.UserInputConnect = UserInputService.InputBegan:Connect(function(input, gameProcessedEvent)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			if not pickedShip then
				if CollectionService:HasTag(self.Mouse.Target.Parent, 'Ship') then
					pickedShip = self.Mouse.Target:FindFirstAncestorOfClass('Model'):Clone()
					pickedShip.Parent = self.ShipsFolder
					pickedShip.PrimaryPart = self.Mouse.Target
					self.Mouse.TargetFilter = pickedShip
					CollectionService:RemoveTag(pickedShip, 'Ship')
				end
			else
				local cellsIndex = {}
				for _, shipPart in pairs(pickedShip:GetChildren()) do

					local pos = shipPart.Position

					for _, cellPartList in pairs(self.Board.mainBoard) do
						for _, cellPart in pairs(cellPartList) do
							local cellSide = {
								{cellPart.Position.X - cellPart.Size.X / 2, cellPart.Position.X + cellPart.Size.X / 2},
								{cellPart.Position.Z - cellPart.Size.Z / 2, cellPart.Position.Z + cellPart.Size.Z / 2}
							}
							if (cellSide[1][1] < pos.X and pos.X < cellSide[1][2]) and (cellSide[2][1] < pos.Z and pos.Z < cellSide[2][2]) then
								table.insert(cellsIndex, cellPart:GetAttribute('Index'))
							end
						end
					end
				end
				
				if #cellsIndex == 0 then 
					pickedShip:Destroy()
					pickedShip, angleOfShip = nil, CFrame.Angles(0,0,0)
					return
				end
				
				local remote
				remote = script.RemoteEvent.OnClientEvent:Connect(function(action, ...)
					if action == 'SetupShip' then
						if not ... then
							pickedShip:Destroy()
							pickedShip, angleOfShip = nil, CFrame.Angles(0,0,0)
						else
							local occupiedCells = {}
							for i, shipPart in pairs(pickedShip:GetChildren()) do
								shipPart.Position = self.Board.mainBoard[cellsIndex[i].X][cellsIndex[i].Y].Position + Vector3.new(0, 1, 0)
								self.Board.mainBoardMatrix[cellsIndex[i].X][cellsIndex[i].Y] = shipPart
								table.insert(occupiedCells, cellsIndex[i])
							end
							script.RemoteEvent:FireServer('UpdateMainBoard', occupiedCells)
							pickedShip, angleOfShip = nil, CFrame.Angles(0,0,0)
						end
					end
					remote:Disconnect()
				end)
				script.RemoteEvent:FireServer('Check', cellsIndex)
			end
		elseif input.KeyCode == Enum.KeyCode.R and pickedShip then
			angleOfShip *= CFrame.Angles(0, math.rad(90), 0)
		end
	end)

	self.RunServiceConnect = RunService.Stepped:Connect(function(time, deltaTime)
		if pickedShip then 
			pickedShip:PivotTo(CFrame.new(self.Mouse.Hit.X,self.Board.mainBoard[1][1].Position.Y+1,self.Mouse.Hit.Z) * angleOfShip)
		end
	end)

end

function Player:moveCameraToPart(cframe)
	local tween = TweenService:Create(self.Camera, TweenInfo.new(3), {CFrame = cframe})
	tween:Play()
	tween.Completed:Wait()
end

function Player:Attack()
	self.UserInputConnect = UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessedEvent: boolean) 
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			local cellIndex = self.Mouse.Target:GetAttribute('Index')
			if cellIndex and self.Mouse.Target.Parent.Name == 'FireBoard' and self.Board.fireBoardMatrix[cellIndex.X][cellIndex.Y] == 0 then
				script.RemoteEvent:FireServer('Attack', cellIndex)
				self.Mouse.Target.Color = Color3.new(1,0,0)
				self.Board.fireBoardMatrix[cellIndex.X][cellIndex.Y] = -1
				local getResult
				local shootResult
				getResult = script.RemoteEvent.OnClientEvent:Connect(function(action, ...)
					if action == 'ShootResult' then
						if not ... then self.UserInputConnect:Disconnect() end
						if getResult and getResult.Connected then getResult:Disconnect() end
					end
				end)
			end
		end
	end)
end

function Player:Defence()
	if self.UserInputConnect and self.UserInputConnect.Connected then self.UserInputConnect:Disconnect() end
end

function Player:Start()
	self.UserInputConnect:Disconnect()
	self.RunServiceConnect:Disconnect()
	self:BattleSubs()
end

function Player:Over() -- put all connections in subs evenets list, i did it but it did not work idk why 
	for _, subs in pairs(self.SubscribedEvents) do subs:Disconnect() end
	self.UserInputConnect:Disconnect()
	self.RunServiceConnect:Disconnect()
	
	self.Camera.CameraType = Enum.CameraType.Custom
	self.Camera.FieldOfView = 80
	self.Camera.CameraSubject = self.Player.Character.Humanoid
	
	self.ShipsFolder:Destroy()
	
	for i, column in pairs(self.Board.fireBoard) do
		print(column)
		for j, cell in pairs(column) do
			print(cell)
			local color
			if i%2 == 0 then
				if j%2 == 0 then
					color = Color3.new(1,1,1)	
				else
					color = Color3.new(0,0,0)
				end
			else
				if  j%2 == 1 then
					color = Color3.new(1,1,1)	
				else
					color = Color3.new(0,0,0)
				end
			end
			cell.Color = color
		end
	end
	
	script:Destroy()
	
	
end

function Player:BattleSubs()
	self.SubscribedEvents[1] = script.RemoteEvent.OnClientEvent:Connect(function(action, ...)
		if action == 'Attack' then
			print('Attack')
			self:moveCameraToPart(self.Board.attackingCameraCFrame)
			self:Attack()
		elseif action == 'Defence' then
			print('Defence')
			self:moveCameraToPart(self.Board.defenceCameraCFrame)
			
		elseif action == 'UpdateMainBoard' then
			print('UpdateMainBoard')
			local attackedCellIndex = ... 
			self.Board.mainBoardMatrix[attackedCellIndex.X][attackedCellIndex.Y].Color = Color3.new(1,1,0)
		end
		
	end)
end

function Player:Subs()
	self.SubscribedEvents[2] = script.RemoteEvent.OnClientEvent:Connect(function(action, ...)
		if action == 'Setup' then
			print('Setup')
			self.Board = ...
			self:Setup()
		elseif action == 'Wait' then
			print('Wait')
			self:Wait()
		elseif action == 'Prepare' then
			print('Prepare')
			self:Prepare()
		elseif action == 'Start' then
			print('Start')
			self:Start()
		elseif action == 'Over' then
			print('Over')
			self:Over()
		end
	end)
end

function Player:Init()
	self:Subs()
end

Player.New()