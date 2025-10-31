#!/bin/bash

set -e

PROJECT_NAME="storage-test"

echo "=========================================="
echo "LINSTOR Storage Test - OpenShift"
echo "=========================================="
echo ""

# Check for existing deployments
check_existing_deployments() {
    local rwo_exists=false
    local rwx_exists=false

    if oc get project $PROJECT_NAME &>/dev/null; then
        echo "🔍 Checking for existing deployments..."
        if oc get deployment storage-demo-rwo -n $PROJECT_NAME &>/dev/null; then
            rwo_exists=true
            echo "   ⚠️  RWO mode is already deployed"
        fi
        if oc get deployment storage-demo-rwx -n $PROJECT_NAME &>/dev/null; then
            rwx_exists=true
            echo "   ⚠️  RWX mode is already deployed"
        fi

        if [ "$rwo_exists" = true ] || [ "$rwx_exists" = true ]; then
            echo ""
            read -p "Clean up existing deployments before proceeding? (y/N): " -n 1 -r
            echo ""
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                [ "$rwo_exists" = true ] && ./delete-rwo.sh
                [ "$rwx_exists" = true ] && ./delete-rwx.sh
                echo "✅ Cleanup complete"
                echo ""
            else
                echo "❌ Cannot proceed with existing deployments. Exiting."
                exit 1
            fi
        fi
    fi
}

# Show test mode selection menu
select_test_mode() {
    echo "Select a test mode:"
    echo ""
    echo "  1) RWO Mode - Node Failover Testing"
    echo "     └─ Single pod, tests node failure scenarios"
    echo "     └─ Options: cordon/drain, VM shutdown, VM destroy"
    echo ""
    echo "  2) RWX Mode - Multi-Writer Testing"
    echo "     └─ Two pods on different nodes, concurrent writes via NFS"
    echo ""
    read -p "Enter your choice [1-2]: " choice

    case "$choice" in
        1)
            TEST_MODE="rwo"
            ;;
        2)
            TEST_MODE="rwx"
            ;;
        *)
            echo "❌ Invalid choice. Please select 1 or 2."
            exit 1
            ;;
    esac

    echo ""
    echo "🎯 Selected: ${TEST_MODE^^} Mode"
    echo ""
}

# Run RWO test workflow
run_rwo_test() {
    echo "=========================================="
    echo "RWO MODE: Node Failover Test"
    echo "=========================================="
    echo ""

    # Deploy
    echo "📦 Step 1/3: Deploying RWO mode..."
    echo ""
    ./deploy-rwo.sh

    echo ""
    echo "✅ Deployment complete!"
    echo ""

    # Wait a moment for writer to start
    echo "⏳ Waiting for application to start writing to storage..."
    sleep 20

    # Quick status check
    echo ""
    echo "📊 Current status:"
    oc get pods -l mode=rwo -o wide
    echo ""

    # Test
    echo "=========================================="
    echo "📦 Step 2/3: Running failover test..."
    echo "=========================================="
    echo ""
    ./test-node-failover.sh

    echo ""
    echo "✅ Failover test complete!"
    echo ""

    # Cleanup
    echo "=========================================="
    echo "📦 Step 3/3: Cleanup"
    echo "=========================================="
    echo ""
    read -p "Clean up RWO mode deployment? (y/N): " -n 1 -r
    echo ""
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        ./delete-rwo.sh
        echo "✅ Cleanup complete!"
    else
        echo "ℹ️  Deployment left running. Clean up later with: ./delete-rwo.sh"
    fi
}

# Run RWX test workflow
run_rwx_test() {
    echo "=========================================="
    echo "RWX MODE: Multi-Writer Test"
    echo "=========================================="
    echo ""

    # Deploy
    echo "📦 Step 1/3: Deploying RWX mode..."
    echo ""
    ./deploy-rwx.sh

    echo ""
    echo "✅ Deployment complete!"
    echo ""

    # Wait for both pods to start writing
    echo "⏳ Waiting for applications to start writing to storage..."
    sleep 25

    # Show status and logs
    echo ""
    echo "=========================================="
    echo "📦 Step 2/3: Verifying multi-writer access"
    echo "=========================================="
    echo ""

    echo "📊 Pod status (should be on different nodes):"
    oc get pods -l mode=rwx-nfs -o wide
    echo ""

    echo "📝 Storage content (showing writes from multiple pods):"
    POD=$(oc get pods -l mode=rwx-nfs -o jsonpath='{.items[0].metadata.name}')
    if [ -n "$POD" ]; then
        echo ""
        echo "--- Last 20 entries (look for different pod names!) ---"
        oc exec $POD -c writer -- tail -20 /mnt/shared/output.txt 2>/dev/null || echo "Could not read file"
        echo ""
        echo "Total entries:"
        oc exec $POD -c writer -- wc -l /mnt/shared/output.txt 2>/dev/null || echo "Could not count"
        echo "-------------------------------------------------------"
        echo ""

        # Count unique writers
        echo "📊 Unique writers detected:"
        oc exec $POD -c writer -- cat /mnt/shared/output.txt 2>/dev/null | grep -o 'Pod: [^|]*' | sort -u || echo "Could not analyze"
        echo ""
    else
        echo "⚠️  Could not find pod for verification"
    fi

    echo "✅ Multi-writer verification complete!"
    echo ""

    read -p "Press Enter to view live logs from all writers (Ctrl+C to stop)..."
    echo ""
    echo "📺 Live logs (showing writes from both pods):"
    oc logs -f deployment/storage-demo-rwx -c writer --all-pods=true || true

    echo ""

    # Cleanup
    echo ""
    echo "=========================================="
    echo "📦 Step 3/3: Cleanup"
    echo "=========================================="
    echo ""
    read -p "Clean up RWX mode deployment? (y/N): " -n 1 -r
    echo ""
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        ./delete-rwx.sh
        echo "✅ Cleanup complete!"
    else
        echo "ℹ️  Deployment left running. Clean up later with: ./delete-rwx.sh"
    fi
}

# Main workflow
main() {
    # Check for existing deployments
    check_existing_deployments

    # Select test mode
    select_test_mode

    # Confirmation
    echo "=========================================="
    echo "⚠️  READY TO START"
    echo "=========================================="
    echo ""
    echo "This will:"
    echo "  1. Deploy ${TEST_MODE^^} mode"
    echo "  2. Run tests"
    echo "  3. Offer cleanup"
    echo ""
    read -p "Continue? (y/N): " -n 1 -r
    echo ""
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Test cancelled."
        exit 0
    fi
    echo ""

    # Run selected test
    case "$TEST_MODE" in
        rwo)
            run_rwo_test
            ;;
        rwx)
            run_rwx_test
            ;;
    esac

    echo ""
    echo "=========================================="
    echo "✅ Test Complete!"
    echo "=========================================="
    echo ""
    echo "📋 Don't forget to document your results in TEST_RESULTS.md"
    echo ""
}

# Show help
if [ "$1" == "--help" ] || [ "$1" == "-h" ]; then
    echo "Unified test workflow for LINSTOR storage on OpenShift"
    echo ""
    echo "Usage: $0"
    echo ""
    echo "This script will:"
    echo "  1. Check for and clean up any existing deployments"
    echo "  2. Prompt you to select a test mode (RWO or RWX)"
    echo "  3. Deploy the selected mode"
    echo "  4. Run appropriate tests"
    echo "  5. Offer cleanup"
    echo ""
    echo "Test Modes:"
    echo "  RWO - Node failover testing with failure scenarios"
    echo "  RWX - Multi-writer concurrent access testing"
    echo ""
    exit 0
fi

# Run main workflow
main
