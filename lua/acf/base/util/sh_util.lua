do -- Ricochet/Penetration materials
	local Materials = {}
	local MatCache = {}
	local Lookup = {}
	local Count = 0

	local function GetMaterial(Path)
		if not Path then return end
		if MatCache[Path] then return MatCache[Path] end

		local Object = Material(Path)

		MatCache[Path] = Object

		return Object
	end

	local function DefaultScale(Caliber)
		return Caliber * 0.1312 -- Default AP decal makes a 76.2mm hole, dividing by 7.62cm
	end

	function ACF.RegisterAmmoDecal(Type, PenPath, RicoPath, ScaleFunc)
		if not Type then return end

		if not Lookup[Type] then
			Count = Count + 1

			Materials[Count] = {
				Penetration = GetMaterial(PenPath),
				Ricochet = GetMaterial(RicoPath),
				Scale = ScaleFunc or DefaultScale,
				Index = Count,
				Type = Type,
			}

			Lookup[Type] = Materials[Count]
		else
			local Data = Lookup[Type]
			Data.Penetration = GetMaterial(PenPath)
			Data.Ricochet = GetMaterial(RicoPath)
			Data.Scale = ScaleFunc or DefaultScale
		end
	end

	function ACF.IsValidAmmoDecal(Key)
		if not Key then return false end
		if Lookup[Key] then return true end
		if Materials[Key] then return true end

		return false
	end

	function ACF.GetAmmoDecalIndex(Type)
		if not Type then return end
		if not Lookup[Type] then return end

		return Lookup[Type].Index
	end

	function ACF.GetAmmoDecalType(Index)
		if not Index then return end
		if not Materials[Index] then return end

		return Materials[Index].Type
	end

	function ACF.GetPenetrationDecal(Key)
		if not Key then return end

		if Lookup[Key] then
			return Lookup[Key].Penetration
		end

		if Materials[Key] then
			return Materials[Key].Penetration
		end
	end

	function ACF.GetRicochetDecal(Key)
		if not Key then return end

		if Lookup[Key] then
			return Lookup[Key].Ricochet
		end

		if Materials[Key] then
			return Materials[Key].Ricochet
		end
	end

	function ACF.GetDecalScale(Key, Caliber)
		if not Key then return end

		if Lookup[Key] then
			return Lookup[Key].Scale(Caliber)
		end

		if Materials[Key] then
			return Materials[Key].Scale(Caliber)
		end
	end
end

do -- Time lapse function
	local Units = {
		{ Unit = "year", Reduction = 1970 },
		{ Unit = "month", Reduction = 1 },
		{ Unit = "day", Reduction = 1 },
		{ Unit = "hour", Reduction = 0 },
		{ Unit = "min", Reduction = 0 },
		{ Unit = "sec", Reduction = 0 },
	}

	local function LocalToUTC()
		return os.time(os.date("!*t", os.time()))
	end

	function ACF.GetTimeLapse(Date)
		if not Date then return end

		local Time = LocalToUTC() - Date
		local DateData = os.date("!*t", Time)

		-- Negative values to os.date will return nil
		-- LocalToUTC() is most likely flawed, will need testing with people from different timezones.
		if Time <= 0 then return "now" end

		for _, Data in ipairs(Units) do
			Time = DateData[Data.Unit] - Data.Reduction

			if Time > 0 then
				return Time .. " " .. Data.Unit .. (Time ~= 1 and "s" or "") .. " ago"
			end
		end
	end
end

do -- Sound aliases
	local Stored = {}
	local Lookup = {}
	local Path = "sound/%s"

	local function CreateData(Name)
		if not Lookup[Name] then
			Lookup[Name] = {
				Name = Name,
				Children = {}
			}
		else
			Stored[Name] = nil
		end

		return Lookup[Name]
	end

	local function RegisterAlias(Old, New)
		if not isstring(Old) then return end
		if not isstring(New) then return end

		Old = Old:lower()
		New = New:lower()

		local OldData = CreateData(Old)
		local NewData = CreateData(New)

		NewData.Children[OldData] = true
		OldData.Parent = NewData
	end

	local function GetParentSound(Name, List, Total)
		for I = Total, 1, -1 do
			local Sound = List[I].Name

			if file.Exists(Path:format(Sound), "GAME") then
				Stored[Name] = Sound

				return Sound
			end
		end
	end

	-- Note: This isn't syncronized between server and client.
	-- If a sound happens to have multiple children, the result will differ between client and server.
	local function GetChildSound(Name)
		local Data = Lookup[Name]
		local Next = Data.Children
		local Checked = { [Data] = true }

		repeat
			local New = {}

			for Child in pairs(Next) do
				if Checked[Child] then continue end

				local Sound = Child.Name

				if file.Exists(Path:format(Sound), "GAME") then
					Stored[Name] = Sound

					return Sound
				end

				for K in pairs(Child.Children) do
					New[K] = true
				end

				Checked[Child] = true
			end

			Next = New

		until not next(Next)
	end

	local function GetAlias(Name)
		if not isstring(Name) then return end

		Name = Name:lower()

		if not Lookup[Name] then return Name end
		if Stored[Name] then return Stored[Name] end

		local Checked, List = {}, {}
		local Next = Lookup[Name]
		local Count = 0

		repeat
			if Checked[Next] then break end

			Count = Count + 1

			Checked[Next] = true
			List[Count] = Next

			Next = Next.Parent
		until not Next

		local Parent = GetParentSound(Name, List, Count)
		if Parent then return Parent end

		local Children = GetChildSound(Name)
		if Children then return Children end

		Stored[Name] = Name

		return Name
	end

	function ACF.RegisterSoundAliases(Table)
		if not istable(Table) then return end

		for K, V in pairs(Table) do
			RegisterAlias(K, V)
		end
	end

	ACF.GetSoundAlias = GetAlias

	-- sound.Play hijacking
	sound.DefaultPlay = sound.DefaultPlay or sound.Play

	function sound.Play(Name, ...)
		Name = GetAlias(Name)

		return sound.DefaultPlay(Name, ...)
	end

	-- ENT:EmitSound hijacking
	local ENT = FindMetaTable("Entity")

	ENT.DefaultEmitSound = ENT.DefaultEmitSound or ENT.EmitSound

	function ENT:EmitSound(Name, ...)
		Name = GetAlias(Name)

		return self:DefaultEmitSound(Name, ...)
	end

	-- CreateSound hijacking
	DefaultCreateSound = DefaultCreateSound or CreateSound

	function CreateSound(Entity, Name, ...)
		Name = GetAlias(Name)

		return DefaultCreateSound(Entity, Name, ...)
	end

	-- Valid sound check
	if CLIENT then
		local SoundCache = {}

		function ACF.IsValidSound(Name)
			Name = GetAlias(Name)

			if SoundCache[Name] == nil then
				SoundCache[Name] = file.Exists(Path:format(Name), "GAME")
			end

			return SoundCache[Name]
		end
	end
end
