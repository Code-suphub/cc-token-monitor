class CcTokenMonitor < Formula
  desc "Monitor Claude Code token usage and costs"
  homepage "https://github.com/Code-suphub/cc-token-monitor"
  url "https://github.com/Code-suphub/cc-token-monitor/archive/refs/tags/v1.0.0.tar.gz"
  sha256 "c2d5d41de7f8011ba3de53a6328db38e857a3d788ce7bed417fa260f4ef52ffe"
  license "MIT"

  depends_on "jq"
  depends_on "python@3" => :optional

  def install
    bin.install "bin/cc-token-monitor"
    bin.install "bin/cc-token-web" if File.exist?("bin/cc-token-web")
    bin.install "bin/cc-token-web-stop" if File.exist?("bin/cc-token-web-stop")

    (pkgshare/"config").install "config/prices.json"

    # Install web app if python is available
    if build.with?("python@3")
      (pkgshare/"web").install Dir["web/*"]
    end
  end

  def post_install
    # Create config directory
    (HOMEBREW_PREFIX/".claude/token-stats/config").mkpath

    # Link default config if not exists
    config_file = HOMEBREW_PREFIX/".claude/token-stats/config/prices.json"
    unless config_file.exist?
      cp pkgshare/"config/prices.json", config_file
    end
  end

  def caveats
    <<~EOS
      CC Token Monitor has been installed!

      Quick start:
        cc-token-monitor once     # Initialize
        cc-token-monitor today    # View today's stats
        cc-token-monitor help     # Show all commands

      Add aliases to your shell:
        echo 'alias cctok="cc-token-monitor"' >> ~/.zshrc
        echo 'alias cctoday="cc-token-monitor today"' >> ~/.zshrc

      Configuration:
        Edit ~/.claude/token-stats/config/prices.json to customize prices

      For more information:
        https://github.com/Code-suphub/cc-token-monitor#readme
    EOS
  end

  test do
    system "#{bin}/cc-token-monitor", "help"
  end
end
