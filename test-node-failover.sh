#!/bin/bash

set -e

PROJECT_NAME="storage-test"

echo "=========================================="
echo "Node Failover Test Script (RWO Mode)"
echo "=========================================="
echo ""

# Show help if requested
if [ "$1" == "--help" ] || [ "$1" == "-h" ]; then
    echo "This script tests node failover scenarios for RWO storage."
    echo ""
    echo "When run, you'll be prompted to select a failure mode:"
    echo ""
    echo "  1. Cordon/Drain  - Gracefully drain the node (Kubernetes native)"
    echo "  2. Shutdown      - Graceful VM shutdown via virsh"
    echo "  3. Destroy       - Hard VM power-off via virsh (simulates hardware failure)"
    echo ""
    echo "The script will:"
    echo "  - Show storage content BEFORE failover"
    echo "  - Trigger the selected failure mode"
    echo "  - Monitor pod migration to new node"
    echo "  - Show storage content AFTER failover"
    echo "  - Offer recovery options"
    echo ""
    exit 0
fi

# Interactive menu for failure mode selection
echo "Select a failure mode to test:"
echo ""
echo "  1) Cordon/Drain  - Gracefully drain the node (Kubernetes native)"
echo "     └─ Safest option, uses standard Kubernetes operations"
echo ""
echo "  2) Shutdown      - Graceful VM shutdown (virsh shutdown)"
echo "     └─ Simulates a controlled server shutdown"
echo ""
echo "  3) Destroy       - Hard power-off (virsh destroy)"
echo "     └─ Simulates sudden hardware failure (pulling the power cable)"
echo ""
read -p "Enter your choice [1-3]: " choice

case "$choice" in
    1)
        FAILURE_MODE="cordon"
        ;;
    2)
        FAILURE_MODE="shutdown"
        ;;
    3)
        FAILURE_MODE="destroy"
        ;;
    *)
        echo "❌ Invalid choice. Please run the script again and select 1, 2, or 3."
        exit 1
        ;;
esac

echo ""
echo "🎯 Selected Failure Mode: $FAILURE_MODE"
echo ""

# Switch to project
echo "📦 Switching to project: $PROJECT_NAME"
if ! oc project $PROJECT_NAME &>/dev/null; then
    echo "   ⚠️  Project $PROJECT_NAME does not exist."
    echo "   Please deploy RWO mode first: ./deploy-rwo.sh"
    exit 1
fi
echo ""

# Check if RWO mode is deployed
echo "🔍 Checking RWO mode deployment..."
if ! oc get deployment storage-demo-rwo &>/dev/null; then
    echo "   ⚠️  RWO mode is not deployed."
    echo "   Please deploy RWO mode first: ./deploy-rwo.sh"
    exit 1
fi
echo "   ✅ RWO mode is deployed"
echo ""

# Get current pod and node info
echo "📊 Current pod status:"
oc get pods -l mode=rwo -o wide
echo ""

POD=$(oc get pods -l mode=rwo -o jsonpath='{.items[0].metadata.name}')
NODE=$(oc get pods -l mode=rwo -o jsonpath='{.items[0].spec.nodeName}')

if [ -z "$POD" ] || [ -z "$NODE" ]; then
    echo "   ⚠️  Could not find pod or node. Is RWO mode running?"
    exit 1
fi

echo "📍 Pod: $POD"
echo "📍 Node: $NODE"
echo ""

# Show current storage content BEFORE failover
echo "=========================================="
echo "📝 BEFORE FAILOVER - Storage Content"
echo "=========================================="
echo ""
echo "Checking storage file on origin node ($NODE)..."
if oc exec $POD -c writer -- test -f /mnt/shared/output.txt 2>/dev/null; then
    echo ""
    echo "--- Last 5 entries from origin node ---"
    oc exec $POD -c writer -- tail -5 /mnt/shared/output.txt 2>/dev/null || echo "Could not read file"
    echo "---------------------------------------"
    echo ""
    LAST_ENTRY_BEFORE=$(oc exec $POD -c writer -- tail -1 /mnt/shared/output.txt 2>/dev/null | grep -o 'Iteration: [^/]*' || echo "unknown")
    echo "✅ Storage accessible on origin node"
    echo "   Last entry: $LAST_ENTRY_BEFORE"
else
    echo "⚠️  Storage file not found yet (pod may be starting)"
fi
echo ""

# Get VM name for virsh operations
VM_NAME=""
if [ "$FAILURE_MODE" != "cordon" ]; then
    echo "🔍 Looking up VM name for node: $NODE"
    # Try to map OpenShift node name to VM name
    # Assuming naming like: ostest_master_0 maps to master-0
    NODE_SUFFIX=$(echo $NODE | grep -oE '[0-9]+$')
    NODE_PREFIX=$(echo $NODE | sed 's/-[0-9]*$//')

    # Try common naming patterns
    POSSIBLE_NAMES=(
        "ostest_${NODE_PREFIX}_${NODE_SUFFIX}"
        "ostest-${NODE_PREFIX}-${NODE_SUFFIX}"
        "${NODE_PREFIX}_${NODE_SUFFIX}"
        "${NODE_PREFIX}-${NODE_SUFFIX}"
    )

    for name in "${POSSIBLE_NAMES[@]}"; do
        if virsh -c qemu:///system list --all 2>/dev/null | grep -q "$name"; then
            VM_NAME="$name"
            echo "   ✅ Found VM: $VM_NAME"
            break
        fi
    done

    if [ -z "$VM_NAME" ]; then
        echo "   ⚠️  Could not find VM for node: $NODE"
        echo "   Available VMs:"
        virsh -c qemu:///system list --all 2>/dev/null | grep -v "^---" | grep -v "^ Id"
        echo ""
        read -p "   Enter VM name manually: " VM_NAME
        if [ -z "$VM_NAME" ]; then
            echo "   No VM name provided. Falling back to 'cordon' mode."
            FAILURE_MODE="cordon"
        fi
    fi
fi
echo ""

# Confirm before proceeding
echo "=========================================="
echo "⚠️  CONFIRMATION"
echo "=========================================="
echo ""
echo "This will trigger a failover using: $FAILURE_MODE"
echo "  Node: $NODE"
[ -n "$VM_NAME" ] && echo "  VM: $VM_NAME"
echo ""
case "$FAILURE_MODE" in
    cordon)
        echo "Action: Kubernetes will gracefully drain the node"
        ;;
    shutdown)
        echo "Action: VM will be gracefully shutdown (virsh shutdown)"
        ;;
    destroy)
        echo "Action: VM will be hard powered-off (virsh destroy)"
        echo "⚠️  This simulates sudden hardware failure!"
        ;;
esac
echo ""
read -p "Continue? (y/N): " -n 1 -r
echo ""
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Test cancelled."
    exit 0
fi
echo ""

# Execute failover based on mode
echo "=========================================="
echo "💥 TRIGGERING FAILOVER"
echo "=========================================="
echo ""

case "$FAILURE_MODE" in
    cordon)
        echo "🚫 Cordoning and draining node: $NODE"
        echo "   - Marking node as unschedulable"
        echo "   - Evicting all pods gracefully"
        echo ""
        oc adm drain $NODE --ignore-daemonsets --delete-emptydir-data --force
        echo ""
        echo "✅ Node drained successfully"
        ;;

    shutdown)
        echo "🔌 Gracefully shutting down VM: $VM_NAME"
        echo "   This simulates a graceful server shutdown"
        echo ""
        virsh -c qemu:///system shutdown $VM_NAME
        echo ""
        echo "✅ Shutdown command sent"
        echo "   Waiting for VM to power off..."
        sleep 10
        # Wait for node to become NotReady
        timeout=60
        elapsed=0
        while [ $elapsed -lt $timeout ]; do
            status=$(oc get node $NODE -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "Unknown")
            if [ "$status" != "True" ]; then
                echo "   ✅ Node is now NotReady"
                break
            fi
            sleep 5
            elapsed=$((elapsed + 5))
        done
        ;;

    destroy)
        echo "⚡ HARD POWER-OFF VM: $VM_NAME"
        echo "   ⚠️  This simulates pulling the power cable!"
        echo ""

        echo "💾 Backing up domain XML..."
        VM_XML_BACKUP="/tmp/${VM_NAME}-backup.xml"
        virsh -c qemu:///system dumpxml $VM_NAME > $VM_XML_BACKUP
        if [ -f "$VM_XML_BACKUP" ]; then
            echo "   ✅ Domain XML backed up to: $VM_XML_BACKUP"
        else
            echo "   ⚠️  Failed to backup domain XML"
            exit 1
        fi
        echo ""

        echo "🔒 Disabling autostart to prevent automatic recovery..."
        virsh -c qemu:///system autostart --disable $VM_NAME
        echo ""

        echo "🗑️  Undefining domain to prevent auto-restart..."
        virsh -c qemu:///system undefine --nvram $VM_NAME
        echo ""

        echo "💥 Destroying VM (hard power-off)..."
        virsh -c qemu:///system destroy $VM_NAME
        echo ""
        echo "✅ VM destroyed and undefined (hard power-off)"
        echo "   Node should become NotReady shortly..."
        sleep 5
        ;;
esac
echo ""

# Watch pod migration
echo "=========================================="
echo "⏳ WAITING FOR FAILOVER"
echo "=========================================="
echo ""
echo "Watching pod migration and recreation..."
echo ""

# Wait for old pod to terminate
echo "1️⃣  Waiting for old pod to terminate..."
timeout=120
elapsed=0
while [ $elapsed -lt $timeout ]; do
    pod_status=$(oc get pod $POD -o jsonpath='{.status.phase}' 2>/dev/null || echo "NotFound")
    if [ "$pod_status" == "NotFound" ] || [ "$pod_status" == "Terminating" ]; then
        echo "   ✅ Old pod terminating/terminated"
        break
    fi
    if [ $((elapsed % 10)) -eq 0 ]; then
        echo "   Status: $pod_status (waiting for termination...)"
    fi
    sleep 2
    elapsed=$((elapsed + 2))
done
echo ""

# Wait for new pod to be created and running
echo "2️⃣  Waiting for new pod to be created and running..."
timeout=180
elapsed=0
NEW_POD=""
NEW_NODE=""
while [ $elapsed -lt $timeout ]; do
    # Get running pod
    NEW_POD=$(oc get pods -l mode=rwo -o jsonpath='{.items[?(@.status.phase=="Running")].metadata.name}' 2>/dev/null | head -n 1)

    if [ -n "$NEW_POD" ] && [ "$NEW_POD" != "$POD" ]; then
        NEW_NODE=$(oc get pod $NEW_POD -o jsonpath='{.spec.nodeName}' 2>/dev/null)
        # Check if containers are ready
        ready=$(oc get pod $NEW_POD -o jsonpath='{.status.containerStatuses[*].ready}' 2>/dev/null)
        if [[ "$ready" == *"true"*"true"* ]] || [[ "$ready" == "true true" ]]; then
            echo "   ✅ New pod running and ready!"
            echo "   Pod: $NEW_POD"
            echo "   Node: $NEW_NODE"
            break
        fi
    fi

    if [ $((elapsed % 10)) -eq 0 ]; then
        current_pods=$(oc get pods -l mode=rwo --no-headers 2>/dev/null | wc -l)
        echo "   Waiting for new pod... (${elapsed}s elapsed, $current_pods pods found)"
    fi
    sleep 5
    elapsed=$((elapsed + 5))
done

if [ -z "$NEW_POD" ]; then
    echo "   ⚠️  Timeout waiting for new pod"
fi
echo ""

echo "📊 Current pod status:"
oc get pods -l mode=rwo -o wide
echo ""

if [ "$NEW_NODE" != "$NODE" ]; then
    echo "✅ SUCCESS: Pod migrated from $NODE to $NEW_NODE"
else
    echo "⚠️  WARNING: Pod appears to be on same node (may indicate an issue)"
fi
echo ""

# Wait for new write to storage
echo "=========================================="
echo "📝 AFTER FAILOVER - Verifying Storage"
echo "=========================================="
echo ""

if [ -z "$NEW_POD" ]; then
    NEW_POD=$(oc get pods -l mode=rwo -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
fi

if [ -n "$NEW_POD" ]; then
    echo "3️⃣  Waiting for new node to write to storage..."
    echo "   (Writer writes every 15 seconds, waiting up to 30 seconds...)"
    echo ""

    # Wait for a new entry to appear
    timeout=35
    elapsed=0
    success=false

    while [ $elapsed -lt $timeout ]; do
        if oc exec $NEW_POD -c writer -- test -f /mnt/shared/output.txt 2>/dev/null; then
            current_entry=$(oc exec $NEW_POD -c writer -- tail -1 /mnt/shared/output.txt 2>/dev/null | grep -o 'Iteration: [^/]*' || echo "unknown")

            # Check if we have a new entry or if node name changed
            current_node_in_file=$(oc exec $NEW_POD -c writer -- tail -1 /mnt/shared/output.txt 2>/dev/null | grep -o 'Node: [^|]*' || echo "unknown")

            if [[ "$current_node_in_file" == *"$NEW_NODE"* ]] || [ "$current_entry" != "$LAST_ENTRY_BEFORE" ]; then
                echo "   ✅ New entry detected from failover node!"
                success=true
                break
            fi
        fi

        if [ $((elapsed % 5)) -eq 0 ] && [ $elapsed -gt 0 ]; then
            echo "   Waiting... (${elapsed}s / ${timeout}s)"
        fi
        sleep 2
        elapsed=$((elapsed + 2))
    done

    echo ""
    echo "--- Storage file content AFTER failover ---"
    if oc exec $NEW_POD -c writer -- test -f /mnt/shared/output.txt 2>/dev/null; then
        echo "Last 10 entries:"
        oc exec $NEW_POD -c writer -- tail -10 /mnt/shared/output.txt 2>/dev/null || echo "Could not read file"
        echo ""
        echo "Total entries in file:"
        oc exec $NEW_POD -c writer -- wc -l /mnt/shared/output.txt 2>/dev/null || echo "Could not count lines"
    else
        echo "⚠️  Storage file not accessible"
    fi
    echo "-------------------------------------------"
    echo ""

    # Determine test result
    if [ "$success" = true ]; then
        TEST_RESULT="PASS"
        TEST_STATUS="✅"
        TEST_MESSAGE="Storage is accessible and being written to by failover node"
    else
        TEST_RESULT="FAIL"
        TEST_STATUS="❌"
        TEST_MESSAGE="No new entries detected - failover may have failed"
    fi
else
    TEST_RESULT="FAIL"
    TEST_STATUS="❌"
    TEST_MESSAGE="Could not find new pod for storage verification"
fi
echo ""

# Recovery and cleanup
echo "=========================================="
echo "🔄 RECOVERY"
echo "=========================================="
echo ""

case "$FAILURE_MODE" in
    cordon)
        read -p "Do you want to uncordon node $NODE now? (y/N): " -n 1 -r
        echo ""
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            echo "   Uncordoning node $NODE..."
            oc adm uncordon $NODE
            echo "   ✅ Node $NODE is now schedulable again"
        else
            echo "   ℹ️  Node $NODE remains cordoned"
            echo "   To uncordon later: oc adm uncordon $NODE"
        fi
        ;;

    shutdown)
        echo "VM '$VM_NAME' is powered off."
        echo ""
        read -p "Do you want to start the VM now? (y/N): " -n 1 -r
        echo ""
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            echo "   Starting VM $VM_NAME..."
            virsh -c qemu:///system start $VM_NAME
            echo "   ✅ VM start command sent"
            echo ""
            echo "   Note: Node will take a few minutes to rejoin the cluster"
            echo ""
            echo "   Monitor node status with:"
            echo "     watch oc get nodes"
        else
            echo "   ℹ️  VM remains powered off"
            echo "   To start later: virsh -c qemu:///system start $VM_NAME"
        fi
        ;;

    destroy)
        echo "VM '$VM_NAME' is powered off and undefined."
        echo ""
        read -p "Do you want to restore and start the VM now? (y/N): " -n 1 -r
        echo ""
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            # Restore VM definition from backup
            if [ -f "$VM_XML_BACKUP" ]; then
                echo "   Restoring VM definition from backup..."
                virsh -c qemu:///system define $VM_XML_BACKUP
                echo "   ✅ VM defined from backup"
                echo ""
            else
                echo "   ❌ Error: Backup XML not found at $VM_XML_BACKUP"
                echo "   Cannot restore VM without domain XML"
                exit 1
            fi

            echo "   Starting VM $VM_NAME..."
            virsh -c qemu:///system start $VM_NAME
            echo "   ✅ VM start command sent"
            echo ""

            read -p "   Do you want to re-enable autostart for this VM? (y/N): " -n 1 -r
            echo ""
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                virsh -c qemu:///system autostart $VM_NAME
                echo "   ✅ Autostart re-enabled"
            else
                echo "   ℹ️  Autostart remains disabled"
                echo "   To enable later: virsh -c qemu:///system autostart $VM_NAME"
            fi

            echo ""
            read -p "   Delete backup XML file? (y/N): " -n 1 -r
            echo ""
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                rm -f "$VM_XML_BACKUP"
                echo "   ✅ Backup XML deleted"
            else
                echo "   ℹ️  Backup XML kept at: $VM_XML_BACKUP"
            fi

            echo ""
            echo "   Note: Node will take a few minutes to rejoin the cluster"
            echo ""
            echo "   Monitor node status with:"
            echo "     watch oc get nodes"
        else
            echo "   ℹ️  VM remains powered off and undefined"
            echo "   Note: Domain XML backup saved at: $VM_XML_BACKUP"
            echo ""
            echo "   To restore later:"
            echo "     virsh -c qemu:///system define $VM_XML_BACKUP"
            echo "     virsh -c qemu:///system start $VM_NAME"
        fi
        ;;
esac
echo ""

echo "=========================================="
echo "TEST RESULTS"
echo "=========================================="
echo ""
echo "Failure Mode: $FAILURE_MODE"
echo "Origin Node:  $NODE"
echo "Failover Node: $NEW_NODE"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "  TEST STATUS: $TEST_STATUS $TEST_RESULT"
echo ""
echo "  $TEST_MESSAGE"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

if [ "$TEST_RESULT" == "FAIL" ]; then
    echo "⚠️  TEST FAILED - Recommended Actions:"
    echo ""
    echo "1. Check pod events for detailed error messages:"
    echo "   oc describe pod -l mode=rwo"
    echo ""
    echo "2. Check PVC status:"
    echo "   oc describe pvc linstor-shared-storage-rwo"
    echo ""
    echo "3. Check LINSTOR resources:"
    echo "   oc get linstorresources -A"
    echo ""
    echo "4. Review TEST_RESULTS.md and document this failure"
    echo ""
    echo "5. Consider using a different failure mode:"
    if [ "$FAILURE_MODE" == "shutdown" ]; then
        echo "   - Try 'cordon' mode for planned maintenance scenarios"
        echo "   - Try 'destroy' mode for catastrophic failure testing"
    fi
    echo ""
fi

echo "=========================================="
echo "Test Complete"
echo "=========================================="
echo ""

echo "📝 Useful commands:"
echo ""
echo "  Monitor pods:"
echo "    watch oc get pods -l mode=rwo -o wide"
echo ""
echo "  View writer logs:"
echo "    oc logs -f deployment/storage-demo-rwo -c writer"
echo ""
echo "  View reader logs:"
echo "    oc logs -f deployment/storage-demo-rwo -c reader"
echo ""
echo "  Check cordoned nodes:"
echo "    oc get nodes | grep SchedulingDisabled"
echo ""
echo "  Uncordon the node:"
echo "    oc adm uncordon $NODE"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "📋 Please document your test results in TEST_RESULTS.md"
echo ""
echo "   Test: RWO Mode - $FAILURE_MODE"
echo "   Status: $TEST_STATUS $TEST_RESULT"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
