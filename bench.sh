#!/bin/bash
# Автор модификации Nikola_Tesla ©, по багам, вопросам пишите в ТГ https://t.me/tracerlab 


trap _exit INT QUIT TERM
# Limitation of the launch frequency
LOCK_FILE="/tmp/iperf3_last_run"
MIN_INTERVAL=300 
TEST_SUCCESS=false

if [ -f "$LOCK_FILE" ]; then
    last_run="$(cat "$LOCK_FILE" 2>/dev/null || echo 0)"
    now="$(date +%s)"
    last_run="${last_run//[^0-9]/}"
    [ -z "$last_run" ] && last_run=0
    diff=$(( now - last_run ))
    if [ "$diff" -lt "$MIN_INTERVAL" ]; then
        mins_left=$(((MIN_INTERVAL - diff) / 60))
        secs_left=$(((MIN_INTERVAL - diff) % 60))
        echo "⚠ The test can be run no more than once every 10 minutes."
        echo "⏳ Wait another ${mins_left} min ${secs_left} sec."
        exit 1
    fi
fi

trap 'if [ "$TEST_SUCCESS" = true ]; then date +%s > "$LOCK_FILE"; fi' EXIT

# Enable color
_red() { printf '\033[0;31;31m%b\033[0m' "$1"; }
_green() { printf '\033[0;31;32m%b\033[0m' "$1"; }
_yellow() { printf '\033[0;31;33m%b\033[0m' "$1"; }
_blue() { printf '\033[0;31;36m%b\033[0m' "$1"; }
_magenta() { printf '\033[0;35m%b\033[0m' "$1"; }
_cyan()    { printf '\033[0;36m%b\033[0m' "$1"; }

hide_cursor() { printf "\033[?25l"; }
show_cursor() { printf "\033[?25h"; }

_exists() {
    local cmd="$1"
    if eval type type >/dev/null 2>&1; then
        eval type "$cmd" >/dev/null 2>&1
    elif command >/dev/null 2>&1; then
        command -v "$cmd" >/dev/null 2>&1
    else
        which "$cmd" >/dev/null 2>&1
    fi
    return $?
}

_exit() {
    show_cursor
    _red "\nThe script has been terminated. Cleaning up files...\n"
    rm -fr benchtest_* 2>/dev/null
    exit 1
}

get_opsy() {
    [ -f /etc/redhat-release ] && awk '{print $0}' /etc/redhat-release && return
    [ -f /etc/os-release ] && awk -F'[= "]' '/PRETTY_NAME/{print $3,$4,$5}' /etc/os-release && return
    [ -f /etc/lsb-release ] && awk -F'[="]+' '/DESCRIPTION/{print $2}' /etc/lsb-release && return
}

next() { printf "%-70s\n" "-" | sed 's/\s/-/g'; }

THREADS=8

spinner() {
    local delay=0.1
    local spinstr='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
    local i=0
    
    hide_cursor
    while true; do
        i=$(( (i+1) % 10 ))
        printf "\033[1;33m%s\033[0m" "${spinstr:$i:1}"
        sleep $delay
        printf "\b"
    done
    show_cursor
}

speed_test() {
    local server="$1"
    local port="$2"
    local nodeName="$3"
    
    [ -z "$server" ] && return
    
    printf "\033[0;33m%-18s\033[0m " " ${nodeName}"
    spinner &
    spinner_pid=$!
    
    if ! ping -c 1 -W 2 "$server" >/dev/null 2>&1; then
        kill $spinner_pid >/dev/null 2>&1
        wait $spinner_pid 2>/dev/null
        show_cursor
        printf "\r\033[K"
        return
    fi
    
    local dl_speed=0 up_speed=0
    local test_file="/tmp/iperf3_$$.txt"
    local latency=$(ping -c 3 "$server" 2>/dev/null | awk -F'/' '/avg/ {printf "%.2f ms", $5}')
    
# 1. Test Upload
if timeout 20 iperf3 -c "$server" -p "$port" -t 10 -O 3 -f m -P $THREADS > "$test_file" 2>/dev/null; then
    up_speed=$(grep '\[SUM\]' "$test_file" | grep 'sender' | awk '{print $6}')
    if [ -z "$up_speed" ]; then
        up_speed=$(grep 'sender' "$test_file" | grep 'MBytes' | awk '{sum+=$7} END{print sum}')
        [ "$(echo "$up_speed < 0.1" | bc -l 2>/dev/null)" = "1" ] && \
        up_speed=$(grep 'sender' "$test_file" | grep 'MBytes' | awk '{sum+=$6} END{print sum}')
    fi
fi

sleep 1

# 2. Test Download
if timeout 20 iperf3 -c "$server" -p "$port" -t 10 -O 3 -f m -P $THREADS --reverse > "$test_file" 2>/dev/null; then
    dl_speed=$(grep '\[SUM\]' "$test_file" | grep 'receiver' | awk '{print $6}')
    if [ -z "$dl_speed" ]; then
        dl_speed=$(grep 'receiver' "$test_file" | grep 'MBytes' | awk '{sum+=$7} END{print sum}')
        [ "$(echo "$dl_speed < 0.1" | bc -l 2>/dev/null)" = "1" ] && \
        dl_speed=$(grep 'receiver' "$test_file" | grep 'MBytes' | awk '{sum+=$6} END{print sum}')
    fi
fi

    
    rm -f "$test_file" 2>/dev/null
    
    kill $spinner_pid >/dev/null 2>&1
    wait $spinner_pid 2>/dev/null
    show_cursor
    printf "\r\033[K"
    
    if [[ -z "$up_speed" || -z "$dl_speed" ]] || [[ "$up_speed" == "0" || "$dl_speed" == "0" ]]; then
    return
    fi
    
    printf "\033[0;33m%-17s\033[0;32m%9s %-8s\033[0;31m%7s %-8s\033[0;36m%13s\033[0m\n" \
           " ${nodeName}" "$up_speed" "Mbit/s" "$dl_speed" "Mbit/s" "${latency:-"N/A"}"
}

# Тестим этот список по одному
speed() {
    declare -a servers=(
        # Russian servers
        'spd-rudp.hostkey.ru:5201:Moscow, Hostkey'
        'st.spb.ertelecom.ru:5201:SPB, Er-com'
        'voronezh-speedtest.corbina.net:5201:Voronezh,Beeline'
        'st.nn.ertelecom.ru:5201:N.Novgorod'
		'speedtest-kaliningrad-01.corbina.net:5201:Kaliningrad'
        'st.kzn.ertelecom.ru:5201:Kazan, Er-com'
        'st.samara.ertelecom.ru:5201:Samara, Er-com'
        'st.rostov.ertelecom.ru:5201:Rostov-on-Don'
        'st.volgograd.ertelecom.ru:5201:Volgograd'
		'st.chel.ertelecom.ru:5201:Chelyabinsk'
		'st.omsk.ertelecom.ru:5201:Omsk'
        'st.krsk.ertelecom.ru:5201:Krasnoyarsk'
        'st.irkutsk.ertelecom.ru:5201:Irkutsk, Er-com'
#        'yktst.st.mtsws.net:3333:Yakutsk, MTS'
        
        # International servers
        'iperf-ams-nl.eranium.net:5201:NL Amsterdam'
#        'iperf3.moji.fr:5200:FR Paris'
        'speedtest.fra1.de.leaseweb.net:5201:DE Frankfurt'
    )

    printf "%-15s%19s%18s%11s\n" " Node Name" "Upload Speed" "Download Speed" "Latency"
    
    for server_info in "${servers[@]}"; do
        IFS=':' read -r server port nodeName <<< "$server_info"
        speed_test "$server" "$port" "$nodeName"
    done
}

io_test() {
    (LANG=C dd if=/dev/zero of=benchtest_$$ bs=512k count="$1" conv=fdatasync && rm -f benchtest_$$) 2>&1 | awk -F, '{io=$NF} END { print io}' | sed 's/^[ \t]*//;s/[ \t]*$//'
}

calc_size() {
    local raw=$1
    local total_size=0
    local num=1
    local unit="KB"
    
    [ "$raw" -eq 0 ] && echo "" && return
    
    # Conversion to GB for values greater than 1GB
    if [ "$raw" -ge 1099511627776 ]; then
        num=1099511627776
        unit="TB"
    elif [ "$raw" -ge 1073741824 ]; then
        num=1073741824
        unit="GB"
    elif [ "$raw" -ge 1048576 ]; then
        num=1048576
        unit="MB"
    elif [ "$raw" -ge 1024 ]; then
        num=1024
        unit="KB"
    fi
    
    total_size=$(awk 'BEGIN{printf "%.2f", '"$raw"' / '"$num"'}')
    echo "${total_size} ${unit}"
}

to_kibyte() { awk 'BEGIN{printf "%.0f", '"$1"' / 1024}'; }

calc_sum() {
    local sum=0
    for i in "$@"; do sum=$((sum + i)); done
    echo $sum
}

check_virt() {
    _exists "dmesg" && virtualx="$(dmesg 2>/dev/null)"
    if _exists "dmidecode"; then
        sys_manu="$(dmidecode -s system-manufacturer 2>/dev/null)"
        sys_product="$(dmidecode -s system-product-name 2>/dev/null)"
        sys_ver="$(dmidecode -s system-version 2>/dev/null)"
    else
        sys_manu=""; sys_product=""; sys_ver=""
    fi
    
    if grep -qa docker /proc/1/cgroup; then virt="Docker"
    elif grep -qa lxc /proc/1/cgroup; then virt="LXC"
    elif grep -qa container=lxc /proc/1/environ; then virt="LXC"
    elif [[ -f /proc/user_beancounters ]]; then virt="OpenVZ"
    elif [[ "${virtualx}" == *kvm-clock* ]]; then virt="KVM"
    elif [[ "${sys_product}" == *KVM* ]]; then virt="KVM"
    elif [[ "${cname}" == *KVM* ]]; then virt="KVM"
    elif [[ "${cname}" == *QEMU* ]]; then virt="KVM"
    elif [[ "${virtualx}" == *"VMware Virtual Platform"* ]]; then virt="VMware"
    elif [[ "${sys_product}" == *"VMware Virtual Platform"* ]]; then virt="VMware"
    elif [[ "${virtualx}" == *"Parallels Software International"* ]]; then virt="Parallels"
    elif [[ "${virtualx}" == *VirtualBox* ]]; then virt="VirtualBox"
    elif [[ -e /proc/xen ]]; then
        grep -q "control_d" "/proc/xen/capabilities" 2>/dev/null && virt="Xen-Dom0" || virt="Xen-DomU"
    elif [ -f "/sys/hypervisor/type" ] && grep -q "xen" "/sys/hypervisor/type"; then virt="Xen"
    elif [[ "${sys_manu}" == *"Microsoft Corporation"* ]]; then
        [[ "${sys_product}" == *"Virtual Machine"* ]] && \
        [[ "${sys_ver}" == *"7.0"* || "${sys_ver}" == *"Hyper-V" ]] && virt="Hyper-V" || virt="Microsoft Virtual Machine"
    else virt="Dedicated"; fi
}

# IPv4
ipv4_info() {
    local org city country region
    org="$(wget -q -T10 -O- ipinfo.io/org 2>/dev/null)"
    city="$(wget -q -T10 -O- ipinfo.io/city 2>/dev/null)"
    country="$(wget -q -T10 -O- ipinfo.io/country 2>/dev/null)"
    region="$(wget -q -T10 -O- ipinfo.io/region 2>/dev/null)"
    
    [ -n "${org}" ] && echo " Organization       : $(_blue "${org}")"
    [ -n "${city}" ] && [ -n "${country}" ] && echo " Location           : $(_blue "${city} / ${country}")"
    [ -n "${region}" ] && echo " Region             : $(_yellow "${region}")"
    [ -z "${org}" ] && echo " Region             : $(_red "No ISP detected")"
}

# Инсталируем iperf3
install_iperf3() {
    if ! _exists "iperf3"; then
        echo " iperf3 not found, trying to install..."
        local install_success=false
        
        if _exists "apt-get"; then
            DEBIAN_FRONTEND=noninteractive apt-get update -qq >/dev/null 2>&1 && \
            DEBIAN_FRONTEND=noninteractive apt-get install -y -qq iperf3 >/dev/null 2>&1 && install_success=true
        elif _exists "yum"; then
            yum install -y -q iperf3 >/dev/null 2>&1 && install_success=true
        elif _exists "dnf"; then
            dnf install -y -q iperf3 >/dev/null 2>&1 && install_success=true
        elif _exists "pacman"; then
            pacman -S --noconfirm --quiet iperf3 >/dev/null 2>&1 && install_success=true
        elif _exists "apk"; then
            apk add --quiet iperf3 >/dev/null 2>&1 && install_success=true
        fi
        
        # Накатывам бинарник
        if ! _exists "iperf3" && ! $install_success; then
            echo " Trying to install static binary..."
            local arch=$(uname -m)
            local url=""
            
            [ "$arch" = "x86_64" ] && url="https://github.com/userdocs/iperf3-static/releases/latest/download/iperf3-amd64"
            [[ "$arch" = "aarch64" || "$arch" = "arm64" ]] && url="https://github.com/userdocs/iperf3-static/releases/latest/download/iperf3-arm64"
            
            if [ -n "$url" ]; then
                if _exists "wget"; then
                    wget -q -O /tmp/iperf3 "$url" >/dev/null 2>&1 && chmod +x /tmp/iperf3
                elif _exists "curl"; then
                    curl -sL -o /tmp/iperf3 "$url" >/dev/null 2>&1 && chmod +x /tmp/iperf3
                fi
                
                if [ -x "/tmp/iperf3" ]; then
                    /tmp/iperf3 --version >/dev/null 2>&1 && \
                    mv /tmp/iperf3 /usr/local/bin/iperf3 2>/dev/null || \
                    mv /tmp/iperf3 ./iperf3
                    export PATH=".:$PATH"
                    install_success=true
                fi
            fi
        fi
        
        if ! _exists "iperf3" && ! $install_success; then
            echo " Failed to install iperf3. Skipping speed tests..."
            return 1
        fi
    fi
    return 0
}

print_intro() {
    clear
    echo -e "\e[36m\e[0m\e[37m------------------- A Bench.sh Script By Teddysun ---------------------\e[36m\e[0m"
    echo -e "\e[36m\e[0m\e[37m                      $(_cyan "Modified by Nikola Tesla") - https://t.me/tracerlab \e[36m\e[0m"
    echo -e "\e[36m\e[0m\e[37m      Network         Updated servers — Russia, Europe, (all regions)        \e[36m\e[0m"
    echo -e "\e[36m\e[0m\e[37m   Bench Utility      $(_green v2025-11-04)                                    \e[36m\e[0m"
    echo -e "\e[36m\e[0m\e[37m                      $(_red "wget -qO- bench.tlab.pw | bash") <- Usage command \e[36m\e[0m"
}

# Info cpu ram
get_system_info() {
    cname=$(awk -F: '/model name/ {name=$2} END {print name}' /proc/cpuinfo | sed 's/^[ \t]*//;s/[ \t]*$//')
    cores=$(awk -F: '/^processor/ {core++} END {print core}' /proc/cpuinfo)
    freq=$(awk -F'[ :]' '/cpu MHz/ {print $4;exit}' /proc/cpuinfo)
    ccache=$(awk -F: '/cache size/ {cache=$2} END {print cache}' /proc/cpuinfo | sed 's/^[ \t]*//;s/[ \t]*$//')
    cpu_aes=$(grep -i 'aes' /proc/cpuinfo)
    cpu_virt=$(grep -Ei 'vmx|svm' /proc/cpuinfo)
    
    total_ram_bytes=$(free -b | awk '/Mem/ {print $2}')
    used_ram_bytes=$(free -b | awk '/Mem/ {print $3}')
    total_swap_bytes=$(free -b | awk '/Swap/ {print $2}')
    used_swap_bytes=$(free -b | awk '/Swap/ {print $3}')
    
    tram=$(calc_size "$total_ram_bytes")
    uram=$(calc_size "$used_ram_bytes")
    swap=$(calc_size "$total_swap_bytes")
    uswap=$(calc_size "$total_swap_bytes")
    
    up=$(awk '{a=$1/86400;b=($1%86400)/3600;c=($1%3600)/60} {printf("%d days, %d hour %d min\n",a,b,c)}' /proc/uptime)
    
    if _exists "w"; then
        load=$(w | head -1 | awk -F'load average:' '{print $2}' | sed 's/^[ \t]*//;s/[ \t]*$//')
    elif _exists "uptime"; then
        load=$(uptime | head -1 | awk -F'load average:' '{print $2}' | sed 's/^[ \t]*//;s/[ \t]*$//')
    fi
    
    opsy=$(get_opsy)
    arch=$(uname -m)
    _exists "getconf" && lbit=$(getconf LONG_BIT) || lbit=$(echo "${arch}" | grep -q "64" && echo 32)
    kern=$(uname -r)
    
    # Disk calculations
    in_kernel_no_swap_total_size=$(df -t simfs -t ext2 -t ext3 -t ext4 -t btrfs -t xfs -t vfat -t ntfs --total -B1 2>/dev/null | grep total | awk '{ print $2 }')
    swap_total_size=$(free -b | grep Swap | awk '{print $2}')
    zfs_total_size=0
    if _exists "zpool"; then
        zfs_total_size=$(zpool list -o size -Hp 2> /dev/null | while read -r size; do echo "$size"; done)
        zfs_total_size=$(calc_sum $zfs_total_size)
    fi
    disk_total_size=$(calc_size $((swap_total_size + in_kernel_no_swap_total_size + zfs_total_size)))
    
    in_kernel_no_swap_used_size=$(df -t simfs -t ext2 -t ext3 -t ext4 -t btrfs -t xfs -t vfat -t ntfs --total -B1 2>/dev/null | grep total | awk '{ print $3 }')
    swap_used_size=$(free -b | grep Swap | awk '{print $3}')
    zfs_used_size=0
    if _exists "zpool"; then
        zfs_used_size=$(zpool list -o allocated -Hp 2> /dev/null | while read -r size; do echo "$size"; done)
        zfs_used_size=$(calc_sum $zfs_used_size)
    fi
    disk_used_size=$(calc_size $((swap_used_size + in_kernel_no_swap_used_size + zfs_used_size)))
    
    tcpctrl=$(sysctl net.ipv4.tcp_congestion_control 2>/dev/null | awk -F ' ' '{print $3}')
}

# System information output
print_system_info() {
    [ -n "$cname" ] && echo " CPU Model          : $(_blue "$cname")" || echo " CPU Model          : $(_blue "CPU model not detected")"
    [ -n "$freq" ] && echo " CPU Cores          : $(_blue "$cores @ $freq MHz")" || echo " CPU Cores          : $(_blue "$cores")"
    [ -n "$ccache" ] && echo " CPU Cache          : $(_blue "$ccache")"
    [ -n "$cpu_aes" ] && echo " AES-NI             : $(_green "\xe2\x9c\x93 Enabled")" || echo " AES-NI             : $(_red "\xe2\x9c\x97 Disabled")"
    [ -n "$cpu_virt" ] && echo " VM-x/AMD-V         : $(_green "\xe2\x9c\x93 Enabled")" || echo " VM-x/AMD-V         : $(_red "\xe2\x9c\x97 Disabled")"
    echo " Total Disk         : $(_yellow "$disk_total_size") $(_blue "($disk_used_size Used)")"
    echo " Total Mem          : $(_yellow "$tram") $(_blue "($uram Used)")"
    [ "$swap" != "0" ] && [ "$swap" != "0 B" ] && echo " Total Swap         : $(_blue "$swap ($uswap Used)")"
    echo " System uptime      : $(_blue "$up")"
    echo " Load average       : $(_blue "$load")"
    echo " OS                 : $(_blue "$opsy")"
    echo " Arch               : $(_blue "$arch ($lbit Bit)")"
    echo " Kernel             : $(_blue "$kern")"
    [ -n "$tcpctrl" ] && echo " TCP CC             : $(_yellow "$tcpctrl")"
    echo " Virtualization     : $(_blue "$virt")"
    echo " IPv4/IPv6          : $online"
}

# Disk test
print_io_test() {
    freespace=$(df -m . | awk 'NR==2 {print $4}')
    [ -z "${freespace}" ] && freespace=$(df -m . | awk 'NR==3 {print $3}')
    
    if [ "${freespace}" -gt 1024 ]; then
        writemb=2048
        io1=$(io_test ${writemb})
        echo " I/O Speed(1st run) : $(_yellow "$io1")"
        io2=$(io_test ${writemb})
        echo " I/O Speed(2nd run) : $(_yellow "$io2")"
        io3=$(io_test ${writemb})
        echo " I/O Speed(3rd run) : $(_yellow "$io3")"
        
        ioraw1=$(echo "$io1" | awk 'NR==1 {print $1}')
        [ "$(echo "$io1" | awk 'NR==1 {print $2}')" == "GB/s" ] && ioraw1=$(awk 'BEGIN{print '"$ioraw1"' * 1024}')
        ioraw2=$(echo "$io2" | awk 'NR==1 {print $1}')
        [ "$(echo "$io2" | awk 'NR==1 {print $2}')" == "GB/s" ] && ioraw2=$(awk 'BEGIN{print '"$ioraw2"' * 1024}')
        ioraw3=$(echo "$io3" | awk 'NR==1 {print $1}')
        [ "$(echo "$io3" | awk 'NR==1 {print $2}')" == "GB/s" ] && ioraw3=$(awk 'BEGIN{print '"$ioraw3"' * 1024}')
        
        ioall=$(awk 'BEGIN{print '"$ioraw1"' + '"$ioraw2"' + '"$ioraw3"'}')
        ioavg=$(awk 'BEGIN{printf "%.1f", '"$ioall"' / 3}')
        echo " I/O Speed(average) : $(_yellow "$ioavg MB/s")"
    else
        echo " $(_red "Not enough space for I/O Speed test!")"
    fi
}

# Completion time
print_end_time() {
    end_time=$(date +%s)
    time=$((end_time - start_time))
    if [ ${time} -gt 60 ]; then
        min=$((time / 60))
        sec=$((time % 60))
        echo " Finished in        : ${min} min ${sec} sec"
    else
        echo " Finished in        : ${time} sec"
    fi
    date_time=$(date '+%Y-%m-%d %H:%M:%S %Z')
    echo " Timestamp          : $date_time"
    echo " Follow             : $(_blue "https://t.me/tracerlab")"
}

# Чек зависимостей
! _exists "wget" && _red "Error: wget command not found.\n" && exit 1
! _exists "free" && _red "Error: free command not found.\n" && exit 1
! _exists "ping" && _red "Error: ping command not found.\n" && exit 1

# Checking the connection
ipv4_check=$( (ping -4 -c 1 -W 4 ipv4.google.com >/dev/null 2>&1 && echo true) || (wget -q -T4 -4 -O- ipinfo.io/org >/dev/null 2>&1 && echo true) )
ipv6_check=$( (ping -6 -c 1 -W 4 ipv6.google.com >/dev/null 2>&1 && echo true) || (wget -q -T4 -6 -O- ipinfo.io/org >/dev/null 2>&1 && echo true) )
[ -z "$ipv4_check" ] && [ -z "$ipv6_check" ] && _yellow "Warning: Both IPv4 and IPv6 connectivity were not detected.\n"
[ -z "$ipv4_check" ] && online="$(_red "\xe2\x9c\x97 Offline")" || online="$(_green "\xe2\x9c\x93 Online")"
[ -z "$ipv6_check" ] && online+=" / $(_red "\xe2\x9c\x97 Offline")" || online+=" / $(_green "\xe2\x9c\x93 Online")"


countRunTimes() {
    local stats_json today total
    stats_json=$(curl -sL --max-time 10 "https://bench.tlab.pw/stats.json")

    # чек инфы с сервера
    today=$(echo "$stats_json" | grep -o '"day"[[:space:]]*:[[:space:]]*[0-9]*' | grep -o '[0-9]*')
    total=$(echo "$stats_json" | grep -o '"total"[[:space:]]*:[[:space:]]*[0-9]*' | grep -o '[0-9]*')

    if [[ "$today" =~ ^[0-9]+$ ]] && [[ "$total" =~ ^[0-9]+$ ]]; then
        echo -e " Run statistics     : Today:${today} Total:${total} \033[3mThanks for using the script!\033[0m"
    else
        echo -e "Run statistics     : Unavailable"
    fi
}

# The main flow of execution
start_time=$(date +%s)
get_system_info
check_virt
print_intro
next
print_system_info
ipv4_info
next
print_io_test
next

if install_iperf3; then
    speed
    TEST_SUCCESS=true
else
    echo " Network speed tests skipped due to missing iperf3"
fi

next
print_end_time
countRunTimes
next