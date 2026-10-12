--[[
	NeonMetropolis  (ModuleScript)
	Pfad: ServerStorage/MapTemplates/NeonMetropolis

	Futuristische Stadt bei Nacht. Laserbarrieren, Greifhaken-Lücken zwischen
	Hochhäusern und eine geteilte Route (Dächer oben, Wartungstunnel unten).
]]

return function(B)
	B:Start(60)
	B:Flat(50)
	B:Gap(B:D(12), 0, 36)
	B:Steps(3, 4, 12)
	B:PickupRow(3)
	B:Flat(30)
	B:SlideTunnel(32)
	B:Flat(24)
	B:GrappleGap(B:D(54), { AnchorHeight = 24 })
	B:TimedBarrier(40, { Period = 2.4, OnTime = 1.0 })
	B:BoostStrip(70, 85)
	B:Split({
		Length = 280,
		Depth = 28,
		Upper = function(b)
			b:Flat(10)
			b:GrappleGap(56, { Landing = 24 })
			b:Gap(16, 0, 20)
			b:GrappleGap(64, { Anchors = 2, Landing = 30 })
			b:BoostStrip(40, 90)
		end,
		Lower = function(b)
			b:Flat(40)
			b:SlideTunnel(28)
			b:Flat(20)
			b:Pit(36, { Pillars = 2, Landing = 24 })
			b:TimedBarrier(36, { Period = 2.2, OnTime = 0.9, Offset = 0.7 })
			b:Flat(40)
		end,
	})
	B:PickupRow(3)
	B:WallClimb(20, 14)
	B:Flat(40)
	B:Gap(B:D(16), -4, 30)
	B:GrappleGap(B:D(72), { Anchors = 2, AnchorHeight = 26 })
	B:Ramp(40, 10)
	B:Flat(24)
	B:Drop(14, 30)
	B:SlideTunnel(26, { Lethal = true })
	B:PickupRow(2)
	B:Gap(B:D(18), 0, 30)
	B:TimedBarrier(36, { Period = 2.0, OnTime = 0.9, Offset = 1.1 })
	B:Steps(4, -3, 10)
	B:BoostStrip(60, 90)
	B:GrappleGap(B:D(60), { AnchorHeight = 22 })
	B:Flat(30)
	B:Finish(80)
	B:Decorate()
end
