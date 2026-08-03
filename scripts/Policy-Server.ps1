param([int]$Port = 843)
$listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, $Port)
$listener.Start()
try {
    while ($true) {
        $client = $listener.AcceptTcpClient()
        try {
            $stream = $client.GetStream()
            $buffer = New-Object byte[] 1024
            [void]$stream.Read($buffer, 0, $buffer.Length)
            $policy = '<cross-domain-policy><allow-access-from domain="*" to-ports="*" /></cross-domain-policy>' + [char]0
            $bytes = [Text.Encoding]::UTF8.GetBytes($policy)
            $stream.Write($bytes, 0, $bytes.Length)
        } finally { $client.Dispose() }
    }
} finally { $listener.Stop() }
