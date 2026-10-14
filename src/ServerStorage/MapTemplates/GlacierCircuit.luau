--[[
	GlacierCircuit  (ModuleScript)
	Pfad: ServerStorage/MapTemplates/GlacierCircuit

	Eisige Strecke: Rutschige Eisflächen erhalten Momentum, verlangen aber
	frühes Abbremsen. Eiszapfen-Tunnel sind tödlich, wenn man nicht rutscht.
]]

return function(B)
	B:Start(60)
	B:IceRun(70)
	B:Gap(B:D(14), 0, 30)
	B:IceRun(50)
	B:SlideTunnel(30, { Lethal = true })
	B:PickupRow(3)
	B:Steps(3, 4, 14)
	B:IceRun(60)
	B:GrappleGap(B:D(54), { AnchorHeight = 24 })
	B:Ramp(40, -10)
	B:IceRun(80)
	B:Pit(B:D(36), { Pillars = 2, Landing = 30 })
	B:TimedBarrier(36, { Period = 2.4, OnTime = 1.0 })
	B:Split({
		Length = 260,
		Depth = 28,
		Upper = function(b)
			b:Flat(8)
			b:GrappleGap(58, { Landing = 20 })
			b:IceRun(40)
			b:GrappleGap(62, { Anchors = 2, Landing = 30 })
		end,
		Lower = function(b)
			b:IceRun(50)
			b:SlideTunnel(26, { Lethal = true })
			b:IceRun(30)
			b:Pit(30, { Pillars = 1, Landing = 30 })
			b:Flat(30)
		end,
	})
	B:PickupRow(3)
	B:JumpPadUp(16, 30)
	B:IceRun(50)
	B:GrappleGap(B:D(70), { Anchors = 2, AnchorHeight = 26 })
	B:Drop(12, 30)
	B:BoostStrip(50, 85)
	B:IceRun(60)
	B:Gap(B:D(18), 0, 30)
	B:WallClimb(18, 14)
	B:Flat(30)
	B:Finish(80)
	-- Optik (rein dekorativ): Eistore
	B:Gates(3, B.Theme.Accent, { FrameColor = Color3.fromRGB(196, 228, 250), Material = Enum.Material.Ice })
	B:Decorate()
end
