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
	[string]$VMComputerName
)

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

	# OPTIONAL
	developerPrincipalId      = $DeveloperPrincipalId
	apiAppSettings            = $ApiAppSettings
	webAppSettings            = $WebAppSettings

	sequence                  = $Sequence
	namingConvention          = $NamingConvention
	tags                      = $Tags
}

Select-AzSubscription $TargetSubscription

$DeploymentResult = New-AzDeployment -Location $Location -Name "$WorkloadName-$Environment-$(Get-Date -Format 'yyyyMMddThhmmssZ' -AsUTC)" `
	-TemplateFile ".\main.bicep" -TemplateParameterObject $TemplateParameters

$DeploymentResult

if ($DeploymentResult.ProvisioningState -eq 'Succeeded') {
	Write-Host "🔥 Azure Resource Manager deployment successful!"
}
