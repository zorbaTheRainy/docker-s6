#!/command/execlineb -P
with-contenv

# Change to the working directory
cd /srv

# Run Caddy with the specified configuration
/usr/bin/caddy run --config /etc/caddy/Caddyfile --adapter caddyfile

