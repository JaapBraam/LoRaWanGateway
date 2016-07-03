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

MC1={
  BW125=0x70,
  BW250=0x80,
  BW500=0x90,
  BW150=0x00
}
MC1["4/5"]=0x02
MC1["4/6"]=0x04
MC1["4/7"]=0x06
MC1["4/8"]=0x08

MC2={
  FSK=0x00,
  SF6=0x60,
  SF7=0x70,
  SF8=0x80,
  SF9=0x90,
  SF10=0xA0,
  SF11=0xB0,
  SF12=0xC0
}

function getName(table,value,mask)
  for k,v in pairs(table) do
    if bit.band(value,mask) == v then
      return k
    end
  end
  return "?"
end

-- channels
function chan(freq,modulation,bw)
  return {
    freq=freq,
    modu=modulation,
    bw=bw
  }
end

CHN={}
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
