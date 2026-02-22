
function Get-ServiceFeature {
    param(
        [Parameter(ValueFromRemainingArguments)]
        [string[]]$Features
    )

    foreach ($feature in $Features) {
        Install-WindowsFeature -Name $feature -IncludeManagementTools -ErrorAction SilentlyContinue | Out-Null
    }
}

function Get-Domains {
    Write-Host ("{0,-30} {1,-15}" -f "DOMINIO", "IP")
    Write-Host ("{0,-30} {1,-15}" -f "------------------------------", "---------------")

    $zones = Get-DnsServerZone | Where-Object { $_.ZoneName -notlike "*.arpa" }

    foreach ($zone in $zones) {
        $record = Get-DnsServerResourceRecord -ZoneName $zone.ZoneName -RRType A -ErrorAction SilentlyContinue |
                  Select-Object -First 1

        if ($record) {
            $ip = $record.RecordData.IPv4Address.IPAddressToString
            Write-Host ("{0,-30} {1,-15}" -f $zone.ZoneName, $ip)
        }
    }
}

function Is-DomainName {
    param([string]$Name)

    $regex = '^[a-zA-Z0-9]+(\-[a-zA-Z0-9]+)?\.[a-zA-Z]{2,}$'
    return $Name -match $regex
}


function Get-ZonaInversa {
    param([string]$Ip)

    if (-not (Is-IpFormat $Ip)) { return $null }

    $o = $Ip.Split('.')
    return "$($o[2]).$($o[1]).$($o[0])"
}


function Reset-Dns {
    Restart-Service DNS -Force
}


function Domain-Exists {
    param([string]$Domain)

    return (Get-DnsServerZone -Name $Domain -ErrorAction SilentlyContinue) -ne $null
}

function Delete-Domain {
    $domain = Read-Host "Dominio a eliminar"

    if (-not (Domain-Exists $domain)) {
        Write-Host "El dominio no existe"
        return
    }

    Remove-DnsServerZone -Name $domain -Force
    Write-Host "Dominio eliminado correctamente"
    Reset-Dns
}
function Set-ConfigDefaultEthernet2 {

    $Interfaz = "Ethernet 2"
    $IP       = "192.168.11.1"
    $Prefijo  = 24
    $Gateway  = "192.168.11.254"
    $DNS      = "192.168.11.1"

    Write-Host "Configurando $Interfaz con valores por defecto..." -ForegroundColor Cyan

    # Verificar que exista la interfaz
    if (-not (Get-NetAdapter -Name $Interfaz -ErrorAction SilentlyContinue)) {
        Write-Host "La interfaz $Interfaz no existe." -ForegroundColor Red
        return
    }

    # Desactivar DHCP
    Set-NetIPInterface -InterfaceAlias $Interfaz -Dhcp Disabled

    # Eliminar IPs previas
    Get-NetIPAddress -InterfaceAlias $Interfaz -AddressFamily IPv4 -ErrorAction SilentlyContinue |
        Remove-NetIPAddress -Confirm:$false

    # Asignar nueva IP
    New-NetIPAddress `
        -InterfaceAlias $Interfaz `
        -IPAddress $IP `
        -PrefixLength $Prefijo `
        -DefaultGateway $Gateway `
        -AddressFamily IPv4

    # Configurar DNS
    Set-DnsClientServerAddress `
        -InterfaceAlias $Interfaz `
        -ServerAddresses $DNS

    Write-Host "SE APLICO UNA CONFIGURACION POR DEFECTO DE RED CON VALORES:"
    Write-Host "Ethernet 2"
    Write-Host "IP=192.168.11.1"
    Write-Host "Prefijo=24"
    Write-Host "Gateway=192.168.11.254"
    Write-Host "DNS=192.168.11.1"
}