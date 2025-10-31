# Two-Node Storage Demo - OpenShift/LINSTOR

> ⚠️ **DISCLAIMER**: This application was entirely vibe-coded by an AI. Use at your own risk.

Test LINSTOR storage on OpenShift with two modes: node failover (RWO) and multi-writer (RWX).

📋 **[View Test Results & Known Issues →](TEST_RESULTS.md)**

## Two Test Modes

### RWO Mode: Node Failover Testing
- 1 pod with writer + reader containers
- LINSTOR ReadWriteOnce storage
- Test failover when node fails/reboots

### RWX Mode: Multi-Writer Testing
- 2 pods (each with writer + reader)
- NFS on LINSTOR for ReadWriteMany
- Test concurrent writes from multiple nodes

## Quick Start

### Prerequisites
- OpenShift cluster with LINSTOR installed
- `oc` CLI logged in as cluster admin

### Run Tests (Recommended)

**Unified workflow - handles everything:**
```bash
./run-test.sh
```

This script will:
1. Check for existing deployments and offer cleanup
2. Prompt you to select RWO or RWX mode
3. Deploy the selected mode
4. Run appropriate tests
5. Offer cleanup when done

**RWO Test** - Interactive failover with 3 modes:
- Cordon/Drain - Kubernetes graceful drain
- Shutdown - Graceful VM shutdown (`virsh shutdown`)
- Destroy - Hard VM power-off (`virsh destroy`)

**RWX Test** - Verifies concurrent writes from multiple pods

### Manual Mode (Advanced)

**RWO Mode:**
```bash
./deploy-rwo.sh          # Deploy
./test-node-failover.sh  # Test failover
./check-rwo.sh           # Check status
./delete-rwo.sh          # Clean up
```

**RWX Mode:**
```bash
./deploy-rwx.sh   # Deploy
./check-rwx.sh    # Check status
./delete-rwx.sh   # Clean up
```

## Verification Commands

### RWO Mode
```bash
# Pod status
oc get pods -l mode=rwo -o wide

# Watch logs
oc logs -f -l mode=rwo --all-containers=true

# Read storage file
POD=$(oc get pods -l mode=rwo -o jsonpath='{.items[0].metadata.name}')
oc exec $POD -c writer -- tail -f /mnt/shared/output.txt
```

### RWX Mode
```bash
# Pod status (should be on different nodes)
oc get pods -l mode=rwx-nfs -o wide

# Watch logs from all writers
oc logs -f deployment/storage-demo-rwx -c writer --all-pods=true

# Read storage file (should see multiple writers!)
POD=$(oc get pods -l mode=rwx-nfs -o jsonpath='{.items[0].metadata.name}')
oc exec $POD -c writer -- tail -f /mnt/shared/output.txt
```

## How It Works

**RWO Mode:**
- Writer and reader share one pod with one RWO mount
- LINSTOR/DRBD replicates data to 2 nodes
- On failover, pod migrates and DRBD promotes replica

**RWX Mode:**
- NFS server uses LINSTOR RWO as backing storage
- Multiple pods access via NFS (provides RWX)
- 2 writers write concurrently through NFS

**Security:**
- Uses `privileged` SCC for full SELinux/host access
- `fsGroup: 0` for root group ownership on mounts

## Troubleshooting

### No logs appearing
```bash
# Check pod status
oc get pods -l mode=rwo

# Check container logs individually
POD=$(oc get pods -l mode=rwo -o jsonpath='{.items[0].metadata.name}')
oc logs $POD -c writer
oc logs $POD -c reader

# Read file directly
oc exec $POD -c writer -- cat /mnt/shared/output.txt
```

### Mount failures
```bash
# Check PVC
oc describe pvc linstor-shared-storage-rwo

# Check pod events
oc describe pod -l mode=rwo

# Verify storage class
oc get storageclass linstor-basic-storage-class
```

### Permission denied
```bash
# Verify ServiceAccount has privileged SCC
oc get sa storage-demo-sa
oc get rolebinding storage-demo-privileged

# Check what SCC pod is using
oc get pod -l mode=rwo -o yaml | grep "openshift.io/scc"

# Should be: privileged
```

### Image pull failures during failover
```bash
# Pre-pull image to all nodes (done automatically by deploy script)
./prepull-image.sh
```

### Diagnose permissions issues
```bash
./diagnose-permissions.sh
```

## Comparison

| Feature | RWO Mode | RWX Mode |
|---------|----------|----------|
| Pods | 1 | 2 |
| Storage | LINSTOR RWO | NFS over LINSTOR |
| Concurrent Writes | No | Yes |
| Use Case | Failover testing | Multi-writer testing |
| Performance | Direct (fast) | Via NFS (slower) |

## License

See LICENSE file.
