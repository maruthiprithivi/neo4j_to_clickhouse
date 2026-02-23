#!/bin/bash
set -e

# GitHub Repository Push Script
# Creates and pushes the Neo4j CDC project to GitHub

GITHUB_USERNAME="${GITHUB_USERNAME:-maruthiprithivi}"
REPO_NAME="neo4j-clickhouse-cdc"

echo "═══════════════════════════════════════════════════════════"
echo "  GitHub Push Script - Neo4j CDC Pipeline"
echo "═══════════════════════════════════════════════════════════"
echo ""
echo "Configuration:"
echo "  GitHub Username: $GITHUB_USERNAME"
echo "  Repository Name: $REPO_NAME"
echo "  Repository URL:  git@github.com:$GITHUB_USERNAME/$REPO_NAME.git"
echo ""

# Change to project directory
cd "$(dirname "$0")"

# Check if remote already exists
if git remote get-url origin &>/dev/null; then
    echo "⚠️  Remote 'origin' already exists:"
    git remote get-url origin
    echo ""
    read -p "Replace it? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        git remote remove origin
    else
        echo "Aborted."
        exit 1
    fi
fi

# Add GitHub remote
echo "📝 Adding GitHub remote..."
git remote add origin "git@github.com:$GITHUB_USERNAME/$REPO_NAME.git"
echo "✅ Remote added"
echo ""

# Check if repository exists on GitHub
echo "🔍 Checking if GitHub repository exists..."
if ssh -T git@github.com 2>&1 | grep -q "successfully authenticated"; then
    if git ls-remote origin &>/dev/null; then
        echo "✅ Repository exists on GitHub"
    else
        echo "❌ Repository does not exist on GitHub"
        echo ""
        echo "Please create the repository first:"
        echo "  1. Go to: https://github.com/new"
        echo "  2. Repository name: $REPO_NAME"
        echo "  3. Description: Production-ready CDC pipeline: Neo4j → Kafka → ClickHouse"
        echo "  4. DO NOT initialize with README"
        echo "  5. Click 'Create repository'"
        echo ""
        read -p "Press Enter after creating the repository..."
    fi
else
    echo "⚠️  Cannot connect to GitHub via SSH"
    echo "Please ensure:"
    echo "  1. SSH key is added to GitHub (https://github.com/settings/keys)"
    echo "  2. SSH agent is running: eval \$(ssh-agent) && ssh-add"
    echo ""
    read -p "Press Enter to continue anyway..."
fi

echo ""
echo "📤 Pushing branches to GitHub..."
echo ""

# Push main branch
echo "Pushing 'main' branch..."
if git push -u origin main; then
    echo "✅ Main branch pushed"
else
    echo "⚠️  Failed to push main branch (may already exist)"
fi

echo ""

# Push feature branch
echo "Pushing 'feature/production-ready-python-consumer' branch..."
if git push -u origin feature/production-ready-python-consumer; then
    echo "✅ Feature branch pushed"
else
    echo "❌ Failed to push feature branch"
    exit 1
fi

echo ""
echo "═══════════════════════════════════════════════════════════"
echo "  ✅ Push Complete!"
echo "═══════════════════════════════════════════════════════════"
echo ""
echo "Repository URL:"
echo "  https://github.com/$GITHUB_USERNAME/$REPO_NAME"
echo ""
echo "Branches:"
echo "  • main:    https://github.com/$GITHUB_USERNAME/$REPO_NAME/tree/main"
echo "  • feature: https://github.com/$GITHUB_USERNAME/$REPO_NAME/tree/feature/production-ready-python-consumer"
echo ""
echo "Next steps:"
echo "  1. View repository: https://github.com/$GITHUB_USERNAME/$REPO_NAME"
echo "  2. Create Pull Request from feature branch to main"
echo "  3. Add topics/tags for discoverability"
echo "  4. Add GitHub Actions for CI/CD (optional)"
echo ""
