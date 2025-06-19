#!/bin/bash

# MTProxy 快速一键安装脚本
# 支持 Alpine Linux, AlmaLinux/RHEL/CentOS, Debian/Ubuntu

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_info() { echo -e "${BLUE}[信息]${NC} $1"; }
print_success() { echo -e "${GREEN}[成功]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[警告]${NC} $1"; }
print_error() { echo -e "${RED}[错误]${NC} $1"; }

# 系统检测
detect_system() {
    if [[ -f /etc/alpine-release ]]; then
        OS="alpine"
        PKG_MANAGER="apk"
    elif [[ -f /etc/redhat-release ]] || [[ -f /etc/almalinux-release ]] || [[ -f /etc/centos-release ]]; then
        OS="rhel"
        PKG_MANAGER="yum"
        command -v dnf >/dev/null 2>&1 && PKG_MANAGER="dnf"
    elif [[ -f /etc/debian_version ]]; then
        OS="debian"
        PKG_MANAGER="apt"
    else
        print_error "不支持的操作系统"
        exit 1
    fi
    print_info "检测到系统: $OS (使用 $PKG_MANAGER)"
}

# 获取公网IP
get_ip_public() {
    public_ip=$(curl -s https://api.ip.sb/ip -A Mozilla --ipv4 --connect-timeout 10)
    [ -z "$public_ip" ] && public_ip=$(curl -s ipinfo.io/ip -A Mozilla --ipv4 --connect-timeout 10)
    echo $public_ip
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

# 安装依赖
install_deps() {
    print_info "安装依赖包..."
    case $OS in
        "alpine") apk update && apk add --no-cache curl wget procps net-tools ;;
        "rhel") $PKG_MANAGER install -y curl wget procps-ng net-tools ;;
        "debian") apt update && apt install -y curl wget procps net-tools ;;
    esac
}

# 下载MTG
download_mtg() {
    print_info "下载MTG..."
    local arch=$(get_architecture)
    local url="https://github.com/9seconds/mtg/releases/download/v1.0.11/mtg-1.0.11-linux-$arch.tar.gz"
    
    wget $url -O mtg.tar.gz -q --timeout=30 || {
        print_error "下载失败"
        exit 1
    }
    
    tar -xzf mtg.tar.gz mtg-1.0.11-linux-$arch/mtg --strip-components 1
    chmod +x mtg
    rm -f mtg.tar.gz
    
    [ -f "./mtg" ] || {
        print_error "MTG安装失败"
        exit 1
    }
}

# 快速配置
quick_config() {
    print_info "使用默认配置..."
    
    # 默认配置
    local port=443
    local web_port=8888
    local domain="azure.microsoft.com"
    local secret=$(gen_rand_hex 32)
    local public_ip=$(get_ip_public)
    
    # 保存配置
    cat > mtp_config <<EOF
secret="$secret"
port=$port
web_port=$web_port
domain="$domain"
proxy_tag=""
os="$OS"
pkg_manager="$PKG_MANAGER"
EOF
    
    print_success "配置完成: 端口=$port, 管理端口=$web_port"
}

# 启动服务
start_service() {
    print_info "启动MTProxy..."
    
    source ./mtp_config
    
    # 创建pid目录
    mkdir -p pid
    
    # 构建命令
    local domain_hex=$(str_to_hex $domain)
    local client_secret="ee${secret}${domain_hex}"
    local public_ip=$(get_ip_public)
    
    # 启动
    ./mtg run $client_secret -b 0.0.0.0:$port --multiplex-per-connection 500 --prefer-ip=ipv6 -t 127.0.0.1:$web_port -4 "$public_ip:$port" >/dev/null 2>&1 &
    
    echo $! > pid/pid_mtproxy
    sleep 2
    
    # 检查状态
    if kill -0 $(cat pid/pid_mtproxy) 2>/dev/null; then
        print_success "MTProxy启动成功！"
        show_info
    else
        print_error "启动失败"
        exit 1
    fi
}

# 显示信息
show_info() {
    source ./mtp_config
    local public_ip=$(get_ip_public)
    local domain_hex=$(str_to_hex $domain)
    local client_secret="ee${secret}${domain_hex}"
    
    echo "========================================"
    echo -e "${GREEN}MTProxy 安装完成！${NC}"
    echo "========================================"
    echo -e "服务器IP: ${GREEN}$public_ip${NC}"
    echo -e "端口: ${GREEN}$port${NC}"
    echo -e "密钥: ${GREEN}$client_secret${NC}"
    echo -e "管理端口: ${GREEN}$web_port${NC}"
    echo ""
    echo -e "${BLUE}Telegram连接链接:${NC}"
    echo "https://t.me/proxy?server=${public_ip}&port=${port}&secret=${client_secret}"
    echo "tg://proxy?server=${public_ip}&port=${port}&secret=${client_secret}"
    echo "========================================"
    echo ""
    echo -e "${YELLOW}管理命令:${NC}"
    echo "启动: ./mtproxy_universal.sh start"
    echo "停止: ./mtproxy_universal.sh stop"
    echo "状态: ./mtproxy_universal.sh status"
    echo "卸载: ./mtproxy_universal.sh uninstall"
}

# 主函数
main() {
    echo -e "${BLUE}MTProxy 一键安装脚本${NC}"
    echo "========================================"
    
    detect_system
    install_deps
    download_mtg
    quick_config
    start_service
    
    print_success "安装完成！请保存上面的连接信息。"
}

# 运行
main
