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

require("utils")

-- communication with router!

local GW_id="<UNKNOWN>"
local router_client
local radio

local function getGW_id()
  s=string.gsub(wifi.sta.getmac(),":","")
  s=string.sub(s,1,6).."FFFF"..string.sub(s,7)
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

local GW_stat={
  time=gmtime(rtctime.get()),
  alti=0,
  rxnb=0,
  rxok=0,
  rxfw=0,
  ackr=0, -- float!
  dwnb=0,
  txnb=0,
  pfrm="ESP8266",
  mail="",
  desc="ESP8266 Gateway (Lua)"
}

-- statistics for ackr
local upSent=0 -- upstream messages sent
local upAcks=0 -- upstream messages acked

function stat()
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
  msg=msg:gsub('"(%d+)[.](%d+)"','%1.%2')
  radio.rxnb=0
  radio.rxok=0
  radio.txnb=0
  upSent=0
  upAcks=0
  GW_stat.dwnb=0
  GW_stat.rxfw=0
  return header(0x00)..msg
end

local SNTP_TIMER=4
local SNTP_INTERVAL=300*1000
local PUSH_TIMER=5
local PUSH_INTERVAL=30*1000
local PULL_TIMER=6
local PULL_INTERVAL=5*1000

local function start_scheduler(router)
  tmr.alarm(PUSH_TIMER,PUSH_INTERVAL,tmr.ALARM_AUTO,function()
    local msg=stat()
    --print("push",encoder.toHex(msg:sub(1,12)),"message",msg:sub(13),"length",msg:len())
    router:send(msg)
    upSent=upSent+1
  end)
  tmr.alarm(PULL_TIMER,PULL_INTERVAL,tmr.ALARM_AUTO,function()
    local msg=header(0x02)
    --print("pull",encoder.toHex(msg:sub(1,12)))
    router:send(msg)
    upSent=upSent+1
  end)
  tmr.alarm(SNTP_TIMER,SNTP_INTERVAL,tmr.ALARM_AUTO,function()
    sntp.sync('nl.pool.ntp.org',function(s,us,server)
      print("ntp synced using "..server)
    end)
  end)
end

local function rxpk(pkg)
  local msg=header(0x00)..cjson.encode({rxpk={pkg}})
  -- fix '4\/5' -> '4/5'
  msg=msg:gsub("\\/","/")
  -- fix floats in strings
  msg=msg:gsub('"(%d+)[.](%d+)"','%1.%2')
  router_client:send(msg)
  print("rxpk",encoder.toHex(msg:sub(1,12)),"message",msg:sub(13),"length",msg:len())
  upSent=upSent+1
  GW_stat.rxfw=GW_stat.rxfw+1
end

local function tx_ack(data)
  local msg=header(0x05,data:byte(2),data:byte(3))
  -- translate freq (Mhz) float to int (Hz)
  local fix=data:sub(5):gsub('"freq":(%d+)[.](%d+),',function(d,f) return '"freq":'..(d*1000000+f*100000)..',' end)
  local json=cjson.decode(fix)
  local resp=radio.txpk(json.txpk)
  GW_stat.dwnb=GW_stat.dwnb+1
  print("txpk",data:sub(5))
  print("txpk_ack",resp)
  router_client:send(msg..resp)
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
  router_client:dns("router.eu.thethings.network",function(sck,ip)
    router_client:connect(1700,ip)
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
    print(gmtime(rtctime.get()))
    math.randomseed(us)
    connectRouter()
    GW_stat.lati=GW_LAT
    GW_stat.long=GW_LON
    radio=require("SX1276")(1,2)
    radio.rxpk=rxpk
  end)
end)

-- startup
wifi.sta.eventMonStart()
