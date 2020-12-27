#!/bin/sh

echo "########################################"
echo "Grafana - Azure Configure Datasource"
echo "########################################"

help_arguments() {
    echo "Mandatory arguments missing."
    echo "Argument 1 : grafana instance name"
    echo "Argument 2 : azure subscription id"
}

get_existing_datasource_id() {
    DATASOURCES_LIST=$(curl "$1/api/datasources" -u "$2:$3" -H 'content-type: application/json' -H 'x-grafana-org-id: 1' --compressed)
    echo $DATASOURCES_LIST | jq '.[] | select(.name == "Azure Monitor") | .id'
}

post_to_grafana() {
    CREATE_DATASOURCES=$(curl "$1/api/datasources$6" -X "$5" -u "$2:$3" -H 'content-type: application/json' -H 'x-grafana-org-id: 1' --compressed --data-binary "$4")
    echo $CREATE_DATASOURCES | grep "Data source with the same name already exists"
    exit_status=$?
    if [ $exit_status -eq 0 ]; then
        echo "Need to update the datasource"
        DATASOURCE_ID=$(get_existing_datasource_id $1 $2 $3)
        post_to_grafana $1 $2 $3 "$4" "PUT" "/$DATASOURCE_ID" 
    else 
        echo $CREATE_DATASOURCES | jq '.message'
    fi
}

if [ $# -eq 0 ]; then
    help_arguments
    exit 1
elif [ $# -le 1 ]; then
    help_arguments
    exit 1
else

    ########################################
    ########## Create and assign variables
    ########################################

    SERVER_NAME=$1
    SUBSCRIPTION_ID=$2
    SPN_NAME="$SERVER_NAME-datasource"

    ########################################
    ########## Create SPN/Service account
    ########################################

    echo "Creating SPN for Grafana datasource ( SPN : $SPN_NAME ) and assigning permissions"
    SPN_APP_ID=$(az ad sp create-for-rbac --name https://$SPN_NAME --role "Monitoring Reader" --scopes /subscriptions/$SUBSCRIPTION_ID -o tsv --query appId | tr -d '\r')
    TENANT_ID=$(az ad sp show --id https://$SPN_NAME -o tsv --query appOwnerTenantId | tr -d '\r')
    echo "SPN Name : $SPN_NAME"
    echo "SPN ID : $SPN_APP_ID"
    echo "Tenant ID : $TENANT_ID"

    echo "(Re)Generating secret for Grafana authentication SPN ( SPN : $SPN_NAME )"
    SPN_SECRET=$(az ad app credential reset --id https://$SPN_NAME --credential-description "grafana" -o tsv --query "password" | tr -d '\r')

    ########################################
    ########## Retreiving Secrets
    ########################################

    echo "Retreiving Grafana Password"
    GRAFANAADMIN=grafana-admin
    GRAFANAPASSWORD=$(az keyvault secret show --vault-name $SERVER_NAME-kv --name grafana-password --query value -o tsv | tr -d '\r')

    ########################################
    ########## Configure Grafana
    ########################################

    echo "Configuring Grafana"
    post_to_grafana "https://$SERVER_NAME.azurewebsites.net" $GRAFANAADMIN $GRAFANAPASSWORD '{ "name" : "Azure Monitor", "type" : "grafana-azure-monitor-datasource", "url" : "https://management.azure.com", "access": "proxy", "isDefault" : false, "jsonData": { "tenantId": "'"$TENANT_ID"'", "clientId": "'"$SPN_APP_ID"'",  "subscriptionId" : "'"$SUBSCRIPTION_ID"'" }, "secureJsonData" : { "clientSecret" : "'"$SPN_SECRET"'" } }' "POST"
    exit 0

fi
