# Hmcon

Homematic Funk-/Wired-Schnittstellen-Software

![architecture](img/hmcon-current.png)

Hmcon dient als Schnittstelle zwischen Smarthome-Software (wie z.B. hm2mqtt, ioBroker oder OpenHAB) und Homematic Funk-
und Wired-Geräten. Hierfür kommen die Schnittstellenprozesse "rfd" und "hs485d" zum Einsatz, die
[eQ-3](http://www.eq-3.de) als Teil der [OCCU](https://github.com/eq-3/occu) in Binärform unter der
["HMSL" Lizenz](https://github.com/eq-3/occu/blob/master/LicenseDE.txt) zur Verfügung stellt. Auf die Logikschicht
"ReGa" und das HomeMatic WebUI wird bewusst verzichtet, Hmcon nutzt den
[Homematic Manager](https://github.com/hobbyquaker/homematic-manager) als Weboberfläche zur Verwaltung von Geräten und
Direktverknüpfungen.


## Installation

#### Voraussetzungen

Bisher auf folgenden Betriebssystemen getestet:

* Debian Wheezy (armhf)
* Debian Jessie (armhf)
* Ubuntu 14.04 (amd64)

Um Hmcon auf einem 64Bit Betriebssystem auszuführen siehe
https://www.thomas-krenn.com/de/wiki/Debian_7_32bit_Libraries oder http://askubuntu.com/questions/454253/how-to-run-32-bit-app-in-ubuntu-64-bit.


Hmcon benötigt (falls man den Homematic Manager nutzen will) eine [Nodejs](https://nodejs.org/) Installation:
Empfohlene Vorgehensweise:

* Auf aktuellen Raspberrys (Pi2/3) und auf x86/amd64 Plattformen kann das offizielle Repository von nodesource.com genutzt werden:
```
curl -sL https://deb.nodesource.com/setup_4.x | sudo -E bash -
sudo apt-get install -y nodejs build-essential
```

* Leider funktioniert der Build von nodesource.com Für alte Raspberrys (Pi1, Model B) nicht. Ein funktionierenden Build für ARMv6 gibt es auf https://github.com/nathanjohnson320/node_arm
```
wget http://node-arm.herokuapp.com/node_latest_armhf.deb
sudo dpkg -i node_latest_armhf.deb
```

* Ein weiterer komfortabler Weg Nodejs zu installieren ist auch das Tool [n](https://github.com/tj/n) - besonders zu empfehlen wenn man (gleichzeitig) mit unterschiedlichen Nodejs Versionen arbeiten muss.

#### Installation von Hmcon

Hmcon wird mit einem interaktiven Shell-Script installiert, dass die benötigten Software-Komponenten herunterlädt sowie
Konfigurationsdateien und Startscripte anlegt.

```Shell
wget https://raw.githubusercontent.com/hobbyquaker/hmcon/master/hmcon-setup.sh -O hmcon-setup.sh
sudo chmod a+x hmcon-setup.sh
sudo ./hmcon-setup.sh
```

Updates können ebenfalls mit hmcon-setup.sh durchgeführt werden.


#### Migration von einer CCU2

Ein Tool um CCU2-Backups in Hmcon einzuspielen steht hier zur Verfügung: https://github.com/hobbyquaker/hmcon-restore

## Lizenzen


### hmcon-setup.sh

[MIT](http://de.wikipedia.org/wiki/MIT-Lizenz)

### Homematic Manager

Copyright (c) 2014, 2015 Anli, Hobbyquaker

[CC BY-NC-SA 4.0](http://creativecommons.org/licenses/by-nc-sa/4.0/)

### OCCU

[eQ-3](http://www.eq-3.de) [HMSL](https://github.com/eq-3/occu/blob/master/LicenseDE.txt)
