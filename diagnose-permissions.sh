#!/bin/bash

echo "=========================================="
echo "RWO Storage Permission Diagnostics"
echo "=========================================="
echo ""

POD=$(oc get pods -l mode=rwo -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)

if [ -z "$POD" ]; then
    echo "❌ No RWO pod found. Deploy first with: ./deploy-rwo.sh"
    exit 1
fi

echo "🔍 Pod: $POD"
echo ""

echo "📋 Security Context Check:"
echo "---"
echo "Pod-level securityContext:"
oc get pod $POD -o yaml | grep -A 5 "^  securityContext:"
echo ""

echo "Container securityContext (writer):"
oc get pod $POD -o jsonpath='{.spec.containers[?(@.name=="writer")].securityContext}' | python3 -m json.tool 2>/dev/null || echo "  Not set or error"
echo ""

echo "Container securityContext (reader):"
oc get pod $POD -o jsonpath='{.spec.containers[?(@.name=="reader")].securityContext}' | python3 -m json.tool 2>/dev/null || echo "  Not set or error"
echo ""

echo "🔐 SCC Check:"
echo "---"
echo "Actual SCC used by pod:"
oc get pod $POD -o yaml | grep "openshift.io/scc"
echo ""

echo "ServiceAccount:"
oc get pod $POD -o jsonpath='{.spec.serviceAccountName}'
echo ""
echo ""

echo "SCC Binding:"
oc get rolebinding storage-demo-privileged -o yaml 2>/dev/null | grep -A 3 "subjects:" || echo "  Binding not found!"
echo ""

echo "💾 Volume Mount Check:"
echo "---"
echo "Writer container mounts:"
oc exec $POD -c writer -- mount | grep "/mnt/shared" 2>/dev/null || echo "  Mount not found or error"
echo ""

echo "Mount details:"
oc exec $POD -c writer -- ls -la /mnt/ 2>/dev/null || echo "  Cannot list /mnt/"
echo ""

echo "Permissions on /mnt/shared:"
oc exec $POD -c writer -- ls -lad /mnt/shared 2>/dev/null || echo "  Cannot access /mnt/shared"
echo ""

echo "🧪 Permission Test:"
echo "---"
echo "Testing directory creation:"
oc exec $POD -c writer -- mkdir -p /mnt/shared/test 2>&1
echo ""

echo "Testing file write:"
oc exec $POD -c writer -- sh -c 'echo "test" > /mnt/shared/test.txt' 2>&1
echo ""

echo "Testing file read:"
oc exec $POD -c writer -- cat /mnt/shared/test.txt 2>&1
echo ""

echo "🔬 SELinux Context:"
echo "---"
echo "Process context (writer):"
oc exec $POD -c writer -- id 2>/dev/null || echo "  Cannot get id"
echo ""

echo "SELinux status in container:"
oc exec $POD -c writer -- getenforce 2>/dev/null || echo "  SELinux tools not available"
echo ""

echo "File context on /mnt/shared:"
oc exec $POD -c writer -- ls -Z /mnt/ 2>/dev/null || echo "  Cannot get SELinux context"
echo ""

echo "📊 PVC Details:"
echo "---"
oc get pvc linstor-shared-storage-rwo -o yaml | grep -A 10 "^spec:"
echo ""

echo "=========================================="
echo "Diagnostic Complete"
echo "=========================================="
