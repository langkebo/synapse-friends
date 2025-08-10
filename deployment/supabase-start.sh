#!/bin/bash

# Synapse Matrix 服务器启动脚本 - Supabase 版本
# 包含数据库初始化和好友功能配置

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
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

# 检查必要的环境变量
check_env_vars() {
    local required_vars=(
        "SYNAPSE_SERVER_NAME"
        "SUPABASE_DB_HOST"
        "SUPABASE_DB_USER"
        "SUPABASE_DB_PASSWORD"
        "SUPABASE_DB_NAME"
        "REGISTRATION_SHARED_SECRET"
        "MACAROON_SECRET_KEY"
        "FORM_SECRET"
    )
    
    for var in "${required_vars[@]}"; do
        if [[ -z "${!var}" ]]; then
            log_error "环境变量 $var 未设置"
            exit 1
        fi
    done
    
    log_success "环境变量检查通过"
}

# 等待数据库连接
wait_for_db() {
    log_info "等待 Supabase 数据库连接..."
    
    local max_attempts=30
    local attempt=1
    
    while [[ $attempt -le $max_attempts ]]; do
        if python3 -c "
import psycopg2
try:
    conn = psycopg2.connect(
        host='$SUPABASE_DB_HOST',
        port='${SUPABASE_DB_PORT:-5432}',
        user='$SUPABASE_DB_USER',
        password='$SUPABASE_DB_PASSWORD',
        database='$SUPABASE_DB_NAME',
        sslmode='require'
    )
    conn.close()
    print('数据库连接成功')
except Exception as e:
    print(f'数据库连接失败: {e}')
    exit(1)
" 2>/dev/null; then
            log_success "数据库连接成功"
            return 0
        fi
        
        log_warning "数据库连接失败，重试 $attempt/$max_attempts"
        sleep 5
        ((attempt++))
    done
    
    log_error "无法连接到 Supabase 数据库"
    exit 1
}

# 生成配置文件
generate_config() {
    log_info "生成 Synapse 配置文件..."
    
    # 替换环境变量
    envsubst < /config/homeserver.yaml.template > /data/homeserver.yaml
    
    # 复制日志配置
    cp /config/log.config /data/log.config
    
    log_success "配置文件生成完成"
}

# 生成签名密钥
generate_keys() {
    if [[ ! -f "/data/signing.key" ]]; then
        log_info "生成签名密钥..."
        python3 -m synapse.app.homeserver \
            --config-path /data/homeserver.yaml \
            --generate-keys
        log_success "签名密钥生成完成"
    else
        log_info "签名密钥已存在，跳过生成"
    fi
}

# 运行数据库迁移
run_migrations() {
    log_info "运行数据库迁移..."
    
    python3 -m synapse.app.homeserver \
        --config-path /data/homeserver.yaml \
        --run-migrations
    
    log_success "数据库迁移完成"
}

# 创建必要目录
create_directories() {
    log_info "创建必要目录..."
    
    mkdir -p /data/media_store
    mkdir -p /logs
    
    # 确保权限正确
    chown -R synapse:synapse /data /logs 2>/dev/null || true
    
    log_success "目录创建完成"
}

# 健康检查
health_check() {
    log_info "启动健康检查..."
    
    # 等待服务启动
    sleep 10
    
    local max_attempts=12
    local attempt=1
    
    while [[ $attempt -le $max_attempts ]]; do
        if curl -f http://localhost:8008/health >/dev/null 2>&1; then
            log_success "Synapse 服务健康检查通过"
            return 0
        fi
        
        log_warning "健康检查失败，重试 $attempt/$max_attempts"
        sleep 5
        ((attempt++))
    done
    
    log_error "Synapse 服务健康检查失败"
    return 1
}

# 启动 Synapse
start_synapse() {
    log_info "启动 Synapse Matrix 服务器..."
    
    # 在后台启动健康检查
    health_check &
    
    # 启动 Synapse
    exec python3 -m synapse.app.homeserver \
        --config-path /data/homeserver.yaml
}

# 信号处理
trap 'log_info "收到停止信号，正在关闭服务..."; exit 0' SIGTERM SIGINT

# 主函数
main() {
    log_info "=== Synapse Matrix 服务器启动 - Supabase 版本 ==="
    
    check_env_vars
    create_directories
    wait_for_db
    generate_config
    generate_keys
    run_migrations
    
    log_success "初始化完成，启动 Synapse 服务器..."
    start_synapse
}

# 运行主函数
main "$@"