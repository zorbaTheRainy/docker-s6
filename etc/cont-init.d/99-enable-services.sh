#!/usr/bin/with-contenv sh

enable_service() {
  # Example:
  # enable_service "${ENABLE_CADDY}" "caddy" "Caddy reverse proxy"

  # boolean/string:  a flag to enable the service 1 or "true", othersiw disable the service
  local enable_flag="$1"
  # string: the directory name used by the service in /etc/services-available/${service_dir} and /etc/services.d/${service_dir}
  local service_dir="$2"
  # string: just a short description of the service for the log output
  local description="$3"


  # convert int to str
  if [ "${enable_flag}" -eq 1 ] 2>/dev/null; then
    enable_flag="true"
  elif [ "${enable_flag}" -eq 0 ] 2>/dev/null; then
    enable_flag="false"
  fi

  # Convert enable_flag to lowercase for comparison
  enable_flag_lower=$(echo "${enable_flag}" | tr '[:upper:]' '[:lower:]')

  # perform the actual check
  if [ "${enable_flag_lower}" == "true" ]; then
    echo "[enable-services] enabling ${description}"

    # Enable supervised service
    if [ -d /etc/services.d/${service_dir} ]
    then
      echo "[enable-services] ${description} already enabled"
    else
      ln -s /etc/services-available/${service_dir} /etc/services.d/${service_dir}
    fi
  else
    echo "[enable-services] disabled ${description}"
  fi
}

# Example:
# enable_service "${ENABLE_CADDY}" "caddy" "Caddy reverse proxy"

