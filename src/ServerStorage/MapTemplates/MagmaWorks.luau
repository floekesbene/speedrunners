--[[
	MagmaWorks  (ModuleScript)
	Pfad: ServerStorage/MapTemplates/MagmaWorks

	Industrieanlage über einem Lavasee. Viele Lavagruben mit Säulen,
	Flammenwerfer-Barrieren und Sprungpads. Schwierigste Strecke.
]]

return function(B)
	B:Start(60)
	B:Flat(40)
	B:Pit(B:D(30), { Pillars = 1, Landing = 30 })
	B:Steps(3, 5, 12)
	B:TimedBarrier(40, { Period = 2.6, OnTime = 1.2 })
	B:PickupRow(3)
	B:GrappleGap(B:D(50), { AnchorHeight = 24 })
	B:Drop(10, 30)
	B:Pit(B:D(44), { Pillars = 2, PillarRise = 4, Landing = 30 })
	B:JumpPadUp(18, 40)
	B:SlideTunnel(30, { Lethal = true })
	B:Flat(20)
	B:Split({
		Length = 260,
		Depth = 30,
		Upper = function(b)
			b:Flat(8)
			b:GrappleGap(60, { Landing = 20 })
			b:TimedBarrier(30, { Period = 1.8, OnTime = 0.7 })
			b:GrappleGap(54, { Landing = 24 })
			b:BoostStrip(40, 90)
		end,
		Lower = function(b)
			b:Flat(30)
			b:Pit(34, { Pillars = 2, Landing = 20 })
			b:SlideTunnel(26)
			b:Flat(16)
			b:Pit(30, { Pillars = 1, Landing = 30 })
			b:Flat(30)
		end,
	})
	B:PickupRow(3)
	B:WallClimb(22, 14)
	B:TimedBarrier(36, { Period = 2.2, OnTime = 1.0, Offset = 0.5 })
	B:Gap(B:D(16), 0, 24)
	B:Gap(B:D(16), 3, 24)
	B:GrappleGap(B:D(70), { Anchors = 2, AnchorHeight = 26 })
	B:Ramp(30, -8)
	B:BoostStrip(60, 90)
	B:Pit(B:D(40), { Pillars = 2, Landing = 30 })
	B:TimedBarrier(40, { Period = 2.0, OnTime = 0.9, Offset = 1.3 })
	B:Steps(3, -4, 12)
	B:GrappleGap(B:D(58), { AnchorHeight = 24 })
	B:Flat(30)
	B:Finish(80)
	-- Optik (rein dekorativ): Werkstore in Warnfarbe
	B:Gates(3, B.Theme.Accent2, { FrameColor = Color3.fromRGB(70, 56, 50), Material = Enum.Material.CorrodedMetal })
	B:Decorate()
end
