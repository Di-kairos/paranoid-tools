class Panic < Formula
  desc "One-step hide-and-lock kill-switch for macOS"
  homepage "https://github.com/Di-kairos/paranoid-tools"
  url "https://github.com/Di-kairos/paranoid-tools/archive/refs/tags/panic-v0.1.16.tar.gz"
  sha256 "a019bfa75f6e56b165085ddcad94e41f2c7feb8ee77dc2a2b6586e322b2c83c8"
  license "MIT"

  def install
    bin.install "panic/panic"
  end

  test do
    assert_match "panic", shell_output("#{bin}/panic version")
  end
end
