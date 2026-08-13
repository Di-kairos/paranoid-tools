class Panic < Formula
  desc "One-step hide-and-lock kill-switch for macOS"
  homepage "https://github.com/Di-kairos/panic"
  url "https://github.com/Di-kairos/panic/archive/refs/tags/v0.1.15.tar.gz"
  sha256 "c219e3304f36a028d09babc9190a12073bbf2eb720188a605327637cc5125690"
  license "MIT"

  def install
    bin.install "panic"
  end

  test do
    assert_match "panic", shell_output("#{bin}/panic version")
  end
end
