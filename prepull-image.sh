#!/bin/bash

set -e

echo "=========================================="
echo "Pre-pull Image to All Nodes"
echo "=========================================="
echo ""

PROJECT_NAME="storage-test"
IMAGE_NAME="storage-demo:latest"
IMAGE_FULL="image-registry.openshift-image-registry.svc:5000/${PROJECT_NAME}/${IMAGE_NAME}"

# Check if we're in the right project
echo "📦 Switching to project: $PROJECT_NAME"
if ! oc project $PROJECT_NAME &>/dev/null; then
    echo "   ⚠️  Project $PROJECT_NAME does not exist."
    echo "   Please deploy first: ./deploy-rwo.sh or ./deploy-rwx.sh"
    exit 1
fi
echo ""

# Check if image exists in registry
echo "🔍 Checking if image exists in registry..."
if ! oc get is storage-demo &>/dev/null; then
    echo "   ⚠️  ImageStream 'storage-demo' not found."
    echo "   Please build the image first by running deploy script."
    exit 1
fi

IMAGE_SHA=$(oc get is storage-demo -o jsonpath='{.status.tags[?(@.tag=="latest")].items[0].dockerImageReference}' 2>/dev/null)
if [ -z "$IMAGE_SHA" ]; then
    echo "   ⚠️  No 'latest' tag found in ImageStream."
    echo "   Please build the image first."
    exit 1
fi

echo "   ✅ Image exists: $IMAGE_SHA"
echo ""

# Create a DaemonSet to pre-pull the image to all nodes
echo "🚀 Creating DaemonSet to pre-pull image to all nodes..."
cat <<EOF | oc apply -f -
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: storage-demo-image-prepull
  labels:
    app: storage-demo-prepull
spec:
  selector:
    matchLabels:
      app: storage-demo-prepull
  template:
    metadata:
      labels:
        app: storage-demo-prepull
    spec:
      serviceAccountName: storage-demo-sa
      initContainers:
      # This container just pulls the image, then exits
      - name: image-prepuller
        image: ${IMAGE_FULL}
        imagePullPolicy: Always
        command: ["sh", "-c", "echo 'Image pulled successfully' && sleep 5"]
      containers:
      # Keep the pod running briefly
      - name: sleeper
        image: ${IMAGE_FULL}
        imagePullPolicy: IfNotPresent
        command: ["sh", "-c", "echo 'Image cached on node' && sleep 30"]
        resources:
          requests:
            memory: "32Mi"
            cpu: "50m"
          limits:
            memory: "64Mi"
            cpu: "100m"
EOF

echo "   ✅ DaemonSet created"
echo ""

# Wait for DaemonSet to complete on all nodes
echo "⏳ Waiting for image to be pulled to all nodes..."
sleep 5

timeout=120
elapsed=0
while [ $elapsed -lt $timeout ]; do
    desired=$(oc get daemonset storage-demo-image-prepull -o jsonpath='{.status.desiredNumberScheduled}' 2>/dev/null || echo "0")
    ready=$(oc get daemonset storage-demo-image-prepull -o jsonpath='{.status.numberReady}' 2>/dev/null || echo "0")

    if [ "$desired" -gt 0 ] && [ "$ready" -eq "$desired" ]; then
        echo "   ✅ Image pulled to all $ready nodes!"
        break
    fi

    echo "   Pulling image to nodes... ($ready/$desired ready)"
    sleep 5
    elapsed=$((elapsed + 5))
done
echo ""

# Show where image was pulled
echo "📊 DaemonSet status:"
oc get daemonset storage-demo-image-prepull
echo ""

echo "📋 Image pulled to these nodes:"
oc get pods -l app=storage-demo-prepull -o wide
echo ""

# Clean up the DaemonSet
echo "🧹 Cleaning up DaemonSet..."
oc delete daemonset storage-demo-image-prepull
echo ""

echo "=========================================="
echo "✅ Image Pre-pull Complete!"
echo "=========================================="
echo ""
echo "The image is now cached on all nodes."
echo "Node failover should work without image pull issues."
echo ""
echo "Run the failover test:"
echo "  ./test-node-failover.sh"
echo ""
