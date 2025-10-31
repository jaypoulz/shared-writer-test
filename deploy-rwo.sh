#!/bin/bash

set -e

PROJECT_NAME="storage-test"
MODE="RWO (ReadWriteOnce - Node Failover Test)"

echo "=========================================="
echo "Storage Test Deployment - $MODE"
echo "=========================================="
echo ""
echo "This mode deploys:"
echo "  - 1 Pod with writer + reader containers (ReadWriteOnce)"
echo "  - Both containers share the same RWO volume mount"
echo "  - Tests node failover/disruption"
echo ""

# Check if storage class exists
echo "🔍 Checking for storage class..."
if ! oc get storageclass linstor-basic-storage-class &>/dev/null; then
    echo "   ⚠️  StorageClass 'linstor-basic-storage-class' not found."
    echo ""
    read -p "   Do you want to create it now? (requires cluster-admin) (y/N): " -n 1 -r
    echo ""
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo "   Creating StorageClass and LinstorSatelliteConfiguration..."
        oc apply -f openshift/satellite-config.yaml
        oc apply -f openshift/storageclass.yaml
        echo "   ✅ Storage resources created"
    else
        echo "   ⚠️  Continuing without creating storage class."
        echo "   Note: PVC creation may fail if the storage class doesn't exist."
    fi
else
    echo "   ✅ StorageClass already exists"
fi
echo ""

# Create project if it doesn't exist
echo "📦 Creating/switching to project: $PROJECT_NAME"
if oc get project $PROJECT_NAME &>/dev/null; then
    echo "   Project already exists, switching to it..."
    oc project $PROJECT_NAME
else
    echo "   Creating new project..."
    oc new-project $PROJECT_NAME
fi
echo ""

# Create ImageStream
echo "🖼️  Creating ImageStream..."
oc apply -f openshift/imagestream.yaml
echo ""

# Create BuildConfig or use binary build
if [ -f openshift/buildconfig.yaml ]; then
    echo "🔨 Creating BuildConfig..."
    oc apply -f openshift/buildconfig.yaml
    echo "   Starting build from Git repository..."
    oc start-build storage-demo --follow
else
    echo "🔨 Creating binary build..."
    if ! oc get bc storage-demo &>/dev/null; then
        oc new-build --name storage-demo --binary --strategy docker
    fi
    echo "   Starting build from local directory..."
    oc start-build storage-demo --from-dir=. --follow
fi
echo ""

# Create ServiceAccount and grant privileged SCC
echo "👤 Creating ServiceAccount..."
oc apply -f openshift/serviceaccount.yaml
echo ""

echo "🔐 Granting privileged SCC to ServiceAccount (for SELinux/host access)..."
oc apply -f openshift/scc-binding.yaml
echo ""

# Create PVC
echo "💾 Creating PersistentVolumeClaim..."
oc apply -f openshift/rwo/pvc.yaml
echo ""

# Pre-pull image to all nodes
echo "📥 Pre-pulling image to all nodes for failover support..."
echo ""

# Get image reference
IMAGE_SHA=$(oc get is storage-demo -o jsonpath='{.status.tags[?(@.tag=="latest")].items[0].dockerImageReference}' 2>/dev/null)
if [ -z "$IMAGE_SHA" ]; then
    echo "   ⚠️  Warning: Could not get image reference. Skipping pre-pull."
else
    echo "   Image: $IMAGE_SHA"

    # Create temporary DaemonSet to pull image to all nodes
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
      - name: image-prepuller
        image: image-registry.openshift-image-registry.svc:5000/storage-test/storage-demo:latest
        imagePullPolicy: Always
        command: ["sh", "-c", "echo 'Image pulled to node' && sleep 2"]
        resources:
          requests:
            memory: "32Mi"
            cpu: "50m"
          limits:
            memory: "64Mi"
            cpu: "100m"
      containers:
      - name: sleeper
        image: image-registry.openshift-image-registry.svc:5000/storage-test/storage-demo:latest
        imagePullPolicy: IfNotPresent
        command: ["sh", "-c", "echo 'Image cached' && sleep 10"]
        resources:
          requests:
            memory: "32Mi"
            cpu: "50m"
          limits:
            memory: "64Mi"
            cpu: "100m"
EOF

    # Wait for image to be pulled to all nodes
    echo "   Waiting for image to be cached on all nodes..."
    sleep 5

    timeout=90
    elapsed=0
    while [ $elapsed -lt $timeout ]; do
        desired=$(oc get daemonset storage-demo-image-prepull -o jsonpath='{.status.desiredNumberScheduled}' 2>/dev/null || echo "0")
        ready=$(oc get daemonset storage-demo-image-prepull -o jsonpath='{.status.numberReady}' 2>/dev/null || echo "0")

        if [ "$desired" -gt 0 ] && [ "$ready" -eq "$desired" ]; then
            echo "   ✅ Image cached on all $ready nodes"
            break
        fi

        if [ "$elapsed" -gt 0 ]; then
            echo "   Caching image... ($ready/$desired nodes ready)"
        fi
        sleep 5
        elapsed=$((elapsed + 5))
    done

    # Clean up DaemonSet
    oc delete daemonset storage-demo-image-prepull --ignore-not-found=true >/dev/null 2>&1
fi
echo ""

# Deploy combined writer+reader pod
echo "🚀 Deploying pod (writer + reader containers)..."
oc apply -f openshift/rwo/deployment.yaml
echo ""

# Wait for deployment to be ready
echo "⏳ Waiting for pod to be ready..."
oc rollout status deployment/storage-demo-rwo --timeout=120s || true
echo ""

# Display status
echo "=========================================="
echo "✅ RWO Deployment Complete!"
echo "=========================================="
echo ""
echo "📊 Current Status:"
echo ""
oc get pods -l mode=rwo -o wide
echo ""
echo "💾 Storage:"
oc get pvc linstor-shared-storage-rwo
echo ""
echo "🧪 Node Failover Testing:"
echo ""
echo "  Test node failover:"
echo "    ./test-node-failover.sh"
echo ""
echo "📝 View Logs:"
echo ""
echo "  Writer: oc logs -f deployment/storage-demo-rwo -c writer"
echo "  Reader: oc logs -f deployment/storage-demo-rwo -c reader"
echo "  Both:   oc logs -f -l mode=rwo --all-containers=true"
echo ""
echo "🔍 Verify Storage Content:"
echo ""
echo "  Read the file directly from storage:"
echo "    POD=\$(oc get pods -l mode=rwo -o jsonpath='{.items[0].metadata.name}')"
echo "    oc exec \$POD -c writer -- cat /mnt/shared/output.txt"
echo ""
echo "  Watch file in real-time:"
echo "    oc exec \$POD -c writer -- tail -f /mnt/shared/output.txt"
echo ""
echo "  Clean up: ./delete-rwo.sh"
echo ""
