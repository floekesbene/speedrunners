--[[
	SkywayRuins  (ModuleScript)
	Pfad: ServerStorage/MapTemplates/SkywayRuins

	Schwebende Ruinen über den Wolken. Viele Greifhaken-Passagen, Abgründe
	ins Nichts und eine lange Schwung-Route als Abkürzung.
]]

return function(B)
	B:Start(60)
	B:Flat(40)
	B:GrappleGap(B:D(50), { AnchorHeight = 22 })
	B:Gap(B:D(14), 4, 24)
	B:Gap(B:D(14), 4, 24)
	B:PickupRow(3)
	B:GrappleGap(B:D(80), { Anchors = 2, AnchorHeight = 26 })
	B:Drop(16, 30)
	B:SlideTunnel(26)
	B:Flat(20)
	B:TimedBarrier(34, { Period = 2.6, OnTime = 1.0 })
	B:Split({
		Length = 300,
		Depth = 30,
		Upper = function(b)
			b:Flat(8)
			b:GrappleGap(60, { Landing = 16 })
			b:GrappleGap(60, { Landing = 16 })
			b:GrappleGap(70, { Anchors = 2, Landing = 30 })
		end,
		Lower = function(b)
			b:Flat(30)
			b:Gap(14, 0, 20)
			b:Steps(3, 3, 10)
			b:Gap(14, -9, 30)
			b:SlideTunnel(24)
			b:Pit(30, { Pillars = 1, Landing = 30 })
		end,
	})
	B:BoostStrip(60, 85)
	B:WallClimb(18, 14)
	B:PickupRow(2)
	B:GrappleGap(B:D(66), { Anchors = 2, AnchorHeight = 20, Rise = 4 })
	B:Gap(B:D(18), -6, 30)
	B:Ramp(40, 12)
	B:GrappleGap(B:D(56), { AnchorHeight = 24 })
	B:TimedBarrier(34, { Period = 2.2, OnTime = 0.9, Offset = 0.9 })
	B:Steps(4, -4, 10)
	B:Flat(30)
	B:Finish(80)
	-- Optik (rein dekorativ): Säulentore und ein riesiger Ruinenbogen auf einer Insel
	B:Gates(2, B.Theme.Accent, { FrameColor = Color3.fromRGB(236, 230, 216), Material = Enum.Material.Marble })
	B:Decorate()
	local islandX = (B.MinX + B.MaxX) * 0.45
	local top = B:Island(islandX, 30, -150, 40)
	B:Prop("RuinArch", islandX, top - 0.5, -150, { Scale = 2.2 })
end
