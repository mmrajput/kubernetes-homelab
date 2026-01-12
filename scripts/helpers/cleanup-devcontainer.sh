#!/bin/bash
# Safe DevContainer Cleanup Script
# Keeps: Last 2 DevContainer images + Ubuntu 24.04 base
# Removes: Old DevContainer images, stopped containers, build cache

set -e

echo "🧹 DevContainer Cleanup Script"
echo "=============================="
echo ""

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Show current state
echo -e "${BLUE}📊 Current Docker disk usage:${NC}"
docker system df
echo ""

# Step 1: Remove stopped containers
echo -e "${YELLOW}Step 1: Removing stopped containers...${NC}"
STOPPED_CONTAINERS=$(docker ps -a -q -f status=exited 2>/dev/null)
if [ -n "$STOPPED_CONTAINERS" ]; then
    docker rm $STOPPED_CONTAINERS
    echo -e "${GREEN}✓ Removed stopped containers${NC}"
else
    echo -e "${GREEN}✓ No stopped containers to remove${NC}"
fi
echo ""

# Step 2: Identify DevContainer images (keep last 2)
echo -e "${YELLOW}Step 2: Cleaning up old DevContainer images...${NC}"

# Get all DevContainer image IDs sorted by creation date (newest first)
# Pattern matches: vsc-*, devcontainer*, *homelab*
ALL_DEVCONTAINER_IMAGES=$(docker images --format "{{.ID}}|{{.Repository}}|{{.Tag}}|{{.CreatedAt}}" | \
    grep -iE "vsc-|devcontainer|homelab" | \
    sort -t'|' -k4 -r | \
    awk -F'|' '{print $1}')

if [ -z "$ALL_DEVCONTAINER_IMAGES" ]; then
    echo -e "${GREEN}✓ No DevContainer images found${NC}"
else
    # Count total DevContainer images
    TOTAL_IMAGES=$(echo "$ALL_DEVCONTAINER_IMAGES" | wc -l)
    echo "Found $TOTAL_IMAGES DevContainer image(s)"
    
    if [ "$TOTAL_IMAGES" -gt 2 ]; then
        # Keep first 2 (newest), remove the rest
        IMAGES_TO_KEEP=$(echo "$ALL_DEVCONTAINER_IMAGES" | head -n 2)
        IMAGES_TO_REMOVE=$(echo "$ALL_DEVCONTAINER_IMAGES" | tail -n +3)
        
        echo -e "${GREEN}Keeping 2 newest DevContainer images:${NC}"
        echo "$IMAGES_TO_KEEP" | while read image_id; do
            docker images --format "table {{.Repository}}\t{{.Tag}}\t{{.Size}}\t{{.CreatedAt}}" | grep "$image_id" || true
        done
        
        echo ""
        echo -e "${RED}Removing $(echo "$IMAGES_TO_REMOVE" | wc -l) old DevContainer image(s):${NC}"
        echo "$IMAGES_TO_REMOVE" | while read image_id; do
            docker images --format "table {{.Repository}}\t{{.Tag}}\t{{.Size}}\t{{.CreatedAt}}" | grep "$image_id" || true
            docker rmi -f "$image_id" 2>/dev/null || echo "  (Skipped - in use)"
        done
        
        echo -e "${GREEN}✓ Old DevContainer images cleaned up${NC}"
    else
        echo -e "${GREEN}✓ Only $TOTAL_IMAGES DevContainer image(s) - nothing to remove (keeping all)${NC}"
    fi
fi
echo ""

# Step 3: Remove dangling images (except Ubuntu base)
echo -e "${YELLOW}Step 3: Removing dangling images (keeping Ubuntu base)...${NC}"
DANGLING_IMAGES=$(docker images -f "dangling=true" -q 2>/dev/null)
if [ -n "$DANGLING_IMAGES" ]; then
    docker rmi $DANGLING_IMAGES 2>/dev/null || echo "Some dangling images in use, skipped"
    echo -e "${GREEN}✓ Dangling images removed${NC}"
else
    echo -e "${GREEN}✓ No dangling images to remove${NC}"
fi
echo ""

# Step 4: Clean build cache
echo -e "${YELLOW}Step 4: Cleaning build cache...${NC}"
docker builder prune -f > /dev/null 2>&1
echo -e "${GREEN}✓ Build cache cleaned${NC}"
echo ""

# Step 5: Verify Ubuntu base image exists
echo -e "${YELLOW}Step 5: Verifying Ubuntu 24.04 base image...${NC}"
if docker images ubuntu:24.04 --format "{{.Repository}}" | grep -q ubuntu; then
    echo -e "${GREEN}✓ Ubuntu 24.04 base image present${NC}"
    docker images ubuntu:24.04 --format "  Repository: {{.Repository}}\n  Tag: {{.Tag}}\n  Size: {{.Size}}"
else
    echo -e "${RED}⚠ Ubuntu 24.04 base image not found!${NC}"
    echo -e "${YELLOW}Pulling Ubuntu 24.04...${NC}"
    docker pull ubuntu:24.04
    echo -e "${GREEN}✓ Ubuntu 24.04 base image restored${NC}"
fi
echo ""

# Final summary
echo -e "${BLUE}📊 After cleanup:${NC}"
docker system df
echo ""

echo -e "${GREEN}✅ Cleanup complete!${NC}"
echo ""
echo "Summary:"
echo "  ✓ Removed stopped containers"
echo "  ✓ Kept last 2 DevContainer images"
echo "  ✓ Removed dangling images"
echo "  ✓ Cleaned build cache"
echo "  ✓ Verified Ubuntu 24.04 base image"
echo ""
echo -e "${BLUE}Current DevContainer images:${NC}"
docker images | grep -iE "REPOSITORY|vsc-|devcontainer|homelab" || echo "No DevContainer images found"
