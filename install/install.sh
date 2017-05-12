#!/usr/bin/env bash
## Heavily referenced pi-hole's install script https://github.com/pi-hole/pi-hole/blob/master/automated%20install/basic-install.sh

set -e

DNSMON_LOCAL_DIR="$(pwd)"

IPV4_ADDRESS=""

# Screen size settings for whiptail
screen_size=$(stty size 2> /dev/null || echo 24 80)
rows=$(echo "${sreen_size}" | awk '{print $1}')
columns=$(echo "${screen_size}" | awk '{print $2}')

r=$((rows / 2))
c=$((columns / 2))
r=$(( r < 20 ? 20 : r ))
c=$(( c < 70 ? 70 : c ))


init_debian() {
    PKG_MANAGER="apt-get"
    UPDATE_PKG_CACHE="wait_dpkg_unlock; ${PKG_MANAGER} update"
    PKG_INSTALL=(${PKG_MANAGER} --yes --no-install-recommends install)
    PKG_COUNT="${PKG_MANAGER} -s -o Debug::NoLocking=true upgrade | grep -c ^Inst || true"

    if ${PKG_MANAGER} install --dry-run iproute2 > /dev/null 2>&1; then
        iproute_pkg="iproute2"
    else
        iproute_pkg="iproute"
    fi

    INSTALLER_DEPS=(apt-utils debconf ${iproute_pkg} whiptail)
    DNSMON_DEPS=(dnsmasq dnsutils sudo)
    DNSMASQ_USER="dnsmasq"

    wait_dpkg_unlock() {
        i=0
        while fuser /var/lib/dpkg/lock > /dev/null 2>&1; do
            sleep 0.5
            ((i=i+1))
        done
        return 0
    }
}

start_service() {
    echo -n "** Starting ${1} service..."
    systemctl restart "${1}" &> /dev/null || true
    echo " done."
}

stop_service() {
    echo -n "** Stoping ${1} service..."
    systemctl stop "${1}" &> /dev/null || true
    echo " done."
}

update_package_cache() {
    echo -n "** Updating package cache..."
    if eval "${UPDATE_PKG_CACHE}" &> /dev/null; then
        echo " done."
    else
        echo -en "\n!! Unable to update package cache."
        return 1
    fi
}

install_dependencies() {
    declare -a argArray1=("${!1}")
    declare -a installArray

    for i in "${argArray1[@]}"; do
        echo -n "** Checking for $i..."
        if dpkg-query -W -f='${Status}' "${i}" 2> /dev/null | grep "ok installed" &> /dev/null; then
            echo " installed."
        else
            echo " added to install list."
            installArray+=("${i}")
        fi
    done
    if [[ ${#installArray[@]} -gt 0 ]]; then
        wait_dpkg_unlock
        debconf-apt-progress -- "${PKG_INSTALL[@]}" "${installArray[@]}"
    fi
}

get_available_interfaces() {
    availableInterfaces=$(ip --oneline link show up | grep -v "lo" | awk '{print $2}' | cut -d':' -f1 | cut -d'@' -f1)
}

choose_interface() {
    local interfacesArray=()
    local interfaceCount
    local chooseInterfaceCmd
    local chooseInterfaceOptions
    local firstLoop=1

    interfaceCount=$(echo "${availableInterfaces}" | wc -l)

    if [[ ${interfaceCount} -eq 1 ]]; then
        DNSMON_INTERFACE="${availableInterfaces}"
    else
        while read -r line; do
            mode="OFF"
            if [[ ${firstLoop} -eq 1 ]]; then
                firstLoop=0
                mode="ON"
            fi
            interfacesArray+=("${line}" "available" "${mode}")
        done <<< "$availableInterfaces"

        chooseInterfaceCmd=(whiptail --separate-output --radiolist "Choose an interface:" ${r} ${c} ${interfaceCount})
        chooseInterfaceOptions=$("${chooseInterfaceCmd[@]}" "${interfacesArray[@]}" 2>&1 >/dev/tty) || \
        { echo "::: Cancel selected. Exiting"; exit 1; }
        for desiredInterface in ${chooseInterfaceOptions}; do
            DNSMON_INTERFACE=${desiredInterface}
            echo "** Using interface: $DNSMON_INTERFACE"
        done
    fi
}

set_dns() {
    DNSChooseOptions=(Google ""
        OpenDNS ""
        Comodo "")

    DNSchoices=$(whiptail --separate-output --menu "Select an upstream DNS provider, or custom to user your own." ${r} ${c} 6 "${DNSChooseOptions[@]}" 2>&1 >/dev/tty) || { echo "** Cancel selected. Exiting"; exit 1; }
    case ${DNSchoices} in
        Google)
            echo "** Using Google DNS."
            DNS_1="8.8.8.8"
            DNS_2="8.8.4.4"
            ;;
        OpenDNS)
            echo "** Using OpenDns DNS."
            DNS_1="208.67.222.222"
            DNS_2="208.67.220.220"
            ;;
        Comodo)
            echo "** Using Comodo Secure DNS."
            DNS_1="8.26.56.26"
            DNS_2="8.20.247.20"
            ;;
    esac
}

find_ipv4_information() {
    local route
    route=$(ip route get 8.8.8.8)
    ipv4dev=$(awk '{for (i=1; i<=NF; i++) if ($i~/dev/) print $(i+1)}' <<< "${route}")
    ipv4bare=$(awk '{print $7}' <<< "${route}")
    IPV4_ADDRESS=$(ip -o -f inet addr show | grep "${IPv4bare}" |  awk '{print $4}' | awk 'END {print}')
    ipv4gw=$(awk '{print $3}' <<< "${route}")
}

get_static_ipv4_settings() {
    local ipSettingsCorrect
    if whiptail --title "Static IP Address" --yesno "Do you want to use your current network settings as a static address?
            IP address:    ${IPV4_ADDRESS}
            Gateway:       ${ipv4gw}" ${r} ${c}; then
        return
    else
        until [[ ${ipSettingsCorrect} = True ]]; do
            IPV4_ADDRESS=$(whiptail --title "IPv4 address" --inputbox "Enter your desired IPv4 address" ${r} ${c} "${IPV4_ADDRESS}" 3>&1 1>&2 2>&3) || \
            { ipSettingsCorrect=False; echo "::: Cancel selected. Exiting..."; exit 1; }
            echo "::: Your static IPv4 address:    ${IPV4_ADDRESS}"

            ipv4gw=$(whiptail --title "IPv4 gateway (router)" --inputbox "Enter your desired IPv4 default gateway" ${r} ${c} "${ipv4gw}" 3>&1 1>&2 2>&3) || \
            { ipSettingsCorrect=False; echo "::: Cancel selected. Exiting..."; exit 1; }
            echo "::: Your static IPv4 gateway:    ${ipv4gw}"

            if whiptail --title "Static IP Address" --yesno "Are these settings correct?
                IP address:    ${IPV4_ADDRESS}
                Gateway:       ${ipv4gw}" ${r} ${c}; then
                ipSettingsCorrect=True
            else
                ipSettingsCorrect=False
            fi
        done
    fi
}

setDHCPCD() {
  # Append these lines to dhcpcd.conf to enable a static IP
  echo "interface ${DNSMON_INTERFACE}
  static ip_address=${IPV4_ADDRESS}
  static routers=${ipv4gw}
  static domain_name_servers=${ipv4gw}" | tee -a /etc/dhcpcd.conf >/dev/null
}


set_static_ipv4() {
    local IFCFG_FILE
    local IPADDR
    local CIDR

    if grep -q "${IPV4_ADDRESS}" /etc/dhcpcd.conf; then
        echo "** Static IP already configured."
    else
        setDHCPCD
        ip addr replace dev "${DNSMON_INTERFACE}" "${IPV4_ADDRESS}"
        echo "** Setting IP to ${IPV4_ADDRESS}. You may need to restart after the install."
    fi
}

setup_ipv4_static() {
    find_ipv4_information
    get_static_ipv4_settings
    set_static_ipv4
    echo "** IPv4 address: ${IPV4_ADDRESS}"
}

create_dnsmon_user() {
    echo "** Checking if user 'dnsmon' exists..."
    if id -u dnsmon &> /dev/null; then
        echo "** User 'dnsmon' already exists"
    else
        echo "** User 'dnsmon' doesn't exist. Creating..."
        useradd -r -s /usr/sbin/nologin dnsmon
    fi
}

install_dnsmasq() {
    local dnsmasq_conf="/etc/dnsmasq.conf"
    local dnsmasq_conf_orig="/etc/dnsmasq.conf.orig"
    local dnsmasq_dnsmon_conf="${DNSMON_LOCAL_DIR}/dnsmon.conf"
    local dnsmasq_conf_location="/etc/dnsmasq.d/dnsmon.conf"

    if [ -f ${dnsmasq_conf} ]; then
        echo "** Existing dnsmasq.conf found, leaving alone."
    else
        echo -n "** No dnsmasq.conf found, restoring default..."
        cp ${dnsmasq_conf_orig} ${dnsmasq_conf}
        echo " done."
    fi

    echo -n "** Copying dnsmon.conf to /etc/dnsmasq.d/..."
    cp ${dnsmasq_dnsmon_conf} ${dnsmasq_conf_location}
    echo " done."

    sed -i "s/@INT@/$DNSMON_INTERFACE/" ${dnsmasq_conf_location}
    if [[ "${DNS_1}" != "" ]]; then
        sed -i "s/@DNS1@/$DNS_1/" ${dnsmasq_conf_location}
    else
        sed -i '/^server=@DNS1@/d' ${dnsmasq_conf_location}
    fi
    if [[ "${DNS_2}" != "" ]]; then
        sed -i "s/@DNS2@/$DNS_2/" ${dnsmasq_conf_location}
    else
        sed -i '/^server=@DNS2@/d' ${dnsmasq_conf_location}
    fi

    sed -i 's/^#conf-dir=\/etc\/dnsmasq.d$/conf-dir=\/etc\/dnsmasq.d/' ${dnsmasq_conf}
}


install_dnsmon() {
    create_dnsmon_user
    install_dnsmasq
}

main() {
    # Make sure this was run with root privileges
    if [[ ${EUID} -ne 0 ]]; then
        echo "** Please try again with root privileges, we are going to install packages and configure network settings."
        exit 1
    fi

    # Initialize Debian specific variables and system settings
    if command -v apt-get &> /dev/null; then
        init_debian
    else
        echo "** System unsupported. dnsmon only supports Debian systems."
        exit 1
    fi

    # apt-get update
    update_package_cache || exit 1

    # Install package dependencies for this script
    install_dependencies INSTALLER_DEPS[@]

    # Install dependencies for dnsmon
    install_dependencies DNSMON_DEPS[@]

    whiptail --msgbox --title "dnsmon installer" "This will install dnsmon on your raspberrypi" ${r} ${c}

    stop_service dnsmasq
    get_available_interfaces
    choose_interface
    set_dns
    setup_ipv4_static

    install_dnsmon

    echo "!! dnsmon install complete. Please restart."
}

main