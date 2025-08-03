#!/bin/bash

# MTProxy 简洁版管理脚本
# 专门解决多种网络环境问题
# 支持: 纯IPv4、纯IPv6、双栈、WARP代理

WORKDIR=$(dirname $(readlink -f $0))
cd $WORKDIR
pid_file=$WORKDIR/mtproxy.pid

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# 打印函数
print_info() { echo -e "${BLUE}[信息]${NC} $1"; }
print_success() { echo -e "${GREEN}[成功]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[警告]${NC} $1"; }
print_error() { echo -e "${RED}[错误]${NC} $1"; }

# 检测网络环境
detect_network() {
    print_info "检测网络环境..."

    # 检测IPv4
    IPV4=$(curl -s --connect-timeout 10 --max-time 10 https://api.ip.sb/ip -A Mozilla --ipv4 2>/dev/null)
    if [[ -n "$IPV4" && "$IPV4" != *"curl:"* && "$IPV4" != *"error"* ]]; then
        HAS_IPV4=true
        # 检测WARP
        if [[ "$IPV4" =~ ^(162\.159\.|104\.28\.|172\.67\.|104\.16\.) ]]; then
            IS_WARP=true
        else
            IS_WARP=false
        fi
    else
        HAS_IPV4=false
        IS_WARP=false
    fi

    # 检测IPv6
    IPV6=$(curl -s --connect-timeout 10 --max-time 10 https://api.ip.sb/ip -A Mozilla --ipv6 2>/dev/null)
    if [[ -n "$IPV6" && "$IPV6" != *"curl:"* && "$IPV6" != *"error"* ]]; then
        HAS_IPV6=true
        # 检测WARP IPv6
        if [[ "$IPV6" =~ ^2606:4700: ]]; then
            IS_WARP=true
        fi
    else
        HAS_IPV6=false
    fi

    # 检测本地IP（用于NAT环境）
    LOCAL_IP=$(ip route get 8.8.8.8 2>/dev/null | grep -oP 'src \K\S+' | head -1)
    if [[ -n "$LOCAL_IP" && "$LOCAL_IP" != "$IPV4" ]]; then
        IS_NAT=true
    else
        IS_NAT=false
    fi

    # 确定网络类型
    if [[ "$HAS_IPV4" == true && "$HAS_IPV6" == true ]]; then
        NETWORK_TYPE="dual"
    elif [[ "$HAS_IPV4" == true && "$HAS_IPV6" == false ]]; then
        NETWORK_TYPE="ipv4"
    elif [[ "$HAS_IPV4" == false && "$HAS_IPV6" == true ]]; then
        NETWORK_TYPE="ipv6"
    else
        NETWORK_TYPE="none"
    fi

    if [[ "$IS_WARP" == true ]]; then
        NETWORK_TYPE="${NETWORK_TYPE}_warp"
    fi

    echo -e "网络类型: ${GREEN}$NETWORK_TYPE${NC}"
    [[ "$HAS_IPV4" == true ]] && echo -e "IPv4: ${GREEN}$IPV4${NC}"
    [[ "$HAS_IPV6" == true ]] && echo -e "IPv6: ${GREEN}$IPV6${NC}"
    [[ "$IS_WARP" == true ]] && echo -e "WARP: ${YELLOW}检测到${NC}"
    [[ "$IS_NAT" == true ]] && echo -e "NAT环境: ${YELLOW}是${NC} (本地IP: $LOCAL_IP)"
}

# 下载MTG
download_mtg() {
    if [ -f "./mtg" ]; then
        print_info "MTG已存在，跳过下载"
        return 0
    fi
    
    local arch
    case $(uname -m) in
        x86_64) arch="amd64" ;;
        aarch64) arch="arm64" ;;
        armv7l) arch="armv6l" ;;
        i386|i686) arch="386" ;;
        *) print_error "不支持的架构: $(uname -m)" && exit 1 ;;
    esac
    
    print_info "下载MTG ($arch)..."
    local url="https://github.com/9seconds/mtg/releases/download/v1.0.11/mtg-1.0.11-linux-$arch.tar.gz"
    
    if ! wget -q --timeout=30 "$url" -O mtg.tar.gz; then
        print_error "下载失败"
        return 1
    fi
    
    tar -xzf mtg.tar.gz "mtg-1.0.11-linux-$arch/mtg" --strip-components 1
    chmod +x mtg
    rm -f mtg.tar.gz
    
    if [ -f "./mtg" ]; then
        print_success "MTG下载完成"
    else
        print_error "MTG安装失败"
        return 1
    fi
}

# 生成配置
generate_config() {
    print_info "配置MTProxy..."
    
    # 端口配置
    read -p "客户端端口 (默认 443): " PORT
    PORT=${PORT:-443}
    
    read -p "管理端口 (默认 8888): " WEB_PORT
    WEB_PORT=${WEB_PORT:-8888}
    
    read -p "伪装域名 (默认 azure.microsoft.com): " DOMAIN
    DOMAIN=${DOMAIN:-azure.microsoft.com}
    
    read -p "推广TAG (可选): " TAG
    
    # 生成密钥
    SECRET=$(dd if=/dev/urandom bs=1 count=16 2>/dev/null | od -An -tx1 | tr -d ' \n')
    
    # 保存配置
    cat > ./mtproxy.conf <<EOF
PORT=$PORT
WEB_PORT=$WEB_PORT
DOMAIN="$DOMAIN"
TAG="$TAG"
SECRET="$SECRET"
EOF
    
    print_success "配置生成完成"
    echo -e "客户端端口: ${GREEN}$PORT${NC}"
    echo -e "管理端口: ${GREEN}$WEB_PORT${NC}"
    echo -e "伪装域名: ${GREEN}$DOMAIN${NC}"
}

# 生成MTG启动命令
generate_mtg_command() {
    local domain_hex=$(printf "%s" "$DOMAIN" | od -An -tx1 | tr -d ' \n')
    local client_secret="ee${SECRET}${domain_hex}"
    
    # 根据网络环境选择绑定方式
    local bind_params=""
    local external_params=""
    
    case "$NETWORK_TYPE" in
        "dual"|"dual_warp")
            # 双栈：绑定所有接口，声明IPv4和IPv6
            bind_params="-b 0.0.0.0:$PORT"
            [[ "$HAS_IPV4" == true ]] && external_params="$external_params -4 $IPV4:$PORT"
            [[ "$HAS_IPV6" == true ]] && external_params="$external_params -6 [$IPV6]:$PORT"
            ;;
        "ipv4"|"ipv4_warp")
            # 纯IPv4：在NAT环境下正确配置
            # 绑定所有接口但通过临时禁用IPv6确保只用IPv4
            bind_params="-b 0.0.0.0:$PORT"
            external_params="-4 $IPV4:$PORT"
            ;;
        "ipv6"|"ipv6_warp")
            # 纯IPv6：只绑定IPv6
            bind_params="-b [::]:$PORT"
            external_params="-6 [$IPV6]:$PORT"
            ;;
        *)
            print_error "无法确定网络环境"
            return 1
            ;;
    esac
    
    # 构建完整命令
    local cmd="./mtg run $client_secret"
    [[ -n "$TAG" ]] && cmd="$cmd $TAG"
    cmd="$cmd $bind_params --multiplex-per-connection 500 -t 127.0.0.1:$WEB_PORT"
    cmd="$cmd $external_params"
    
    echo "$cmd"
}

# 启动MTProxy
start_mtproxy() {
    if [ ! -f "./mtproxy.conf" ]; then
        print_error "配置文件不存在，请先安装"
        return 1
    fi
    
    source ./mtproxy.conf
    
    # 检查是否已运行
    if [ -f "$pid_file" ] && kill -0 $(cat $pid_file) 2>/dev/null; then
        print_warning "MTProxy已在运行"
        return 0
    fi
    
    # 检测网络环境
    detect_network
    
    # 生成启动命令
    local mtg_cmd=$(generate_mtg_command)
    if [ $? -ne 0 ]; then
        return 1
    fi
    
    print_info "启动MTProxy..."
    print_info "命令: $mtg_cmd"

    # 在纯IPv4环境下，临时禁用IPv6以强制MTG使用IPv4
    local ipv6_disabled=false
    if [[ "$NETWORK_TYPE" == "ipv4" || "$NETWORK_TYPE" == "ipv4_warp" ]]; then
        if [ -f /proc/sys/net/ipv6/conf/all/disable_ipv6 ]; then
            local current_ipv6=$(cat /proc/sys/net/ipv6/conf/all/disable_ipv6)
            if [ "$current_ipv6" = "0" ]; then
                print_info "临时禁用IPv6以确保正确绑定..."
                echo 1 > /proc/sys/net/ipv6/conf/all/disable_ipv6 2>/dev/null
                ipv6_disabled=true
            fi
        fi
    fi

    # 启动MTG
    eval "$mtg_cmd" > mtg.log 2>&1 &
    echo $! > $pid_file

    sleep 3

    # 恢复IPv6设置
    if [ "$ipv6_disabled" = true ]; then
        sleep 1
        print_info "恢复IPv6设置..."
        echo 0 > /proc/sys/net/ipv6/conf/all/disable_ipv6 2>/dev/null
    fi

    # 检查启动状态
    if [ -f "$pid_file" ] && kill -0 $(cat $pid_file) 2>/dev/null; then
        print_success "MTProxy启动成功 (PID: $(cat $pid_file))"
        show_info
    else
        print_error "MTProxy启动失败"
        if [ -f "mtg.log" ]; then
            print_error "错误日志:"
            cat mtg.log
        fi
        rm -f $pid_file
        return 1
    fi
}

# 停止MTProxy
stop_mtproxy() {
    if [ -f "$pid_file" ]; then
        local pid=$(cat $pid_file)
        if kill -0 $pid 2>/dev/null; then
            print_info "停止MTProxy (PID: $pid)..."
            kill $pid
            rm -f $pid_file
        else
            print_info "清理无效PID文件"
            rm -f $pid_file
        fi
    fi
    
    # 确保清理所有mtg进程
    pkill -f mtg 2>/dev/null
    print_success "MTProxy已停止"
}

# 显示信息
show_info() {
    if [ ! -f "./mtproxy.conf" ]; then
        print_error "配置文件不存在"
        return 1
    fi
    
    source ./mtproxy.conf
    detect_network
    
    local domain_hex=$(printf "%s" "$DOMAIN" | od -An -tx1 | tr -d ' \n')
    local client_secret="ee${SECRET}${domain_hex}"
    
    echo "========================================"
    if [ -f "$pid_file" ] && kill -0 $(cat $pid_file) 2>/dev/null; then
        print_success "MTProxy状态: 运行中"
    else
        print_warning "MTProxy状态: 已停止"
    fi
    
    echo -e "网络环境: ${GREEN}$NETWORK_TYPE${NC}"
    [[ "$HAS_IPV4" == true ]] && echo -e "IPv4地址: ${GREEN}$IPV4${NC}"
    [[ "$HAS_IPV6" == true ]] && echo -e "IPv6地址: ${GREEN}$IPV6${NC}"
    echo -e "客户端端口: ${GREEN}$PORT${NC}"
    echo -e "管理端口: ${GREEN}$WEB_PORT${NC}"
    echo -e "代理密钥: ${GREEN}$client_secret${NC}"
    echo -e "伪装域名: ${GREEN}$DOMAIN${NC}"
    [[ -n "$TAG" ]] && echo -e "推广TAG: ${GREEN}$TAG${NC}"
    
    echo ""
    if [[ "$HAS_IPV4" == true ]]; then
        echo -e "${BLUE}Telegram连接链接 (IPv4):${NC}"
        echo "https://t.me/proxy?server=${IPV4}&port=${PORT}&secret=${client_secret}"
        echo "tg://proxy?server=${IPV4}&port=${PORT}&secret=${client_secret}"
        echo ""
    fi
    
    if [[ "$HAS_IPV6" == true ]]; then
        echo -e "${BLUE}Telegram连接链接 (IPv6):${NC}"
        echo "https://t.me/proxy?server=${IPV6}&port=${PORT}&secret=${client_secret}"
        echo "tg://proxy?server=${IPV6}&port=${PORT}&secret=${client_secret}"
    fi
    echo "========================================"
}

# 安装MTProxy
install_mtproxy() {
    print_info "开始安装MTProxy..."

    # 安装依赖
    if command -v apt >/dev/null 2>&1; then
        apt update >/dev/null 2>&1
        apt install -y curl wget >/dev/null 2>&1
    elif command -v yum >/dev/null 2>&1; then
        yum install -y curl wget >/dev/null 2>&1
    elif command -v apk >/dev/null 2>&1; then
        apk update >/dev/null 2>&1
        apk add --no-cache curl wget >/dev/null 2>&1
    fi

    # 下载MTG
    download_mtg || return 1

    # 生成配置
    generate_config

    # 启动服务
    start_mtproxy

    print_success "安装完成！"
}

# 卸载MTProxy
uninstall_mtproxy() {
    print_warning "即将卸载MTProxy，包括所有配置文件"
    read -p "确认卸载? (y/N): " confirm

    if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
        print_info "取消卸载"
        return 0
    fi

    stop_mtproxy
    rm -f ./mtg ./mtproxy.conf ./mtproxy.pid
    print_success "卸载完成"
}

# 主菜单
show_menu() {
    clear
    echo -e "${BLUE}"
    echo "========================================"
    echo "        MTProxy 简洁版管理脚本"
    echo "    支持多种网络环境自动适配"
    echo "========================================"
    echo -e "${NC}"

    if [ -f "./mtproxy.conf" ]; then
        show_info
    else
        print_info "MTProxy未安装"
        echo "========================================"
    fi

    echo -e "${YELLOW}请选择操作:${NC}"
    echo "1. 安装MTProxy"
    echo "2. 启动MTProxy"
    echo "3. 停止MTProxy"
    echo "4. 重启MTProxy"
    echo "5. 查看信息"
    echo "6. 卸载MTProxy"
    echo "0. 退出"
    echo
}

# 主程序
main() {
    while true; do
        show_menu
        read -p "请输入选项 [0-6]: " choice

        case $choice in
            1)
                install_mtproxy
                read -p "按回车键继续..."
                ;;
            2)
                start_mtproxy
                read -p "按回车键继续..."
                ;;
            3)
                stop_mtproxy
                read -p "按回车键继续..."
                ;;
            4)
                stop_mtproxy
                sleep 1
                start_mtproxy
                read -p "按回车键继续..."
                ;;
            5)
                show_info
                read -p "按回车键继续..."
                ;;
            6)
                uninstall_mtproxy
                read -p "按回车键继续..."
                ;;
            0)
                print_info "退出脚本"
                exit 0
                ;;
            *)
                print_error "无效选项"
                sleep 1
                ;;
        esac
    done
}

# 命令行参数处理
if [[ $# -eq 0 ]]; then
    main
else
    case $1 in
        "install") install_mtproxy ;;
        "start") start_mtproxy ;;
        "stop") stop_mtproxy ;;
        "restart") stop_mtproxy && sleep 1 && start_mtproxy ;;
        "status") show_info ;;
        "uninstall") uninstall_mtproxy ;;
        *)
            echo "用法: $0 [install|start|stop|restart|status|uninstall]"
            echo "或直接运行 $0 进入交互模式"
            ;;
    esac
fi
