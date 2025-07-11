# Sistema COPEC com Guardian - PowerShell Version
param([string]$Mode = "")

# Definir variáveis
$SITE_NAME = "COPEC-Application"
$APP_POOL = "COPEC-AppPool" 
$SITE_PATH = "C:\inetpub\wwwroot\COPEC"
$PORT = 8080
$MONITOR_LOG = "$SITE_PATH\system.log"
$GUARDIAN_PID_FILE = "$SITE_PATH\guardian.pid"
$COPEC_PID_FILE = "$SITE_PATH\copec_app.pid"
$COPEC_SCRIPT = "$SITE_PATH\copec_worker.ps1"

function Test-Administrator {
    $currentUser = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($currentUser)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Write-Log {
    param([string]$Message)
    $timestamp = Get-Date -Format "MM/dd/yyyy HH:mm:ss"
    $logMessage = "$timestamp - $Message"
    Write-Host $logMessage
    try {
        Add-Content -Path $MONITOR_LOG -Value $logMessage -ErrorAction SilentlyContinue
    } catch {}
}

function Test-CopecWorker {
    try {
        $workerProcesses = Get-Process | Where-Object { $_.MainWindowTitle -eq "COPEC-Application-Worker" }
        if ($workerProcesses) {
            Write-Log "COPEC Worker encontrado por titulo PID: $($workerProcesses[0].Id)"
            return $true
        }
    } catch {}
    
    if (Test-Path $COPEC_PID_FILE) {
        try {
            $pidFromFile = Get-Content $COPEC_PID_FILE -ErrorAction SilentlyContinue
            if ($pidFromFile -and (Get-Process -Id $pidFromFile -ErrorAction SilentlyContinue)) {
                Write-Log "COPEC Worker encontrado por arquivo PID: $pidFromFile"
                return $true
            }
        } catch {}
    }
    
    return $false
}

function Get-CopecWorkerPid {
    $workerPid = "Inativo"
    $workerStatus = "Parado"
    
    try {
        $workerProcesses = Get-Process | Where-Object { $_.MainWindowTitle -eq "COPEC-Application-Worker" }
        if ($workerProcesses) {
            $workerPid = $workerProcesses[0].Id
            $workerStatus = "Ativo"
            Write-Log "COPEC Worker PID por titulo: $workerPid"
            return @{ PID = $workerPid; Status = $workerStatus }
        }
    } catch {}
    
    if (Test-Path $COPEC_PID_FILE) {
        try {
            $pidFromFile = Get-Content $COPEC_PID_FILE -ErrorAction SilentlyContinue
            if ($pidFromFile) {
                $process = Get-Process -Id $pidFromFile -ErrorAction SilentlyContinue
                if ($process) {
                    $workerPid = $pidFromFile
                    $workerStatus = "Ativo (Arquivo)"
                    Write-Log "COPEC PID do arquivo: $pidFromFile"
                } else {
                    $workerPid = "$pidFromFile (morto)"
                    $workerStatus = "Processo Morto"
                    Write-Log "PID do arquivo morto: $pidFromFile"
                }
            }
        } catch {}
    }
    
    return @{ PID = $workerPid; Status = $workerStatus }
}

function Start-CopecWorker {
    Write-Log "Iniciando COPEC Worker"
    
    try {
        Get-Process | Where-Object { $_.MainWindowTitle -eq "COPEC-Application-Worker" } | ForEach-Object {
            Write-Log "Encerrando processo COPEC Worker PID: $($_.Id)"
            Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue
        }
    } catch {}
    
    Start-Sleep -Seconds 2
    
    Write-Log "Criando novo COPEC Worker..."
    try {
        $scriptPath = "`"$COPEC_SCRIPT`""
        Start-Process -FilePath "powershell.exe" -ArgumentList "-WindowStyle Minimized -ExecutionPolicy Bypass -File $scriptPath" -WindowStyle Minimized
        Start-Sleep -Seconds 3
        Write-Log "COPEC Worker iniciado com sucesso"
    } catch {
        Write-Log "Erro ao iniciar COPEC Worker: $($_.Exception.Message)"
    }
}

function New-CopecWorkerScript {
    $scriptContent = @'
# COPEC Application Worker Process
$Host.UI.RawUI.WindowTitle = "COPEC-Application-Worker"

$SITE_NAME = "COPEC-Application"
$MONITOR_LOG = "C:\inetpub\wwwroot\COPEC\system.log"
$GUARDIAN_PID_FILE = "C:\inetpub\wwwroot\COPEC\guardian.pid"
$COPEC_PID_FILE = "C:\inetpub\wwwroot\COPEC\copec_app.pid"

function Write-WorkerLog {
    param([string]$Message)
    $timestamp = Get-Date -Format "MM/dd/yyyy HH:mm:ss"
    try {
        Add-Content -Path $MONITOR_LOG -Value "$timestamp - [WORKER] $Message" -ErrorAction SilentlyContinue
    } catch {}
}

try {
    $PID | Out-File -FilePath $COPEC_PID_FILE -Encoding ASCII
    Write-WorkerLog "COPEC Application Worker iniciado - PID: $PID"
} catch {}

while ($true) {
    if (Test-Path $GUARDIAN_PID_FILE) {
        try {
            $guardianPid = Get-Content $GUARDIAN_PID_FILE -ErrorAction SilentlyContinue
            if ($guardianPid -and !(Get-Process -Id $guardianPid -ErrorAction SilentlyContinue)) {
                Write-WorkerLog "Guardian morreu, encerrando COPEC Application"
                break
            }
        } catch {}
    }
    
    try {
        Get-Date -Format "HH:mm:ss" | Out-File -FilePath "$COPEC_PID_FILE.heartbeat" -Encoding ASCII
    } catch {}
    
    try {
        $appCmdPath = "$env:windir\system32\inetsrv\appcmd.exe"
        $siteResult = & $appCmdPath list site $SITE_NAME 2>$null
        if ($siteResult -notlike '*Started*') {
            Write-WorkerLog "Site IIS parado, tentando reiniciar"
            & $appCmdPath start site $SITE_NAME 2>$null
        }
    } catch {
        Write-WorkerLog "Erro ao verificar status do site IIS"
    }
    
    Start-Sleep -Seconds 3
}

Write-WorkerLog "COPEC Application Worker finalizando"
'@
    
    try {
        $scriptContent | Out-File -FilePath $COPEC_SCRIPT -Encoding UTF8
        Write-Log "COPEC Worker script criado!"
    } catch {
        Write-Log "Erro ao criar Worker script: $($_.Exception.Message)"
    }
}

function New-CopecHtml {
    param(
        [string]$WorkerPid = "Inicializando",
        [string]$WorkerStatus = "Configurando", 
        [string]$LastCheck = "Aguardando"
    )
    
    $htmlContent = @"
<!DOCTYPE html>
<html>
<head>
    <title>COPEC - Sistema Online</title>
    <meta http-equiv="refresh" content="30">
    <style>
        body { font-family: Arial; text-align: center; margin-top: 50px; background: linear-gradient(135deg, #667eea 0%, #764ba2 100%); color: white; }
        .container { max-width: 700px; margin: 0 auto; background: rgba(255,255,255,0.1); padding: 40px; border-radius: 15px; box-shadow: 0 8px 32px rgba(31, 38, 135, 0.37); backdrop-filter: blur(4px); border: 1px solid rgba(255,255,255,0.18); }
        .logo { font-size: 48px; color: #fff; font-weight: bold; margin-bottom: 20px; text-shadow: 2px 2px 4px rgba(0,0,0,0.3); }
        .status { color: #00ff88; margin: 20px; font-size: 18px; font-weight: bold; }
        .guardian { background: rgba(40, 167, 69, 0.2); padding: 15px; border-radius: 8px; margin: 20px 0; border: 1px solid #28a745; }
        .process-info { background: rgba(0, 123, 255, 0.2); padding: 15px; border-radius: 8px; margin: 20px 0; border: 1px solid #007bff; }
        .info { margin: 10px; color: #f8f9fa; }
        .footer { margin-top: 30px; padding-top: 20px; border-top: 1px solid rgba(255,255,255,0.3); color: #adb5bd; font-size: 12px; }
        .blink { animation: blink 1s linear infinite; }
        .dots-container { margin: 15px 0; }
        .dots { display: inline-block; font-size: 24px; }
        .dot1 { animation: dotBlink 1.5s infinite; }
        .dot2 { animation: dotBlink 1.5s infinite 0.3s; }
        .dot3 { animation: dotBlink 1.5s infinite 0.6s; }
        .dot4 { animation: dotBlink 1.5s infinite 0.9s; }
        .dot5 { animation: dotBlink 1.5s infinite 1.2s; }
        @keyframes blink { 0% { opacity: 1; } 50% { opacity: 0.5; } 100% { opacity: 1; } }
        @keyframes dotBlink { 0% { opacity: 0.3; color: #666; } 50% { opacity: 1; color: #00ff88; } 100% { opacity: 0.3; color: #666; } }
    </style>
    <script>
        function updateTime() {
            document.getElementById('current-time').innerHTML = new Date().toLocaleString('pt-BR');
        }
        setInterval(updateTime, 1000);
        window.onload = updateTime;
    </script>
</head>
<body>
    <div class="container">
        <div class="logo">COPEC</div>
        <div class="status blink">Sistema Online e Funcionando</div>
        <div class="guardian">
            <strong>Guardian System</strong>
            <div class="dots-container">
                <span class="dots dot1">C</span>
                <span class="dots dot2">O</span>
                <span class="dots dot3">P</span>
                <span class="dots dot4">E</span>
                <span class="dots dot5">C</span>
            </div>
            Status: Monitoramento Ativo
        </div>
        <div class="process-info">
            <strong>COPEC Application Status</strong>
            <br>PID da Aplicacao COPEC: $WorkerPid
            <br>Status: $WorkerStatus
            <br>Ultima Verificacao: $LastCheck
            <br><small>Protegido por Guardian System</small>
        </div>
        <div class="info">Servidor: IIS/Windows</div>
        <div class="info">Porta: $PORT</div>
        <div class="info">Aplicacao: $SITE_NAME</div>
        <div class="info">Host: $env:COMPUTERNAME</div>
        <div class="info">Data/Hora: <span id="current-time"></span></div>
        <div class="footer">
            Usuario: $env:USERNAME | Host: $env:COMPUTERNAME<br>
            Sistema COPEC v4.0 PowerShell - Guardian Protected<br>
            Release: 09/07/2025 - PowerShell Edition
        </div>
    </div>
</body>
</html>
"@
    
    try {
        $htmlContent | Out-File -FilePath "$SITE_PATH\index.html" -Encoding UTF8
    } catch {
        Write-Log "Erro ao criar HTML: $($_.Exception.Message)"
    }
}

function Update-CopecHtml {
    $workerInfo = Get-CopecWorkerPid
    $currentTime = Get-Date -Format "HH:mm:ss"
    
    New-CopecHtml -WorkerPid $workerInfo.PID -WorkerStatus $workerInfo.Status -LastCheck $currentTime
    Write-Log "HTML atualizado - PID:$($workerInfo.PID) Status:$($workerInfo.Status)"
}

function Start-Guardian {
    $Host.UI.RawUI.WindowTitle = "COPEC System Monitor"
    Write-Log "Guardian iniciado (PowerShell Mode)"
    
    try {
        $PID | Out-File -FilePath $GUARDIAN_PID_FILE -Encoding ASCII
        Write-Log "Guardian PID: $PID"
    } catch {}
    
    Write-Log "Iniciando COPEC Worker Process"
    Start-CopecWorker
    
    Update-CopecHtml
    
    $downCount = 0
    $updateCycle = 0
    
    while ($true) {
        if (!(Test-CopecWorker)) {
            Write-Log "COPEC Worker morreu, reiniciando..."
            Start-CopecWorker
            Update-CopecHtml
        }
        
        $poolStatus = $false
        $siteStatus = $false
        $httpStatus = $false
        
        try {
            $appCmd = "$env:windir\system32\inetsrv\appcmd.exe"
            $poolResult = & $appCmd list apppool $APP_POOL 2>$null
            $poolStatus = $poolResult -like "*Started*"
            
            $siteResult = & $appCmd list site $SITE_NAME 2>$null
            $siteStatus = $siteResult -like "*Started*"
            
            $httpResponse = Invoke-WebRequest -Uri "http://localhost:$PORT" -TimeoutSec 3 -ErrorAction Stop
            $httpStatus = $httpResponse.StatusCode -eq 200
        } catch {}
        
        if (!$poolStatus -or !$siteStatus -or !$httpStatus) {
            $downCount++
            Write-Log "Servico DOWN - Contador: $downCount/3"
            
            if ($downCount -ge 3) {
                Write-Log "REINICIANDO SERVICOS IIS"
                
                try {
                    $appCmd = "$env:windir\system32\inetsrv\appcmd.exe"
                    & $appCmd stop site $SITE_NAME 2>$null
                    & $appCmd stop apppool $APP_POOL 2>$null
                    Start-Sleep -Seconds 2
                    
                    & $appCmd start apppool $APP_POOL 2>$null
                    & $appCmd start site $SITE_NAME 2>$null
                    
                    Write-Log "Servicos IIS reiniciados"
                    $downCount = 0
                    Update-CopecHtml
                } catch {
                    Write-Log "Erro ao reiniciar servicos: $($_.Exception.Message)"
                }
            }
        } else {
            if ($downCount -gt 0) {
                Write-Log "Servicos restaurados"
            }
            $downCount = 0
        }
        
        $updateCycle++
        if ($updateCycle -ge 30) {
            Update-CopecHtml
            $updateCycle = 0
        }
        
        Start-Sleep -Seconds 1
    }
}

function Initialize-CopecSystem {
    Write-Host "======================================="
    Write-Host "   CONFIGURACAO COPEC SYSTEM PS1"
    Write-Host "======================================="
    
    if (!(Test-Administrator)) {
        Write-Host "ERRO: Execute como Administrador!" -ForegroundColor Red
        Read-Host "Pressione Enter para sair"
        return
    }
    
    Write-Host "1. Criando diretorio do site..."
    if (!(Test-Path $SITE_PATH)) {
        New-Item -ItemType Directory -Path $SITE_PATH -Force | Out-Null
        Write-Host "   Diretorio criado: $SITE_PATH"
    } else {
        Write-Host "   Diretorio ja existe: $SITE_PATH"
    }
    
    Write-Host "`n2. Criando COPEC Worker Script..."
    New-CopecWorkerScript
    
    Write-Host "`n3. Criando pagina HTML..."
    New-CopecHtml
    Write-Host "   index.html criado com sucesso!"
    
    Write-Host "`n4. Configurando permissoes..."
    try {
        icacls $SITE_PATH /grant "IIS_IUSRS:(OI)(CI)RX" /T /Q 2>$null
        Write-Host "   Permissoes configuradas!"
    } catch {}
    
    Write-Host "`n5. Removendo configuracoes anteriores..."
    $appCmd = "$env:windir\system32\inetsrv\appcmd.exe"
    & $appCmd delete site $SITE_NAME 2>$null
    & $appCmd delete apppool $APP_POOL 2>$null
    Write-Host "   Configuracoes anteriores removidas"
    
    Write-Host "`n6. Criando Application Pool..."
    $result = & $appCmd add apppool /name:$APP_POOL /managedRuntimeVersion:"" 2>$null
    if ($LASTEXITCODE -eq 0) {
        Write-Host "   Application Pool '$APP_POOL' criado!"
    } else {
        Write-Host "   ERRO ao criar Application Pool"
    }
    
    Write-Host "`n7. Criando Site IIS..."
    $bindingString = "http/*:${PORT}:"
    $result = & $appCmd add site /name:$SITE_NAME /physicalPath:$SITE_PATH /bindings:$bindingString 2>$null
    if ($LASTEXITCODE -eq 0) {
        Write-Host "   Site '$SITE_NAME' criado!"
    } else {
        Write-Host "   ERRO ao criar Site"
    }
    
    & $appCmd set site $SITE_NAME /applicationDefaults.applicationPool:$APP_POOL 2>$null
    Write-Host "   Site associado ao Application Pool!"
    
    Write-Host "`n8. Iniciando servicos..."
    try {
        Start-Service W3SVC -ErrorAction SilentlyContinue
        & $appCmd start apppool $APP_POOL 2>$null
        & $appCmd start site $SITE_NAME 2>$null
        Write-Host "   Servicos iniciados!"
    } catch {}
    
    Write-Host "`n9. Verificando status..."
    & $appCmd list site $SITE_NAME
    & $appCmd list apppool $APP_POOL
    
    Write-Host "`n======================================="
    Write-Host "   CONFIGURACAO CONCLUIDA!"
    Write-Host "======================================="
    Write-Host "Site: $SITE_NAME"
    Write-Host "URL: http://localhost:$PORT"
    Write-Host "Caminho: $SITE_PATH"
    Write-Host "======================================="
    
    Write-Host "`n10. Iniciando Guardian Parent Process..."
    
    try {
        Get-Process | Where-Object { $_.MainWindowTitle -eq "COPEC System Monitor" } | ForEach-Object {
            Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue
        }
    } catch {}
    
    try {
        $scriptPath = "`"$PSCommandPath`""
        Start-Process -FilePath "powershell.exe" -ArgumentList "-WindowStyle Minimized -ExecutionPolicy Bypass -File $scriptPath -Mode GUARDIAN" -WindowStyle Minimized
        
        Write-Host "Guardian iniciado!"
        Write-Host "Site publicado e rodando: http://localhost:$PORT"
        
        $openBrowser = Read-Host "`nAbrir no navegador? (S/N)"
        if ($openBrowser -eq "S" -or $openBrowser -eq "s") {
            Start-Process "http://localhost:$PORT"
        }
        
        Write-Host "`nPressione qualquer tecla para sair (Guardian continua rodando)..."
        $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
    } catch {
        Write-Host "Erro ao iniciar Guardian: $($_.Exception.Message)" -ForegroundColor Red
    }
}

# Main execution
if ($Mode -eq "GUARDIAN") {
    Start-Guardian
} else {
    Initialize-CopecSystem
}