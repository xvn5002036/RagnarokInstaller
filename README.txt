Ragnarok 安裝管理中心 v6.0.3 精裝版

啟動方式
1. 完整保留本資料夾內的 Config、Modules 與 Logs 目錄。
2. 雙擊 Start.cmd。
3. 接受 Windows 系統管理員權限提示。

主要路徑
- 安裝根目錄：C:\Server
- rAthena：C:\Server\rAthena
- PandasWS：C:\Server\PandasWS
- WARP：C:\Server\WARP0716
- ROenglishRE：C:\Server\ROenglishRE
- NPC 中文化：C:\Server\rathena-npc-big5
- 玩家管理後台：C:\Server\RathenaPlayerAdmin（由安裝器內建原始碼安裝）

主選單
[1] 安裝 / 更新開發環境
[2] 安裝 / 更新 MariaDB
[3] 更新 rAthena / PandasWS
[4] 編譯目前核心
[5] 還原目前核心為未編譯狀態（通常不需要；會清除伺服器 EXE 與編譯快取，下一次 [4] 會完整編譯）
[6] 更新 WARP
[7] 建立 / 匯入資料庫
[8] 初始化 rAthena 設定
[9] 顯示系統資訊
[A] 開啟 Logs
[L] 清除 Logs
[B] 全部移除
[C] 開啟 C:\Server\rAthena\runserver.bat 啟動並監看伺服器
[H] 停止伺服器
[D] 更新 ROenglishRE
[E] 更新 NPC 腳本中文化
[F] 套用中文化
[G] 一鍵初始化（不自動啟動）
[I] 安裝 / 更新 RathenaPlayerAdmin 玩家管理後台（套用內建最新版並準備 .NET 環境）
[J] 啟動 RathenaPlayerAdmin 玩家管理後台（只啟動，不下載）
[0] 離開

第 3 項官方同步方式
- 選擇 rAthena 時固定同步 https://github.com/rathena/rathena.git 的 master 分支。
- 選擇 PandasWS 時固定同步 https://github.com/PandasWS/Pandas.git 的 master 分支。
- 既有資料夾會先校正 origin 網址，再 fetch 官方最新提交並將已追蹤檔案對齊官方版本。
- 若專案包含 Git 子模組，會同步並更新全部子模組。
- 未追蹤檔案（例如自行新增但尚未加入 Git 的 NPC 腳本）不會被刪除。
- 主畫面上方會顯示核心分支、Commit、提交日期與官方同步狀態；第 3 項完成後可立即確認更新版本。

玩家管理後台
- 後台原始碼收錄於 Tools\RathenaPlayerAdmin；按 [I] 會更新至 C:\Server\RathenaPlayerAdmin，不會覆蓋 rAthena 或 PandasWS 核心。
- 更新安裝器後再按 [I]，即可套用內建的最新版；所需 Microsoft .NET 8 SDK 統一由選項 [1] 管理。
- 選項 [I] 也會在需要時下載 Player Admin 專用的 .NET 8 環境；選項 [J] 只會啟動，不會下載任何檔案。
- 第一次安裝會沿用本安裝器的 MariaDB 主機、連接埠、資料庫與伺服器帳密。
- 後續更新會保留 C:\Server\RathenaPlayerAdmin\local-settings.json，不會用遠端設定覆蓋本機資料庫設定。
- 選項 [J] 會執行獨立專案內的 Start.cmd；準備完成後開啟 http://127.0.0.1:5080。
- 管理介面預設只供本機使用，不要把 5080 連接埠直接公開到網際網路。

開發與執行環境
- Git、Ninja、7-Zip、Python（先驗證實際版本；損壞時強制修復）。
- Microsoft .NET 8 SDK（供 RathenaPlayerAdmin 建置與執行）。
- Python 採無人值守安裝；Chocolatey 來源失效時自動改用 Python 官方安裝程式。
- Python 安裝完成後以非互動模式讀取版本，不會停在 Python 輸入畫面。
- Visual Studio 2022 Build Tools、MSVC v143 與 Windows SDK。
- Visual C++ 2012 x64 Runtime；rAthena 的 pcre8.dll 需要 MSVCR110.dll。
- MariaDB 使用 mariadb.install；損壞安裝會先備份並移開舊 data，再使用 MSI 乾淨修復。

編譯方式
- 使用 rAthena 官方 rAthena.sln。
- Visual Studio 2022 MSBuild，Release | x64。
- 選項 [4] 執行增量 Build：程式修改後直接使用，MSBuild 只會重新編譯已變更和相依檔案，產出與完整編譯相同。選項 [5] 會清除核心根目錄的編譯 EXE / PDB / LIB / EXP 與 `.vs\\build` 快取，讓核心回到未編譯狀態；僅在核心更新、編譯異常或需要完整重建時使用。
- login-server.exe、char-server.exe、map-server.exe、web-server.exe 位於 C:\Server\rAthena。
- 編譯畫面會持續顯示 MSBuild PID、耗時及編譯／連結狀態。

MariaDB 與資料庫
- 主要資料庫：rathenadb
- 紀錄資料庫：rathenalog
- 字元集：utf8mb4
- 排序規則：utf8mb4_unicode_520_ci
- 伺服器資料庫帳號：rathenadbusr
- 伺服器資料庫密碼：froggopass
- 伺服器通訊帳號：froggos1
- 伺服器通訊密碼：froggop1
- GM 帳號：test / test，等級 99

第 7 項說明
- 空資料庫會依指定順序完整匯入 SQL。
- 偵測到現有資料時，直接 Enter 會保留資料並略過基礎 SQL，避免 Duplicate entry。
- 選擇全新重建後仍須輸入 REBUILD，才會清除並重新建立資料庫。
- 本機 MariaDB 連線使用 --ssl=0，避免無密碼 root 的 SSL 警告。

第 8 項說明
- conf\import 不存在時，完整複製 conf\import-tmpl。
- conf\import 已存在時，只補上缺少的範本檔案。
- 所有 conf\import\*.txt 使用 UTF-8 無 BOM，確保第一行能被 rAthena 正確辨識。
- 完整寫入資料庫 IP、Port、帳號、密碼及資料庫名稱。
- 同步設定 char-server 與 map-server 通訊帳密。
- 確認 account_id=1 為 froggos1 / froggop1 / sex=S。
- 驗證 inter、char、map、login 主設定均有載入 import 檔。
- 修改 packets.hpp 的 PACKETVER 為 20260107。
- 一般 conf 修改只需停止後重新啟動伺服器；PACKETVER 變更則須重新編譯。

WARP
- Git 來源：https://github.com/CrazyBebop/WARP0716.git
- 分支：main
- 下載位置：C:\Server\WARP0716
- 若偵測到不同 Git 來源，舊資料夾會先加上日期時間備份，再下載正確來源。

啟動伺服器
- 依序啟動 login-server.exe、char-server.exe、map-server.exe、web-server.exe。
- 啟動前會檢查 Visual C++ 2012 x64 Runtime，缺少時自動安裝。
- 修改設定後請先選 [H] 停止伺服器，再選 [C] 重新啟動。

注意事項
- 不要從不明網站單獨下載 MSVCR110.dll。
- 不要在伺服器執行中覆蓋 conf 或重新編譯。
- MariaDB 修復前的舊 data 備份位於 C:\Server\Backups。
- 執行記錄位於本程式資料夾的 Logs。
