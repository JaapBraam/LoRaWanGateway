# LoRaWanGateway
A LoRaWan Gateway in Lua, listening to all spreading factors on one specific channel.

## Goals
+ Port the OneChannelGateway to NodeMCU/Lua (https://github.com/things4u/ESP-1ch-Gateway) - Done!
+ Add support for sending messages to nodes - Done!
+ Add support for OTAA - Done!
+ Add support for receiving multiple SF's on a channel - Done!
+ Add support for more than one channel (won't work :-( )

## Why Lua?
Lua is an event driven language, which is a good match for a gateway: a gateway has to respond to incoming messages from nodes and routers.
The LoraWanGateway runs on an ESP8266 chip, with the NodeMCU firmware it runs a full WiFi stack and a Lua runtime. The NodeMCU contains a lot of libraries that are usefull for a gateway: WiFi, NTP support, SPI, 6 timers, JSON support etc.

## How multiple spreading factors are detected
Unlike complex LoRaWAN concentrator modules (such as SX1301/SX1308), a simple SX1276/SX1278 module needs to be told exactly for which channel and spreading factor (SF) it should perform channel activity detection (CAD). This works fine when using the module in an end device (node), as then LoRaWAN explicitly defines which combination is to be used. But for a single channel gateway the goal is to listen on all SFs of that single channel.

The strategy to make this work for a simple SX1276/SX1278 module is to first detect a signal on the channel frequency, using RSSI detection in FSK mode.

When a signal is detected, CAD is used to detect a SF7 preamble. If a preamble is detected the message is received using the RX_SINGLE mode of the module. If a preamble is not detected on SF7, CAD is used to detect a SF8 preamble. This is repeated for all spreading factors.

This works because the preamble always uses 8 symbols, and the length of a symbol is dependent on the spreading factor. The next SF's symbol length is twice the length of the previous length.

Detecting a signal using CAD takes less than two symbols. So when a SF7 CAD returns, two symbols of the preamble are 'used', leaving 6 more to synchronize the reading of the message. The two SF7 symbols that are gone, acount for _one_ SF8 symbol. So there are 7 preamble symbols available to detect a SF8 signal. Likewise:

- For a SF9 signal there will be 8 - (1 + 0.5) = 6.5 symbols available
- For a SF10 signal there will be 8 - (1 + 0.5 + 0.25) = 6.25 symbols available
- For a SF11 signal there will be 8 - (1 + 0.5 + 0.25 + 0.125) = 6.125 symbols available
- For a SF12 signal there will be 8 - (1 + 0.5 + 0.25 + 0.125 + 0.0625) = 6.0625 symbols available

So there are always enough preamble symbols left to try to detect a higher SF signal, if the lower SF detection fails.

In order to make this work it is important to detect the presence of a signal on the channel as soon as possible; the RSSI detection in FSK mode can be used to do that. A drawback of this approach is that the range of this gateway will be less of that of a 'real' gateway; it can only receive messages that can be detected by RSSI.

## Hardware
In order to run a LoRaWanGateway you need:

+ An ESP8266 module
+ An SX1276/SX1278 module
+ A way to flash your ESP8266

Connections
<table>
<tr><th>ESP PIN</th><th>SX1276 PIN</th></tr>
<tr><td>D1</td><td>DIO0</td></tr>
<tr><td>D2</td><td>DIO1</td></tr>
<tr><td>D5</td><td>SCK</td></tr>
<tr><td>D6</td><td>MISO</td></tr>
<tr><td>D7</td><td>MOSI</td></tr>
<tr><td>D0</td><td>NSS</td></tr>
<tr><td>GND</td><td>GND</td></tr>
<tr><td>3.3V</td><td>VCC</td></tr>
</table>

## How to run

The LoRaWanGateway needs quite some RAM and processing power, so it it necessary to flash firmware that uses as little resources as possible. 
Therefore you have to build NodeMCU firmware containing only the modules needed. The build I'm using can be found in the firmware directory, along with the NodeMCU flasher application.

+ Use the firmware in the firmware directory

OR

+ Get the latest NodeMCU firmware on https://nodemcu-build.com/
	+ select the dev branch
	+ select the following modules: bit, CJSON, encoder, file, GPIO, net, node, RTC time, SNTP, SPI, timer, UART, WiFi

+ Flash the integer version on your ESP8266
	+ connect your ESP8266 to a serial port
	+ start ESP8266Flasher.exe in the firmware directory
	+ choose the correct serial port
	+ push the Flash button
	
+ Format ESP8266 filesystem
+ Register your wifi network
	+ in the Lua shell run 
		+ wifi.setmode(wifi.STATION)
		+ wifi.sta.config("your SSID","your key")
		+ wifi.sta.autoconnect(1)
		+ wifi.sta.connect()
	+ Your ESP8266 will remember your wifi settings!
+ Upload all files in the src directory to your ESP8266
+ Restart your ESP8266
+ The LoRaWanGateway will start after first compiling all your sources


## Configuration
The LoRaWanGateway is configured to listen for all spreadingsfactors on EU channel 0.

The LoRaWanGateway can be run in two modes
+ Listen to all SF's, signal detection by RSSI
+ Listen to a single SF, lora signal detection
When listening to a single SF, the range of your gateway will increase a lot because messages below the noise floor will be received too.

Changing the configuration can be done in `init.lua`.
<table>
<tr><th>Parameter</th><th>Description</th><th>Default</th></tr>
<tr><td>GW_ROUTER</td><td>Dns name of the router to connect</td><td>router.eu.thethings.network</td></tr>
<tr><td>GW_CH</td><td>Channel to listen to</td><td>0</td></tr>
<tr><td>GW_SF</td><td>SF to listen to</td><td>N/A - listen to all SF's</td></tr>
<tr><td>GW_ALT</td><td>Altitude of your gateway location</td><td>0</td></tr>
<tr><td>GW_LAT</td><td>Latitude of your gateway location</td><td>"0.0"</td></tr>
<tr><td>GW_LON</td><td>Longitude of your gateway location</td><td>"0.0"</td></tr>
<tr><td>GW_NSS</td><td>NSS pin number</td><td>0</td></tr>
<tr><td>GW_DIO0</td><td>DIO0 pin number</td><td>1</td></tr>
<tr><td>GW_DIO1</td><td>DIO1 pin number</td><td>2</td></tr>
</table>

To use the US915 band, change `SX1276.lua` to read:

	local CHN={}
	CHN[0]=chan(902300000,"LoRa",MC1.BW125)
	CHN[1]=chan(902500000,"LoRa",MC1.BW125)
	CHN[2]=chan(902700000,"LoRa",MC1.BW125)
	CHN[3]=chan(902900000,"LoRa",MC1.BW125)
	CHN[4]=chan(903100000,"LoRa",MC1.BW125)
	CHN[5]=chan(903300000,"LoRa",MC1.BW125)
	CHN[6]=chan(903500000,"LoRa",MC1.BW125)
	CHN[7]=chan(903700000,"LoRa",MC1.BW125)
	CHN[8]=chan(903900000,"LoRa",MC1.BW250)
	CHN[9]=chan(904100000,"FSK" ,MC1.BW150)


It will listen to only one specific channel. It will send on whatever channel or datarate the router seems fit...

## Revisions

* 2017-01-26 more accurate time in rxpk message
* 2017-01-16 support for listening on a single SF, drastically increasing range
* 2017-01-15 add documentation [from the TTN forum](https://www.thethingsnetwork.org/forum/t/single-channel-gateway/798/227) and [issue #10](https://github.com/JaapBraam/LoRaWanGateway/issues/10)
* 2017-01-15 fix for initialization using GW_NSS parameter
* 2017-01-15 add firmware directory containing flasher and nodemcu firmware
+ 2017-01-08 change UDP send because latest firmware changed udpsocket.send method.
+ 2016-09-21 add GW_ALT and GW_NSS parameters to init.lua, fix stat message
+ 2016-08-12 measure RSSI in Lora mode, speed up SPI bus, cpufreq 160Mhz
+ 2016-08-08 receive messages on all spreading factors
+ 2016-07-04 changed SX1278 NSS pin to D0
+ 2016-07-03 refactor to use integer version of firmware in order to have more free resources
+ 2016-07-02 initial revision


 



