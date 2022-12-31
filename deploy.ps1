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
	[securestring]$DbAppSvcLogin,
	[Parameter(Mandatory = $true)]
	[securestring]$DbAppSvcPassword,
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
	[Parameter(Mandatory)]
	[securestring]$VmLocalPassword,
	[bool]$IntuneMdmRegister = $true,
	[bool]$DeveloperVmLoginAsAdmin = $false,
	[Parameter(Mandatory)]
	[string]$VMComputerName,
	[securestring]$PfxFilePassword = (ConvertTo-SecureString -AsPlainText -Force 'Azure123456!'),
	[bool]$ImportPfx = $false,
	[string]$PfxFilePath = 'contoso-com.pfx',
	[string]$KeyVaultCertificateName = 'demo-certificate'
)

Select-AzSubscription $TargetSubscription

[string]$CertificateSecretId = ''
[string]$CertificateName = ''

# If a certificate needs to be imported to help configure the Application Gateway
if ($ImportPfx -And $PfxFilePath.Length -gt 0) {
	# Find the current public IP of the system to allow access to Key Vault
	$CurrentHostIpAddress = (Invoke-WebRequest -uri "https://api.ipify.org/").Content
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
			Write-Verbose "Adding demo certificate to Key Vault..."
			$Cert = Import-AzKeyVaultCertificate -VaultName $KeyVaultName -Name $KeyVaultCertificateName -FilePath $PfxFilePath -Password $PfxFilePassword
		}
		else {
			Write-Verbose "Demo certificate already exists in Key Vault."
		}

		$CertSecretArray = $Cert.SecretId.Split('/')
		$CertificateSecretId = $CertSecretArray[0..($CertSecretArray.Count - 1)] -Join '/'
		$CertificateName = $Cert.Name
		Write-Verbose "Using certificate info '$($CertificateName): $CertificateSecretId'"
	}
}

$TemplateParameters = @{
	# REQUIRED
	location                  = $Location
	environment               = $Environment
	workloadName              = $WorkloadName

	mySqlVersion              = $MySQLVersion
	databaseName              = $DatabaseName
	dbAdminPassword           = $DbAdminPassword
	dbAppsvcLogin             = $DbAppSvcLogin
	dbAppSvcPassword          = $DbAppSvcPassword
	vNetAddressSpaceOctet4Min = $VNetAddressSpaceOctet4Min
	vNetAddressSpace          = $VNetAddressSpace
	vNetCidr                  = $VNetCidr
	subnetCidr                = $SubnetCidr
	apiHostName               = $ApiHostName
	webHostName               = $WebHostName
	vmLocalPassword           = $VmLocalPassword
	intuneMdmRegister         = $IntuneMdmRegister
	developerVmLoginAsAdmin   = $DeveloperVmLoginAsAdmin
	VMComputerName            = $VMComputerName
	kvCertificateSecretId     = $CertificateSecretId
	kvCertificateName         = $CertificateName
	configureAppGwTls         = ($CertificateName.Length -gt 0)

	# OPTIONAL
	developerPrincipalId      = $DeveloperPrincipalId
	apiAppSettings            = $ApiAppSettings
	webAppSettings            = $WebAppSettings

	sequence                  = $Sequence
	namingConvention          = $NamingConvention
	tags                      = $Tags
}

$DeploymentResult = New-AzDeployment -Location $Location -Name "$WorkloadName-$Environment-$(Get-Date -Format 'yyyyMMddThhmmssZ' -AsUTC)" `
	-TemplateFile ".\main.bicep" -TemplateParameterObject $TemplateParameters

$DeploymentResult

if ($DeploymentResult.ProvisioningState -eq 'Succeeded') {
	Write-Host "🔥 Azure Resource Manager deployment successful!"
}
