#!/bin/bash

echo "=========================================="
echo "RWX Mode Status Check"
echo "=========================================="
echo ""

# Get pod info
PODS=$(oc get pods -l mode=rwx-nfs -o jsonpath='{.items[*].metadata.name}' 2>/dev/null)

if [ -z "$PODS" ]; then
    echo "❌ No RWX pods found. Is it deployed?"
    echo ""
    echo "Deploy with: ./deploy-rwx.sh"
    exit 1
fi

# Get first pod for storage checks
POD=$(echo $PODS | awk '{print $1}')

echo "📦 NFS Server:"
oc get pods -l role=nfs-server -o wide
echo ""

echo "📦 Application Pods:"
oc get pods -l mode=rwx-nfs -o wide
echo ""

echo "📝 Recent Writer Logs (from all pods, last 10 lines each):"
echo "---"
for pod in $PODS; do
    echo "Pod: $pod"
    oc logs $pod -c writer --tail=10 2>/dev/null || echo "  (no logs yet)"
    echo ""
done

echo "📝 Recent Reader Logs (from all pods, last 10 lines each):"
echo "---"
for pod in $PODS; do
    echo "Pod: $pod"
    oc logs $pod -c reader --tail=10 2>/dev/null || echo "  (no logs yet)"
    echo ""
done

echo "💾 Storage File Content:"
echo "---"
if oc exec $POD -c writer -- test -f /mnt/shared/output.txt 2>/dev/null; then
    oc exec $POD -c writer -- cat /mnt/shared/output.txt
    echo ""
    LINES=$(oc exec $POD -c writer -- wc -l /mnt/shared/output.txt 2>/dev/null | awk '{print $1}')
    UNIQUE_PODS=$(oc exec $POD -c writer -- cat /mnt/shared/output.txt 2>/dev/null | grep -o 'Pod: [^|]*' | sort -u | wc -l)
    echo "✅ File exists with $LINES lines from $UNIQUE_PODS different pod(s)"
else
    echo "⚠️  File /mnt/shared/output.txt not found yet"
fi
echo ""

echo "=========================================="
echo "Commands for real-time monitoring:"
echo "=========================================="
echo ""
echo "  Follow all writer logs:"
echo "    oc logs -f deployment/storage-demo-rwx -c writer --all-pods=true"
echo ""
echo "  Follow all reader logs:"
echo "    oc logs -f deployment/storage-demo-rwx -c reader --all-pods=true"
echo ""
echo "  Watch file updates (you should see writes from multiple pods!):"
echo "    oc exec $POD -c writer -- tail -f /mnt/shared/output.txt"
echo ""
