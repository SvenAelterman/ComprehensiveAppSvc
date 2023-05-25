# PowerShell script to deploy the main.bicep template with parameter values

#Requires -Modules "Az"
#Requires -PSEdition Core

# Use these parameters to customize the deployment instead of modifying the default parameter values
[CmdletBinding()]
Param(
	[ValidateSet('eastus2', 'eastus')]
	[string]$Location = 'eastus',
	# The environment descriptor
	[ValidateSet('TEST', 'DEMO', 'PROD')]
	[string]$Environment = 'TEST',
	#
	[Parameter(Mandatory = $true)]
	[string]$WorkloadName,
	#
	[int]$Sequence = 1,
	[string]$NamingConvention = "{wloadname}-{env}-{rtype}-{loc}-{seq}",
	[Parameter(Mandatory)]
	[string]$TargetSubscription,
	[Parameter(Mandatory)]
	[PSCustomObject]$Tags,
	[Parameter(Mandatory = $true)]
	[string]$MySQLVersion,
	[Parameter(Mandatory = $true)]
	[securestring]$DbAdminPassword,
	[Parameter(Mandatory = $true)]
	[string]$DatabaseName,
	[Parameter(Mandatory = $true)]
	[int]$VNetAddressSpaceOctet4Min,
	[Parameter(Mandatory = $true)]
	[string]$VNetAddressSpace,
	[Parameter(Mandatory = $true)]
	[int]$VNetCidr,
	[Parameter(Mandatory = $true)]
	[int]$SubnetCidr,
	[Parameter(Mandatory = $true)]
	[string]$WebHostName,
	[Parameter(Mandatory = $true)]
	[string]$ApiHostName,
	[bool]$DeployComputeRg = $false,
	[PSCustomObject]$ApiAppSettings = @{},
	[PSCustomObject]$WebAppSettings = @{},
	[string]$DeveloperPrincipalId,
	[string]$VmLocalUserName = 'AzureUser',
	[Parameter(Mandatory)]
	[securestring]$VmLocalPassword,
	[bool]$IntuneMdmRegister = $true,
	[bool]$DeveloperVmLoginAsAdmin = $false,
	[Parameter(Mandatory)]
	[string]$VMComputerName,
	[securestring]$PfxFilePassword = (ConvertTo-SecureString -AsPlainText -Force 'Azure123456!'),
	[bool]$ImportPfx = $false,
	[string]$PfxFilePath = 'contoso-com.pfx',
	[string]$KeyVaultCertificateName = 'demo-certificate',
	[bool]$DeployRedis = $false,
	[string]$CoreSubscriptionId = '',
	[string]$CoreDnsZoneResourceGroupName = '',
	[string]$ApiAppSettingsSecretsFileName = '',
	[string]$CurrentHostIpAddress = ''
)

Select-AzSubscription $TargetSubscription

[string]$CertificateSecretId = ''
[string]$CertificateName = ''

# If a certificate needs to be imported to help configure the Application Gateway
if ($ImportPfx -And $PfxFilePath.Length -gt 0) {
	# Find the current public IP of the system to allow access to Key Vault
	if ($CurrentHostIpAddress.Length -eq 0) {
		$CurrentHostIpAddress = (Invoke-WebRequest -Uri "https://api.ipify.org/").Content
	}

	Write-Warning "`nEnabling access to Key Vault from IP '$CurrentHostIpAddress'. This will be removed during the next deployment but if the next deployment fails, you'll need to reconfigure the Key Vault network restrictions manually.`n".ToUpper()

	# Find the AAD Object ID of the Azure context to enable access to KV
	$CertificatesOfficerPrincipalId = (Get-AzContext).Account.ExtendedProperties.HomeAccountId.Split('.')[0]

	# The Key Vault must be created now instead of in main.bicep
	$KvOnlyTemplateParameters = @{
		# REQUIRED
		location                       = $Location
		environment                    = $Environment
		workloadName                   = $WorkloadName
		kvAllowedIpAddress             = $CurrentHostIpAddress
		certificatesOfficerPrincipalId = $CertificatesOfficerPrincipalId

		# OPTIONAL
		sequence                       = $Sequence
		namingConvention               = $NamingConvention
		tags                           = $Tags
	}

	$KeyVaultDeploymentResult = New-AzDeployment -Location $Location -Name "$WorkloadName-$Environment-KvOnly-$(Get-Date -Format 'yyyyMMddThhmmssZ' -AsUTC)" `
		-TemplateFile ".\main-kvonly.bicep" -TemplateParameterObject $KvOnlyTemplateParameters

	$KeyVaultDeploymentResult

	if ($KeyVaultDeploymentResult.ProvisioningState -eq 'Succeeded') {
		# Use PowerShell to import the PFX file
		$KeyVaultName = $KeyVaultDeploymentResult.Outputs.keyVaultName.Value

		$Cert = Get-AzKeyVaultCertificate -VaultName $KeyVaultName -Name $KeyVaultCertificateName

		if (! $Cert) {
			Write-Verbose "Adding certificate to Key Vault..."
			$Cert = Import-AzKeyVaultCertificate -VaultName $KeyVaultName -Name $KeyVaultCertificateName -FilePath $PfxFilePath -Password $PfxFilePassword
		}
		else {
			# LATER: Determine if it's the same cert based on thumbprint of the PFX file. If not, create a new version.
			Write-Verbose "Certificate already exists in Key Vault (thumbprint: '$($Cert.Thumbprint)')."
		}

		$CertSecretArray = $Cert.SecretId.Split('/')
		# Don't use the secret version for App Gateway, so it will automatically get a new version of the certificate
		$CertificateSecretId = $CertSecretArray[0..($CertSecretArray.Count - 1)] -Join '/'
		$CertificateName = $Cert.Name
		Write-Verbose "Using certificate info '$($CertificateName): $CertificateSecretId' (thumbprint: $($Cert.Thumbprint))"
	}
}

# Create an object of secrets and read secret values from files as necesary
[hashtable]$ApiAppSecretValues = Get-Content -Raw $ApiAppSettingsSecretsFileName | ConvertFrom-Json -AsHashtable
[string]$ReadFromFilePropertyName = 'readFromFile'

foreach ($key in $ApiAppSecretValues.Keys) {
	if ($ApiAppSecretValues[$key].ContainsKey($ReadFromFilePropertyName)) {
		# Create or update the value property with the contents of the file
		$ApiAppSecretValues[$key].value = Get-Content -Raw $ApiAppSecretValues[$key][$ReadFromFilePropertyName]
		# Remove the readFromFile property because Bicep can't use it anyway
		$ApiAppSecretValues[$key].Remove($ReadFromFilePropertyName)
	}
}

[hashtable]$TemplateParameters = @{
	# REQUIRED
	location                     = $Location
	environment                  = $Environment
	workloadName                 = $WorkloadName

	mySqlVersion                 = $MySQLVersion
	databaseName                 = $DatabaseName
	dbAdminPassword              = $DbAdminPassword
	vNetAddressSpaceOctet4Min    = $VNetAddressSpaceOctet4Min
	vNetAddressSpace             = $VNetAddressSpace
	vNetCidr                     = $VNetCidr
	subnetCidr                   = $SubnetCidr
	apiHostName                  = $ApiHostName
	webHostName                  = $WebHostName
	vmLocalUserName              = $VmLocalUserName
	vmLocalPassword              = $VmLocalPassword
	intuneMdmRegister            = $IntuneMdmRegister
	developerVmLoginAsAdmin      = $DeveloperVmLoginAsAdmin
	VMComputerName               = $VMComputerName
	kvCertificateSecretId        = $CertificateSecretId
	kvCertificateName            = $CertificateName
	configureAppGwTls            = ($CertificateName.Length -gt 0)
	apiAppSettingsSecrets        = $ApiAppSecretValues

	# OPTIONAL
	developerPrincipalId         = $DeveloperPrincipalId
	apiAppSettings               = $ApiAppSettings
	webAppSettings               = $WebAppSettings
	deployRedis                  = $DeployRedis
	coreSubscriptionId           = $CoreSubscriptionId
	coreDnsZoneResourceGroupName = $CoreDnsZoneResourceGroupName

	sequence                     = $Sequence
	namingConvention             = $NamingConvention
	tags                         = $Tags
}

# Perform the ARM deployment
$DeploymentResult = New-AzDeployment -Location $Location -Name "$WorkloadName-$Environment-$(Get-Date -Format 'yyyyMMddThhmmssZ' -AsUTC)" `
	-TemplateFile ".\main.bicep" -TemplateParameterObject $TemplateParameters

$DeploymentResult

if ($DeploymentResult.ProvisioningState -eq 'Succeeded') {
	Write-Host "🔥 Azure Resource Manager deployment successful!"

	$AppGwPublicIpAddress = $DeploymentResult.Outputs.appGwPublicIpAddress.Value
	Write-Host "`nFor a quick test, modify your HOSTS file and add the following two entries:`n$($AppGwPublicIpAddress)`t$($ApiHostName)`n$($AppGwPublicIpAddress)`t$($WebHostName)"
	Write-Host "`n(If you used a self-signed certificate, expect certificate warnings from your browser.)"

	[string]$ApiDomainVerificationId = $DeploymentResult.Outputs.apiCustomDomainVerificationId.Value
	[string]$WebDomainVerificationId = $DeploymentResult.Outputs.webCustomDomainVerificationId.Value

	[string]$SplitRegex = '^(.+?)(\.)(.+)'
	[bool]$r = $ApiHostName -match $SplitRegex
	[string]$DomainName = $Matches[3]
	[string]$ApiHostNameOnly = $Matches[1]
	$r = $WebHostName -match $SplitRegex
	[string]$WebHostNameOnly = $Matches[1]
	
	Write-Host "`nTo enable App Service custom domain name verification, create the following entries in the DNS for domain '$DomainName':"
	Write-Host "`tasuid.$ApiHostNameOnly`tTXT`t$ApiDomainVerificationId"
	Write-Host "`tasuid.$WebHostNameOnly`tTXT`t$WebDomainVerificationId`n"

	Write-Warning "`nManual steps:`n`t- Update HOSTS file, if desired (see output above)`n`t- Create database user for API app`n`t- Set custom domain names for App Services and then update the HTTP settings to remove the host name override`n"
}
