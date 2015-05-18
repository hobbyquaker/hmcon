#!/bin/bash

VERSION=0.3

USER=hmcon
PREFIX=/opt/hmcon
VAR=$PREFIX/var
ETC=$PREFIX/etc

echo ""
echo "  Hmcon Setup $VERSION"
echo "  ---------------"
echo ""

if [ "$(id -u)" != "0" ]; then
   echo "This script must be run as root" 1>&2
   exit 1
fi

command -v git >/dev/null 2>&1 || { echo >&2 "git required, but it's not installed.  Aborting."; exit 1; }
command -v node >/dev/null 2>&1 || { echo >&2 "node required, but it's not installed.  Aborting."; exit 1; }
command -v npm >/dev/null 2>&1 || { echo >&2 "npm required, but it's not installed.  Aborting."; exit 1; }

mkdir -p $ETC >/dev/null 2>&1
mkdir -p $VAR >/dev/null 2>&1
mkdir -p $PREFIX/bin >/dev/null 2>&1

echo "$PREFIX/lib/" > /etc/ld.so.conf.d/hm.conf

echo "PATH=\$PATH:$PREFIX/bin" > /etc/profile.d/hm.sh
echo "export PATH" >> /etc/profile.d/hm.sh
chmod a+x /etc/profile.d/hm.sh
/etc/profile.d/hm.sh

if id -u "$USER" >/dev/null 2>&1; then
        echo "User $USER already exists"
else
        echo "Adding user $USER"
        useradd -r -s /bin/false $USER
fi

ARCH=`arch`

mkdir -p $PREFIX/src/occu >/dev/null 2>&1
if [ -d "$PREFIX/src/occu/.git" ]; then
    cd $PREFIX/src/occu
    echo "Pull https://github.com/eq-3/occu"
    git checkout master
    git pull $PREFIX/src/occu
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
        apt-get install libusb-1.0-0:i386
    else
        apt-get install libusb-1.0-0
    fi
fi


mkdir -p $VAR >/dev/null 2>&1
cp -R $PREFIX/src/occu/firmware $PREFIX/


function rfd {

    # FIXME RFD.handler path
    touch /var/RFD.handlers
    chown $USER.$USER /var/RFD.handlers


    # FIXME crypttool.cfg
    mkdir -p /etc/config >/dev/null 2>&1
    chown $USER.$USER /etc/config

    mkdir -p $ETC/rfd >/dev/null 2>&1
    mkdir -p $VAR/rfd/devices >/dev/null 2>&1
    mkdir -p $PREFIX/bin >/dev/null 2>&1
    cp $SRC/RFD/bin/rfd $PREFIX/bin/
    cp $SRC/RFD/bin/SetInterfaceClock $PREFIX/bin/
    cp $SRC/RFD/bin/avrprog $PREFIX/bin/
    cp $SRC/RFD/bin/crypttool $PREFIX/bin/


    # Install libs
    cp -R $SRC/RFD/lib $PREFIX/
    ldconfig

    # Config file
cat > $ETC/rfd.conf <<- EOM
Listen Port = 2001
Log Destination = File
Log Filename = $VAR/rfd/rfd.log
Log Identifier = rfd
Log Level = 1
Persist Keys = 1
# PID File = $VAR/rfd/rfd.pid
# UDS File = $VAR/rfd/socket_rfd
Device Description Dir = $VAR/firmware/rftypes
Device Files Dir = $VAR/rfd/devices
Key File = $VAR/rfd/keys
Address File = $VAR/rfd/ids
Firmware Dir = $PREFIX/firmware
Replacemap File = $PREFIX/firmware/rftypes/replaceMap/rfReplaceMap.xml
EOM

    function rfdInterface {
        i=0
        ADD=1
        while [ $ADD -gt 0  ];
        do


            PS3="Choose BidCos-RF interface $i type: "
            options=("Serial" "USB" "HM-CFG-LAN" "HM-LGW-O-TW-W-EU" "cancel")

            select opt in "${options[@]}"
            do

                case $opt in
                    "Serial")
cat >> $ETC/rfd.conf <<- EOM
[Interface $i]
Type = CCU2
ComPortFile = /dev/ttyAPP0
AccessFile = /dev/null
ResetFile = /dev/ccu2-ic200
EOM
                        i=`expr $i + 1`
                        break
                        ;;
                    "USB")
                        echo -n "Input serial number: "
                        read SERIAL
cat >> $ETC/rfd.conf <<- EOM
[Interface $i]
Type = USB Interface
Serial Number = $SERIAL
EOM
                        i=`expr $i + 1`
                        break
                        ;;
                    "HM-CFG-LAN")
                        echo -n "Input serial number: "
                        read SERIAL
                        echo -n "Input encryption key: "
                        read KEY
cat >> $ETC/rfd.conf <<- EOM
[Interface $i]
Type = Lan Interface
Serial Number = $SERIAL
Encryption Key = $KEY
EOM
                        i=`expr $i + 1`
                        break
                        ;;
                    "HM-LGW-O-TW-W-EU")
                        echo -n "Input serial number: "
                        read SERIAL
                        echo -n "Input encryption key: "
                        read KEY
cat >> $ETC/rfd.conf <<- EOM
[Interface $i]
Type = HMLGW2
Description = HM-LGW-O-TW-W-EU
Serial Number = $SERIAL
Encryption Key = $KEY
EOM
                        i=`expr $i + 1`
                        break
                        ;;
                    "cancel")
                        break
                        ;;
                    *)
                        echo "invalid option"
                        ;;
                esac
            done

            read -p "Add another rf interface (y/N)? " choice
            case "$choice" in
                y|Y )
                    ;;
                * )
                    ADD=0
                    ;;
            esac
        done
    }
    rfdInterface


    read -p "Install startscript /etc/init.d/rfd (Y/n)? " choice
    case "$choice" in
         n|N )
            ADD=0
            ;;
        * )

cat > /etc/init.d/rfd <<- EOM
#! /bin/sh
### BEGIN INIT INFO
# Provides:          skeleton
# Required-Start:    \$remote_fs $syslog
# Required-Stop:     \$remote_fs $syslog
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


            ;;
    esac

}

function hs485d {

    mkdir -p $PREFIX/bin >/dev/null 2>&1


    # Install binaries
    mkdir -p $PREFIX/bin >/dev/null 2>&1
    cp -R $SRC/HS485D/bin $PREFIX/

    # Install libs
    cp -Rn $SRC/HS485D/lib $PREFIX/
    echo "$PREFIX/lib/" > /etc/ld.so.conf.d/hm.conf
    ldconfig

    echo "Configure BidCos-Wired interface:"
    echo -n "Input serial number: "
    read SERIAL
    echo -n "Input encryption key: "
    read KEY
    echo -n "Input IP-Address: "
    read IP

cat > $ETC/hs485d.conf <<- EOM
Listen Port = 2000
Log Destination = Syslog
Log Identifier = hs485d
[Interface 0]
Type = HMWLGW
Serial Number = $SERIAL
Encryption Key = $KEY
IP Address = $IP
EOM

}

function manager {
    cd $PREFIX
    npm install homematic-manager

    read -p "Install startscript /etc/init.d/hm-manager (Y/n)? " choice
    case "$choice" in
         n|N )
            ADD=0
            ;;
        * )

cat > /etc/init.d/hm-manager <<- EOM
#! /bin/sh
### BEGIN INIT INFO
# Provides:          skeleton
# Required-Start:    \$remote_fs $syslog
# Required-Stop:     \$remote_fs $syslog
# Default-Start:     2 3 4 5
# Default-Stop:      0 1 6
# Short-Description: Homematic Manager
# Description:       Homematic Webinterface
### END INIT INFO

# Author: Sebastian 'hobbyquaker' Raff <hq@ccu.io>

PATH=/sbin:/usr/sbin:/bin:/usr/bin:/opt/hm/bin:/opt/hm/node_modules/.bin
DESC="Homematic Webinterface"
NAME=hm-manager
DAEMON=$PREFIX/node_modules/.bin/\$NAME
DAEMON_ARGS=""
PIDFILE=$VAR/hm-manager/\$NAME.pid
SCRIPTNAME=/etc/init.d/\$NAME
USER=$USER

[ -x "\$DAEMON" ] || exit 0

. /lib/init/vars.sh

. /lib/lsb/init-functions

sudo -u $USER $PREFIX/node_modules/.bin/\$NAME $1

:
EOM
        chmod a+x /etc/init.d/hm-manager
        update-rc.d hm-manager defaults


            ;;
    esac

}

read -p "Install rfd (Y/n)? " choice
case "$choice" in
    n|N ) ;;
    * ) rfd;;
esac

# Todo hs485d tests and startscript
#read -p "Install hs485d (y/N)? " choice
#case "$choice" in
#    y|Y ) hs485d;;
#    * ) ;;
#esac

read -p "Install Homematic Manager (Y/n)? " choice
case "$choice" in
    n|N ) ;;
    * ) manager;;
esac

# FIXME ugly
chown -R $USER.$USER $PREFIX
chown -R $USER.$USER $VAR
chown -R $USER.$USER $ETC

echo ""
echo "Setup done."
echo "-----------"
echo "Configuration files are located in $ETC"

read -p "Start rfd now (Y/n)? " choice
case "$choice" in
    n|N ) ;;
    * )
        /etc/init.d/rfd restart
    ;;
esac

read -p "Start Homematic Manager now (Y/n)? " choice
case "$choice" in
    n|N ) ;;
    * )
        /etc/init.d/hm-manager restart
    ;;
esac
