# Script para monitorar PID do processo antes e depois do taskkill
# Autor: Script para monitoramento de respawn de processos
# Data: $(Get-Date)
# Vers�o: 2.0 - Com configura��o din�mica via PID

param(
    [switch]$config
)

# Criar diret�rio de logs se n�o existir
$logsDir = ".\logs"
if (-not (Test-Path $logsDir)) {
    New-Item -ItemType Directory -Path $logsDir -Force | Out-Null
    Write-Host "Diret�rio de logs criado: $logsDir"
}

# Arquivo de configura��o
$configFile = "$logsDir\process_config.json"

# Fun��o para registrar logs com timestamp
function Write-Log {
    param($Message, $Type = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss.fff"
    $logEntry = "[$timestamp] [$Type] $Message"
    Write-Host $logEntry
    $logEntry | Out-File -FilePath "$logsDir\process_monitor.log" -Append -Encoding UTF8
}

# Fun��o para configurar o processo alvo via PID
function Set-ProcessConfiguration {
    Write-Host "`n=== CONFIGURA��O DO PROCESSO ALVO ===" -ForegroundColor Yellow
    Write-Host "Este modo permite configurar qual processo monitorar baseado em um PID existente." -ForegroundColor White
    Write-Host "O script ir� extrair o CommandLine do PID informado e usar como padr�o de busca." -ForegroundColor White
    Write-Host "=========================================" -ForegroundColor Yellow
    
    do {
        $pidInput = Read-Host "`nDigite o PID do processo que deseja monitorar"
        
        if ([string]::IsNullOrWhiteSpace($pidInput)) {
            Write-Host "PID n�o pode estar vazio. Tente novamente." -ForegroundColor Red
            continue
        }
        
        if (-not ($pidInput -match '^\d+$')) {
            Write-Host "PID deve ser um n�mero v�lido. Tente novamente." -ForegroundColor Red
            continue
        }
        
        $targetPid = [int]$pidInput
        
        try {
            Write-Host "Buscando processo com PID: $targetPid..." -ForegroundColor Cyan
            
            # Obter informa��es do processo via PID
            $processInfo = Get-CimInstance Win32_Process -Filter "ProcessId = $targetPid" -ErrorAction Stop
            
            if (-not $processInfo) {
                Write-Host "Processo com PID $targetPid n�o encontrado. Tente novamente." -ForegroundColor Red
                continue
            }
            
            # Extrair informa��es do processo
            $commandLine = $processInfo.CommandLine
            $processName = $processInfo.Name
            $executablePath = $processInfo.ExecutablePath
            
            Write-Host "`n=== INFORMA��ES DO PROCESSO ENCONTRADO ===" -ForegroundColor Green
            Write-Host "PID: $targetPid" -ForegroundColor White
            Write-Host "Nome: $processName" -ForegroundColor White
            Write-Host "Execut�vel: $executablePath" -ForegroundColor White
            Write-Host "Linha de Comando:" -ForegroundColor White
            Write-Host "  $commandLine" -ForegroundColor Gray
            Write-Host "=============================================" -ForegroundColor Green
            
            if ([string]::IsNullOrWhiteSpace($commandLine)) {
                Write-Host "`nAVISO: O processo n�o possui CommandLine detect�vel." -ForegroundColor Yellow
                Write-Host "Isso pode acontecer com processos do sistema ou com permiss�es restritas." -ForegroundColor Yellow
                
                $useProcessName = Read-Host "Deseja usar o nome do processo ($processName) como padr�o de busca? (S/N)"
                if ($useProcessName -match '^[Ss]') {
                    $commandLine = $processName
                    Write-Host "Configura��o definida para buscar por nome do processo: $processName" -ForegroundColor Green
                } else {
                    Write-Host "Configura��o cancelada pelo usu�rio." -ForegroundColor Red
                    continue
                }
            }
            
            # Confirmar configura��o
            Write-Host "`nEste padr�o ser� usado para encontrar o processo durante o monitoramento." -ForegroundColor Cyan
            $confirm = Read-Host "Confirma esta configura��o? (S/N)"
            
            if ($confirm -match '^[Ss]') {
                # Salvar configura��o
                $config = @{
                    ConfiguredAt = Get-Date -Format "yyyy-MM-dd HH:mm:ss.fff"
                    ConfiguredBy = $env:USERNAME
                    Computer = $env:COMPUTERNAME
                    SourcePID = $targetPid
                    ProcessName = $processName
                    ExecutablePath = $executablePath
                    CommandLinePattern = $commandLine
                    SearchMethod = if ([string]::IsNullOrWhiteSpace($processInfo.CommandLine)) { "ProcessName" } else { "CommandLine" }
                }
                
                $config | ConvertTo-Json -Depth 2 | Out-File -FilePath $configFile -Encoding UTF8
                
                Write-Host "`n=== CONFIGURA��O SALVA COM SUCESSO ===" -ForegroundColor Green
                Write-Host "Arquivo: $configFile" -ForegroundColor White
                Write-Host "Padr�o de busca: $commandLine" -ForegroundColor White
                Write-Host "M�todo: $($config.SearchMethod)" -ForegroundColor White
                Write-Host "====================================" -ForegroundColor Green
                
                Write-Host "`nAgora voc� pode executar o script normalmente para monitorar este tipo de processo." -ForegroundColor Cyan
                Write-Host "Exemplo: .\script.ps1" -ForegroundColor White
                
                return $true
            } else {
                Write-Host "Configura��o cancelada pelo usu�rio." -ForegroundColor Yellow
                continue
            }
            
        } catch {
            Write-Host "Erro ao acessar o processo PID $targetPid : $($_.Exception.Message)" -ForegroundColor Red
            Write-Host "Verifique se o PID existe e se voc� tem permiss�es adequadas." -ForegroundColor Yellow
            continue
        }
        
    } while ($true)
    
    return $false
}

# Fun��o para carregar configura��o
function Get-ProcessConfiguration {
    if (-not (Test-Path $configFile)) {
        Write-Host "Arquivo de configura��o n�o encontrado: $configFile" -ForegroundColor Red
        Write-Host "Execute o script com par�metro -config para configurar o processo alvo." -ForegroundColor Yellow
        Write-Host "Exemplo: .\script.ps1 -config" -ForegroundColor White
        return $null
    }
    
    try {
        $config = Get-Content $configFile -Raw | ConvertFrom-Json
        Write-Log "Configura��o carregada: $configFile" "CONFIG"
        Write-Log "Padr�o de busca: $($config.CommandLinePattern)" "CONFIG"
        Write-Log "M�todo de busca: $($config.SearchMethod)" "CONFIG"
        return $config
    } catch {
        Write-Log "Erro ao carregar configura��o: $($_.Exception.Message)" "ERROR"
        return $null
    }
}

# Fun��o para encontrar o processo baseado na configura��o
function Find-TargetProcess {
    param($Config)
    
    if (-not $Config) {
        return $null
    }
    
    try {
        if ($Config.SearchMethod -eq "ProcessName") {
            # Buscar por nome do processo
            $targetProcess = Get-CimInstance -ClassName Win32_Process | Where-Object {
                $_.Name -eq $Config.CommandLinePattern
            }
        } else {
            # Buscar por padr�o na linha de comando
            $targetProcess = Get-CimInstance -ClassName Win32_Process | Where-Object {
                $_.CommandLine -like "*$($Config.CommandLinePattern)*"
            }
        }
        
        return $targetProcess
        
    } catch {
        Write-Log "Erro ao buscar processo: $($_.Exception.Message)" "ERROR"
        return $null
    }
}

# Fun��o para coletar informa��es de CPU e Mem�ria
function Get-ProcessPerformance {
    param($ProcessInfo)
    
    try {
        # Obter informa��es do processo via Get-Process para CPU
        $process = Get-Process -Id $ProcessInfo.ProcessId -ErrorAction SilentlyContinue
        
        if ($process) {
            # Calcular uso de CPU (requer duas medi��es)
            $cpu1 = $process.CPU
            Start-Sleep -Milliseconds 500
            $process = Get-Process -Id $ProcessInfo.ProcessId -ErrorAction SilentlyContinue
            $cpu2 = $process.CPU
            $cpuUsage = if ($cpu2 -gt $cpu1) { [math]::Round(($cpu2 - $cpu1) * 2, 2) } else { 0 }
            
            $performance = @{
                # CPU Information
                CPUUsagePercent = $cpuUsage
                TotalProcessorTime = [math]::Round($process.TotalProcessorTime.TotalSeconds, 2)
                
                # Memory Information (em MB)
                WorkingSetMB = [math]::Round($process.WorkingSet / 1MB, 2)
                VirtualMemoryMB = [math]::Round($ProcessInfo.VirtualSize / 1MB, 2)
                PagedMemoryMB = [math]::Round($process.PagedMemorySize / 1MB, 2)
                NonPagedMemoryMB = [math]::Round($process.NonpagedSystemMemorySize / 1MB, 2)
                PrivateMemoryMB = [math]::Round($process.PrivateMemorySize / 1MB, 2)
                PageFileUsageMB = [math]::Round($ProcessInfo.PageFileUsage / 1MB, 2)
                
                # Additional Info
                HandleCount = $process.HandleCount
                ThreadCount = $process.Threads.Count
                PriorityClass = $process.PriorityClass
            }
        } else {
            $performance = @{
                CPUUsagePercent = "N/A"
                TotalProcessorTime = "N/A"
                WorkingSetMB = [math]::Round($ProcessInfo.WorkingSetSize / 1MB, 2)
                VirtualMemoryMB = [math]::Round($ProcessInfo.VirtualSize / 1MB, 2)
                PagedMemoryMB = "N/A"
                NonPagedMemoryMB = "N/A"
                PrivateMemoryMB = "N/A"
                PageFileUsageMB = [math]::Round($ProcessInfo.PageFileUsage / 1MB, 2)
                HandleCount = "N/A"
                ThreadCount = "N/A"
                PriorityClass = "N/A"
            }
        }
        
        return $performance
    } catch {
        Write-Log "Erro ao coletar informa��es de performance: $($_.Exception.Message)" "WARNING"
        return @{
            CPUUsagePercent = "ERROR"
            WorkingSetMB = "ERROR"
            VirtualMemoryMB = "ERROR"
        }
    }
}

# Fun��o para exibir informa��es de performance nos logs
function Show-Performance {
    param($Performance, $Phase)
    
    Write-Log "=== INFORMA��ES DE CPU E MEM�RIA - $Phase ===" "PERFORMANCE"
    Write-Log "CPU Usage: $($Performance.CPUUsagePercent)%" "PERFORMANCE"
    Write-Log "Total CPU Time: $($Performance.TotalProcessorTime)s" "PERFORMANCE"
    Write-Log "Working Set (RAM): $($Performance.WorkingSetMB) MB" "PERFORMANCE"
    Write-Log "Virtual Memory: $($Performance.VirtualMemoryMB) MB" "PERFORMANCE"
    Write-Log "Paged Memory: $($Performance.PagedMemoryMB) MB" "PERFORMANCE"
    Write-Log "Non-Paged Memory: $($Performance.NonPagedMemoryMB) MB" "PERFORMANCE"
    Write-Log "Private Memory: $($Performance.PrivateMemoryMB) MB" "PERFORMANCE"
    Write-Log "Page File Usage: $($Performance.PageFileUsageMB) MB" "PERFORMANCE"
    Write-Log "Handle Count: $($Performance.HandleCount)" "PERFORMANCE"
    Write-Log "Thread Count: $($Performance.ThreadCount)" "PERFORMANCE"
    Write-Log "Priority Class: $($Performance.PriorityClass)" "PERFORMANCE"
    Write-Log "===============================================" "PERFORMANCE"
}

# ===== MAIN EXECUTION =====

# Verificar se est� em modo de configura��o
if ($config) {
    Write-Host "MODO DE CONFIGURA��O ATIVADO" -ForegroundColor Cyan
    $configResult = Set-ProcessConfiguration
    if (-not $configResult) {
        Write-Host "Configura��o n�o foi conclu�da." -ForegroundColor Red
        exit 1
    }
    exit 0
}

# In�cio do script de monitoramento
Write-Log "=== INICIANDO MONITORAMENTO DE PROCESSO ===" "START"
Write-Log "Usu�rio: $env:USERNAME | Computador: $env:COMPUTERNAME" "INFO"

try {
    # Carregar configura��o
    $processConfig = Get-ProcessConfiguration
    if (-not $processConfig) {
        Write-Log "N�o foi poss�vel carregar a configura��o. Execute com -config primeiro." "ERROR"
        exit 1
    }
    
    Write-Log "Configura��o carregada - Padr�o: $($processConfig.CommandLinePattern)" "CONFIG"
    
    # ===== FASE 1: BUSCAR PROCESSO ANTES DO TASKKILL =====
    Write-Log "Procurando processo alvo..." "SEARCH"
    
    $processBeforeKill = Find-TargetProcess -Config $processConfig
    
    if (-not $processBeforeKill) {
        Write-Log "Processo alvo n�o encontrado. Encerrando monitoramento." "ERROR"
        Write-Log "Padr�o de busca: $($processConfig.CommandLinePattern)" "ERROR"
        exit 1
    }
    
    # Registrar evid�ncias ANTES do taskkill
    $pidBefore = $processBeforeKill.ProcessId
    $commandLine = $processBeforeKill.CommandLine
    $creationTime = $processBeforeKill.CreationDate
    
    Write-Log "=== PID REGISTRADO ANTES DO TASKKILL ===" "CRITICAL"
    Write-Log "PID: $pidBefore" "CRITICAL"
    Write-Log "Comando: $commandLine" "CRITICAL"
    Write-Log "Criado em: $creationTime" "CRITICAL"
    Write-Log "============================================" "CRITICAL"
    
    # Coletar informa��es de CPU e Mem�ria ANTES do taskkill
    Write-Log "Coletando informa��es de performance..." "COLLECT"
    $performanceBefore = Get-ProcessPerformance -ProcessInfo $processBeforeKill
    Show-Performance -Performance $performanceBefore -Phase "ANTES DO TASKKILL"
    
    # Salvar evid�ncia pr�-taskkill
    $evidenceBefore = @{
        Phase = "BEFORE_TASKKILL"
        Configuration = $processConfig
        PID = $pidBefore
        ProcessName = $processBeforeKill.Name
        CommandLine = $commandLine
        CreationDate = $creationTime
        ParentPID = $processBeforeKill.ParentProcessId
        ExecutablePath = $processBeforeKill.ExecutablePath
        Performance = $performanceBefore
        Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss.fff"
    }
    
    $evidenceFile = "$logsDir\process_pid_before_taskkill_$(Get-Date -Format 'yyyyMMdd_HHmmss').json"
    $evidenceBefore | ConvertTo-Json -Depth 4 | Out-File -FilePath $evidenceFile -Encoding UTF8
    Write-Log "Evid�ncia PR�-TASKKILL salva: $evidenceFile" "SAVE"
    
    # ===== FASE 2: EXECUTAR TASKKILL =====
    Write-Log "Executando taskkill no PID: $pidBefore" "TASKKILL"
    
    $taskkillTime = Get-Date
    $taskkillResult = taskkill /F /PID $pidBefore 2>&1
    
    Write-Log "Comando executado: taskkill /F /PID $pidBefore" "TASKKILL"
    Write-Log "Resultado: $taskkillResult" "TASKKILL"
    Write-Log "Hor�rio do taskkill: $($taskkillTime.ToString('yyyy-MM-dd HH:mm:ss.fff'))" "TASKKILL"
    
    # ===== FASE 3: AGUARDAR 20 SEGUNDOS E MONITORAR =====
    Write-Log "Aguardando 20 segundos para verificar respawn..." "MONITOR"
    
    for ($i = 1; $i -le 20; $i++) {
        Start-Sleep -Seconds 1
        Write-Log "Monitoramento: $i/20 segundos" "MONITOR"
    }
    
    # ===== FASE 4: VERIFICAR SE PROCESSO RESPAWNOU =====
    Write-Log "Verificando se processo respawnou..." "SEARCH"
    
    $processAfterKill = Find-TargetProcess -Config $processConfig
    
    if ($processAfterKill) {
        $pidAfter = $processAfterKill.ProcessId
        $newCreationTime = $processAfterKill.CreationDate
        
        Write-Log "=== PROCESSO RESPAWNOU - NOVO PID DETECTADO ===" "CRITICAL"
        Write-Log "PID Original: $pidBefore" "CRITICAL"
        Write-Log "NOVO PID: $pidAfter" "CRITICAL"
        Write-Log "Nova cria��o: $newCreationTime" "CRITICAL"
        Write-Log "Comando: $($processAfterKill.CommandLine)" "CRITICAL"
        Write-Log "===============================================" "CRITICAL"
        
        # Coletar informa��es de CPU e Mem�ria do processo respawnado
        Write-Log "Coletando performance do processo respawnado..." "COLLECT"
        $performanceAfter = Get-ProcessPerformance -ProcessInfo $processAfterKill
        Show-Performance -Performance $performanceAfter -Phase "DEPOIS DO RESPAWN"
        
        # Salvar evid�ncia p�s-taskkill (respawn detectado)
        $evidenceAfter = @{
            Phase = "AFTER_TASKKILL_RESPAWN"
            Configuration = $processConfig
            OriginalPID = $pidBefore
            NewPID = $pidAfter
            ProcessName = $processAfterKill.Name
            CommandLine = $processAfterKill.CommandLine
            OriginalCreationDate = $creationTime
            NewCreationDate = $newCreationTime
            ParentPID = $processAfterKill.ParentProcessId
            ExecutablePath = $processAfterKill.ExecutablePath
            PerformanceBefore = $performanceBefore
            PerformanceAfter = $performanceAfter
            TaskkillTime = $taskkillTime.ToString('yyyy-MM-dd HH:mm:ss.fff')
            RespawnDetectedTime = Get-Date -Format "yyyy-MM-dd HH:mm:ss.fff"
            MonitoringDuration = "20 segundos"
        }
        
        $respawnFile = "$logsDir\process_pid_after_respawn_$(Get-Date -Format 'yyyyMMdd_HHmmss').json"
        $evidenceAfter | ConvertTo-Json -Depth 4 | Out-File -FilePath $respawnFile -Encoding UTF8
        Write-Log "Evid�ncia P�S-TASKKILL (RESPAWN) salva: $respawnFile" "SAVE"
        
    } else {
        Write-Log "=== PROCESSO N�O RESPAWNOU ===" "SUCCESS"
        Write-Log "PID Original: $pidBefore foi terminado com sucesso" "SUCCESS"
        Write-Log "Nenhum novo processo detectado ap�s 20 segundos" "SUCCESS"
        Write-Log "=============================" "SUCCESS"
        
        # Salvar evid�ncia p�s-taskkill (sem respawn)
        $evidenceAfter = @{
            Phase = "AFTER_TASKKILL_NO_RESPAWN"
            Configuration = $processConfig
            OriginalPID = $pidBefore
            NewPID = "N/A"
            ProcessName = $processBeforeKill.Name
            CommandLine = $commandLine
            OriginalCreationDate = $creationTime
            PerformanceBefore = $performanceBefore
            PerformanceAfter = "N/A - Processo n�o respawnou"
            TaskkillTime = $taskkillTime.ToString('yyyy-MM-dd HH:mm:ss.fff')
            VerificationTime = Get-Date -Format "yyyy-MM-dd HH:mm:ss.fff"
            MonitoringDuration = "20 segundos"
            Status = "PROCESSO_TERMINADO_DEFINITIVAMENTE"
        }
        
        $noRespawnFile = "$logsDir\process_pid_no_respawn_$(Get-Date -Format 'yyyyMMdd_HHmmss').json"
        $evidenceAfter | ConvertTo-Json -Depth 4 | Out-File -FilePath $noRespawnFile -Encoding UTF8
        Write-Log "Evid�ncia P�S-TASKKILL (SEM RESPAWN) salva: $noRespawnFile" "SAVE"
    }
    
} catch {
    Write-Log "Erro durante execu��o: $($_.Exception.Message)" "ERROR"
    Write-Log "Stack Trace: $($_.Exception.StackTrace)" "ERROR"
} finally {
    Write-Log "=== MONITORAMENTO CONCLU�DO ===" "END"
    Write-Log "Log completo: $logsDir\process_monitor.log" "INFO"
}

# Resumo final
Write-Host "`n=== RESUMO DO MONITORAMENTO ===" -ForegroundColor Yellow
Write-Host "Data/Hora: $(Get-Date)" -ForegroundColor White
Write-Host "Usu�rio: $env:USERNAME" -ForegroundColor White
Write-Host "Computador: $env:COMPUTERNAME" -ForegroundColor White
Write-Host "Configura��o: $configFile" -ForegroundColor White
Write-Host "Log principal: $logsDir\process_monitor.log" -ForegroundColor White
Write-Host "Evid�ncias: Arquivos JSON no diret�rio $logsDir" -ForegroundColor White
Write-Host "===============================" -ForegroundColor Yellow