#!/bin/sh

echo "########################################"
echo "Grafana - Azure Installation"
echo "########################################"

help_arguments() {
    echo "Mandatory arguments missing."
    echo "Argument 1 : grafana instance name"
    echo "Argument 2 : azure subscription id"
    echo "Argument 3 : grafana version"
}


if [ $# -eq 0 ]; then

    help_arguments
    exit 1

elif [ $# -le 2 ]; then

    help_arguments
    exit 1

else

    ########################################
    ########## Create and assign variables
    ########################################

    SERVER_NAME=$1
    SUBSCRIPTION_ID=$2
    GRAFANA_VERSION=$3
    SPN_NAME="$SERVER_NAME-auth"
    DEPLOYMENT_NAME=deployment-${SERVER_NAME}-$(date +%s)
    CURRENT_USER_OBJECT_ID=$(az ad signed-in-user show --query objectId -o tsv | tr -d '\r')
    echo "Installing grafana instance $SERVER_NAME ( grafana/grafana:$GRAFANA_VERSION ) on $SUBSCRIPTION_ID"

    ########################################
    ########## Generate random passwords
    ########################################

    MYSQL_PASSWORD=$(date +%s | sha256sum | base64 | head -c 24)
    KEYVAULT_ID=$(az keyvault show  --name $SERVER_NAME-kv --subscription $SUBSCRIPTION_ID --query id -o tsv)
    DOES_KEYVAULT_EXIST=$?
    if [ $DOES_KEYVAULT_EXIST -eq 0 ]; then
        echo "Keyvault found already. Retreiving existing grafana password"
        GRAFANA_PASSWORD=$(az keyvault secret show --vault-name $SERVER_NAME-kv --name grafana-password --query value -o tsv | tr -d '\r')
    else 
        echo "Keyvault not found. Generating new grafana password"
        GRAFANA_PASSWORD=$(date +%s | sha256sum | base64 | head -c 24)
    fi

    ########################################
    ########## Create SPN/Service account
    ########################################

    echo "Creating SPN for Grafana authentication ( SPN : $SPN_NAME )";
    SPN_APP_ID=$(az ad sp create-for-rbac --name "https://$SPN_NAME" --skip-assignment true -o tsv --query appId)
    az ad app update --id "https://$SPN_NAME" --app-roles @app-roles.manifest.json --reply-urls "https://$SERVER_NAME.azurewebsites.net/login/azuread"
    echo "Generating secret for Grafana authentication SPN ( SPN : $SPN_NAME APP_ID : $SPN_APP_ID )";
    SPN_SECRET=$(az ad app credential reset --id https://$SPN_NAME --credential-description "grafana" -o tsv --query "password")
    
    ########################################
    ########## Add current user as Grafana admin
    ########################################
    SPN_OBJECT_ID=$(az ad sp show --id https://$SPN_NAME --query objectId -o tsv)
    DOES_ROLE_EXIST=$(az rest --method get --uri https://graph.microsoft.com/v1.0/users/$CURRENT_USER_OBJECT_ID/appRoleAssignments --headers "Content-Type=application/json" | jq .value[].appRoleId | grep "08bd0766-08e1-45e4-b20c-cfb0e48a300")
    exit_status=$?
    if [ $exit_status -eq 0 ]; then
        echo "Role already assigned";
    else
        echo "Assigning Role";
        az rest --method post --uri https://graph.microsoft.com/v1.0/users/$CURRENT_USER_OBJECT_ID/appRoleAssignments --headers "Content-Type=application/json" --body '{"appRoleId":"08bd0766-08e1-45e4-b20c-cfb0e48a3005", "principalId":"'"$CURRENT_USER_OBJECT_ID"'","resourceId":"'"$SPN_OBJECT_ID"'"}'
    fi

    ########################################
    ########## Deploy Grafana
    ########################################

    echo "Deploying Grafana ( Deployment Name : $DEPLOYMENT_NAME )";
    az deployment sub create --name $DEPLOYMENT_NAME --location eastus --subscription $SUBSCRIPTION_ID --template-file ./arm-templates/grafana.json --parameters @arm-templates/grafana.params.json --parameters deployment_name=$DEPLOYMENT_NAME server_name=$SERVER_NAME grafana_version=$GRAFANA_VERSION spn_clientid_grafana_online=$SPN_APP_ID spn_clientsecret_grafana_online=$SPN_SECRET grafana_mysql_password=$MYSQL_PASSWORD grafana_admin_password=$GRAFANA_PASSWORD current_user_objectId=$CURRENT_USER_OBJECT_ID
    
    ########################################
    ########## Grafana Healthcheck
    ########################################
    
    echo "Performing healtcheck for https://$SERVER_NAME.azurewebsites.net...."
    echo "Instance logs : https://portal.azure.com/#resource/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$SERVER_NAME/providers/Microsoft.Web/sites/$SERVER_NAME/logStream"
    echo "Performing healtcheck for https://$SERVER_NAME.azurewebsites.net...."
    while [ $(curl --insecure -s -o /dev/null --head -w "%{http_code}" -X GET "https://$SERVER_NAME.azurewebsites.net/api/health") != "200" ]; 
    do
     echo "https://$SERVER_NAME.azurewebsites.net is not available yet / warming up. Check logs."
     sleep 10;
    done
    echo "Grafana is now available in https://$SERVER_NAME.azurewebsites.net"

    ########################################
    ########## Configure Grafana Datasource
    ########################################
    
    ./configure-datasource.sh $SERVER_NAME $SUBSCRIPTION_ID

    exit $?

fi
