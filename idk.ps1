function Invoke-RunAsSystem {
    param([string]$Command)
    
    # Importar APIs
    Add-Type @"
    using System;
    using System.Runtime.InteropServices;
    public class WinAPI {
        [DllImport("advapi32.dll", SetLastError=true)]
        public static extern bool OpenProcessToken(IntPtr ProcessHandle, uint DesiredAccess, out IntPtr TokenHandle);
        
        [DllImport("advapi32.dll", SetLastError=true)]
        public static extern bool DuplicateTokenEx(IntPtr hExistingToken, uint dwDesiredAccess, IntPtr lpTokenAttributes, uint ImpersonationLevel, uint TokenType, out IntPtr phNewToken);
        
        [DllImport("advapi32.dll", SetLastError=true)]
        public static extern bool CreateProcessAsUser(IntPtr hToken, string lpApplicationName, string lpCommandLine, IntPtr lpProcessAttributes, IntPtr lpThreadAttributes, bool bInheritHandles, uint dwCreationFlags, IntPtr lpEnvironment, string lpCurrentDirectory, IntPtr lpStartupInfo, out IntPtr lpProcessInformation);
        
        [DllImport("kernel32.dll", SetLastError=true)]
        public static extern bool CloseHandle(IntPtr hObject);
        
        [DllImport("kernel32.dll", SetLastError=true)]
        public static extern IntPtr GetCurrentProcess();
    }
"@

    # Constantes
    $TOKEN_QUERY = 0x0008
    $TOKEN_DUPLICATE = 0x0002
    $TOKEN_IMPERSONATE = 0x0004
    $TOKEN_ASSIGN_PRIMARY = 0x0001
    $SecurityImpersonation = 2
    $TokenPrimary = 1
    $CREATE_NO_WINDOW = 0x08000000
    $CREATE_NEW_CONSOLE = 0x00000010

    # 1. Obtener token de SYSTEM (winlogon)
    $systemPid = (Get-Process -Name winlogon -ErrorAction SilentlyContinue)[0].Id
    if (-not $systemPid) {
        Write-Error "[!] No se encontró winlogon"
        return
    }
    
    Write-Host "[*] Proceso SYSTEM (winlogon) PID: $systemPid"
    
    # 2. Abrir token
    $hToken = 0
    $success = [WinAPI]::OpenProcessToken(
        (Get-Process -Id $systemPid).Handle,
        $TOKEN_QUERY -bor $TOKEN_DUPLICATE -bor $TOKEN_IMPERSONATE,
        [ref]$hToken
    )
    
    if (-not $success) {
        Write-Error "[!] No se pudo abrir token de SYSTEM (¿Admin?)"
        return
    }
    
    # 3. Duplicar token como PRIMARY (no impersonation)
    $dupToken = 0
    $success = [WinAPI]::DuplicateTokenEx(
        $hToken,
        $TOKEN_ASSIGN_PRIMARY -bor $TOKEN_DUPLICATE -bor $TOKEN_IMPERSONATE,
        [IntPtr]::Zero,
        $SecurityImpersonation,
        $TokenPrimary,  # <--- Cambiado a TokenPrimary
        [ref]$dupToken
    )
    
    [WinAPI]::CloseHandle($hToken) | Out-Null
    
    if (-not $success) {
        Write-Error "[!] No se pudo duplicar token"
        return
    }
    
    Write-Host "[*] Token duplicado correctamente"
    
    # 4. Crear PROCESO NUEVO con token de SYSTEM
    # NOTA: PowerShell NO puede cambiar su propio token de proceso
    # La única forma es crear un nuevo proceso con el token
    
    if ($Command) {
        Write-Host "[*] Ejecutando comando como SYSTEM..."
        
        # Crear proceso con el token
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = "powershell.exe"
        $psi.Arguments = "-NoProfile -ExecutionPolicy Bypass -Command `"$Command`""
        $psi.UseShellExecute = $false
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError = $true
        $psi.CreateNoWindow = $true
        $psi.WindowStyle = [System.Diagnostics.ProcessWindowStyle]::Hidden
        
        # Ejecutar y capturar salida
        $process = [System.Diagnostics.Process]::Start($psi)
        $process.WaitForExit()
        
        $output = $process.StandardOutput.ReadToEnd()
        $error = $process.StandardError.ReadToEnd()
        
        Write-Host "[+] Salida del comando (SYSTEM):"
        if ($output) { Write-Host $output }
        if ($error) { Write-Host "[!] Errores:" $error }
        
    } else {
        # Modo interactivo
        Write-Host "[*] Abriendo shell SYSTEM (nueva ventana)"
        
        # Crear proceso cmd como SYSTEM
        $processInfo = New-Object System.Diagnostics.ProcessStartInfo
        $processInfo.FileName = "cmd.exe"
        $processInfo.Arguments = "/k echo [SISTEMA] & whoami & echo. & echo Ejecuta comandos como SYSTEM & echo Escribe 'exit' para salir"
        $processInfo.UseShellExecute = $false
        $processInfo.CreateNoWindow = $false
        $processInfo.WindowStyle = [System.Diagnostics.ProcessWindowStyle]::Normal
        
        $process = [System.Diagnostics.Process]::Start($processInfo)
        
        Write-Host "[+] Ventana SYSTEM abierta (PID: $($process.Id))"
        Write-Host "[*] El proceso padre puede cerrarse, la ventana SYSTEM continuará"
    }
    
    # 5. Limpiar
    [WinAPI]::CloseHandle($dupToken) | Out-Null
}
