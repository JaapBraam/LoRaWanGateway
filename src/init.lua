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

if file.exists("utils.lua") then
    node.compile("utils.lua")
    file.remove("utils.lua")
    node.restart()
elseif file.exists("SX1276_H.lua") then
    node.compile("SX1276_H.lua")
    file.remove("SX1276_H.lua")
    node.restart()
elseif file.exists("SX1276.lua") then
    node.compile("SX1276.lua")
    file.remove("SX1276.lua")
    node.restart()
elseif file.exists("LoRaWanGW.lua") then
    node.compile("LoRaWanGW.lua")
    file.remove("LoRaWanGW.lua")
    node.restart()
else
   require("LoRaWanGW")
end

-- settings
GW_CH=0
GW_SF="SF7"
-- Gateway location
GW_LAT=0.0 -- the latitude
GW_LON=0.0 -- the longitue
