#!/bin/bash

PROJECT_NAME="storage-test"

echo "=========================================="
echo "RWX Mode Cleanup Script"
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
read -p "⚠️  Delete RWX mode resources (NFS server, deployment, PVCs)? (y/N): " -n 1 -r
echo ""
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Cancelled."
    exit 0
fi
echo ""

# Delete deployment
echo "🗑️  Deleting application deployment..."
oc delete deployment storage-demo-rwx --ignore-not-found=true
echo ""

# Wait for pods to terminate
echo "⏳ Waiting for application pods to terminate..."
sleep 5
echo ""

# Delete client PVC and PV
echo "💾 Deleting NFS client PVC and PV..."
oc delete pvc nfs --ignore-not-found=true
oc delete pv nfs --ignore-not-found=true
echo ""

# Delete NFS server
echo "🗄️  Deleting NFS server..."
oc delete rc nfs-server --ignore-not-found=true
oc delete service nfs-server --ignore-not-found=true
echo ""

# Wait for NFS server to terminate
echo "⏳ Waiting for NFS server to terminate..."
sleep 5
echo ""

# Delete NFS server PVC
echo "💾 Deleting NFS server PVC..."
oc delete pvc nfs-pv-provisioning-demo --ignore-not-found=true
echo ""

# Delete ServiceAccount and SCC binding
echo "🔐 Deleting ServiceAccount and SCC binding..."
oc delete -f openshift/scc-binding.yaml --ignore-not-found=true
oc delete -f openshift/serviceaccount.yaml --ignore-not-found=true
echo ""

echo "✅ RWX mode resources deleted!"
echo ""
echo "📊 Remaining resources:"
oc get all,pvc,pv -l mode=rwx-nfs 2>/dev/null || echo "   All RWX resources cleaned up."
echo ""
