# MTProxy 增强版管理脚本

支持多种Linux发行版的MTProxy一键安装和管理脚本，包含完整的检查、诊断和修复功能。

## 🎯 支持的系统

- ✅ **Alpine Linux** (v3.19+)
- ✅ **AlmaLinux/RHEL/CentOS** (7+)
- ✅ **Debian/Ubuntu** (18.04+)

## 📦 脚本说明

### `mtproxy.sh` - 增强版管理脚本
提供完整的安装、配置、管理和监控功能，包含进程稳定性解决方案。

## 🚀 快速开始

### 📝 使用说明

**基本使用流程：**

1. **首次安装**：运行脚本选择 `功能1` 进行一键安装并启动
2. **进程稳定性**：如果发现代理后台被杀死，建议开启 `功能11` 创建systemd服务
   - systemd服务可确保进程自动重启和开机启动
   - 提供更强的进程稳定性和系统级管理

**推荐配置顺序：**
```bash
./mtproxy.sh
# 选择 1 - 一键安装并运行MTProxy
# 测试正常后，选择 11 - 创建systemd服务（推荐）
```

### 💻 一键安装命令

```bash
wget https://raw.githubusercontent.com/mqiancheng/mtproxy/main/mtproxy.sh && chmod +x mtproxy.sh && ./mtproxy.sh
```

<details>
<summary>📋 点击复制安装命令</summary>

```bash
wget https://raw.githubusercontent.com/mqiancheng/mtproxy/main/mtproxy.sh && chmod +x mtproxy.sh && ./mtproxy.sh
```

</details>

## 📋 功能特性

### ✨ 主要功能
- 🔄 **自动系统检测** - 自动识别Linux发行版
- 🌐 **IPv4/IPv6双栈支持** - 自动检测并生成对应链接
- 🎛️ **交互式配置** - 友好的配置界面
- 📊 **状态监控** - 实时查看运行状态
- 🗑️ **完整卸载** - 彻底清理所有文件
- 🔧 **进程稳定性** - 解决进程被杀死问题
- 📈 **健康检查** - 全面的系统健康评估
- 🚨 **自动修复** - 智能问题诊断和修复

### 🛠️ 管理功能
- ▶️ 启动/停止/重启服务
- 📈 查看运行状态和代理信息
- 🔧 端口配置修改
- 🚨 进程监控和自动重启
- 🏥 系统健康检查
- 🔍 网络环境诊断
- 🛠️ 自动修复问题
- 🗑️ 完全卸载

### 🔧 高级功能
- 📊 **systemd服务支持** - 系统级服务管理
- 🔄 **进程监控** - 自动检测和重启
- 📝 **日志记录** - 完整的运行日志
- 🌐 **网络诊断** - 智能网络环境分析
- ⚡ **性能优化** - 网络超时优化（6秒）

## 📖 使用说明

### 安装后管理
安装完成后，您可以使用以下命令管理MTProxy：

```bash
# 查看状态和连接信息
./mtproxy.sh status

# 停止服务
./mtproxy.sh stop

# 启动服务
./mtproxy.sh start

# 重启服务
./mtproxy.sh restart

# 进程监控和自动重启
./mtproxy.sh monitor

# 健康检查
./mtproxy.sh health

# 网络环境诊断
./mtproxy.sh diagnose

# 自动修复问题
./mtproxy.sh fix

# 创建systemd服务
./mtproxy.sh systemd

# 完全卸载
./mtproxy.sh uninstall
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
```bash
# 使用端口修改功能
./mtproxy.sh ports
```

### 推广TAG
如需使用推广TAG：
1. 联系 @MTProxybot 获取TAG
2. 在配置阶段输入TAG

### systemd服务（推荐）
创建系统级服务，确保开机自启和自动重启：
```bash
# 创建systemd服务
./mtproxy.sh systemd

# 管理服务
systemctl start mtproxy    # 启动
systemctl stop mtproxy     # 停止
systemctl restart mtproxy  # 重启
systemctl status mtproxy   # 状态
systemctl enable mtproxy   # 开机自启
```

### 进程监控
实时监控进程状态，自动重启：
```bash
# 启动监控
./mtproxy.sh monitor
```

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

## 🔧 进程稳定性解决方案

### 问题：MTProxy进程经常被杀死

这是一个常见问题，可能的原因包括：
- 系统资源不足（内存/CPU）
- 系统重启后未自动启动
- OOM Killer杀死进程
- 网络环境变化

### 解决方案

#### 1. 使用进程监控（推荐）
```bash
# 启动进程监控
./mtproxy.sh monitor
```

#### 2. 创建systemd服务（最佳方案）
```bash
# 创建systemd服务
./mtproxy.sh systemd

# 管理服务
systemctl start mtproxy    # 启动
systemctl stop mtproxy     # 停止
systemctl restart mtproxy  # 重启
systemctl status mtproxy   # 状态
systemctl enable mtproxy   # 开机自启
```

#### 3. 设置定时任务
```bash
# 编辑crontab
crontab -e

# 添加以下配置（每5分钟检查一次）
*/5 * * * * /path/to/mtproxy/mtproxy.sh start
```

#### 4. 健康检查
```bash
# 定期健康检查
./mtproxy.sh health

# 查看详细状态
./mtproxy.sh check
```

## 🐛 故障排除

### 常见问题

**1. 进程经常被杀死**
```bash
# 检查系统资源
free -h
df -h
top

# 使用监控功能
./mtproxy.sh monitor

# 创建systemd服务
./mtproxy.sh systemd
```

**2. 下载失败**
```bash
# 检查网络连接
curl -I https://github.com

# 使用代理下载
export https_proxy=http://your-proxy:port
```

**3. 端口被占用**
```bash
# 查看端口占用
netstat -tulpn | grep :443

# 杀死占用进程
pkill -f mtg
```

**4. 服务启动失败**
```bash
# 查看详细错误
./mtg run [参数] # 不加后台运行查看错误

# 查看日志
tail -f ./logs/mtproxy.log
```

**5. IPv6不工作**
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

# 查看MTProxy日志
tail -f ./logs/mtproxy.log
```

### 系统资源优化
```bash
# 检查内存使用
./mtproxy.sh health

# 如果内存不足，考虑：
# 1. 增加swap空间
# 2. 优化系统配置
# 3. 定期重启服务
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
