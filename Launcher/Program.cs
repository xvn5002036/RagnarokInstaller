using System;
using System.ComponentModel;
using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.IO.Compression;
using System.Net;
using System.Windows.Forms;

namespace RagnarokInstallerLauncher
{
    internal static class Program
    {
        [STAThread]
        private static void Main()
        {
            ServicePointManager.SecurityProtocol = SecurityProtocolType.Tls12;
            Application.EnableVisualStyles();
            Application.SetCompatibleTextRenderingDefault(false);
            Application.Run(new LauncherForm());
        }
    }

    internal sealed class LauncherForm : Form
    {
        private const string DownloadUrl = "https://github.com/xvn5002036/RagnarokInstaller/archive/refs/heads/main.zip";
        private readonly Label statusLabel;
        private readonly Label detailLabel;
        private readonly ProgressBar progressBar;
        private readonly Button closeButton;
        private readonly BackgroundWorker worker;

        public LauncherForm()
        {
            Text = "Ragnarok Installer";
            ClientSize = new Size(520, 245);
            FormBorderStyle = FormBorderStyle.FixedDialog;
            MaximizeBox = false;
            MinimizeBox = true;
            StartPosition = FormStartPosition.CenterScreen;
            BackColor = Color.FromArgb(10, 16, 27);
            ForeColor = Color.White;
            Font = new Font("Segoe UI", 10F);
            Icon = Icon.ExtractAssociatedIcon(Application.ExecutablePath);

            Label title = new Label();
            title.Text = "Ragnarok Installer";
            title.Font = new Font("Segoe UI", 20F, FontStyle.Bold);
            title.ForeColor = Color.FromArgb(244, 196, 82);
            title.AutoSize = true;
            title.Location = new Point(30, 24);
            Controls.Add(title);

            statusLabel = new Label();
            statusLabel.Text = "準備下載最新版…";
            statusLabel.Font = new Font("Microsoft JhengHei UI", 11F, FontStyle.Bold);
            statusLabel.AutoSize = true;
            statusLabel.Location = new Point(32, 82);
            Controls.Add(statusLabel);

            detailLabel = new Label();
            detailLabel.Text = "請保持網路連線，完成後會自動開啟管理中心。";
            detailLabel.Font = new Font("Microsoft JhengHei UI", 9F);
            detailLabel.ForeColor = Color.FromArgb(161, 177, 198);
            detailLabel.AutoEllipsis = true;
            detailLabel.Location = new Point(32, 113);
            detailLabel.Size = new Size(455, 24);
            Controls.Add(detailLabel);

            progressBar = new ProgressBar();
            progressBar.Location = new Point(34, 149);
            progressBar.Size = new Size(450, 22);
            progressBar.Minimum = 0;
            progressBar.Maximum = 100;
            Controls.Add(progressBar);

            closeButton = new Button();
            closeButton.Text = "取消";
            closeButton.Location = new Point(394, 190);
            closeButton.Size = new Size(90, 32);
            closeButton.FlatStyle = FlatStyle.Flat;
            closeButton.FlatAppearance.BorderColor = Color.FromArgb(61, 78, 103);
            closeButton.Click += delegate { Close(); };
            Controls.Add(closeButton);

            worker = new BackgroundWorker();
            worker.WorkerReportsProgress = true;
            worker.DoWork += DownloadAndInstall;
            worker.ProgressChanged += UpdateProgress;
            worker.RunWorkerCompleted += FinishInstall;

            Shown += delegate { worker.RunWorkerAsync(); };
            FormClosing += PreventClosingDuringInstall;
        }

        private void DownloadAndInstall(object sender, DoWorkEventArgs e)
        {
            string desktopOverride = Environment.GetEnvironmentVariable("RAGNAROK_INSTALLER_TEST_DESKTOP");
            string desktop = String.IsNullOrWhiteSpace(desktopOverride)
                ? Environment.GetFolderPath(Environment.SpecialFolder.DesktopDirectory)
                : desktopOverride;
            string archive = Path.Combine(Path.GetTempPath(), "RagnarokInstaller-" + Guid.NewGuid().ToString("N") + ".zip");
            string installFolder = Path.Combine(desktop, "RagnarokInstaller-main");

            try
            {
                Directory.CreateDirectory(desktop);
                worker.ReportProgress(2, "正在連接 GitHub…");
                DownloadArchive(DownloadUrl, archive);

                worker.ReportProgress(82, "正在準備桌面上的安裝資料夾…");
                if (Directory.Exists(installFolder))
                    Directory.Delete(installFolder, true);

                worker.ReportProgress(88, "正在解壓縮最新版…");
                ZipFile.ExtractToDirectory(archive, desktop);

                string startFile = Path.Combine(installFolder, "Start.cmd");
                if (!File.Exists(startFile))
                    throw new FileNotFoundException("下載完成，但找不到 Start.cmd。", startFile);

                worker.ReportProgress(100, "下載完成，正在啟動管理中心…");
                if (!String.Equals(Environment.GetEnvironmentVariable("RAGNAROK_INSTALLER_TEST_MODE"), "1", StringComparison.Ordinal))
                {
                    ProcessStartInfo startInfo = new ProcessStartInfo(startFile);
                    startInfo.WorkingDirectory = installFolder;
                    startInfo.UseShellExecute = true;
                    Process.Start(startInfo);
                }
                e.Result = installFolder;
            }
            finally
            {
                try { if (File.Exists(archive)) File.Delete(archive); }
                catch { }
            }
        }

        private void DownloadArchive(string url, string destination)
        {
            HttpWebRequest request = (HttpWebRequest)WebRequest.Create(url);
            request.UserAgent = "RagnarokInstaller/6.0";
            request.AllowAutoRedirect = true;
            request.Timeout = 30000;
            request.ReadWriteTimeout = 30000;

            using (WebResponse response = request.GetResponse())
            using (Stream input = response.GetResponseStream())
            using (FileStream output = new FileStream(destination, FileMode.Create, FileAccess.Write, FileShare.None))
            {
                long total = response.ContentLength;
                long received = 0;
                byte[] buffer = new byte[81920];
                int read;
                while ((read = input.Read(buffer, 0, buffer.Length)) > 0)
                {
                    output.Write(buffer, 0, read);
                    received += read;
                    int percent = total > 0 ? 5 + (int)Math.Min(75, received * 75 / total) : 40;
                    worker.ReportProgress(percent, total > 0
                        ? String.Format("正在下載最新版… {0}%", Math.Min(100, received * 100 / total))
                        : "正在下載最新版…");
                }
            }
        }

        private void UpdateProgress(object sender, ProgressChangedEventArgs e)
        {
            progressBar.Value = Math.Max(0, Math.Min(100, e.ProgressPercentage));
            statusLabel.Text = Convert.ToString(e.UserState);
        }

        private void FinishInstall(object sender, RunWorkerCompletedEventArgs e)
        {
            if (e.Error != null)
            {
                statusLabel.Text = "安裝程式執行失敗";
                statusLabel.ForeColor = Color.FromArgb(255, 127, 121);
                detailLabel.Text = e.Error.GetBaseException().Message;
                closeButton.Text = "關閉";
                return;
            }

            statusLabel.Text = "管理中心已啟動";
            detailLabel.Text = "安裝位置：" + Convert.ToString(e.Result);
            closeButton.Text = "完成";
            closeButton.Enabled = true;
            Timer timer = new Timer();
            timer.Interval = 1200;
            timer.Tick += delegate { timer.Stop(); Close(); };
            timer.Start();
        }

        private void PreventClosingDuringInstall(object sender, FormClosingEventArgs e)
        {
            if (worker.IsBusy && e.CloseReason == CloseReason.UserClosing)
            {
                DialogResult result = MessageBox.Show(
                    "下載尚未完成，確定要取消嗎？",
                    "Ragnarok Installer",
                    MessageBoxButtons.YesNo,
                    MessageBoxIcon.Question);
                if (result == DialogResult.No)
                    e.Cancel = true;
            }
        }
    }
}
