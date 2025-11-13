#!/bin/bash

# Build script for Docker Compose deployment
set -e

echo "=========================================="
echo "Building MVD for Docker Compose"
echo "=========================================="

# Clean and build all modules
echo "Building Java artifacts..."
./gradlew clean build -x test

echo ""
echo "=========================================="
echo "Build completed successfully!"
echo "=========================================="
echo ""
echo "JAR files created:"
find launchers -name "*.jar" -type f

echo ""
echo "Next steps:"
echo "1. Run: docker-compose build"
echo "2. Run: docker-compose up -d"
echo "3. Run: ./seed-docker.sh (to seed the dataspace)"
