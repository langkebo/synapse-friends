#!/bin/bash

# Synapse Supabase 部署测试脚本
# 验证配置文件和数据库连接

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

echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}           Synapse Supabase 部署配置测试${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo

# 测试1: 检查必要文件是否存在
log_info "测试1: 检查必要文件是否存在..."

files_to_check=(
    "deployment/docker-compose.supabase.yml"
    "deployment/.env.supabase.example"
    "deployment/Dockerfile.supabase"
    "deployment/deploy-supabase.sh"
    "supabase/migrations/001_init_friends_tables.sql"
)

for file in "${files_to_check[@]}"; do
    if [[ -f "$file" ]]; then
        log_success "✓ $file 存在"
    else
        log_error "✗ $file 不存在"
        exit 1
    fi
done

echo

# 测试2: 检查Docker Compose配置
log_info "测试2: 验证Docker Compose配置..."

if command -v docker &> /dev/null; then
    if command -v docker-compose &> /dev/null; then
        if docker-compose -f deployment/docker-compose.supabase.yml config > /dev/null 2>&1; then
            log_success "✓ Docker Compose 配置有效"
        else
            log_error "✗ Docker Compose 配置无效"
            exit 1
        fi
    elif docker compose version &> /dev/null; then
        if docker compose -f deployment/docker-compose.supabase.yml config > /dev/null 2>&1; then
            log_success "✓ Docker Compose 配置有效"
        else
            log_error "✗ Docker Compose 配置无效"
            exit 1
        fi
    else
        log_warning "⚠ Docker Compose 未安装，跳过配置验证"
    fi
else
    log_warning "⚠ Docker 未安装，跳过配置验证"
fi

echo

# 测试3: 检查环境变量模板
log_info "测试3: 检查环境变量模板..."

required_vars=(
    "SUPABASE_URL"
    "SUPABASE_ANON_KEY"
    "SUPABASE_SERVICE_ROLE_KEY"
    "SUPABASE_DB_HOST"
    "FRIENDS_ENABLED"
)

for var in "${required_vars[@]}"; do
    if grep -q "$var" deployment/.env.supabase.example; then
        log_success "✓ $var 在环境变量模板中"
    else
        log_error "✗ $var 不在环境变量模板中"
        exit 1
    fi
done

echo

# 测试4: 检查数据库迁移脚本
log_info "测试4: 验证数据库迁移脚本..."

required_tables=(
    "user_friendships"
    "friend_requests"
    "friend_settings"
)

for table in "${required_tables[@]}"; do
    if grep -q "CREATE TABLE.*$table" supabase/migrations/001_init_friends_tables.sql; then
        log_success "✓ $table 表定义存在"
    else
        log_error "✗ $table 表定义不存在"
        exit 1
    fi
done

echo

# 测试5: 检查部署脚本权限
log_info "测试5: 检查部署脚本权限..."

if [[ -x "deployment/deploy-supabase.sh" ]]; then
    log_success "✓ 部署脚本有执行权限"
else
    log_error "✗ 部署脚本没有执行权限"
    exit 1
fi

echo

# 测试6: 检查Supabase连接（如果提供了数据库密码）
log_info "测试6: 测试Supabase连接..."

if [[ -n "$SUPABASE_DB_PASSWORD" ]]; then
    SUPABASE_DB_HOST="db.gomidmecjarcriccnvyc.supabase.co"
    
    if command -v docker &> /dev/null; then
        if docker run --rm postgres:13 psql "postgresql://postgres:$SUPABASE_DB_PASSWORD@$SUPABASE_DB_HOST:5432/postgres?sslmode=require" -c "SELECT version();" > /dev/null 2>&1; then
            log_success "✓ Supabase 数据库连接成功"
        else
            log_warning "⚠ Supabase 数据库连接失败（可能是密码错误）"
        fi
    else
        log_warning "⚠ Docker 未安装，跳过数据库连接测试"
    fi
else
    log_warning "⚠ 未提供数据库密码，跳过连接测试"
    log_info "要测试数据库连接，请运行: SUPABASE_DB_PASSWORD=your_password $0"
fi

echo

# 测试7: 检查Friends功能代码
log_info "测试7: 检查Friends功能代码..."

friends_files=(
    "synapse/handlers/friends.py"
    "synapse/rest/client/friends.py"
    "synapse/storage/databases/main/friends.py"
)

for file in "${friends_files[@]}"; do
    if [[ -f "$file" ]]; then
        log_success "✓ $file 存在"
    else
        log_error "✗ $file 不存在"
        exit 1
    fi
done

echo

# 总结
log_success "═══════════════════════════════════════════════════════════════"
log_success "                    所有测试通过！"
log_success "═══════════════════════════════════════════════════════════════"
echo
log_info "部署配置验证完成。你可以使用以下命令开始部署："
echo "  cd deployment"
echo "  ./deploy-supabase.sh"
echo
log_info "或者手动部署："
echo "  1. 复制 .env.supabase.example 为 .env 并填写配置"
echo "  2. 运行: docker-compose -f docker-compose.supabase.yml up -d"
echo
log_warning "注意：部署前请确保："
echo "  - 已正确配置域名DNS解析"
echo "  - 已获取有效的SSL证书"
echo "  - 已配置防火墙规则"
echo "  - 已设置Supabase数据库密码"
echo