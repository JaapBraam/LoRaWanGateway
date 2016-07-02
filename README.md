# LoRaWanGateway
A LoRaWan Gateway in LUA
## Goals
+ Port the OneChannelGateway to NodeMCU/LUA (https://github.com/things4u/ESP-1ch-Gateway) - Done!
+ Add support for sending messages to nodes - Done!
+ Add support for receiving multiple SF's on a channel
+ Add support for more than one channel

## Why LUA?
Lua is an event driven language, which is a good match for a gateway: a gateway has to respond to incoming messages from nodes and routers.
The LoraWanGateway runs on a ESP8266 chip, with the NodeMCU firmware it runs a full WiFi stack and a lua interpreter. The NodeMCU contains a 
lot of libraries that are usefull for a gateway: NTP support, 6 timers, json support etc. 

## Hardware
In order to run a LoRaWanGateway you need
+ A ESP8266 module
+ A SX1278 module
+ A way to flash your ESP8266

Connections
ESP PIN | SX1276 PIN
--- | ---
D1 | DIO0
D2 | DIO1
D5 | SCK
D6 | MISO
D7 | MOSI
D8 | NSS
GND | GND
3.3V | VCC

## How to run
+ Get the NodeMCU firmware on http://nodemcu-build.com/index.php 
	+ select the dev branch
	+ select the following modules: bit,cjson,encoder,file,gpio,net,node,rtctime,sntp,spi,tmr,uart,wifi
+ Flash the float version on your ESP8266
+ Format ESP8266 filesystem
+ Register your wifi network
	+ In the lua shell run 
		+ wifi.setmode(wifi.STATION)
		+ wifi.sta.config("<your SSID>","<your key>")
		+ wifi.sta.autoconnect(1)
		+ wifi.sta.connect()
	+ Your ESP8266 will remember your wifi settings!
+ Upload all files in the src directory to your ESP8266
+ Restart your ESP8266
+ The LoRaWanGateway will start after first compiling all your sources

The LoRaWanGateway is configured to listen on EU channel 0, SF7BW125




 



