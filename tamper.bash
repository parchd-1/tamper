#!/bin/bash

# Tamper: Boot and MBR tamper checker
# Copyright © 2016 parchd

# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.

# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.

# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.


VERSION=0.1

TAMPER_DIR="/var/lib/tamper"
BOOT_LOG="$TAMPER_DIR/boot"
MBR_LOG="$TAMPER_DIR/mbr"

MBR_DEVICE=""
SMS_TO=""
CLOCKWORK_KEY=""

function get_mbr(){
        dd if=$MBR_DEVICE of=/tmp/mbr.bak bs=512 count=1
}

function get_boot(){
        tar -c /boot --exclude /boot/grub/grubenv -f /tmp/boot.bak
}

function check_mbr(){
        if [ -z $MBR_DEVICE ]; then
                echo "\$MBR_DEVICE not configured" >&2
                exit 9
        fi

        if [ -e $MBR_LOG ]; then
                get_mbr &&
                sha512sum --check --status --strict <(tail -n1 $MBR_LOG)
        else
                echo "'$MBR_LOG' does not exist" >&2
                return 1
        fi
}

function check_boot(){
        if [ -e $BOOT_LOG ]; then
                get_boot &&
                sha512sum --check --status --strict <(tail -n1 $BOOT_LOG)
        else
                echo "'$BOOT_LOG' does not exist" >&2
                return 1
        fi
}

function check() {
        s=0
        if check_mbr; then
                rm /tmp/mbr.bak
        else
                echo "MBR did not validate!" >&2
                s=1
        fi

        if check_boot; then
                rm /tmp/boot.bak
        else
                echo "/boot did not validate!" >&2
                s=1
        fi

        return $s
}

function fail(){
        (
        echo "Warning: boot or MBR tampering detected" >> /etc/motd &&
        if [ -z "$CLOCKWORK_KEY" ] & [ -z "$SMS_TO" ]; then
                curl "https://api.clockworksms.com/http/send.aspx?key=$CLOCKWORK_KEY&to=$SMS_TO&content=Boot+tampering+detected+on+$HOST"
        fi
        ) || exit 5
		exit 3
}

function update(){
        mkdir -p $TAMPER_DIR &&
        if ! check_mbr; then
                if ! [ -e /tmp/mbr.bak ]; then
                        get_mbr
                fi
                sha512sum /tmp/mbr.bak >> $MBR_LOG
                mv /tmp/mbr.bak $TAMPER_DIR
                echo "Updated mbr"
        else
                echo "MBR already up to date"
                rm /tmp/mbr.bak
        fi

        if ! check_boot; then
                if ! [ -e /tmp/boot.bak ]; then
                        get_boot
                fi
                sha512sum /tmp/boot.bak >> $BOOT_LOG
                mv /tmp/boot.bak $TAMPER_DIR
                echo "Updated boot"
        else
                echo "/boot already up to date"
                rm /tmp/boot.bak
        fi
}

case $1 in
        "--help" ) ;&
        "-h" )
                echo "Options:
   --update (-u): update the tamper database
   --check (-c): check the tamper database and perform fail actions
   --pretend (-p): check the tamper database, but just echo what would be done
   --version (-v): print the version
   --help (-h): print this help message"
                ;;
        "--update" ) ;&
        "-u" )
                update &&
                echo "Updated"
                ;;
        "--check" ) ;&
        "-c" )
                check || fail
                ;;
		"--pretend") ;&
		"-p" )
                check || (s=$?; echo "Failed! Would run:"; declare -f fail >&2; exit $s)
				;;
		"--version") ;&
		"-v" )
                echo $VERSION
				;;
esac

exit $?
