#!/bin/bash

# Synapse Matrix 服务器自动部署脚本
# 适用于 Ubuntu 20.04+ 系统

set -e  # 遇到错误立即退出

# 获取脚本所在目录的绝对路径
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 日志函数
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 检查是否为 root 用户
check_root() {
    if [[ $EUID -eq 0 ]]; then
        log_error "请不要以 root 用户运行此脚本"
        exit 1
    fi
}

# 检查系统版本
check_system() {
    # 检测操作系统类型
    if [[ "$OSTYPE" == "darwin"* ]]; then
        # macOS 系统
        log_success "系统检查通过: macOS (Darwin)"
        return 0
    elif [[ -f /etc/os-release ]]; then
        # Linux 系统
        . /etc/os-release
        if [[ "$ID" != "ubuntu" ]]; then
            log_warning "检测到非 Ubuntu 系统: $ID，部分功能可能不兼容"
        fi
        
        if [[ "$VERSION_ID" < "20.04" ]] && [[ "$ID" == "ubuntu" ]]; then
            log_error "需要 Ubuntu 20.04 或更高版本"
            exit 1
        fi
        
        log_success "系统检查通过: $ID $VERSION_ID"
    else
        log_warning "无法检测系统版本，继续执行部署"
    fi
}

# 获取用户输入
get_user_input() {
    echo
    log_info "请输入部署配置信息:"
    
    read -p "域名 (例如: matrix.example.com): " DOMAIN
    if [[ -z "$DOMAIN" ]]; then
        log_error "域名不能为空"
        exit 1
    fi
    
    read -p "选择部署方式 [docker/native] (默认: docker): " DEPLOY_METHOD
    DEPLOY_METHOD=${DEPLOY_METHOD:-docker}
    
    if [[ "$DEPLOY_METHOD" != "docker" && "$DEPLOY_METHOD" != "native" ]]; then
        log_error "无效的部署方式，请选择 docker 或 native"
        exit 1
    fi
    
    read -s -p "PostgreSQL 密码: " POSTGRES_PASSWORD
    echo
    if [[ -z "$POSTGRES_PASSWORD" ]]; then
        log_error "PostgreSQL 密码不能为空"
        exit 1
    fi
    
    read -s -p "Redis 密码: " REDIS_PASSWORD
    echo
    if [[ -z "$REDIS_PASSWORD" ]]; then
        log_error "Redis 密码不能为空"
        exit 1
    fi
    
    # 生成随机密钥
    REGISTRATION_SECRET=$(openssl rand -hex 32)
    MACAROON_SECRET=$(openssl rand -hex 32)
    FORM_SECRET=$(openssl rand -hex 32)
    
    log_success "配置信息收集完成"
}

# 更新系统
update_system() {
    log_info "更新系统包..."
    
    if [[ "$OSTYPE" == "darwin"* ]]; then
        # macOS 系统
        if command -v brew >/dev/null 2>&1; then
            brew update
            brew install curl wget git openssl
        else
            log_warning "未检测到 Homebrew，请手动安装必要依赖"
        fi
    else
        # Linux 系统
        sudo apt update && sudo apt upgrade -y
        sudo apt install -y curl wget git ufw openssl
    fi
    
    log_success "系统更新完成"
}

# 配置防火墙
setup_firewall() {
    log_info "配置防火墙..."
    
    if [[ "$OSTYPE" == "darwin"* ]]; then
        # macOS 系统 - 使用 pfctl
        log_warning "macOS 防火墙配置需要手动设置，请确保端口 80, 443, 8448 开放"
    else
        # Linux 系统 - 使用 ufw
        sudo ufw --force enable
        sudo ufw allow 22/tcp      # SSH
        sudo ufw allow 80/tcp      # HTTP
        sudo ufw allow 443/tcp     # HTTPS
        sudo ufw allow 8448/tcp    # Matrix Federation
    fi
    
    log_success "防火墙配置完成"
}

# Docker 部署
deploy_docker() {
    log_info "开始 Docker 部署..."
    
    # 检查并安装 Docker
    if ! command -v docker >/dev/null 2>&1; then
        log_info "安装 Docker..."
        if [[ "$OSTYPE" == "darwin"* ]]; then
            # macOS 系统
            log_warning "请手动安装 Docker Desktop for Mac: https://docs.docker.com/desktop/mac/install/"
            read -p "Docker 已安装完成后按回车继续..."
        else
            # Linux 系统
            curl -fsSL https://get.docker.com -o get-docker.sh
            sudo sh get-docker.sh
            sudo usermod -aG docker $USER
            rm get-docker.sh
        fi
    else
        log_success "Docker 已安装"
    fi
    
    # 检查并安装 Docker Compose
    if ! command -v docker-compose >/dev/null 2>&1; then
        log_info "安装 Docker Compose..."
        if [[ "$OSTYPE" == "darwin"* ]]; then
            # macOS 通常 Docker Desktop 已包含 docker-compose
            log_success "Docker Compose 已包含在 Docker Desktop 中"
        else
            # Linux 系统
            sudo curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
            sudo chmod +x /usr/local/bin/docker-compose
        fi
    else
        log_success "Docker Compose 已安装"
    fi
    
    # 创建部署目录
    DEPLOY_DIR="/opt/synapse"
    sudo mkdir -p $DEPLOY_DIR
    sudo chown $USER:$USER $DEPLOY_DIR
    cd $DEPLOY_DIR
    
    # 复制配置文件
    cp "$SCRIPT_DIR/docker-compose.yml" .
    cp "$SCRIPT_DIR/.env.example" .env
    
    # 更新环境变量
    sed -i "s/your-domain.com/$DOMAIN/g" .env
    sed -i "s/your_secure_postgres_password/$POSTGRES_PASSWORD/g" .env
    sed -i "s/your_secure_redis_password/$REDIS_PASSWORD/g" .env
    sed -i "s/your_registration_secret/$REGISTRATION_SECRET/g" .env
    sed -i "s/your_macaroon_secret/$MACAROON_SECRET/g" .env
    sed -i "s/your_form_secret/$FORM_SECRET/g" .env
    
    # 创建必要目录
    mkdir -p data config logs ssl
    
    # 获取 SSL 证书
    setup_ssl_docker
    
    # 生成 Synapse 配置
    log_info "生成 Synapse 配置..."
    docker run -it --rm \
        -v "$PWD/data:/data" \
        -e SYNAPSE_SERVER_NAME=$DOMAIN \
        -e SYNAPSE_REPORT_STATS=no \
        matrixdotorg/synapse:latest generate
    
    # 启动服务
    log_info "启动服务..."
    docker-compose up -d
    
    # 等待服务启动
    sleep 30
    
    log_success "Docker 部署完成"
}

# 原生部署
deploy_native() {
    log_info "开始原生部署..."
    
    # 安装依赖
    log_info "安装系统依赖..."
    sudo apt install -y \
        python3 python3-pip python3-venv \
        postgresql postgresql-contrib \
        nginx certbot python3-certbot-nginx \
        redis-server \
        build-essential libffi-dev \
        python3-dev libssl-dev \
        libjpeg-dev libxslt1-dev \
        libpq-dev
    
    # 配置 PostgreSQL
    setup_postgresql
    
    # 配置 Redis
    setup_redis
    
    # 安装 Synapse
    install_synapse
    
    # 配置 Synapse
    configure_synapse
    
    # 配置 systemd 服务
    setup_systemd
    
    # 配置 Nginx
    setup_nginx
    
    log_success "原生部署完成"
}

# 配置 PostgreSQL
setup_postgresql() {
    log_info "配置 PostgreSQL..."
    
    sudo -u postgres psql << EOF
CREATE USER synapse WITH PASSWORD '$POSTGRES_PASSWORD';
CREATE DATABASE synapse
    ENCODING 'UTF8'
    LC_COLLATE='C'
    LC_CTYPE='C'
    template=template0
    OWNER synapse;
\q
EOF
    
    # 配置认证
    PG_VERSION=$(sudo -u postgres psql -t -c "SELECT version();" | grep -oP '\d+\.\d+' | head -1)
    PG_HBA_FILE="/etc/postgresql/$PG_VERSION/main/pg_hba.conf"
    
    if ! grep -q "local synapse synapse md5" $PG_HBA_FILE; then
        echo "local synapse synapse md5" | sudo tee -a $PG_HBA_FILE
        sudo systemctl restart postgresql
    fi
    
    log_success "PostgreSQL 配置完成"
}

# 配置 Redis
setup_redis() {
    log_info "配置 Redis..."
    
    # 设置 Redis 密码
    sudo sed -i "s/# requirepass foobared/requirepass $REDIS_PASSWORD/" /etc/redis/redis.conf
    sudo systemctl restart redis-server
    sudo systemctl enable redis-server
    
    log_success "Redis 配置完成"
}

# 安装 Synapse
install_synapse() {
    log_info "安装 Synapse..."
    
    # 创建 synapse 用户
    sudo adduser --system --group --home /opt/synapse synapse || true
    
    # 创建虚拟环境
    sudo -u synapse bash << 'EOF'
cd /opt/synapse
python3 -m venv venv
source venv/bin/activate
pip install --upgrade pip setuptools
pip install matrix-synapse[postgres,redis]
EOF
    
    log_success "Synapse 安装完成"
}

# 配置 Synapse
configure_synapse() {
    log_info "配置 Synapse..."
    
    sudo mkdir -p /etc/synapse /var/lib/synapse /var/log/synapse
    sudo chown synapse:synapse /var/lib/synapse /var/log/synapse
    
    # 生成配置文件
    sudo -u synapse /opt/synapse/venv/bin/python -m synapse.app.homeserver \
        --server-name $DOMAIN \
        --config-path /etc/synapse/homeserver.yaml \
        --generate-config \
        --report-stats=no
    
    # 更新配置文件
    sudo tee /etc/synapse/homeserver.yaml > /dev/null << EOF
server_name: "$DOMAIN"
pid_file: /var/run/synapse.pid
listeners:
  - port: 8008
    tls: false
    type: http
    x_forwarded: true
    bind_addresses: ['127.0.0.1']
    resources:
      - names: [client, federation]
        compress: false

database:
  name: psycopg2
  args:
    user: synapse
    password: $POSTGRES_PASSWORD
    database: synapse
    host: localhost
    cp_min: 5
    cp_max: 10

redis:
  enabled: true
  host: localhost
  port: 6379
  password: $REDIS_PASSWORD

log_config: "/etc/synapse/log.config"
media_store_path: "/var/lib/synapse/media"
max_upload_size: 50M
enable_registration: false
registration_shared_secret: "$REGISTRATION_SECRET"
macaroon_secret_key: "$MACAROON_SECRET"
form_secret: "$FORM_SECRET"
signing_key_path: "/etc/synapse/signing.key"
trusted_key_servers:
  - server_name: "matrix.org"

# 好友功能配置
friends:
  enabled: true
  max_friends_per_user: 1000
  friend_request_timeout: 604800
EOF
    
    # 生成签名密钥
    sudo -u synapse /opt/synapse/venv/bin/python -m synapse.app.homeserver \
        --config-path /etc/synapse/homeserver.yaml \
        --generate-keys
    
    log_success "Synapse 配置完成"
}

# 配置 systemd 服务
setup_systemd() {
    log_info "配置 systemd 服务..."
    
    sudo cp "$SCRIPT_DIR/synapse.service" /etc/systemd/system/
    sudo systemctl daemon-reload
    sudo systemctl enable synapse
    sudo systemctl start synapse
    
    # 等待服务启动
    sleep 10
    
    if sudo systemctl is-active --quiet synapse; then
        log_success "Synapse 服务启动成功"
    else
        log_error "Synapse 服务启动失败"
        sudo systemctl status synapse
        exit 1
    fi
}

# 配置 SSL (Docker)
setup_ssl_docker() {
    log_info "配置 SSL 证书..."
    
    # 安装 Certbot
    sudo apt install -y certbot
    
    # 获取证书
    sudo certbot certonly --standalone -d $DOMAIN --non-interactive --agree-tos --email admin@$DOMAIN
    
    # 复制证书
    sudo cp /etc/letsencrypt/live/$DOMAIN/fullchain.pem ssl/
    sudo cp /etc/letsencrypt/live/$DOMAIN/privkey.pem ssl/
    sudo chown -R 1000:1000 ssl/
    
    log_success "SSL 证书配置完成"
}

# 配置 Nginx
setup_nginx() {
    log_info "配置 Nginx..."
    
    # 复制配置文件
    sudo cp "$SCRIPT_DIR/nginx-synapse.conf" /etc/nginx/sites-available/synapse
    
    # 更新域名
    sudo sed -i "s/your-domain.com/$DOMAIN/g" /etc/nginx/sites-available/synapse
    
    # 启用站点
    sudo ln -sf /etc/nginx/sites-available/synapse /etc/nginx/sites-enabled/
    sudo rm -f /etc/nginx/sites-enabled/default
    
    # 获取 SSL 证书
    sudo certbot --nginx -d $DOMAIN --non-interactive --agree-tos --email admin@$DOMAIN
    
    # 测试配置
    sudo nginx -t
    sudo systemctl restart nginx
    
    log_success "Nginx 配置完成"
}

# 创建管理员用户
create_admin_user() {
    log_info "创建管理员用户..."
    
    read -p "管理员用户名: " ADMIN_USER
    if [[ -z "$ADMIN_USER" ]]; then
        log_warning "跳过创建管理员用户"
        return
    fi
    
    if [[ "$DEPLOY_METHOD" == "docker" ]]; then
        cd /opt/synapse
        docker-compose exec synapse register_new_matrix_user -c /data/homeserver.yaml http://localhost:8008 -u $ADMIN_USER -a
    else
        sudo -u synapse /opt/synapse/venv/bin/register_new_matrix_user -c /etc/synapse/homeserver.yaml http://localhost:8008 -u $ADMIN_USER -a
    fi
    
    log_success "管理员用户创建完成"
}

# 显示部署信息
show_deployment_info() {
    echo
    log_success "=== 部署完成 ==="
    echo
    log_info "服务器信息:"
    echo "  域名: https://$DOMAIN"
    echo "  Matrix 客户端: https://$DOMAIN"
    echo "  Federation: https://$DOMAIN:8448"
    echo
    log_info "管理命令:"
    if [[ "$DEPLOY_METHOD" == "docker" ]]; then
        echo "  查看日志: cd /opt/synapse && docker-compose logs -f"
        echo "  重启服务: cd /opt/synapse && docker-compose restart"
        echo "  停止服务: cd /opt/synapse && docker-compose down"
    else
        echo "  查看日志: sudo journalctl -u synapse -f"
        echo "  重启服务: sudo systemctl restart synapse"
        echo "  停止服务: sudo systemctl stop synapse"
    fi
    echo
    log_info "测试连接:"
    echo "  curl https://$DOMAIN/_matrix/client/versions"
    echo
    log_warning "请保存好以下密钥信息:"
    echo "  PostgreSQL 密码: $POSTGRES_PASSWORD"
    echo "  Redis 密码: $REDIS_PASSWORD"
    echo "  注册密钥: $REGISTRATION_SECRET"
    echo
}

# 主函数
main() {
    echo "=== Synapse Matrix 服务器部署脚本 ==="
    echo
    
    check_root
    check_system
    get_user_input
    update_system
    setup_firewall
    
    if [[ "$DEPLOY_METHOD" == "docker" ]]; then
        deploy_docker
    else
        deploy_native
    fi
    
    create_admin_user
    show_deployment_info
    
    log_success "部署完成！请访问 https://$DOMAIN 测试服务"
}

# 运行主函数
main "$@"