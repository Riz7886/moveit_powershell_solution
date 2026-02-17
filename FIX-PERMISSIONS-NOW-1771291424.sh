#!/bin/bash

echo ""
echo "================================================"
echo "FIXING SERVICE PRINCIPAL PERMISSIONS"
echo "================================================"
echo ""

SP_ID="d519efa6-3cb5-4fa0-8535-c657175be154"

echo "[1] Getting all Databricks workspaces..."
WORKSPACES=$(az databricks workspace list --query "[].{id:id,name:name}" -o json)

echo ""
echo "Found workspaces:"
echo "$WORKSPACES" | jq -r '.[] | "\(.name) -> \(.id)"'
echo ""

echo "[2] Granting Contributor role to service principal on each workspace..."
echo ""

echo "$WORKSPACES" | jq -r '.[].id' | while read WORKSPACE_ID; do
    WORKSPACE_NAME=$(echo "$WORKSPACES" | jq -r --arg id "$WORKSPACE_ID" '.[] | select(.id==$id) | .name')
    
    echo "   Processing: $WORKSPACE_NAME"
    
    az role assignment create \
        --assignee "$SP_ID" \
        --role "Contributor" \
        --scope "$WORKSPACE_ID" \
        2>/dev/null
    
    if [ $? -eq 0 ]; then
        echo "      SUCCESS: Contributor role granted"
    else
        echo "      ALREADY EXISTS or ERROR"
    fi
    
    echo ""
done

echo "[3] Verifying role assignments..."
echo ""
az role assignment list --assignee "$SP_ID" --query "[].{Role:roleDefinitionName,Scope:scope}" -o table

echo ""
echo "================================================"
echo "DONE!"
echo "================================================"
echo ""
echo "Now Preyash should be able to assign jobs!"
echo ""
