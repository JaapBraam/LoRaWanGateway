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

local floor=math.floor

function round(num, idp)
  local mult = 10^(idp or 0)
  return floor(num * mult + 0.5) / mult
end

function padBase64(s)
  local p=4-(#s % 4)
  return s..string.rep("=",p % 4)
end


-- time stamp

local DSEC=24*60*60 -- secs in a day
local YSEC=365*DSEC -- secs in a year
local LSEC=YSEC+DSEC    -- secs in a leap year
local FSEC=4*YSEC+DSEC  -- secs in a 4-year interval
local BASE_DOW=4    -- 1970-01-01 was a Thursday
local BASE_YEAR=1970    -- 1970 is the base year

local _days={
    -1, 30, 58, 89, 119, 150, 180, 211, 242, 272, 303, 333, 364
}
local _lpdays={}
for i=1,2  do _lpdays[i]=_days[i]   end
for i=3,13 do _lpdays[i]=_days[i]+1 end

function gmtime(t,us)
--print(os.date("!\n%c\t%j",t),t)
    local y,j,m,d,w,h,n,s
    local mdays=_days
    s=t
    -- First calculate the number of four-year-interval, so calculation
    -- of leap year will be simple. Btw, because 2000 IS a leap year and
    -- 2100 is out of range, this formula is so simple.
    y=floor(s/FSEC)
    s=s-y*FSEC
    y=y*4+BASE_YEAR         -- 1970, 1974, 1978, ...
    if s>=YSEC then
        y=y+1           -- 1971, 1975, 1979,...
        s=s-YSEC
        if s>=YSEC then
            y=y+1       -- 1972, 1976, 1980,... (leap years!)
            s=s-YSEC
            if s>=LSEC then
                y=y+1   -- 1971, 1975, 1979,...
                s=s-LSEC
            else        -- leap year
                mdays=_lpdays
            end
        end
    end
    j=floor(s/DSEC)
    s=s-j*DSEC
    local m=1
    while mdays[m]<j do m=m+1 end
    m=m-1
    local d=(j-mdays[m])
    -- Calculate day of week. Sunday is 0
    w=(floor(t/DSEC)+BASE_DOW)%7
    -- Calculate the time of day from the remaining seconds
    h=floor(s/3600)
    s=s-h*3600
    n=floor(s/60)
    s=s-n*60
    return string.format('%04d-%02d-%02dT%02d:%02d:%02d.%06dZ',y,m,d,h,n,s,us)
end
