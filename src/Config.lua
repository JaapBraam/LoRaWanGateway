CONFIG = {}
-- defaults
CONFIG["GW_HOSTNAME"]="lorawangw"
CONFIG["GW_ROUTER"]="router.eu.thethings.network"
CONFIG["GW_FREQ"]=868100000
CONFIG["GW_BW"]="BW125"
CONFIG["GW_SF"]="ALL"
CONFIG["GW_LAT"]="0.0"
CONFIG["GW_LON"]="0.0"
CONFIG["GW_ALT"]=0
CONFIG["GW_NSS"]=0
CONFIG["GW_DIO0"]=1
CONFIG["GW_DIO1"]=2

local function printConfig()
   print("GW_HOSTNAME",'"'..CONFIG["GW_HOSTNAME"]..'"')
   print("GW_ROUTER  ",'"'..CONFIG["GW_ROUTER"]..'"')
   print("GW_FREQ    ",CONFIG["GW_FREQ"])
   print("GW_BW      ",'"'..CONFIG["GW_BW"]..'"')
   print("GW_SF      ",'"'..CONFIG["GW_SF"]..'"')
   print("GW_LAT     ",'"'..CONFIG["GW_LAT"]..'"')
   print("GW_LON     ",'"'..CONFIG["GW_LON"]..'"')
   print("GW_ALT     ",CONFIG["GW_ALT"])
   print("GW_NSS     ",CONFIG["GW_NSS"])
   print("GW_DIO0    ",CONFIG["GW_DIO0"])
   print("GW_DIO1    ",CONFIG["GW_DIO1"])
end

local function saveConfig()
  CONFIG.save=nil
  CONFIG.print=nil
  file.open('config.json',"w+")
  file.write(cjson.encode(CONFIG))
  file.close()
  CONFIG.save=saveConfig
  CONFIG.print=printConfig
end

if file.exists('config.json') then
  file.open('config.json')
  local json=file.read()
  file.close()
  CONFIG=cjson.decode(json)
else
  print("no config found, using default values")
end

CONFIG.print=printConfig
CONFIG.save=saveConfig

-- a simple telnet server
local s=net.createServer(net.TCP)
s:listen(23,function(c)
   con_std = c
   function s_output(str)
      if(con_std~=nil)
         then con_std:send(str)
      end
   end
   node.output(s_output, 0)   -- re-direct output to function s_ouput.
   c:on("receive",function(c,l)
      node.input(l)           -- works like pcall(loadstring(l)) but support multiple separate line
   end)
   c:on("disconnection",function(c)
      con_std = nil
      node.output(nil)        -- un-regist the redirect output function, output goes to serial
   end)
   print("LoRaWanGateway")
   printConfig()
end)
