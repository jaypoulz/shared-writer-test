#!/bin/bash

echo "=========================================="
echo "RWO Mode Status Check"
echo "=========================================="
echo ""

# Get pod info
POD=$(oc get pods -l mode=rwo -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)

if [ -z "$POD" ]; then
    echo "❌ No RWO pod found. Is it deployed?"
    echo ""
    echo "Deploy with: ./deploy-rwo.sh"
    exit 1
fi

echo "📦 Pod Status:"
oc get pods -l mode=rwo -o wide
echo ""

echo "📊 Pod Details:"
oc describe pod $POD | grep -A 5 "Containers:"
echo ""

echo "📝 Recent Writer Logs (last 20 lines):"
echo "---"
oc logs $POD -c writer --tail=20
echo ""

echo "📝 Recent Reader Logs (last 20 lines):"
echo "---"
oc logs $POD -c reader --tail=20
echo ""

echo "💾 Storage File Content:"
echo "---"
if oc exec $POD -c writer -- test -f /mnt/shared/output.txt 2>/dev/null; then
    oc exec $POD -c writer -- cat /mnt/shared/output.txt
    echo ""
    echo "✅ File exists and contains $(oc exec $POD -c writer -- wc -l /mnt/shared/output.txt 2>/dev/null | awk '{print $1}') lines"
else
    echo "⚠️  File /mnt/shared/output.txt not found yet"
fi
echo ""

echo "=========================================="
echo "Commands for real-time monitoring:"
echo "=========================================="
echo ""
echo "  Follow writer logs:"
echo "    oc logs -f $POD -c writer"
echo ""
echo "  Follow reader logs:"
echo "    oc logs -f $POD -c reader"
echo ""
echo "  Watch file updates:"
echo "    oc exec $POD -c writer -- tail -f /mnt/shared/output.txt"
echo ""
