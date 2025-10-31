# Test Results - LINSTOR Storage on OpenShift

This document tracks test results for the two-node storage demo.

## Test Environment

- **Storage Backend**: DRBD
- **Test Date**: October 31, 2025

---

## RWO Mode: Node Failover Tests

### Test 1: Cordon/Drain Mode

**Status**: ✅ PASS

**Description**: Kubernetes native graceful drain of node, pods migrate cleanly.

**Expected Behavior**:
- Node is cordoned (marked unschedulable)
- Pods are gracefully evicted
- LINSTOR releases volume on old node
- Pod reschedules on new node
- Volume mounts successfully on new node
- Writer continues writing with new node name

**Result**:
```
Test passes successfully. Pod migrates cleanly, volume remounts on new node,
and writes continue without interruption.
```

---

### Test 2: Graceful Shutdown Mode

**Status**: ❌ FAIL

**Description**: Graceful VM shutdown without draining workloads first.

**Expected Behavior**:
- Node powers down gracefully
- LINSTOR detects node failure
- LINSTOR promotes replica on surviving node
- Pod reschedules and mounts volume on new node

**Actual Behavior**:
Volume fails to mount on new node with the following error:

```
Events:
  Normal   Scheduled               2m43s               default-scheduler        Successfully assigned storage-test/storage-demo-rwo-756bc6c68b-5nzfs to master-1
  Warning  FailedAttachVolume      2m44s               attachdetach-controller  Multi-Attach error for volume "pvc-4affbfd7-9e7b-4fa0-97db-57d21f6874cc" Volume is already exclusively attached to one node and can't be attached to another
  Normal   SuccessfulAttachVolume  104s                attachdetach-controller  AttachVolume.Attach succeeded for volume "pvc-4affbfd7-9e7b-4fa0-97db-57d21f6874cc"
  Warning  FailedMount             37s (x8 over 104s)  kubelet                  MountVolume.SetUp failed for volume "pvc-4affbfd7-9e7b-4fa0-97db-57d21f6874cc" : rpc error: code = Internal desc = NodePublishVolume failed for pvc-4affbfd7-9e7b-4fa0-97db-57d21f6874cc: mount failed: exit status 32
Mounting command: mount
Mounting arguments: -w-w -t xfs -o _netdev,nouuid /dev/drbd1000 /var/lib/kubelet/pods/44ea0d50-38d1-4d97-8c29-ee78dedd1061/volumes/kubernetes.io~csi/pvc-4affbfd7-9e7b-4fa0-97db-57d21f6874cc/mount
Output: mount: /var/lib/kubelet/pods/44ea0d50-38d1-4d97-8c29-ee78dedd1061/volumes/kubernetes.io~csi/pvc-4affbfd7-9e7b-4fa0-97db-57d21f6874cc/mount: /dev/drbd1000 is write-protected but explicit read-write mode requested.
```

**Root Cause**:
When the node is gracefully shutdown without draining first, the old pod doesn't terminate cleanly. LINSTOR/DRBD doesn't release the volume mount from the old node, leaving it in a write-protected state. The new pod cannot acquire read-write access.

**Additional Impact**:
The shutdown test left the storage pool on the shutdown node in an error state, preventing any further provisioning:

```
$ kubectl-linstor storage-pool list
╭─────────────────────────────────────────────────────────────────────────────────────────────────╮
┊ StoragePool          ┊ Node     ┊ Driver   ┊ PoolName     ┊ FreeCapacity ┊ TotalCapacity ┊ State ┊
╞═════════════════════════════════════════════════════════════════════════════════════════════════╡
┊ vg1-thin             ┊ master-0 ┊ LVM_THIN ┊ vg1/vg1-thin ┊        0 KiB ┊         0 KiB ┊ Error ┊
┊ vg1-thin             ┊ master-1 ┊ LVM_THIN ┊ vg1/vg1-thin ┊    59.88 GiB ┊     59.88 GiB ┊ Ok    ┊
╰─────────────────────────────────────────────────────────────────────────────────────────────────╯

ERROR:
Description:
    Node: 'master-0', storage pool: 'vg1-thin' - Failed to query free space from storage pool
```

The storage pool requires manual intervention or node restart to recover.

**Workaround**:
- Use "Cordon/Drain" mode instead, which properly migrates workloads before shutdown

---

### Test 3: Destroy Mode (Hard Power-Off)

**Status**: ⏳ NOT TESTED

**Description**: Hard VM power-off simulating catastrophic hardware failure.

**Expected Behavior**:
- VM is hard powered-off (like pulling power cable)
- Autostart is disabled to prevent automatic recovery
- Node becomes NotReady
- LINSTOR detects node failure and promotes replica
- Pod reschedules on surviving node
- Volume mounts successfully on new node

**Result**:
```
Not yet tested
```

---

## RWX Mode: Multi-Writer Tests

> ⚠️ **WARNING**: RWX mode is an UNTESTED PROTOTYPE. This configuration has not been validated.

### Test 4: Concurrent Writes

**Status**: ⏳ NOT TESTED

**Description**: Two pods on different nodes writing concurrently via NFS.

**Expected Behavior**:
- NFS server runs on one node with LINSTOR-backed storage
- Two application pods spread across different nodes
- Both pods write to shared NFS mount concurrently
- File shows entries from both pods interleaved
- No corruption or lock issues

**Result**:
```
Not yet tested
```

---

## Test Configuration

### StorageClass
```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: linstor-basic-storage-class
provisioner: linstor.csi.linbit.com
parameters:
  autoPlace: "2"
  storagePool: "lvm-thin"
  resourceGroup: "default"
  fsType: xfs
```

### Security Context
```yaml
# Pod-level
securityContext:
  fsGroup: 0
  runAsNonRoot: false

# Container-level
securityContext:
  privileged: true
  runAsUser: 0
  allowPrivilegeEscalation: true
```

### SCC
- Using `privileged` SCC via RoleBinding
