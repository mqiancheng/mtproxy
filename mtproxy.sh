#!/bin/bash

# MTProxy 增强版管理系统 - 优化版本
# 支持 Alpine Linux, AlmaLinux/RHEL/CentOS, Debian/Ubuntu

WORKDIR=$(dirname $(readlink -f $0))
cd $WORKDIR
pid_file=$WORKDIR/pid/pid_mtproxy

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

# 打印函数
print_info() { echo -e "${BLUE}[信息]${NC} $1"; }
print_success() { echo -e "${GREEN}[成功]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[警告]${NC} $1"; }
print_error() { echo -e "${RED}[错误]${NC} $1"; }
print_debug() { echo -e "${CYAN}[调试]${NC} $1"; }
print_line() { echo "========================================"; }

# ==================== 通用辅助函数 ====================

# 加载配置文件
load_config() {
    if [ ! -f "./mtp_config" ]; then
        print_error "配置文件不存在，请先安装"
        return 1
    fi
    source ./mtp_config
    return 0
}

# 检查进程状态
check_process_status() {
    if [ -f "$pid_file" ]; then
        local pid=$(cat $pid_file)
        if kill -0 $pid 2>/dev/null; then
            echo $pid
            return 0  # 运行中
        else
            rm -f $pid_file
            return 1  # 已停止
        fi
    else
        return 1  # PID文件不存在
    fi
}

# 释放端口
release_port() {
    local port=$1
    if netstat -tulpn 2>/dev/null | grep -q ":$port "; then
        print_info "释放端口 $port..."
        local pids=$(netstat -tulpn 2>/dev/null | grep ":$port " | awk '{print $7}' | sed 's|/.*||')
        for pid in $pids; do
            kill -9 $pid 2>/dev/null
        done
    fi
}

# 标准函数头部
function_header() {
    local title="$1"
    print_line
    print_info "$title"
    print_line
}

# 确保系统检测
ensure_system_detected() {
    if [ -z "$OS" ]; then
        detect_system 2>/dev/null
    fi
}

# 确保网络环境检测
ensure_network_detected() {
    if [ -z "$NETWORK_TYPE" ]; then
        detect_network_environment
    fi
}

# 检查端口是否被占用
is_port_occupied() {
    local port=$1
    netstat -tulpn 2>/dev/null | grep -q ":$port "
}

# 获取端口占用进程
get_port_process() {
    local port=$1
    netstat -tulpn 2>/dev/null | grep ":$port " | awk '{print $7}' | head -1
}

# 验证端口号
validate_port() {
    local port=$1
    if [[ "$port" =~ ^[0-9]+$ ]] && [ $port -ge 1 ] && [ $port -le 65535 ]; then
        return 0
    else
        return 1
    fi
}

# 创建必要目录
create_directories() {
    mkdir -p pid logs
}

# 生成客户端密钥
generate_client_secret() {
    local domain_hex=$(str_to_hex $domain)
    echo "ee${secret}${domain_hex}"
}

# 显示防火墙配置命令
show_firewall_commands() {
    local client_port=$1
    local manage_port=$2

    function_header "防火墙配置提示"

    case $OS in
        "rhel")
            echo "AlmaLinux/RHEL/CentOS 防火墙配置"
            echo "firewall-cmd --permanent --add-port=$client_port/tcp"
            echo "firewall-cmd --permanent --add-port=$manage_port/tcp"
            echo "firewall-cmd --reload"
            ;;
        "debian")
            echo "Debian/Ubuntu 防火墙配置"
            echo "ufw allow $client_port/tcp"
            echo "ufw allow $manage_port/tcp"
            ;;
        "alpine")
            echo "Alpine Linux 通常不需要额外的防火墙配置"
            echo "如果使用iptables:"
            echo "iptables -A INPUT -p tcp --dport $client_port -j ACCEPT"
            echo "iptables -A INPUT -p tcp --dport $manage_port -j ACCEPT"
            ;;
    esac
    print_line
}

# ==================== 系统检测函数 ====================

# 系统检测
detect_system() {
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
        print_error "不支持的操作系"
        exit 1
    fi
}

# 网络环境检测
detect_network_environment() {
    local ipv4=$(curl -s --connect-timeout 3 https://api.ip.sb/ip -A Mozilla --ipv4 2>/dev/null)
    local ipv6=$(curl -s --connect-timeout 3 https://api.ip.sb/ip -A Mozilla --ipv6 2>/dev/null)
    local has_ipv4=false
    local has_ipv6=false
    local is_warp=false
    local is_nat=false

    # 检查IPv4
    if [[ -n "$ipv4" && "$ipv4" != *"curl:"* && "$ipv4" != *"error"* ]]; then
        has_ipv4=true
        # 检查是否为WARP (Cloudflare IP段)
        if [[ "$ipv4" =~ ^(162\.159\.|104\.28\.|172\.67\.|104\.16\.) ]]; then
            is_warp=true
        fi
    fi

    # 检查IPv6
    if [[ -n "$ipv6" && "$ipv6" != *"curl:"* && "$ipv6" != *"error"* ]]; then
        has_ipv6=true
        # 检查是否为WARP IPv6
        if [[ "$ipv6" =~ ^2606:4700: ]]; then
            is_warp=true
        fi
    fi

    # 检查是否为NAT环境
    local local_ip=$(ip route get 8.8.8.8 2>/dev/null | grep -oP 'src \K\S+' | head -1)
    if [[ -n "$local_ip" && "$local_ip" != "$ipv4" ]]; then
        is_nat=true
    fi

    # 确定网络环境类型
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

    # 导出环境变量
    export NETWORK_TYPE
    export HAS_IPV4=$has_ipv4
    export HAS_IPV6=$has_ipv6
    export IS_WARP=$is_warp
    export IS_NAT=$is_nat
    export PUBLIC_IPV4="$ipv4"
    export PUBLIC_IPV6="$ipv6"
    export LOCAL_IP="$local_ip"
}

# 获取架构
get_architecture() {
    case $(uname -m) in
    i386|i686) echo "386" ;;
    x86_64) echo "amd64" ;;
    aarch64) echo "arm64" ;;
    arm*) echo "armv6l" ;;
    *) print_error "不支持的架构: $(uname -m)" && exit 1 ;;
    esac
}

# 生成随机字符串
gen_rand_hex() {
    dd if=/dev/urandom bs=1 count=500 status=none 2>/dev/null | od -An -tx1 | tr -d ' \n' | head -c $1
}

# 字符串转十六进制
str_to_hex() {
    printf "%s" "$1" | od -An -tx1 | tr -d ' \n'
}

# 根据网络环境生成MTG启动参数
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
            # 双栈环境，绑定所有接口，优先IPv4
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
            # 纯IPv4环境，明确绑定IPv4地址
            bind_addr="$PUBLIC_IPV4:$port"
            prefer_ip="--prefer-ip=ipv4"
            if [[ -n "$PUBLIC_IPV4" ]]; then
                external_params="-4 $PUBLIC_IPV4:$port"
            fi
            ;;
        "ipv6_only")
            # 纯IPv6环境，绑定IPv6
            bind_addr="[::]:$port"
            prefer_ip="--prefer-ip=ipv6"
            if [[ -n "$PUBLIC_IPV6" ]]; then
                external_params="-6 [$PUBLIC_IPV6]:$port"
            fi
            ;;
        "warp_proxy")
            # WARP代理环境，特殊处理
            if [[ "$HAS_IPV6" == true ]]; then
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
            # 默认配置
            bind_addr="0.0.0.0:$port"
            prefer_ip="--prefer-ip=ipv4"
            if [[ -n "$PUBLIC_IPV4" ]]; then
                external_params="-4 $PUBLIC_IPV4:$port"
            fi
            ;;
    esac

    # 构建完整命令
    local base_cmd="./mtg run $client_secret"
    [[ -n "$proxy_tag" ]] && base_cmd="$base_cmd $proxy_tag"

    local full_cmd="$base_cmd -b $bind_addr --multiplex-per-connection 500 $prefer_ip -t 127.0.0.1:$web_port"
    [[ -n "$external_params" ]] && full_cmd="$full_cmd $external_params"

    echo "$full_cmd"
}

# ==================== 检查和诊断函数 ====================

# 系统信息检查
check_system_info() {
    function_header "系统信息检查"
    
    echo -e "操作系统: ${GREEN}$DISTRO${NC}"
    echo -e "包管理器: ${GREEN}$PKG_MANAGER${NC}"
    echo -e "系统架构: ${GREEN}$(uname -m)${NC}"
    echo -e "内核版本: ${GREEN}$(uname -r)${NC}"
    echo -e "运行时间: ${GREEN}$(uptime | awk '{print $3,$4}' | sed 's/,//')${NC}"
    
    # 检查内存
    local mem_total=$(free -h | awk '/^Mem:/ {print $2}')
    local mem_used=$(free -h | awk '/^Mem:/ {print $3}')
    echo -e "内存使用: ${GREEN}$mem_used / $mem_total${NC}"
    
    # 检查磁盘空间
    local disk_usage=$(df -h . | awk 'NR==2 {print $5}')
    echo -e "磁盘使用: ${GREEN}$disk_usage${NC}"
}

# 网络检查
check_network() {
    function_header "网络连接检查及环境检测"

    detect_network_environment

    # 显示网络环境信息
    echo -e "网络环境类型: ${GREEN}$NETWORK_TYPE${NC}"

    # 检查IPv4连接
    print_info "检查IPv4连接..."
    if [[ "$HAS_IPV4" == true ]]; then
        echo -e "IPv4地址: ${GREEN}$PUBLIC_IPV4${NC}"
        [[ "$IS_WARP" == true ]] && echo -e "WARP检测: ${YELLOW}是${NC}"
    else
        echo -e "IPv4连接: ${RED}失败${NC}"
    fi

    # 检查IPv6连接
    print_info "检查IPv6连接..."
    if [[ "$HAS_IPV6" == true ]]; then
        echo -e "IPv6地址: ${GREEN}$PUBLIC_IPV6${NC}"
    else
        echo -e "IPv6连接: ${YELLOW}不可用${NC}"
    fi

    # NAT检测
    if [[ "$IS_NAT" == true ]]; then
        echo -e "NAT环境: ${YELLOW}是${NC} (本地IP: $LOCAL_IP)"
    else
        echo -e "NAT环境: ${GREEN}否${NC}"
    fi

    # 检查DNS解析
    print_info "检查DNS解析..."
    if nslookup google.com >/dev/null 2>&1; then
        echo -e "DNS解析: ${GREEN}正常${NC}"
    else
        echo -e "DNS解析: ${RED}异常${NC}"
    fi

    # 检查网络接口信息
    print_info "网络接口信息:"
    ip addr show | grep -E "inet |inet6 " | grep -v "127.0.0.1" | grep -v "::1" | while read line; do
        echo -e "  ${CYAN}$line${NC}"
    done

    # 显示环境特定的提示
    echo ""
    print_info "环境分析:"
    case "$NETWORK_TYPE" in
        "dual_stack")
            echo -e "${GREEN}✔ 双栈环境，IPv4 和 IPv6 均可用，连接应该稳定${NC}"
            ;;
        "ipv4_only")
            echo -e "${YELLOW}⚠ 纯IPv4环境，IPv6 连接将不可用${NC}"
            ;;
        "ipv6_only")
            echo -e "${YELLOW}⚠ 纯IPv6环境，确保客户端支持IPv6${NC}"
            ;;
        "warp_proxy")
            echo -e "${YELLOW}⚠ WARP代理环境，可能存在连接稳定性问题${NC}"
            ;;
        "unknown")
            echo -e "${RED}✘ 网络环境异常，建议运行诊断功能${NC}"
            ;;
    esac
}

# 端口检查
check_ports() {
    function_header "端口使用情况检查"
    
    # 检查常用端口
    local common_ports=(22 80 443 8080 8443 8888 9999)
    for port in "${common_ports[@]}"; do
        if is_port_occupied $port; then
            local process=$(get_port_process $port)
            echo -e "端口 $port: ${RED}被占用${NC} ($process)"
        else
            echo -e "端口 $port: ${GREEN}可用${NC}"
        fi
    done
    
    # 如果有配置文件，检查配置的端口
    if load_config; then
        echo ""
        print_info "MTProxy配置端口检查"
        
        if is_port_occupied $port; then
            local process=$(get_port_process $port)
            echo -e "客户端端口 $port: ${RED}被占用${NC} ($process)"
        else
            echo -e "客户端端口 $port: ${GREEN}可用${NC}"
        fi
        
        if is_port_occupied $web_port; then
            local process=$(get_port_process $web_port)
            echo -e "管理端口 $web_port: ${RED}被占用${NC} ($process)"
        else
            echo -e "管理端口 $web_port: ${GREEN}可用${NC}"
        fi
    fi
}

# 防火墙检查
check_firewall() {
    function_header "防火墙状态检查"
    
    case $OS in
        "rhel")
            if command -v firewall-cmd >/dev/null 2>&1; then
                if systemctl is-active firewalld >/dev/null 2>&1; then
                    echo -e "Firewalld: ${GREEN}运行中${NC}"
                    if load_config; then
                        local port_open=$(firewall-cmd --list-ports | grep -c "$port/tcp")
                        local web_port_open=$(firewall-cmd --list-ports | grep -c "$web_port/tcp")
                        echo -e "端口 $port/tcp: $([ $port_open -gt 0 ] && echo -e "${GREEN}已开放${NC}" || echo -e "${RED}未开放${NC}")"
                        echo -e "端口 $web_port/tcp: $([ $web_port_open -gt 0 ] && echo -e "${GREEN}已开放${NC}" || echo -e "${RED}未开放${NC}")"
                    fi
                else
                    echo -e "Firewalld: ${YELLOW}未运行${NC}"
                fi
            else
                echo -e "Firewalld: ${YELLOW}未安装${NC}"
            fi
            ;;
        "debian")
            if command -v ufw >/dev/null 2>&1; then
                local ufw_status=$(ufw status | head -1)
                if [[ "$ufw_status" == *"active"* ]]; then
                    echo -e "UFW: ${GREEN}激活${NC}"
                    if load_config; then
                        ufw status | grep -q "$port/tcp" && echo -e "端口 $port/tcp: ${GREEN}已开放${NC}" || echo -e "端口 $port/tcp: ${RED}未开放${NC}"
                        ufw status | grep -q "$web_port/tcp" && echo -e "端口 $web_port/tcp: ${GREEN}已开放${NC}" || echo -e "端口 $web_port/tcp: ${RED}未开放${NC}"
                    fi
                else
                    echo -e "UFW: ${YELLOW}未激活${NC}"
                fi
            else
                echo -e "UFW: ${YELLOW}未安装${NC}"
            fi
            ;;
        "alpine")
            if command -v iptables >/dev/null 2>&1; then
                local iptables_rules=$(iptables -L INPUT -n | wc -l)
                echo -e "iptables规则数: ${GREEN}$iptables_rules${NC}"
            else
                echo -e "iptables: ${YELLOW}未安装${NC}"
            fi
            ;;
    esac
}

# MTProxy状态检查
check_mtproxy_status() {
    function_header "MTProxy状态检查"
    
    # 检查配置文件
    if load_config; then
        echo -e "配置文件: ${GREEN}存在${NC}"
        echo -e "客户端端口: ${GREEN}$port${NC}"
        echo -e "管理端口: ${GREEN}$web_port${NC}"
        echo -e "伪装域名: ${GREEN}$domain${NC}"
        [[ -n "$proxy_tag" ]] && echo -e "推广TAG: ${GREEN}$proxy_tag${NC}" || echo -e "推广TAG: ${YELLOW}未设置${NC}"
    else
        return 1
    fi
    
    # 检查MTG程序
    if [ -f "./mtg" ]; then
        echo -e "MTG程序: ${GREEN}存在${NC}"
        local mtg_version=$(./mtg --version 2>/dev/null | head -1 || echo "未知版本")
        echo -e "MTG版本: ${GREEN}$mtg_version${NC}"
    else
        echo -e "MTG程序: ${RED}不存在${NC}"
        return 1
    fi
    
    # 检查进程状态
    if check_process_status >/dev/null; then
        local pid=$(check_process_status)
        echo -e "进程状态: ${GREEN}运行中${NC} (PID: $pid)"
        
        # 检查进程详情
        local process_info=$(ps aux | grep $pid | grep -v grep | head -1)
        echo -e "进程信息: ${CYAN}$process_info${NC}"
        
        # 检查端口监听
        if is_port_occupied $port; then
            echo -e "端口监听: ${GREEN}正常${NC} ($port)"
        else
            echo -e "端口监听: ${RED}异常${NC} ($port)"
        fi
    else
        echo -e "进程状态: ${YELLOW}未运行${NC} (无PID文件)"
    fi
    
    # 检查所有mtg进程
    local mtg_processes=$(ps aux | grep -v grep | grep mtg | wc -l)
    if [ $mtg_processes -gt 0 ]; then
        echo -e "MTG进程数: ${GREEN}$mtg_processes${NC}"
        ps aux | grep -v grep | grep mtg | while read line; do
            echo -e "  ${CYAN}$line${NC}"
        done
    else
        echo -e "MTG进程数: ${YELLOW}0${NC}"
    fi
}

# 依赖检查
check_dependencies() {
    function_header "依赖检查"
    
    local deps=("curl" "wget" "netstat" "ps" "kill" "tar" "od")
    
    for dep in "${deps[@]}"; do
        if command -v $dep >/dev/null 2>&1; then
            echo -e "$dep: ${GREEN}已安装${NC}"
        else
            echo -e "$dep: ${RED}未安装${NC}"
        fi
    done
    
    # 检查特定系统的包
    case $OS in
        "alpine")
            local alpine_deps=("procps" "net-tools")
            for dep in "${alpine_deps[@]}"; do
                if apk info -e $dep >/dev/null 2>&1; then
                    echo -e "$dep: ${GREEN}已安装${NC}"
                else
                    echo -e "$dep: ${RED}未安装${NC}"
                fi
            done
            ;;
        "rhel")
            local rhel_deps=("procps-ng" "net-tools")
            for dep in "${rhel_deps[@]}"; do
                if rpm -q $dep >/dev/null 2>&1; then
                    echo -e "$dep: ${GREEN}已安装${NC}"
                else
                    echo -e "$dep: ${RED}未安装${NC}"
                fi
            done
            ;;
        "debian")
            local debian_deps=("procps" "net-tools")
            for dep in "${debian_deps[@]}"; do
                if dpkg -l | grep -q "^ii  $dep "; then
                    echo -e "$dep: ${GREEN}已安装${NC}"
                else
                    echo -e "$dep: ${RED}未安装${NC}"
                fi
            done
            ;;
    esac
}

# ==================== 核心功能函数 ====================

# 下载MTG
download_mtg() {
    local arch=$(get_architecture)
    local url="https://github.com/9seconds/mtg/releases/download/v1.0.11/mtg-1.0.11-linux-$arch.tar.gz"

    print_info "下载MTG ($arch)..."
    wget $url -O mtg.tar.gz -q --timeout=30 || {
        print_error "下载失败，请检查网络连接"
        return 1
    }

    tar -xzf mtg.tar.gz mtg-1.0.11-linux-$arch/mtg --strip-components 1
    chmod +x mtg
    rm -f mtg.tar.gz

    if [ -f "./mtg" ]; then
        print_success "MTG下载完成"
    else
        print_error "MTG安装失败"
        return 1
    fi
}

# 安装依赖
install_dependencies() {
    print_info "安装系统依赖..."
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
        print_success "依赖安装完成"
    else
        print_error "依赖安装失败"
        return 1
    fi
}

# 配置MTProxy
config_mtproxy() {
    function_header "配置MTProxy"

    # 端口配置
    while true; do
        read -p "请输入客户端连接端口 (默认 443): " input_port
        [ -z "$input_port" ] && input_port=443

        if validate_port $input_port; then
            if is_port_occupied $input_port; then
                print_warning "端口 $input_port 已占用"
                get_port_process $input_port
                read -p "是否继续使用此端口? (y/N): " continue_port
                if [[ "$continue_port" == "y" || "$continue_port" == "Y" ]]; then
                    break
                fi
            else
                break
            fi
        else
            print_error "请输入有效的端口号 [1-65535]"
        fi
    done

    # 管理端口配置
    while true; do
        read -p "请输入管理端口 (默认 8888): " input_manage_port
        [ -z "$input_manage_port" ] && input_manage_port=8888

        if validate_port $input_manage_port; then
            if [ $input_manage_port -eq $input_port ]; then
                print_error "管理端口不能与客户端端口相同"
            elif is_port_occupied $input_manage_port; then
                print_warning "端口 $input_manage_port 已占用"
                read -p "是否继续使用此端口? (y/N): " continue_port
                if [[ "$continue_port" == "y" || "$continue_port" == "Y" ]]; then
                    break
                fi
            else
                break
            fi
        else
            print_error "请输入有效的端口号 [1-65535]"
        fi
    done

    # 域名配置
    read -p "请输入伪装域名 (默认 azure.microsoft.com): " input_domain
    [ -z "$input_domain" ] && input_domain="azure.microsoft.com"

    # TAG配置
    read -p "请输入推广TAG (可选，直接回车跳过): " input_tag

    # 生成配置
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

    print_success "配置生成完成"
    show_firewall_commands $input_port $input_manage_port
}

# 启动MTProxy
start_mtproxy() {
    if ! load_config; then
        return 1
    fi

    # 检查是否已运行
    if check_process_status >/dev/null; then
        local pid=$(check_process_status)
        print_warning "MTProxy已经在运行中 (PID: $pid)"
        return 0
    fi

    # 检查MTG程序
    if [ ! -f "./mtg" ]; then
        print_error "MTG程序不存在，请重新安装"
        return 1
    fi

    # 释放端口
    release_port $port
    release_port $web_port

    # 创建必要目录
    create_directories

    # 构建运行命令
    local client_secret=$(generate_client_secret)

    print_info "正在启动MTProxy..."
    print_info "检测网络环境..."

    # 生成适合当前网络环境的启动参数
    local mtg_cmd=$(generate_mtg_params "$client_secret" "$proxy_tag" "$port" "$web_port")

    print_debug "网络环境: $NETWORK_TYPE"
    print_debug "启动命令: $mtg_cmd"

    # 启动MTG (添加日志输出)
    local log_file="./logs/mtproxy.log"
    eval "$mtg_cmd >> $log_file 2>&1 &"

    echo $! > $pid_file
    sleep 3

    # 检查启动状态
    if check_process_status >/dev/null; then
        local pid=$(check_process_status)
        print_success "MTProxy启动成功 (PID: $pid)"
        print_info "日志文件: $log_file"
        show_proxy_info
    else
        print_error "MTProxy启动失败"
        print_info "查看日志: tail -f $log_file"
        return 1
    fi
}

# 停止MTProxy
stop_mtproxy() {
    if check_process_status >/dev/null; then
        local pid=$(check_process_status)
        print_info "正在停止MTProxy (PID: $pid)..."
        kill -9 $pid 2>/dev/null
        rm -f $pid_file
    fi

    # 额外确保所有mtg进程被杀死
    pkill -f mtg 2>/dev/null

    sleep 1

    # 检查是否还有mtg进程
    if pgrep -f mtg >/dev/null 2>&1; then
        print_warning "仍有MTG进程在运行，强制终止..."
        pkill -9 -f mtg 2>/dev/null
    fi

    print_success "MTProxy已停止"
}

# 显示代理信息
show_proxy_info() {
    if ! load_config; then
        return 1
    fi

    # 快速网络检测（仅用于菜单显示）
    if [ -z "$NETWORK_TYPE" ]; then
        # 使用更快的检测方式
        local ipv4=$(curl -s --connect-timeout 2 https://api.ip.sb/ip -A Mozilla --ipv4 2>/dev/null)
        if [[ -n "$ipv4" && "$ipv4" != *"curl:"* && "$ipv4" != *"error"* ]]; then
            NETWORK_TYPE="ipv4"
            HAS_IPV4=true
            PUBLIC_IPV4="$ipv4"
        else
            NETWORK_TYPE="unknown"
            HAS_IPV4=false
        fi
    fi
    
    local client_secret=$(generate_client_secret)

    print_line
    if check_process_status >/dev/null; then
        local pid=$(check_process_status)
        print_success "MTProxy状态: 运行中 (PID: $pid)"
    else
        print_warning "MTProxy状态: 已停止"
    fi

    echo -e "系统类型: ${PURPLE}$os${NC}"
    echo -e "网络环境: ${PURPLE}$NETWORK_TYPE${NC}"

    if [[ "$HAS_IPV4" == true ]]; then
        echo -e "服务器IPv4: ${GREEN}$PUBLIC_IPV4${NC}"
        [[ "$IS_WARP" == true ]] && echo -e "WARP状态: ${YELLOW}已启用${NC}"
    fi

    if [[ "$HAS_IPV6" == true ]]; then
        echo -e "服务器IPv6: ${GREEN}$PUBLIC_IPV6${NC}"
    fi

    [[ "$IS_NAT" == true ]] && echo -e "NAT环境: ${YELLOW}是${NC} (本地IP: $LOCAL_IP)"

    echo -e "客户端端口: ${GREEN}$port${NC}"
    echo -e "管理端口: ${GREEN}$web_port${NC}"
    echo -e "代理密钥: ${GREEN}$client_secret${NC}"
    echo -e "伪装域名: ${GREEN}$domain${NC}"
    [[ -n "$proxy_tag" ]] && echo -e "推广TAG: ${GREEN}$proxy_tag${NC}"

    # 根据网络环境显示连接链接
    if [[ "$HAS_IPV4" == true ]]; then
        echo -e "\n${BLUE}Telegram连接链接 (IPv4):${NC}"
        echo "https://t.me/proxy?server=${PUBLIC_IPV4}&port=${port}&secret=${client_secret}"
        echo "tg://proxy?server=${PUBLIC_IPV4}&port=${port}&secret=${client_secret}"
    fi

    if [[ "$HAS_IPV6" == true ]]; then
        echo -e "\n${BLUE}Telegram连接链接 (IPv6):${NC}"
        echo "https://t.me/proxy?server=${PUBLIC_IPV6}&port=${port}&secret=${client_secret}"
        echo "tg://proxy?server=${PUBLIC_IPV6}&port=${port}&secret=${client_secret}"
    fi

    # 显示网络环境特定的提示
    case "$NETWORK_TYPE" in
        "warp_proxy")
            echo -e "\n${YELLOW}注意: 检测到WARP代理环境，如果连接有问题请尝试重启服务${NC}"
            ;;
        "ipv6_only")
            echo -e "\n${YELLOW}注意: 纯IPv6环境，确保客户端支持IPv6${NC}"
            ;;
        "ipv4_only")
            echo -e "\n${GREEN}注意: 纯IPv4环境，连接应该正常${NC}"
            ;;
        "dual_stack")
            echo -e "\n${GREEN}注意: 双栈环境，IPv4 和 IPv6 均可用${NC}"
            ;;
    esac

    print_line
}

# ==================== 高级功能函数 ====================

# 连接测试
test_connection() {
    function_header "连接测试"
    
    if ! load_config; then
        return 1
    fi
    
    local public_ip=$(curl -s --connect-timeout 6 https://api.ip.sb/ip -A Mozilla --ipv4)
    
    # 测试端口连通性
    print_info "测试端口连通性..."
    if timeout 5 bash -c "</dev/tcp/127.0.0.1/$port" 2>/dev/null; then
        echo -e "本地端口 $port: ${GREEN}可连接${NC}"
    else
        echo -e "本地端口 $port: ${RED}无法连接${NC}"
    fi
    
    if timeout 5 bash -c "</dev/tcp/127.0.0.1/$web_port" 2>/dev/null; then
        echo -e "管理端口 $web_port: ${GREEN}可连接${NC}"
    else
        echo -e "管理端口 $web_port: ${RED}无法连接${NC}"
    fi
    
    # 测试外部连接
    print_info "测试外部连接..."

    ensure_network_detected

    # 测试IPv4外部连接
    if [[ "$HAS_IPV4" == true && -n "$PUBLIC_IPV4" ]]; then
        print_info "测试IPv4外部连接 ($PUBLIC_IPV4:$port)..."
        if timeout 10 bash -c "</dev/tcp/$PUBLIC_IPV4/$port" 2>/dev/null; then
            echo -e "IPv4外部端口 $port: ${GREEN}可连接${NC}"
        else
            echo -e "IPv4外部端口 $port: ${RED}无法连接${NC}"
            if [[ "$IS_NAT" == true ]]; then
                echo -e "  ${YELLOW}注意: 检测到NAT环境，可能需要端口映射${NC}"
            fi
        fi
    fi

    # 测试IPv6外部连接
    if [[ "$HAS_IPV6" == true && -n "$PUBLIC_IPV6" ]]; then
        print_info "测试IPv6外部连接 ([$PUBLIC_IPV6]:$port)..."
        # IPv6连接测试需要特殊处理
        if command -v nc >/dev/null 2>&1; then
            if timeout 10 nc -6 -z "$PUBLIC_IPV6" "$port" 2>/dev/null; then
                echo -e "IPv6外部端口 $port: ${GREEN}可连接${NC}"
            else
                echo -e "IPv6外部端口 $port: ${RED}无法连接${NC}"
            fi
        else
            echo -e "IPv6外部端口 $port: ${YELLOW}无法测试 (缺少nc工具)${NC}"
        fi
    else
        echo -e "IPv6连接: ${YELLOW}不可用，跳过IPv6连接测试${NC}"
    fi

    # 生成连接信息
    local client_secret=$(generate_client_secret)

    print_info "连接信息:"
    echo -e "网络环境: ${GREEN}$NETWORK_TYPE${NC}"

    if [[ "$HAS_IPV4" == true ]]; then
        echo -e "服务器IPv4: ${GREEN}$PUBLIC_IPV4${NC}"
    fi
    if [[ "$HAS_IPV6" == true ]]; then
        echo -e "服务器IPv6: ${GREEN}$PUBLIC_IPV6${NC}"
    fi

    echo -e "端口: ${GREEN}$port${NC}"
    echo -e "密钥: ${GREEN}$client_secret${NC}"
    echo ""

    # 生成连接链接
    if [[ "$HAS_IPV4" == true ]]; then
        echo -e "${BLUE}Telegram连接链接 (IPv4):${NC}"
        echo "https://t.me/proxy?server=${PUBLIC_IPV4}&port=${port}&secret=${client_secret}"
        echo "tg://proxy?server=${PUBLIC_IPV4}&port=${port}&secret=${client_secret}"
        echo ""
    fi

    if [[ "$HAS_IPV6" == true ]]; then
        echo -e "${BLUE}Telegram连接链接 (IPv6):${NC}"
        echo "https://t.me/proxy?server=${PUBLIC_IPV6}&port=${port}&secret=${client_secret}"
        echo "tg://proxy?server=${PUBLIC_IPV6}&port=${port}&secret=${client_secret}"
    fi
}

# 网络环境诊断
diagnose_network_issues() {
    function_header "MTProxy 网络问题诊断"

    # 首先进行基本的网络检测
    ensure_network_detected

    print_info "📡 网络环境分析"
    echo -e "当前环境: ${GREEN}$NETWORK_TYPE${NC}"

    # 针对不同环境提供详细的诊断和建议
    case "$NETWORK_TYPE" in
        "dual_stack")
            print_success "✔ 双栈环境 - 最佳配置"
            echo "  📊 诊断结果:"
            echo "    - IPv4 和 IPv6 均可用"
            echo "    - MTProxy 将优先使用IPv4"
            echo "    - 客户端可选择IPv4 或 IPv6 连接"
            ;;
        "ipv4_only")
            print_warning "⚠ 纯IPv4环境"
            echo "  📊 诊断结果:"
            echo "    - 只有IPv4 可用"
            echo "    - IPv6 连接链接将无法使用"
            echo "  🛠 优化建议:"
            echo "    - 考虑启用IPv6（如果服务商支持）"
            echo "    - 确保IPv4 连接稳定性"
            ;;
        "ipv6_only")
            print_warning "⚠ 纯IPv6环境"
            echo "  📊 诊断结果:"
            echo "    - 只有IPv6 可用"
            echo "    - IPv4 连接链接将无法使用"
            echo "  🛠 优化建议:"
            echo "    - 配置IPv4 隧道或 NAT64"
            echo "    - 或使用WARP 获取IPv4 连接"
            echo "    - 确保客户端支持IPv6"
            ;;
        "warp_proxy")
            print_warning "⚠ WARP代理环境"
            echo "  📊 诊断结果:"
            echo "    - 检测到Cloudflare WARP"
            echo "    - 可能存在连接稳定性问题"
            echo "  🛠 优化建议:"
            echo "    - 尝试重启WARP: warp-cli disconnect && warp-cli connect"
            echo "    - 或尝试使用原生IPv6"
            echo "    - 监控连接稳定性"
            ;;
        "unknown")
            print_error "✘ 网络环境异常"
            echo "  📊 诊断结果:"
            echo "    - 无法获取有效的公网IP"
            echo "    - 可能存在网络连接问题"
            echo "  🔧 故障排除:"
            echo "    - 检查网络连接: ping 8.8.8.8"
            echo "    - 检查DNS解析: nslookup google.com"
            echo "    - 检查防火墙设置"
            ;;
    esac

    echo ""

    # MTProxy特定的诊断
    if load_config; then
        print_info "📡 MTProxy配置诊断"

        # 检查端口占用
        if is_port_occupied $port; then
            local process=$(get_port_process $port)
            if [[ "$process" == *"mtg"* ]]; then
                print_success "✔ 端口 $port 被MTProxy正常占用"
            else
                print_error "✘ 端口 $port 被其他进程占用: $process"
                echo "  🔧 解决方案: 停止占用进程或更改端口"
            fi
        else
            print_warning "⚠ 端口 $port 未被占用"
            echo "  🛠 可能原因: MTProxy未启动或启动失败"
        fi

        # 检查防火墙配置
        print_info "📡 防火墙配置检查"
        case $OS in
            "rhel")
                if systemctl is-active firewalld >/dev/null 2>&1; then
                    if firewall-cmd --list-ports | grep -q "$port/tcp"; then
                        print_success "✔ Firewalld端口 $port 已开放"
                    else
                        print_error "✘ Firewalld端口 $port 未开放"
                        echo "  🔧 解决方案:"
                        echo "    firewall-cmd --permanent --add-port=$port/tcp"
                        echo "    firewall-cmd --permanent --add-port=$web_port/tcp"
                        echo "    firewall-cmd --reload"
                    fi
                else
                    print_info "☑ Firewalld未运行"
                fi
                ;;
            "debian")
                if command -v ufw >/dev/null 2>&1 && ufw status | grep -q "Status: active"; then
                    if ufw status | grep -q "$port/tcp"; then
                        print_success "✔ UFW端口 $port 已开放"
                    else
                        print_error "✘ UFW端口 $port 未开放"
                        echo "  🔧 解决方案:"
                        echo "    ufw allow $port/tcp"
                        echo "    ufw allow $web_port/tcp"
                    fi
                else
                    print_info "☑ UFW未激活或未安装"
                fi
                ;;
            "alpine")
                print_info "☑ Alpine Linux通常无需额外防火墙配置"
                ;;
        esac

        # 连接测试建议
        echo ""
        print_info "📡 连接测试建议"
        echo "1. 本地测试: telnet 127.0.0.1 $port"
        if [[ "$HAS_IPV4" == true ]]; then
            echo "2. IPv4测试: telnet $PUBLIC_IPV4 $port"
        fi
        if [[ "$HAS_IPV6" == true ]]; then
            echo "3. IPv6测试: telnet $PUBLIC_IPV6 $port"
        fi
        echo "4. 使用Telegram客户端测试连接链接"

    else
        print_warning "⚠ MTProxy配置文件不存在"
        echo "  🛠 建议: 先运行安装程序创建配置"
    fi
}

# 自动修复功能
auto_fix() {
    function_header "自动修复功能"

    # 网络环境诊断
    diagnose_network_issues

    # 检查并安装缺失的依赖
    print_info "检查并安装缺失的依赖..."
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
    print_success "依赖检查完成"

    # 清理残留进程
    print_info "清理可能的重影进程..."
    pkill -f mtg 2>/dev/null
    rm -f $pid_file
    print_success "进程清理完成"

    # 检查并修复MTG程序
    if [ ! -f "./mtg" ]; then
        print_info "MTG程序不存在，正在下载..."
        download_mtg
    fi

    # 修复权限
    print_info "修复文件权限..."
    chmod +x ./mtg 2>/dev/null
    chmod +x ./*.sh 2>/dev/null
    print_success "权限修复完成"

    # 根据网络环境给出建议
    print_info "网络环境优化建议..."
    ensure_network_detected
    case "$NETWORK_TYPE" in
        "warp_proxy")
            print_warning "WARP环境建议:"
            echo "- 考虑重启WARP服务"
            echo "- 或尝试使用原生IPv6"
            ;;
        "ipv6_only")
            print_warning "IPv6环境建议:"
            echo "- 确保客户端支持IPv6"
            echo "- 考虑配置IPv4隧道"
            ;;
        "unknown")
            print_error "网络环境异常，建议检查网络配置"
            ;;
    esac
}

# 修改端口配置
change_ports() {
    function_header "修改端口配置"
    
    if ! load_config; then
        return 1
    fi
    
    print_info "当前配置:"
    echo "  客户端端口: $port"
    echo "  管理端口: $web_port"
    echo ""
    
    # 输入新端口
    read -p "请输入新的客户端端口 [$port]: " new_port
    if [ -z "$new_port" ]; then
        new_port=$port
    fi
    
    read -p "请输入新的管理端口 [$web_port]: " new_web_port
    if [ -z "$new_web_port" ]; then
        new_web_port=$web_port
    fi
    
    # 验证端口
    if ! validate_port $new_port; then
        print_error "无效的客户端端口: $new_port"
        return 1
    fi
    
    if ! validate_port $new_web_port; then
        print_error "无效的管理端口: $new_web_port"
        return 1
    fi
    
    # 检查端口冲突
    if [ "$new_port" != "$port" ] && is_port_occupied $new_port; then
        print_error "端口 $new_port 已被占用"
        return 1
    fi
    
    if [ "$new_web_port" != "$web_port" ] && is_port_occupied $new_web_port; then
        print_error "端口 $new_web_port 已被占用"
        return 1
    fi
    
    # 停止当前服务
    if check_process_status >/dev/null; then
        print_info "停止当前MTProxy服务..."
        stop_mtproxy
    fi
    
    # 更新配置
    print_info "更新配置文件..."
    sed -i "s/port=$port/port=$new_port/" ./mtp_config
    sed -i "s/web_port=$web_port/web_port=$new_web_port/" ./mtp_config
    
    print_success "端口配置已更新"
    print_info "新配置:"
    echo "  客户端端口: $new_port"
    echo "  管理端口: $new_web_port"
    
    # 询问是否立即启动服务
    read -p "是否立即启动服务? (y/N): " restart_confirm
    if [[ "$restart_confirm" =~ ^[Yy]$ ]]; then
        start_mtproxy
    fi
}

# 进程监控和自动重启
monitor_mtproxy() {
    function_header "进程监控和自动重启"
    
    print_info "启动MTProxy进程监控..."
    print_warning "按 Ctrl+C 停止监控"
    
    local restart_count=0
    local max_restarts=5
    local check_interval=30
    local last_restart_time=0
    
    while true; do
        if check_process_status >/dev/null; then
            local pid=$(check_process_status)
            print_success "MTProxy运行正常 (PID: $pid)"
            restart_count=0  # 重置重启计数
        else
            print_warning "MTProxy进程已停止，尝试重启..."
            
            # 检查重启频率限制
            local current_time=$(date +%s)
            if [ $((current_time - last_restart_time)) -lt 60 ]; then
                print_error "重启过于频繁，等待60秒..."
                sleep 60
                continue
            fi
            
            # 检查最大重启次数
            if [ $restart_count -ge $max_restarts ]; then
                print_error "已达到最大重启次数 ($max_restarts)，停止监控"
                break
            fi
            
            # 尝试重启
            if start_mtproxy; then
                restart_count=$((restart_count + 1))
                last_restart_time=$current_time
                print_success "重启成功 (第 $restart_count 次)"
            else
                print_error "重启失败"
            fi
        fi
        
        sleep $check_interval
    done
}

# 创建系统服务
create_systemd_service() {
    function_header "创建系统服务"
    
    if [ $EUID -ne 0 ]; then
        print_error "创建系统服务需要root权限"
        return 1
    fi
    
    if ! load_config; then
        return 1
    fi
    
    local script_path="$(pwd)/mtproxy.sh"
    
    # 检测系统类型并创建相应的服务
    if [[ "$OS" == "alpine" ]]; then
        # Alpine Linux - 使用OpenRC
        print_info "检测到Alpine Linux，创建OpenRC服务..."
        
        local service_file="/etc/init.d/mtproxy"
        cat > $service_file <<EOF
#!/sbin/openrc-run

name="MTProxy"
description="MTProxy Service"
command="$script_path"
command_args="start"
pidfile="/var/run/mtproxy.pid"
command_background="yes"
start_stop_daemon_args="--background --make-pidfile --pidfile \$pidfile"

depend() {
    need net
    after net
}

start() {
    ebegin "Starting MTProxy"
    start-stop-daemon --start --background --make-pidfile --pidfile \$pidfile --exec \$command -- \$command_args
    eend \$?
}

stop() {
    ebegin "Stopping MTProxy"
    start-stop-daemon --stop --pidfile \$pidfile
    eend \$?
}

restart() {
    stop
    sleep 1
    start
}
EOF
        
        chmod +x $service_file
        
        # 添加到默认运行级别
        rc-update add mtproxy default 2>/dev/null
        
        print_success "OpenRC服务创建成功"
        print_info "服务管理命令:"
        echo "  启动服务: rc-service mtproxy start"
        echo "  停止服务: rc-service mtproxy stop"
        echo "  重启服务: rc-service mtproxy restart"
        echo "  查看状态: rc-service mtproxy status"
        echo "  开机自启: rc-update add mtproxy default"
        echo "  取消自启: rc-update del mtproxy default"
        
        read -p "是否立即启动服务? (y/N): " start_confirm
        if [[ "$start_confirm" =~ ^[Yy]$ ]]; then
            rc-service mtproxy start
            sleep 2
            rc-service mtproxy status
        fi
        
    else
        # 其他系统 - 使用systemd
        print_info "创建systemd服务文件..."
        
        local service_file="/etc/systemd/system/mtproxy.service"
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
        
        # 重载systemd并启用服务
        systemctl daemon-reload
        systemctl enable mtproxy
        
        print_success "systemd服务创建成功"
        print_info "服务管理命令:"
        echo "  启动服务: systemctl start mtproxy"
        echo "  停止服务: systemctl stop mtproxy"
        echo "  重启服务: systemctl restart mtproxy"
        echo "  查看状态: systemctl status mtproxy"
        echo "  查看日志: journalctl -u mtproxy -f"
        
        read -p "是否立即启动systemd服务? (y/N): " start_confirm
        if [[ "$start_confirm" =~ ^[Yy]$ ]]; then
            systemctl start mtproxy
            sleep 2
            systemctl status mtproxy --no-pager
        fi
    fi
}

# 健康检查
health_check() {
    function_header "MTProxy健康检查"
    
    local health_score=0
    local max_score=100
    
    print_info "开始健康检查..."
    
    # 1. 检查配置文件 (20分)
    if [ -f "./mtp_config" ]; then
        print_success "✔ 配置文件存在 (+20分)"
        health_score=$((health_score + 20))
    else
        print_error "✘ 配置文件不存在 (-20分)"
    fi
    
    # 2. 检查MTG程序 (20分)
    if [ -f "./mtg" ] && [ -x "./mtg" ]; then
        print_success "✔ MTG程序存在且可执行 (+20分)"
        health_score=$((health_score + 20))
    else
        print_error "✘ MTG程序不存在或不可执行 (-20分)"
    fi
    
    # 3. 检查进程状态 (30分)
    if check_process_status >/dev/null; then
        local pid=$(check_process_status)
        print_success "✔ MTProxy进程运行正常 (PID: $pid) (+30分)"
        health_score=$((health_score + 30))
        
        # 检查内存使用
        local mem_usage=$(ps -o rss= -p $pid 2>/dev/null | awk '{print int($1/1024)}')
        if [ -n "$mem_usage" ]; then
            if [ $mem_usage -lt 100 ]; then
                print_success "✔ 内存使用正常 (${mem_usage}MB) (+10分)"
                health_score=$((health_score + 10))
            else
                print_warning "⚠ 内存使用较高 (${mem_usage}MB) (+5分)"
                health_score=$((health_score + 5))
            fi
        fi
    else
        print_error "✘ MTProxy进程未运行 (-30分)"
    fi
    
    # 4. 检查端口监听 (20分)
    if load_config; then
        if netstat -tulpn 2>/dev/null | grep -q ":$port "; then
            print_success "✔ 端口 $port 监听正常 (+20分)"
            health_score=$((health_score + 20))
        else
            print_error "✘ 端口 $port 未监听 (-20分)"
        fi
    fi
    
    # 5. 检查日志文件 (10分)
    if [ -f "./logs/mtproxy.log" ]; then
        local log_size=$(stat -c%s "./logs/mtproxy.log" 2>/dev/null || echo "0")
        if [ $log_size -gt 0 ]; then
            print_success "✔ 日志文件正常 (+10分)"
            health_score=$((health_score + 10))
        else
            print_warning "⚠ 日志文件为空 (+5分)"
            health_score=$((health_score + 5))
        fi
    else
        print_warning "⚠ 日志文件不存在 (+0分)"
    fi
    
    # 显示健康分数
    print_line
    print_info "健康检查完成"
    echo -e "健康分数: ${GREEN}$health_score/$max_score${NC}"
    
    if [ $health_score -ge 90 ]; then
        print_success "🎉 系统状态优秀"
    elif [ $health_score -ge 70 ]; then
        print_warning "⚠ 系统状态良好，有改进空间"
    elif [ $health_score -ge 50 ]; then
        print_warning "⚠ 系统状态一般，建议检查"
    else
        print_error "✘ 系统状态较差，需要修复"
    fi
    
    print_line
}

# 生成随机十六进制字符串
gen_rand_hex() {
    local length=$1
    openssl rand -hex $((length/2))
}

# 获取系统架构
get_architecture() {
    local arch=$(uname -m)
    case "$arch" in
        "x86_64") echo "amd64" ;;
        "aarch64") echo "arm64" ;;
        "armv7l") echo "armv7" ;;
        "i386"|"i686") echo "386" ;;
        *) echo "amd64" ;;  # 默认使用amd64
    esac
}

# 安装系统依赖
install_dependencies() {
    print_info "安装系统依赖..."
    
    case "$PKG_MANAGER" in
        "apk")
            apk update
            apk add --no-cache curl wget tar gzip openssl netstat-nat
            ;;
        "yum"|"dnf")
            $PKG_MANAGER update -y
            $PKG_MANAGER install -y curl wget tar gzip openssl net-tools
            ;;
        "apt")
            apt update
            apt install -y curl wget tar gzip openssl net-tools
            ;;
        *)
            print_error "不支持的包管理器: $PKG_MANAGER"
            return 1
            ;;
    esac
    
    print_success "依赖安装完成"
}

# 配置MTProxy
config_mtproxy() {
    function_header "配置MTProxy"
    
    # 端口配置
    read -p "请输入客户端连接端口 (默认 443): " input_port
    [ -z "$input_port" ] && input_port=443
    
    read -p "请输入管理端口 (默认 8888): " input_manage_port
    [ -z "$input_manage_port" ] && input_manage_port=8888
    
    # 域名配置
    read -p "请输入伪装域名 (默认 azure.microsoft.com): " input_domain
    [ -z "$input_domain" ] && input_domain="azure.microsoft.com"
    
    # TAG配置
    read -p "请输入推广TAG (可选，直接回车跳过): " input_tag
    
    # 生成配置
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
    
    print_success "配置生成完成"
}

# 显示防火墙配置提示
show_firewall_commands() {
    function_header "防火墙配置提示"
    
    # 从配置文件读取端口
    if [ -f "./mtp_config" ]; then
        source ./mtp_config
    fi
    
    case "$OS" in
        "alpine")
            echo "Alpine Linux 通常不需要额外的防火墙配置"
            echo "如果使用iptables:"
            echo "iptables -A INPUT -p tcp --dport $port -j ACCEPT"
            echo "iptables -A INPUT -p tcp --dport $web_port -j ACCEPT"
            ;;
        "rhel")
            echo "CentOS/RHEL/AlmaLinux 防火墙配置:"
            echo "firewall-cmd --permanent --add-port=$port/tcp"
            echo "firewall-cmd --permanent --add-port=$web_port/tcp"
            echo "firewall-cmd --reload"
            ;;
        "debian")
            echo "Debian/Ubuntu 防火墙配置:"
            echo "ufw allow $port/tcp"
            echo "ufw allow $web_port/tcp"
            ;;
    esac
}

# 下载MTG程序
download_mtg() {
    print_info "下载MTG ($(get_architecture))..."
    
    local arch=$(get_architecture)
    local mtg_url="https://github.com/9seconds/mtg/releases/latest/download/mtg-linux-$arch"
    
    # 尝试下载
    if curl -L --connect-timeout 10 --retry 3 -o mtg "$mtg_url"; then
        # 检查文件大小，MTG程序应该至少几MB
        local file_size=$(stat -c%s mtg 2>/dev/null || echo "0")
        if [ "$file_size" -lt 1000000 ]; then  # 小于1MB说明下载失败
            print_error "MTG下载失败：文件大小异常 ($file_size bytes)"
            rm -f mtg
            return 1
        fi
        
        chmod +x mtg
        print_success "MTG下载完成 ($(($file_size / 1024 / 1024))MB)"
        return 0
    else
        print_error "MTG下载失败：网络连接错误"
        return 1
    fi
}

# 一键安装并运行
install_and_run() {
    function_header "开始一键安装MTProxy..."
    
    # 检测系统
    ensure_system_detected
    
    # 安装依赖
    install_dependencies
    if [ $? -ne 0 ]; then
        print_error "依赖安装失败"
        return 1
    fi
    
    # 下载MTG
    download_mtg
    if [ $? -ne 0 ]; then
        print_error "MTG下载失败"
        return 1
    fi
    
    # 配置MTProxy
    config_mtproxy
    if [ $? -ne 0 ]; then
        print_error "配置失败"
        return 1
    fi
    
    # 显示防火墙配置提示
    show_firewall_commands
    
    # 启动MTProxy
    start_mtproxy
    if [ $? -eq 0 ]; then
        print_success "安装完成！"
    else
        print_error "启动失败，请检查配置"
        return 1
    fi
}

# 完全卸载MTProxy
uninstall_mtproxy() {
    function_header "完全卸载MTProxy"
    
    print_warning "⚠ 将完全卸载MTProxy，包括所有配置和日志文件"
    read -p "确认继续? (y/N): " confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        print_info "取消卸载"
        return 0
    fi
    
    print_info "正在卸载MTProxy..."
    
    # 1. 停止服务
    stop_mtproxy
    
    # 2. 杀死所有相关进程
    pkill -f mtg 2>/dev/null
    pkill -9 -f mtg 2>/dev/null
    pkill -f mtproxy 2>/dev/null
    
    # 3. 停止并删除systemd服务
    if [ -f "/etc/systemd/system/mtproxy.service" ]; then
        systemctl stop mtproxy 2>/dev/null
        systemctl disable mtproxy 2>/dev/null
        rm -f /etc/systemd/system/mtproxy.service
        systemctl daemon-reload 2>/dev/null
    fi
    
    # 4. 删除所有相关文件
    print_info "删除程序文件..."
    
    # 强制删除MTG程序
    if [ -f "./mtg" ]; then
        rm -f ./mtg
        print_info "已删除: ./mtg"
    fi
    
    # 强制删除配置文件
    if [ -f "./mtp_config" ]; then
        rm -f ./mtp_config
        print_info "已删除: ./mtp_config"
    fi
    
    # 删除配置文件变体
    rm -f ./mtp_config.*
    
    # 删除PID文件
    if [ -f "$pid_file" ]; then
        rm -f $pid_file
        print_info "已删除: $pid_file"
    fi
    
    # 删除PID目录
    if [ -d "./pid" ]; then
        rm -rf ./pid
        print_info "已删除: ./pid/"
    fi
    
    # 删除日志目录和文件
    if [ -d "./logs" ]; then
        rm -rf ./logs
        print_info "已删除: ./logs/"
    fi
    
    # 删除其他相关文件
    rm -f ./mtg.tar.gz
    rm -f ./mtg.*
    rm -f ./config.*
    rm -f ./*.log
    
    # 额外检查：删除可能存在的其他文件
    for file in mtg mtp_config mtproxy.log; do
        if [ -f "./$file" ]; then
            rm -f "./$file"
            print_info "已删除: ./$file"
        fi
    done
    
    # 检查是否还有残留文件
    local remaining_files=$(ls -la | grep -E "(mtg|mtp_config|mtproxy\.log)" | wc -l)
    if [ "$remaining_files" -gt 0 ]; then
        print_warning "发现残留文件，尝试强制删除..."
        ls -la | grep -E "(mtg|mtp_config|mtproxy\.log)"
        # 强制删除
        rm -f ./mtg* ./mtp_config* ./mtproxy.log* 2>/dev/null
    fi
    
    print_success "MTProxy已完全卸载"
    
    # 询问是否删除脚本本身
    echo
    read -p "是否删除管理脚本 (mtproxy.sh)? (y/N): " delete_script
    if [[ "$delete_script" =~ ^[Yy]$ ]]; then
        if [ -f "./mtproxy.sh" ]; then
            rm -f ./mtproxy.sh
            print_success "管理脚本已删除"
            print_info "如需重新安装，请重新下载脚本"
        fi
    else
        print_info "管理脚本 (mtproxy.sh) 保留，可用于重新安装"
    fi
}

# 一键安装并运行
install_and_run() {
    function_header "开始一键安装MTProxy..."

    ensure_system_detected
    install_dependencies
    download_mtg
    config_mtproxy
    start_mtproxy

    print_success "安装完成！"
}

# 完整系统检查
full_system_check() {
    clear
    echo -e "${PURPLE}"
    echo "========================================"
    echo "        MTProxy 完整系统检查"
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
    print_info "系统检查完成"
    print_line
}

# 主菜单
show_menu() {
    clear
    echo -e "${PURPLE}"
    echo "========================================"
    echo "     MTProxy 增强版管理系统"
    echo "   支持 Alpine/RHEL/Debian 系统"
    echo "========================================"
    echo -e "${NC}"

    if [ -f "./mtp_config" ]; then
        show_proxy_info
    else
        print_info "MTProxy未安装"
        print_line
    fi

    echo -e "${YELLOW}请选择操作:${NC}"
    echo "1.  一键安装并运行MTProxy"
    echo "2.  启动MTProxy"
    echo "3.  停止MTProxy"
    echo "4.  重启MTProxy"
    echo "5.  查看代理信息"
    echo "6.  修改端口配置"
    echo "7.  完整系统检查"
    echo "8.  网络环境诊断"
    echo "9.  自动修复问题"
    echo "10. 进程监控和自动重启"
    echo "11. 创建系统服务"
    echo "12. 健康检查"
    echo "13. 完全卸载MTProxy"
    echo "0.  退出"
    echo
}

# 主程序
main() {
    # 检查是否为root用户
    if [[ $EUID -ne 0 ]]; then
        print_warning "建议使用root用户运行此脚本以获取完整功能"
    fi

    while true; do
        show_menu
        read -p "请输入选项 [0-13]: " choice

        case $choice in
            1)
                install_and_run
                read -p "按回车键继续..."
                ;;
            2)
                ensure_system_detected
                start_mtproxy
                read -p "按回车键继续..."
                ;;
            3)
                stop_mtproxy
                read -p "按回车键继续..."
                ;;
            4)
                ensure_system_detected
                stop_mtproxy
                sleep 1
                start_mtproxy
                read -p "按回车键继续..."
                ;;
            5)
                show_proxy_info
                read -p "按回车键继续..."
                ;;
            6)
                ensure_system_detected
                change_ports
                read -p "按回车键继续..."
                ;;
            7)
                full_system_check
                read -p "按回车键继续..."
                ;;
            8)
                ensure_system_detected
                diagnose_network_issues
                read -p "按回车键继续..."
                ;;
            9)
                ensure_system_detected
                auto_fix
                read -p "按回车键继续..."
                ;;
            10)
                ensure_system_detected
                monitor_mtproxy
                read -p "按回车键继续..."
                ;;
            11)
                ensure_system_detected
                create_systemd_service
                read -p "按回车键继续..."
                ;;
            12)
                ensure_system_detected
                health_check
                read -p "按回车键继续..."
                ;;
            13)
                uninstall_mtproxy
                read -p "按回车键继续..."
                ;;
            0)
                print_info "退出脚本"
                exit 0
                ;;
            *)
                print_error "无效选项，请重新选择"
                sleep 1
                ;;
        esac
    done
}

# 检查参数
if [[ $# -eq 0 ]]; then
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
            echo "用法: $0 [install|start|stop|restart|status|check|diagnose|fix|ports|monitor|systemd|health|uninstall]"
            echo "或直接运行 $0 进入交互模式"
            echo ""
            echo "命令说明:"
            echo "  install   - 一键安装并运行"
            echo "  start     - 启动服务"
            echo "  stop      - 停止服务"
            echo "  restart   - 重启服务"
            echo "  status    - 查看状态"
            echo "  check     - 完整系统检查"
            echo "  diagnose  - 网络环境诊断"
            echo "  fix       - 自动修复问题"
            echo "  ports     - 修改端口配置"
            echo "  monitor   - 进程监控和自动重启"
            echo "  systemd   - 创建系统服务"
            echo "  health    - 健康检查"
            echo "  uninstall - 完全卸载"
            ;;
    esac
fi
