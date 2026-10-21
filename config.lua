-------------------------------------------------------------------------------
-- config.lua
-- Default configuration entrypoint delegating to the modular rule engine.
-- To override the engine completely, write custom imapfilter Lua logic here.
-------------------------------------------------------------------------------
local engine = loadfile('/usr/local/share/imapfilter/engine.lua') or
               loadfile('src/engine.lua') or
               loadfile('./src/engine.lua')

if engine then
    engine()
else
    error('Could not locate engine.lua')
end
