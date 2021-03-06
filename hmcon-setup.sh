#!/bin/bash

VERSION=0.18

USER=hmcon
PREFIX=/opt/hmcon
VAR=$PREFIX/var
ETC=$PREFIX/etc

ASK_TO_REBOOT=0

if [ "$(id -u)" != "0" ]; then
   echo "This script must be run as root" 1>&2
   exit 1
fi

whiptail --msgbox "Hmcon Setup $VERSION" 20 72

command -v git >/dev/null 2>&1 || { apt-get install git; }

mkdir -p $ETC >/dev/null 2>&1
mkdir -p $VAR/log >/dev/null 2>&1
mkdir -p $VAR/firmware >/dev/null 2>&1
mkdir -p $PREFIX/lib >/dev/null 2>&1
mkdir -p $PREFIX/bin >/dev/null 2>&1

echo "{\"version\":\"$VERSION\"}" > $PREFIX/hmcon.json

echo "$PREFIX/lib/" > /etc/ld.so.conf.d/hm.conf

echo "PATH=\$PATH:$PREFIX/bin" > /etc/profile.d/hm.sh
echo "export PATH" >> /etc/profile.d/hm.sh
chmod a+x /etc/profile.d/hm.sh
/etc/profile.d/hm.sh

if [ -f "/etc/init.d/rfd" ]; then
    /etc/init.d/rfd stop
fi
if [ -f "/etc/init.d/hs485d" ]; then
    /etc/init.d/hs485d stop
fi
if [ -f "/etc/init.d/hm-manager" ]; then
    /etc/init.d/hm-manager stop
fi



if id -u "$USER" >/dev/null 2>&1; then
    usermod -s /bin/false -d $PREFIX $USER
else
    echo "Adding user $USER"
    useradd -r -s /bin/false -d $PREFIX $USER
fi

ARCH=`arch`

mkdir -p $PREFIX/src/occu >/dev/null 2>&1
if [ -d "$PREFIX/src/occu/.git" ]; then
    cd $PREFIX/src/occu
    echo "Pull https://github.com/eq-3/occu"
    git checkout master
    git pull
else
    echo "Clone https://github.com/eq-3/occu"
    git clone https://github.com/eq-3/occu $PREFIX/src/occu
fi

echo "Checking libs"
if [[ "$ARCH" == "arm"* ]]; then
    SRC=$PREFIX/src/occu/arm-gnueabihf/packages-eQ-3
    apt-get install libusb-1.0-0
else
    SRC=$PREFIX/src/occu/X86_32_Debian_Wheezy/packages-eQ-3
    if [[ "$ARCH" == "x86_64" ]]; then
        apt-get install libc6:i386 libstdc++6:i386
        apt-get install libusb-1.0-0:i386
    else
        apt-get install libusb-1.0-0
    fi
fi


cp -R $PREFIX/src/occu/firmware $PREFIX/
cp $SRC/LinuxBasis/bin/eq3configcmd $PREFIX/bin/
cp $SRC/LinuxBasis/lib/libeq3config.so $PREFIX/lib/

rfd() {

    mkdir -p $VAR/rfd/devices >/dev/null 2>&1
    mkdir -p $PREFIX/bin >/dev/null 2>&1

    # use rfd from 2.27.7 occu (classic rfd without HmIP Support - not crRFD, no multimacd)
    cd $PREFIX/src/occu
		echo "checking out OCCU 2.27.7"
    git checkout 532edbdf01dae7a595323a318711e14853124539 .

    cp $SRC/RFD/bin/rfd $PREFIX/bin/
    cp $SRC/RFD/bin/SetInterfaceClock $PREFIX/bin/
    cp $SRC/RFD/bin/avrprog $PREFIX/bin/

    echo "checking out OCCU head"
    git reset --hard


    # Install libs
    cp -R $SRC/RFD/lib $PREFIX/
    ldconfig

    # Config file
    rfdInterface() {
        i=0
        ADD=1
        while [ $ADD -gt 0  ];
        do
            opt=$(whiptail --radiolist test 20 60 4 "HM-MOD-RPI-PCB" "HM-MOD-RPI-PCB" "HM-MOD-RPI-PCB" "HM-CFG-USB-2" "HM-CFG-USB-2" "HM-CFG-USB-2" "HM-CFG-LAN" "HM-CFG-LAN" "HM-CFG-LAN" "HM-LGW-O-TW-W-EU" "HM-LGW-O-TW-W-EU" "HM-LGW-O-TW-W-EU" 3>&1 1>&2 2>&3)
            exitstatus=$?
            if [ $exitstatus = 0 ]; then
                case $opt in

                    "HM-MOD-RPI-PCB")

                    #prepare additional snippet for rfd init script
                    SetupGPIO="# export GPIO
if [ ! -d /sys/class/gpio/gpio18 ] ; then
  echo 18 > /sys/class/gpio/export
  echo out > /sys/class/gpio/gpio18/direction
fi
"
                    # disable serial console (code from raspi-config)
                    echo "disabling serial-console"
                    if command -v systemctl > /dev/null && systemctl | grep -q '\-\.mount'; then
                        SYSTEMD=1
                    elif [ -f /etc/init.d/cron ] && [ ! -h /etc/init.d/cron ]; then
                        SYSTEMD=0
                    else
                        echo "[Warning] Unrecognised init system"
                    fi

                    if [ $SYSTEMD -eq 0 ]; then
                        sed -i /etc/inittab -e "s|^.*:.*:respawn:.*ttyAMA0|#&|"
                    fi
                    sed -i /boot/cmdline.txt -e "s/console=ttyAMA0,[0-9]\+ //"
                    sed -i /boot/cmdline.txt -e "s/console=serial0,[0-9]\+ //"
                    ASK_TO_REBOOT=1

                    # allow hmcon gpio access when using HM-MOD-RPI-PCB
                    # if group gpio doesn't exist, creat it and create a corresponding udev-rule
                    if ! grep gpio /etc/group >/dev/null 2>&1; then
                        groupadd gpio
                        UDEVFILE=99-rfd-gpio.rules
                        echo "creating new udev-rule for gpio"
cat > /etc/udev/rules.d/$UDEVFILE <<- EOM
SUBSYSTEM=="gpio*", PROGRAM="/bin/sh -c 'chown -R root:gpio /sys/class/gpio && chmod -R 770 /sys/class/gpio; chown -R root:gpio /sys/devices/virtual/gpio && chmod -R 770 /sys/devices/virtual/gpio; chown -R root:gpio /sys/devices/platform/soc/*.gpio/gpio && chmod -R 770 /sys/devices/platform/soc/*.gpio/gpio'"
EOM
                        if grep "SUBSYSTEM==\"gpio\"" --exclude=$UDEVFILE /etc/udev/rules.d/* >/dev/null 2>&1; then
                            echo ""
                            echo "[WARNING] Another udev-rule for the gpios is already in place and may conflict with the one added here.\r"
                            echo "[WARNING] The rule in question is: "
                            grep "SUBSYSTEM==\"gpio\"" --exclude=$UDEVFILE /etc/udev/rules.d/*
                            echo "[WARNING] Check rfd.log for errors"
                        fi
                        udevadm control --reload-rules
                    fi

                    echo "adding user hmcon to gpio and dialout group"
                    usermod -a -G gpio,dialout $USER
cat >> $ETC/rfd.conf <<- EOM
[Interface $i]
Type = CCU2
ComPortFile = /dev/ttyAMA0
AccessFile = /dev/null
ResetFile = /sys/class/gpio/gpio18/value
EOM
                        i=`expr $i + 1`
                        ;;
                    "HM-CFG-USB-2")
                        SERIAL=$(whiptail --inputbox "\n\nEnter Serial Number" 20 60 "" --title "HM-CFG-USB-2 Serial" 3>&1 1>&2 2>&3)
                        exitstatus=$?
                        if [ $exitstatus != 0 ]; then
                            continue;
                        fi
cat >> $ETC/rfd.conf <<- EOM
[Interface $i]
Type = USB Interface
Serial Number = $SERIAL
EOM
                        # Add UDEV Rule to prevent occupation of USB Interface
                        # FIXME ugly world writeable. Should be USER=\"$USER\" instead of MODE=\"0666\" - but this didn't work with ubuntu
                        echo "SUBSYSTEM==\"usb\", ATTR{idVendor}==\"1b1f\", ATTR{idProduct}==\"c00f\", MODE:=\"0666\"" > /etc/udev/rules.d/homematic.rules
                        echo "SUBSYSTEM==\"usb\", ATTR{idVendor}==\"1b1f\", ATTR{idProduct}==\"c010\", MODE:=\"0666\"" >> /etc/udev/rules.d/homematic.rules

                        i=`expr $i + 1`
                        ;;
                    "HM-CFG-LAN")
                        SERIAL=$(whiptail --inputbox "\n\nEnter Serial Number" 20 60 --title "HM-CFG-LAN Serial" 3>&1 1>&2 2>&3)
                        exitstatus=$?
                        if [ $exitstatus != 0 ]; then
                            continue;
                        fi
                        KEY=$(whiptail --inputbox "\n\nEnter Encryption Key" 20 60 --title "HM-CFG-LAN Key" 3>&1 1>&2 2>&3)
                        exitstatus=$?
                        if [ $exitstatus != 0 ]; then
                            continue;
                        fi
cat >> $ETC/rfd.conf <<- EOM
[Interface $i]
Type = Lan Interface
Serial Number = $SERIAL
Encryption Key = $KEY
EOM
                        i=`expr $i + 1`

                        ;;
                    "HM-LGW-O-TW-W-EU")
                        SERIAL=$(whiptail --inputbox "\n\nEnter Serial Number" 20 60 --title "HM-LGW-O-TW-W-EU Serial" 3>&1 1>&2 2>&3)
                        exitstatus=$?
                        if [ $exitstatus != 0 ]; then
                            continue;
                        fi
                        KEY=$(whiptail --inputbox "\n\nEnter Encryption Key" 20 60 --title "HM-LGW-O-TW-W-EU Key" 3>&1 1>&2 2>&3)
                        exitstatus=$?
                        if [ $exitstatus != 0 ]; then
                            continue;
                        fi

cat >> $ETC/rfd.conf <<- EOM
[Interface $i]
Type = HMLGW2
Description = HM-LGW-O-TW-W-EU
Serial Number = $SERIAL
Encryption Key = $KEY
EOM
                        i=`expr $i + 1`
                        ;;

                esac

            fi

            whiptail --yesno "Add another rf interface" 20 60 2
            if [ $? -eq 0 ]; then # yes
                ADD=1
            else
                ADD=0
            fi

        done

    }

    if [ -f "$ETC/rfd.conf" ]; then
        whiptail --yesno "Keep existing rfd.conf" 20 60 2
        if [ $? -eq 0 ]; then # yes
            NEWRFDCONF=0
        else
            NEWRFDCONF=1
        fi
    else
        NEWRFDCONF=1
    fi

    if [[ "$NEWRFDCONF" -gt 0 ]]; then
        cat > $ETC/rfd.conf <<- EOM
Listen Port = 2001
Log Destination = File
Log Filename = $VAR/log/rfd.log
Log Identifier = rfd
Log Level = 1
Persist Keys = 1
# PID File = $VAR/rfd/rfd.pid
# UDS File = $VAR/rfd/socket_rfd
Device Description Dir = $PREFIX/firmware/rftypes
Device Files Dir = $VAR/rfd/devices
Key File = $VAR/rfd/keys
Address File = $ETC/rfd/ids
Firmware Dir = $PREFIX/firmware
User Firmware Dir = $VAR/firmware
XmlRpcHandlersFile = $VAR/RFD.handlers
Replacemap File = $PREFIX/firmware/rftypes/replaceMap/rfReplaceMap.xml
EOM

        rfdInterface
    fi

    whiptail --yesno "Install startscript /etc/init.d/rfd" 20 60 2
    if [ $? -eq 0 ]; then # yes
cat > /etc/init.d/rfd <<- EOM
#! /bin/sh
### BEGIN INIT INFO
# Provides:          rfd
# Required-Start:    \$remote_fs \$syslog
# Required-Stop:     \$remote_fs \$syslog
# Default-Start:     2 3 4 5
# Default-Stop:      0 1 6
# Short-Description: HomeMatic rfd
# Description:       HomeMatic BidCoS-RF interface process
### END INIT INFO

# Author: Sebastian 'hobbyquaker' Raff <hq@ccu.io>

PATH=/sbin:/usr/sbin:/bin:/usr/bin:/opt/hm/bin
DESC="HomeMatic BidCoS-RF interface process"
NAME=rfd
DAEMON=$PREFIX/bin/\$NAME
DAEMON_ARGS="-f $ETC/rfd.conf -d"
PIDFILE=$VAR/rfd/\$NAME.pid
SCRIPTNAME=/etc/init.d/\$NAME
USER=$USER

[ -x "\$DAEMON" ] || exit 0

. /lib/init/vars.sh

. /lib/lsb/init-functions

$SetupGPIO
case "\$1" in
  start)
    log_daemon_msg "Starting \$DESC" "\$NAME"
    start-stop-daemon --start --quiet -c \$USER --exec \$DAEMON -- \$DAEMON_ARGS
    ;;
  stop)
    log_daemon_msg "Stopping \$DESC" "\$NAME"
    start-stop-daemon -K -q -u \$USER -n \$NAME
    ;;
  status)
    status_of_proc "\$DAEMON" "\$NAME" && exit 0 || exit \$?
    ;;
  *)
    echo "Usage: \$SCRIPTNAME {start|stop|status}" >&2
    exit 3
    ;;
esac

:
EOM
        chmod a+x /etc/init.d/rfd
        update-rc.d rfd defaults
    else
        ADD=0
    fi

}

hs485d() {

    mkdir -p $VAR/hs485d/devices >/dev/null 2>&1
    mkdir -p $PREFIX/bin >/dev/null 2>&1


    # Install binaries
    mkdir -p $PREFIX/bin >/dev/null 2>&1
    cp -R $SRC/HS485D/bin $PREFIX/

    # Install libs
    cp -Rn $SRC/HS485D/lib $PREFIX/
    echo "$PREFIX/lib/" > /etc/ld.so.conf.d/hm.conf
    ldconfig

    if [ -f "$ETC/hs485d.conf" ]; then
        whiptail --yesno "Keep existing hs485d.conf" 20 60 2
        if [ $? -eq 0 ]; then # yes
            NEWHS485DCONF=0
        else
            NEWHS485DCONF=1
        fi
    else
        NEWHS485DCONF=1
    fi

    if [[ "$NEWHS485DCONF" -gt 0 ]]; then

        SERIAL=$(whiptail --inputbox "\n\nEnter Serial Number" 20 60 "" --title "HMW LAN GW Serial" 3>&1 1>&2 2>&3)
        exitstatus=$?
        if [ $exitstatus != 0 ]; then
            return;
        fi
        KEY=$(whiptail --inputbox "\n\nEnter Encryption Key" 20 60 "" --title "HMW LAN GW Serial" 3>&1 1>&2 2>&3)
        exitstatus=$?
        if [ $exitstatus != 0 ]; then
            return;
        fi
        IP=$(whiptail --inputbox "\n\nEnter IP Address" 20 60 "" --title "HMW LAN GW Serial" 3>&1 1>&2 2>&3)
        exitstatus=$?
        if [ $exitstatus != 0 ]; then
            return;
        fi

cat > $ETC/hs485d.conf <<- EOM
Listen Port = 2000

Log Filename = $VAR/log/hs485d.log
Log Identifier = hs485d
Log Level = 1
# PID File = $VAR/hs485d/hs485d.pid
Device Description Dir = $PREFIX/firmware/hs485types
Device Files Dir = $VAR/hs485d/devices
Firmware Dir = $PREFIX/firmware
User Firmware Dir = $VAR/firmware
XmlRpcHandlersFile = $VAR/HS485D.handlers


[Interface 0]
Type = HMWLGW
Serial Number = $SERIAL
Encryption Key = $KEY
#IP Address = $IP
EOM

    fi

    whiptail --yesno "Install startscript /etc/init.d/hs485d" 20 60 2
    if [ $? -eq 0 ]; then # yes
cat > /etc/init.d/hs485d <<- EOM
#! /bin/sh
### BEGIN INIT INFO
# Provides:          hs485d
# Required-Start:    \$remote_fs \$syslog
# Required-Stop:     \$remote_fs \$syslog
# Default-Start:     2 3 4 5
# Default-Stop:      0 1 6
# Short-Description: HomeMatic hs485d
# Description:       HomeMatic BidCoS-RF interface process
### END INIT INFO

# Author: Sebastian 'hobbyquaker' Raff <hq@ccu.io>

PATH=/sbin:/usr/sbin:/bin:/usr/bin:/opt/hm/bin
DESC="HomeMatic BidCoS-RF interface process"
NAME=hs485d
DAEMON=$PREFIX/bin/\$NAME
DAEMON_ARGS="-f $ETC/hs485d.conf -g -i 0"
PIDFILE=$VAR/hs485d/\$NAME.pid
SCRIPTNAME=/etc/init.d/\$NAME
USER=$USER

[ -x "\$DAEMON" ] || exit 0

. /lib/init/vars.sh

. /lib/lsb/init-functions

case "\$1" in
  start)
    log_daemon_msg "Starting \$DESC" "\$NAME"
    start-stop-daemon --start --quiet --background -c \$USER --exec \$DAEMON -- \$DAEMON_ARGS
    ;;
  stop)
    log_daemon_msg "Stopping \$DESC" "\$NAME"
    start-stop-daemon -K -q -u \$USER -n \$NAME
    ;;
  status)
    status_of_proc "\$DAEMON" "\$NAME" && exit 0 || exit \$?
    ;;
  *)
    echo "Usage: \$SCRIPTNAME {start|stop|status}" >&2
    exit 3
    ;;
esac

:
EOM

        chmod a+x /etc/init.d/hs485d
        update-rc.d hs485d defaults

    else
        ADD=0
    fi

}

whiptail --yesno "Install rfd?" 20 60 2
if [ $? -eq 0 ]; then # yes
    RF=1
    rfd
else
    RF=0
fi

whiptail --yesno "Install hs485d?" 20 60 2 --defaultno
if [ $? -eq 0 ]; then # yes
    WIRED=1
    hs485d
else
    WIRED=0
fi

manager() {

    command -v node >/dev/null 2>&1 || { echo >&2 "Error: Homematic Manager install failed. node required, but it's not installed."; return 0; }
    command -v npm >/dev/null 2>&1 || { echo >&2 "Error: Homematic Manager install failed. npm required, but it's not installed."; return 0; }


    cd $PREFIX
    npm cache clean
    npm install homematic-manager
    ln -s $PREFIX/node_modules/.bin/hm-manager $PREFIX/bin/hm-manager >/dev/null 2>&1

    INPUT=$(whiptail --inputbox "\n\nHomematic Manager Webserver Port" 20 60 "8081" --title "Homematic Manager Port" 3>&1 1>&2 2>&3)
    exitstatus=$?
    if [ $exitstatus = 0 ]; then
        PORT=${INPUT:-8081}
        nc -z localhost $PORT
        if [ $? -eq 0 ]; then
                echo "Warning Port $PORT seems to be already in use!"
        fi
        if [ $WIRED -eq 1 ]; then
cat > $PREFIX/etc/hm-manager.json <<- EOM
{
    "webServerPort": $PORT,
    "rpcListenIp": "127.0.0.1",
    "rpcListenPort": "2015",
    "rpcListenPortBin": "2016",
    "daemons": {
        "RF": {
            "type": "BidCos-RF",
            "ip": "127.0.0.1",
            "port": 2001,
            "protocol": "binrpc"
        },
        "Wired": {
            "type": "BidCos-Wired",
            "ip": "127.0.0.1",
            "port": 2000,
            "protocol": "binrpc"
        }
    },
    "language": "de"
}
EOM
        else
cat > $PREFIX/etc/hm-manager.json <<- EOM
{
    "webServerPort": $PORT,
    "rpcListenIp": "127.0.0.1",
    "rpcListenPort": "2015",
    "rpcListenPortBin": "2016",
    "daemons": {
        "RF": {
            "type": "BidCos-RF",
            "ip": "127.0.0.1",
            "port": 2001,
            "protocol": "binrpc"
        }
    },
    "language": "de"
}
EOM
        fi

        chown $USER $PREFIX/etc/hm-manager.json
    else
        return;
    fi

    whiptail --yesno "Install startscript /etc/init.d/hm-manager?" 20 60 2
    if [ $? -eq 0 ]; then # yes

cat > /etc/init.d/hm-manager <<- EOM
#! /bin/sh
### BEGIN INIT INFO
# Provides:          hm-manager
# Required-Start:    \$remote_fs \$syslog
# Required-Stop:     \$remote_fs \$syslog
# Default-Start:     2 3 4 5
# Default-Stop:      0 1 6
# Short-Description: Homematic Manager
# Description:       Homematic Webinterface
### END INIT INFO

# Author: Sebastian 'hobbyquaker' Raff <hq@ccu.io>

PATH=/usr/local/bin:/sbin:/usr/sbin:/bin:/usr/bin:/opt/hm/bin
DESC="Homematic Webinterface"
NAME=hm-manager
DAEMON=$PREFIX/bin/\$NAME
DAEMON_ARGS=""
PIDFILE=$VAR/hm-manager/\$NAME.pid
SCRIPTNAME=/etc/init.d/\$NAME
USER=$USER

[ -x "\$DAEMON" ] || exit 0

. /lib/init/vars.sh

. /lib/lsb/init-functions

sudo -u \$USER $PREFIX/node_modules/.bin/\$NAME \$1

:
EOM
        chmod a+x /etc/init.d/hm-manager
        update-rc.d hm-manager defaults


    else
        ADD=0
    fi

}


whiptail --yesno "Install Homematic Manager?" 20 60 2
if [ $? -eq 0 ]; then # yes
    manager
fi

# FIXME ugly. what if $PREFIX is / ?!?
chown -R $USER.$USER $PREFIX
chown -R $USER.$USER $VAR
chown -R $USER.$USER $ETC

read -d . DEBIAN_VERSION < /etc/debian_version
if (($DEBIAN_VERSION==8)); then  # TODO
    systemctl daemon-reload
fi

if [ -f "$ETC/rfd.conf" ] && [ $ASK_TO_REBOOT -eq 0 ]; then
    whiptail --yesno "Start rfd now?" 20 60 2
    if [ $? -eq 0 ]; then # yes
        /etc/init.d/rfd start
    fi
fi

if [ -f "$ETC/hs485d.conf" ] && [ $ASK_TO_REBOOT -eq 0 ]; then
    whiptail --yesno "Start hs485d now?" 20 60 2
    if [ $? -eq 0 ]; then # yes
        /etc/init.d/hs485d start
    fi
fi

if [ -f "$ETC/hm-manager.json" ] && [ $ASK_TO_REBOOT -eq 0 ]; then
    whiptail --yesno "Start Homematic Manager now?" 20 60 2
    if [ $? -eq 0 ]; then # yes
        /etc/init.d/hm-manager start
        HMMPORTHINT="Homematic Manager listening on http://`hostname`:$PORT/"
    else
        HMMPORTHINT=""
    fi
fi

whiptail --msgbox "Setup done.\n-----------\n\nConfiguration files are located in $ETC\nLogfiles are located in $VAR/log\n$HMMPORTHINT\n\n\n\nHave Fun :-)" 20 60

if [ $ASK_TO_REBOOT -eq 1 ]; then
    whiptail --yesno "Reboot required. Would you like to reboot now?" 20 60 2
    if [ $? -eq 0 ]; then # yes
        shutdown -r now
    fi
fi

