--[[
	JungleVelocity  (ModuleScript)
	Pfad: ServerStorage/MapTemplates/JungleVelocity

	Dschungel mit zwei geteilten Abschnitten: Baumkronen-Route (oben, schnell)
	und Waldboden (unten, sicher). Einsteigerfreundlich (Schwierigkeit 1).
]]

return function(B)
	B:Start(60)
	B:Flat(50)
	B:Gap(B:D(12), 0, 30)
	B:Steps(2, 5, 14)
	B:PickupRow(3)
	B:Split({
		Length = 300,
		Depth = 30,
		Upper = function(b)
			b:Flat(10)
			b:GrappleGap(50, { Landing = 20 })
			b:Gap(14, 3, 20)
			b:GrappleGap(56, { Landing = 20 })
			b:Gap(14, -3, 20)
			b:BoostStrip(40, 85)
		end,
		Lower = function(b)
			b:Flat(30)
			b:Pit(30, { Pillars = 1, Landing = 20 })
			b:SlideTunnel(28)
			b:Flat(20)
			b:Steps(2, 4, 12)
			b:Gap(14, -8, 30)
			b:Flat(30)
		end,
	})
	B:TimedBarrier(36, { Period = 2.6, OnTime = 1.1 })
	B:GrappleGap(B:D(54), { AnchorHeight = 24 })
	B:Ramp(36, 8)
	B:PickupRow(2)
	B:Pit(B:D(40), { Pillars = 2, Landing = 30 })
	B:WallClimb(18, 14)
	B:Flat(30)
	B:Drop(18, 30)
	B:Split({
		Length = 240,
		Depth = 26,
		Upper = function(b)
			b:Flat(8)
			b:GrappleGap(60, { Anchors = 2, Landing = 20 })
			b:SlideTunnel(20)
			b:GrappleGap(50, { Landing = 30 })
		end,
		Lower = function(b)
			b:Flat(30)
			b:TimedBarrier(30, { Period = 2.2, OnTime = 0.9 })
			b:Pit(32, { Pillars = 2, Landing = 20 })
			b:Flat(40)
		end,
	})
	B:BoostStrip(60, 90)
	B:Gap(B:D(16), 0, 30)
	B:GrappleGap(B:D(64), { Anchors = 2, AnchorHeight = 24 })
	B:Flat(30)
	B:Finish(80)
	B:Decorate()
end
