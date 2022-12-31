[CmdletBinding()]
Param(
	[Parameter(Position = 1)]
	[string]$DnsName = 'www.contoso.com',
	[Parameter(Position = 2)]
	[string]$Subject = $DnsName,
	[Parameter( Position = 3)]
	[string]$PfxFileName = 'contoso-com.pfx',
	[Parameter( Position = 4)]
	[securestring]$PfxPassword = (ConvertTo-SecureString -AsPlainText -Force 'Azure123456!')
)

[string]$CertStoreLocation = 'cert:\currentuser\my'

$Cert = New-SelfSignedCertificate -DnsName $DnsName -CertStoreLocation $CertStoreLocation `
	-FriendlyName "Azure App Gateway sample self-signed" -Subject $Subject `
	-KeyExportPolicy Exportable

[string]$Thumbprint = $Cert.Thumbprint

Export-PfxCertificate -Cert "$CertStoreLocation\$Thumbprint" -Password $PfxPassword `
	-FilePath $PfxFileName

Write-Verbose "Created certificate $PfxFileName with thumbprint '$Thumbprint'"