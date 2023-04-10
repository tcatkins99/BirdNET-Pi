#!/usr/bin/env -S sudo -E sh
# Altered from raspi-config tool below
# https://github.com/RPi-Distro/birdnet-pi-config
#
# See LICENSE file for copyright and license details
# Copyright (c) 2012 Alex Bradbury <asb@asbradbury.org>
set -x
birdnetpi_dir=/home/pi/BirdNET-Pi
birders_config=${birdnetpi_dir}/Birders_Guide_Installer_Configuration.txt
branch=forms
INTERACTIVE=True
ASK_TO_REBOOT=0
BLACKLIST=/etc/modprobe.d/raspi-blacklist.conf
CONFIG=/boot/config.txt

USER=${SUDO_USER:-$(who -m | awk '{ print $1 }')}

is_pi () {
  ARCH=$(dpkg --print-architecture)
  if [ "$ARCH" = "armhf" ] || [ "$ARCH" = "arm64" ] ; then
    return 0
  else
    return 1
  fi
}

if is_pi ; then
  CMDLINE=/boot/cmdline.txt
else
  CMDLINE=/proc/cmdline
fi

is_pione() {
   if grep -q "^Revision\s*:\s*00[0-9a-fA-F][0-9a-fA-F]$" /proc/cpuinfo; then
      return 0
   elif grep -q "^Revision\s*:\s*[ 123][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F]0[0-36][0-9a-fA-F]$" /proc/cpuinfo ; then
      return 0
   else
      return 1
   fi
}

is_pitwo() {
   grep -q "^Revision\s*:\s*[ 123][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F]04[0-9a-fA-F]$" /proc/cpuinfo
   return $?
}

is_pizero() {
   grep -q "^Revision\s*:\s*[ 123][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F]0[9cC][0-9a-fA-F]$" /proc/cpuinfo
   return $?
}

is_pifour() {
   grep -q "^Revision\s*:\s*[ 123][0-9a-fA-F][0-9a-fA-F]3[0-9a-fA-F][0-9a-fA-F][0-9a-fA-F]$" /proc/cpuinfo
   return $?
}

get_pi_type() {
   if is_pione; then
      echo 1
   elif is_pitwo; then
      echo 2
   else
      echo 0
   fi
}

is_live() {
    grep -q "boot=live" $CMDLINE
    return $?
}

is_ssh() {
  if pstree -p | egrep --quiet --extended-regexp ".*sshd.*\($$\)"; then
    return 0
  else
    return 1
  fi
}

is_fkms() {
  if grep -s -q okay /proc/device-tree/soc/v3d@7ec00000/status \
                     /proc/device-tree/soc/firmwarekms@7e600000/status \
                     /proc/device-tree/v3dbus/v3d@7ec04000/status; then
    return 0
  else
    return 1
  fi
}

is_pulseaudio() {
  PS=$(ps ax)
  echo "$PS" | grep -q pulseaudio
  return $?
}

has_analog() {
  if [ $(get_leds) -eq -1 ] ; then
    return 0
  else
    return 1
  fi
}

is_installed() {
    if [ "$(dpkg -l "$1" 2> /dev/null | tail -n 1 | cut -d ' ' -f 1)" != "ii" ]; then
      return 1
    else
      return 0
    fi
}

deb_ver () {
  ver=`cat /etc/debian_version | cut -d . -f 1`
  echo $ver
}

calc_wt_size() {
  # NOTE: it's tempting to redirect stderr to /dev/null, so supress error 
  # output from tput. However in this case, tput detects neither stdout or 
  # stderr is a tty and so only gives default 80, 24 values
  WT_HEIGHT=18
  WT_WIDTH=$(tput cols)

  if [ -z "$WT_WIDTH" ] || [ "$WT_WIDTH" -lt 60 ]; then
    WT_WIDTH=80
  fi
  if [ "$WT_WIDTH" -gt 178 ]; then
    WT_WIDTH=120
  fi
  WT_MENU_HEIGHT=$(($WT_HEIGHT-7))
}

do_change_pass() {
  whiptail --msgbox "You will now be asked to enter a new password for the $USER user" 20 60 1
  passwd $USER &&
  whiptail --msgbox "Password changed successfully" 20 60 1
}

do_configure_keyboard() {
  printf "Reloading keymap. This may take a short while\n"
  if [ "$INTERACTIVE" = True ]; then
    dpkg-reconfigure keyboard-configuration
  else
    local KEYMAP="$1"
    sed -i /etc/default/keyboard -e "s/^XKBLAYOUT.*/XKBLAYOUT=\"$KEYMAP\"/"
    dpkg-reconfigure -f noninteractive keyboard-configuration
  fi
  invoke-rc.d keyboard-setup start
  setsid sh -c 'exec setupcon -k --force <> /dev/tty1 >&0 2>&1'
  udevadm trigger --subsystem-match=input --action=change
  return 0
}

do_change_locale() {
  dpkg-reconfigure locales && \
    ASK_TO_REBOOT=2 && return 0
}

do_change_timezone() {
  dpkg-reconfigure tzdata && \
    return 0
}

get_wifi_country() {
  CODE=${1:-0}
  IFACE="$(list_wlan_interfaces | head -n 1)"
  if [ -z "$IFACE" ]; then
    whiptail --msgbox "No wireless interface found" 20 60
    return 1
  fi
  if ! wpa_cli -i "$IFACE" status > /dev/null 2>&1; then
    whiptail --msgbox "Could not communicate with wpa_supplicant" 20 60
    return 1
  fi
  wpa_cli -i "$IFACE" save_config > /dev/null 2>&1
  COUNTRY="$(wpa_cli -i "$IFACE" get country)"
  if [ "$COUNTRY" = "FAIL" ]; then
    return 1
  fi
  if [ $CODE = 0 ]; then
    echo "$COUNTRY"
  fi
  return 0
}

do_wifi_country() {
  IFACE="$(list_wlan_interfaces | head -n 1)"
  if [ -z "$IFACE" ]; then
    whiptail --msgbox "No wireless interface found" 20 60
    return 1
  fi

  if ! wpa_cli -i "$IFACE" status > /dev/null 2>&1; then
    whiptail --msgbox "Could not communicate with wpa_supplicant" 20 60
    return 1
  fi

  oIFS="$IFS"
  value=$(cat /usr/share/zoneinfo/iso3166.tab | tail -n +26 | tr '\t' '/' | tr '\n' '/')
  IFS="/"
  COUNTRY=$(whiptail --menu "Select the country in which the Pi is to be used" 20 60 10 ${value} 3>&1 1>&2 2>&3)
  if [ $? -eq 0 ];then
    wpa_cli -i "$IFACE" set country "$COUNTRY"
    wpa_cli -i "$IFACE" save_config > /dev/null 2>&1
    if iw reg set "$COUNTRY" 2> /dev/null; then
        ASK_TO_REBOOT=1
    fi
    if hash rfkill 2> /dev/null; then
      rfkill unblock wifi
      if is_pi ; then
        for filename in /var/lib/systemd/rfkill/*:wlan ; do
          echo 0 > $filename
        done
      fi
    fi
    whiptail --msgbox "Wireless LAN country set to $COUNTRY" 20 60 1
  fi
  IFS=$oIFS
}

get_labels_lang() {
  oIFS="$IFS"
  value=$(cat ${birdnetpi_dir}/model/labels_lang.txt | tr ',' ' ' | tr '\n' ' ')
  IFS=" "
  get_lang=$(whiptail --menu "Select the file that corresponds to your language" 20 60 10 ${value} 3>&1 1>&2 2>&3)
  labels_lang=$(awk -F, "/$get_lang/{print \$2}" ${birdnetpi_dir}/model/labels_lang.txt)
  if [ $? -eq 0 ];then
    whiptail --msgbox "Your installation will now use $labels_lang" 20 60 1
    mv ${birdnetpi_dir}/model/labels.txt ${birdnetpi_dir}/model/labels.txt.old
    unzip ${birdnetpi_dir}/model/labels_l18n.zip ${labels_lang} -d ${birdnetpi_dir}/model
    mv ${birdnetpi_dir}/model/${labels_lang} ${birdnetpi_dir}/model/labels.txt
  fi
  IFS=$oIFS
}

get_ssh() {
  if service ssh status | grep -q inactive; then
    echo 1
  else
    echo 0
  fi
}

do_ssh() {
  if [ -e /var/log/regen_ssh_keys.log ] && ! grep -q "^finished" /var/log/regen_ssh_keys.log; then
    whiptail --msgbox "Initial ssh key generation still running. Please wait and try again." 20 60 2
    return 1
  fi
  DEFAULT=--defaultno
  if [ $(get_ssh) -eq 0 ]; then
    DEFAULT=
  fi
  whiptail --yesno \
    "Would you like the SSH server to be enabled?\n\nCaution: Default and weak passwords are a security risk when SSH is enabled!" $DEFAULT 20 60 2
  RET=$?
  if [ $RET -eq 0 ]; then
    ssh-keygen -A &&
    update-rc.d ssh enable &&
    invoke-rc.d ssh start &&
    STATUS=enabled
  elif [ $RET -eq 1 ]; then
    update-rc.d ssh disable &&
    invoke-rc.d ssh stop &&
    STATUS=disabled
  else
    return $RET
  fi
  whiptail --msgbox "The SSH server is $STATUS" 20 60 1
}

get_vnc() {
  if systemctl status vncserver-x11-serviced.service  | grep -q -w active; then
    echo 0
  else
    echo 1
  fi
}

do_config_zram() {
  if [ -e /etc/udev/rules.d/99-zram.rules ]; then
    ## get current swap allocation from /etc/udev/rules.d/99-zram.rules
    size="$(awk -F\" '{print $4}' /etc/udev/rules.d/99-zram.rules)"
  else
    size="4G"
  fi
  new_size=$(whiptail --inputbox "How much memory (G) should the zRAM swap partition have? Choose 1G, 2G, or 4G - 4G recommended" \
  19 70 -- "$size" 3>&1 1>&2 2>&3)
  if [ $? -eq 0 ];then
    return 0
    ASK_TO_REBOOT=2
  else
    return 1
  fi
}

do_install_zram() {
  echo "Configuring zram.service"
  touch /etc/modules-load.d/zram.conf
  echo 'zram' > /etc/modules-load.d/zram.conf
  touch /etc/modprobe.d/zram.conf
  echo 'options zram num_devices=1' > /etc/modprobe.d/zram.conf
  touch /etc/udev/rules.d/99-zram.rules
  echo "KERNEL==\"zram0\", ATTR{disksize}=\"${new_size}\",TAG+=\"systemd\"" \
    > /etc/udev/rules.d/99-zram.rules
  touch /etc/systemd/system/zram.service
  echo "Installing zram.service"
  cat << EOF > /etc/systemd/system/zram.service
[Unit]
Description=Swap with zram
After=multi-user.target

[Service]
Type=oneshot
RemainAfterExit=true
ExecStartPre=/sbin/mkswap /dev/zram0
ExecStart=/sbin/swapon /dev/zram0
ExecStop=/sbin/swapoff /dev/zram0

[Install]
WantedBy=multi-user.target
EOF
  systemctl enable zram
  if [ $? -eq 0 ];then
    return 0
    ASK_TO_REBOOT=2
  else
    return 1
  fi
}

do_zram_menu() {
  whiptail --yesno "Would like to enable the zram swapping kernel module?" --defaultno 20 60 2
  RET=$?
  if [ $RET -eq 0 ]; then
    do_config_zram
    do_install_zram
    STATUS=enabled
  elif [ $RET -eq 1 ]; then
    if [ -e /etc/udev/rules.d/99-zram.rules ];then
      systemctl disable --now zram
    fi
    STATUS=disabled
  fi
  whiptail --msgbox "ZRAM swapping is $STATUS" 20 60 1
  return $RET
}

do_vnc() {
  DEFAULT=--defaultno
  if [ $(get_vnc) -eq 0 ]; then
    DEFAULT=
  fi
  whiptail --yesno "Would you like the VNC Server to be enabled?" $DEFAULT 20 60 2
  RET=$?
  if [ $RET -eq 0 ]; then
    if is_installed realvnc-vnc-server || apt-get install realvnc-vnc-server; then
      systemctl enable vncserver-x11-serviced.service &&
      systemctl start vncserver-x11-serviced.service &&
      STATUS=enabled
    else
      return 1
    fi
  elif [ $RET -eq 1 ]; then
    if is_installed realvnc-vnc-server; then
        systemctl disable vncserver-x11-serviced.service
        systemctl stop vncserver-x11-serviced.service
    fi
    STATUS=disabled
  else
    return $RET
  fi
  whiptail --msgbox "The VNC Server is $STATUS" 20 60 1
}

do_audio() {
  if is_pulseaudio ; then
    oIFS="$IFS"
    list=$(sudo -u $SUDO_USER XDG_RUNTIME_DIR=/run/user/$SUDO_UID pacmd list-sources | grep -B1 -e 'alsa.card_name' -e 'name.*input' | grep -A4 index | sed -e s/*//g | sed s/^[' '\\t]*//g | grep -e index -e card_name | sed s/'index: '//g | sed s/'alsa.card_name = '//g | sed s/\"//g | tr '\n' '\/')
    if ! [ -z "$list" ] ; then
      IFS="/"
      AUDIO_IN=$(whiptail --menu "Choose the audio input" 20 60 10 ${list} 3>&1 1>&2 2>&3)
      return 0
    else
      whiptail --msgbox "No internal audio devices found" 20 60 1
      return 1
    fi
    if [ $? -eq 0 ]; then
      sudo -u $SUDO_USER XDG_RUNTIME_DIR=/run/user/$SUDO_UID pactl set-default-source "$AUDIO_IN"
    fi
    IFS=$oIFS
    fi
    sudo -u $SUDO_USER pulseaudio -k
}

list_wlan_interfaces() {
  for dir in /sys/class/net/*/wireless; do
    if [ -d "$dir" ]; then
      basename "$(dirname "$dir")"
    fi
  done
}

do_wifi_ssid_passphrase() {
  RET=0
  IFACE_LIST="$(list_wlan_interfaces)"
  IFACE="$(echo "$IFACE_LIST" | head -n 1)"

  if [ -z "$IFACE" ]; then
    whiptail --msgbox "No wireless interface found" 20 60
    return 1
  fi

  if ! wpa_cli -i "$IFACE" status > /dev/null 2>&1; then
    whiptail --msgbox "Could not communicate with wpa_supplicant" 20 60
    return 1
  fi

  if [ -z "$(get_wifi_country)" ]; then
    do_wifi_country
  fi

  SSID="$1"
  while [ -z "$SSID" ] ; do
    SSID=$(whiptail --inputbox "Please enter SSID" 20 60 3>&1 1>&2 2>&3)
    if [ $? -ne 0 ]; then
      return 0
    elif [ -z "$SSID" ]; then
      whiptail --msgbox "SSID cannot be empty. Please try again." 20 60
    fi
  done

  PASSPHRASE="$2"
  PASSPHRASE=$(whiptail --passwordbox "Please enter passphrase. Leave it empty if none." 20 60 3>&1 1>&2 2>&3)
  if [ $? -ne 0 ]; then
    return 0
  else
    return 1
  fi

  # Escape special characters for embedding in regex below
  local ssid="$(echo "$SSID" \
   | sed 's;\\;\\\\;g' \
   | sed -e 's;\.;\\\.;g' \
         -e 's;\*;\\\*;g' \
         -e 's;\+;\\\+;g' \
         -e 's;\?;\\\?;g' \
         -e 's;\^;\\\^;g' \
         -e 's;\$;\\\$;g' \
         -e 's;\/;\\\/;g' \
         -e 's;\[;\\\[;g' \
         -e 's;\];\\\];g' \
         -e 's;{;\\{;g'   \
         -e 's;};\\};g'   \
         -e 's;(;\\(;g'   \
         -e 's;);\\);g'   \
         -e 's;";\\\\\";g')"

  wpa_cli -i "$IFACE" list_networks \
   | tail -n +2 | cut -f -2 | grep -P "\t$ssid$" | cut -f1 \
   | while read ID; do
    wpa_cli -i "$IFACE" remove_network "$ID" > /dev/null 2>&1
  done

  ID="$(wpa_cli -i "$IFACE" add_network)"
  wpa_cli -i "$IFACE" set_network "$ID" ssid "\"$SSID\"" 2>&1 | grep -q "OK"
  RET=$((RET + $?))

  if [ -z "$PASSPHRASE" ]; then
    wpa_cli -i "$IFACE" set_network "$ID" key_mgmt NONE 2>&1 | grep -q "OK"
    RET=$((RET + $?))
  else
    wpa_cli -i "$IFACE" set_network "$ID" psk "\"$PASSPHRASE\"" 2>&1 | grep -q "OK"
    RET=$((RET + $?))
  fi

  if [ $RET -eq 0 ]; then
    wpa_cli -i "$IFACE" enable_network "$ID" > /dev/null 2>&1
  else
    wpa_cli -i "$IFACE" remove_network "$ID" > /dev/null 2>&1
    whiptail --msgbox "Failed to set SSID or passphrase" 20 60
  fi
  wpa_cli -i "$IFACE" save_config > /dev/null 2>&1

  echo "$IFACE_LIST" | while read IFACE; do
    wpa_cli -i "$IFACE" reconfigure > /dev/null 2>&1
  done

  return $RET
}

do_reget_birdnetpi_urls() {
  birdnetpi_url=$(whiptail --inputbox "Put your domain here. Example: \"https://birdnetpi.pmcgui.xyz\"." \
  19 70 -- "https://" 3>&1 1>&2 2>&3) extractionlog_url=$(whiptail --inputbox "Put your domain here. Example: \"https://extractionlog.pmcgui.xyz\"." 19 70 -- "https://" 3>&1 1>&2 2>&3) birdnetlog_url=$(whiptail --inputbox "Put your domain here. Example: \"https://birdnetlog.pmcgui.xyz\"." 19 70 -- "https://" 3>&1 1>&2 2>&3) ${birdnetpi_dir}/scripts/rewrite_config.sh
  if [ $? -eq 0 ];then
    return 0
  else
    return 1
  fi
}

do_reget_db_pwd() {
  db_pwd=$(whiptail --inputbox "Please set the password the 'birder' user will use to access the database." \
  19 70 3>&1 1>&2 2>&3) ${birdnetpi_dir}/scripts/rewrite_config.sh
  if [ $? -eq 0 ];then
    return 0
    ASK_TO_REBOOT=2
  else
    return 1
  fi
}

do_reget_birdweather_id() {
  birdweather_id=$(whiptail --inputbox "Input your BirdWeather ID" \
  19 70 3>&1 1>&2 2>&3) ${birdnetpi_dir}/scripts/rewrite_config.sh
  if [ $? -eq 0 ];then
    return 0
    ASK_TO_REBOOT=2
  else
    return 1
  fi
}


do_reget_caddy_pwd() {
  caddy_pwd=$(whiptail --inputbox "Please set the password for the web interface." \
  19 70 3>&1 1>&2 2>&3) ${birdnetpi_dir}/scripts/rewrite_config.sh
  if [ $? -eq 0 ];then
    return 0
    ASK_TO_REBOOT=2
  else
    return 1
  fi
}


do_reget_lon() {
  lon="$(curl -s4 ifconfig.co/json | awk '/lon/ {print $2}' | tr -d ',')"
  new_lon=$(whiptail --inputbox "Please set the longitude where recordings will take place." \
  19 70 -- "$lon" 3>&1 1>&2 2>&3) ${birdnetpi_dir}/scripts/rewrite_config.sh
  if [ $? -eq 0 ];then
    return 0
    ASK_TO_REBOOT=2
  else
    return 1
  fi
}

do_reget_lat() {
  lat="$(curl -s4 ifconfig.co/json | awk '/lat/ {print $2}' | tr -d ',')"
  new_lat=$(whiptail --inputbox "Please set the latitude where recordings will take place." \
  19 70 -- "$lat" 3>&1 1>&2 2>&3) ${birdnetpi_dir}/scripts/rewrite_config.sh
  if [ $? -eq 0 ];then
    return 0
    ASK_TO_REBOOT=2
  else
    return 1
  fi
}

do_get_confidence() {
  confidence="$(awk -F= '/CONFIDENCE=/ {print $2}' ${birdnetpi_dir}/birdnet.conf)"
  new_confidence=$(whiptail --inputbox "Please set the minimum confidence score BirdNET-Lite should use." \
  19 70 -- "$confidence" 3>&1 1>&2 2>&3) ${birdnetpi_dir}/scripts/rewrite_config.sh
  if [ $? -eq 0 ];then
    return 0
    ASK_TO_REBOOT=2
  else
    return 1
  fi
}


do_get_overlap() {
  overlap="$(awk -F= '/OVERLAP=/ {print $2}' ${birdnetpi_dir}/birdnet.conf)"
  new_overlap=$(whiptail --inputbox "Please set the overlap BirdNET-Lite should use." \
  19 70 -- "$overlap" 3>&1 1>&2 2>&3) ${birdnetpi_dir}/scripts/rewrite_config.sh
  if [ $? -eq 0 ];then
    return 0
    ASK_TO_REBOOT=2
  else
    return 1
  fi
}


do_get_sensitivity() {
  sensitivity="$(awk -F= '/SENSITIVITY=/ {print $2}' ${birdnetpi_dir}/birdnet.conf)"
  new_sensitivity=$(whiptail --inputbox "Please set the simoid sensitivty BirdNET-Lite should use." \
  19 70 -- "$sensitivity" 3>&1 1>&2 2>&3) ${birdnetpi_dir}/scripts/rewrite_config.sh
  if [ $? -eq 0 ];then
    return 0
    ASK_TO_REBOOT=2
  else
    return 1
  fi
}

do_get_birdnetlog_url() {
  birdnetlog_url=$(whiptail --inputbox "Put your domain here. Example: \"https://birdnetlog.pmcgui.xyz\"." \
  19 70 -- "https://" 3>&1 1>&2 2>&3) ${birdnetpi_dir}/scripts/write_config.sh
  if [ $? -eq 0 ];then
    return 0
    ASK_TO_REBOOT=2
  else
    return 1
  fi
}

do_get_extractionlog_url() {
  extractionlog_url=$(whiptail --inputbox "Put your domain here. Example: \"https://extractionlog.pmcgui.xyz\"." \
  19 70 -- "https://" 3>&1 1>&2 2>&3) ${birdnetpi_dir}/scripts/write_config.sh
  if [ $? -eq 0 ];then
    return 0
    ASK_TO_REBOOT=2
  else
    return 1
  fi
}

do_get_birdnetpi_url() {
  birdnetpi_url=$(whiptail --inputbox "Put your domain here. Example: \"https://birdnetpi.pmcgui.xyz\"." \
  19 70 -- "https://" 3>&1 1>&2 2>&3) ${birdnetpi_dir}/scripts/write_config.sh
  if [ $? -eq 0 ];then
    return 0
    ASK_TO_REBOOT=2
  else
    return 1
  fi
}

do_get_birdweather_id() {
  birdweather_id=$(whiptail --inputbox "Input your BirdWeather ID" \
  19 70 3>&1 1>&2 2>&3) ${birdnetpi_dir}/scripts/write_config.sh
  if [ $? -eq 0 ];then
    return 0
    ASK_TO_REBOOT=2
  else
    return 1
  fi
}

do_get_db_pwd() {
  db_pwd=$(whiptail --inputbox "Please set the password the 'birder' user will use to access the database." \
  19 70 3>&1 1>&2 2>&3) ${birdnetpi_dir}/scripts/write_config.sh
  if [ $? -eq 0 ];then
    return 0
    ASK_TO_REBOOT=2
  else
    return 1
  fi
}

do_get_ice_pwd() {
  ice_pwd=$(whiptail --inputbox "Please set the password for the live stream." \
  19 70 3>&1 1>&2 2>&3) ${birdnetpi_dir}/scripts/write_config.sh
  if [ $? -eq 0 ];then
    return 0
    ASK_TO_REBOOT=2
  else
    return 1
  fi
}

do_get_caddy_pwd() {
  caddy_pwd=$(whiptail --inputbox "Please set the password for the web interface." \
  19 70 3>&1 1>&2 2>&3) ${birdnetpi_dir}/scripts/write_config.sh
  if [ $? -eq 0 ];then
    return 0
    ASK_TO_REBOOT=2
  else
    return 1
  fi
}


do_get_lon() {
  lon="$(curl -s4 ifconfig.co/json | awk '/lon/ {print $2}' | tr -d ',')"
  new_lon=$(whiptail --inputbox "Please set the longitude where recordings will take place." \
  19 70 -- "$lon" 3>&1 1>&2 2>&3) ${birdnetpi_dir}/scripts/write_config.sh
  if [ $? -eq 0 ];then
    return 0
    ASK_TO_REBOOT=2
  else
    return 1
  fi
}

do_get_lat() {
  lat="$(curl -s4 ifconfig.co/json | awk '/lat/ {print $2}' | tr -d ',')"
  new_lat=$(whiptail --inputbox "Please set the latitude where recordings will take place." \
  19 70 -- "$lat" 3>&1 1>&2 2>&3) ${birdnetpi_dir}/scripts/write_config.sh
  if [ $? -eq 0 ];then
    return 0
    ASK_TO_REBOOT=2
  else
    return 1
  fi
}

do_update_os() {
  apt update && apt -y full-upgrade && \
    ASK_TO_REBOOT=1
}

do_update_birdnet() {
  sudo -E -upi ${birdnetpi_dir}/scripts/update_birdnet.sh
}

do_install_birdnet() {
  sudo -E -upi ${birdnetpi_dir}/Birders_Guide_Installer.sh && \
    ASK_TO_REBOOT=1
}

insist_on_reboot() {
  if [ $ASK_TO_REBOOT -eq 2 ]; then
    whiptail --yesno "You really should reboot. Do that now?" 20 60 2
    if [ $? -eq 0 ]; then # yes
      sync
      reboot
    fi
  fi
}

do_finish() {
  if [ $ASK_TO_REBOOT -eq 1 ]; then
    whiptail --yesno "Would you like to reboot now?" 20 60 2
    if [ $? -eq 0 ]; then # yes
      sync
      reboot
    fi
  elif [ $ASK_TO_REBOOT -eq 2 ]; then
    whiptail --yesno "You really should reboot. Do that now?" 20 60 2
    if [ $? -eq 0 ]; then # yes
      sync
      reboot
    fi
  fi
  exit 0
}

# Everything else needs to be run as root
if [ $(id -u) -ne 0 ]; then
  printf "Script must be run as root. Try 'sudo birdnet-pi-config'\n"
  exit 1
fi

do_advanced_reconfig_menu() {
  MENU=9
  while [ $MENU -eq 9 ];do
    if is_pi ; then
      FUN=$(whiptail --title "BirdNET-Pi Software Configuration Tool (birdnet-pi-config)" --menu "BirdNET-Pi Configuration Options" $WT_HEIGHT $WT_WIDTH $WT_MENU_HEIGHT --cancel-button Back --ok-button Select \
        "Sensitivity" "Set the sigmoid sensitivity" \
        "Confidence" "Set the minimum confidence score required for a detection" \
        "Overlap" "Set the analysis overlap in seconds" \
        "BirdNET-Pi URLs" "Set the URLs your installation should use" \
        3>&1 1>&2 2>&3)
    else
        exit
    fi
    RET=$?
    if [ $RET -eq 1 ]; then
      return 0
      MENU=0
    elif [ $RET -eq 0 ]; then
      case "$FUN" in
        Sens*) do_get_sensitivity;;
        Confi*) do_get_confidence;;
        Overlap*) do_get_overlap;;
        Bird*) do_reget_birdnetpi_urls;;
        *) whiptail --msgbox "Programmer error: unrecognized option" 20 60 1 ;;
      esac || whiptail --msgbox "There was an error running option $FUN" 20 60 1
    fi
  done
}

do_interface_menu() {
  MENU=6
  while [ $MENU -eq 6 ];do
    if is_pi ; then
      FUN=$(whiptail --title "BirdNET-Pi Software Configuration Tool (birdnet-pi-config)" --menu "Interfacing Options" $WT_HEIGHT $WT_WIDTH $WT_MENU_HEIGHT --cancel-button Back --ok-button Select \
        "SSH" "Enable/disable remote command line access using SSH" \
        "VNC" "Enable/disable graphical remote access using RealVNC" \
        3>&1 1>&2 2>&3)
    else
        exit
    fi
    RET=$?
    if [ $RET -eq 1 ]; then
      return 0
      MENU=0
    elif [ $RET -eq 0 ]; then
      case "$FUN" in
        SSH*) do_ssh ;;
        VNC*) do_vnc ;;
        *) whiptail --msgbox "Programmer error: unrecognized option" 20 60 1 ;;
      esac || whiptail --msgbox "There was an error running option $FUN" 20 60 1
    fi
  done
}

do_advanced_config_menu() {
  MENU=5
  while [ $MENU -eq 5 ];do
    if is_pi ; then
      FUN=$(whiptail --title "BirdNET-Pi Software Configuration Tool (birdnet-pi-config)" --menu "BirdNET-Pi Configuration Options" $WT_HEIGHT $WT_WIDTH $WT_MENU_HEIGHT --cancel-button Back --ok-button Select \
        "Sensitivity" "Set the sigmoid sensitivity" \
        "Confidence" "Set the minimum confidence score required for a detection" \
        "Overlap" "Set the analysis overlap in seconds" \
        "BirdNET-Pi URLs" "Set the URLs your installation should use" \
        3>&1 1>&2 2>&3)
    else
        exit
    fi
    RET=$?
    if [ $RET -eq 1 ]; then
      return 0
      MENU=0
    elif [ $RET -eq 0 ]; then
      case "$FUN" in
        Sens*) do_get_sensitivity;;
        Confi*) do_get_confidence;;
        Overlap*) do_get_overlap;;
        Bird*) do_get_birdnetpi_url; do_get_birdnetlog_url; do_get_extractionlog_url;;
        *) whiptail --msgbox "Programmer error: unrecognized option" 20 60 1 ;;
      esac || whiptail --msgbox "There was an error running option $FUN" 20 60 1
    fi
  done
}

do_system_menu() {
  MENU=4
  while [ $MENU -eq 4 ];do
    if is_pi ; then
      FUN=$(whiptail --title "BirdNET-Pi Software Configuration Tool (birdnet-pi-config)" --menu "System Options" $WT_HEIGHT $WT_WIDTH $WT_MENU_HEIGHT --cancel-button Back --ok-button Select \
        "Password" "Change password for the '$USER' user" \
        "Audio" "Select audio device you'd like BirdNET-Pi to use" \
        "Wireless LAN" "Enter SSID and passphrase" \
        "Update the OS" "Update the underlying operating system" \
        "Interface Options" "Enable/Disable SSH and VNC" \
        "Configure zRAM" "Enable/Disable zRAM" \
        "Timezone" "Configure time zone" \
        "Keyboard" "Set keyboard layout to match your keyboard" \
        "WLAN Country" "Set legal wireless channels for your country" \
        3>&1 1>&2 2>&3)
    else
        exit
    fi
    RET=$?
    if [ $RET -eq 1 ]; then
      return 0
      MENU=0
    elif [ $RET -eq 0 ]; then
      case "$FUN" in
        Password*) do_change_pass ;;
        Audio*) do_audio ;;
        Wireless*) do_wifi_ssid_passphrase ;;
        Update*) do_update_os ;;
        Interface*) do_interface_menu ;;
        Configure*) do_zram_menu ;;
        Time*) do_change_timezone; insist_on_reboot ;;
        Key*) do_configure_keyboard ;;
        WLAN*) do_wifi_country ;;
        *) whiptail --msgbox "Programmer error: unrecognized option" 20 60 1 ;;
      esac || whiptail --msgbox "There was an error running option $FUN" 20 60 1
    fi
  done
}


do_reconfig_birdnet_menu() {
  MENU=3
  while [ $MENU -eq 3 ];do
    if is_pi ; then
      FUN=$(whiptail --title "BirdNET-Pi Software Configuration Tool (birdnet-pi-config)" --menu "BirdNET-Pi Re-configuration Options" $WT_HEIGHT $WT_WIDTH $WT_MENU_HEIGHT --cancel-button Back --ok-button Select \
        "Latitude " "Set the latitude your system should use" \
        "Longitude" "Set the longitude your system should use" \
        "Caddy Password" "Set the web interface password" \
        "Database Password" "Set the password BirdNET-Pi will use to access the DB" \
        "BirdWeather ID" "Input your BirdWeather ID if you have one" \
        "Advanced Settings" "Sensitivity, Overlap, Confidence, URLs" \
        3>&1 1>&2 2>&3)
    else
        exit
    fi
    RET=$?
    if [ $RET -eq 1 ]; then
      return 0
      MENU=0
    elif [ $RET -eq 0 ]; then
      case "$FUN" in
        Lat*) do_reget_lat;;
        Lon*) do_reget_lon;;
        Cad*) do_reget_caddy_pwd;;
        Data*) do_reget_db_pwd;;
        Bird*) do_reget_birdweather_id;;
        Advanced*) do_advanced_reconfig_menu;;
        *) whiptail --msgbox "Programmer error: unrecognized option" 20 60 1 ;;
      esac || whiptail --msgbox "There was an error running option $FUN" 20 60 1
    fi
  done
}

do_config_birdnet_menu() {
  MENU=2
  while [ $MENU -eq 2 ];do
    if is_pi ; then
      FUN=$(whiptail --title "BirdNET-Pi Software Configuration Tool (birdnet-pi-config)" --menu "BirdNET-Pi Configuration Options" $WT_HEIGHT $WT_WIDTH $WT_MENU_HEIGHT --cancel-button Back --ok-button Select \
        "Latitude " "Set the latitude your system should use" \
        "Longitude" "Set the longitude your system should use" \
        "Caddy Password" "Set the web interface password" \
        "IceCast2 Password" "Set the IceCast2 password" \
        "Database Password" "Set the password BirdNET-Pi will use to access the DB" \
        "BirdWeather ID" "Input your BirdWeather ID if you have one" \
        "Set Custom URLS" "Designate custom URLs for the web services if you've set that up" \
        3>&1 1>&2 2>&3)
    else
        exit
    fi
    RET=$?
    if [ $RET -eq 1 ]; then
      return 0
      MENU=0
    elif [ $RET -eq 0 ]; then
      case "$FUN" in
        Lat*) do_get_lat;;
        Lon*) do_get_lon;;
        Cad*) do_get_caddy_pwd;;
        Ice*) do_get_ice_pwd;;
        Data*) do_get_db_pwd;;
        Bird*) do_get_birdweather_id;;
        Set*) do_get_birdnetpi_url; do_get_birdnetlog_url; do_get_extractionlog_url;;
        *) whiptail --msgbox "Programmer error: unrecognized option" 20 60 1 ;;
      esac || whiptail --msgbox "There was an error running option $FUN" 20 60 1
    fi
  done
}

do_internationalisation_menu() {
  MENU=1
  while [ $MENU -eq 1 ];do
    FUN=$(whiptail --title "BirdNET-Pi Software Configuration Tool (birdnet-pi-config)" --menu "Localisation Options" $WT_HEIGHT $WT_WIDTH $WT_MENU_HEIGHT --cancel-button Back --ok-button Select \
      "System Locale" "Configure the system language and regional settings" \
      "labels.txt" "Set the language to use for species detection" \
      "Time Zone" "Set the Time Zone" \
      3>&1 1>&2 2>&3)
    RET=$?
    if [ $RET -eq 1 ]; then
      return 0
      MENU=0
    elif [ $RET -eq 0 ]; then
      case "$FUN" in
        System*) do_change_locale;;
        label*) get_labels_lang;;
        Time*) do_change_timezone;;
        *) whiptail --msgbox "Programmer error: unrecognized option" 20 60 1 ;;
      esac || whiptail --msgbox "There was an error running option $FUN" 20 60 1
    fi
  done
}



#
# Interactive use loop
#
[ -e $CONFIG ] || touch $CONFIG
calc_wt_size
while [ "$USER" = "root" ] || [ -z "$USER" ]; do
  if ! USER=$(whiptail --inputbox "birdnet-pi-config could not determine the default user.\\n\\nWhat user should these settings apply to?" 20 60 pi 3>&1 1>&2 2>&3); then
    return 0
  fi
done
while true; do
  FUN=$(whiptail --title "BirdNET-Pi Software Configuration Tool (birdnet-pi-config)" --backtitle "$(cat /proc/device-tree/model)" --menu "Setup Options" $WT_HEIGHT $WT_WIDTH $WT_MENU_HEIGHT --cancel-button Finish --ok-button Select \
    "Step 1" "Configure language and timezone" \
    "Step 2" "Configure BirdNET-Pi before installation" \
    "Step 3" "Install BirdNET-Pi" \
    "Step 4" "Reconfigure BirdNET-Pi AFTER installation" \
    "Step 5" "Update BirdNET-Pi (run this if you changed URLs)" \
    "System Options" "Configure system settings" \
    3>&1 1>&2 2>&3)
  RET=$?
  if [ $RET -eq 1 ]; then
    do_finish
  elif [ $RET -eq 0 ]; then
    case "$FUN" in
      *1) do_internationalisation_menu ;;
      *2) do_config_birdnet_menu ;;
      *3) do_install_birdnet;;
      *4) do_reconfig_birdnet_menu ;;
      *5) do_update_birdnet;;
      Sys*) do_system_menu ;;
      *) whiptail --msgbox "Programmer error: unrecognized option" 20 60 1 ;;
    esac || whiptail --msgbox "There was an error running option $FUN" 20 60 1
  fi
done
