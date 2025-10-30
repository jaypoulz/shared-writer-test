#!/bin/bash

PROJECT_NAME="storage-test"

echo "=========================================="
echo "RWO Mode Cleanup Script"
echo "=========================================="
echo ""

# Switch to project
echo "📦 Switching to project: $PROJECT_NAME"
if ! oc project $PROJECT_NAME &>/dev/null; then
    echo "   ⚠️  Project $PROJECT_NAME does not exist or you don't have access to it."
    echo "   Nothing to clean up."
    exit 0
fi
echo ""

# Ask for confirmation
read -p "⚠️  Delete RWO mode resources (deployment, PVC)? (y/N): " -n 1 -r
echo ""
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Cancelled."
    exit 0
fi
echo ""

# Delete deployment
echo "🗑️  Deleting RWO deployment..."
oc delete deployment storage-demo-rwo --ignore-not-found=true
echo ""

# Wait a moment for pods to terminate
echo "⏳ Waiting for pods to terminate..."
sleep 5
echo ""

# Delete PVC
echo "💾 Deleting PersistentVolumeClaim..."
oc delete pvc linstor-shared-storage-rwo --ignore-not-found=true
echo ""

# Delete ServiceAccount and SCC binding
echo "🔐 Deleting ServiceAccount and SCC binding..."
oc delete -f openshift/scc-binding.yaml --ignore-not-found=true
oc delete -f openshift/serviceaccount.yaml --ignore-not-found=true
echo ""

echo "✅ RWO mode resources deleted!"
echo ""
echo "📊 Remaining resources:"
oc get all,pvc -l mode=rwo 2>/dev/null || echo "   All RWO resources cleaned up."
echo ""
