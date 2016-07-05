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

require("SX1276_H")

local now=tmr.now
local wdclr=tmr.wdclr
local gpiowrite=gpio.write
local spisend=spi.send
local spirecv=spi.recv
local bor=bit.bor
local band=bit.band
local lshift=bit.lshift
local bnot=bit.bnot

local M={
  rxnb=0,
  rxok=0,
  txnb=0
}

local nss=0

local function read(addr)
  gpiowrite(nss, 0)
  spisend(1,band(addr,0x7F))
  local b = spirecv(1,1)
  gpiowrite(nss, 1)
  return string.byte(b)
end

local function readBuffer(addr,len)
  gpiowrite(nss, 0)
  spisend(1,band(addr,0x7F))
  local buf = spirecv(1,len)
  gpiowrite(nss, 1)
  return buf
end

local function write(addr,value)
  gpiowrite(nss, 0)
  spisend(1,bor(addr,0x80),value)
  gpiowrite(nss, 1)
end

local function pktCRC()
  --  local IRQ_FLAGS=0x12
  --  local PayloadCrcError=0x20
  --  local HOP_CHANNEL=0x1C

  local irqflags = read(0x12)
  if band(irqflags,0x20) == 0x20 then
    write(0x12, 0x20)
    return -1
  else
    local rhc = read(0x1C)
    if band(rhc,0x40) == 0x40 then
      return 1
    else
      return 0
    end
  end
end

local function pktChan()
  --  local HOP_CHANNEL=0x1C
  return band(read(0x1C),0x1F)
end

local function pktFreq()
  -- local FRF_MSB=0x06
  -- local FRF_MID=0x07
  -- local FRF_LSB=0x08

  --local frf=lshift(lshift(read(0x06),8)+read(0x07),8)+read(0x08)
  --return (125*frf/2^11) -- in KHz
  return (125000*read(0x08)/2^11)+(125000*read(0x07)/2^3)+(125000*read(0x06)*2^5)
end

local function pktLsnr()
  -- local PKT_SNR_VALUE=0x19
  local snr=read(0x19)
  if band(snr,0x80) then
    snr=-band(bnot(snr)+1,0xFF)
  end
  return snr/4
end

local function pktRssi()
  -- local PKT_RSSI_VALUE=0x1A

  local rssi=read(0x1A)
  return -157+rssi
end

local function pktDatr()
  -- local MODEM_CONFIG=0x1D
  -- local MODEM_CONFIG2=0x1E

  local mc1=read(0x1D)
  local mc2=read(0x1E)
  return getName(MC2,mc2,0xF0)..getName(MC1,mc1,0xF0)
end

local function pktCodr()
  -- local MODEM_CONFIG=0x1D
  local mc1=read(0x1D)
  return getName(MC1,mc1,0x0E)
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

local function rxDone()
  --  local IRQ_FLAGS=0x12
  --  local RxDone=0x40
  local tmst=now()
  local pkt={}
  pkt.tmst=tmst
  pkt.time=gmtime(rtctime.get())
  -- clear rxDone
  write(0x12, 0x40)
  -- message counter
  M.rxnb=M.rxnb+1

  pkt.stat=pktCRC()
  if pkt.stat ~= -1 then
    pkt.chan=pktChan()
    pkt.rfch=0
    pkt.modu="LORA"
    local freq=pktFreq() -- in Hz
    pkt.freq=string.format("%0d.%06d",freq/1000000,freq%1000000)
    pkt.rssi=pktRssi()
    pkt.lsnr=pktLsnr()
    pkt.datr=pktDatr()
    pkt.codr=pktCodr()
    local data=pktData()
    pkt.size=#data
    pkt.data=encoder.toBase64(data)
    -- message ok counter
    M.rxok=M.rxok+1
    -- callback
    M.rxpk(pkt)
  end
end

local function setOpMode(mode)
  --  local OPMODE=0x01
  --  local LORA=0x80
  write(0x01, bor(0x80,mode))
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
  local mc3=0x04
  if (sf == 0xB0 or sf == 0xC0) then mc3=0x0C end -- MC2.SF11=0xB0, MC2.SF12=0xC0
  local stl=0x08
  if (sf == 0xA0 or sf == 0xB0 or sf == 0xC0) then stl=0x05 end

  local pw = powe
  if pw >= 16 then pw = 15
  elseif pw < 2 then pw = 2
  end
  local pac=bor(0x80,band(pw,0x0f))

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

local prevDump={}
local function dump()
  print("----------")
  for r=0x01,0x039 do
    local v=read(r)
    local p=prevDump[r] or 0
    print(string.format("reg %02X = %02X (%02X)",r,v,p))
    prevDump[r]=v
  end
  print("----------")
end


local function transmitPkt(tmst,freq,sf,bw,cr,crc,iiq,powe,data)
  --  local IRQ_FLAGS=0x12
  --  local DIO_MAPPING_1=0x40
  --  local TxDone=0x08
  --  local OPMODE_STDBY=0x01
  --  local OPMODE_FSTX=0x02
  --  local OPMODE_TX=0x03

  local t0=now()
  setOpMode(0x01)
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
  setOpMode(0x02)
  local t1=now()
  local t2=now()
  while t2 < tmst do
    t2=now()
  end
  setOpMode(0x03)
  M.txnb=M.txnb+1
  print("transmitPkt",tmst-t0,tmst-t1,tmst-t2,freq,sf,bw,cr,powe,#data)
end


local function continuous()
  --  local OPMODE_SLEEP=0x00
  --  local OPMODE_RXCONTINUOUS=0x05
  --  local DIO_MAPPING_1=0x40

  setOpMode(0x00)
  --
  write(0x39,0x34) -- syncword LoRaWan
  -- event handler
  write(0x40,0x00)
  gpio.mode(M.dio0,gpio.INT)
  gpio.trig(M.dio0,"up",rxDone)
  -- set channel
  setChannel(M.ch,M.sf)
  -- Set Continous Receive Mode
  print("start continuous scanner...")
  setOpMode(0x05)
end

function M.rxpk(pkg)
  print(cjson.encode(pkg))
end

local TX_TIMER=0
function M.txpk(pkt)
  -- local INVERT_IQ=0x33

  --{"txpk":{"codr":"4/5","data":"YHBhYUoAAwABHOZxE2w","freq":869.525,"ipol":true,"modu":"LORA","powe":27,"rfch":0,"size":14,"tmst":190582123,"datr":"SF9BW125"}}
  local tmst=pkt.tmst
  local freq=pkt.freq
  local sf=MC2[pkt.datr:sub(1,-6)]
  local bw=MC1[pkt.datr:sub(-5)]
  local cr=MC1[pkt.codr]
  local crc=0x00 -- crc disabled...
  local iiq=0x27
  if pkt.ipol then iiq=0x67 end
  local powe=pkt.powe
  local size=pkt.size
  local data=encoder.fromBase64(padBase64(pkt.data)):sub(1,size)
  local trig=(tmst-now())/1000-30
  if trig > 0 then
    tmr.alarm(TX_TIMER,trig,tmr.ALARM_SINGLE,function() transmitPkt(tmst,freq,sf,bw,cr,crc,iiq,powe,data,size) end)
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
  --  local LNA_OFF_GAIN=0x00
  --  local LNA_LOW_GAIN=0x20

  local version = read(0x42)
  if (version ~= 0x12) then
    print("Unknown radio: ",version)
  end
  setOpMode(0x00)
  write(0x39,0x34)
  write(0x0C,0x23)
  write(0x23,0x80)
  write(0x22,0x40)
  write(0x21,0x08)
  write(0x0A, bor(band(read(0x0A),0xF0),0x08)) --set PA ramp-up time 50 uSec
  write(0x5A,bor(read(0x5A),0x04))
end

local function init(dio0,dio1)
  -- setup SPI
  spi.setup(1,spi.MASTER,spi.CPOL_LOW,spi.CPHA_LOW,spi.DATABITS_8,0)
  gpio.mode(nss, gpio.OUTPUT)
  -- init radio
  sxInit()
  M.dio0=dio0
  M.dio1=dio1
  M.ch=GW_CH
  M.sf=MC2[GW_SF]

  M.scanner=continuous
  --M.scanner=manual
  --M.scanner=cad

  M.scanner()

  return M
end

return init
