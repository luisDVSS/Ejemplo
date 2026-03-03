Import-Module WebAdministration
Set-ItemProperty "IIS:\Sites\FTP" -name ftpServer.security.ssl.controlChannelPolicy -value 0
Set-ItemProperty "IIS:\Sites\FTP" -name ftpServer.security.ssl.dataChannelPolicy -value 0