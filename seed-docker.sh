#!/bin/bash

# Seed script for Docker Compose deployment
set -e

echo "=========================================="
echo "Seeding MVD Dataspace (Docker Compose)"
echo "=========================================="

# Wait for services to be ready
echo "Waiting for services to be healthy..."
sleep 30

# TODO: Add seeding logic here
# This should include:
# 1. Creating assets in provider connectors
# 2. Creating policies
# 3. Seeding credentials to IdentityHubs
# 4. Creating catalog assets in catalog server

echo ""
echo "=========================================="
echo "Dataspace seeding completed!"
echo "=========================================="
echo ""
echo "Service endpoints:"
echo "- Consumer Connector Management API: http://localhost:8081/api/management/"
echo "- Provider QnA Connector Management API: http://localhost:8191/api/management/"
echo "- Provider Manufacturing Connector Management API: http://localhost:8291/api/management/"
echo "- Provider Catalog Server Management API: http://localhost:8181/api/management/"
echo ""
echo "Authentication: Use header 'X-Api-Key: password'"
