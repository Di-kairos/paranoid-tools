class Panic < Formula
  desc "One-step hide-and-lock kill-switch for macOS"
  homepage "https://github.com/Di-kairos/paranoid-tools"
  url "https://github.com/Di-kairos/paranoid-tools/archive/refs/tags/panic-v0.1.17.tar.gz"
  sha256 "68b9c88b70654d3ce818d68edd067e9b2e7063cc6c48c461a91d28d19dcccd27"
  license "MIT"

  def install
    bin.install "panic/panic"
  end

  test do
    assert_match "panic", shell_output("#{bin}/panic version")
  end
end
