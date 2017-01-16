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
  return string.format('%04d-%02d-%02dT%02d:%02d:%02d.%06dZ',tm["year"],tm["mon"],tm["day"],tm["hour"],tm["min"],tm["sec"],us)
end

local MC1={
  BW125=0x70,
  BW250=0x80,
  BW500=0x90,
  BW150=0x00
}
MC1["4/5"]=0x02
MC1["4/6"]=0x04
MC1["4/7"]=0x06
MC1["4/8"]=0x08

local MC2={
  FSK=0x00,
  SF6=0x60,
  SF7=0x70,
  SF8=0x80,
  SF9=0x90,
  SF10=0xA0,
  SF11=0xB0,
  SF12=0xC0
}

local function getName(table,value,mask)
  for k,v in pairs(table) do
    if bit.band(value,mask) == v then
      return k
    end
  end
  return "?"
end

-- channels
local function chan(freq,modulation,bw)
  return {
    freq=freq,
    modu=modulation,
    bw=bw
  }
end

local CHN={}
CHN[0]=chan(868100000,"LoRa",MC1.BW125)
CHN[1]=chan(868300000,"LoRa",MC1.BW125)
CHN[2]=chan(868500000,"LoRa",MC1.BW125)
CHN[3]=chan(867100000,"LoRa",MC1.BW125)
CHN[4]=chan(867300000,"LoRa",MC1.BW125)
CHN[5]=chan(867500000,"LoRa",MC1.BW125)
CHN[6]=chan(867700000,"LoRa",MC1.BW125)
CHN[7]=chan(867900000,"LoRa",MC1.BW125)
CHN[8]=chan(868300000,"LoRa",MC1.BW250)
CHN[9]=chan(868800000,"FSK" ,MC1.BW150)

local now=tmr.now
local gpiowrite=gpio.write
local spisend=spi.send
local spirecv=spi.recv
local bor=bit.bor
local band=bit.band
local bnot=bit.bnot
local delay=tmr.delay
local byte=string.byte

local M={
  rxnb=0,
  rxok=0,
  txnb=0
}

local nss=0

local function read(addr)
  gpiowrite(nss, 0)
  spisend(1,addr)
  local b = spirecv(1,1)
  gpiowrite(nss, 1)
  return byte(b)
end

local function readBuffer(addr,len)
  gpiowrite(nss, 0)
  spisend(1,addr)
  local buf = spirecv(1,len)
  gpiowrite(nss, 1)
  return buf
end

local function write(addr,value)
  gpiowrite(nss, 0)
  spisend(1,addr+0x80,value)
  gpiowrite(nss, 1)
end

local function pktData()
  -- local FIFO_RX_CURRENT_ADDR=0x10
  -- local RX_NB_BYTES=0x13
  -- local FIFO_ADDR_PTR=0x0D
  -- local FIFO=0x00

  local curr = read(0x10)
  local count = read(0x13)
  write(0x0D, curr)
  return readBuffer(0x00,count)
end

local tmst=0
local function rxDone()
  --  local IRQ_FLAGS=0x12
  --  local RxDone=0x40
  --local tmst=now()
  local pkt={}
  pkt.tmst=tmst
  pkt.time=gmtime(rtctime.get())
  -- clear rxDone
  write(0x12, 0x40)
  -- message counter
  M.rxnb=M.rxnb+1

  -- CRC
  local irqflags = read(0x12)
  if band(irqflags,0x20) == 0x20 then
    write(0x12, 0x20)
    pkt.stat=-1
  else
    local rhc = read(0x1C)
    if band(rhc,0x40) == 0x40 then
      pkt.stat= 1
    else
      pkt.stat= 0
    end
  end

  if pkt.stat ~= -1 then
    local hopch=read(0x1C)
    pkt.chan=band(hopch,0x1F) --pktChan()

    pkt.rfch=0
    pkt.modu="LORA"

    local freq=(125000*read(0x08)/2^11)+(125000*read(0x07)/2^3)+(125000*read(0x06)*2^5) --pktFreq() -- in Hz
    pkt.freq=string.format("%0d.%03d",freq/1000000,((freq+500)/1000)%1000)

    local rssi=read(0x1A)
    pkt.rssi=-157+rssi-- pktRssi()

    local snr=read(0x19)
    if snr > 127 then
      snr=-(band(bnot(snr),0xFF)+1)
    end
    pkt.lsnr=snr/4 --pktLsnr()

    local mc1=read(0x1D)
    local mc2=read(0x1E)
    pkt.datr=getName(MC2,mc2,0xF0)..getName(MC1,mc1,0xF0) -- pktDatr()

    pkt.codr=getName(MC1,mc1,0x0E) -- pktCodr()

    local data=pktData()
    pkt.size=#data
    pkt.data=encoder.toBase64(data)
    -- message ok counter
    M.rxok=M.rxok+1
    -- callback
    M.rxpk(pkt)
  end
end

local function setFreq(freqHz)
  --  local FRF_MSB=0x06
  --  local FRF_MID=0x07
  --  local FRF_LSB=0x08

  -- keep resolution for integer version
  -- frf = (freqHz*2^19)/32000000
  -- frf = (freqHz*2^14)/1000000
  -- frf = (freqHz/1000*2^14)/1000
  -- frf = (freqHz/1000*2^11)/125
  local frf=(freqHz/1000*2^11)/125
  local frfMsb=frf/2^16
  local frfMid=frf/2^8 % 256
  local frfLsb=frf % 256
  write(0x06, frfMsb)
  write(0x07, frfMid)
  write(0x08, frfLsb)
  --print(string.format("%0d.%06d Mhz %02X %02X %02X ",freqHz/1000000,freqHz%1000000,frfMsb,frfMid,frfLsb))
end

local function setRate(sf,bw,cr,crc,iiq,powe)
  --  local SF10=0xA0
  --  local SF11=0xB0
  --  local SF12=0xC0
  --  local PA_CONFIG=0x09
  --  local MODEM_CONFIG1=0x1D
  --  local MODEM_CONFIG2=0x1E
  --  local MODEM_CONFIG3=0x26
  --  local SYMB_TIMEOUT_LSB=0x1F
  --  local INVERT_IQ=0x33

  local mc1=bor(bw,cr)
  local mc2=bor(sf,crc)
  --local mc3=0x04
  local mc3=0x00 -- no AGC
  if (sf == 0xB0 or sf == 0xC0) then mc3=0x08 end -- MC2.SF11=0xB0, MC2.SF12=0xC0
  local stl=0x08
  if (sf == 0xA0 or sf == 0xB0 or sf == 0xC0) then stl=0x05 end

  local pac 
  if powe > 17 then pac = 0x8F               -- 17dbm
  elseif powe < -3  then pac = 0x20          -- -3dbm
  elseif powe <= 12 then pac = 0x20+powe+3   -- -3dbm .. 12dbm
  else pac = 0x80+powe-2                     -- 13dbm .. 16dbm          
  end

  write(0x09,pac)
  write(0x1D,mc1)
  write(0x1E,mc2)
  write(0x26,mc3)
  write(0x1F,stl)
  write(0x33,iiq)
end


local function setChannel(ch,sf)
  --  local HOP_PERIOD=0x24
  --  local FIFO_ADDR_PTR=0x0D
  --  local FIFO_RX_BASE_AD=0x0F
  --  local CR4_5=0x02
  --  local CRC_ON=0x04

  setFreq(CHN[ch].freq)
  setRate(sf,CHN[ch].bw,0x02,0x04,0x27,14) -- CR4/5=0x02, CRC_ON=0x04
  write(0x24,0x00)
  write(0x0D,read(0x0F))
end

local function txBuffer(data)
  --  local FIFO_ADDR_PTR=0x0D
  --  local FIFO_TX_BASE_AD=0x0E
  --  local PAYLOAD_LENGTH=0x22
  --  local FIFO=0x00

  write(0x0D,read(0x0E))
  write(0x22,#data)
  write(0x00,data)
end

local function transmitPkt(tmst,freq,sf,bw,cr,crc,iiq,powe,data)
  --  local IRQ_FLAGS=0x12
  --  local DIO_MAPPING_1=0x40
  --  local TxDone=0x08
  --  local OPMODE_STDBY=0x01
  --  local OPMODE_FSTX=0x02
  --  local OPMODE_TX=0x03

  local t0=now()
  state=3 -- tx
  write(0x01,0x80)
  write(0x40,0x40) --DIO_MAPPING_1=0x40
  gpio.mode(M.dio0,gpio.INT)
  gpio.trig(M.dio0,"up",function()
    -- clear TxDone
    write(0x12, 0xFF)
    --print("TxDone")
    M.scanner()
  end)
  setFreq(freq)
  setRate(sf,bw,cr,crc,iiq,powe)
  txBuffer(data)
  write(0x01,0x82)
  local t1=now()
  local t2=now()
  while t2 < tmst do
    t2=now()
  end
  write(0x01,0x83)
  M.txnb=M.txnb+1
  print("transmitPkt",tmst-t0,tmst-t1,tmst-t2,freq,sf,bw,cr,iiq,powe,#data)
end

local state=0
local cadSF=0
local cadCh=0

local function hop()
  local rssi=read(0x1B)
  if rssi < 50 then
    write(0x01,0x81) -- Lora STANDBY
    --cadCh=(cadCh+1)%3
    if cadCh == 0 then
      --setFreq(868100000)
      --write(0x06, 0xD9);
      write(0x07, 0x06);
      write(0x08, 0x66);
    elseif cadCh == 1 then
      --setFreq(868300000)
      --write(0x06, 0xD9);
      write(0x07, 0x13);
      write(0x08, 0x33);
    elseif cadCh == 2 then
      --setFreq(868500000)
      --write(0x06, 0xD9);
      write(0x07, 0x20);
      write(0x08, 0x00);
    end
    write(0x01,0x87) -- set mode LoRa CAD
    write(0x40,0xA3) -- DIO0 CadDone, DIO1 None, DIO3 None
  end
end

local function dio1handler()
  --  local IRQ_FLAGS=0x12
  --  local DIO_MAPPING_1=0x40

  if state == 0 or state == 1 then -- CAD_DETECTED
    write(0x01,0x86) -- RX_SINGLE
    write(0x12,0xFF) -- clear interrupt flags
    state=2
    write(0x40,0x03) -- DIO0 RxDone, DIO1 RxTimeout, DIO3 None
    delay(256)
    local rssi=read(0x1B)
    if rssi < 40 then
      M.scanner()
    end
  elseif state == 2 then -- RX_TIMEOUT
    local rssi=read(0x1B)
    print("rx timeout",cadSF/16,cadCh,"rssi",rssi)
    M.scanner()
  end
end

local function dio0handler()
  --  local OP_MODE=0x01
  --  local IRQ_FLAGS=0x12
  --  local MODEM_CONFIG3=0x26
  --  local DIO_MAPPING_1=0x40
  --  local OPMODE_CAD=0x07

  tmst=now()
  -- CadDone
  if state==1 then
    if cadSF < 0xC0 then -- try next SF
      cadSF=cadSF+0x10 -- next SF
      write(0x1E,cadSF) -- set next SF
      if cadSF==0xB4 then
        write(0x26,0x0C) -- ModemConfig3: LowDataRateOptimize on
      end
      if cadSF==0xA4 then
        write(0x1F,0x05) -- RegSymbolTimeoutLSB: SymbolTimeout 5
      end
      write(0x01,0x87) -- set mode LoRa CAD
      write(0x12,0xFF) -- clear interrupt flags
      delay(256)
      local rssi=read(0x1B)
      if rssi < 40 then
        M.scanner()
      end
    else
      M.scanner() -- restart scanner
    end
  elseif state==0 then
    write(0x01,0x87) -- set mode LoRa CAD
    write(0x12,0xFF) -- clear interrupt flags
    delay(256)
    local rssi=read(0x1B)
    if rssi > 42 then
      state=1 -- CAD
    else
    --hop()
    end
  elseif state==2 then
    local flags=read(0x12)
    if band(flags,0x40)==0x40 then
      -- RxDone
      rxDone() -- handle message received
      M.scanner() -- restart scanner
    end
  end
end


local function allSf()
  --  local RegOpMode=0x01
  --  local OPMODE_SLEEP=0x00
  --  local OPMODE_RX=0x05
  --  local DIO_MAPPING_1=0x40

  write(0x01,0x81)  -- set mode LoRa standby
  write(0x39,0x34) -- syncword LoRaWan
  setChannel(M.ch,M.sf) -- channel settings in LoRa mode

  cadSF=M.sf+0x04 -- reset SF hopper

  gpio.mode(M.dio0,gpio.INT)
  gpio.trig(M.dio0,"up",dio0handler)
  gpio.mode(M.dio1,gpio.INT)
  gpio.trig(M.dio1,"up",dio1handler)
  write(0x40,0xA3) -- DIO0 CadDone, DIO1 None, DIO3 None

  --start
  write(0x01,0x87) -- set mode LoRa CAD
  state=0 -- RSSI detect
  write(0x12,0xFF) -- clear interrupt flags
  delay(256)
  local rssi=read(0x1B)
  if rssi > 42 then
    state=1 -- CAD
  end
end

local function singleSf()
  write(0x01,0x81)  -- set mode LoRa standby
  write(0x39,0x34) -- syncword LoRaWan
  setChannel(M.ch,M.sf) -- channel settings in LoRa mode
  gpio.mode(M.dio0,gpio.INT)
  gpio.trig(M.dio0,"up",function()
    tmst=now()
    rxDone()
    write(0x12,0xFF) -- clear interrupt flags
  end)
  write(0x40,0x03) -- DIO0 RxDone, DIO1 RxTimeout, DIO3 None
  write(0x01,0x85)  -- set mode LoRa rxContinuous
end


function M.rxpk(pkg)
  print(cjson.encode(pkg))
end

function M.txpk(pkt)
  --{"txpk":{"codr":"4/5","data":"YHBhYUoAAwABHOZxE2w","freq":869.525,"ipol":true,"modu":"LORA","powe":27,"rfch":0,"size":14,"tmst":190582123,"datr":"SF9BW125"}}
  local tmst=pkt.tmst+1000 -- Send a bit later than commanded by the txpk. Works much better for OTAA, I don't know why...
  local freq=pkt.freq
  local sf=MC2[pkt.datr:sub(1,-6)]
  local bw=MC1[pkt.datr:sub(-5)]
  local cr=MC1[pkt.codr]
  local crc=0x00 -- crc disabled...
  local iiq=0x27
  if pkt.ipol==true then iiq=0x40 end
  local powe=pkt.powe
  local size=pkt.size
  local data=encoder.fromBase64(padBase64(pkt.data)):sub(1,size)
  local trig=((tmst-now())/1000)-20
  if trig > 0 then
    tmr.alarm(0,trig,tmr.ALARM_SINGLE,function() transmitPkt(tmst,freq,sf,bw,cr,crc,iiq,powe,data,size) end)
  else
    transmitPkt(tmst,freq,sf,bw,cr,crc,iiq,powe,data,size)
  end
  local msg='{"txpk_ack":{"error":"NONE"}}'
  if trig <= 0 then
    msg='{"txpk_ack":{"error":"TOO_LATE"}}'
  end
  return msg
end

local function sxInit()
  --  local VERSION=0x42
  --  local OPMODE_SLEEP=0x00
  --  local SYNC_WORD=0x39
  --  local LNA=0x0C
  --  local MAX_PAYLOAD_LENGTH=0x23
  --  local PAYLOAD_LENGTH=0x22
  --  local PREAMBLE_LSB=0x21
  --  local PA_RAMP=0x0A
  --  local PA_DAC=0x5A
  --  local LNA_MAX_GAIN=0x23

  local version = read(0x42)
  if (version ~= 0x12) then
    print("Unknown radio: ",version)
  end
  write(0x01,0x80)
  write(0x39,0x34)
  write(0x0C,0x23)
  write(0x23,0x23)
  write(0x22,0x40)
  write(0x21,0x08)
  write(0x0A, bor(band(read(0x0A),0xF0),0x08)) --set PA ramp-up time 50 uSec
  write(0x5A,bor(read(0x5A),0x04))
  write(0x37,0x0A) -- detection threshold
end

local function init(dio0,dio1)
  --
  node.setcpufreq(node.CPU160MHZ)
  -- setup SPI
  spi.setup(1,spi.MASTER,spi.CPOL_LOW,spi.CPHA_LOW,spi.DATABITS_8,3)
  if (GW_NSS) then
    nss=GW_NSS
  end
  gpio.mode(nss, gpio.OUTPUT)
  -- init radio
  sxInit()
  -- setup handlers
  M.dio0=dio0
  M.dio1=dio1

  M.ch=GW_CH
  if (GW_SF) then
    M.sf=MC2[GW_SF]
    M.scanner=singleSf
    print("start singleSF detector on",GW_SF)
  else
    M.sf=MC2["SF7"]
    M.scanner=allSf
    print("start allSF detector")
  end

  M.scanner()

  return M
end

return init
