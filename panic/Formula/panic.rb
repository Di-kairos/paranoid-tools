class Panic < Formula
  desc "One-step hide-and-lock kill-switch for macOS"
  homepage "https://github.com/Di-kairos/paranoid-tools"
  url "https://github.com/Di-kairos/paranoid-tools/archive/refs/tags/panic-v0.1.19.tar.gz"
  sha256 "cd81fd13ccb664994f4a29bc3bb989d8884e5e7060d62dbc63a91b5d041d067a"
  license "MIT"

  def install
    bin.install "panic/panic"
  end

  test do
    assert_match "panic", shell_output("#{bin}/panic version")
  end
end
