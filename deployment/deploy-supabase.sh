#!/bin/bash

# Synapse Matrix 服务器 Supabase 部署脚本
# 自动化部署到 Supabase 环境

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

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

log_step() {
    echo -e "${PURPLE}[STEP]${NC} $1"
}

log_debug() {
    if [[ "$DEBUG" == "true" ]]; then
        echo -e "${CYAN}[DEBUG]${NC} $1"
    fi
}

# 显示横幅
show_banner() {
    echo -e "${PURPLE}"
    echo "═══════════════════════════════════════════════════════════════"
    echo "           Synapse Matrix 服务器 - Supabase 部署脚本"
    echo "                    包含好友管理功能"
    echo "═══════════════════════════════════════════════════════════════"
    echo -e "${NC}"
}

# 检查系统要求
check_requirements() {
    log_step "检查系统要求..."
    
    # 检查 Docker
    if ! command -v docker &> /dev/null; then
        log_error "Docker 未安装，请先安装 Docker"
        exit 1
    fi
    
    # 检查 Docker Compose
    if ! command -v docker-compose &> /dev/null && ! docker compose version &> /dev/null; then
        log_error "Docker Compose 未安装，请先安装 Docker Compose"
        exit 1
    fi
    
    # 检查 curl
    if ! command -v curl &> /dev/null; then
        log_error "curl 未安装，请先安装 curl"
        exit 1
    fi
    
    # 检查 openssl
    if ! command -v openssl &> /dev/null; then
        log_error "openssl 未安装，请先安装 openssl"
        exit 1
    fi
    
    log_success "系统要求检查通过"
}

# 获取用户输入
get_user_input() {
    log_step "收集部署配置信息..."
    
    # 域名配置
    while [[ -z "$DOMAIN" ]]; do
        read -p "请输入你的 Matrix 服务器域名 (例如: matrix.example.com): " DOMAIN
        if [[ -z "$DOMAIN" ]]; then
            log_error "域名不能为空"
        fi
    done
    
    # Supabase 项目信息
    echo
    log_info "请提供 Supabase 项目信息 (可在项目设置 -> 数据库 -> 连接信息中找到):"
    
    while [[ -z "$SUPABASE_DB_HOST" ]]; do
        read -p "Supabase 数据库主机 (例如: db.xxx.supabase.co): " SUPABASE_DB_HOST
    done
    
    while [[ -z "$SUPABASE_DB_PASSWORD" ]]; do
        read -s -p "Supabase 数据库密码: " SUPABASE_DB_PASSWORD
        echo
    done
    
    # 可选配置
    echo
    read -p "是否启用 Redis 缓存? [Y/n]: " ENABLE_REDIS
    ENABLE_REDIS=${ENABLE_REDIS:-Y}
    
    read -p "是否启用用户注册? [y/N]: " ENABLE_REGISTRATION
    ENABLE_REGISTRATION=${ENABLE_REGISTRATION:-N}
    
    read -p "是否部署 Element Web 客户端? [Y/n]: " DEPLOY_ELEMENT
    DEPLOY_ELEMENT=${DEPLOY_ELEMENT:-Y}
    
    read -p "是否启用监控 (Prometheus + Grafana)? [y/N]: " ENABLE_MONITORING
    ENABLE_MONITORING=${ENABLE_MONITORING:-N}
    
    log_success "配置信息收集完成"
}

# 生成密钥
generate_secrets() {
    log_step "生成安全密钥..."
    
    REGISTRATION_SECRET=$(openssl rand -hex 32)
    MACAROON_SECRET=$(openssl rand -hex 32)
    FORM_SECRET=$(openssl rand -hex 32)
    REDIS_PASSWORD=$(openssl rand -hex 16)
    COTURN_SECRET=$(openssl rand -hex 16)
    GRAFANA_PASSWORD=$(openssl rand -hex 8)
    
    log_success "安全密钥生成完成"
}

# 创建环境配置文件
create_env_file() {
    log_step "创建环境配置文件..."
    
    cat > .env << EOF
# Synapse Matrix 服务器配置 - Supabase 版本
# 自动生成于 $(date)

# 基本配置
SYNAPSE_SERVER_NAME=$DOMAIN
REPORT_STATS=no
ENABLE_REGISTRATION=$([ "$ENABLE_REGISTRATION" = "Y" ] || [ "$ENABLE_REGISTRATION" = "y" ] && echo "true" || echo "false")
MAX_UPLOAD_SIZE=50M

# Supabase 项目配置
SUPABASE_URL=https://gomidmecjarcriccnvyc.supabase.co
SUPABASE_ANON_KEY=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImdvbWlkbWVjamFyY3JpY2NudnljIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTQ4MTI4ODYsImV4cCI6MjA3MDM4ODg4Nn0.m-VxIB-wBq7kEZVKstqFt6XWjplpfFuxFd_kIQODHQU
SUPABASE_SERVICE_ROLE_KEY=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImdvbWlkbWVjamFyY3JpY2NudnljIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc1NDgxMjg4NiwiZXhwIjoyMDcwMzg4ODg2fQ.TLW1aNMYC34Q9EL3nWHCbpqPz7fNH8IHVvW2taSz5J8

# Supabase 数据库配置
SUPABASE_DB_HOST=$SUPABASE_DB_HOST
SUPABASE_DB_PORT=5432
SUPABASE_DB_USER=postgres
SUPABASE_DB_PASSWORD=$SUPABASE_DB_PASSWORD
SUPABASE_DB_NAME=postgres

# Redis 配置
REDIS_ENABLED=$([ "$ENABLE_REDIS" = "Y" ] || [ "$ENABLE_REDIS" = "y" ] && echo "true" || echo "false")
REDIS_HOST=redis
REDIS_PORT=6379
REDIS_PASSWORD=$REDIS_PASSWORD

# 安全密钥
REGISTRATION_SHARED_SECRET=$REGISTRATION_SECRET
MACARRON_SECRET_KEY=$MACAROON_SECRET
FORM_SECRET=$FORM_SECRET

# 好友功能配置
FRIENDS_ENABLED=true
MAX_FRIENDS_PER_USER=1000
FRIEND_REQUEST_TIMEOUT=604800
ALLOW_CROSS_DOMAIN_FRIENDS=true

# 性能配置
CACHE_FACTOR=0.5

# Coturn 配置
COTURN_MIN_PORT=49152
COTURN_MAX_PORT=65535
COTURN_STATIC_AUTH_SECRET=$COTURN_SECRET
COTURN_REALM=$DOMAIN

# 监控配置
PROMETHEUS_PORT=9090
GRAFANA_PORT=3000
GRAFANA_ADMIN_PASSWORD=$GRAFANA_PASSWORD

# Element Web 配置
ELEMENT_WEB_VERSION=latest
ELEMENT_DEFAULT_SERVER=https://$DOMAIN

# 其他配置
TZ=Asia/Shanghai
LOG_LEVEL=INFO
DEBUG=false
EOF
    
    log_success "环境配置文件创建完成"
}

# 创建必要目录
create_directories() {
    log_step "创建必要目录..."
    
    mkdir -p data logs ssl
    chmod 755 data logs ssl
    
    log_success "目录创建完成"
}

# 创建 Element Web 配置
create_element_config() {
    if [[ "$DEPLOY_ELEMENT" = "Y" ]] || [[ "$DEPLOY_ELEMENT" = "y" ]]; then
        log_step "创建 Element Web 配置..."
        
        cat > element-config.json << EOF
{
    "default_server_config": {
        "m.homeserver": {
            "base_url": "https://$DOMAIN",
            "server_name": "$DOMAIN"
        },
        "m.identity_server": {
            "base_url": "https://vector.im"
        }
    },
    "disable_custom_urls": false,
    "disable_guests": true,
    "disable_login_language_selector": false,
    "disable_3pid_login": false,
    "brand": "Element",
    "integrations_ui_url": "https://scalar.vector.im/",
    "integrations_rest_url": "https://scalar.vector.im/api",
    "integrations_widgets_urls": [
        "https://scalar.vector.im/_matrix/integrations/v1",
        "https://scalar.vector.im/api",
        "https://scalar-staging.vector.im/_matrix/integrations/v1",
        "https://scalar-staging.vector.im/api",
        "https://scalar-staging.riot.im/scalar/api"
    ],
    "bug_report_endpoint_url": "https://element.io/bugreports/submit",
    "defaultCountryCode": "CN",
    "showLabsSettings": true,
    "features": {
        "feature_new_spinner": true,
        "feature_pinning": true,
        "feature_custom_status": true,
        "feature_custom_tags": true,
        "feature_state_counters": true
    },
    "default_federate": true,
    "default_theme": "light",
    "roomDirectory": {
        "servers": [
            "$DOMAIN",
            "matrix.org"
        ]
    }
}
EOF
        
        log_success "Element Web 配置创建完成"
    fi
}

# 测试 Supabase 连接
test_supabase_connection() {
    log_step "测试 Supabase 数据库连接..."
    
    # 使用 Docker 临时容器测试连接
    if docker run --rm postgres:13 psql "postgresql://postgres:$SUPABASE_DB_PASSWORD@$SUPABASE_DB_HOST:5432/postgres?sslmode=require" -c "SELECT version();" > /dev/null 2>&1; then
        log_success "Supabase 数据库连接测试成功"
    else
        log_error "Supabase 数据库连接测试失败，请检查连接信息"
        exit 1
    fi
}

# 应用数据库迁移
apply_database_migrations() {
    log_step "应用数据库迁移..."
    
    # 检查迁移文件是否存在
    if [[ -d "supabase/migrations" ]]; then
        for migration_file in supabase/migrations/*.sql; do
            if [[ -f "$migration_file" ]]; then
                log_info "应用迁移: $(basename "$migration_file")"
                docker run --rm postgres:13 psql "postgresql://postgres:$SUPABASE_DB_PASSWORD@$SUPABASE_DB_HOST:5432/postgres?sslmode=require" -f "$migration_file"
                if [[ $? -eq 0 ]]; then
                    log_success "迁移应用成功: $(basename "$migration_file")"
                else
                    log_warning "迁移应用失败或已存在: $(basename "$migration_file")"
                fi
            fi
        done
    else
        log_warning "未找到数据库迁移文件"
    fi
    
    log_success "数据库迁移完成"
}

# 构建 Docker 镜像
build_docker_image() {
    log_step "构建 Synapse Docker 镜像..."
    
    docker build -f deployment/Dockerfile.supabase -t synapse-supabase:latest .
    
    log_success "Docker 镜像构建完成"
}

# 启动服务
start_services() {
    log_step "启动 Synapse 服务..."
    
    # 构建 Docker Compose 命令
    COMPOSE_CMD="docker-compose -f deployment/docker-compose.supabase.yml"
    
    # 添加可选服务
    PROFILES=""
    
    if [[ "$DEPLOY_ELEMENT" = "Y" ]] || [[ "$DEPLOY_ELEMENT" = "y" ]]; then
        PROFILES="$PROFILES --profile element"
    fi
    
    if [[ "$ENABLE_MONITORING" = "Y" ]] || [[ "$ENABLE_MONITORING" = "y" ]]; then
        PROFILES="$PROFILES --profile monitoring"
    fi
    
    # 启动服务
    $COMPOSE_CMD $PROFILES up -d
    
    log_success "服务启动完成"
}

# 等待服务就绪
wait_for_services() {
    log_step "等待服务启动..."
    
    local max_attempts=60
    local attempt=1
    
    while [[ $attempt -le $max_attempts ]]; do
        if curl -f http://localhost:8008/health > /dev/null 2>&1; then
            log_success "Synapse 服务已就绪"
            return 0
        fi
        
        log_info "等待服务启动... ($attempt/$max_attempts)"
        sleep 5
        ((attempt++))
    done
    
    log_error "服务启动超时"
    return 1
}

# 创建管理员用户
create_admin_user() {
    log_step "创建管理员用户..."
    
    read -p "请输入管理员用户名: " ADMIN_USERNAME
    if [[ -z "$ADMIN_USERNAME" ]]; then
        log_warning "跳过创建管理员用户"
        return
    fi
    
    read -s -p "请输入管理员密码: " ADMIN_PASSWORD
    echo
    
    if [[ -z "$ADMIN_PASSWORD" ]]; then
        log_warning "跳过创建管理员用户"
        return
    fi
    
    # 创建管理员用户
    docker-compose -f deployment/docker-compose.supabase.yml exec synapse \
        register_new_matrix_user -c /data/homeserver.yaml http://localhost:8008 \
        -u "$ADMIN_USERNAME" -p "$ADMIN_PASSWORD" -a
    
    log_success "管理员用户创建完成: @$ADMIN_USERNAME:$DOMAIN"
}

# 显示部署信息
show_deployment_info() {
    echo
    log_success "═══════════════════════════════════════════════════════════════"
    log_success "                    部署完成！"
    log_success "═══════════════════════════════════════════════════════════════"
    echo
    
    log_info "服务访问地址:"
    echo "  Matrix 服务器: https://$DOMAIN"
    echo "  健康检查: http://localhost:8008/health"
    
    if [[ "$DEPLOY_ELEMENT" = "Y" ]] || [[ "$DEPLOY_ELEMENT" = "y" ]]; then
        echo "  Element Web: http://localhost:8080"
    fi
    
    if [[ "$ENABLE_MONITORING" = "Y" ]] || [[ "$ENABLE_MONITORING" = "y" ]]; then
        echo "  Prometheus: http://localhost:9090"
        echo "  Grafana: http://localhost:3000 (admin/$GRAFANA_PASSWORD)"
    fi
    
    echo
    log_info "管理命令:"
    echo "  查看日志: docker-compose -f deployment/docker-compose.supabase.yml logs -f"
    echo "  重启服务: docker-compose -f deployment/docker-compose.supabase.yml restart"
    echo "  停止服务: docker-compose -f deployment/docker-compose.supabase.yml down"
    echo "  创建用户: docker-compose -f deployment/docker-compose.supabase.yml exec synapse register_new_matrix_user -c /data/homeserver.yaml http://localhost:8008"
    
    echo
    log_info "重要信息 (请妥善保存):"
    echo "  注册密钥: $REGISTRATION_SECRET"
    echo "  Redis 密码: $REDIS_PASSWORD"
    if [[ "$ENABLE_MONITORING" = "Y" ]] || [[ "$ENABLE_MONITORING" = "y" ]]; then
        echo "  Grafana 密码: $GRAFANA_PASSWORD"
    fi
    
    echo
    log_info "测试好友功能 API:"
    echo "  获取访问令牌: curl -X POST https://$DOMAIN/_matrix/client/r0/login"
    echo "  发送好友请求: curl -X POST https://$DOMAIN/_matrix/client/v1/friends/request"
    echo "  获取好友列表: curl -X GET https://$DOMAIN/_matrix/client/v1/friends"
    
    echo
    log_warning "下一步:"
    echo "  1. 配置域名 DNS 解析指向此服务器"
    echo "  2. 配置 SSL 证书 (Let's Encrypt 或其他)"
    echo "  3. 配置防火墙规则"
    echo "  4. 设置定期备份"
    
    echo
    log_success "═══════════════════════════════════════════════════════════════"
}

# 清理函数
cleanup() {
    if [[ $? -ne 0 ]]; then
        log_error "部署过程中发生错误"
        log_info "清理临时文件..."
        # 这里可以添加清理逻辑
    fi
}

# 设置错误处理
trap cleanup EXIT

# 主函数
main() {
    show_banner
    
    # 解析命令行参数
    while [[ $# -gt 0 ]]; do
        case $1 in
            --debug)
                DEBUG=true
                shift
                ;;
            --domain)
                DOMAIN="$2"
                shift 2
                ;;
            --db-host)
                SUPABASE_DB_HOST="$2"
                shift 2
                ;;
            --db-password)
                SUPABASE_DB_PASSWORD="$2"
                shift 2
                ;;
            --help)
                echo "用法: $0 [选项]"
                echo "选项:"
                echo "  --debug              启用调试模式"
                echo "  --domain DOMAIN      指定域名"
                echo "  --db-host HOST       指定 Supabase 数据库主机"
                echo "  --db-password PASS   指定 Supabase 数据库密码"
                echo "  --help               显示此帮助信息"
                exit 0
                ;;
            *)
                log_error "未知参数: $1"
                exit 1
                ;;
        esac
    done
    
    check_requirements
    get_user_input
    generate_secrets
    create_env_file
    create_directories
    create_element_config
    test_supabase_connection
    apply_database_migrations
    build_docker_image
    start_services
    wait_for_services
    create_admin_user
    show_deployment_info
    
    log_success "Synapse Matrix 服务器部署完成！"
}

# 运行主函数
main "$@"