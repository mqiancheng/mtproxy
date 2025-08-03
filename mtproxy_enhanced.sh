#!/bin/bash

# MTProxy 增强版管理脚本
# 包含完整的检查、诊断和修复功能
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
        print_error "不支持的操作系统"
        exit 1
    fi
}

# 系统信息检查
check_system_info() {
    print_line
    print_info "系统信息检查"
    print_line
    
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
    print_line
    print_info "网络连接检查"
    print_line
    
    # 检查IPv4连接
    print_info "检查IPv4连接..."
    local ipv4=$(curl -s --connect-timeout 10 https://api.ip.sb/ip -A Mozilla --ipv4)
    if [[ -n "$ipv4" && "$ipv4" != *"curl:"* ]]; then
        echo -e "IPv4地址: ${GREEN}$ipv4${NC}"
    else
        echo -e "IPv4连接: ${RED}失败${NC}"
    fi
    
    # 检查IPv6连接
    print_info "检查IPv6连接..."
    local ipv6=$(curl -s --connect-timeout 10 https://api.ip.sb/ip -A Mozilla --ipv6 2>/dev/null)
    if [[ -n "$ipv6" && "$ipv6" != *"curl:"* && "$ipv6" != *"error"* ]]; then
        echo -e "IPv6地址: ${GREEN}$ipv6${NC}"
    else
        echo -e "IPv6连接: ${YELLOW}不可用${NC}"
    fi
    
    # 检查DNS解析
    print_info "检查DNS解析..."
    if nslookup google.com >/dev/null 2>&1; then
        echo -e "DNS解析: ${GREEN}正常${NC}"
    else
        echo -e "DNS解析: ${RED}异常${NC}"
    fi
    
    # 检查网络接口
    print_info "网络接口信息:"
    ip addr show | grep -E "inet |inet6 " | grep -v "127.0.0.1" | grep -v "::1" | while read line; do
        echo -e "  ${CYAN}$line${NC}"
    done
}

# 端口检查
check_ports() {
    print_line
    print_info "端口使用情况检查"
    print_line
    
    # 检查常用端口
    local common_ports=(22 80 443 8080 8443 8888 9999)
    for port in "${common_ports[@]}"; do
        if netstat -tulpn 2>/dev/null | grep -q ":$port "; then
            local process=$(netstat -tulpn 2>/dev/null | grep ":$port " | awk '{print $7}' | head -1)
            echo -e "端口 $port: ${RED}被占用${NC} ($process)"
        else
            echo -e "端口 $port: ${GREEN}可用${NC}"
        fi
    done
    
    # 如果有配置文件，检查配置的端口
    if [ -f "./mtp_config" ]; then
        source ./mtp_config
        echo ""
        print_info "MTProxy配置端口检查:"
        
        if netstat -tulpn 2>/dev/null | grep -q ":$port "; then
            local process=$(netstat -tulpn 2>/dev/null | grep ":$port " | awk '{print $7}' | head -1)
            echo -e "客户端端口 $port: ${RED}被占用${NC} ($process)"
        else
            echo -e "客户端端口 $port: ${GREEN}可用${NC}"
        fi
        
        if netstat -tulpn 2>/dev/null | grep -q ":$web_port "; then
            local process=$(netstat -tulpn 2>/dev/null | grep ":$web_port " | awk '{print $7}' | head -1)
            echo -e "管理端口 $web_port: ${RED}被占用${NC} ($process)"
        else
            echo -e "管理端口 $web_port: ${GREEN}可用${NC}"
        fi
    fi
}

# 防火墙检查
check_firewall() {
    print_line
    print_info "防火墙状态检查"
    print_line
    
    case $OS in
        "rhel")
            if command -v firewall-cmd >/dev/null 2>&1; then
                if systemctl is-active firewalld >/dev/null 2>&1; then
                    echo -e "Firewalld: ${GREEN}运行中${NC}"
                    if [ -f "./mtp_config" ]; then
                        source ./mtp_config
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
                    if [ -f "./mtp_config" ]; then
                        source ./mtp_config
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
    print_line
    print_info "MTProxy状态检查"
    print_line
    
    # 检查配置文件
    if [ -f "./mtp_config" ]; then
        echo -e "配置文件: ${GREEN}存在${NC}"
        source ./mtp_config
        echo -e "客户端端口: ${GREEN}$port${NC}"
        echo -e "管理端口: ${GREEN}$web_port${NC}"
        echo -e "伪装域名: ${GREEN}$domain${NC}"
        [[ -n "$proxy_tag" ]] && echo -e "推广TAG: ${GREEN}$proxy_tag${NC}" || echo -e "推广TAG: ${YELLOW}未设置${NC}"
    else
        echo -e "配置文件: ${RED}不存在${NC}"
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
    if [ -f "$pid_file" ]; then
        local pid=$(cat $pid_file)
        if kill -0 $pid 2>/dev/null; then
            echo -e "进程状态: ${GREEN}运行中${NC} (PID: $pid)"
            
            # 检查进程详情
            local process_info=$(ps aux | grep $pid | grep -v grep | head -1)
            echo -e "进程信息: ${CYAN}$process_info${NC}"
            
            # 检查端口监听
            if netstat -tulpn 2>/dev/null | grep -q ":$port "; then
                echo -e "端口监听: ${GREEN}正常${NC} ($port)"
            else
                echo -e "端口监听: ${RED}异常${NC} ($port)"
            fi
            
        else
            echo -e "进程状态: ${RED}已停止${NC} (PID文件存在但进程不存在)"
            rm -f $pid_file
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

# 连接测试
test_connection() {
    print_line
    print_info "连接测试"
    print_line
    
    if [ ! -f "./mtp_config" ]; then
        print_error "配置文件不存在，无法进行连接测试"
        return 1
    fi
    
    source ./mtp_config
    local public_ip=$(curl -s --connect-timeout 10 https://api.ip.sb/ip -A Mozilla --ipv4)
    
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

    # 测试IPv4外部连接
    if [[ -n "$public_ip" ]]; then
        print_info "测试IPv4外部连接 ($public_ip:$port)..."
        if timeout 10 bash -c "</dev/tcp/$public_ip/$port" 2>/dev/null; then
            echo -e "IPv4外部端口 $port: ${GREEN}可连接${NC}"
        else
            echo -e "IPv4外部端口 $port: ${RED}无法连接${NC}"
        fi
    fi

    # 测试IPv6外部连接
    local public_ipv6=$(curl -s --connect-timeout 10 https://api.ip.sb/ip -A Mozilla --ipv6 2>/dev/null)
    if [[ -n "$public_ipv6" && "$public_ipv6" != *"curl:"* && "$public_ipv6" != *"error"* ]]; then
        print_info "测试IPv6外部连接 ([$public_ipv6]:$port)..."
        if timeout 10 bash -c "</dev/tcp/$public_ipv6/$port" 2>/dev/null; then
            echo -e "IPv6外部端口 $port: ${GREEN}可连接${NC}"
        else
            echo -e "IPv6外部端口 $port: ${RED}无法连接${NC}"
        fi
    else
        echo -e "IPv6地址: ${YELLOW}不可用，跳过IPv6连接测试${NC}"
    fi
    
    # 生成连接信息
    if [[ -n "$public_ip" ]]; then
        local domain_hex=$(printf "%s" "$domain" | od -An -tx1 | tr -d ' \n')
        local client_secret="ee${secret}${domain_hex}"
        
        print_info "连接信息:"
        echo -e "服务器IP: ${GREEN}$public_ip${NC}"
        echo -e "端口: ${GREEN}$port${NC}"
        echo -e "密钥: ${GREEN}$client_secret${NC}"
        echo ""
        echo -e "${BLUE}Telegram连接链接:${NC}"
        echo "https://t.me/proxy?server=${public_ip}&port=${port}&secret=${client_secret}"
        echo "tg://proxy?server=${public_ip}&port=${port}&secret=${client_secret}"
    fi
}

# 依赖检查
check_dependencies() {
    print_line
    print_info "依赖检查"
    print_line
    
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

# 自动修复功能
auto_fix() {
    print_line
    print_info "自动修复功能"
    print_line

    # 安装缺失的依赖
    print_info "检查并安装缺失的依赖..."
    case $OS in
        "alpine")
            apk update >/dev/null 2>&1
            apk add --no-cache curl wget procps net-tools >/dev/null 2>&1
            ;;
        "rhel")
            $PKG_MANAGER install -y curl wget procps-ng net-tools >/dev/null 2>&1
            ;;
        "debian")
            apt update >/dev/null 2>&1
            apt install -y curl wget procps net-tools >/dev/null 2>&1
            ;;
    esac
    print_success "依赖检查完成"

    # 清理僵尸进程
    print_info "清理可能的僵尸进程..."
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
}

# 端口修改功能
change_ports() {
    print_line
    print_info "端口修改功能"
    print_line

    if [ ! -f "./mtp_config" ]; then
        print_error "配置文件不存在，请先安装MTProxy"
        return 1
    fi

    source ./mtp_config

    echo -e "当前客户端端口: ${GREEN}$port${NC}"
    echo -e "当前管理端口: ${GREEN}$web_port${NC}"
    echo ""

    # 输入新端口
    while true; do
        read -p "请输入新的客户端端口 (直接回车保持 $port): " new_port
        [ -z "$new_port" ] && new_port=$port

        if [[ "$new_port" =~ ^[0-9]+$ ]] && [ $new_port -ge 1 ] && [ $new_port -le 65535 ]; then
            if netstat -tulpn 2>/dev/null | grep -q ":$new_port " && [ $new_port -ne $port ]; then
                print_warning "端口 $new_port 已被占用"
                netstat -tulpn 2>/dev/null | grep ":$new_port "
                read -p "是否强制使用此端口? (y/N): " force
                if [[ "$force" == "y" || "$force" == "Y" ]]; then
                    break
                fi
            else
                break
            fi
        else
            print_error "请输入有效的端口号 [1-65535]"
        fi
    done

    while true; do
        read -p "请输入新的管理端口 (直接回车保持 $web_port): " new_web_port
        [ -z "$new_web_port" ] && new_web_port=$web_port

        if [[ "$new_web_port" =~ ^[0-9]+$ ]] && [ $new_web_port -ge 1 ] && [ $new_web_port -le 65535 ]; then
            if [ $new_web_port -eq $new_port ]; then
                print_error "管理端口不能与客户端端口相同"
            elif netstat -tulpn 2>/dev/null | grep -q ":$new_web_port " && [ $new_web_port -ne $web_port ]; then
                print_warning "端口 $new_web_port 已被占用"
                read -p "是否强制使用此端口? (y/N): " force
                if [[ "$force" == "y" || "$force" == "Y" ]]; then
                    break
                fi
            else
                break
            fi
        else
            print_error "请输入有效的端口号 [1-65535]"
        fi
    done

    # 确认修改
    if [ $new_port -eq $port ] && [ $new_web_port -eq $web_port ]; then
        print_info "端口未发生变化"
        return 0
    fi

    print_warning "端口修改确认:"
    echo -e "客户端端口: $port → ${GREEN}$new_port${NC}"
    echo -e "管理端口: $web_port → ${GREEN}$new_web_port${NC}"

    read -p "确认修改? (y/N): " confirm
    if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
        print_info "取消修改"
        return 0
    fi

    # 停止服务
    stop_mtproxy

    # 修改配置
    sed -i "s/port=$port/port=$new_port/g" mtp_config
    sed -i "s/web_port=$web_port/web_port=$new_web_port/g" mtp_config

    print_success "端口修改完成"

    # 显示防火墙提示
    show_firewall_commands $new_port $new_web_port

    # 重启服务
    read -p "是否立即重启服务? (Y/n): " restart
    if [[ "$restart" != "n" && "$restart" != "N" ]]; then
        start_mtproxy
    fi
}

# 显示防火墙命令
show_firewall_commands() {
    local client_port=$1
    local manage_port=$2

    print_line
    print_warning "防火墙配置提示"
    print_line

    case $OS in
        "rhel")
            echo "AlmaLinux/RHEL/CentOS 防火墙配置:"
            echo "firewall-cmd --permanent --add-port=$client_port/tcp"
            echo "firewall-cmd --permanent --add-port=$manage_port/tcp"
            echo "firewall-cmd --reload"
            ;;
        "debian")
            echo "Debian/Ubuntu 防火墙配置:"
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

# 生成随机字符串
gen_rand_hex() {
    dd if=/dev/urandom bs=1 count=500 status=none 2>/dev/null | od -An -tx1 | tr -d ' \n' | head -c $1
}

# 字符串转十六进制
str_to_hex() {
    printf "%s" "$1" | od -An -tx1 | tr -d ' \n'
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
    print_line
    print_info "配置MTProxy"
    print_line

    # 端口配置
    while true; do
        read -p "请输入客户端连接端口 (默认 443): " input_port
        [ -z "$input_port" ] && input_port=443

        if [[ "$input_port" =~ ^[0-9]+$ ]] && [ $input_port -ge 1 ] && [ $input_port -le 65535 ]; then
            if netstat -tulpn 2>/dev/null | grep -q ":$input_port "; then
                print_warning "端口 $input_port 已被占用"
                netstat -tulpn 2>/dev/null | grep ":$input_port "
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

        if [[ "$input_manage_port" =~ ^[0-9]+$ ]] && [ $input_manage_port -ge 1 ] && [ $input_manage_port -le 65535 ]; then
            if [ $input_manage_port -eq $input_port ]; then
                print_error "管理端口不能与客户端端口相同"
            elif netstat -tulpn 2>/dev/null | grep -q ":$input_manage_port "; then
                print_warning "端口 $input_manage_port 已被占用"
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
    if [ ! -f "./mtp_config" ]; then
        print_error "配置文件不存在，请先安装"
        return 1
    fi

    source ./mtp_config

    # 检查是否已运行
    if [ -f "$pid_file" ]; then
        local pid=$(cat $pid_file)
        if kill -0 $pid 2>/dev/null; then
            print_warning "MTProxy已经在运行中 (PID: $pid)"
            return 0
        else
            rm -f $pid_file
        fi
    fi

    # 检查MTG程序
    if [ ! -f "./mtg" ]; then
        print_error "MTG程序不存在，请重新安装"
        return 1
    fi

    # 杀死可能占用端口的进程
    if netstat -tulpn 2>/dev/null | grep -q ":$port "; then
        print_info "释放端口 $port..."
        local pids=$(netstat -tulpn 2>/dev/null | grep ":$port " | awk '{print $7}' | sed 's|/.*||')
        for pid in $pids; do
            kill -9 $pid 2>/dev/null
        done
    fi

    if netstat -tulpn 2>/dev/null | grep -q ":$web_port "; then
        print_info "释放端口 $web_port..."
        local pids=$(netstat -tulpn 2>/dev/null | grep ":$web_port " | awk '{print $7}' | sed 's|/.*||')
        for pid in $pids; do
            kill -9 $pid 2>/dev/null
        done
    fi

    # 创建pid目录
    mkdir -p pid

    # 构建运行命令
    local domain_hex=$(str_to_hex $domain)
    local client_secret="ee${secret}${domain_hex}"
    local public_ip=$(curl -s --connect-timeout 10 https://api.ip.sb/ip -A Mozilla --ipv4)

    print_info "正在启动MTProxy..."

    # 启动MTG
    if [[ -n "$proxy_tag" ]]; then
        ./mtg run $client_secret $proxy_tag -b 0.0.0.0:$port --multiplex-per-connection 500 --prefer-ip=ipv6 -t 127.0.0.1:$web_port -4 "$public_ip:$port" >/dev/null 2>&1 &
    else
        ./mtg run $client_secret -b 0.0.0.0:$port --multiplex-per-connection 500 --prefer-ip=ipv6 -t 127.0.0.1:$web_port -4 "$public_ip:$port" >/dev/null 2>&1 &
    fi

    echo $! > $pid_file
    sleep 3

    # 检查启动状态
    if [ -f "$pid_file" ]; then
        local pid=$(cat $pid_file)
        if kill -0 $pid 2>/dev/null; then
            print_success "MTProxy启动成功 (PID: $pid)"
            show_proxy_info
        else
            print_error "MTProxy启动失败"
            rm -f $pid_file
            return 1
        fi
    else
        print_error "MTProxy启动失败"
        return 1
    fi
}

# 停止MTProxy
stop_mtproxy() {
    if [ -f "$pid_file" ]; then
        local pid=$(cat $pid_file)
        if kill -0 $pid 2>/dev/null; then
            print_info "正在停止MTProxy (PID: $pid)..."
            kill -9 $pid 2>/dev/null
            rm -f $pid_file
        else
            print_info "PID文件存在但进程不存在，清理PID文件"
            rm -f $pid_file
        fi
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
    if [ ! -f "./mtp_config" ]; then
        print_error "配置文件不存在"
        return 1
    fi

    source ./mtp_config
    local public_ip=$(curl -s --connect-timeout 10 https://api.ip.sb/ip -A Mozilla --ipv4)
    local public_ipv6=$(curl -s --connect-timeout 10 https://api.ip.sb/ip -A Mozilla --ipv6 2>/dev/null)
    local domain_hex=$(str_to_hex $domain)
    local client_secret="ee${secret}${domain_hex}"

    print_line
    if [ -f "$pid_file" ] && kill -0 $(cat $pid_file) 2>/dev/null; then
        print_success "MTProxy状态: 运行中"
    else
        print_warning "MTProxy状态: 已停止"
    fi

    echo -e "系统类型: ${PURPLE}$os${NC}"
    echo -e "服务器IPv4: ${GREEN}$public_ip${NC}"
    if [[ -n "$public_ipv6" && "$public_ipv6" != *"curl:"* && "$public_ipv6" != *"error"* ]]; then
        echo -e "服务器IPv6: ${GREEN}$public_ipv6${NC}"
    fi
    echo -e "客户端端口: ${GREEN}$port${NC}"
    echo -e "管理端口: ${GREEN}$web_port${NC}"
    echo -e "代理密钥: ${GREEN}$client_secret${NC}"
    echo -e "伪装域名: ${GREEN}$domain${NC}"
    [[ -n "$proxy_tag" ]] && echo -e "推广TAG: ${GREEN}$proxy_tag${NC}"

    echo -e "\n${BLUE}Telegram连接链接 (IPv4):${NC}"
    echo "https://t.me/proxy?server=${public_ip}&port=${port}&secret=${client_secret}"
    echo "tg://proxy?server=${public_ip}&port=${port}&secret=${client_secret}"

    if [[ -n "$public_ipv6" && "$public_ipv6" != *"curl:"* && "$public_ipv6" != *"error"* ]]; then
        echo -e "\n${BLUE}Telegram连接链接 (IPv6):${NC}"
        echo "https://t.me/proxy?server=${public_ipv6}&port=${port}&secret=${client_secret}"
        echo "tg://proxy?server=${public_ipv6}&port=${port}&secret=${client_secret}"
    fi
    print_line
}

# 完全卸载
uninstall_mtproxy() {
    print_warning "即将完全卸载MTProxy，包括所有配置文件和进程"
    read -p "确认卸载? (y/N): " confirm

    if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
        print_info "取消卸载"
        return 0
    fi

    print_info "正在卸载MTProxy..."

    # 停止服务
    stop_mtproxy

    # 杀死所有相关进程
    pkill -f mtg 2>/dev/null
    pkill -9 -f mtg 2>/dev/null

    # 删除文件
    rm -f ./mtg
    rm -f ./mtp_config
    rm -rf ./pid
    rm -f ./mtg.tar.gz

    print_success "MTProxy已完全卸载"
}

# 一键安装并运行
install_and_run() {
    print_line
    print_info "开始一键安装MTProxy..."
    print_line

    detect_system
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

    detect_system
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
    echo "     MTProxy 增强版管理脚本"
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
    echo "8.  自动修复问题"
    echo "9.  完全卸载MTProxy"
    echo "0.  退出"
    echo
}

# 主程序
main() {
    # 检查是否为root用户
    if [[ $EUID -ne 0 ]]; then
        print_warning "建议使用root用户运行此脚本以获得完整功能"
    fi

    while true; do
        show_menu
        read -p "请输入选项 [0-9]: " choice

        case $choice in
            1)
                install_and_run
                read -p "按回车键继续..."
                ;;
            2)
                detect_system 2>/dev/null
                start_mtproxy
                read -p "按回车键继续..."
                ;;
            3)
                stop_mtproxy
                read -p "按回车键继续..."
                ;;
            4)
                detect_system 2>/dev/null
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
                detect_system 2>/dev/null
                change_ports
                read -p "按回车键继续..."
                ;;
            7)
                full_system_check
                read -p "按回车键继续..."
                ;;
            8)
                detect_system 2>/dev/null
                auto_fix
                read -p "按回车键继续..."
                ;;
            9)
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
    detect_system 2>/dev/null
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
        "fix")
            auto_fix
            ;;
        "ports")
            change_ports
            ;;
        "uninstall")
            uninstall_mtproxy
            ;;
        *)
            echo "用法: $0 [install|start|stop|restart|status|check|fix|ports|uninstall]"
            echo "或直接运行 $0 进入交互模式"
            echo ""
            echo "命令说明:"
            echo "  install   - 一键安装并运行"
            echo "  start     - 启动服务"
            echo "  stop      - 停止服务"
            echo "  restart   - 重启服务"
            echo "  status    - 查看状态"
            echo "  check     - 完整系统检查"
            echo "  fix       - 自动修复问题"
            echo "  ports     - 修改端口配置"
            echo "  uninstall - 完全卸载"
            ;;
    esac
fi
