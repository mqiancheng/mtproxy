#!/bin/bash

# MTProxy 澧炲己鐗堢鐞嗚剼鏈?- 浼樺寲鐗堟湰
# 娑堥櫎閲嶅浠ｇ爜锛屾彁楂樺彲缁存姢鎬?# 鏀寔 Alpine Linux, AlmaLinux/RHEL/CentOS, Debian/Ubuntu

WORKDIR=$(dirname $(readlink -f $0))
cd $WORKDIR
pid_file=$WORKDIR/pid/pid_mtproxy

# 棰滆壊瀹氫箟
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

# 鎵撳嵃鍑芥暟
print_info() { echo -e "${BLUE}[淇℃伅]${NC} $1"; }
print_success() { echo -e "${GREEN}[鎴愬姛]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[璀﹀憡]${NC} $1"; }
print_error() { echo -e "${RED}[閿欒]${NC} $1"; }
print_debug() { echo -e "${CYAN}[璋冭瘯]${NC} $1"; }
print_line() { echo "========================================"; }

# ==================== 閫氱敤杈呭姪鍑芥暟 ====================

# 鍔犺浇閰嶇疆鏂囦欢
load_config() {
    if [ ! -f "./mtp_config" ]; then
        print_error "閰嶇疆鏂囦欢涓嶅瓨鍦紝璇峰厛瀹夎"
        return 1
    fi
    source ./mtp_config
    return 0
}

# 妫€鏌ヨ繘绋嬬姸鎬?check_process_status() {
    if [ -f "$pid_file" ]; then
        local pid=$(cat $pid_file)
        if kill -0 $pid 2>/dev/null; then
            echo $pid
            return 0  # 杩愯涓?        else
            rm -f $pid_file
            return 1  # 宸插仠姝?        fi
    else
        return 1  # PID鏂囦欢涓嶅瓨鍦?    fi
}

# 閲婃斁绔彛
release_port() {
    local port=$1
    if netstat -tulpn 2>/dev/null | grep -q ":$port "; then
        print_info "閲婃斁绔彛 $port..."
        local pids=$(netstat -tulpn 2>/dev/null | grep ":$port " | awk '{print $7}' | sed 's|/.*||')
        for pid in $pids; do
            kill -9 $pid 2>/dev/null
        done
    fi
}

# 鏍囧噯鍑芥暟澶撮儴
function_header() {
    local title="$1"
    print_line
    print_info "$title"
    print_line
}

# 纭繚绯荤粺妫€娴?ensure_system_detected() {
    if [ -z "$OS" ]; then
        detect_system 2>/dev/null
    fi
}

# 纭繚缃戠粶鐜妫€娴?ensure_network_detected() {
    if [ -z "$NETWORK_TYPE" ]; then
        detect_network_environment
    fi
}

# 妫€鏌ョ鍙ｆ槸鍚﹁鍗犵敤
is_port_occupied() {
    local port=$1
    netstat -tulpn 2>/dev/null | grep -q ":$port "
}

# 鑾峰彇绔彛鍗犵敤杩涚▼
get_port_process() {
    local port=$1
    netstat -tulpn 2>/dev/null | grep ":$port " | awk '{print $7}' | head -1
}

# 楠岃瘉绔彛鍙?validate_port() {
    local port=$1
    if [[ "$port" =~ ^[0-9]+$ ]] && [ $port -ge 1 ] && [ $port -le 65535 ]; then
        return 0
    else
        return 1
    fi
}

# 鍒涘缓蹇呰鐩綍
create_directories() {
    mkdir -p pid logs
}

# 鐢熸垚瀹㈡埛绔瘑閽?generate_client_secret() {
    local domain_hex=$(str_to_hex $domain)
    echo "ee${secret}${domain_hex}"
}

# 鏄剧ず闃茬伀澧欓厤缃懡浠?show_firewall_commands() {
    local client_port=$1
    local manage_port=$2

    function_header "闃茬伀澧欓厤缃彁绀?

    case $OS in
        "rhel")
            echo "AlmaLinux/RHEL/CentOS 闃茬伀澧欓厤缃?"
            echo "firewall-cmd --permanent --add-port=$client_port/tcp"
            echo "firewall-cmd --permanent --add-port=$manage_port/tcp"
            echo "firewall-cmd --reload"
            ;;
        "debian")
            echo "Debian/Ubuntu 闃茬伀澧欓厤缃?"
            echo "ufw allow $client_port/tcp"
            echo "ufw allow $manage_port/tcp"
            ;;
        "alpine")
            echo "Alpine Linux 閫氬父涓嶉渶瑕侀澶栫殑闃茬伀澧欓厤缃?
            echo "濡傛灉浣跨敤iptables:"
            echo "iptables -A INPUT -p tcp --dport $client_port -j ACCEPT"
            echo "iptables -A INPUT -p tcp --dport $manage_port -j ACCEPT"
            ;;
    esac
    print_line
}

# ==================== 绯荤粺妫€娴嬪嚱鏁?====================

# 绯荤粺妫€娴?detect_system() {
    if [[ -f /etc/alpine-release ]]; then
        OS="alpine"
        PKG_MANAGER="apk"
        DISTRO="Alpine Linux $(cat /etc/alpine-release)"
    elif [[ -f /etc/redhat-release ]] || [[ -f /etc/almalinux-release ]] || [[ -f /etc/centos-release ]]; then
        OS="rhel"
        PKG_MANAGER="yum"
        command -v dnf >/dev/null 2>&1 && PKG_MANAGER="dnf"
        if [[ -f /etc/almalinux-release ]]; then
            DISTRO="AlmaLinux $(grep VERSION_ID /etc/os-release | cut -d'"' -f2)"
        elif [[ -f /etc/centos-release ]]; then
            DISTRO="CentOS $(cat /etc/centos-release | grep -oE '[0-9]+\.[0-9]+')"
        else
            DISTRO="RHEL $(grep VERSION_ID /etc/os-release | cut -d'"' -f2)"
        fi
    elif [[ -f /etc/debian_version ]]; then
        OS="debian"
        PKG_MANAGER="apt"
        if grep -q "Ubuntu" /etc/os-release; then
            DISTRO="Ubuntu $(grep VERSION_ID /etc/os-release | cut -d'"' -f2)"
        else
            DISTRO="Debian $(cat /etc/debian_version)"
        fi
    else
        print_error "涓嶆敮鎸佺殑鎿嶄綔绯荤粺"
        exit 1
    fi
}

# 缃戠粶鐜妫€娴?detect_network_environment() {
    local ipv4=$(curl -s --connect-timeout 6 https://api.ip.sb/ip -A Mozilla --ipv4 2>/dev/null)
    local ipv6=$(curl -s --connect-timeout 6 https://api.ip.sb/ip -A Mozilla --ipv6 2>/dev/null)
    local has_ipv4=false
    local has_ipv6=false
    local is_warp=false
    local is_nat=false

    # 妫€鏌Pv4
    if [[ -n "$ipv4" && "$ipv4" != *"curl:"* && "$ipv4" != *"error"* ]]; then
        has_ipv4=true
        # 妫€鏌ユ槸鍚︿负WARP (Cloudflare IP娈?
        if [[ "$ipv4" =~ ^(162\.159\.|104\.28\.|172\.67\.|104\.16\.) ]]; then
            is_warp=true
        fi
    fi

    # 妫€鏌Pv6
    if [[ -n "$ipv6" && "$ipv6" != *"curl:"* && "$ipv6" != *"error"* ]]; then
        has_ipv6=true
        # 妫€鏌ユ槸鍚︿负WARP IPv6
        if [[ "$ipv6" =~ ^2606:4700: ]]; then
            is_warp=true
        fi
    fi

    # 妫€鏌ユ槸鍚︿负NAT鐜
    local local_ip=$(ip route get 8.8.8.8 2>/dev/null | grep -oP 'src \K\S+' | head -1)
    if [[ -n "$local_ip" && "$local_ip" != "$ipv4" ]]; then
        is_nat=true
    fi

    # 纭畾缃戠粶鐜绫诲瀷
    if [[ "$has_ipv4" == true && "$has_ipv6" == true && "$is_warp" == false ]]; then
        NETWORK_TYPE="dual_stack"
    elif [[ "$has_ipv4" == true && "$has_ipv6" == false ]]; then
        NETWORK_TYPE="ipv4_only"
    elif [[ "$has_ipv4" == false && "$has_ipv6" == true ]]; then
        NETWORK_TYPE="ipv6_only"
    elif [[ "$is_warp" == true ]]; then
        NETWORK_TYPE="warp_proxy"
    else
        NETWORK_TYPE="unknown"
    fi

    # 瀵煎嚭鐜鍙橀噺
    export NETWORK_TYPE
    export HAS_IPV4=$has_ipv4
    export HAS_IPV6=$has_ipv6
    export IS_WARP=$is_warp
    export IS_NAT=$is_nat
    export PUBLIC_IPV4="$ipv4"
    export PUBLIC_IPV6="$ipv6"
    export LOCAL_IP="$local_ip"
}

# 鑾峰彇鏋舵瀯
get_architecture() {
    case $(uname -m) in
    i386|i686) echo "386" ;;
    x86_64) echo "amd64" ;;
    aarch64) echo "arm64" ;;
    arm*) echo "armv6l" ;;
    *) print_error "涓嶆敮鎸佺殑鏋舵瀯: $(uname -m)" && exit 1 ;;
    esac
}

# 鐢熸垚闅忔満瀛楃涓?gen_rand_hex() {
    dd if=/dev/urandom bs=1 count=500 status=none 2>/dev/null | od -An -tx1 | tr -d ' \n' | head -c $1
}

# 瀛楃涓茶浆鍗佸叚杩涘埗
str_to_hex() {
    printf "%s" "$1" | od -An -tx1 | tr -d ' \n'
}

# 鏍规嵁缃戠粶鐜鐢熸垚MTG鍚姩鍙傛暟
generate_mtg_params() {
    local client_secret="$1"
    local proxy_tag="$2"
    local port="$3"
    local web_port="$4"

    ensure_network_detected

    local bind_addr=""
    local external_params=""
    local prefer_ip=""

    case "$NETWORK_TYPE" in
        "dual_stack")
            # 鍙屾爤鐜锛氱粦瀹氭墍鏈夋帴鍙ｏ紝浼樺厛IPv4
            bind_addr="0.0.0.0:$port"
            prefer_ip="--prefer-ip=ipv4"
            if [[ -n "$PUBLIC_IPV4" ]]; then
                external_params="-4 $PUBLIC_IPV4:$port"
            fi
            if [[ -n "$PUBLIC_IPV6" ]]; then
                external_params="$external_params -6 [$PUBLIC_IPV6]:$port"
            fi
            ;;
        "ipv4_only")
            # 绾疘Pv4鐜锛氭槑纭粦瀹欼Pv4鍦板潃
            bind_addr="$PUBLIC_IPV4:$port"
            prefer_ip="--prefer-ip=ipv4"
            if [[ -n "$PUBLIC_IPV4" ]]; then
                external_params="-4 $PUBLIC_IPV4:$port"
            fi
            ;;
        "ipv6_only")
            # 绾疘Pv6鐜锛氱粦瀹欼Pv6
            bind_addr="[::]:$port"
            prefer_ip="--prefer-ip=ipv6"
            if [[ -n "$PUBLIC_IPV6" ]]; then
                external_params="-6 [$PUBLIC_IPV6]:$port"
            fi
            ;;
        "warp_proxy")
            # WARP浠ｇ悊鐜锛氱壒娈婂鐞?            if [[ "$HAS_IPV6" == true ]]; then
                bind_addr="[::]:$port"
                prefer_ip="--prefer-ip=ipv6"
                if [[ -n "$PUBLIC_IPV6" ]]; then
                    external_params="-6 [$PUBLIC_IPV6]:$port"
                fi
            else
                bind_addr="0.0.0.0:$port"
                prefer_ip="--prefer-ip=ipv4"
                if [[ -n "$PUBLIC_IPV4" ]]; then
                    external_params="-4 $PUBLIC_IPV4:$port"
                fi
            fi
            ;;
        *)
            # 榛樿閰嶇疆
            bind_addr="0.0.0.0:$port"
            prefer_ip="--prefer-ip=ipv4"
            if [[ -n "$PUBLIC_IPV4" ]]; then
                external_params="-4 $PUBLIC_IPV4:$port"
            fi
            ;;
    esac

    # 鏋勫缓瀹屾暣鍛戒护
    local base_cmd="./mtg run $client_secret"
    [[ -n "$proxy_tag" ]] && base_cmd="$base_cmd $proxy_tag"

    local full_cmd="$base_cmd -b $bind_addr --multiplex-per-connection 500 $prefer_ip -t 127.0.0.1:$web_port"
    [[ -n "$external_params" ]] && full_cmd="$full_cmd $external_params"

    echo "$full_cmd"
}

# ==================== 妫€鏌ュ拰璇婃柇鍑芥暟 ====================

# 绯荤粺淇℃伅妫€鏌?check_system_info() {
    function_header "绯荤粺淇℃伅妫€鏌?
    
    echo -e "鎿嶄綔绯荤粺: ${GREEN}$DISTRO${NC}"
    echo -e "鍖呯鐞嗗櫒: ${GREEN}$PKG_MANAGER${NC}"
    echo -e "绯荤粺鏋舵瀯: ${GREEN}$(uname -m)${NC}"
    echo -e "鍐呮牳鐗堟湰: ${GREEN}$(uname -r)${NC}"
    echo -e "杩愯鏃堕棿: ${GREEN}$(uptime | awk '{print $3,$4}' | sed 's/,//')${NC}"
    
    # 妫€鏌ュ唴瀛?    local mem_total=$(free -h | awk '/^Mem:/ {print $2}')
    local mem_used=$(free -h | awk '/^Mem:/ {print $3}')
    echo -e "鍐呭瓨浣跨敤: ${GREEN}$mem_used / $mem_total${NC}"
    
    # 妫€鏌ョ鐩樼┖闂?    local disk_usage=$(df -h . | awk 'NR==2 {print $5}')
    echo -e "纾佺洏浣跨敤: ${GREEN}$disk_usage${NC}"
}

# 缃戠粶妫€鏌?check_network() {
    function_header "缃戠粶杩炴帴妫€鏌ヤ笌鐜妫€娴?

    detect_network_environment

    # 鏄剧ず缃戠粶鐜淇℃伅
    echo -e "缃戠粶鐜绫诲瀷: ${GREEN}$NETWORK_TYPE${NC}"

    # 妫€鏌Pv4杩炴帴
    print_info "妫€鏌Pv4杩炴帴..."
    if [[ "$HAS_IPV4" == true ]]; then
        echo -e "IPv4鍦板潃: ${GREEN}$PUBLIC_IPV4${NC}"
        [[ "$IS_WARP" == true ]] && echo -e "WARP妫€娴? ${YELLOW}鏄?{NC}"
    else
        echo -e "IPv4杩炴帴: ${RED}澶辫触${NC}"
    fi

    # 妫€鏌Pv6杩炴帴
    print_info "妫€鏌Pv6杩炴帴..."
    if [[ "$HAS_IPV6" == true ]]; then
        echo -e "IPv6鍦板潃: ${GREEN}$PUBLIC_IPV6${NC}"
    else
        echo -e "IPv6杩炴帴: ${YELLOW}涓嶅彲鐢?{NC}"
    fi

    # NAT妫€娴?    if [[ "$IS_NAT" == true ]]; then
        echo -e "NAT鐜: ${YELLOW}鏄?{NC} (鏈湴IP: $LOCAL_IP)"
    else
        echo -e "NAT鐜: ${GREEN}鍚?{NC}"
    fi

    # 妫€鏌NS瑙ｆ瀽
    print_info "妫€鏌NS瑙ｆ瀽..."
    if nslookup google.com >/dev/null 2>&1; then
        echo -e "DNS瑙ｆ瀽: ${GREEN}姝ｅ父${NC}"
    else
        echo -e "DNS瑙ｆ瀽: ${RED}寮傚父${NC}"
    fi

    # 妫€鏌ョ綉缁滄帴鍙?    print_info "缃戠粶鎺ュ彛淇℃伅:"
    ip addr show | grep -E "inet |inet6 " | grep -v "127.0.0.1" | grep -v "::1" | while read line; do
        echo -e "  ${CYAN}$line${NC}"
    done

    # 鏄剧ず鐜鐗瑰畾鐨勬彁绀?    echo ""
    print_info "鐜鍒嗘瀽:"
    case "$NETWORK_TYPE" in
        "dual_stack")
            echo -e "${GREEN}鉁?鍙屾爤鐜锛孖Pv4鍜孖Pv6閮藉彲鐢紝杩炴帴搴旇绋冲畾${NC}"
            ;;
        "ipv4_only")
            echo -e "${YELLOW}鈿?绾疘Pv4鐜锛孖Pv6杩炴帴灏嗕笉鍙敤${NC}"
            ;;
        "ipv6_only")
            echo -e "${YELLOW}鈿?绾疘Pv6鐜锛岀‘淇濆鎴风鏀寔IPv6${NC}"
            ;;
        "warp_proxy")
            echo -e "${YELLOW}鈿?WARP浠ｇ悊鐜锛屽彲鑳藉瓨鍦ㄨ繛鎺ョǔ瀹氭€ч棶棰?{NC}"
            ;;
        "unknown")
            echo -e "${RED}鉁?缃戠粶鐜寮傚父锛屽缓璁繍琛岃瘖鏂姛鑳?{NC}"
            ;;
    esac
}

# 绔彛妫€鏌?check_ports() {
    function_header "绔彛浣跨敤鎯呭喌妫€鏌?
    
    # 妫€鏌ュ父鐢ㄧ鍙?    local common_ports=(22 80 443 8080 8443 8888 9999)
    for port in "${common_ports[@]}"; do
        if is_port_occupied $port; then
            local process=$(get_port_process $port)
            echo -e "绔彛 $port: ${RED}琚崰鐢?{NC} ($process)"
        else
            echo -e "绔彛 $port: ${GREEN}鍙敤${NC}"
        fi
    done
    
    # 濡傛灉鏈夐厤缃枃浠讹紝妫€鏌ラ厤缃殑绔彛
    if load_config; then
        echo ""
        print_info "MTProxy閰嶇疆绔彛妫€鏌?"
        
        if is_port_occupied $port; then
            local process=$(get_port_process $port)
            echo -e "瀹㈡埛绔鍙?$port: ${RED}琚崰鐢?{NC} ($process)"
        else
            echo -e "瀹㈡埛绔鍙?$port: ${GREEN}鍙敤${NC}"
        fi
        
        if is_port_occupied $web_port; then
            local process=$(get_port_process $web_port)
            echo -e "绠＄悊绔彛 $web_port: ${RED}琚崰鐢?{NC} ($process)"
        else
            echo -e "绠＄悊绔彛 $web_port: ${GREEN}鍙敤${NC}"
        fi
    fi
}

# 闃茬伀澧欐鏌?check_firewall() {
    function_header "闃茬伀澧欑姸鎬佹鏌?
    
    case $OS in
        "rhel")
            if command -v firewall-cmd >/dev/null 2>&1; then
                if systemctl is-active firewalld >/dev/null 2>&1; then
                    echo -e "Firewalld: ${GREEN}杩愯涓?{NC}"
                    if load_config; then
                        local port_open=$(firewall-cmd --list-ports | grep -c "$port/tcp")
                        local web_port_open=$(firewall-cmd --list-ports | grep -c "$web_port/tcp")
                        echo -e "绔彛 $port/tcp: $([ $port_open -gt 0 ] && echo -e "${GREEN}宸插紑鏀?{NC}" || echo -e "${RED}鏈紑鏀?{NC}")"
                        echo -e "绔彛 $web_port/tcp: $([ $web_port_open -gt 0 ] && echo -e "${GREEN}宸插紑鏀?{NC}" || echo -e "${RED}鏈紑鏀?{NC}")"
                    fi
                else
                    echo -e "Firewalld: ${YELLOW}鏈繍琛?{NC}"
                fi
            else
                echo -e "Firewalld: ${YELLOW}鏈畨瑁?{NC}"
            fi
            ;;
        "debian")
            if command -v ufw >/dev/null 2>&1; then
                local ufw_status=$(ufw status | head -1)
                if [[ "$ufw_status" == *"active"* ]]; then
                    echo -e "UFW: ${GREEN}婵€娲?{NC}"
                    if load_config; then
                        ufw status | grep -q "$port/tcp" && echo -e "绔彛 $port/tcp: ${GREEN}宸插紑鏀?{NC}" || echo -e "绔彛 $port/tcp: ${RED}鏈紑鏀?{NC}"
                        ufw status | grep -q "$web_port/tcp" && echo -e "绔彛 $web_port/tcp: ${GREEN}宸插紑鏀?{NC}" || echo -e "绔彛 $web_port/tcp: ${RED}鏈紑鏀?{NC}"
                    fi
                else
                    echo -e "UFW: ${YELLOW}鏈縺娲?{NC}"
                fi
            else
                echo -e "UFW: ${YELLOW}鏈畨瑁?{NC}"
            fi
            ;;
        "alpine")
            if command -v iptables >/dev/null 2>&1; then
                local iptables_rules=$(iptables -L INPUT -n | wc -l)
                echo -e "iptables瑙勫垯鏁? ${GREEN}$iptables_rules${NC}"
            else
                echo -e "iptables: ${YELLOW}鏈畨瑁?{NC}"
            fi
            ;;
    esac
}

# MTProxy鐘舵€佹鏌?check_mtproxy_status() {
    function_header "MTProxy鐘舵€佹鏌?
    
    # 妫€鏌ラ厤缃枃浠?    if load_config; then
        echo -e "閰嶇疆鏂囦欢: ${GREEN}瀛樺湪${NC}"
        echo -e "瀹㈡埛绔鍙? ${GREEN}$port${NC}"
        echo -e "绠＄悊绔彛: ${GREEN}$web_port${NC}"
        echo -e "浼鍩熷悕: ${GREEN}$domain${NC}"
        [[ -n "$proxy_tag" ]] && echo -e "鎺ㄥ箍TAG: ${GREEN}$proxy_tag${NC}" || echo -e "鎺ㄥ箍TAG: ${YELLOW}鏈缃?{NC}"
    else
        return 1
    fi
    
    # 妫€鏌TG绋嬪簭
    if [ -f "./mtg" ]; then
        echo -e "MTG绋嬪簭: ${GREEN}瀛樺湪${NC}"
        local mtg_version=$(./mtg --version 2>/dev/null | head -1 || echo "鏈煡鐗堟湰")
        echo -e "MTG鐗堟湰: ${GREEN}$mtg_version${NC}"
    else
        echo -e "MTG绋嬪簭: ${RED}涓嶅瓨鍦?{NC}"
        return 1
    fi
    
    # 妫€鏌ヨ繘绋嬬姸鎬?    local pid=$(check_process_status)
    if [ $? -eq 0 ]; then
        echo -e "杩涚▼鐘舵€? ${GREEN}杩愯涓?{NC} (PID: $pid)"
        
        # 妫€鏌ヨ繘绋嬭鎯?        local process_info=$(ps aux | grep $pid | grep -v grep | head -1)
        echo -e "杩涚▼淇℃伅: ${CYAN}$process_info${NC}"
        
        # 妫€鏌ョ鍙ｇ洃鍚?        if is_port_occupied $port; then
            echo -e "绔彛鐩戝惉: ${GREEN}姝ｅ父${NC} ($port)"
        else
            echo -e "绔彛鐩戝惉: ${RED}寮傚父${NC} ($port)"
        fi
    else
        echo -e "杩涚▼鐘舵€? ${YELLOW}鏈繍琛?{NC} (鏃燩ID鏂囦欢)"
    fi
    
    # 妫€鏌ユ墍鏈塵tg杩涚▼
    local mtg_processes=$(ps aux | grep -v grep | grep mtg | wc -l)
    if [ $mtg_processes -gt 0 ]; then
        echo -e "MTG杩涚▼鏁? ${GREEN}$mtg_processes${NC}"
        ps aux | grep -v grep | grep mtg | while read line; do
            echo -e "  ${CYAN}$line${NC}"
        done
    else
        echo -e "MTG杩涚▼鏁? ${YELLOW}0${NC}"
    fi
}

# 渚濊禆妫€鏌?check_dependencies() {
    function_header "渚濊禆妫€鏌?
    
    local deps=("curl" "wget" "netstat" "ps" "kill" "tar" "od")
    
    for dep in "${deps[@]}"; do
        if command -v $dep >/dev/null 2>&1; then
            echo -e "$dep: ${GREEN}宸插畨瑁?{NC}"
        else
            echo -e "$dep: ${RED}鏈畨瑁?{NC}"
        fi
    done
    
    # 妫€鏌ョ壒瀹氱郴缁熺殑鍖?    case $OS in
        "alpine")
            local alpine_deps=("procps" "net-tools")
            for dep in "${alpine_deps[@]}"; do
                if apk info -e $dep >/dev/null 2>&1; then
                    echo -e "$dep: ${GREEN}宸插畨瑁?{NC}"
                else
                    echo -e "$dep: ${RED}鏈畨瑁?{NC}"
                fi
            done
            ;;
        "rhel")
            local rhel_deps=("procps-ng" "net-tools")
            for dep in "${rhel_deps[@]}"; do
                if rpm -q $dep >/dev/null 2>&1; then
                    echo -e "$dep: ${GREEN}宸插畨瑁?{NC}"
                else
                    echo -e "$dep: ${RED}鏈畨瑁?{NC}"
                fi
            done
            ;;
        "debian")
            local debian_deps=("procps" "net-tools")
            for dep in "${debian_deps[@]}"; do
                if dpkg -l | grep -q "^ii  $dep "; then
                    echo -e "$dep: ${GREEN}宸插畨瑁?{NC}"
                else
                    echo -e "$dep: ${RED}鏈畨瑁?{NC}"
                fi
            done
            ;;
    esac
}

# ==================== 鏍稿績鍔熻兘鍑芥暟 ====================

# 涓嬭浇MTG
download_mtg() {
    local arch=$(get_architecture)
    local url="https://github.com/9seconds/mtg/releases/download/v1.0.11/mtg-1.0.11-linux-$arch.tar.gz"

    print_info "涓嬭浇MTG ($arch)..."
    wget $url -O mtg.tar.gz -q --timeout=30 || {
        print_error "涓嬭浇澶辫触锛岃妫€鏌ョ綉缁滆繛鎺?
        return 1
    }

    tar -xzf mtg.tar.gz mtg-1.0.11-linux-$arch/mtg --strip-components 1
    chmod +x mtg
    rm -f mtg.tar.gz

    if [ -f "./mtg" ]; then
        print_success "MTG涓嬭浇瀹屾垚"
    else
        print_error "MTG瀹夎澶辫触"
        return 1
    fi
}

# 瀹夎渚濊禆
install_dependencies() {
    print_info "瀹夎绯荤粺渚濊禆..."
    case $OS in
        "alpine")
            apk update && apk add --no-cache curl wget procps net-tools
            ;;
        "rhel")
            $PKG_MANAGER install -y curl wget procps-ng net-tools
            ;;
        "debian")
            apt update && apt install -y curl wget procps net-tools
            ;;
    esac

    if [ $? -eq 0 ]; then
        print_success "渚濊禆瀹夎瀹屾垚"
    else
        print_error "渚濊禆瀹夎澶辫触"
        return 1
    fi
}

# 閰嶇疆MTProxy
config_mtproxy() {
    function_header "閰嶇疆MTProxy"

    # 绔彛閰嶇疆
    while true; do
        read -p "璇疯緭鍏ュ鎴风杩炴帴绔彛 (榛樿 443): " input_port
        [ -z "$input_port" ] && input_port=443

        if validate_port $input_port; then
            if is_port_occupied $input_port; then
                print_warning "绔彛 $input_port 宸茶鍗犵敤"
                get_port_process $input_port
                read -p "鏄惁缁х画浣跨敤姝ょ鍙? (y/N): " continue_port
                if [[ "$continue_port" == "y" || "$continue_port" == "Y" ]]; then
                    break
                fi
            else
                break
            fi
        else
            print_error "璇疯緭鍏ユ湁鏁堢殑绔彛鍙?[1-65535]"
        fi
    done

    # 绠＄悊绔彛閰嶇疆
    while true; do
        read -p "璇疯緭鍏ョ鐞嗙鍙?(榛樿 8888): " input_manage_port
        [ -z "$input_manage_port" ] && input_manage_port=8888

        if validate_port $input_manage_port; then
            if [ $input_manage_port -eq $input_port ]; then
                print_error "绠＄悊绔彛涓嶈兘涓庡鎴风绔彛鐩稿悓"
            elif is_port_occupied $input_manage_port; then
                print_warning "绔彛 $input_manage_port 宸茶鍗犵敤"
                read -p "鏄惁缁х画浣跨敤姝ょ鍙? (y/N): " continue_port
                if [[ "$continue_port" == "y" || "$continue_port" == "Y" ]]; then
                    break
                fi
            else
                break
            fi
        else
            print_error "璇疯緭鍏ユ湁鏁堢殑绔彛鍙?[1-65535]"
        fi
    done

    # 鍩熷悕閰嶇疆
    read -p "璇疯緭鍏ヤ吉瑁呭煙鍚?(榛樿 azure.microsoft.com): " input_domain
    [ -z "$input_domain" ] && input_domain="azure.microsoft.com"

    # TAG閰嶇疆
    read -p "璇疯緭鍏ユ帹骞縏AG (鍙€夛紝鐩存帴鍥炶溅璺宠繃): " input_tag

    # 鐢熸垚閰嶇疆
    local secret=$(gen_rand_hex 32)

    cat > ./mtp_config <<EOF
secret="$secret"
port=$input_port
web_port=$input_manage_port
domain="$input_domain"
proxy_tag="$input_tag"
os="$OS"
pkg_manager="$PKG_MANAGER"
EOF

    print_success "閰嶇疆鐢熸垚瀹屾垚"
    show_firewall_commands $input_port $input_manage_port
}

# 鍚姩MTProxy
start_mtproxy() {
    if ! load_config; then
        return 1
    fi

    # 妫€鏌ユ槸鍚﹀凡杩愯
    local pid=$(check_process_status)
    if [ $? -eq 0 ]; then
        print_warning "MTProxy宸茬粡鍦ㄨ繍琛屼腑 (PID: $pid)"
        return 0
    fi

    # 妫€鏌TG绋嬪簭
    if [ ! -f "./mtg" ]; then
        print_error "MTG绋嬪簭涓嶅瓨鍦紝璇烽噸鏂板畨瑁?
        return 1
    fi

    # 閲婃斁绔彛
    release_port $port
    release_port $web_port

    # 鍒涘缓蹇呰鐩綍
    create_directories

    # 鏋勫缓杩愯鍛戒护
    local client_secret=$(generate_client_secret)

    print_info "姝ｅ湪鍚姩MTProxy..."
    print_info "妫€娴嬬綉缁滅幆澧?.."

    # 鐢熸垚閫傚悎褰撳墠缃戠粶鐜鐨勫惎鍔ㄥ弬鏁?    local mtg_cmd=$(generate_mtg_params "$client_secret" "$proxy_tag" "$port" "$web_port")

    print_debug "缃戠粶鐜: $NETWORK_TYPE"
    print_debug "鍚姩鍛戒护: $mtg_cmd"

    # 鍚姩MTG (娣诲姞鏃ュ織杈撳嚭)
    local log_file="./logs/mtproxy.log"
    eval "$mtg_cmd >> $log_file 2>&1 &"

    echo $! > $pid_file
    sleep 3

    # 妫€鏌ュ惎鍔ㄧ姸鎬?    local pid=$(check_process_status)
    if [ $? -eq 0 ]; then
        print_success "MTProxy鍚姩鎴愬姛 (PID: $pid)"
        print_info "鏃ュ織鏂囦欢: $log_file"
        show_proxy_info
    else
        print_error "MTProxy鍚姩澶辫触"
        print_info "鏌ョ湅鏃ュ織: tail -f $log_file"
        return 1
    fi
}

# 鍋滄MTProxy
stop_mtproxy() {
    local pid=$(check_process_status)
    if [ $? -eq 0 ]; then
        print_info "姝ｅ湪鍋滄MTProxy (PID: $pid)..."
        kill -9 $pid 2>/dev/null
        rm -f $pid_file
    fi

    # 棰濆纭繚鎵€鏈塵tg杩涚▼琚潃姝?    pkill -f mtg 2>/dev/null

    sleep 1

    # 妫€鏌ユ槸鍚﹁繕鏈塵tg杩涚▼
    if pgrep -f mtg >/dev/null 2>&1; then
        print_warning "浠嶆湁MTG杩涚▼鍦ㄨ繍琛岋紝寮哄埗缁堟..."
        pkill -9 -f mtg 2>/dev/null
    fi

    print_success "MTProxy宸插仠姝?
}

# 鏄剧ず浠ｇ悊淇℃伅
show_proxy_info() {
    if ! load_config; then
        return 1
    fi

    ensure_network_detected
    local client_secret=$(generate_client_secret)

    print_line
    local pid=$(check_process_status)
    if [ $? -eq 0 ]; then
        print_success "MTProxy鐘舵€? 杩愯涓?
    else
        print_warning "MTProxy鐘舵€? 宸插仠姝?
    fi

    echo -e "绯荤粺绫诲瀷: ${PURPLE}$os${NC}"
    echo -e "缃戠粶鐜: ${PURPLE}$NETWORK_TYPE${NC}"

    if [[ "$HAS_IPV4" == true ]]; then
        echo -e "鏈嶅姟鍣↖Pv4: ${GREEN}$PUBLIC_IPV4${NC}"
        [[ "$IS_WARP" == true ]] && echo -e "WARP鐘舵€? ${YELLOW}宸插惎鐢?{NC}"
    fi

    if [[ "$HAS_IPV6" == true ]]; then
        echo -e "鏈嶅姟鍣↖Pv6: ${GREEN}$PUBLIC_IPV6${NC}"
    fi

    [[ "$IS_NAT" == true ]] && echo -e "NAT鐜: ${YELLOW}鏄?{NC} (鏈湴IP: $LOCAL_IP)"

    echo -e "瀹㈡埛绔鍙? ${GREEN}$port${NC}"
    echo -e "绠＄悊绔彛: ${GREEN}$web_port${NC}"
    echo -e "浠ｇ悊瀵嗛挜: ${GREEN}$client_secret${NC}"
    echo -e "浼鍩熷悕: ${GREEN}$domain${NC}"
    [[ -n "$proxy_tag" ]] && echo -e "鎺ㄥ箍TAG: ${GREEN}$proxy_tag${NC}"

    # 鏍规嵁缃戠粶鐜鏄剧ず杩炴帴閾炬帴
    if [[ "$HAS_IPV4" == true ]]; then
        echo -e "\n${BLUE}Telegram杩炴帴閾炬帴 (IPv4):${NC}"
        echo "https://t.me/proxy?server=${PUBLIC_IPV4}&port=${port}&secret=${client_secret}"
        echo "tg://proxy?server=${PUBLIC_IPV4}&port=${port}&secret=${client_secret}"
    fi

    if [[ "$HAS_IPV6" == true ]]; then
        echo -e "\n${BLUE}Telegram杩炴帴閾炬帴 (IPv6):${NC}"
        echo "https://t.me/proxy?server=${PUBLIC_IPV6}&port=${port}&secret=${client_secret}"
        echo "tg://proxy?server=${PUBLIC_IPV6}&port=${port}&secret=${client_secret}"
    fi

    # 鏄剧ず缃戠粶鐜鐗瑰畾鐨勬彁绀?    case "$NETWORK_TYPE" in
        "warp_proxy")
            echo -e "\n${YELLOW}鎻愮ず: 妫€娴嬪埌WARP浠ｇ悊鐜锛屽鏋滆繛鎺ユ湁闂璇峰皾璇曢噸鍚湇鍔?{NC}"
            ;;
        "ipv6_only")
            echo -e "\n${YELLOW}鎻愮ず: 绾疘Pv6鐜锛岀‘淇濆鎴风鏀寔IPv6杩炴帴${NC}"
            ;;
        "ipv4_only")
            echo -e "\n${GREEN}鎻愮ず: 绾疘Pv4鐜锛岃繛鎺ュ簲璇ョǔ瀹?{NC}"
            ;;
        "dual_stack")
            echo -e "\n${GREEN}鎻愮ず: 鍙屾爤鐜锛孖Pv4鍜孖Pv6閮藉彲鐢?{NC}"
            ;;
    esac

    print_line
}

# ==================== 楂樼骇鍔熻兘鍑芥暟 ====================

# 杩炴帴娴嬭瘯
test_connection() {
    function_header "杩炴帴娴嬭瘯"
    
    if ! load_config; then
        return 1
    fi
    
    local public_ip=$(curl -s --connect-timeout 6 https://api.ip.sb/ip -A Mozilla --ipv4)
    
    # 娴嬭瘯绔彛杩為€氭€?    print_info "娴嬭瘯绔彛杩為€氭€?.."
    if timeout 5 bash -c "</dev/tcp/127.0.0.1/$port" 2>/dev/null; then
        echo -e "鏈湴绔彛 $port: ${GREEN}鍙繛鎺?{NC}"
    else
        echo -e "鏈湴绔彛 $port: ${RED}鏃犳硶杩炴帴${NC}"
    fi
    
    if timeout 5 bash -c "</dev/tcp/127.0.0.1/$web_port" 2>/dev/null; then
        echo -e "绠＄悊绔彛 $web_port: ${GREEN}鍙繛鎺?{NC}"
    else
        echo -e "绠＄悊绔彛 $web_port: ${RED}鏃犳硶杩炴帴${NC}"
    fi
    
    # 娴嬭瘯澶栭儴杩炴帴
    print_info "娴嬭瘯澶栭儴杩炴帴..."

    ensure_network_detected

    # 娴嬭瘯IPv4澶栭儴杩炴帴
    if [[ "$HAS_IPV4" == true && -n "$PUBLIC_IPV4" ]]; then
        print_info "娴嬭瘯IPv4澶栭儴杩炴帴 ($PUBLIC_IPV4:$port)..."
        if timeout 10 bash -c "</dev/tcp/$PUBLIC_IPV4/$port" 2>/dev/null; then
            echo -e "IPv4澶栭儴绔彛 $port: ${GREEN}鍙繛鎺?{NC}"
        else
            echo -e "IPv4澶栭儴绔彛 $port: ${RED}鏃犳硶杩炴帴${NC}"
            if [[ "$IS_NAT" == true ]]; then
                echo -e "  ${YELLOW}鎻愮ず: 妫€娴嬪埌NAT鐜锛屽彲鑳介渶瑕佺鍙ｆ槧灏?{NC}"
            fi
        fi
    fi

    # 娴嬭瘯IPv6澶栭儴杩炴帴
    if [[ "$HAS_IPV6" == true && -n "$PUBLIC_IPV6" ]]; then
        print_info "娴嬭瘯IPv6澶栭儴杩炴帴 ([$PUBLIC_IPV6]:$port)..."
        # IPv6杩炴帴娴嬭瘯闇€瑕佺壒娈婂鐞?        if command -v nc >/dev/null 2>&1; then
            if timeout 10 nc -6 -z "$PUBLIC_IPV6" "$port" 2>/dev/null; then
                echo -e "IPv6澶栭儴绔彛 $port: ${GREEN}鍙繛鎺?{NC}"
            else
                echo -e "IPv6澶栭儴绔彛 $port: ${RED}鏃犳硶杩炴帴${NC}"
            fi
        else
            echo -e "IPv6澶栭儴绔彛 $port: ${YELLOW}鏃犳硶娴嬭瘯 (缂哄皯nc宸ュ叿)${NC}"
        fi
    else
        echo -e "IPv6杩炴帴: ${YELLOW}涓嶅彲鐢紝璺宠繃IPv6杩炴帴娴嬭瘯${NC}"
    fi

    # 鐢熸垚杩炴帴淇℃伅
    local client_secret=$(generate_client_secret)

    print_info "杩炴帴淇℃伅:"
    echo -e "缃戠粶鐜: ${GREEN}$NETWORK_TYPE${NC}"

    if [[ "$HAS_IPV4" == true ]]; then
        echo -e "鏈嶅姟鍣↖Pv4: ${GREEN}$PUBLIC_IPV4${NC}"
    fi
    if [[ "$HAS_IPV6" == true ]]; then
        echo -e "鏈嶅姟鍣↖Pv6: ${GREEN}$PUBLIC_IPV6${NC}"
    fi

    echo -e "绔彛: ${GREEN}$port${NC}"
    echo -e "瀵嗛挜: ${GREEN}$client_secret${NC}"
    echo ""

    # 鐢熸垚杩炴帴閾炬帴
    if [[ "$HAS_IPV4" == true ]]; then
        echo -e "${BLUE}Telegram杩炴帴閾炬帴 (IPv4):${NC}"
        echo "https://t.me/proxy?server=${PUBLIC_IPV4}&port=${port}&secret=${client_secret}"
        echo "tg://proxy?server=${PUBLIC_IPV4}&port=${port}&secret=${client_secret}"
        echo ""
    fi

    if [[ "$HAS_IPV6" == true ]]; then
        echo -e "${BLUE}Telegram杩炴帴閾炬帴 (IPv6):${NC}"
        echo "https://t.me/proxy?server=${PUBLIC_IPV6}&port=${port}&secret=${client_secret}"
        echo "tg://proxy?server=${PUBLIC_IPV6}&port=${port}&secret=${client_secret}"
    fi
}

# 缃戠粶鐜璇婃柇
diagnose_network_issues() {
    function_header "MTProxy 缃戠粶闂璇婃柇"

    # 鍏堣繘琛屽熀鏈殑缃戠粶妫€鏌?    ensure_network_detected

    print_info "馃攳 缃戠粶鐜鍒嗘瀽"
    echo -e "褰撳墠鐜: ${GREEN}$NETWORK_TYPE${NC}"

    # 閽堝涓嶅悓鐜鎻愪緵璇︾粏鐨勮瘖鏂拰寤鸿
    case "$NETWORK_TYPE" in
        "dual_stack")
            print_success "鉁?鍙屾爤鐜 - 鏈€浣抽厤缃?
            echo "  馃搵 璇婃柇缁撴灉:"
            echo "    - IPv4鍜孖Pv6閮藉彲鐢?
            echo "    - MTProxy灏嗕紭鍏堜娇鐢↖Pv4"
            echo "    - 瀹㈡埛绔彲閫夋嫨IPv4鎴朓Pv6杩炴帴"
            ;;
        "ipv4_only")
            print_warning "鈿?绾疘Pv4鐜"
            echo "  馃搵 璇婃柇缁撴灉:"
            echo "    - 鍙湁IPv4鍙敤"
            echo "    - IPv6杩炴帴閾炬帴灏嗘棤娉曚娇鐢?
            echo "  馃挕 浼樺寲寤鸿:"
            echo "    - 鑰冭檻鍚敤IPv6锛堝鏋滄湇鍔″晢鏀寔锛?
            echo "    - 纭繚IPv4杩炴帴绋冲畾鎬?
            ;;
        "ipv6_only")
            print_warning "鈿?绾疘Pv6鐜"
            echo "  馃搵 璇婃柇缁撴灉:"
            echo "    - 鍙湁IPv6鍙敤"
            echo "    - IPv4杩炴帴閾炬帴灏嗘棤娉曚娇鐢?
            echo "  馃挕 浼樺寲寤鸿:"
            echo "    - 閰嶇疆IPv4闅ч亾鎴朜AT64"
            echo "    - 鎴栦娇鐢╓ARP鑾峰彇IPv4杩炴帴"
            echo "    - 纭繚瀹㈡埛绔敮鎸両Pv6"
            ;;
        "warp_proxy")
            print_warning "鈿?WARP浠ｇ悊鐜"
            echo "  馃搵 璇婃柇缁撴灉:"
            echo "    - 妫€娴嬪埌Cloudflare WARP"
            echo "    - 鍙兘瀛樺湪杩炴帴绋冲畾鎬ч棶棰?
            echo "  馃挕 浼樺寲寤鸿:"
            echo "    - 灏濊瘯閲嶅惎WARP: warp-cli disconnect && warp-cli connect"
            echo "    - 鎴栬€冭檻浣跨敤鍘熺敓IPv6"
            echo "    - 鐩戞帶杩炴帴绋冲畾鎬?
            ;;
        "unknown")
            print_error "鉁?缃戠粶鐜寮傚父"
            echo "  馃搵 璇婃柇缁撴灉:"
            echo "    - 鏃犳硶鑾峰彇鏈夋晥鐨勫叕缃慖P"
            echo "    - 鍙兘瀛樺湪缃戠粶杩炴帴闂"
            echo "  馃敡 鏁呴殰鎺掗櫎:"
            echo "    - 妫€鏌ョ綉缁滆繛鎺? ping 8.8.8.8"
            echo "    - 妫€鏌NS瑙ｆ瀽: nslookup google.com"
            echo "    - 妫€鏌ラ槻鐏璁剧疆"
            ;;
    esac

    echo ""

    # MTProxy鐗瑰畾鐨勮瘖鏂?    if load_config; then
        print_info "馃攳 MTProxy閰嶇疆璇婃柇"

        # 妫€鏌ョ鍙ｅ崰鐢?        if is_port_occupied $port; then
            local process=$(get_port_process $port)
            if [[ "$process" == *"mtg"* ]]; then
                print_success "鉁?绔彛 $port 琚玀TProxy姝ｅ父鍗犵敤"
            else
                print_error "鉁?绔彛 $port 琚叾浠栬繘绋嬪崰鐢? $process"
                echo "  馃敡 瑙ｅ喅鏂规: 鍋滄鍗犵敤杩涚▼鎴栨洿鎹㈢鍙?
            fi
        else
            print_warning "鈿?绔彛 $port 鏈鍗犵敤"
            echo "  馃挕 鍙兘鍘熷洜: MTProxy鏈惎鍔ㄦ垨鍚姩澶辫触"
        fi

        # 妫€鏌ラ槻鐏閰嶇疆
        print_info "馃攳 闃茬伀澧欓厤缃鏌?
        case $OS in
            "rhel")
                if systemctl is-active firewalld >/dev/null 2>&1; then
                    if firewall-cmd --list-ports | grep -q "$port/tcp"; then
                        print_success "鉁?Firewalld绔彛 $port 宸插紑鏀?
                    else
                        print_error "鉁?Firewalld绔彛 $port 鏈紑鏀?
                        echo "  馃敡 瑙ｅ喅鏂规:"
                        echo "    firewall-cmd --permanent --add-port=$port/tcp"
                        echo "    firewall-cmd --permanent --add-port=$web_port/tcp"
                        echo "    firewall-cmd --reload"
                    fi
                else
                    print_info "鈩?Firewalld鏈繍琛?
                fi
                ;;
            "debian")
                if command -v ufw >/dev/null 2>&1 && ufw status | grep -q "Status: active"; then
                    if ufw status | grep -q "$port/tcp"; then
                        print_success "鉁?UFW绔彛 $port 宸插紑鏀?
                    else
                        print_error "鉁?UFW绔彛 $port 鏈紑鏀?
                        echo "  馃敡 瑙ｅ喅鏂规:"
                        echo "    ufw allow $port/tcp"
                        echo "    ufw allow $web_port/tcp"
                    fi
                else
                    print_info "鈩?UFW鏈縺娲绘垨鏈畨瑁?
                fi
                ;;
            "alpine")
                print_info "鈩?Alpine Linux閫氬父鏃犻渶棰濆闃茬伀澧欓厤缃?
                ;;
        esac

        # 杩炴帴娴嬭瘯寤鸿
        echo ""
        print_info "馃攳 杩炴帴娴嬭瘯寤鸿"
        echo "1. 鏈湴娴嬭瘯: telnet 127.0.0.1 $port"
        if [[ "$HAS_IPV4" == true ]]; then
            echo "2. IPv4娴嬭瘯: telnet $PUBLIC_IPV4 $port"
        fi
        if [[ "$HAS_IPV6" == true ]]; then
            echo "3. IPv6娴嬭瘯: telnet $PUBLIC_IPV6 $port"
        fi
        echo "4. 浣跨敤Telegram瀹㈡埛绔祴璇曡繛鎺ラ摼鎺?

    else
        print_warning "鈿?MTProxy閰嶇疆鏂囦欢涓嶅瓨鍦?
        echo "  馃挕 寤鸿: 鍏堣繍琛屽畨瑁呯▼搴忓垱寤洪厤缃?
    fi
}

# 鑷姩淇鍔熻兘
auto_fix() {
    function_header "鑷姩淇鍔熻兘"

    # 缃戠粶鐜璇婃柇
    diagnose_network_issues

    # 瀹夎缂哄け鐨勪緷璧?    print_info "妫€鏌ュ苟瀹夎缂哄け鐨勪緷璧?.."
    case $OS in
        "alpine")
            apk update >/dev/null 2>&1
            apk add --no-cache curl wget procps net-tools netcat-openbsd >/dev/null 2>&1
            ;;
        "rhel")
            $PKG_MANAGER install -y curl wget procps-ng net-tools nc >/dev/null 2>&1
            ;;
        "debian")
            apt update >/dev/null 2>&1
            apt install -y curl wget procps net-tools netcat >/dev/null 2>&1
            ;;
    esac
    print_success "渚濊禆妫€鏌ュ畬鎴?

    # 娓呯悊鍍靛案杩涚▼
    print_info "娓呯悊鍙兘鐨勫兊灏歌繘绋?.."
    pkill -f mtg 2>/dev/null
    rm -f $pid_file
    print_success "杩涚▼娓呯悊瀹屾垚"

    # 妫€鏌ュ苟淇MTG绋嬪簭
    if [ ! -f "./mtg" ]; then
        print_info "MTG绋嬪簭涓嶅瓨鍦紝姝ｅ湪涓嬭浇..."
        download_mtg
    fi

    # 淇鏉冮檺
    print_info "淇鏂囦欢鏉冮檺..."
    chmod +x ./mtg 2>/dev/null
    chmod +x ./*.sh 2>/dev/null
    print_success "鏉冮檺淇瀹屾垚"

    # 鏍规嵁缃戠粶鐜缁欏嚭寤鸿
    print_info "缃戠粶鐜浼樺寲寤鸿..."
    ensure_network_detected
    case "$NETWORK_TYPE" in
        "warp_proxy")
            print_warning "WARP鐜寤鸿:"
            echo "- 鑰冭檻閲嶅惎WARP鏈嶅姟"
            echo "- 鎴栧皾璇曚娇鐢ㄥ師鐢烮Pv6"
            ;;
        "ipv6_only")
            print_warning "IPv6鐜寤鸿:"
            echo "- 纭繚瀹㈡埛绔敮鎸両Pv6"
            echo "- 鑰冭檻閰嶇疆IPv4闅ч亾"
            ;;
        "unknown")
            print_error "缃戠粶鐜寮傚父锛屽缓璁鏌ョ綉缁滈厤缃?
            ;;
    esac
}

# ==================== 楂樼骇鍔熻兘鍑芥暟 ====================

# 杩炴帴娴嬭瘯
test_connection() {
    function_header "杩炴帴娴嬭瘯"
    
    if ! load_config; then
        return 1
    fi
    
    local public_ip=$(curl -s --connect-timeout 6 https://api.ip.sb/ip -A Mozilla --ipv4)
    
    # 娴嬭瘯绔彛杩為€氭€?    print_info "娴嬭瘯绔彛杩為€氭€?.."
    if timeout 5 bash -c "</dev/tcp/127.0.0.1/$port" 2>/dev/null; then
        echo -e "鏈湴绔彛 $port: ${GREEN}鍙繛鎺?{NC}"
    else
        echo -e "鏈湴绔彛 $port: ${RED}鏃犳硶杩炴帴${NC}"
    fi
    
    if timeout 5 bash -c "</dev/tcp/127.0.0.1/$web_port" 2>/dev/null; then
        echo -e "绠＄悊绔彛 $web_port: ${GREEN}鍙繛鎺?{NC}"
    else
        echo -e "绠＄悊绔彛 $web_port: ${RED}鏃犳硶杩炴帴${NC}"
    fi
    
    # 娴嬭瘯澶栭儴杩炴帴
    print_info "娴嬭瘯澶栭儴杩炴帴..."

    ensure_network_detected

    # 娴嬭瘯IPv4澶栭儴杩炴帴
    if [[ "$HAS_IPV4" == true && -n "$PUBLIC_IPV4" ]]; then
        print_info "娴嬭瘯IPv4澶栭儴杩炴帴 ($PUBLIC_IPV4:$port)..."
        if timeout 10 bash -c "</dev/tcp/$PUBLIC_IPV4/$port" 2>/dev/null; then
            echo -e "IPv4澶栭儴绔彛 $port: ${GREEN}鍙繛鎺?{NC}"
        else
            echo -e "IPv4澶栭儴绔彛 $port: ${RED}鏃犳硶杩炴帴${NC}"
            if [[ "$IS_NAT" == true ]]; then
                echo -e "  ${YELLOW}鎻愮ず: 妫€娴嬪埌NAT鐜锛屽彲鑳介渶瑕佺鍙ｆ槧灏?{NC}"
            fi
        fi
    fi

    # 娴嬭瘯IPv6澶栭儴杩炴帴
    if [[ "$HAS_IPV6" == true && -n "$PUBLIC_IPV6" ]]; then
        print_info "娴嬭瘯IPv6澶栭儴杩炴帴 ([$PUBLIC_IPV6]:$port)..."
        # IPv6杩炴帴娴嬭瘯闇€瑕佺壒娈婂鐞?        if command -v nc >/dev/null 2>&1; then
            if timeout 10 nc -6 -z "$PUBLIC_IPV6" "$port" 2>/dev/null; then
                echo -e "IPv6澶栭儴绔彛 $port: ${GREEN}鍙繛鎺?{NC}"
            else
                echo -e "IPv6澶栭儴绔彛 $port: ${RED}鏃犳硶杩炴帴${NC}"
            fi
        else
            echo -e "IPv6澶栭儴绔彛 $port: ${YELLOW}鏃犳硶娴嬭瘯 (缂哄皯nc宸ュ叿)${NC}"
        fi
    else
        echo -e "IPv6杩炴帴: ${YELLOW}涓嶅彲鐢紝璺宠繃IPv6杩炴帴娴嬭瘯${NC}"
    fi

    # 鐢熸垚杩炴帴淇℃伅
    local client_secret=$(generate_client_secret)

    print_info "杩炴帴淇℃伅:"
    echo -e "缃戠粶鐜: ${GREEN}$NETWORK_TYPE${NC}"

    if [[ "$HAS_IPV4" == true ]]; then
        echo -e "鏈嶅姟鍣↖Pv4: ${GREEN}$PUBLIC_IPV4${NC}"
    fi
    if [[ "$HAS_IPV6" == true ]]; then
        echo -e "鏈嶅姟鍣↖Pv6: ${GREEN}$PUBLIC_IPV6${NC}"
    fi

    echo -e "绔彛: ${GREEN}$port${NC}"
    echo -e "瀵嗛挜: ${GREEN}$client_secret${NC}"
    echo ""

    # 鐢熸垚杩炴帴閾炬帴
    if [[ "$HAS_IPV4" == true ]]; then
        echo -e "${BLUE}Telegram杩炴帴閾炬帴 (IPv4):${NC}"
        echo "https://t.me/proxy?server=${PUBLIC_IPV4}&port=${port}&secret=${client_secret}"
        echo "tg://proxy?server=${PUBLIC_IPV4}&port=${port}&secret=${client_secret}"
        echo ""
    fi

    if [[ "$HAS_IPV6" == true ]]; then
        echo -e "${BLUE}Telegram杩炴帴閾炬帴 (IPv6):${NC}"
        echo "https://t.me/proxy?server=${PUBLIC_IPV6}&port=${port}&secret=${client_secret}"
        echo "tg://proxy?server=${PUBLIC_IPV6}&port=${port}&secret=${client_secret}"
    fi
}

# 缃戠粶鐜璇婃柇
diagnose_network_issues() {
    function_header "MTProxy 缃戠粶闂璇婃柇"

    # 鍏堣繘琛屽熀鏈殑缃戠粶妫€鏌?    ensure_network_detected

    print_info "馃攳 缃戠粶鐜鍒嗘瀽"
    echo -e "褰撳墠鐜: ${GREEN}$NETWORK_TYPE${NC}"

    # 閽堝涓嶅悓鐜鎻愪緵璇︾粏鐨勮瘖鏂拰寤鸿
    case "$NETWORK_TYPE" in
        "dual_stack")
            print_success "鉁?鍙屾爤鐜 - 鏈€浣抽厤缃?
            echo "  馃搵 璇婃柇缁撴灉:"
            echo "    - IPv4鍜孖Pv6閮藉彲鐢?
            echo "    - MTProxy灏嗕紭鍏堜娇鐢↖Pv4"
            echo "    - 瀹㈡埛绔彲閫夋嫨IPv4鎴朓Pv6杩炴帴"
            ;;
        "ipv4_only")
            print_warning "鈿?绾疘Pv4鐜"
            echo "  馃搵 璇婃柇缁撴灉:"
            echo "    - 鍙湁IPv4鍙敤"
            echo "    - IPv6杩炴帴閾炬帴灏嗘棤娉曚娇鐢?
            echo "  馃挕 浼樺寲寤鸿:"
            echo "    - 鑰冭檻鍚敤IPv6锛堝鏋滄湇鍔″晢鏀寔锛?
            echo "    - 纭繚IPv4杩炴帴绋冲畾鎬?
            ;;
        "ipv6_only")
            print_warning "鈿?绾疘Pv6鐜"
            echo "  馃搵 璇婃柇缁撴灉:"
            echo "    - 鍙湁IPv6鍙敤"
            echo "    - IPv4杩炴帴閾炬帴灏嗘棤娉曚娇鐢?
            echo "  馃挕 浼樺寲寤鸿:"
            echo "    - 閰嶇疆IPv4闅ч亾鎴朜AT64"
            echo "    - 鎴栦娇鐢╓ARP鑾峰彇IPv4杩炴帴"
            echo "    - 纭繚瀹㈡埛绔敮鎸両Pv6"
            ;;
        "warp_proxy")
            print_warning "鈿?WARP浠ｇ悊鐜"
            echo "  馃搵 璇婃柇缁撴灉:"
            echo "    - 妫€娴嬪埌Cloudflare WARP"
            echo "    - 鍙兘瀛樺湪杩炴帴绋冲畾鎬ч棶棰?
            echo "  馃挕 浼樺寲寤鸿:"
    # 鍋滄褰撳墠鏈嶅姟
    if check_process_status >/dev/null; then
        print_info "鍋滄褰撳墠MTProxy鏈嶅姟..."
        stop_mtproxy
    fi
    
    # 鏇存柊閰嶇疆
    print_info "鏇存柊閰嶇疆鏂囦欢..."
    sed -i "s/port=$port/port=$new_port/" ./mtp_config
    sed -i "s/web_port=$web_port/web_port=$new_web_port/" ./mtp_config
    
    print_success "绔彛閰嶇疆宸叉洿鏂?
    print_info "鏂伴厤缃?"
    echo "  瀹㈡埛绔鍙? $new_port"
    echo "  绠＄悊绔彛: $new_web_port"
    
    # 璇㈤棶鏄惁閲嶅惎鏈嶅姟
    read -p "鏄惁绔嬪嵆鍚姩鏈嶅姟? (y/N): " restart_confirm
    if [[ "$restart_confirm" =~ ^[Yy]$ ]]; then
        start_mtproxy
    fi
}

# 淇敼绔彛閰嶇疆
change_ports() {
    function_header "淇敼绔彛閰嶇疆"
    
    if ! load_config; then
        return 1
    fi
    
    print_info "褰撳墠閰嶇疆:"
    echo "  瀹㈡埛绔彛: $port"
    echo "  绠＄悊绔彛: $web_port"
    echo ""
    
    # 杈撳叆鏂扮鍙?    read -p "璇疯緭鍏ユ柊鐨勫瀹㈡埛绔彛 [$port]: " new_port
    if [ -z "$new_port" ]; then
        new_port=$port
    fi
    
    read -p "璇疯緭鍏ユ柊鐨勭鐞嗙鍙?[$web_port]: " new_web_port
    if [ -z "$new_web_port" ]; then
        new_web_port=$web_port
    fi
    
    # 楠岃瘉绔彛
    if ! validate_port $new_port; then
        print_error "鏃犳晥鐨勫瀹㈡埛绔彛: $new_port"
        return 1
    fi
    
    if ! validate_port $new_web_port; then
        print_error "鏃犳晥鐨勭鐞嗙鍙?$new_web_port"
        return 1
    fi
    
    # 妫€鏌ョ鍙崇煕鐩?    if [ "$new_port" != "$port" ] && is_port_occupied $new_port; then
        print_error "绔彛 $new_port 宸茶琚崰鐢?        return 1
    fi
    
    if [ "$new_web_port" != "$web_port" ] && is_port_occupied $new_web_port; then
        print_error "绔彛 $new_web_port 宸茶琚崰鐢?        return 1
    fi
    
    # 鍋滄鍚庡湪鏈嶅姟
    if check_process_status >/dev/null; then
        print_info "鍋滄褰撳墠MTProxy鏈嶅姟..."
        stop_mtproxy
    fi
    
    # 鏇存柊閰嶇疆
    print_info "鏇存柊閰嶇疆鏂囦欢..."
    sed -i "s/port=$port/port=$new_port/" ./mtp_config
    sed -i "s/web_port=$web_port/web_port=$new_web_port/" ./mtp_config
    
    print_success "绔彛閰嶇疆宸叉洿鏂?    print_info "鏂伴厤缃?    echo "  瀹㈡埛绔彛: $new_port"
    echo "  绠＄悊绔彛: $new_web_port"
    
    # 璇㈤棶鏄惁閲嶅惎鏈嶅姟
    read -p "鏄惁绔嬪嵆鍚姩鏈嶅姟? (y/N): " restart_confirm
    if [[ "$restart_confirm" =~ ^[Yy]$ ]]; then
        start_mtproxy
    fi
}

# 杩涚▼鐩戞帶鍜岃嚜鍔ㄩ噸鍚?monitor_mtproxy() {
    function_header "杩涚▼鐩戞帶鍜岃嚜鍔ㄩ噸鍚?
    
    print_info "鍚姩MTProxy杩涚▼鐩戞帶..."
    print_warning "鎸?Ctrl+C 鍋滄鐩戞帶"
    
    local restart_count=0
    local max_restarts=5
    local check_interval=30
    local last_restart_time=0
    
    while true; do
        local pid=$(check_process_status)
        if [ $? -eq 0 ]; then
            print_success "MTProxy杩愯姝ｅ父 (PID: $pid)"
            restart_count=0  # 閲嶇疆閲嶅惎璁℃暟
        else
            print_warning "MTProxy杩涚▼宸插仠姝紝灏濊瘯閲嶅惎..."
            
            # 妫€鏌ラ噸鍚鐜囬檺鍒?            local current_time=$(date +%s)
            if [ $((current_time - last_restart_time)) -lt 60 ]; then
                print_error "閲嶅惎杩囦簬棰戠箒锛岀瓑寰?0绉?.."
                sleep 60
                continue
            fi
            
            # 妫€鏌ユ渶澶ч噸鍚鏁?            if [ $restart_count -ge $max_restarts ]; then
                print_error "宸茶揪鍒版渶澶ч噸鍚鏁?($max_restarts)锛屽仠姝㈢洃鎺?
                break
            fi
            
            # 灏濊瘯閲嶅惎
            if start_mtproxy; then
                restart_count=$((restart_count + 1))
                last_restart_time=$current_time
                print_success "閲嶅惎鎴愬姛 (绗?$restart_count 娆?"
            else
                print_error "閲嶅惎澶辫触"
            fi
        fi
        
        sleep $check_interval
    done
}

# 鍒涘缓systemd鏈嶅姟
create_systemd_service() {
    function_header "鍒涘缓systemd鏈嶅姟"
    
    if [ $EUID -ne 0 ]; then
        print_error "鍒涘缓systemd鏈嶅姟闇€瑕乺oot鏉冮檺"
        return 1
    fi
    
    if ! load_config; then
        return 1
    fi
    
    local service_file="/etc/systemd/system/mtproxy.service"
    local script_path="$(pwd)/mtproxy.sh"
    
    print_info "鍒涘缓systemd鏈嶅姟鏂囦欢..."
    cat > $service_file <<EOF
[Unit]
Description=MTProxy Service
After=network.target

[Service]
Type=forking
User=root
WorkingDirectory=$(pwd)
ExecStart=$script_path start
ExecStop=$script_path stop
ExecReload=$script_path restart
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF
    
    # 閲嶈浇systemd骞跺惎鐢ㄦ湇鍔?    systemctl daemon-reload
    systemctl enable mtproxy
    
    print_success "systemd鏈嶅姟鍒涘缓鎴愬姛"
    print_info "鏈嶅姟绠＄悊鍛戒护:"
    echo "  鍚姩鏈嶅姟: systemctl start mtproxy"
    echo "  鍋滄鏈嶅姟: systemctl stop mtproxy"
    echo "  閲嶅惎鏈嶅姟: systemctl restart mtproxy"
    echo "  鏌ョ湅鐘舵€? systemctl status mtproxy"
    echo "  鏌ョ湅鏃ュ織: journalctl -u mtproxy -f"
    
    # 璇㈤棶鏄惁绔嬪嵆鍚姩
    read -p "鏄惁绔嬪嵆鍚姩systemd鏈嶅姟? (y/N): " start_confirm
    if [[ "$start_confirm" =~ ^[Yy]$ ]]; then
        systemctl start mtproxy
        sleep 2
        systemctl status mtproxy --no-pager
    fi
}

# 鍋ュ悍妫€鏌?health_check() {
    function_header "MTProxy鍋ュ悍妫€鏌?
    
    local health_score=0
    local max_score=100
    
    print_info "寮€濮嬪仴搴锋鏌?.."
    
    # 1. 妫€鏌ラ厤缃枃浠?(20鍒?
    if [ -f "./mtp_config" ]; then
        print_success "鉁?閰嶇疆鏂囦欢瀛樺湪 (+20鍒?"
        health_score=$((health_score + 20))
    else
        print_error "鉁?閰嶇疆鏂囦欢涓嶅瓨鍦?(-20鍒?"
    fi
    
    # 2. 妫€鏌TG绋嬪簭 (20鍒?
    if [ -f "./mtg" ] && [ -x "./mtg" ]; then
        print_success "鉁?MTG绋嬪簭瀛樺湪涓斿彲鎵ц (+20鍒?"
        health_score=$((health_score + 20))
    else
        print_error "鉁?MTG绋嬪簭涓嶅瓨鍦ㄦ垨涓嶅彲鎵ц (-20鍒?"
    fi
    
    # 3. 妫€鏌ヨ繘绋嬬姸鎬?(30鍒?
    local pid=$(check_process_status)
    if [ $? -eq 0 ]; then
        print_success "鉁?MTProxy杩涚▼杩愯姝ｅ父 (PID: $pid) (+30鍒?"
        health_score=$((health_score + 30))
        
        # 妫€鏌ュ唴瀛樹娇鐢?        local mem_usage=$(ps -o rss= -p $pid 2>/dev/null | awk '{print int($1/1024)}')
        if [ -n "$mem_usage" ]; then
            if [ $mem_usage -lt 100 ]; then
                print_success "鉁?鍐呭瓨浣跨敤姝ｅ父 (${mem_usage}MB) (+10鍒?"
                health_score=$((health_score + 10))
            else
                print_warning "鈿?鍐呭瓨浣跨敤杈冮珮 (${mem_usage}MB) (+5鍒?"
                health_score=$((health_score + 5))
            fi
        fi
    else
        print_error "鉁?MTProxy杩涚▼鏈繍琛?(-30鍒?"
    fi
    
    # 4. 妫€鏌ョ鍙ｇ洃鍚?(20鍒?
    if load_config; then
        if netstat -tulpn 2>/dev/null | grep -q ":$port "; then
            print_success "鉁?绔彛 $port 鐩戝惉姝ｅ父 (+20鍒?"
            health_score=$((health_score + 20))
        else
            print_error "鉁?绔彛 $port 鏈洃鍚?(-20鍒?"
        fi
    fi
    
    # 5. 妫€鏌ユ棩蹇楁枃浠?(10鍒?
    if [ -f "./logs/mtproxy.log" ]; then
        local log_size=$(stat -c%s "./logs/mtproxy.log" 2>/dev/null || echo "0")
        if [ $log_size -gt 0 ]; then
            print_success "鉁?鏃ュ織鏂囦欢姝ｅ父 (+10鍒?"
            health_score=$((health_score + 10))
        else
            print_warning "鈿?鏃ュ織鏂囦欢涓虹┖ (+5鍒?"
            health_score=$((health_score + 5))
        fi
    else
        print_warning "鈿?鏃ュ織鏂囦欢涓嶅瓨鍦?(+0鍒?"
    fi
    
    # 鏄剧ず鍋ュ悍璇勫垎
    print_line
    print_info "鍋ュ悍妫€鏌ュ畬鎴?
    echo -e "鍋ュ悍璇勫垎: ${GREEN}$health_score/$max_score${NC}"
    
    if [ $health_score -ge 90 ]; then
        print_success "馃帀 绯荤粺鐘舵€佷紭绉€"
    elif [ $health_score -ge 70 ]; then
        print_warning "鈿?绯荤粺鐘舵€佽壇濂斤紝鏈夋敼杩涚┖闂?
    elif [ $health_score -ge 50 ]; then
        print_warning "鈿?绯荤粺鐘舵€佷竴鑸紝寤鸿妫€鏌?
    else
        print_error "鉂?绯荤粺鐘舵€佽緝宸紝闇€瑕佷慨澶?
    fi
    
    print_line
}

# 瀹屽叏鍗歌浇MTProxy
uninstall_mtproxy() {
    function_header "瀹屽叏鍗歌浇MTProxy"
    
    print_warning "鈿?鍗冲皢瀹屽叏鍗歌浇MTProxy锛屽寘鎷墍鏈夐厤缃拰鏃ュ織鏂囦欢"
    read -p "纭缁х画? (y/N): " confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        print_info "鍙栨秷鍗歌浇"
        return 0
    fi
    
    # 1. 鍋滄MTProxy杩涚▼
    print_info "鍋滄MTProxy杩涚▼..."
    local pid=$(check_process_status)
    if [ $? -eq 0 ]; then
        kill -TERM $pid 2>/dev/null
        sleep 2
        if kill -0 $pid 2>/dev/null; then
            kill -KILL $pid 2>/dev/null
        fi
        print_success "MTProxy杩涚▼宸插仠姝?
    else
        print_info "MTProxy杩涚▼鏈繍琛?
    fi
    
    # 2. 鍋滄骞跺垹闄ystemd鏈嶅姟
    print_info "妫€鏌ュ苟鍒犻櫎systemd鏈嶅姟..."
    if [ -f "/etc/systemd/system/mtproxy.service" ]; then
        systemctl stop mtproxy 2>/dev/null
        systemctl disable mtproxy 2>/dev/null
        rm -f /etc/systemd/system/mtproxy.service
        systemctl daemon-reload 2>/dev/null
        print_success "systemd鏈嶅姟宸插垹闄?
    else
        print_info "鏈彂鐜皊ystemd鏈嶅姟"
    fi
    
    # 3. 娓呯悊杩涚▼鍜岀鍙?    print_info "娓呯悊鐩稿叧杩涚▼..."
    pkill -f mtg 2>/dev/null
    pkill -f mtproxy 2>/dev/null
    
    # 4. 鍒犻櫎鏂囦欢鍜岀洰褰?    print_info "鍒犻櫎绋嬪簭鏂囦欢..."
    rm -f ./mtg
    rm -f ./mtp_config
    rm -f $pid_file
    rm -rf ./pid
    rm -rf ./logs
    
    # 5. 娓呯悊闃茬伀澧欒鍒欙紙濡傛灉瀛樺湪锛?    print_info "娓呯悊闃茬伀澧欒鍒?.."
    if load_config 2>/dev/null; then
        # 灏濊瘯鍒犻櫎鍙兘鐨勯槻鐏瑙勫垯
        if command -v ufw >/dev/null 2>&1; then
            ufw delete allow $port 2>/dev/null
            ufw delete allow $web_port 2>/dev/null
        fi
        if command -v firewall-cmd >/dev/null 2>&1; then
            firewall-cmd --permanent --remove-port=$port/tcp 2>/dev/null
            firewall-cmd --permanent --remove-port=$web_port/tcp 2>/dev/null
            firewall-cmd --reload 2>/dev/null
        fi
    fi
    
    print_line
    print_success "鉁?MTProxy宸插畬鍏ㄥ嵏杞?
    print_info "浠ヤ笅鏂囦欢宸插垹闄わ細"
    echo "  - MTG绋嬪簭 (./mtg)"
    echo "  - 閰嶇疆鏂囦欢 (./mtp_config)"
    echo "  - PID鏂囦欢 (./pid/)"
    echo "  - 鏃ュ織鐩綍 (./logs/)"
    echo "  - systemd鏈嶅姟 (/etc/systemd/system/mtproxy.service)"
    print_info "绠＄悊鑴氭湰 (mtproxy.sh) 淇濈暀锛屽彲鐢ㄤ簬閲嶆柊瀹夎"
    print_line
}

# 涓€閿畨瑁呭苟杩愯
install_and_run() {
    function_header "寮€濮嬩竴閿畨瑁匨TProxy..."

    ensure_system_detected
    install_dependencies
    download_mtg
    config_mtproxy
    start_mtproxy

    print_success "瀹夎瀹屾垚锛?
}

# 瀹屾暣绯荤粺妫€鏌?full_system_check() {
    clear
    echo -e "${PURPLE}"
    echo "========================================"
    echo "        MTProxy 瀹屾暣绯荤粺妫€鏌?
    echo "========================================"
    echo -e "${NC}"

    ensure_system_detected
    check_system_info
    check_network
    check_dependencies
    check_ports
    check_firewall
    check_mtproxy_status
    test_connection

    print_line
    print_info "绯荤粺妫€鏌ュ畬鎴?
    print_line
}

# 涓昏彍鍗?show_menu() {
    clear
    echo -e "${PURPLE}"
    echo "========================================"
    echo "     MTProxy 澧炲己鐗堢鐞嗚剼鏈?
    echo "   鏀寔 Alpine/RHEL/Debian 绯荤粺"
    echo "========================================"
    echo -e "${NC}"

    if [ -f "./mtp_config" ]; then
        show_proxy_info
    else
        print_info "MTProxy鏈畨瑁?
        print_line
    fi

    echo -e "${YELLOW}璇烽€夋嫨鎿嶄綔:${NC}"
    echo "1.  涓€閿畨瑁呭苟杩愯MTProxy"
    echo "2.  鍚姩MTProxy"
    echo "3.  鍋滄MTProxy"
    echo "4.  閲嶅惎MTProxy"
    echo "5.  鏌ョ湅浠ｇ悊淇℃伅"
    echo "6.  淇敼绔彛閰嶇疆"
    echo "7.  瀹屾暣绯荤粺妫€鏌?
    echo "8.  缃戠粶鐜璇婃柇"
    echo "9.  鑷姩淇闂"
    echo "10. 杩涚▼鐩戞帶鍜岃嚜鍔ㄩ噸鍚?
    echo "11. 鍒涘缓systemd鏈嶅姟"
    echo "12. 鍋ュ悍妫€鏌?
    echo "13. 瀹屽叏鍗歌浇MTProxy"
    echo "0.  閫€鍑?
    echo
}

# 涓荤▼搴?main() {
    # 妫€鏌ユ槸鍚︿负root鐢ㄦ埛
    if [[ $EUID -ne 0 ]]; then
        print_warning "寤鸿浣跨敤root鐢ㄦ埛杩愯姝よ剼鏈互鑾峰緱瀹屾暣鍔熻兘"
    fi

    while true; do
        show_menu
        read -p "璇疯緭鍏ラ€夐」 [0-13]: " choice

        case $choice in
            1)
                install_and_run
                read -p "鎸夊洖杞﹂敭缁х画..."
                ;;
            2)
                ensure_system_detected
                start_mtproxy
                read -p "鎸夊洖杞﹂敭缁х画..."
                ;;
            3)
                stop_mtproxy
                read -p "鎸夊洖杞﹂敭缁х画..."
                ;;
            4)
                ensure_system_detected
                stop_mtproxy
                sleep 1
                start_mtproxy
                read -p "鎸夊洖杞﹂敭缁х画..."
                ;;
            5)
                show_proxy_info
                read -p "鎸夊洖杞﹂敭缁х画..."
                ;;
            6)
                ensure_system_detected
                change_ports
                read -p "鎸夊洖杞﹂敭缁х画..."
                ;;
            7)
                full_system_check
                read -p "鎸夊洖杞﹂敭缁х画..."
                ;;
            8)
                ensure_system_detected
                diagnose_network_issues
                read -p "鎸夊洖杞﹂敭缁х画..."
                ;;
            9)
                ensure_system_detected
                auto_fix
                read -p "鎸夊洖杞﹂敭缁х画..."
                ;;
            10)
                ensure_system_detected
                monitor_mtproxy
                read -p "鎸夊洖杞﹂敭缁х画..."
                ;;
            11)
                ensure_system_detected
                create_systemd_service
                read -p "鎸夊洖杞﹂敭缁х画..."
                ;;
            12)
                ensure_system_detected
                health_check
                read -p "鎸夊洖杞﹂敭缁х画..."
                ;;
            13)
                uninstall_mtproxy
                read -p "鎸夊洖杞﹂敭缁х画..."
                ;;
            0)
                print_info "閫€鍑鸿剼鏈?
                exit 0
                ;;
            *)
                print_error "鏃犳晥閫夐」锛岃閲嶆柊閫夋嫨"
                sleep 1
                ;;
        esac
    done
}

# 妫€鏌ュ弬鏁?if [[ $# -eq 0 ]]; then
    main
else
    ensure_system_detected
    case $1 in
        "install")
            install_and_run
            ;;
        "start")
            start_mtproxy
            ;;
        "stop")
            stop_mtproxy
            ;;
        "restart")
            stop_mtproxy
            sleep 1
            start_mtproxy
            ;;
        "status")
            show_proxy_info
            ;;
        "check")
            full_system_check
            ;;
        "diagnose")
            diagnose_network_issues
            ;;
        "fix")
            auto_fix
            ;;
        "ports")
            change_ports
            ;;
        "monitor")
            monitor_mtproxy
            ;;
        "systemd")
            create_systemd_service
            ;;
        "health")
            health_check
            ;;
        "uninstall")
            uninstall_mtproxy
            ;;
        *)
            echo "鐢ㄦ硶: $0 [install|start|stop|restart|status|check|diagnose|fix|ports|monitor|systemd|health|uninstall]"
            echo "鎴栫洿鎺ヨ繍琛?$0 杩涘叆浜や簰妯″紡"
            echo ""
            echo "鍛戒护璇存槑:"
            echo "  install   - 涓€閿畨瑁呭苟杩愯"
            echo "  start     - 鍚姩鏈嶅姟"
            echo "  stop      - 鍋滄鏈嶅姟"
            echo "  restart   - 閲嶅惎鏈嶅姟"
            echo "  status    - 鏌ョ湅鐘舵€?
            echo "  check     - 瀹屾暣绯荤粺妫€鏌?
            echo "  diagnose  - 缃戠粶鐜璇婃柇"
            echo "  fix       - 鑷姩淇闂"
            echo "  ports     - 淇敼绔彛閰嶇疆"
            echo "  monitor   - 杩涚▼鐩戞帶鍜岃嚜鍔ㄩ噸鍚?
            echo "  systemd   - 鍒涘缓systemd鏈嶅姟"
            echo "  health    - 鍋ュ悍妫€鏌?
            echo "  uninstall - 瀹屽叏鍗歌浇"
            ;;
    esac
fi
