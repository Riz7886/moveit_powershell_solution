#!/bin/bash

echo ""
echo "=========================================="
echo "VERIFICATION SCRIPT - CHECKING EVERYTHING"
echo "=========================================="
echo ""

SP_ID="d519efa6-3cb5-4fa0-8535-c657175be154"
PASS=0
FAIL=0

# TEST 1: Service Principal Exists
echo "[TEST 1] Checking if service principal exists..."
if az ad sp show --id $SP_ID > /dev/null 2>&1; then
    echo "  PASS - Service principal exists"
    ((PASS++))
else
    echo "  FAIL - Service principal not found"
    ((FAIL++))
fi
echo ""

# TEST 2: Role Assignments on Workspaces
echo "[TEST 2] Checking Azure role assignments..."
ROLE_COUNT=$(az role assignment list --assignee $SP_ID --query "length(@)")

if [ "$ROLE_COUNT" -ge 4 ]; then
    echo "  PASS - Service principal has $ROLE_COUNT role assignments"
    ((PASS++))
else
    echo "  FAIL - Service principal only has $ROLE_COUNT role assignments (need 4)"
    ((FAIL++))
fi

echo ""
echo "  Role assignments details:"
az role assignment list --assignee $SP_ID --query "[].{Role:roleDefinitionName, Scope:scope}" -o table
echo ""

# TEST 3: Verify each workspace has Contributor
echo "[TEST 3] Verifying Contributor on each workspace..."
WORKSPACE_COUNT=0
az databricks workspace list --query "[].{name:name, id:id}" -o tsv | while IFS=$'\t' read -r name id; do
    if az role assignment list --assignee $SP_ID --scope "$id" --query "[?roleDefinitionName=='Contributor']" -o tsv | grep -q .; then
        echo "  PASS - $name has Contributor role"
    else
        echo "  FAIL - $name missing Contributor role"
    fi
done
echo ""

# TEST 4: Check Databricks API Access
echo "[TEST 4] Testing Databricks workspace API access..."
TOKEN=$(az account get-access-token --resource "2ff814a6-3304-4ab8-85cb-cd0e6f879c1d" --query accessToken -o tsv)

if [ -n "$TOKEN" ]; then
    echo "  PASS - Got Databricks API token"
    ((PASS++))
    
    # Try to list service principals in first workspace
    WS_URL="https://adb-3248848193480666.6.azuredatabricks.net"
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" -H "Authorization: Bearer $TOKEN" "$WS_URL/api/2.0/preview/scim/v2/ServicePrincipals")
    
    if [ "$HTTP_CODE" = "200" ]; then
        echo "  PASS - Can access Databricks API"
        ((PASS++))
    else
        echo "  FAIL - Cannot access Databricks API (HTTP $HTTP_CODE)"
        ((FAIL++))
    fi
else
    echo "  FAIL - Could not get Databricks token"
    ((FAIL++))
fi
echo ""

# TEST 5: Check if SP is in Databricks workspaces
echo "[TEST 5] Checking if SP exists in Databricks workspaces..."
RESPONSE=$(curl -s -H "Authorization: Bearer $TOKEN" "$WS_URL/api/2.0/preview/scim/v2/ServicePrincipals")

if echo "$RESPONSE" | grep -q "$SP_ID"; then
    echo "  PASS - Service principal found in Databricks workspace"
    ((PASS++))
else
    echo "  FAIL - Service principal not found in Databricks workspace"
    ((FAIL++))
fi
echo ""

# FINAL RESULTS
echo "=========================================="
echo "FINAL RESULTS:"
echo "=========================================="
echo "PASSED: $PASS tests"
echo "FAILED: $FAIL tests"
echo ""

if [ $FAIL -eq 0 ]; then
    echo "STATUS: ALL TESTS PASSED - READY TO GO!"
    echo ""
    echo "Preyash CAN NOW:"
    echo "  - Assign jobs to service principal"
    echo "  - Run jobs as service principal"
    echo "  - Everything should work!"
else
    echo "STATUS: SOME TESTS FAILED - NEEDS ATTENTION"
    echo ""
    echo "Fix the failed tests before using."
fi
echo ""
echo "=========================================="
echo ""
