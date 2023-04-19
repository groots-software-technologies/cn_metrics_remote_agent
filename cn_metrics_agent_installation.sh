#!/usr/bin/env bash
#######################################################
# Program: Cloudnetra Metrics Agent Installation.
#
# Purpose:
#  Monitoring the server health overview.
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

# Usage details
#######################################################

if [ "${1}" = "--help" -o "${#}" != "6" ];
       then
       echo -e "Usage: $SCRIPTNAME -u [CN_METRICS_USERNAME] -p [CN_METRICS_PASSWORD] -o [CN_ORG_ID]

        OPTION          			DESCRIPTION
        -----------------------------------------------------
	--help          		    	Help
	-u [CN_METRICS_USERNAME]		CloudNetra Metrics Username 
	-p [CN_METRICS_PASSWORD] 		CloudNetra Metrics Password
	-o [CN_ORG_ID]				CloudNetra Metrics Organization Id
        -----------------------------------------------------

        Usage: ./$SCRIPTNAME -u john@cloudnetra.io -p StrongPAssWord -o ecd0e2d4-de8f-11ed-b1bf-2bafe6d048ec

Note : [VALUE] must required";
       exit 3;
fi

#######################################################
# Get user-given variables
#######################################################

while getopts "u:p:o:" OPT
do
        case $OPT in
        u) CN_METRICS_USER="$OPTARG" ;;
        p) CN_METRICS_PASSWORD="$OPTARG" ;;
        o) CN_ORG_ID="$OPTARG" ;;
        *) echo "Usage: $SCRIPTNAME -u [CN_METRICS_USERNAME] -p [CN_METRICS_PASSWORD] -o [CN_ORG_ID]"
           exit 3
           ;;
        esac
done

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

# Setup the CN EXPORTER
#######################################################
rm -rf /tmp/node_exporter-*
wget -P /tmp/ https://github.com/prometheus/node_exporter/releases/download/v1.5.0/node_exporter-1.5.0.linux-amd64.tar.gz -o $LOGFILE
tar -xvf /tmp/node_exporter-1.5.0.linux-amd64.tar.gz -C /tmp/ > /dev/null
cp /tmp/node_exporter-1.5.0.linux-amd64/node_exporter /usr/sbin/cn_exporter > /dev/null

echo "Installing and configuration cloudnetra exporter on the $OS_NAME" | log
echo "------------------------------------------------" | log
if [ "$OS_NAME" == "Ubuntu" ];then	
cat > /lib/systemd/system/cn-exporter.service <<-EOF
[Unit]
Description=CN Exporter
After=multi-user.target

[Service]
Type=simple
#User=cn_exporter
ExecStart=/usr/sbin/cn_exporter --web.listen-address=0.0.0.0:9100 --collector.filesystem.mount-points-exclude='^/(sys|proc|dev|host|etc|run|var/lib/docker/.+|var/snap/.+)($|/)' --collector.systemd --collector.processes --collector.os

[Install]
WantedBy=multi-user.target
EOF
else
cat > /usr/lib/systemd/system/cn-exporter.service <<-EOF
[Unit]
Description=CN Exporter
After=multi-user.target

[Service]
Type=simple
#User=cn_exporter
ExecStart=/usr/sbin/cn_exporter --web.listen-address=0.0.0.0:9100 --collector.filesystem.mount-points-exclude='^/(sys|proc|dev|host|etc|run|var/lib/docker/.+|var/snap/.+)($|/)' --collector.systemd --collector.processes --collector.os

[Install]
WantedBy=multi-user.target
EOF

fi

echo "Start the exporter service" | log
echo "------------------------------------------------" | log
systemctl daemon-reload
sleep 0.5
systemctl enable cn-exporter
sleep 0.5
systemctl start cn-exporter
sleep 0.5

echo "Installation and configuration Cloudnetra Collector" | log
echo "------------------------------------------------" | log
if [ "$OS_NAME" == "Ubuntu" ];then

wget -P /tmp/ https://github.com/open-telemetry/opentelemetry-collector-releases/releases/download/v0.75.0/otelcol-contrib_0.75.0_linux_amd64.deb -o $LOGFILE
sleep 0.5
dpkg -i /tmp/otelcol-contrib_0.75.0_linux_amd64.deb > /dev/null 2>&1
sleep 0.5
systemctl disable otelcol-contrib.service > /dev/null 2>&1
sleep 0.5
systemctl stop otelcol-contrib.service > /dev/null 2>&1
systemctl daemon-reload
sleep 0.5

cp /usr/bin/otelcol-contrib /usr/bin/cn-metrics-collector > /dev/null
sleep 0.5
cat > /lib/systemd/system/cn-metrics-collector.service <<-EOF
[Unit]
Description=CloudNetra Metrics Collector
After=network.target

[Service]
ExecStart=/usr/bin/cn-metrics-collector --config=/etc/otelcol-contrib/config.yaml
KillMode=mixed
Restart=on-failure
Type=simple
User=otelcol-contrib
Group=otelcol-contrib

[Install]
WantedBy=multi-user.target
EOF

else
wget -P /tmp/ https://github.com/open-telemetry/opentelemetry-collector-releases/releases/download/v0.75.0/otelcol-contrib_0.75.0_linux_amd64.rpm -o $LOGFILE
sleep 0.5
rpm -i /tmp/otelcol-contrib_0.75.0_linux_amd64.rpm > /dev/null 2>&1
systemctl disable otelcol-contrib.service  > /dev/null 2>&1
sleep 0.5
systemctl stop otelcol-contrib.service > /dev/null 2>&1
systemctl daemon-reload
sleep 0.5

cp /usr/bin/otelcol-contrib /usr/bin/cn-metrics-collector
cat > /usr/lib/systemd/system/cn-metrics-collector.service <<-EOF
[Unit]
Description=CloudNetra Metrics Collector
After=network.target

[Service]
ExecStart=/usr/bin/cn-metrics-collector --config=/etc/otelcol-contrib/config.yaml
KillMode=mixed
Restart=on-failure
Type=simple
User=otelcol-contrib
Group=otelcol-contrib

[Install]
WantedBy=multi-user.target
EOF

fi

echo "Cloudnetra collector configuration file setup" | log
echo "------------------------------------------------" | log
cp /etc/otelcol-contrib/config.yaml /etc/otelcol-contrib/config.yaml_original > /dev/null
echo > /etc/otelcol-contrib/config.yaml > /dev/null
cat > /etc/otelcol-contrib/config.yaml <<-EOF
extensions:
  health_check:
  pprof:
  zpages:
  memory_ballast:
    size_mib: 128
  basicauth/gc_auth:
    client_auth:
       username: $CN_METRICS_USER
       password: $CN_METRICS_PASSWORD

receivers:
  otlp:
    protocols:
      grpc:
      http:
  opencensus:
  filelog:
    include:
      - /var/log/*.log
    include_file_path: true
    operators:
      - type: move
        from: attributes["log.file.name"]
        to: attributes["log_file_name"]
      - type: move
        from: attributes["log.file.path"]
        to: attributes["log_file_path"]
    attributes:
      type: agent-linux
  prometheus:
    config:
      scrape_configs:
        - job_name: 'cn-metrics-exporter'
          honor_timestamps: false
          scrape_interval: 30s
          static_configs:
            - targets: ['127.0.0.1:9100']

processors:
  memory_limiter:
    check_interval: 5s
    limit_mib: 512
    spike_limit_mib: 256
  batch:
    send_batch_size: 100
    send_batch_max_size: 500
    timeout: 30s
  resource:
    attributes:
      - key: host.id
        from_attribute: host.name
        action: upsert
  resourcedetection/system:
    detectors: ["env", "system"]
    system:
      hostname_sources: ["os"]
  attributes/agent:
    actions:
      - key: gmetrics_agent_version
        value: v1.0.0
        action: insert
      - key: org_id
        value: $CN_ORG_ID
        action: insert
      - key: host.id
        from_attribute: host.name
        action: insert

exporters:
  logging:
    loglevel: info
  prometheusremotewrite:
    endpoint: https://beta-listener.cloudnetra.io
    auth:
      authenticator: basicauth/gc_auth
    #headers:
      #Authorization: Bearer DbWAMaaCJIbZvJaeuvdGhgyJMfVBDnFT
    resource_to_telemetry_conversion:
      enabled: true
    retry_on_failure:
      enabled: true
      initial_interval: 5s
      max_interval: 10s
      max_elapsed_time: 30s
    timeout: 30s

service:
  pipelines:
    #logs:
    #receivers:
    metrics:
      receivers:
        - prometheus
      processors: [ memory_limiter, batch, resource, resourcedetection/system, attributes/agent ]
      exporters:
        - prometheusremotewrite
  telemetry:
    logs:
      level: "info"
    metrics:
      level: detailed
      address: localhost:8888

  extensions: [health_check, pprof, zpages, basicauth/gc_auth]
EOF

echo "Cloudnetra Metrics Collector Service Starting" | log
echo "------------------------------------------------" | log
systemctl daemon-reload

systemctl enable cn-metrics-collector.service
sleep 0.5
systemctl start cn-metrics-collector.service
sleep 0.5
systemctl restart cn-metrics-collector.service

rm -rf /tmp/node_exporter-*
rm -rf /tmp/otelcol-contrib*

echo "Cloudnetra Metrics Collector Agent Successfully Installed" | log
echo "Please install dashboard and start your monitoring" | log
echo "------------------------------------------------" | log

# END MAIN LOGIC
#######################################################
