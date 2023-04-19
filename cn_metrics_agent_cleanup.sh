#!/bin/bash
#######################################################
# Program: Cloudnetra Metrics Agent Un-Installation.
#
# Purpose:
#  Remove the server health monitoring agent.
#  can be run in interactive.
#
# License:
#  This program is distributed in the hope that it will be useful,
#  but under groots software technologies @rights.
#
#######################################################

#Set script name
#######################################################
SCRIPTNAME=`basename $0`

# OS NAME DETECT
#######################################################
OS_NAME=`cat /etc/os-release | grep -w "NAME=" | awk -F '=' '{print $2}' | sed 's/"//g'`

# Logfile
#######################################################

LOGDIR="/var/log/cn_metrics/"
LOGFILE=$LOGDIR/"$SCRIPTNAME".log

if [ ! -d $LOGDIR ]
then
        mkdir -p $LOGDIR
elif [ ! -f $LOGFILE ]
then
        touch $LOGFILE
fi

# Logger function
#######################################################

log () {
        while read line; do echo "[`date +"%Y-%m-%dT%H:%M:%S,%N" | rev | cut -c 7- | rev`][$SCRIPTNAME]: $line"| tee -a $LOGFILE 2>&1 ; done
}

# MAIN LOGIC
#######################################################

echo "Stopping the cloudnetra agent service exporter" | log
echo "------------------------------------------------" | log
systemctl stop cn-exporter
sleep 0.5
systemctl disable cn-exporter
sleep 0.5
systemctl daemon-reload
sleep 0.5

echo "Cloudnetra application un-installation agent exporter" | log
echo "------------------------------------------------" | log
rm -rf /usr/sbin/cn_exporter
rm -rf /lib/systemd/system/cn-exporter.service

echo "Stopping cloudnetra remote agent collector" | log
echo "------------------------------------------------" | log
systemctl disable cn-metrics-collector.service
sleep 0.5
systemctl stop cn-metrics-collector.service
sleep 0.5
systemctl daemon-reload

echo "Cloudnetra remote agent collector un-installation" | log
echo "------------------------------------------------" | log

if [ "$OS_NAME" == "Ubuntu" ];then
	apt-get remove otelcol-contrib -y > /dev/null 2>&1
else
	rpm -e otelcol-contrib > /dev/null 2>&1
fi

echo "Cloudnetra remote agent collector temporary files" | log
echo "------------------------------------------------" | log
rm -rf /etc/otelcol-contrib/
rm -rf /lib/systemd/system/cn-metrics-collector.service

# END MAIN LOGIC
#######################################################
