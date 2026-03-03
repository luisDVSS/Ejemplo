function pasarA{
	param(
	[string]$url,
	[string]$urld,
	[string]$user,
	[string]$ip
	)
$destino="$user@$ip`:$urld"

scp -r "$url" "$destino"
	}
