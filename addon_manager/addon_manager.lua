_addon.name = 'addon_manager'
_addon.author = 'Icy'
_addon.version = '1.0.0.1'
_addon.commands = {'addon_manager','addonmanager'}

--[[
	1.0.0.1: adjusted 'load by zone' logic. Fixed debug_mode logic.
]]

require('logger')
require('tables')
file = require('files')
config = require('config')

function get_settings()
	return file.exists('data/settings.xml') and config.load('data/settings.xml') or config.load(defaults)
end

defaults = {
	debug_mode = false,
	load_delay = 5,
	-- none-windower controlled (turned on via launcher) addons you want to load for everyone
	global_addons = S{'equipviewer','equipviewer',}, 
	
	-- none-windower controlled (turned on via launcher) plugins you want to load for everyone
	global_plugins = S{'',}, 
	
	-- character specific addons loaded on login
	player_addons = T{ 
		['charname'] = S{'',}
	},
	
	player_plugins = T{ -- character specific plugins loaded on login
		['charname'] = S{'',}
	},
	
	-- zone specific addons for everyone, unless specified the player is specified in the ignore list.
	--	note: addon's are unloaded when the player leaves the zone.
	by_zone = T{
		dynamis = {
			zone_names = S{'Dynamis - Valkurm','Dynamis - Buburimu','Dynamis - Qufim','Dynamis - Tavnazia','Dynamis - Beaucedine','Dynamis - Xarcabard','Dynamis - San d\'Oria','Dynamis - Bastok','Dynamis - Windurst','Dynamis - Jeuno'},
			addons = S{'dynamishelper'}, 
			plugins = S{''}, 
			ignore = S{''} 
		},
		example_unique_name = { 
			zone_names = S{'Abyssea - Konschtat','Abyssea - Tahrongi','Abyssea - La Theine','Abyssea - Attohwa','Abyssea - Misareaux','Abyssea - Vunkerl','Abyssea - Altepa','Abyssea - Uleguerand','Abyssea - Grauberg'},
			addons = S{'vwhl'}, 
			plugins = S{''}, 
			ignore = S{''} 
		},
	},
	
	-- job specific addons for everyone, unless specified the player is specified in the ignore list.
	by_job = T{ 
		war = { addons = S{'autows',}, plugins = S{'',}, ignore = S{'',} },
		whm = { addons = S{'',}, plugins = S{'',}, ignore = S{'',} },
		rdm = { addons = S{'',}, plugins = S{'',}, ignore = S{'',} },
		pld = { addons = S{'',}, plugins = S{'',}, ignore = S{'',} },
		bst = { addons = S{'pettp',}, plugins = S{'',}, ignore = S{'',} },
		rng = { addons = S{'autows',}, plugins = S{'',}, ignore = S{'',} },
		nin = { addons = S{'',}, plugins = S{'',}, ignore = S{'',} },
		smn = { addons = S{'pettp',}, plugins = S{'',}, ignore = S{'',} },
		cor = { addons = S{'autows',}, plugins = S{'',}, ignore = S{'',} },
		dnc = { addons = S{'',}, plugins = S{'',}, ignore = S{'',} },
		geo = { addons = S{'pettp',}, plugins = S{'',}, ignore = S{'',} },
		mnk = { addons = S{'autows',}, plugins = S{'',}, ignore = S{'',} },
		blm = { addons = S{'',}, plugins = S{'',}, ignore = S{'',} },
		thf = { addons = S{'thtracker',}, plugins = S{'',}, ignore = S{'',} },
		drk = { addons = S{'autows',}, plugins = S{'',}, ignore = S{'',} },
		brd = { addons = S{'',}, plugins = S{'',}, ignore = S{'',} },
		sam = { addons = S{'autows',}, plugins = S{'',}, ignore = S{'',} },
		drg = { addons = S{'pettp',}, plugins = S{'',}, ignore = S{'',} },
		blu = { addons = S{'azureSets',}, plugins = S{'',}, ignore = S{'',} },
		pup = { addons = S{'autocontrol','pettp'}, plugins = S{''}, ignore = S{''} },
		sch = { addons = S{'',}, plugins = S{'',}, ignore = S{'',} },
		run = { addons = S{'',}, plugins = S{'',}, ignore = S{'',} },
	}
}
--settings = file.exists('data/settings.xml') and config.load('data/settings.xml') or config.load(defaults)
settings = get_settings()

local player_name = nil
local delay = tonumber(settings.load_delay) or 3
local autoload = nil
local current_zone = nil
local current_job_id = nil
local addon_command = 'lua load '
local plugin_command = 'load '
local force = false
local jobs = nil
local zones = nil
local last_loaded_addons = S{}

function parse_autoload()
	local list = T{}
	list.addons = S{}
	list.plugins = S{}
	
	-- code borrowed from libs/files.lua, thanks ^^
	local autoload_file = windower.windower_path..'scripts/autoload/autoload.txt'
	if windower.file_exists(autoload_file) then
		local fh = io.open(autoload_file, 'r')
		local content = fh:read('*all*')
		fh:close()

		-- Remove byte order mark for UTF-8, if present
		if content:sub(1, 3) == string.char(0xEF, 0xBB, 0xBF) then
			content = content:sub(4)
		end
		
		for i, line in pairs(content:split('\n')) do
			if not tonumber(line) then
				line = line:gsub(';', ''):lower()
				if line and not line:empty() and not tonumber(line) and not line:contains('//') and not line:contains('luacore') then
					if line:startswith('load') then
						list.plugins:insert(line:gsub('load ', ''):trim())
					elseif line:startswith('lua load') then
						list.addons:insert(line:gsub('lua load ', ''):trim())
					end
				end
			end
		end
	else
		error('Unable to find:', autoload_file)
	end
	
	return list
end

function is_autoloaded(name, flag)	
	for i, a in pairs(flag and autoload.plugins or autoload.addons) do
		if a:lower() == name:lower() then
			return true
		end
	end
	
	return false
end

function load_global_addons(unload)
	if unload then
		addon_command = 'lua unload '
		plugin_command = 'unload '
	end
	
	if settings.debug_mode then log('GLOBAL') end
	if settings.global_addons and settings.global_addons:length() > 0 then
		for i, name in pairs(settings.global_addons:split(',')) do
			if not tonumber(name) and not is_autoloaded(name) then
				run_command(addon_command..name)
			end
		end
	end
	
	if unload then plugin_command = 'unload ' end
	if settings.global_plugins and settings.global_plugins:length() > 0 then
		for i, name in pairs(settings.global_plugins:split(',')) do
			if not tonumber(name) and not is_autoloaded(name, true) then
				run_command(plugin_command..name)
			end
		end
	end
	
	if unload then
		addon_command = 'lua load '
		plugin_command = 'load '
	end
end

function load_player_addons(unload)
	if settings.debug_mode then log('PLAYER') end
	
	if settings.player_addons[player_name] and settings.player_addons[player_name]:length() > 0 then
		for i, name in pairs(settings.player_addons[player_name]:split(',')) do
			if not tonumber(name) and not is_autoloaded(name) and not settings.global_addons:contains(name) then
				local addoncmd = unload and addon_command:gsub('load', 'unload')..name or addon_command..name
				run_command(addoncmd)
			end
		end
	end
	
	if settings.player_plugins[player_name] and settings.player_plugins[player_name]:length() > 0 then
		for i, name in pairs(settings.player_plugins[player_name]:split(',')) do
			if not tonumber(name) and not is_autoloaded(name, true) and not settings.global_plugins:contains(name) then
				local plugincmd = unload and plugin_command:gsub('load', 'unload')..name or plugin_command..name
				run_command(plugincmd)
			end
		end
	end
end

function load_zone_addons(zone_name, unload)
	if settings.debug_mode then log('BY ZONE') end
	
	if settings.by_zone then
		for i, entry in pairs(settings.by_zone) do
			if entry.zone_names:contains(zone_name) and not entry.ignore:contains(player_name) then
				if entry.addons and entry.addons:length() > 0 then
					for i, name in pairs(entry.addons:split(',')) do
						if not tonumber(name) and not is_autoloaded(name) and not settings.global_addons:contains(name) then
							local addoncmd = unload and addon_command:gsub('load', 'unload')..name or addon_command..name
							run_command(addoncmd)
						end
					end
				end
				
				if entry.plugins and entry.plugins:length() > 0 then
					for i, name in pairs(entry.plugins:split(',')) do
						if not tonumber(name) and not is_autoloaded(name, true) and not settings.global_plugins:contains(name) then
							local plugincmd = unload and plugin_command:gsub('load', 'unload')..name or plugin_command..name
							run_command(plugincmd)
						end
					end
				end
			end
		end
	end
end

function get_zones_addons(zone_name)
	local list = S{}
	for i, entry in pairs(settings.by_zone) do
		if entry.zone_names:contains(zone_name) and not entry.ignore:contains(player_name) then
			if entry.addons and entry.addons:length() > 0 then
				for i, name in pairs(entry.addons:split(',')) do
					if not tonumber(name) and not is_autoloaded(name) and not settings.global_addons:contains(name) then
						list:add(name)
					end
				end
			end
		end
	end
	return list
end

function load_job_addons(job, unload)
	if settings.debug_mode then log('BY JOB') end
	
	if settings.by_job[job] then 
		if settings.by_job[job].addons and settings.by_job[job].addons:length() > 0 then
			for i, name in pairs(settings.by_job[job].addons:split(',')) do
				if not tonumber(name) and not is_autoloaded(name) and not settings.global_addons:contains(name) then
					local addoncmd = unload and addon_command:gsub('load', 'unload')..name or addon_command..name
					run_command(addoncmd)
				end
			end
		end
		
		if settings.by_job[job].plugins and settings.by_job[job].plugins:length() > 0 then
			for i, name in pairs(settings.by_job[job].plugins:split(',')) do
				if not tonumber(name) and not is_autoloaded(name, true) and not settings.global_plugins:contains(name) then
					local plugincmd = unload and plugin_command:gsub('load', 'unload')..name or plugin_command..name
					run_command(plugincmd)
				end
			end
		end
	end
end

function load_autoload_items()
	if settings.debug_mode then log('WINDOWERS AUTOLOAD') end
	if autoload.addons then
		for i, name in pairs(autoload.addons) do
			run_command(addon_command..name)
		end
	end
	if autoload.plugins then
		for i, name in pairs(autoload.plugins) do
			run_command(plugin_command..name)
		end
	end
end

function init()
	local res = require('resources')
	if not jobs or not zones then
		zones = res.zones
		jobs = res.jobs
	end
	
	local player = windower.ffxi.get_player()
	if player and not player_name then
		player_name = player.name:lower()
	elseif not player then
		coroutine.schedule(init, delay)
		return
	end
	
	if not autoload or not autoload.addons or not autoload.plugins then
		autoload = parse_autoload()
		autoload.addons:remove('luacore')
		autoload.plugins:remove('luacore')
	end
	
	if force then load_autoload_items() end
	
	load_global_addons()
	load_player_addons()
	
	current_zone = get_zone_name(windower.ffxi.get_info().zone)
	load_zone_addons(current_zone)
	
	current_job_id = player.main_job_id
	load_job_addons(get_job_shortname(current_job_id))
	
	addon_command = 'lua load '
	plugin_command = 'load '
	log('Complete!')
	
	if force then
		force = false
	end
	
	res = nil
end

function run_command(cmd)
	if settings.debug_mode then log('\t', cmd) end
	windower.send_command(cmd)
	coroutine.sleep(.2)
end

function get_job_shortname(job_id)
	return jobs[job_id].ens:lower()
end

function get_zone_name(zone_id)
	return zones[zone_id].en
end

function get_friendly_zone_name(zone_id)
	return get_zone_name(zone_id):lower():gsub(' ', '_'):gsub('\'', '_'):gsub('-', '_')
end

windower.register_event('addon command', function(...)
	local commands = {...}
	if commands[1] and commands[1] == 'reload' then
		settings = get_settings()
		
		force = false
		if commands[2] and commands[2] == 'force' or commands[2] == 'f' then
			force = true
		end
		
		addon_command = 'lua reload '
		plugin_command = 'reload '
		init()
	elseif commands[1] and commands[1] == 'debug' or commands[1] == 'debugmode' then
		settings.debug_mode = not settings.debug_mode
		log('DEBUG MODE:', settings.debug_mode)
	end
end)

windower.register_event('job change', function(main_job_id, main_job_level, sub_job_id, sub_job_level)
	load_job_addons(get_job_shortname(current_job_id), true) -- flag set to true will unload the addons instead
	
	current_job_id = main_job_id
	load_job_addons(get_job_shortname(current_job_id))
end)

windower.register_event('zone change', function(new_id, old_id)
	local old_zone = get_zone_name(old_id)
	current_zone = get_zone_name(new_id)
	--load_zone_addons(old_zone, true)
	local old_zones_addons = get_zones_addons(old_zone)
	local load_addons = S{}
	for cname in pairs(get_zones_addons(current_zone)) do
		if old_zones_addons:contains(cname) then
			old_zones_addons:remove(cname) -- remove it so it doesn't get unloaded
		elseif not old_zones_addons:contains(cname) then
			load_addons:add(cname) -- add it to be loaded
		end
	end
	
	-- unload the addons from previous zone
	for uname in pairs(old_zones_addons) do
		run_command('lua unload '..uname)
	end
	
	-- load addons from the load_addons list that was built
	for lname in pairs(load_addons) do
		run_command('lua load '..lname)
	end
end)

windower.register_event('load', function()
	local res = require('resources')
	zones = res.zones
	jobs = res.jobs
	
	autoload = parse_autoload()
	autoload.addons:remove('luacore')
	autoload.plugins:remove('luacore')
		
	local player = windower.ffxi.get_player()
	if player and not player_name then
		player_name = player.name:lower()
		current_job_id = player.main_job_id
	end
	
	current_zone = get_zone_name(windower.ffxi.get_info().zone)
	load_zone_addons(current_zone)
	
	res = nil
end)

windower.register_event('login', function()
	coroutine.schedule(init, delay)
end)

windower.register_event('logout', function()
	load_zone_addons(current_zone, true)
	load_job_addons(get_job_shortname(current_job_id), true)
	--load_global_addons(true)
end)
