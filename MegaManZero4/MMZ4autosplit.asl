//Made by Coltaho 9/22/2019

state("EmuHawk"){}

startup {	
	refreshRate = 1;

	settings.Add("options", true, "---Options---");
	settings.Add("missiontimer", false, "Show Mission Timer", "options");
	settings.Add("refightsplit", false, "Split on first door after refights", "options");
	
	settings.Add("infosection", true, "---Info---");
	settings.Add("info", true, "Mega Man Zero 4 AutoSplitter v1.0 by Coltaho", "infosection");
	settings.Add("info0", true, "- Supported emulators : Win7 or Win10 Bizhawk with VBA-Next Core", "infosection");
	settings.Add("info1", true, "- Website : https://github.com/Coltaho/Autosplitters", "infosection");
	
	vars.findpointers = (Action<Process, int>)((proc, mymodulesize) => {
		print("--Scanning for pointers!--");
		
		vars.baseptr = IntPtr.Zero;
		vars.ewram = IntPtr.Zero;
		vars.scantest = new SigScanTarget[4];
		
		vars.scantest[0] = new SigScanTarget(38, "448B41104489442438488BCA488D5424404C8D442428E8");
		vars.scantest[1] = new SigScanTarget(5, "83EC2048B9????????????????488B0949BB????????????????390941FF13488BF0488BCEE8");
		vars.scantest[2] = new SigScanTarget(9, "488B00E9????????BA????????488B1248B9????????????????E8????????488BC849BB");
		vars.scantest[3] = new SigScanTarget(4, "488BF8BA????????488B124885D20F84");
		vars.ptr = IntPtr.Zero;

		for (int i = 0; i < 4; i++) {
			print("--Searching for Window OS Signatures index: " + i);
			foreach (var page in proc.MemoryPages()) {
				var scanner = new SignatureScanner(proc, page.BaseAddress, (int)page.RegionSize);		
				if(vars.ptr == IntPtr.Zero && ((vars.ptr = scanner.Scan(vars.scantest[i])) != IntPtr.Zero)) {
					print("--Ptr Found : " + (vars.ptr).ToString("X"));
					break;
				}
			}
			if (vars.ptr != IntPtr.Zero) {
				break;
			}
		}
		
		if (vars.ptr == IntPtr.Zero)
			throw new Exception("--Couldn't find a pointer I want! GBA Core probably not loaded!");
		
		List<int> offsets = new List<int> { 0x0, 0x70, 0x8, 0x8, 0x18, 0x28 };
		
		vars.ewram = proc.ReadValue<ulong>((IntPtr)vars.ptr);
		vars.baseptr = vars.ewram;
		print("--Base Ptr: " + (vars.ewram).ToString("X"));
		
		foreach	(int offset in offsets) {
			vars.ewram = proc.ReadValue<ulong>((IntPtr)vars.ewram + offset);
			print("--Offset " + offset.ToString("X") + " value: " + vars.ewram.ToString("X"));
		}
	});
	
	vars.GetWatcherList = (Func<IntPtr, IntPtr, MemoryWatcherList>)((baseptr, ewram) =>
	{
		return new MemoryWatcherList
		{
			new MemoryWatcher<ulong>((IntPtr)baseptr) { Name = "baseptr" },
			new MemoryWatcher<byte>((IntPtr)ewram + 0x366A4) { Name = "myhp" },
			new MemoryWatcher<byte>((IntPtr)ewram + 0x2F3B7) { Name = "menuscreen" }, // = 4 when on difficulty select screen
			new MemoryWatcher<ushort>((IntPtr)ewram + 0x2F606) { Name = "start" }, //main menu fade? goes to 31 as screen fades
			new MemoryWatcher<ushort>((IntPtr)ewram + 0x2F3B4) { Name = "gamestate" }, //261 when playing, 516 on main menu, resets to 1 during restart
			new MemoryWatcher<ushort>((IntPtr)ewram + 0x3A4E4) { Name = "bosshp" },
			new MemoryWatcher<ushort>((IntPtr)ewram + 0x3A4D8) { Name = "bossid" }, //prolly not actual boss id but 46129 only at last weil form
			new MemoryWatcher<byte>((IntPtr)ewram + 0x2E912) { Name = "checkpoint" }, //5 after refights
			new MemoryWatcher<byte>((IntPtr)ewram + 0x2E910) { Name = "stage" }, //16 for last stage
			new MemoryWatcher<ushort>((IntPtr)ewram + 0x3591C) { Name = "scorescreen" }, // changed
			new MemoryWatcher<uint>((IntPtr)ewram + 0x2E8E8) { Name = "missiontimer" }
		};
	});
	
	vars.UpdateRoomTimer = (Action<Process>)((proc) => {
        if(vars.textSettingMissionTimer == null) {
            foreach (dynamic component in timer.Layout.Components) {
                if (component.GetType().Name != "TextComponent") continue;
                if (component.Settings.Text1 == "Mission Timer") vars.textSettingMissionTimer = component.Settings;
            }

            if(vars.textSettingMissionTimer == null)
                vars.textSettingMissionTimer = vars.CreateTextComponent("Mission Timer");
        }
        vars.textSettingMissionTimer.Text2 = vars.FormatTimer(vars.watchers["missiontimer"].Current);       
    });
	
	vars.CreateTextComponent = (Func<string, dynamic>)((name) => {
        var textComponentAssembly = Assembly.LoadFrom("Components\\LiveSplit.Text.dll");
        dynamic textComponent = Activator.CreateInstance(textComponentAssembly.GetType("LiveSplit.UI.Components.TextComponent"), timer);
        timer.Layout.LayoutComponents.Add(new LiveSplit.UI.Components.LayoutComponent("LiveSplit.Text.dll", textComponent as LiveSplit.UI.Components.IComponent));
        textComponent.Settings.Text1 = name;
        return textComponent.Settings;
    });
	
	vars.FormatTimer = (Func<uint, string>)((frames) => {
        return (frames / 60 / 60 % 60).ToString("D2") + "'" + (frames / 60 % 60).ToString("D2");
    });
}

init {
	print("--Setting init variables!--");

	vars.baseptr = IntPtr.Zero;
	vars.ewram = IntPtr.Zero;
	vars.watchers = new MemoryWatcherList();
	vars.textSettingMissionTimer = null;
	
	vars.findpointers(game, modules.First().ModuleMemorySize);
	vars.watchers = vars.GetWatcherList((IntPtr)vars.baseptr, (IntPtr)vars.ewram);
	
	refreshRate = 60;
}

update {
	vars.watchers.UpdateAll(game);
	if(settings["missiontimer"]) vars.UpdateRoomTimer(game);
	if (vars.watchers["baseptr"].Changed || vars.watchers["baseptr"].Current == 0) {
		print("--Base ptr changed to: " + vars.watchers["baseptr"].Current.ToString("X"));
		vars.findpointers(game, modules.First().ModuleMemorySize);
		vars.watchers = vars.GetWatcherList((IntPtr)vars.baseptr, (IntPtr)vars.ewram);
	}
	// print("--Gamestate: " + vars.watchers["gamestate"].Current + " | MenuScreen: " + vars.watchers["menuscreen"].Current + " | MenuFade: " + vars.watchers["start"].Current + " | BossID: " + vars.watchers["bossid"].Current + " | BossHP: " + vars.watchers["bosshp"].Current + " | Scorescreen: " + vars.watchers["scorescreen"].Current + " | HP: " + vars.watchers["myhp"].Current);
}

start { 
	return (vars.watchers["gamestate"].Current == 516 && vars.watchers["menuscreen"].Old == 4 && vars.watchers["start"].Old == 0 && vars.watchers["start"].Current >= 28);
}

reset { 
	return (vars.watchers["gamestate"].Old != 1 && vars.watchers["gamestate"].Current == 1);
}

split {
	return (settings["refightsplit"] && vars.watchers["stage"].Current == 16 && vars.watchers["checkpoint"].Old == 3 && vars.watchers["checkpoint"].Current == 5) || (vars.watchers["scorescreen"].Changed && vars.watchers["scorescreen"].Current != 0) || (vars.watchers["myhp"].Current > 0 && vars.watchers["bossid"].Current == 46129  && vars.watchers["bosshp"].Current == 0 && vars.watchers["bosshp"].Old >= 1);
}
