#!/bin/bash

echo ""
echo "FIXING SERVICE PRINCIPAL PERMISSIONS"
echo ""

SP_ID="d519efa6-3cb5-4fa0-8535-c657175be154"

echo "Getting workspaces..."
echo ""

az databricks workspace list --query "[].{name:name, id:id}" -o tsv | while IFS=$'\t' read -r name id; do
    echo "Processing: $name"
    az role assignment create --assignee $SP_ID --role "Contributor" --scope "$id" 2>&1 | grep -q "already exists" && echo "  OK - Already exists" || echo "  DONE - Permission granted"
    echo ""
done

echo ""
echo "VERIFYING PERMISSIONS:"
echo ""
az role assignment list --assignee $SP_ID --query "[].{Role:roleDefinitionName, Workspace:scope}" -o table

echo ""
echo "COMPLETE!"
echo ""
