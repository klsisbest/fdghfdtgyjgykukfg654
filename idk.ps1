function Invoke-RunAsSystem {
    param([string]$Command)
    
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
        [DllImport("user32.dll", SetLastError=true)]
        public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
        [DllImport("kernel32.dll", SetLastError=true)]
        public static extern IntPtr GetConsoleWindow();
    }
"@

    $systemPid = (Get-Process -Name winlogon -ErrorAction SilentlyContinue)[0].Id
    if (-not $systemPid) {
        Write-Error "[!] No se encontró winlogon"
        return
    }
    
    Write-Host "[*] Proceso SYSTEM (winlogon) PID: $systemPid"
    
    $hToken = 0
    [WinAPI]::OpenProcessToken(
        (Get-Process -Id $systemPid).Handle,
        0x0008 -bor 0x0002 -bor 0x0004,
        [ref]$hToken
    ) | Out-Null
    
    $dupToken = 0
    [WinAPI]::DuplicateTokenEx(
        $hToken,
        0x001F0FFF,
        [IntPtr]::Zero,
        2,
        1,
        [ref]$dupToken
    ) | Out-Null
    
    [WinAPI]::CloseHandle($hToken) | Out-Null
    
    if ($dupToken -eq 0) {
        Write-Error "[!] No se pudo duplicar el token"
        return
    }
    
    Write-Host "[*] Token duplicado correctamente"
    
    # --- Crear proceso VISIBLE ---
    if ($Command) {
        $cmdLine = "powershell.exe -NoProfile -ExecutionPolicy Bypass -Command `"$Command`""
    } else {
        # Abrir CMD como SYSTEM visible
        $cmdLine = "cmd.exe /k echo [SISTEMA] & whoami & echo. & echo Ejecuta comandos como SYSTEM & echo Escribe 'exit' para salir"
    }
    
    Write-Host "[*] Creando proceso visible como SYSTEM..."
    
    # STARTUPINFO para ventana visible
    $startupInfo = [System.Runtime.InteropServices.Marshal]::AllocHGlobal(68)
    [System.Runtime.InteropServices.Marshal]::WriteInt32($startupInfo, 68)  # cb
    
    # Flag para mostrar ventana normalmente
    [System.Runtime.InteropServices.Marshal]::WriteInt32($startupInfo + 44, 0x00000001)  # dwFlags = STARTF_USESHOWWINDOW
    [System.Runtime.InteropServices.Marshal]::WriteInt16($startupInfo + 48, 1)  # wShowWindow = SW_SHOWNORMAL (1)
    
    $pi = 0
    $success = [WinAPI]::CreateProcessAsUser(
        $dupToken,
        $null,
        $cmdLine,
        [IntPtr]::Zero,
        [IntPtr]::Zero,
        $false,
        0x00000010,  # CREATE_NEW_CONSOLE (para que tenga su propia ventana)
        [IntPtr]::Zero,
        $null,
        $startupInfo,
        [ref]$pi
    )
    
    [System.Runtime.InteropServices.Marshal]::FreeHGlobal($startupInfo)
    [WinAPI]::CloseHandle($dupToken) | Out-Null
    
    if ($success) {
        $processId = [System.Runtime.InteropServices.Marshal]::ReadInt32($pi + 16)
        Write-Host "[+] ✅ PROCESO SYSTEM CREADO CON ÉXITO"
        Write-Host "[+] PID: $processId"
        Write-Host "[+] Deberías ver una nueva ventana abierta"
        Write-Host "[*] Si no ves la ventana, revisa que tengas permisos de Administrador"
    } else {
        Write-Error "[!] Falló al crear el proceso. Error: $([System.Runtime.InteropServices.Marshal]::GetLastWin32Error())"
        Write-Host "[*] Posibles causas:"
        Write-Host "    - No ejecutas como Administrador"
        Write-Host "    - El token de SYSTEM no es válido"
        Write-Host "    - Antivirus bloqueando la creación"
    }
}
