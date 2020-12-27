# Grafana - Azure

## Installing Grafana in Azure

This setup allows you to create a full grafana in azure. Features 

* Grafana running as Azure web app using Linux App Service Plan
* Persistent data using Azure MySQL
* Provisioned with custom plugins
* Grafana authentication by Azure AD with user roles
* Authentication form disabled and direct SSO Login
* Can be customized through Azure Resource Manager Template (ARM Template)
* Secrets stored in Azure key vault for reference
* Using official grafana docker image

### Usage

```bash
 ./install.sh <grafana-instance-name> <azure-subscription-id> <grafana-version>
```

**Example** The command `./install.sh grafana-instance-name xxxx-xxxx-xxxx-xxxx 7.3.3` will create **https://grafana-instance-name.azurewebsites.net/** using grafana `7.3.3` on subscription `xxxx-xxxx-xxxx-xxxx`.
