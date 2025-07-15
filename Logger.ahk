#Requires AutoHotkey v2.0

class Logger {
    static logFile := ""
    static logDir := A_ScriptDir "\Logs"

    static Init() {
        if !DirExist(Logger.logDir)
            DirCreate(Logger.logDir)

        timestamp := FormatTime(, "yyyy-MM-dd_HH-mm-ss")
        Logger.logFile := Logger.logDir "\log_" timestamp ".txt"
        Logger.Log("日志初始化完成")
    }

    static Log(msg) {
        if Logger.logFile = ""
            return

        timestamp := FormatTime(, "yyyy-MM-dd HH:mm:ss")
        FileAppend("[" timestamp "] " msg "`n", Logger.logFile, "UTF-8")
    }

    static Cleanup(days := 2) {
        cutoff := A_Now
        cutoff := DateAdd(cutoff, -days, "Days")
        cutoff := FormatTime(cutoff, "yyyyMMdd")

        Loop Files Logger.logDir "\log_*.txt" {
            datePart := SubStr(A_LoopFileName, 5, 10) ; "2024-05-01"
            fileDate := StrReplace(datePart, "-", "")
            if fileDate < cutoff {
                FileDelete A_LoopFilePath
            }
        }
    }
}

