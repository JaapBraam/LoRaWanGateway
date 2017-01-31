--The MIT License (MIT)
--
--Copyright (c) 2016 Jaap Braam
--
--Permission is hereby granted, free of charge, to any person obtaining a copy
--of this software and associated documentation files (the "Software"), to deal
--in the Software without restriction, including without limitation the rights
--to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
--copies of the Software, and to permit persons to whom the Software is
--furnished to do so, subject to the following conditions:
--
--The above copyright notice and this permission notice shall be included in all
--copies or substantial portions of the Software.
--
--THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
--IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
--FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
--AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
--LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
--OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
--SOFTWARE.
--
--Author: Jaap Braam

local function padBase64(s)
  local p=4-(#s % 4)
  return s..string.rep("=",p % 4)
end

local function gmtime(t,us)
  local tm = rtctime.epoch2cal(t)
  return string.format('%04d-%02d-%02d %02d:%02d:%02d GMT',tm["year"],tm["mon"],tm["day"],tm["hour"],tm["min"],tm["sec"])
end


-- communication with router!

local GW_id="<UNKNOWN>"
local router_client
local router_ip
local radio

local function getGW_id()
  local s=string.gsub(wifi.sta.getmac(),":","")
  s=string.sub(s,1,6).."F42F"..string.sub(s,7)
  s=string.upper(s)
  print("Gateway ID",s)
  GW_id=""
  for i=1,16,2 do
    GW_id = GW_id .. string.char(tonumber(s:sub(i,i+1),16))
  end
  return s
end

local function header(pkgType,r1,r2)
  if r1 == nil then r1=math.random(256)-1 end
  if r2 == nil then r2=math.random(256)-1 end
  return string.char(
    0x01, --ProtocolVersion
    r1, -- RandomSeed
    r2, -- RandomSeed
    pkgType
  ) .. GW_id
end

local STATS={
  start=0,
  rxnb=0,
  rxok=0,
  rxto=0,
  rxfw=0,
  dwnb=0,
  txnb=0,
  upSent=0,
  upAcks=0
}


local GW_stat={
  time=gmtime(rtctime.get()),
  lati="0.0",
  long="0.0",
  alti=0,
  rxnb=0,
  rxok=0,
  rxfw=0,
  ackr=0, -- float!
  dwnb=0,
  txnb=0,
  pfrm="ESP8266",
--mail="",
  desc="ESP8266 Gateway (Lua)"
}

-- statistics for ackr
local upSent=0 -- upstream messages sent
local upAcks=0 -- upstream messages acked

function statistics()
  local t,us=rtctime.get()
  local tm = rtctime.epoch2cal(t-STATS.start)
  local ackr=1000
  if (STATS.upSent+upSent) > 0 then
    ackr=1000*(STATS.upAcks+upAcks)/(STATS.upSent+upSent)
  end
  print("Statistics")
  print("\tUptime         ",string.format('%d days, %d hours, %d minutes, %d seconds',tm["yday"]-1,tm["hour"],tm["min"],tm["sec"]))
  print("\tMemory free    ",string.format('%d bytes',node.heap()))
  print("\tRx packets     ",STATS.rxnb+radio.rxnb)
  print("\tRx packets OK  ",STATS.rxok+radio.rxok)
  print("\tRx timeouts    ",STATS.rxto+radio.rxto)
  print("\tRx forwarded   ",STATS.rxfw+GW_stat.rxfw)
  print("\tTx packets     ",STATS.dwnb+GW_stat.dwnb)
  print("\tTx packets sent",STATS.txnb+radio.txnb)
  print("\tAck ratio      ",string.format("%0d.%0d%% (%d/%d)",ackr/10,ackr%10,STATS.upAcks+upAcks,STATS.upSent+upSent))
end


local function stat()
  GW_stat.time=gmtime(rtctime.get())
  GW_stat.rxnb=radio.rxnb
  GW_stat.rxok=radio.rxok
  GW_stat.txnb=radio.txnb
  if upSent > 0 then
    local ackr=1000*upAcks/upSent
    GW_stat.ackr=string.format("%0d.%0d",ackr/10,ackr%10)
  end
  local msg=cjson.encode({stat=GW_stat})
  -- fix floats in strings
  msg=msg:gsub('"(%-*%d+)[.](%d+)"','%1.%2')
  -- update statistics since start
  STATS.rxnb=STATS.rxnb+GW_stat.rxnb
  STATS.rxok=STATS.rxok+GW_stat.rxok
  STATS.rxto=STATS.rxto+radio.rxto
  STATS.rxfw=STATS.rxfw+GW_stat.rxfw
  STATS.txnb=STATS.txnb+GW_stat.txnb
  STATS.upSent=STATS.upSent+upSent
  STATS.upAcks=STATS.upAcks+upAcks
  STATS.dwnb=STATS.dwnb+GW_stat.dwnb
  STATS.txnb=STATS.txnb+GW_stat.txnb
  -- clear
  radio.rxnb=0
  radio.rxok=0
  radio.rxto=0
  radio.txnb=0
  upSent=0
  upAcks=0
  GW_stat.dwnb=0
  GW_stat.rxfw=0
  return header(0x00)..msg
end

local PUSH_TIMER=5
local PUSH_INTERVAL=30*1000
local PULL_TIMER=6
local PULL_INTERVAL=5*1000

local function start_scheduler(router)
  tmr.alarm(PUSH_TIMER,PUSH_INTERVAL,tmr.ALARM_AUTO,function()
    local msg=stat()
    --print("push",encoder.toHex(msg:sub(1,12)),"message",msg:sub(13),"length",msg:len())
    --router:send(msg)
    router:send(1700,router_ip,msg)
    upSent=upSent+1
  end)
  tmr.alarm(PULL_TIMER,PULL_INTERVAL,tmr.ALARM_AUTO,function()
    local msg=header(0x02)
    --print("pull",encoder.toHex(msg:sub(1,12)))
    --router:send(msg)
    router:send(1700,router_ip,msg)
    upSent=upSent+1
  end)
  sntp.sync('nl.pool.ntp.org',function(s,us,server)
    print("ntp synced using "..server)
  end,nil,1)
end

local function rxpk(pkg)
  local msg=header(0x00)..cjson.encode({rxpk={pkg}})
  -- fix '4\/5' -> '4/5'
  msg=msg:gsub("\\/","/")
  -- fix floats in strings
  msg=msg:gsub('"(%d+)[.](%d+)"','%1.%2')
  --router_client:send(msg)
  router_client:send(1700,router_ip,msg)
  print("rxpk",encoder.toHex(msg:sub(1,12)),"message",msg:sub(13),"length",msg:len())
  upSent=upSent+1
  GW_stat.rxfw=GW_stat.rxfw+1
end

local function tx_ack(data)
  local msg=header(0x05,data:byte(2),data:byte(3))
  -- translate freq (Mhz) float to int (Hz)
  local fix=data:sub(5):gsub('"freq":(%d+)[.](%d+),',function(d,f) local h=f; while h*10 < 1000000 do h=h*10 end; return '"freq":'..(d*1000000+h)..',' end)
  local json=cjson.decode(fix)
  local resp=radio.txpk(json.txpk)
  GW_stat.dwnb=GW_stat.dwnb+1
  print("txpk",data:sub(5))
  print("txpk_ack",resp)
  --router_client:send(msg..resp)
  router_client:send(1700,router_ip,msg..resp)
end

local function receiver(router,data)
  local t=data:byte(4)
  if     t == 0x01 then -- PUSH_ACK
    --print("recv",encoder.toHex(data),"PUSH_ACK")
    upAcks=upAcks+1
  elseif t == 0x04 then -- PULL_ACK
    --print("recv",encoder.toHex(data),"PULL_ACK")
    upAcks=upAcks+1
  elseif t == 0x03 then -- PULL_RESP
    --print("recv",encoder.toHex(data:sub(1,4)),"PULL_RESP",data:sub(5))
    tx_ack(data)
    GW_stat.dwnb=GW_stat.dwnb+1
  else -- UNKNOWN MSG TYPE
    print("recv","UNKNOWN",encoder.toHex(data))
  end
end

local function connectRouter()
  router_client= net.createConnection(net.UDP)
  router_client:on("receive", receiver)
  router_client:dns(CONFIG["GW_ROUTER"],function(sck,ip)
    print("router ip:",ip)
    router_ip=ip
    --router_client:connect(1700,ip)
    start_scheduler(router_client)
  end)
end

-- start gateway
wifi.sta.eventMonReg(wifi.STA_GOTIP, function()
  -- stop eventloop
  wifi.sta.eventMonStop()
  print("got ip",wifi.sta.getip())
  -- get GW id
  getGW_id()
  -- sync time
  sntp.sync('nl.pool.ntp.org',function(s,us,server)
    print("ntp synced using "..server)
    local t,us=rtctime.get()
    print(gmtime(t,us))
    math.randomseed(us)
    STATS.start=t
    connectRouter()
    if (CONFIG["GW_ALT"]) then
      GW_stat.alti=CONFIG["GW_ALT"]
    end
    if (CONFIG["GW_LAT"]) then
      GW_stat.lati=CONFIG["GW_LAT"]
    end
    if (CONFIG["GW_LON"]) then
      GW_stat.long=CONFIG["GW_LON"]
    end
    local nss=CONFIG["GW_NSS"]
    local dio0=CONFIG["GW_DIO0"]
    local dio1=CONFIG["GW_DIO1"]
    local freq=CONFIG["GW_FREQ"]
    local sf=CONFIG["GW_SF"]
    local bw=CONFIG["GW_BW"]
    radio=require("SX1276")(nss,dio0,dio1,freq,sf,bw)
    radio.rxpk=rxpk
  end,function()
    print("sntp failed... restarting")
    node.restart()
  end)
end)

-- startup
wifi.sta.sethostname(CONFIG['GW_HOSTNAME'])
wifi.sta.eventMonStart()
