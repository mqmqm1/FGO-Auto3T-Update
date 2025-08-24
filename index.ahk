#Include *i %A_ScriptDir%\plugin\ImagePut.ahk
#Include *i %A_ScriptDir%\plugin\RapidOCR\RapidOCR.ahk
#SingleInstance force

global win                       ; 定义全局变量 win
   win := WinGetID("模拟器") ; 获取窗口 ID


; ========== 偏移与缩放处理 ==========
class OffsetHandler {
    static dx := 0
    static dy := 0
    static baseWidth := 1920    ;基本宽度
    static baseHeight := 1080   ;基本高度
    static scaleX := 1.0
    static scaleY := 1.0

    static UpdateScale() {
        global win
        WinGetClientPos(&x, &y, &w, &h, win)
        OffsetHandler.scaleX := w / OffsetHandler.baseWidth
        OffsetHandler.scaleY := h / OffsetHandler.baseHeight
        
    }

    static Apply(x, y) {
        return {
            x: Round(x * OffsetHandler.scaleX) + OffsetHandler.dx,
            y: Round(y * OffsetHandler.scaleY) + OffsetHandler.dy + 6   ; 6 是为了补偿窗口标题栏的高度
        }
    }


    static SetOffsetFromGUI(dx, dy) {
        OffsetHandler.dx := dx
        OffsetHandler.dy := dy  
    }
}




; ========== 鼠标操作类 ==========
class MouseHandler          ; 鼠标操作类
{
    static Click(x, y, sleepTime := 100) {
        global win
        ControlClick("x" x " y" y, win,,,,"NA") ;后台点击
        Sleep sleepTime
    }

    static ClientClick(x, y, sleepTime := 500) {
        global win
        pos := OffsetHandler.Apply(x, y)
        ControlClick("x" pos.x " y" pos.y, win,,,, "NA")
       
        Sleep sleepTime
        
    }
    
}

; ========== OCR文字识别类 ==========
class OCRHandler
{
    static ocr := ""  ; 缓存 OCR 对象，避免每次重复初始化

    ; 初始化 OCR，仅加载一次，提高性能
    static InitOCR() {
        if (OCRHandler.ocr = "") {
            OCRHandler.ocr := RapidOcr(
                {models: A_ScriptDir "\plugin\RapidOCR\models"}, 
                A_ScriptDir "\plugin\RapidOcr\64bit\RapidOcrOnnx.dll"
            )
        }
        return OCRHandler.ocr
    }

    ; 底层统一识别逻辑：一次性识别所有 BattlePage.png 上的 targetText 坐标
    static FindTextCoords(targetText) {
        ; 截图
        ImagePutFile("联想模拟器", "BattlePage.png")

        ; 初始化 OCR
        local ocr := OCRHandler.InitOCR()
        local res := ocr.ocr_from_file("BattlePage.png", , true)

        ; 防止崩溃：如果识别失败或结果为空，直接返回空数组
        if !IsObject(res) || res.Length = 0 {
            return []
        }

        ; 存储所有匹配到的坐标
        coords := []
        for block in res {
            if (block.text = targetText) {
                x1 := block.boxPoint[1].x
                y1 := block.boxPoint[1].y
                x2 := block.boxPoint[3].x
                y2 := block.boxPoint[3].y
                coords.Push({x: (x1 + x2) // 2, y: (y1 + y2) // 2})
            }
        }

        ; 如果有多个匹配结果，按 X 坐标升序排序（左到右点击）
        if (coords.Length > 1) {
            coords := OCRHandler.SortByX(coords)
        }

        return coords
    }

    ; 获取第一个匹配目标的坐标（兼容旧版 ocrRecognize 调用）
    static ocrRecognize(targetText) {
        coords := OCRHandler.FindTextCoords(targetText)
        return coords.Length > 0 ? coords[1] : false
    }

    ; 获取所有匹配目标的坐标（兼容旧版 ocrRecognizeAll 调用）
    static ocrRecognizeAll(targetText) {
        return OCRHandler.FindTextCoords(targetText)
    }

    ; 按 X 坐标升序排序
    static SortByX(coords) {
        Loop coords.Length {
            swapped := false
            Loop coords.Length - A_Index {
                i := A_Index
                j := i + 1
                if (coords[i].x > coords[j].x) {
                    tmp := coords[i]
                    coords[i] := coords[j]
                    coords[j] := tmp
                    swapped := true
                }
            }
            if !swapped
                break
        }
        return coords
    }

    static ocrShowText()        ;文字识别展示
    {
        ocr := RapidOcr({models: A_ScriptDir '\plugin\RapidOCR\models'}, A_ScriptDir '\plugin\RapidOcr\64bit\RapidOcrOnnx.dll')  ; 初始化 OCR
        ImagePutFile("联想模拟器", "TestOCR.png")  ; 截取游戏窗口
        res := ocr.ocr_from_file("TestOCR.png", , true)  ; 识别文本

        if res.Length = 0{ 
        
            MsgBox "OCR 没有识别到任何文本！"
        } 
            else {   
            
                allText := "OCR 识别的文本：`n"
            
                loop res.Length{ 
                
                    block := res[A_Index]
                    allText .= block.text . "`n"  ; 逐行拼接识别的文字
                }
            
        MsgBox allText  ; 显示所有识别的文字
        }   

    }
}


; ========== 战斗操作类 ==========
class CombatActions         ; 战斗操作类
{
    ; 技能坐标表 (角色1, 角色2, 角色3)
    static skillCoords := [
        [[105, 865], [240, 865], [370, 865]],  ; 一号位技能 1, 2, 3
        [[580, 865], [715, 865], [845, 865]],  ; 二号位技能 1, 2, 3
        [[1060, 865], [1190, 865], [1325, 865]]  ; 三号位技能 1, 2, 3
    ]

    static ClickBlank(){
        MouseHandler.ClientClick(920, 405)  ; 点击空白处
        
    }

    static ChooseTarget(targetSlot := 1) {
        ; 1号位: x=480, 2号位: x=955, 3号位: x=1430，y 都是 635
        xPos := [480, 955, 1430]
        if (targetSlot >= 1 && targetSlot <= 3) {
            MouseHandler.ClientClick(xPos[targetSlot], 635)
        } else {
            MouseHandler.ClientClick(480, 635) ; 默认点击1号位
        }
    }
    


    static UseSkill(slot, skill, targetSlot := 0) {
        Logger.Log("释放技能: UseSkill," slot "," skill "," targetSlot)  ; 记录日志""))
        coords := CombatActions.skillCoords[slot][skill]       
        MouseHandler.ClientClick(coords[1], coords[2])  ; 点击技能
    
        if targetSlot >= 1 && targetSlot <= 3 {
            CombatActions.ChooseTarget(targetSlot)
        }
    
        CombatActions.ClickBlank()  ; 点击空白处
        Sleep 500
    }
    

    static Attack() { ; 点击攻击
        Logger.Log("释放技能: Attack")  ; 记录日志"")
        GameManager.WaitForTextAndClick("攻击")
        Sleep 1000  ; 等待1秒，确保界面稳定
    }

    static UseNoblePhantasm(slot) {
        Logger.Log("释放技能: UseNoblePhantasm," slot)  ; 记录日志"")
        static positions := [620, 950, 1275]  ; 宝具1/2/3 的 X 坐标
        if (slot >= 1 && slot <= 3) {
            MouseHandler.ClientClick(positions[slot], 310)  ; 点击宝具图标
            MouseHandler.ClientClick(175, 745)              ; 固定攻击键位置1
            MouseHandler.ClientClick(570, 745)              ; 固定攻击键位置2
        } else {
            MsgBox "错误：宝具位置无效"
        }
    }
    
    ; 固定希耶尔在2号位
static CIEL(order) {
    

    ; 宝具固定位置
    local cielX := 950   ; 2号位宝具X坐标
    local cielY := 310

    ; 一次性识别所有“力击”坐标，避免重复点同一张卡
    local busterCards := OCRHandler.ocrRecognizeAll("力击")
    local busterIndex := 1  ; 记录当前点击的Buster卡索引

    for idx, step in order {
        step := StrUpper(step)

        switch step {
            case "2":  ; 宝具
                MouseHandler.ClientClick(cielX, cielY)
                Logger.Log("执行CIEL宝具")
                Sleep 200
                
            case "B":  ; 点击下一张Buster卡
            {
                maxRetries := 30  ; 最多重试30次
                retryCount := 0

                ; 如果Buster卡不够，就重试几次
                while (busterIndex > busterCards.Length && retryCount < maxRetries) {
                    Logger.Log("Buster卡不足,正在重新识别... 尝试 #" retryCount+1)
                    Sleep 1000  ; 给OCR一点时间
                    busterCards := OCRHandler.ocrRecognizeAll("力击")  ; 重新识别
                    retryCount++
                }

                ; 再次判断是否有足够的卡
                if (busterIndex <= busterCards.Length) {
                    local card := busterCards[busterIndex]
                    MouseHandler.Click(card.x, card.y)
                    busterIndex++
                    Logger.Log("Buster释放")
                    Sleep 500
                } else {
                    Logger.Log("未找到足够的Buster卡,跳过此步骤")
                }
            }


            default:
                Logger.Log("未知CIEL步骤: " step)
        }
    }
}



    static MasterSkill_Atlas(targetSlot := 1) {
        Logger.Log("释放技能: MasterSkill_Atlas," targetSlot)  ; 记录日志"")
        MouseHandler.ClientClick(1785, 465)  ; 打开御主技能
        Sleep 500
        MouseHandler.ClientClick(1623, 465)  ; 选择 Atlas 技能
        Sleep 500
        CombatActions.ChooseTarget(targetSlot)  ; 选择目标
        CombatActions.ClickBlank()
        GameManager.WaitForText("攻击")
    }

    static MasterSkill_Change(frontIndex := 1, backIndex := 1) { ; 换人服
        Logger.Log("释放技能: MasterSkill_Change," frontIndex "," backIndex)  ; 记录日志"")
        MouseHandler.ClientClick(1785, 465)  ; Master Skill 释放
        Sleep 500
        MouseHandler.ClientClick(1623, 465)
        Sleep 500

        ; 换人界面坐标映射
        frontCoords := [200, 500, 800]  ; 前排1~3
        backCoords := [1100, 1400, 1700] ; 后排1~3
        y := 520

        MouseHandler.ClientClick(frontCoords[frontIndex], y)
        Sleep 500
        MouseHandler.ClientClick(backCoords[backIndex], y)
        Sleep 500

        MouseHandler.ClientClick(960, 930)
        CombatActions.ClickBlank()
        GameManager.WaitForText("攻击")
    }

    static MasterSkill_AllBuff() { ; 换人服全体攻击力
        Logger.Log("释放技能: MasterSkill_AllBuff")  ; 记录日志"")
        
        MouseHandler.ClientClick(1785, 465)
        Sleep 500
        MouseHandler.ClientClick(1355, 465)
        CombatActions.ClickBlank()
        GameManager.WaitForText("攻击")
    }

}


; ========== 游戏管理类 ==========
class GameManager       ; 游戏管理类
{  
    static WaitForTextAndClick(targetText,timeoutMs := 200000) {
        Logger.Log("等待并点击: " targetText)  ; 记录日志"")
        startTime := A_TickCount  ; 记录开始时间
        loop {
            if !isRunning
                return
            coords := OCRHandler.ocrRecognize(targetText)  ; 调用 OCR 识别目标文本
            if coords {  ; 如果找到目标文本
                MouseHandler.Click(coords.x, coords.y)  ; 点击识别到的坐标
                return true  ; 识别并点击成功，返回 true
            }
            if (A_TickCount - startTime > timeoutMs) {  ; 检查是否超时
                return false  ; 超时未找到目标文本，返回 false
            }
            Sleep 500  ; 没找到就等待 500ms 继续循环
        }
    }
   

    static WaitForText(targetText,timeoutMs := 100000) {
        Logger.Log("等待: " targetText)  ; 记录日志"")
        startTime := A_TickCount  ; 记录开始时间
        loop {
            if !isRunning
                return
            coords := OCRHandler.ocrRecognize(targetText)  ; 调用 OCR 识别目标文本
            if coords {  ; 如果找到目标文本
               Sleep 300
                return true  
            }
            if (A_TickCount - startTime > timeoutMs) {  ; 检查是否超时
                return false  ; 超时未找到目标文本，返回 false
            }
            Sleep 500  ; 没找到就等待 500ms 继续循环
        }
    }
 
}
   

; ========== 读取技能配置 ==========
LoadAndExecuteSkillsFromTxt(roundName){     ;读取技能配置.txt文件
    Logger.Log("加载技能配置: " roundName)  ; 记录日志"")
local path := A_ScriptDir "\skill_config.txt"   ; 配置文件路径(相对脚本所在路径)
    if !FileExist(path) {
        MsgBox "找不到配置文件: " path
        return
    }

    fileContent := FileRead(path)

    lines := StrSplit(fileContent, "`n")  ; 正确处理换行符

    isTargetRound := false
    loop parse, FileRead(path), "`n", "`r" {    ; 回车符和换行符，遍历每一行
        line := Trim(A_LoopField)   ; 去除行首尾空格
        if line = "" || SubStr(line, 1, 1) = ";"  ; 跳过空行和注释
            continue


       

        ; 回合标记处理
        if InStr(line, "# " roundName) {    
        isTargetRound := true
            continue
        } else if !isTargetRound {
            continue
        } else if SubStr(line, 1, 1) = "#" {  ; 下一回合开始
            break
        }

        
        parts := StrSplit(line, ",")
        cmd := Trim(parts[1])
        try {
            switch cmd {
                case "UseSkill":
                    if !isRunning           ;检查停止标记
                        return

                    ; 配置格式: UseSkill,slot,skill,target
                    slot := Integer(parts[2])
                    skill := Integer(parts[3])
                    targetSlot := (parts.Length >= 4) ? Integer(parts[4]) : 0
                    CombatActions.UseSkill(slot, skill, targetSlot)

                    GameManager.WaitForText("攻击") ; 等待攻击文本出现,防止卡时延
                    if !isRunning
                        return

                case "Attack":

                    if !isRunning
                        return

                    ; 配置格式: Attack
                    CombatActions.Attack()

                    if !isRunning
                        return

                case "UseNoblePhantasm":
                    slot := Integer(parts[2])
                    CombatActions.UseNoblePhantasm(slot)

                    if !isRunning
                        return

                case "CIEL":
                    ; 配置格式: CIEL,step1,step2,step3
                    if (parts.Length < 4) {
                        MsgBox "错误: CIEL 指令格式不正确 → " line
                        return
                    }

                    ; 提取顺序
                    step1 := parts[2]
                    step2 := parts[3]
                    step3 := parts[4]

                    ; 调用 CombatActions 模块
                    CombatActions.CIEL([step1, step2, step3])    

                default:
                    if HasMethod(CombatActions,cmd) {   ; 检查是否为 CombatActions 类的方法

                        if !isRunning
                            return

                        if (cmd = "MasterSkill_Change" && parts.Length >= 3) {
                            arg1 := Integer(parts[2])
                            arg2 := Integer(parts[3])
                            CombatActions.MasterSkill_Change(arg1, arg2)
                        }


                        ; 特判冷却服等有 1 个参数的情况（若需要）
                        else if (parts.Length >= 2) {
                                CombatActions.%cmd%(Integer(parts[2]))
                            }
                        ; 默认无参调用
                        else {
                                CombatActions.%cmd%()
                            }

                            if !isRunning
                                return
                    } else {
                        MsgBox "未知指令: " cmd
                    }
            }
        } catch as e {
            MsgBox "执行失败: " line "`n错误: " e.Message
        }
        
    }

  }  
    

; ========== 读取助战配置 ==========
GetSupportServantNameFromTxt() {        ;读取助战配置文件
    Logger.Log("读取助战配置文件")  ; 记录日志"")
    local path := A_ScriptDir "\skill_config.txt"

        if !FileExist(path) {
        MsgBox "找不到配置文件: " path
    return ""
}

file := FileOpen(path, "r", "UTF-8")    ; 以 UTF-8 编码打开文件，防止乱码
if !IsObject(file) {
    MsgBox "无法以 UTF-8 打开配置文件"
    return ""
}

for line in StrSplit(file.Read(), "`n", "`r") {
    line := Trim(line)
        if line = "" || SubStr(line, 1, 1) = ";"
            continue

        if InStr(line, "SupportName,") {
            parts := StrSplit(line, ",")
        if parts.Length >= 2
            return Trim(parts[2])
    }
}

return ""  ; 找不到就返回空字符串

}

; ========== 选择助战配置 ==========
SelectSupport(servantName) {
    Logger.Log("选择助战: " servantName)  ; 记录日志"")

    if !isRunning
        return
    GameManager.WaitForText("助战选择")
    if !isRunning
        return
    Loop 10 {
        coords := OCRHandler.ocrRecognize(servantName)
        if coords {
            MouseHandler.Click(coords.x, coords.y)
            Sleep 2000
            return
        } else {
            GameManager.WaitForTextAndClick("列表更新")
            GameManager.WaitForTextAndClick("是")
        }
    }
    ;MsgBox "未找到助战角色: " servantName
}
   

UseFruit(fruitName){    
    Logger.Log("使用果实: " fruitName)  ; 记录日志"")
    switch fruitName {
        case "黄金果实":
            if OCRHandler.ocrRecognize("黄金果实") {
        if !isRunning
            return
        GameManager.WaitForTextAndClick("黄金果实")
        if !isRunning
            return
        GameManager.WaitForTextAndClick("决定")
        if !isRunning
            return
        Sleep 3000
    }
        case "白银果实":
            if OCRHandler.ocrRecognize("白银果实") {
            if !isRunning
                return
            GameManager.WaitForTextAndClick("白银果实")
            if !isRunning
                return
            GameManager.WaitForTextAndClick("决定")
            if !isRunning
                return
            Sleep 3000
        }
        case "青铜果实":
            MouseHandler.ClientClick(700,845)  ; 点击青铜果实
        if !isRunning
            return
        GameManager.WaitForTextAndClick("决定")
        if !isRunning
            return
        Sleep 3000
    }

}  
