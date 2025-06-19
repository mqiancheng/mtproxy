# MTProxy 通用安装脚本

支持多种Linux发行版的MTProxy一键安装和管理脚本。

## 🎯 支持的系统

- ✅ **Alpine Linux** (v3.19+)
- ✅ **AlmaLinux/RHEL/CentOS** (7+)
- ✅ **Debian/Ubuntu** (18.04+)

## 📦 脚本说明

### 1. `quick_install.sh` - 快速一键安装
最简单的安装方式，使用默认配置快速部署。

```bash
# 下载并运行
wget https://raw.githubusercontent.com/mqiancheng/mtproxy/main/quick_install.sh
chmod +x quick_install.sh
./quick_install.sh
```

**默认配置：**
- 端口：443
- 管理端口：8888
- 伪装域名：azure.microsoft.com

### 2. `mtproxy_universal.sh` - 完整管理脚本
提供完整的安装、配置和管理功能。

```bash
# 下载脚本
wget https://raw.githubusercontent.com/mqiancheng/mtproxy/main/mtproxy_universal.sh
chmod +x mtproxy_universal.sh

# 交互式菜单
./mtproxy_universal.sh

# 命令行使用
./mtproxy_universal.sh install    # 安装
./mtproxy_universal.sh start      # 启动
./mtproxy_universal.sh stop       # 停止
./mtproxy_universal.sh restart    # 重启
./mtproxy_universal.sh status     # 查看状态
./mtproxy_universal.sh uninstall  # 卸载
```

## 🚀 快速开始

### 方法一：一键安装（推荐新手）
```bash
bash <(curl -fsSL https://raw.githubusercontent.com/mqiancheng/mtproxy/main/quick_install.sh)
```

### 方法二：完整安装
```bash
# 下载脚本
wget https://raw.githubusercontent.com/mqiancheng/mtproxy/main/mtproxy_universal.sh
chmod +x mtproxy_universal.sh

# 运行安装
./mtproxy_universal.sh
# 选择选项 1 进行安装
```

## 📋 功能特性

### ✨ 主要功能
- 🔄 **自动系统检测** - 自动识别Linux发行版
- 🌐 **IPv4/IPv6双栈支持** - 自动检测并生成对应链接
- 🎛️ **交互式配置** - 友好的配置界面
- 📊 **状态监控** - 实时查看运行状态
- 🗑️ **完整卸载** - 彻底清理所有文件

### 🛠️ 管理功能
- ▶️ 启动/停止服务
- 🔄 重启服务
- 📈 查看运行状态
- 🔧 重新配置
- 🗑️ 完全卸载

## 📖 使用说明

### 安装后管理
安装完成后，您可以使用以下命令管理MTProxy：

```bash
# 查看状态和连接信息
./mtproxy_universal.sh status

# 停止服务
./mtproxy_universal.sh stop

# 启动服务
./mtproxy_universal.sh start

# 重启服务
./mtproxy_universal.sh restart

# 完全卸载
./mtproxy_universal.sh uninstall
```

### 配置文件
配置文件保存在 `mtp_config`，包含以下信息：
- 代理密钥
- 端口配置
- 伪装域名
- 推广TAG（可选）

### 连接信息
安装完成后会显示：
- 服务器IP地址（IPv4/IPv6）
- 连接端口
- 代理密钥
- Telegram连接链接

## 🔧 高级配置

### 自定义端口
默认使用443端口，如需修改：
1. 运行完整安装脚本
2. 在配置阶段输入自定义端口

### 推广TAG
如需使用推广TAG：
1. 联系 @MTProxybot 获取TAG
2. 在配置阶段输入TAG

### 防火墙配置
确保以下端口开放：
- 代理端口（默认443）
- 管理端口（默认8888）

```bash
# CentOS/RHEL/AlmaLinux
firewall-cmd --permanent --add-port=443/tcp
firewall-cmd --permanent --add-port=8888/tcp
firewall-cmd --reload

# Debian/Ubuntu
ufw allow 443/tcp
ufw allow 8888/tcp

# Alpine Linux
# 通常不需要额外配置
```

## 🐛 故障排除

### 常见问题

**1. 下载失败**
```bash
# 检查网络连接
curl -I https://github.com

# 使用代理下载
export https_proxy=http://your-proxy:port
```

**2. 端口被占用**
```bash
# 查看端口占用
netstat -tulpn | grep :443

# 杀死占用进程
pkill -f mtg
```

**3. 服务启动失败**
```bash
# 查看详细错误
./mtg run [参数] # 不加后台运行查看错误
```

**4. IPv6不工作**
```bash
# 检查IPv6支持
ping6 google.com
curl -6 ipinfo.io/ip
```

### 日志查看
```bash
# 查看进程状态
ps aux | grep mtg

# 查看端口监听
netstat -tulpn | grep mtg
```

## 📞 支持

如遇问题，请提供以下信息：
- 操作系统版本：`cat /etc/os-release`
- 系统架构：`uname -m`
- 错误信息截图
- 网络环境说明

## 📄 许可证

MIT License

## 🤝 贡献

欢迎提交Issue和Pull Request！
