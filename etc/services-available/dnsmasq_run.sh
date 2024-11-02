#!/command/execlineb -P
with-contenv

# Run the webproc command with the specified configuration
/usr/local/bin/webproc --configuration-file /etc/dnsmasq.conf -- dnsmasq --no-daemon